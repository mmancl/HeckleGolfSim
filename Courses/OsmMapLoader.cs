using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;
using Godot;

namespace HeckleLinks.Courses;

[GlobalClass]
public partial class OsmMapLoader : Node
{
    private static readonly string LogPrefix = "[OsmMapLoader]";
    private static readonly string OverpassUrl = "https://overpass-api.de/api/interpreter";
    private static readonly string[] OverpassEndpoints = new[]
    {
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter"
    };
    private static readonly System.Net.Http.HttpClient HttpClient = CreateHttpClient();

    private static System.Net.Http.HttpClient CreateHttpClient()
    {
        var client = new System.Net.Http.HttpClient();
        client.Timeout = TimeSpan.FromSeconds(120);
        client.DefaultRequestHeaders.Add("User-Agent", "HeckleLinks/1.0 (contact: github.com/mmancl/HeckleGolfSim)");
        return client;
    }

    [Signal]
    public delegate void SearchCompletedEventHandler(Godot.Collections.Array results);

    [Signal]
    public delegate void CourseGeneratedEventHandler(bool success);

    [Signal]
    public delegate void DownloadProgressEventHandler(string statusMessage);

    private string _generationMessage = "";
    private ElevationMap? _currentElevationMap;
    private double _refLat;
    private double _refLon;
    private double _metersPerLat = 111320.0;
    private double _metersPerLon = 111320.0;

    public string GetGenerationMessage()
    {
        return _generationMessage;
    }

    public async void DownloadAndGenerateCourse(double lat, double lon, string courseName)
    {
        _generationMessage = "";
        string safeName = string.Concat(courseName.Split(Path.GetInvalidFileNameChars())).Replace(" ", "_");
        string courseDir = $"user://courses/{safeName}";
        string globalCourseDir = ProjectSettings.GlobalizePath(courseDir);

        if (!Directory.Exists(globalCourseDir))
        {
            Directory.CreateDirectory(globalCourseDir);
        }

        string tscnPath = $"{courseDir}/course.tscn";
        string jsonPath = $"{courseDir}/course.json";
        string globalTscnPath = ProjectSettings.GlobalizePath(tscnPath);
        string globalJsonPath = ProjectSettings.GlobalizePath(jsonPath);

        EmitSignal(SignalName.DownloadProgress, $"Connecting to OpenStreetMap for '{courseName}'...");
        string osmJson = await DownloadOsmDataAsync(lat, lon, courseName);
        if (string.IsNullOrEmpty(osmJson))
        {
            try
            {
                if (Directory.Exists(globalCourseDir) && !Directory.EnumerateFileSystemEntries(globalCourseDir).Any())
                {
                    Directory.Delete(globalCourseDir);
                }
            }
            catch (Exception ex)
            {
                GD.PrintErr($"{LogPrefix} Failed to delete empty course folder: {ex.Message}");
            }
            if (string.IsNullOrEmpty(_generationMessage))
            {
                _generationMessage = "Error: Course download timed out or failed. Please retry the download, and if it continues to fail, please log a bug.";
            }
            EmitSignal(SignalName.CourseGenerated, false);
            return;
        }

        byte[]? satImageBytes = null;
        var bbox = CalculateBBoxFromOsmJson(osmJson, lat, lon);
        if (bbox != null)
        {
            EmitSignal(SignalName.DownloadProgress, "Downloading satellite imagery...");
            satImageBytes = await DownloadSatelliteImageAsync(bbox.LonMin, bbox.LatMin, bbox.LonMax, bbox.LatMax, 2048, 2048);
            
            EmitSignal(SignalName.DownloadProgress, "Downloading terrain elevation data...");
            await DownloadElevationDataAsync(bbox, globalCourseDir);
        }
        else
        {
            GD.Print($"{LogPrefix} Warning: Could not calculate course bounding box for satellite tree detection.");
        }

        CallDeferred(MethodName.GenerateCourseDeferred, osmJson, courseName, lat, lon, satImageBytes ?? Array.Empty<byte>());
    }

    public async void GenerateCourseDeferred(string jsonString, string courseName, double lat, double lon, byte[]? satImageBytes)
    {
        bool success = await GenerateCourseFromDataAsync(jsonString, courseName, lat, lon, satImageBytes);
        EmitSignal(SignalName.CourseGenerated, success);
    }

    private async Task<string> DownloadOsmDataAsync(double lat, double lon, string courseName)
    {
        GD.Print($"{LogPrefix} Downloading OSM data for course '{courseName}' around {lat}, {lon}...");
        // Reduced radius to 1000 to prevent Gateway Timeout (504) on Overpass API, increased query timeout to 90s, and removed natural=tree since we scan satellite imagery
        string query = $@"
        [out:json][timeout:90];
        (
          nwr(around:1000, {lat}, {lon})[""leisure""=""golf_course""];
          nwr(around:1000, {lat}, {lon})[""golf""];
          nwr(around:1000, {lat}, {lon})[""natural""=""water""];
          nwr(around:1000, {lat}, {lon})[""natural""=""wood""];
          nwr(around:1000, {lat}, {lon})[""landuse""=""forest""];
        );
        out body;
        >;
        out skel qt;
        ";

        int maxAttempts = 3;
        for (int attempt = 1; attempt <= maxAttempts; attempt++)
        {
            string endpoint = OverpassEndpoints[(attempt - 1) % OverpassEndpoints.Length];
            GD.Print($"{LogPrefix} Overpass query attempt {attempt}/{maxAttempts} using endpoint: {endpoint}");

            try
            {
                var content = new FormUrlEncodedContent(new[] { new KeyValuePair<string, string>("data", query) });
                var response = await HttpClient.PostAsync(endpoint, content);

                if (response.IsSuccessStatusCode)
                {
                    string result = await response.Content.ReadAsStringAsync();
                    if (!string.IsNullOrWhiteSpace(result))
                    {
                        return result;
                    }
                }

                GD.PrintErr($"{LogPrefix} Attempt {attempt} failed with HTTP status {response.StatusCode} from {endpoint}");
            }
            catch (Exception ex)
            {
                GD.PrintErr($"{LogPrefix} Attempt {attempt} exception querying {endpoint}: {ex.Message}");
            }

            if (attempt < maxAttempts)
            {
                _generationMessage = $"Overpass server busy, retrying query (attempt {attempt + 1}/{maxAttempts})...";
                EmitSignal(SignalName.DownloadProgress, _generationMessage);
                await Task.Delay(2000);
            }
        }

        _generationMessage = "Error: Overpass API request timed out after multiple retries. Please retry the download, and if it continues to fail, please log a bug.";
        return "";
    }

    private async Task<bool> GenerateCourseFromDataAsync(string jsonString, string courseName, double lat, double lon, byte[]? satImageBytes)
    {
        _generationMessage = "";
        EmitSignal(SignalName.DownloadProgress, "Parsing course layout and golf features...");
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

        string safeName = string.Concat(courseName.Split(Path.GetInvalidFileNameChars())).Replace(" ", "_");
        string courseDir = $"user://courses/{safeName}";
        string tscnPath = $"{courseDir}/course.tscn";
        string jsonPath = $"{courseDir}/course.json";
        string globalJsonPath = ProjectSettings.GlobalizePath(jsonPath);
        string globalCourseDir = Path.GetDirectoryName(globalJsonPath) ?? "";

        Image? satImage = null;
        if (satImageBytes != null && satImageBytes.Length > 0)
        {
            try
            {
                if (!Directory.Exists(globalCourseDir))
                {
                    Directory.CreateDirectory(globalCourseDir);
                }
                string satPath = Path.Combine(globalCourseDir, "satellite.png");
                File.WriteAllBytes(satPath, satImageBytes);
                GD.Print($"{LogPrefix} Saved satellite image to: {satPath}");
            }
            catch (Exception ex)
            {
                GD.PrintErr($"{LogPrefix} Failed to save satellite.png: {ex}");
            }

            satImage = new Image();
            var err = satImage.LoadPngFromBuffer(satImageBytes);
            if (err != Error.Ok)
            {
                GD.PrintErr($"{LogPrefix} Failed to parse satellite PNG image: {err}");
                satImage = null;
            }
            else
            {
                GD.Print($"{LogPrefix} Successfully loaded satellite image for tree detection ({satImage.GetWidth()}x{satImage.GetHeight()}).");
            }
        }

        try
        {
            using var doc = JsonDocument.Parse(jsonString);
            if (!doc.RootElement.TryGetProperty("elements", out var elements))
            {
                GD.PrintErr($"{LogPrefix} Invalid JSON elements received from Overpass API.");
                _generationMessage = "Error: Received invalid course data from OpenStreetMap. Please retry the download, and if it continues to fail, please log a bug.";
                return false;
            }

            GD.Print($"{LogPrefix} Parsing OSM elements...");
            var nodes = new Dictionary<long, (double Lat, double Lon)>();
            var nodeTags = new Dictionary<long, Dictionary<string, string>>();
            var ways = new List<OsmWay>();
            var relations = new List<OsmRelation>();
            
            foreach (var element in elements.EnumerateArray())
            {
                string type = element.GetProperty("type").GetString() ?? "";
                long id = element.GetProperty("id").GetInt64();
                
                if (type == "node")
                {
                    double nLat = element.GetProperty("lat").GetDouble();
                    double nLon = element.GetProperty("lon").GetDouble();
                    nodes[id] = (nLat, nLon);

                    var tags = new Dictionary<string, string>();
                    if (element.TryGetProperty("tags", out var tagsProp))
                    {
                        foreach (var tag in tagsProp.EnumerateObject())
                        {
                            tags[tag.Name] = tag.Value.GetString() ?? "";
                        }
                    }
                    nodeTags[id] = tags;
                }
                else if (type == "way")
                {
                    var wayNodes = new List<long>();
                    if (element.TryGetProperty("nodes", out var nodesProp))
                    {
                        foreach (var nodeVal in nodesProp.EnumerateArray())
                        {
                            wayNodes.Add(nodeVal.GetInt64());
                        }
                    }

                    var tags = new Dictionary<string, string>();
                    if (element.TryGetProperty("tags", out var tagsProp))
                    {
                        foreach (var tag in tagsProp.EnumerateObject())
                        {
                            tags[tag.Name] = tag.Value.GetString() ?? "";
                        }
                    }

                    ways.Add(new OsmWay(id, wayNodes, tags));
                }
                else if (type == "relation")
                {
                    var members = new List<(string Type, long Ref, string Role)>();
                    if (element.TryGetProperty("members", out var membersProp))
                    {
                        foreach (var mVal in membersProp.EnumerateArray())
                        {
                            string mType = mVal.GetProperty("type").GetString() ?? "";
                            long mRef = mVal.GetProperty("ref").GetInt64();
                            string mRole = mVal.GetProperty("role").GetString() ?? "";
                            members.Add((mType, mRef, mRole));
                        }
                    }

                    var tags = new Dictionary<string, string>();
                    if (element.TryGetProperty("tags", out var tagsProp))
                    {
                        foreach (var tag in tagsProp.EnumerateObject())
                        {
                            tags[tag.Name] = tag.Value.GetString() ?? "";
                        }
                    }

                    relations.Add(new OsmRelation(id, members, tags));
                }
            }

            if (nodes.Count == 0)
            {
                GD.PrintErr($"{LogPrefix} No nodes found in the query region.");
                _generationMessage = "Error: No course data found for this location in OpenStreetMap. Please retry the download, and if it continues to fail, please log a bug.";
                return false;
            }

            // Reference origin is center of all nodes
            double refLat = nodes.Values.Average(n => n.Lat);
            double refLon = nodes.Values.Average(n => n.Lon);
            double metersPerLat = 111320.0;
            double metersPerLon = 111320.0 * Math.Cos(refLat * Math.PI / 180.0);

            _refLat = refLat;
            _refLon = refLon;
            _metersPerLat = metersPerLat;
            _metersPerLon = metersPerLon;

            // Load elevation data
            string elevationPath = Path.Combine(globalCourseDir, "elevation.dat");
            LoadElevationMap(elevationPath, refLat, refLon, metersPerLat, metersPerLon);

            // Copy tags from relations to member ways and nodes
            foreach (var rel in relations)
            {
                var relTagsToCopy = new Dictionary<string, string>();
                foreach (var tag in rel.Tags)
                {
                    if (tag.Key == "golf" || tag.Key == "natural" || tag.Key == "landuse" || tag.Key == "leisure" || tag.Key == "ref" || tag.Key == "par" || tag.Key == "handicap" || tag.Key == "name")
                    {
                        relTagsToCopy[tag.Key] = tag.Value;
                    }
                }
                
                if (relTagsToCopy.Count > 0)
                {
                    foreach (var member in rel.Members)
                    {
                        if (member.Type == "way")
                        {
                            var targetWay = ways.FirstOrDefault(w => w.Id == member.Ref);
                            if (targetWay != null)
                            {
                                foreach (var kvp in relTagsToCopy)
                                {
                                    // Don't overwrite the 'golf' tag if the way already has one.
                                    // Relations with golf=hole contain members like fairways, greens,
                                    // bunkers — overwriting their golf tag breaks feature classification.
                                    if (kvp.Key == "golf" && targetWay.Tags.ContainsKey("golf"))
                                        continue;
                                    targetWay.Tags[kvp.Key] = kvp.Value;
                                }
                            }
                        }
                        else if (member.Type == "node")
                        {
                            if (nodeTags.TryGetValue(member.Ref, out var targetNodeTags))
                            {
                                foreach (var kvp in relTagsToCopy)
                                {
                                    if (kvp.Key == "golf" && targetNodeTags.ContainsKey("golf"))
                                        continue;
                                    targetNodeTags[kvp.Key] = kvp.Value;
                                }
                            }
                        }
                    }
                }
            }

            // Find the main course boundary to filter out other golf courses in the radius
            double closestDist = double.MaxValue;
            OsmWay closestWay = null;
            OsmRelation closestRel = null;

            foreach (var way in ways)
            {
                if (way.Tags.TryGetValue("leisure", out var leisure) && leisure == "golf_course")
                {
                    var wayNodes = way.NodeIds.Where(nodes.ContainsKey).Select(id => nodes[id]).ToList();
                    if (wayNodes.Count > 0)
                    {
                        double avgLat = wayNodes.Average(n => n.Lat);
                        double avgLon = wayNodes.Average(n => n.Lon);
                        double dLat = avgLat - lat;
                        double dLon = avgLon - lon;
                        double dist = dLat * dLat + dLon * dLon;
                        if (dist < closestDist)
                        {
                            closestDist = dist;
                            closestWay = way;
                            closestRel = null;
                        }
                    }
                }
            }

            foreach (var rel in relations)
            {
                if (rel.Tags.TryGetValue("leisure", out var leisure) && leisure == "golf_course")
                {
                    var memberWays = rel.Members
                        .Where(m => m.Type == "way")
                        .Select(m => ways.FirstOrDefault(w => w.Id == m.Ref))
                        .Where(w => w != null)
                        .ToList();

                    var allNodeCoords = memberWays
                        .SelectMany(w => w.NodeIds)
                        .Where(nodes.ContainsKey)
                        .Select(id => nodes[id])
                        .ToList();

                    if (allNodeCoords.Count > 0)
                    {
                        double avgLat = allNodeCoords.Average(n => n.Lat);
                        double avgLon = allNodeCoords.Average(n => n.Lon);
                        double dLat = avgLat - lat;
                        double dLon = avgLon - lon;
                        double dist = dLat * dLat + dLon * dLon;
                        if (dist < closestDist)
                        {
                            closestDist = dist;
                            closestRel = rel;
                            closestWay = null;
                        }
                    }
                }
            }

            string targetCourseName = "";
            if (closestRel != null && closestRel.Tags.TryGetValue("name", out var relName))
            {
                targetCourseName = relName;
            }
            else if (closestWay != null && closestWay.Tags.TryGetValue("name", out var wayName))
            {
                targetCourseName = wayName;
            }

            // Gather all boundary polygons for golf courses with the same name, or just the closest one if nameless
            var coursePolygons = new List<Vector2[]>();
            
            var matchingWays = ways.Where(w => 
                w.Tags.TryGetValue("leisure", out var l) && l == "golf_course" &&
                (string.IsNullOrEmpty(targetCourseName) ? w == closestWay : (w.Tags.TryGetValue("name", out var n) && n == targetCourseName))
            ).ToList();

            foreach (var w in matchingWays)
            {
                var pts = w.NodeIds
                    .Where(nodes.ContainsKey)
                    .Select(id => nodes[id])
                    .Select(coord => new Vector2(
                        (float)((coord.Lon - refLon) * metersPerLon),
                        -(float)((coord.Lat - refLat) * metersPerLat)
                    ))
                    .ToArray();
                if (pts.Length >= 3)
                {
                    coursePolygons.Add(pts);
                }
            }

            var matchingRels = relations.Where(r => 
                r.Tags.TryGetValue("leisure", out var l) && l == "golf_course" &&
                (string.IsNullOrEmpty(targetCourseName) ? r == closestRel : (r.Tags.TryGetValue("name", out var n) && n == targetCourseName))
            ).ToList();

            foreach (var r in matchingRels)
            {
                var assembled = AssembleRelationPolygons(r, ways, nodes, refLat, refLon, metersPerLat, metersPerLon);
                coursePolygons.AddRange(assembled);
            }

            if (closestWay != null || closestRel != null)
            {
                GD.Print($"{LogPrefix} Identified main golf course boundary: '{targetCourseName}' with {coursePolygons.Count} polygon parts.");
            }
            else
            {
                GD.Print($"{LogPrefix} Warning: No leisure=golf_course boundary found near search coordinates. Allowing all elements.");
            }

            var exclusionPolygons = new List<ExclusionPolygon>();
            var holeInfo = new Dictionary<string, HoleConfig>();
            var tees = new List<TeeConfig>();
            var lineOfPlayPaths = new List<List<Vector2>>();

            Func<Vector2, bool> isPointInMainCourse = (pt) => {
                if (coursePolygons.Count == 0) return true;
                foreach (var poly in coursePolygons)
                {
                    if (PointInPolygon(pt, poly))
                        return true;
                    foreach (var vertex in poly)
                    {
                        if (pt.DistanceTo(vertex) < 60f)
                            return true;
                    }
                }
                for (int pIdx = 0; pIdx < lineOfPlayPaths.Count; pIdx++)
                {
                    var path = lineOfPlayPaths[pIdx];
                    for (int i = 0; i < path.Count - 1; i++)
                    {
                        if (DistanceToSegment(pt, path[i], path[i + 1]) < 90.0f)
                            return true;
                    }
                }
                for (int i = 0; i < exclusionPolygons.Count; i++)
                {
                    var excl = exclusionPolygons[i];
                    if (pt.X >= excl.MinX - 50f && pt.X <= excl.MaxX + 50f && pt.Y >= excl.MinY - 50f && pt.Y <= excl.MaxY + 50f)
                    {
                        if (PointInPolygon(pt, excl.Polygon)) return true;
                    }
                }
                return false;
            };

            // Build individual tree nodes list from nodeTags
            var treeNodeIds = new List<long>();
            foreach (var kvp in nodeTags)
            {
                if (kvp.Value.TryGetValue("natural", out var nat) && nat == "tree")
                {
                    if (nodes.TryGetValue(kvp.Key, out var coord))
                    {
                        float tx = (float)((coord.Lon - refLon) * metersPerLon);
                        float tz = -(float)((coord.Lat - refLat) * metersPerLat);
                        if (isPointInMainCourse(new Vector2(tx, tz)))
                        {
                            treeNodeIds.Add(kvp.Key);
                        }
                    }
                }
            }

            GD.Print($"{LogPrefix} Generating 3D scene...");
            var rootNode = new Node3D { Name = safeName };

            int parsedFairwaysCount = 0;
            int parsedGreensCount = 0;
            var waterPolygons = new List<Vector2[]>();
            var forestPolygons = new List<Vector2[]>();
            var holesWithTeePolygons = new HashSet<string>();

            foreach (var way in ways)
            {
                var points = way.NodeIds
                    .Where(nodes.ContainsKey)
                    .Select(id => nodes[id])
                    .Select(coord => new Vector2(
                        (float)((coord.Lon - refLon) * metersPerLon),
                        -(float)((coord.Lat - refLat) * metersPerLat) // -Z is forward/north
                    ))
                    .ToList();

                if (points.Count < 2) continue;

                // Check if the way belongs to the main course
                var wayCenter = new Vector2(points.Average(p => p.X), points.Average(p => p.Y));
                if (!isPointInMainCourse(wayCenter))
                {
                    // Do not skip the main golf course boundary ways/relations themselves
                    bool isMainBoundary = way.Tags.TryGetValue("leisure", out var l) && l == "golf_course";
                    if (!isMainBoundary)
                        continue;
                }

                // Determine golf type early so line features (hole, tee) are handled before polygon guard
                way.Tags.TryGetValue("golf", out string? golfType);

                // Handle golf=hole as a LINE of play (tee → green), not a polygon
                if (golfType == "hole")
                {
                    lineOfPlayPaths.Add(new List<Vector2>(points));
                    string holeNum = way.Tags.GetValueOrDefault("ref", "1");
                    string hName = way.Tags.GetValueOrDefault("name", $"Hole {holeNum}");
                    int par = int.TryParse(way.Tags.GetValueOrDefault("par", "4"), out var p) ? p : 4;
                    int handicap = int.TryParse(way.Tags.GetValueOrDefault("handicap", "1"), out var h) ? h : 1;

                    // First node = tee area, last node = green/pin
                    var teePos = points.First();
                    var pinPos = points.Last();

                    // Calculate distance along the line of play, convert meters → yards
                    float totalDistanceMeters = 0f;
                    var pathList = new List<float[]>();
                    for (int i = 0; i < points.Count; i++)
                    {
                        pathList.Add(new float[] { points[i].X, points[i].Y });
                        if (i > 0)
                        {
                            totalDistanceMeters += points[i - 1].DistanceTo(points[i]);
                        }
                    }
                    float distanceYards = totalDistanceMeters * 1.09361f;

                    GD.Print($"{LogPrefix} Parsed hole {holeNum}: par {par}, {distanceYards:F0} yards, tee ({teePos.X:F1}, {teePos.Y:F1}) → pin ({pinPos.X:F1}, {pinPos.Y:F1})");

                    // Pre-populate tee boxes from the hole line's first node.
                    // These defaults are overridden if explicit golf=tee data exists.
                    holeInfo[GetHoleKey(holeNum)] = new HoleConfig
                    {
                        Par = par,
                        Handicap = handicap,
                        Name = hName,
                        Distance = distanceYards,
                        HoleLocation = new float[] { pinPos.X, pinPos.Y },
                        TeeBoxes = new Dictionary<string, float[]>
                        {
                            { "Blue", new float[] { teePos.X, teePos.Y } },
                            { "White", new float[] { teePos.X, teePos.Y } },
                            { "Red", new float[] { teePos.X, teePos.Y } }
                        },
                        HolePath = pathList
                    };
                    continue;
                }

                // Handle golf=tee (can be polygon or small way)
                if (golfType == "tee")
                {
                    string? refHole = null;
                    if (way.Tags.TryGetValue("ref", out refHole) && !string.IsNullOrEmpty(refHole))
                    {
                        string teeColor = way.Tags.GetValueOrDefault("tee", "blue").ToLower();
                        var center = new Vector2(points.Average(pt => pt.X), points.Average(pt => pt.Y));

                        tees.Add(new TeeConfig
                        {
                            HoleNum = refHole,
                            Color = teeColor,
                            Location = new float[] { center.X, center.Y }
                        });
                    }

                    // Also render the tee box visually if it has polygon geometry
                    if (points.Count >= 3)
                    {
                        if (!string.IsNullOrEmpty(refHole))
                        {
                            holesWithTeePolygons.Add(GetHoleKey(refHole));
                        }
                        if (points.First() != points.Last())
                            points.Add(points.First());
                        var uniquePoints = points.Take(points.Count - 1).ToArray();
                        exclusionPolygons.Add(new ExclusionPolygon(uniquePoints, "tee", this));
                        // We no longer create a separate visual mesh for the tee boxes.
                        // They are rendered solely on the unified terrain, which prevents Z-fighting and UV scaling mismatch.
                        
                        // Create collision shape for explicit tee box polygon
                        var staticBody = new StaticBody3D { Name = $"tee_Static_explicit_{way.Id}" };
                        staticBody.SetMeta("surface_type", 0); // Fairway physics for tees
                        CreateCollisionForPolygon(staticBody, uniquePoints, rootNode, exclusionPolygons);
                    }
                    continue;
                }

                // All remaining features require polygon geometry (3+ points)
                if (points.Count < 3) continue;

                // Close polygon if not closed
                if (points.First() != points.Last())
                {
                    points.Add(points.First());
                }

                // Check tags for surface features
                bool isGolfSurface = golfType == "fairway" || golfType == "green" || golfType == "bunker";
                                     
                bool isWaterFeature = (way.Tags.TryGetValue("natural", out string? natType) && natType == "water") ||
                                      golfType == "water_hazard" ||
                                      way.Tags.ContainsKey("water");
                                      
                bool isForestFeature = (way.Tags.TryGetValue("natural", out string? natWood) && natWood == "wood") ||
                                       (way.Tags.TryGetValue("landuse", out string? landuseForest) && landuseForest == "forest");

                if (isGolfSurface)
                {
                    if (golfType == "fairway") parsedFairwaysCount++;
                    if (golfType == "green") parsedGreensCount++;

                    var uniquePoints = points.Take(points.Count - 1).ToArray();
                    exclusionPolygons.Add(new ExclusionPolygon(uniquePoints, golfType, this));

                    int surfaceTypeValue = golfType switch
                    {
                        "green" => 4,
                        "fairway" => 0,
                        _ => 2
                    };

                    var staticBody = new StaticBody3D { Name = $"{golfType}_Static_{way.Id}" };
                    staticBody.SetMeta("surface_type", surfaceTypeValue);
                    if (golfType == "bunker")
                    {
                        staticBody.SetMeta("is_sand", true);
                    }
                    CreateCollisionForPolygon(staticBody, uniquePoints, rootNode, exclusionPolygons);
                }
                else if (isWaterFeature)
                {
                    var uniquePoints = points.Take(points.Count - 1).ToArray();
                    waterPolygons.Add(uniquePoints);
                    exclusionPolygons.Add(new ExclusionPolygon(uniquePoints, "water", this));
                    var indices = Geometry2D.TriangulatePolygon(uniquePoints);
                    if (indices.Length > 0)
                    {
                        float heightOffset = 0.01f; // Just above rough base
                        Color color = new Color(0.12f, 0.36f, 0.72f); // Deep blue pond

                        var mesh = Create3DPolygonMesh(uniquePoints, indices, heightOffset, color, "water", exclusionPolygons);
                        var meshInstance = new MeshInstance3D
                        {
                            Name = $"water_{way.Id}",
                            Mesh = mesh
                        };
                        rootNode.AddChild(meshInstance);
                        meshInstance.Owner = rootNode;

                        // Add static body for water zone (treat as Rough)
                        var staticBody = new StaticBody3D { Name = $"water_Static_{way.Id}" };
                        staticBody.SetMeta("surface_type", 2); // SurfaceType.Rough
                        staticBody.SetMeta("is_water", true);
                        staticBody.SetMeta("water_points", uniquePoints);

                        var colShape = new CollisionShape3D();
                        var concaveShape = new ConcavePolygonShape3D();
                        concaveShape.Data = mesh.GetFaces();
                        colShape.Shape = concaveShape;

                        staticBody.AddChild(colShape);
                        rootNode.AddChild(staticBody);
                        staticBody.Owner = rootNode;
                        colShape.Owner = rootNode;
                    }
                }
                else if (isForestFeature)
                {
                    var uniquePoints = points.Take(points.Count - 1).ToArray();
                    if (uniquePoints.Length >= 3)
                    {
                        forestPolygons.Add(uniquePoints);
                    }
                }

            }

            // Find the bounding box of the entire course using all features
            float courseMinX = float.MaxValue;
            float courseMaxX = float.MinValue;
            float courseMinZ = float.MaxValue;
            float courseMaxZ = float.MinValue;
            bool hasValidPoints = false;

            foreach (var excl in exclusionPolygons)
            {
                foreach (var pt in excl.Polygon)
                {
                    if (pt.X < courseMinX) courseMinX = pt.X;
                    if (pt.X > courseMaxX) courseMaxX = pt.X;
                    if (pt.Y < courseMinZ) courseMinZ = pt.Y;
                    if (pt.Y > courseMaxZ) courseMaxZ = pt.Y;
                    hasValidPoints = true;
                }
            }

            foreach (var path in lineOfPlayPaths)
            {
                foreach (var pt in path)
                {
                    if (pt.X < courseMinX) courseMinX = pt.X;
                    if (pt.X > courseMaxX) courseMaxX = pt.X;
                    if (pt.Y < courseMinZ) courseMinZ = pt.Y;
                    if (pt.Y > courseMaxZ) courseMaxZ = pt.Y;
                    hasValidPoints = true;
                }
            }

            foreach (var poly in coursePolygons)
            {
                foreach (var pt in poly)
                {
                    if (pt.X < courseMinX) courseMinX = pt.X;
                    if (pt.X > courseMaxX) courseMaxX = pt.X;
                    if (pt.Y < courseMinZ) courseMinZ = pt.Y;
                    if (pt.Y > courseMaxZ) courseMaxZ = pt.Y;
                    hasValidPoints = true;
                }
            }

            foreach (var poly in forestPolygons)
            {
                foreach (var pt in poly)
                {
                    if (pt.X < courseMinX) courseMinX = pt.X;
                    if (pt.X > courseMaxX) courseMaxX = pt.X;
                    if (pt.Y < courseMinZ) courseMinZ = pt.Y;
                    if (pt.Y > courseMaxZ) courseMaxZ = pt.Y;
                    hasValidPoints = true;
                }
            }

            if (!hasValidPoints)
            {
                courseMinX = -1500f;
                courseMaxX = 1500f;
                courseMinZ = -1500f;
                courseMaxZ = 1500f;
            }
            else
            {
                courseMinX -= 300f;
                courseMaxX += 300f;
                courseMinZ -= 300f;
                courseMaxZ += 300f;
            }

            float courseWidth = courseMaxX - courseMinX;
            float courseDepth = courseMaxZ - courseMinZ;

            // 1. Adjust straight-line or dogleg hole paths to follow the fairway doglegs if needed
            var fairwayPolys = exclusionPolygons.Where(e => e.GolfType == "fairway").ToList();
            if (fairwayPolys.Count > 0)
            {
                foreach (var kp in holeInfo)
                {
                    var hole = kp.Value;
                    if (hole.HolePath == null || hole.HolePath.Count < 2) continue;

                    // Par 3 holes are straight from tee to green and do not need dogleg bending
                    if (hole.Par == 3) continue;

                    var originalPath = new List<Vector2>();
                    foreach (var pt in hole.HolePath)
                    {
                        originalPath.Add(new Vector2(pt[0], pt[1]));
                    }

                    // Resample to 5 points for a clean straight-line path
                    var newPoints = ResamplePath(originalPath, 5);

                    for (int i = 1; i < newPoints.Count - 1; i++)
                    {
                        Vector2 pt = newPoints[i];
                        float t = (float)i / (newPoints.Count - 1);

                        // Don't pull tee-off and green approach too aggressively if they are close to the ends
                        if (t > 0.10f && t < 0.90f)
                        {
                            bool insideFairway = false;
                            foreach (var fw in fairwayPolys)
                            {
                                if (Geometry2D.IsPointInPolygon(pt, fw.Polygon))
                                {
                                    insideFairway = true;
                                    break;
                                }
                            }

                            if (!insideFairway)
                            {
                                // Calculate local path direction to move strictly perpendicularly
                                Vector2 dir = (newPoints[i + 1] - newPoints[i - 1]).Normalized();
                                Vector2 normal = new Vector2(-dir.Y, dir.X);

                                float bestOffset = 0f;
                                bool found = false;
                                float minOffsetAbs = float.MaxValue;

                                // Search for the closest offset along the normal that lands inside a fairway (capped at 40m)
                                for (float offset = -40f; offset <= 40f; offset += 2f)
                                {
                                    Vector2 testPt = pt + normal * offset;
                                    foreach (var fw in fairwayPolys)
                                    {
                                        if (Geometry2D.IsPointInPolygon(testPt, fw.Polygon))
                                        {
                                            float absOffset = Math.Abs(offset);
                                            if (absOffset < minOffsetAbs)
                                            {
                                                minOffsetAbs = absOffset;
                                                bestOffset = offset;
                                                found = true;
                                            }
                                            break;
                                        }
                                    }
                                }

                                if (found)
                                {
                                    float pushSign = bestOffset >= 0 ? 1f : -1f;
                                    pt = pt + normal * (bestOffset + pushSign * 5.0f); // Push 5 meters inside
                                }
                            }
                        }
                        newPoints[i] = pt;
                    }

                    hole.HolePath.Clear();
                    foreach (var p in newPoints)
                    {
                        hole.HolePath.Add(new float[] { p.X, p.Y });
                    }
                }
            }

            // 2. Re-populate lineOfPlayPaths from the updated holeInfo
            lineOfPlayPaths.Clear();
            foreach (var kp in holeInfo)
            {
                var pList = new List<Vector2>();
                foreach (var pt in kp.Value.HolePath)
                {
                    pList.Add(new Vector2(pt[0], pt[1]));
                }
                if (pList.Count >= 2)
                {
                    lineOfPlayPaths.Add(pList);
                }
            }

            // Gather tree positions from OSM trees
            var placedTreePositions = new List<Vector2>();
            foreach (var tId in treeNodeIds)
            {
                if (nodes.TryGetValue(tId, out var coord))
                {
                    float tx = (float)((coord.Lon - refLon) * metersPerLon);
                    float tz = -(float)((coord.Lat - refLat) * metersPerLat);
                    placedTreePositions.Add(new Vector2(tx, tz));
                }
            }

            // Scan satellite imagery for additional trees
            if (satImage != null)
            {
                EmitSignal(SignalName.DownloadProgress, "Scanning foliage from satellite imagery...");
                await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

                GD.Print($"{LogPrefix} Scanning satellite imagery for tree positions...");
                int satWidth = satImage.GetWidth();
                int satHeight = satImage.GetHeight();
                var candidatePoints = new List<Vector2>();
                float spacing = 6.5f; // Grid spacing in meters (increased from 3.5f)
                float minDistanceBetweenTrees = 8.5f; // Minimum distance to keep trees apart (increased from 3.0f)

                var gridPoints = new List<Vector2>();
                for (float rx = courseMinX; rx <= courseMaxX; rx += spacing)
                {
                    for (float rz = courseMinZ; rz <= courseMaxZ; rz += spacing)
                    {
                        var pt = new Vector2(rx, rz);
                        if (isPointInMainCourse(pt))
                        {
                            gridPoints.Add(pt);
                        }
                    }
                }

                await Task.Run(() =>
                {
                    var localCandidates = new System.Collections.Concurrent.ConcurrentBag<Vector2>();

                    Parallel.ForEach(gridPoints, pt =>
                    {
                        float rx = pt.X;
                        float rz = pt.Y;

                        // Check play surface exclusions
                        bool insideExclusion = false;
                        for (int i = 0; i < exclusionPolygons.Count; i++)
                        {
                            var excl = exclusionPolygons[i];
                            if (rx >= excl.MinX && rx <= excl.MaxX && rz >= excl.MinY && rz <= excl.MaxY)
                            {
                                if (PointInPolygon(pt, excl.Polygon))
                                {
                                    insideExclusion = true;
                                    break;
                                }
                            }
                        }
                        if (insideExclusion) return;

                        // Check line of play safety zone (skip if inside a forest polygon)
                        bool tooCloseToLineOfPlay = false;
                        bool insideForest = false;
                        for (int i = 0; i < forestPolygons.Count; i++)
                        {
                            if (PointInPolygon(pt, forestPolygons[i]))
                            {
                                insideForest = true;
                                break;
                            }
                        }

                        if (!insideForest)
                        {
                            for (int pIdx = 0; pIdx < lineOfPlayPaths.Count; pIdx++)
                            {
                                var path = lineOfPlayPaths[pIdx];
                                for (int i = 0; i < path.Count - 1; i++)
                                {
                                    if (DistanceToSegment(pt, path[i], path[i + 1]) < 12.0f)
                                    {
                                        tooCloseToLineOfPlay = true;
                                        break;
                                    }
                                }
                                if (tooCloseToLineOfPlay) break;
                            }
                        }
                        if (tooCloseToLineOfPlay) return;

                        float normX = (rx - courseMinX) / (courseWidth == 0 ? 1f : courseWidth);
                        float normY = (rz - courseMinZ) / (courseDepth == 0 ? 1f : courseDepth);
                        int px = Math.Clamp((int)(normX * satWidth), 0, satWidth - 1);
                        int py = Math.Clamp((int)(normY * satHeight), 0, satHeight - 1);

                        Color pixelColor = GetAveragedPixel(satImage, px, py);
                        float variance = GetLocalVariance(satImage, px, py);
                        if (IsTreeColor(pixelColor) && (variance > 0.0001f || (pixelColor.G > pixelColor.R && pixelColor.G > pixelColor.B)))
                        {
                            localCandidates.Add(pt);
                        }
                    });

                    candidatePoints.AddRange(localCandidates);
                });

                await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

                GD.Print($"{LogPrefix} Found {candidatePoints.Count} tree candidate locations from satellite imagery.");

                int maxSatelliteTrees = 1500; // Capped at 1500 down from 10000
                var selectedPoints = new List<Vector2>();
                if (candidatePoints.Count > maxSatelliteTrees)
                {
                    var rnd = new Random(42);
                    var indices = Enumerable.Range(0, candidatePoints.Count).OrderBy(x => rnd.Next()).Take(maxSatelliteTrees).ToList();
                    foreach (int idx in indices)
                    {
                        selectedPoints.Add(candidatePoints[idx]);
                    }
                    GD.Print($"{LogPrefix} Capped satellite trees to {maxSatelliteTrees} (randomly sampled).");
                }
                else
                {
                    selectedPoints = candidatePoints;
                }

                foreach (var pt in selectedPoints)
                {
                    bool tooClose = false;
                    foreach (var placedPos in placedTreePositions)
                    {
                        if (pt.DistanceTo(placedPos) < minDistanceBetweenTrees)
                        {
                            tooClose = true;
                            break;
                        }
                    }

                    if (!tooClose)
                    {
                        placedTreePositions.Add(pt);
                    }
                }
            }

            // Populate all OSM forest and wood polygons
            if (forestPolygons.Count > 0)
            {
                GD.Print($"{LogPrefix} Populating {forestPolygons.Count} OSM forest/wood polygons with trees...");
                foreach (var forestPoly in forestPolygons)
                {
                    if (forestPoly.Length < 3) continue;
                    float minX = forestPoly.Min(p => p.X);
                    float maxX = forestPoly.Max(p => p.X);
                    float minY = forestPoly.Min(p => p.Y);
                    float maxY = forestPoly.Max(p => p.Y);
                    float width = maxX - minX;
                    float height = maxY - minY;
                    float area = width * height;
                    int targetForestTrees = Mathf.Clamp((int)(area / 180f), 5, 80);

                    var fRnd = new Random((int)(minX * 100f) ^ (int)(minY * 100f));
                    int forestSpawned = 0;
                    for (int attempt = 0; attempt < targetForestTrees * 5 && forestSpawned < targetForestTrees; attempt++)
                    {
                        float rx = minX + (float)fRnd.NextDouble() * width;
                        float rz = minY + (float)fRnd.NextDouble() * height;
                        var rp = new Vector2(rx, rz);
                        if (Geometry2D.IsPointInPolygon(rp, forestPoly))
                        {
                            bool tooClose = false;
                            for (int i = 0; i < placedTreePositions.Count; i++)
                            {
                                if (rp.DistanceTo(placedTreePositions[i]) < 7.0f)
                                {
                                    tooClose = true;
                                    break;
                                }
                            }
                            if (!tooClose)
                            {
                                placedTreePositions.Add(rp);
                                forestSpawned++;
                            }
                        }
                    }
                }
            }

            // Guaranteed procedural tree placement fallback if tree count is too low or satellite scan yielded few/no trees
            int targetTreeCount = Math.Max(120, Math.Max(lineOfPlayPaths.Count, holeInfo.Count) * 28);
            if (placedTreePositions.Count < targetTreeCount)
            {
                GD.Print($"{LogPrefix} Tree count ({placedTreePositions.Count}) is below target ({targetTreeCount}). Generating procedural tree placement fallback...");
                var procRnd = new Random(54321);

                Func<Vector2, bool> isProceduralPointValid = (pt) =>
                {
                    if (!isPointInMainCourse(pt)) return false;

                    for (int i = 0; i < exclusionPolygons.Count; i++)
                    {
                        var excl = exclusionPolygons[i];
                        if (pt.X >= excl.MinX && pt.X <= excl.MaxX && pt.Y >= excl.MinY && pt.Y <= excl.MaxY)
                        {
                            if (PointInPolygon(pt, excl.Polygon))
                                return false;
                        }
                    }

                    for (int pIdx = 0; pIdx < lineOfPlayPaths.Count; pIdx++)
                    {
                        var path = lineOfPlayPaths[pIdx];
                        for (int i = 0; i < path.Count - 1; i++)
                        {
                            if (DistanceToSegment(pt, path[i], path[i + 1]) < 13.0f)
                                return false;
                        }
                    }

                    for (int i = 0; i < placedTreePositions.Count; i++)
                    {
                        if (pt.DistanceTo(placedTreePositions[i]) < 8.5f)
                            return false;
                    }

                    return true;
                };

                // Pass A: Hole corridor fairway framing stands
                foreach (var path in lineOfPlayPaths)
                {
                    if (path.Count < 2) continue;
                    float totalLength = 0f;
                    for (int i = 0; i < path.Count - 1; i++) totalLength += path[i].DistanceTo(path[i + 1]);
                    if (totalLength < 40f) continue;

                    for (float d = 25f; d < totalLength - 20f; d += 15f)
                    {
                        var centerPt = GetPointOnPolyline(path, d);
                        var nextPt = GetPointOnPolyline(path, Math.Min(d + 5f, totalLength));
                        var fwd = (nextPt - centerPt).Normalized();
                        if (fwd.LengthSquared() < 0.001f) fwd = new Vector2(1, 0);
                        var perp = new Vector2(-fwd.Y, fwd.X);

                        // Left stands
                        float[] leftOffsets = new float[] { -22f, -32f, -42f };
                        foreach (var off in leftOffsets)
                        {
                            var cand = centerPt + perp * (off + (float)(procRnd.NextDouble() * 8.0 - 4.0)) + fwd * (float)(procRnd.NextDouble() * 6.0 - 3.0);
                            if (isProceduralPointValid(cand))
                            {
                                placedTreePositions.Add(cand);
                            }
                        }

                        // Right stands
                        float[] rightOffsets = new float[] { 22f, 32f, 42f };
                        foreach (var off in rightOffsets)
                        {
                            var cand = centerPt + perp * (off + (float)(procRnd.NextDouble() * 8.0 - 4.0)) + fwd * (float)(procRnd.NextDouble() * 6.0 - 3.0);
                            if (isProceduralPointValid(cand))
                            {
                                placedTreePositions.Add(cand);
                            }
                        }
                    }
                }

                // Pass B: Green backdrop clusters
                foreach (var kp in holeInfo)
                {
                    if (kp.Value.HoleLocation == null || kp.Value.HoleLocation.Length < 2) continue;
                    var pinPos = new Vector2(kp.Value.HoleLocation[0], kp.Value.HoleLocation[1]);

                    for (int attempt = 0; attempt < 16; attempt++)
                    {
                        float angle = (float)(procRnd.NextDouble() * Math.PI * 2.0);
                        float dist = 18f + (float)procRnd.NextDouble() * 16f;
                        var cand = pinPos + new Vector2(Mathf.Cos(angle) * dist, Mathf.Sin(angle) * dist);
                        if (isProceduralPointValid(cand))
                        {
                            placedTreePositions.Add(cand);
                        }
                    }
                }

                // Pass C: Tee backdrops
                foreach (var kp in holeInfo)
                {
                    if (kp.Value.TeeBoxes != null)
                    {
                        foreach (var teeKvp in kp.Value.TeeBoxes)
                        {
                            if (teeKvp.Value == null || teeKvp.Value.Length < 2) continue;
                            var teePos = new Vector2(teeKvp.Value[0], teeKvp.Value[1]);

                            for (int attempt = 0; attempt < 6; attempt++)
                            {
                                float angle = (float)(procRnd.NextDouble() * Math.PI * 2.0);
                                float dist = 12f + (float)procRnd.NextDouble() * 14f;
                                var cand = teePos + new Vector2(Mathf.Cos(angle) * dist, Mathf.Sin(angle) * dist);
                                if (isProceduralPointValid(cand))
                                {
                                    placedTreePositions.Add(cand);
                                }
                            }
                        }
                    }
                }

                // Pass D: Open rough filler if still below target
                if (placedTreePositions.Count < targetTreeCount)
                {
                    for (float rx = courseMinX + 15f; rx <= courseMaxX - 15f && placedTreePositions.Count < targetTreeCount; rx += 18f)
                    {
                        for (float rz = courseMinZ + 15f; rz <= courseMaxZ - 15f && placedTreePositions.Count < targetTreeCount; rz += 18f)
                        {
                            var cand = new Vector2(
                                rx + (float)(procRnd.NextDouble() * 10.0 - 5.0),
                                rz + (float)(procRnd.NextDouble() * 10.0 - 5.0)
                            );
                            if (isProceduralPointValid(cand))
                            {
                                placedTreePositions.Add(cand);
                            }
                        }
                    }
                }

                GD.Print($"{LogPrefix} Procedural tree placement completed. Total trees: {placedTreePositions.Count}.");
            }

            int subdivisionsX = Mathf.Clamp((int)Math.Ceiling(courseWidth / 2.0f), 100, 1000);
            int subdivisionsZ = Mathf.Clamp((int)Math.Ceiling(courseDepth / 2.0f), 100, 1000);

            EmitSignal(SignalName.DownloadProgress, "Generating 3D terrain and surface blend maps...");
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

            // Generate unified terrain with mulch mapped around all tree positions!
            await CreateUnifiedTerrainAsync(courseMinX, courseMaxX, courseMinZ, courseMaxZ, subdivisionsX, subdivisionsZ, rootNode, exclusionPolygons, placedTreePositions);

            EmitSignal(SignalName.DownloadProgress, "Placing trees, greens, and course objects...");
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

            // Spawn all trees (OSM + satellite selected)
            foreach (var pt in placedTreePositions)
            {
                float height = GetHeight(pt.X, pt.Y);
                AddTreeAt(rootNode, new Vector3(pt.X, height, pt.Y));
            }
            GD.Print($"{LogPrefix} Placed {placedTreePositions.Count} trees total.");

            // Spawn random bushes clustered around a subset of trees
            if (placedTreePositions.Count > 0)
            {
                GD.Print($"{LogPrefix} Placing bushes clustered around trees...");
                var bushRnd = new Random(99);
                int bushCount = 0;
                int maxBushes = 1200;
                var placedBushPositions = new List<Vector2>();

                var treeIndices = Enumerable.Range(0, placedTreePositions.Count).OrderBy(x => bushRnd.Next()).ToList();
                int treesWithBushesCount = (int)(placedTreePositions.Count * 0.35);

                for (int tIdx = 0; tIdx < treesWithBushesCount && bushCount < maxBushes; tIdx++)
                {
                    var treePos = placedTreePositions[treeIndices[tIdx]];
                    int numBushesAroundTree = bushRnd.Next(1, 4);

                    for (int b = 0; b < numBushesAroundTree && bushCount < maxBushes; b++)
                    {
                        double angle = bushRnd.NextDouble() * Math.PI * 2.0;
                        float distance = 1.5f + (float)bushRnd.NextDouble() * 2.0f;
                        float bx = treePos.X + (float)Math.Cos(angle) * distance;
                        float bz = treePos.Y + (float)Math.Sin(angle) * distance;
                        var pt = new Vector2(bx, bz);

                        if (!isPointInMainCourse(pt)) continue;

                        bool insideExclusion = false;
                        foreach (var excl in exclusionPolygons)
                        {
                            if (bx >= excl.MinX && bx <= excl.MaxX && bz >= excl.MinY && bz <= excl.MaxY)
                            {
                                if (PointInPolygon(pt, excl.Polygon))
                                {
                                    insideExclusion = true;
                                    break;
                                }
                            }
                        }
                        if (insideExclusion) continue;

                        bool tooCloseToLineOfPlay = false;
                        bool insideForest = false;
                        foreach (var forestPoly in forestPolygons)
                        {
                            if (PointInPolygon(pt, forestPoly))
                            {
                                insideForest = true;
                                break;
                            }
                        }

                        if (!insideForest)
                        {
                            foreach (var path in lineOfPlayPaths)
                            {
                                for (int i = 0; i < path.Count - 1; i++)
                                {
                                    if (DistanceToSegment(pt, path[i], path[i + 1]) < 8.0f)
                                    {
                                        tooCloseToLineOfPlay = true;
                                        break;
                                    }
                                }
                                if (tooCloseToLineOfPlay) break;
                            }
                        }
                        if (tooCloseToLineOfPlay) continue;

                        bool tooCloseToBush = false;
                        foreach (var bushPos in placedBushPositions)
                        {
                            if (pt.DistanceTo(bushPos) < 1.2f)
                            {
                                tooCloseToBush = true;
                                break;
                            }
                        }
                        if (tooCloseToBush) continue;

                        float bh = GetHeight(bx, bz);
                        AddBushAt(rootNode, new Vector3(bx, bh, bz));
                        placedBushPositions.Add(pt);
                        bushCount++;
                    }
                }
                GD.Print($"{LogPrefix} Placed {bushCount} bushes clustered around trees.");
            }

            // Gather node-based tees from nodeTags list
            foreach (var kvp in nodeTags)
            {
                if (kvp.Value.TryGetValue("golf", out var golfVal) && golfVal == "tee")
                {
                    if (nodes.TryGetValue(kvp.Key, out var coord))
                    {
                        float tx = (float)((coord.Lon - refLon) * metersPerLon);
                        float tz = -(float)((coord.Lat - refLat) * metersPerLat);
                        if (!isPointInMainCourse(new Vector2(tx, tz)))
                            continue;

                        // If node-based tee has no ref tag, do not assign it to Hole 1.
                        if (!kvp.Value.TryGetValue("ref", out string? refHole) || string.IsNullOrEmpty(refHole))
                        {
                            continue;
                        }

                        string teeColor = kvp.Value.GetValueOrDefault("tee", "blue").ToLower();
                        
                        tees.Add(new TeeConfig
                        {
                            HoleNum = refHole,
                            Color = teeColor,
                            Location = new float[] { tx, tz }
                        });
                    }
                }
            }

            // Map tees to their respective holes
            foreach (var tee in tees)
            {
                if (holeInfo.TryGetValue(GetHoleKey(tee.HoleNum), out var holeConfig))
                {
                    string colorKey = char.ToUpper(tee.Color[0]) + tee.Color.Substring(1);
                    holeConfig.TeeBoxes[colorKey] = tee.Location;
                }
            }

            // Ensure every hole has a default tee if none was parsed
            foreach (var kp in holeInfo)
            {
                if (kp.Value.TeeBoxes.Count == 0)
                {
                    kp.Value.TeeBoxes["Blue"] = new float[] { 0.0f, 0.0f };
                    kp.Value.TeeBoxes["Red"] = new float[] { 5.0f, 0.0f };
                    kp.Value.TeeBoxes["White"] = new float[] { 10.0f, 0.0f };
                }
            }

            // If no holes parsed, create a default Hole 1
            if (holeInfo.Count == 0)
            {
                holeInfo["1"] = new HoleConfig
                {
                    Par = 4,
                    Handicap = 1,
                    Name = "Opening Hole",
                    HoleLocation = new float[] { 150.0f, 0.0f },
                    TeeBoxes = new Dictionary<string, float[]>
                    {
                        { "Blue", new float[] { 0.0f, 0.0f } },
                        { "Red", new float[] { 5.0f, 0.0f } },
                        { "White", new float[] { 10.0f, 0.0f } }
                    }
                };
            }

            bool madeUpFairways = false;
            bool madeUpGreens = false;

            if (parsedFairwaysCount == 0 && holeInfo.Count > 0)
            {
                madeUpFairways = true;
                foreach (var kp in holeInfo)
                {
                    var hole = kp.Value;
                    if (hole.HolePath == null || hole.HolePath.Count < 2) continue;

                    var pathPoints = new List<Vector2>();
                    foreach (var p in hole.HolePath)
                    {
                        pathPoints.Add(new Vector2(p[0], p[1]));
                    }

                    float totalLen = 0f;
                    for (int i = 0; i < pathPoints.Count - 1; i++)
                    {
                        totalLen += pathPoints[i].DistanceTo(pathPoints[i + 1]);
                    }

                    float startDist = Math.Min(totalLen * 0.15f, 40f);
                    float endDist = Math.Max(totalLen - 15f, totalLen * 0.85f);
                    if (endDist > startDist + 5f)
                    {
                        var fairwayCenterLine = new List<Vector2>();
                        fairwayCenterLine.Add(GetPointOnPolyline(pathPoints, startDist));

                        float acc = 0f;
                        for (int i = 0; i < pathPoints.Count - 1; i++)
                        {
                            float d = pathPoints[i].DistanceTo(pathPoints[i + 1]);
                            float nextAcc = acc + d;
                            if (nextAcc > startDist && nextAcc < endDist)
                            {
                                fairwayCenterLine.Add(pathPoints[i + 1]);
                            }
                            acc = nextAcc;
                        }

                        fairwayCenterLine.Add(GetPointOnPolyline(pathPoints, endDist));

                        var uniqueCenterLine = new List<Vector2>();
                        foreach (var p in fairwayCenterLine)
                        {
                            if (uniqueCenterLine.Count == 0 || uniqueCenterLine[^1].DistanceTo(p) > 0.1f)
                            {
                                uniqueCenterLine.Add(p);
                            }
                        }

                        // Smooth the centerline to round side corners
                        var smoothedCenterLine = SmoothPath(uniqueCenterLine, 3);

                        int k = smoothedCenterLine.Count - 1;
                        if (k >= 1)
                        {
                            Vector2[] leftPoints = new Vector2[k + 1];
                            Vector2[] rightPoints = new Vector2[k + 1];
                            float fairwayHalfWidth = 15f; // 30 meters total width

                            for (int i = 0; i <= k; i++)
                            {
                                Vector2 forward;
                                if (i == 0)
                                {
                                    forward = (smoothedCenterLine[1] - smoothedCenterLine[0]).Normalized();
                                }
                                else if (i == k)
                                {
                                    forward = (smoothedCenterLine[k] - smoothedCenterLine[k - 1]).Normalized();
                                }
                                else
                                {
                                    Vector2 f1 = (smoothedCenterLine[i] - smoothedCenterLine[i - 1]).Normalized();
                                    Vector2 f2 = (smoothedCenterLine[i + 1] - smoothedCenterLine[i]).Normalized();
                                    forward = (f1 + f2).Normalized();
                                }

                                Vector2 normal = new Vector2(-forward.Y, forward.X);
                                leftPoints[i] = smoothedCenterLine[i] - normal * fairwayHalfWidth;
                                rightPoints[i] = smoothedCenterLine[i] + normal * fairwayHalfWidth;
                            }

                            // Assemble polygon with rounded caps at both ends
                            var fairwayPolygon = new List<Vector2>();

                            // Start cap (at C_0): round from leftPoints[0] to rightPoints[0]
                            Vector2 startForward = (smoothedCenterLine[1] - smoothedCenterLine[0]).Normalized();
                            Vector2 startNormal = new Vector2(-startForward.Y, startForward.X);
                            int capSteps = 6;
                            for (int i = 0; i <= capSteps; i++)
                            {
                                float angle = -Mathf.Pi / 2f + (i * Mathf.Pi / capSteps);
                                Vector2 capPoint = smoothedCenterLine[0] - startForward * fairwayHalfWidth * Mathf.Cos(angle) + startNormal * fairwayHalfWidth * Mathf.Sin(angle);
                                fairwayPolygon.Add(capPoint);
                            }

                            // Right side: from rightPoints[1] to rightPoints[k-1]
                            for (int i = 1; i < k; i++)
                            {
                                fairwayPolygon.Add(rightPoints[i]);
                            }

                            // End cap (at C_k): round from rightPoints[k] to leftPoints[k]
                            Vector2 endForward = (smoothedCenterLine[k] - smoothedCenterLine[k - 1]).Normalized();
                            Vector2 endNormal = new Vector2(-endForward.Y, endForward.X);
                            for (int i = 0; i <= capSteps; i++)
                            {
                                float angle = -Mathf.Pi / 2f + (i * Mathf.Pi / capSteps);
                                Vector2 capPoint = smoothedCenterLine[k] + endForward * fairwayHalfWidth * Mathf.Cos(angle) - endNormal * fairwayHalfWidth * Mathf.Sin(angle);
                                fairwayPolygon.Add(capPoint);
                            }

                            // Left side: from leftPoints[k-1] down to leftPoints[1]
                            for (int i = k - 1; i >= 1; i--)
                            {
                                fairwayPolygon.Add(leftPoints[i]);
                            }

                            // Clip the fairway against all water hazard polygons
                            var currentPolygons = new List<Vector2[]> { fairwayPolygon.ToArray() };
                            foreach (var waterPoly in waterPolygons)
                            {
                                var nextPolygons = new List<Vector2[]>();
                                foreach (var poly in currentPolygons)
                                {
                                    var clipped = Geometry2D.ClipPolygons(poly, waterPoly);
                                    if (clipped != null)
                                    {
                                        foreach (var cp in clipped)
                                        {
                                            if (cp.Length >= 3)
                                            {
                                                nextPolygons.Add(cp);
                                            }
                                        }
                                    }
                                }
                                currentPolygons = nextPolygons;
                            }

                            // Render each unclipped portion of the fairway
                            int partIdx = 0;
                            foreach (var poly in currentPolygons)
                            {
                                string suffix = currentPolygons.Count > 1 
                                    ? $"{kp.Key.Replace(" ", "_")}_part{partIdx++}" 
                                    : kp.Key.Replace(" ", "_");
                                CreateGolfSurfaceMesh(rootNode, poly, "fairway", $"madeup_{suffix}", exclusionPolygons);
                            }
                        }
                    }
                }
            }

            if (parsedGreensCount == 0 && holeInfo.Count > 0)
            {
                madeUpGreens = true;
                foreach (var kp in holeInfo)
                {
                    var hole = kp.Value;
                    if (hole.HolePath == null || hole.HolePath.Count == 0) continue;

                    var lastPt = hole.HolePath[hole.HolePath.Count - 1];
                    Vector2 greenCenter = new Vector2(lastPt[0], lastPt[1]);

                    // Generate a smooth organic oval instead of an octagon
                    int greenPointCount = 24;
                    var greenPoints = new Vector2[greenPointCount];
                    float baseRadius = 12.0f;
                    for (int i = 0; i < greenPointCount; i++)
                    {
                        float angle = i * Mathf.Pi * 2f / greenPointCount;
                        // Create organic oval with gentle variation so it looks natural
                        float radius = baseRadius + 2.0f * Mathf.Sin(angle * 2f) + 1.0f * Mathf.Cos(angle * 3f);
                        greenPoints[i] = greenCenter + new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * radius;
                    }

                    CreateGolfSurfaceMesh(rootNode, greenPoints, "green", $"madeup_{kp.Key.Replace(" ", "_")}", exclusionPolygons);
                }
            }

            bool madeUpTees = false;
            if (holeInfo.Count > 0)
            {
                foreach (var kp in holeInfo)
                {
                    var holeKey = kp.Key;
                    var hole = kp.Value;
                    if (hole.TeeBoxes != null && hole.TeeBoxes.Count > 0)
                    {
                        foreach (var teeBoxKvp in hole.TeeBoxes)
                        {
                            var teeColorName = teeBoxKvp.Key;
                            var teeBoxPos = teeBoxKvp.Value;
                            
                            // Check if this tee position is already inside an explicit tee polygon
                            bool alreadyHasPolygon = false;
                            Vector2 pos2d = new Vector2(teeBoxPos[0], teeBoxPos[1]);
                            foreach (var excl in exclusionPolygons)
                            {
                                if (excl.GolfType == "tee" && Geometry2D.IsPointInPolygon(pos2d, excl.Polygon))
                                {
                                    alreadyHasPolygon = true;
                                    break;
                                }
                            }
                            
                            if (!alreadyHasPolygon)
                            {
                                madeUpTees = true;
                                Vector2 center = pos2d;
                                Vector2 forward = Vector2.Right;
                                if (hole.HolePath != null && hole.HolePath.Count >= 2)
                                {
                                    Vector2 p0 = new Vector2(hole.HolePath[0][0], hole.HolePath[0][1]);
                                    Vector2 p1 = new Vector2(hole.HolePath[1][0], hole.HolePath[1][1]);
                                    if (p0.DistanceTo(p1) > 0.1f)
                                    {
                                        forward = (p1 - p0).Normalized();
                                    }
                                }
                                Vector2 right = new Vector2(-forward.Y, forward.X);
                                
                                var teeBoxPoints = new Vector2[4]
                                {
                                    center - forward * 3f - right * 2f,
                                    center - forward * 3f + right * 2f,
                                    center + forward * 3f + right * 2f,
                                    center + forward * 3f - right * 2f
                                };
                                
                                CreateTeeBoxMesh(rootNode, teeBoxPoints, $"{kp.Key.Replace(" ", "_")}_{teeColorName}", exclusionPolygons);
                            }
                        }
                    }
                    else if (hole.HolePath != null && hole.HolePath.Count > 0)
                    {
                        var teeBoxPos = hole.HolePath[0];
                        Vector2 pos2d = new Vector2(teeBoxPos[0], teeBoxPos[1]);
                        
                        bool alreadyHasPolygon = false;
                        foreach (var excl in exclusionPolygons)
                        {
                            if (excl.GolfType == "tee" && Geometry2D.IsPointInPolygon(pos2d, excl.Polygon))
                            {
                                alreadyHasPolygon = true;
                                break;
                            }
                        }
                        
                        if (!alreadyHasPolygon)
                        {
                            madeUpTees = true;
                            Vector2 center = pos2d;
                            Vector2 forward = Vector2.Right;
                            if (hole.HolePath.Count >= 2)
                            {
                                Vector2 p0 = new Vector2(hole.HolePath[0][0], hole.HolePath[0][1]);
                                Vector2 p1 = new Vector2(hole.HolePath[1][0], hole.HolePath[1][1]);
                                if (p0.DistanceTo(p1) > 0.1f)
                                {
                                    forward = (p1 - p0).Normalized();
                                }
                            }
                            Vector2 right = new Vector2(-forward.Y, forward.X);
                            
                            var teeBoxPoints = new Vector2[4]
                            {
                                center - forward * 3f - right * 2f,
                                center - forward * 3f + right * 2f,
                                center + forward * 3f + right * 2f,
                                center + forward * 3f - right * 2f
                            };
                            
                            CreateTeeBoxMesh(rootNode, teeBoxPoints, $"{kp.Key.Replace(" ", "_")}_default", exclusionPolygons);
                        }
                    }
                }
            }

            // Procedurally spawn rock decorations around water hazards
            InitializeRockAssets();
            if (_rockMeshes != null)
            {
                var rand = new Random(42);
                foreach (var waterPoly in waterPolygons)
                {
                    int numPoints = waterPoly.Length;
                    for (int i = 0; i < numPoints; i++)
                    {
                        Vector2 p1 = waterPoly[i];
                        Vector2 p2 = waterPoly[(i + 1) % numPoints];
                        float segmentLength = p1.DistanceTo(p2);
                        
                        // Spawn a rock every 1.0 to 1.4 meters to cover the full perimeter with no gaps
                        float step = 1.0f + (float)rand.NextDouble() * 0.4f;
                        for (float d = 0f; d < segmentLength; d += step)
                        {
                            float t = d / segmentLength;
                            Vector2 pos2d = p1.Lerp(p2, t);
                            
                            Vector2 dir = (p2 - p1).Normalized();
                            Vector2 perp = new Vector2(-dir.Y, dir.X);
                            
                            // Jitter offset: -0.2m to +0.2m (keep aligned to water perimeter)
                            float jitter = -0.2f + (float)rand.NextDouble() * 0.4f;
                            Vector2 rockPos2d = pos2d + perp * jitter;
                            
                            float rockX = rockPos2d.X;
                            float rockZ = rockPos2d.Y;
                            float terrainY = GetHeightWithFeatures(rockX, rockZ, exclusionPolygons);
                            
                            // Scale variety (various sizes to look natural)
                            float rScaleX = 0.8f + (float)rand.NextDouble() * 1.2f;
                            float rScaleY = 0.5f + (float)rand.NextDouble() * 0.8f;
                            float rScaleZ = 0.8f + (float)rand.NextDouble() * 1.2f;
                            Vector3 rockScale = new Vector3(rScaleX, rScaleY, rScaleZ);
                            
                            float rotY = (float)(rand.NextDouble() * Math.PI * 2.0);
                            var rockMesh = _rockMeshes[rand.Next(_rockMeshes.Length)];
                            
                            // Sit rock on terrain, keeping it above the depressed water level
                            float baseHeight = GetHeight(rockX, rockZ);
                            float spawnY = Math.Max(terrainY, baseHeight - 0.2f);
                            Vector3 rockPos = new Vector3(rockX, spawnY + 0.1f, rockZ);
                            SpawnRockAt(rootNode, rockPos, rockScale, rotY, rockMesh);
                        }
                    }
                }
            }

            var madeUpDetails = new List<string>();
            if (madeUpFairways) madeUpDetails.Add("fairways");
            if (madeUpGreens) madeUpDetails.Add("greens");
            if (madeUpTees) madeUpDetails.Add("tee boxes");

            if (madeUpDetails.Count > 0)
            {
                string detailsStr = string.Join(" and ", madeUpDetails);
                if (madeUpDetails.Count > 2)
                {
                    detailsStr = $"{madeUpDetails[0]}, {madeUpDetails[1]}, and {madeUpDetails[2]}";
                }
                _generationMessage = $"Successfully generated course: {courseName}! ({detailsStr} were made up)";
            }
            else
            {
                _generationMessage = $"Successfully generated course: {courseName}!";
            }

            // Add Player Node structure & TCP Server & Range UI to scene so it's a complete course scene!
            // We can load them from their res:// paths to keep scene compatible
            var playerScene = GD.Load<PackedScene>("res://Player/player.tscn");
            if (playerScene != null)
            {
                var playerInst = playerScene.Instantiate();
                playerInst.Name = "Player";
                rootNode.AddChild(playerInst);
                playerInst.Owner = rootNode;
            }

            // Add PhantomCamera3D & Camera3D structure for range.gd compatibility
            var phantomCam = new Node3D { Name = "PhantomCamera3D" };
            phantomCam.SetScript(GD.Load<Script>("res://addons/phantom_camera/scripts/phantom_camera/phantom_camera_3d.gd"));
            
            var cameraResource = (Resource)GD.Load<GDScript>("res://addons/phantom_camera/scripts/resources/camera_3d_resource.gd").New();
            cameraResource.Set("fov", 55.0f);
            cameraResource.Set("far", 400.0f);
            phantomCam.Set("camera_3d_resource", cameraResource);

            phantomCam.Transform = new Transform3D(
                new Basis(new Vector3(-4.37114e-08f, 0f, -1f), new Vector3(0f, 1f, 0f), new Vector3(1f, 0f, -4.37114e-08f)),
                new Vector3(-6.04467f, 3.02244f, 0f)
            );
            phantomCam.Set("follow_offset", new Vector3(-15.0f, 2.4f, 0f));
            phantomCam.Set("follow_damping", true);
            phantomCam.Set("follow_damping_value", new Vector3(0.4f, 0.1f, 0.1f));
            phantomCam.Set("dead_zone_height", 0.204f);
            rootNode.AddChild(phantomCam);
            phantomCam.Owner = rootNode;

            var camera3d = new Camera3D { Name = "Camera3D" };
            camera3d.Fov = 55.0f;
            camera3d.Far = 400.0f;
            var cameraAttrs = new CameraAttributesPractical();
            cameraAttrs.DofBlurFarEnabled = false;
            cameraAttrs.DofBlurFarDistance = 150.0f;
            cameraAttrs.DofBlurFarTransition = 100.0f;
            cameraAttrs.DofBlurAmount = 0.08f;
            camera3d.Attributes = cameraAttrs;
            camera3d.Transform = new Transform3D(
                new Basis(new Vector3(-4.37114e-08f, 0f, -1f), new Vector3(0f, 1f, 0f), new Vector3(1f, 0f, -4.37114e-08f)),
                new Vector3(-6.04467f, 3.02244f, 0f)
            );
            rootNode.AddChild(camera3d);
            camera3d.Owner = rootNode;

            var camHost = new Node { Name = "PhantomCameraHost" };
            camHost.SetScript(GD.Load<Script>("res://addons/phantom_camera/scripts/phantom_camera_host/phantom_camera_host.gd"));
            camera3d.AddChild(camHost);
            camHost.Owner = rootNode;

            // Create AerialCamera for top-down map view
            var aerialCam = new Camera3D { Name = "AerialCamera" };
            aerialCam.Projection = Camera3D.ProjectionType.Orthogonal;
            aerialCam.Size = 300.0f; // Shows 300m x 300m area
            aerialCam.Transform = new Transform3D(
                new Basis(new Vector3(1f, 0f, 0f), new Vector3(0f, 0f, -1f), new Vector3(0f, 1f, 0f)), // Looking straight down
                new Vector3(0f, 150f, 0f)
            );
            rootNode.AddChild(aerialCam);
            aerialCam.Owner = rootNode;

            // Create SessionRecorder for recording dynamic course play sessions
            var sessionRec = new Node { Name = "SessionRecorder" };
            sessionRec.SetScript(GD.Load<Script>("res://SessionRecorder/session_recorder.gd"));
            rootNode.AddChild(sessionRec);
            sessionRec.Owner = rootNode;

            // Create TCPServer for shot injection
            var tcpServer = new LaunchMonitors.Common.Tcp.TcpServer { Name = "TCPServer" };
            rootNode.AddChild(tcpServer);
            tcpServer.Owner = rootNode;

            // Create Sky3D WorldEnvironment
            var sky3D = new WorldEnvironment { Name = "Sky3D" };
            sky3D.SetScript(GD.Load<Script>("res://addons/sky_3d/src/Sky3D.gd"));
            sky3D.Set("enable_editor_time", false);
            sky3D.Set("current_time", 13.25f);
            sky3D.Set("enable_game_time", false);

            var skyMaterial = new ShaderMaterial();
            skyMaterial.Shader = GD.Load<Shader>("res://addons/sky_3d/shaders/SkyMaterial.gdshader");
            skyMaterial.SetShaderParameter("sky_visible", true);
            skyMaterial.SetShaderParameter("color_correction_params", new Vector2(0f, 1f));
            skyMaterial.SetShaderParameter("ground_color", new Color(0.3f, 0.3f, 0.3f, 1f));
            skyMaterial.SetShaderParameter("horizon_level", 0f);
            skyMaterial.SetShaderParameter("atm_darkness", 0.5f);
            skyMaterial.SetShaderParameter("atm_sun_intensity", 18.0f);
            skyMaterial.SetShaderParameter("atm_day_tint", new Color(0.35f, 0.65f, 0.95f, 1f));
            skyMaterial.SetShaderParameter("atm_horizon_light_tint", new Color(0.980392f, 0.635294f, 0.462745f, 1f));
            skyMaterial.SetShaderParameter("atm_night_tint", new Color(0f, 0f, 0f, 0f));
            skyMaterial.SetShaderParameter("atm_level_params", new Vector3(1f, 0f, 0f));
            skyMaterial.SetShaderParameter("atm_thickness", 0.7f);
            skyMaterial.SetShaderParameter("atm_beta_ray", new Vector3(5.804544e-06f, 1.3562913e-05f, 3.311258e-05f));
            skyMaterial.SetShaderParameter("atm_beta_mie", new Vector3(3.038e-08f, 3.038e-08f, 3.038e-08f));
            skyMaterial.SetShaderParameter("sun_disk_color", new Color(0.996094f, 0.541334f, 0.140076f, 1f));
            skyMaterial.SetShaderParameter("sun_disk_intensity", 30.0f);
            skyMaterial.SetShaderParameter("sun_disk_size", 0.02f);
            skyMaterial.SetShaderParameter("atm_sun_mie_tint", new Color(1f, 1f, 1f, 1f));
            skyMaterial.SetShaderParameter("atm_sun_mie_intensity", 1.0f);
            skyMaterial.SetShaderParameter("atm_sun_partial_mie_phase", new Vector3(0.36f, 1.64f, 1.6f));
            skyMaterial.SetShaderParameter("moon_color", new Color(1f, 1f, 1f, 1f));
            skyMaterial.SetShaderParameter("moon_texture", GD.Load<Texture2D>("res://addons/sky_3d/assets/thirdparty/textures/moon/MoonMap.png"));
            skyMaterial.SetShaderParameter("moon_texture_alignment", new Vector3(7f, 1.4f, 4.8f));
            skyMaterial.SetShaderParameter("moon_texture_flip_u", false);
            skyMaterial.SetShaderParameter("moon_texture_flip_v", false);
            skyMaterial.SetShaderParameter("moon_size", 0.07f);
            skyMaterial.SetShaderParameter("atm_moon_mie_tint", new Color(0.137255f, 0.184314f, 0.292196f, 1f));
            skyMaterial.SetShaderParameter("atm_moon_mie_intensity", 0.0f);
            skyMaterial.SetShaderParameter("atm_moon_partial_mie_phase", new Vector3(0.36f, 1.64f, 1.6f));
            skyMaterial.SetShaderParameter("background_texture", GD.Load<Texture2D>("res://addons/sky_3d/assets/thirdparty/textures/milkyway/Milkyway.jpg"));
            skyMaterial.SetShaderParameter("background_color", new Color(0.709804f, 0.709804f, 0.709804f, 0.854902f));
            skyMaterial.SetShaderParameter("stars_field_color", new Color(1f, 1f, 1f, 1f));
            skyMaterial.SetShaderParameter("stars_field_texture", GD.Load<Texture2D>("res://addons/sky_3d/assets/thirdparty/textures/milkyway/StarField.jpg"));
            skyMaterial.SetShaderParameter("sky_alignment", new Vector3(2.6555f, -0.23935f, 0.4505f));
            skyMaterial.SetShaderParameter("sky_rotation", -8.458832f);
            skyMaterial.SetShaderParameter("sky_tilt", -1.291544f);
            skyMaterial.SetShaderParameter("stars_scintillation", 0.75f);
            skyMaterial.SetShaderParameter("stars_scintillation_speed", 0.01f);
            skyMaterial.SetShaderParameter("noise_tex", GD.Load<Texture2D>("res://addons/sky_3d/assets/textures/noise.jpg"));

            bool isMobilePlatform = OS.GetName() == "Android" || OS.GetName() == "iOS";

            // Clouds
            skyMaterial.SetShaderParameter("clouds_visible", !isMobilePlatform);
            skyMaterial.SetShaderParameter("clouds_coverage", 0.22f);
            skyMaterial.SetShaderParameter("clouds_thickness", 1.2f);
            skyMaterial.SetShaderParameter("clouds_absorption", 2.0f);
            skyMaterial.SetShaderParameter("clouds_sky_tint_fade", 0.5f);
            skyMaterial.SetShaderParameter("clouds_intensity", 10.0f);
            skyMaterial.SetShaderParameter("clouds_size", 2.0f);
            skyMaterial.SetShaderParameter("clouds_uv", new Vector2(0.16f, 0.11f));
            skyMaterial.SetShaderParameter("clouds_speed", 0.07f);
            skyMaterial.SetShaderParameter("clouds_direction", new Vector2(0.25f, 0.25f));
            skyMaterial.SetShaderParameter("clouds_day_color", new Color(1f, 1f, 1f, 1f));
            skyMaterial.SetShaderParameter("clouds_horizon_light_color", new Color(0.98f, 0.43f, 0.15f, 1f));
            skyMaterial.SetShaderParameter("clouds_night_color", new Color(0.090196f, 0.094118f, 0.129412f, 1f));
            skyMaterial.SetShaderParameter("clouds_texture", GD.Load<Texture2D>("res://addons/sky_3d/assets/resources/SNoise.tres"));

            // Cumulus
            skyMaterial.SetShaderParameter("cumulus_clouds_visible", !isMobilePlatform);
            skyMaterial.SetShaderParameter("cumulus_clouds_coverage", 0.25f);
            skyMaterial.SetShaderParameter("cumulus_clouds_thickness", 0.0243f);
            skyMaterial.SetShaderParameter("cumulus_clouds_absorption", 2.0f);
            skyMaterial.SetShaderParameter("cumulus_clouds_noise_freq", 2.7f);
            skyMaterial.SetShaderParameter("cumulus_clouds_sky_tint_fade", 0.0f);
            skyMaterial.SetShaderParameter("cumulus_clouds_intensity", 0.6f);
            skyMaterial.SetShaderParameter("cumulus_clouds_size", 0.5f);
            skyMaterial.SetShaderParameter("cumulus_clouds_speed", 0.05f);
            skyMaterial.SetShaderParameter("cumulus_clouds_direction", new Vector3(0.25f, 0.1f, 0.25f));
            skyMaterial.SetShaderParameter("cumulus_clouds_texture", GD.Load<Texture2D>("res://addons/sky_3d/assets/textures/noiseClouds.png"));
            skyMaterial.SetShaderParameter("cumulus_clouds_day_color", new Color(1f, 1f, 1f, 1f));
            skyMaterial.SetShaderParameter("cumulus_clouds_horizon_light_color", new Color(0.98f, 0.43f, 0.15f, 1f));
            skyMaterial.SetShaderParameter("cumulus_clouds_night_color", new Color(0.090196f, 0.094118f, 0.129412f, 1f));
            skyMaterial.SetShaderParameter("cumulus_clouds_partial_mie_phase", new Vector3(0.957564f, 1.042436f, 0.412f));
            skyMaterial.SetShaderParameter("cumulus_clouds_mie_intensity", 1.0f);

            var sky = new Sky 
            { 
                SkyMaterial = skyMaterial,
                ProcessMode = isMobilePlatform ? Sky.ProcessModeEnum.Quality : Sky.ProcessModeEnum.Automatic
            };
            var env = new Godot.Environment
            {
                BackgroundMode = Godot.Environment.BGMode.Sky,
                Sky = sky,
                AmbientLightSource = Godot.Environment.AmbientSource.Sky,
                AmbientLightColor = new Color(0.9631823f, 0.9631823f, 0.9631823f, 1f),
                AmbientLightSkyContribution = 0.55f,
                AmbientLightEnergy = 0.50f,
                ReflectedLightSource = Godot.Environment.ReflectionSource.Sky,
                TonemapMode = Godot.Environment.ToneMapper.Aces,
                TonemapWhite = 5.0f,
                TonemapExposure = 1.0f,
                SsaoEnabled = !isMobilePlatform,
                SsaoRadius = 2.0f,
                SsaoIntensity = 1.2f,
                SsaoPower = 1.5f,
                SsaoDetail = 0.2f,
                SsaoHorizon = 0.06f,
                GlowEnabled = true,
                GlowIntensity = 0.2f,
                GlowBloom = 0.0f,
                GlowBlendMode = Godot.Environment.GlowBlendModeEnum.Softlight
            };
            sky3D.Environment = env;

            var skyCameraAttrs = new CameraAttributesPractical
            {
                DofBlurFarEnabled = !isMobilePlatform,
                DofBlurFarDistance = 150.0f,
                DofBlurFarTransition = 100.0f,
                DofBlurAmount = 0.08f
            };
            sky3D.CameraAttributes = skyCameraAttrs;

            rootNode.AddChild(sky3D);
            sky3D.Owner = rootNode;

            // Add SunLight
            var sunLight = new DirectionalLight3D { Name = "SunLight" };
            sunLight.LightEnergy = 1.1f;
            sunLight.ShadowEnabled = true;
            sunLight.DirectionalShadowMaxDistance = isMobilePlatform ? 200.0f : 600.0f;
            sunLight.DirectionalShadowMode = isMobilePlatform ? DirectionalLight3D.ShadowMode.Parallel2Splits : DirectionalLight3D.ShadowMode.Parallel4Splits;
            sunLight.DirectionalShadowBlendSplits = true;
            sunLight.DirectionalShadowSplit1 = isMobilePlatform ? 0.1f : 0.05f;
            sunLight.DirectionalShadowSplit2 = 0.15f;
            sunLight.DirectionalShadowSplit3 = 0.40f;
            sunLight.ShadowBias = 0.03f;
            sunLight.ShadowNormalBias = 2.0f;
            sunLight.Transform = new Transform3D(
                new Basis(
                    new Vector3(0f, -0.6049699f, -0.7962483f),
                    new Vector3(-0.36520752f, -0.7412484f, 0.5631823f),
                    new Vector3(-0.9309262f, 0.29079586f, -0.22093955f)
                ),
                new Vector3(-0.7962483f, 0.5631823f, -0.22093955f)
            );
            sky3D.AddChild(sunLight);
            sunLight.Owner = rootNode;

            // Add MoonLight
            var moonLight = new DirectionalLight3D { Name = "MoonLight" };
            moonLight.LightColor = new Color(0.572549f, 0.776471f, 0.956863f, 1f);
            moonLight.LightEnergy = 0.0f;
            moonLight.Transform = new Transform3D(
                new Basis(
                    new Vector3(0f, -0.51897305f, -0.8547907f),
                    new Vector3(-0.35659954f, 0.79859453f, -0.48485434f),
                    new Vector3(0.9342574f, 0.30481797f, -0.18506554f)
                ),
                new Vector3(-0.8547906f, -0.4848543f, -0.18506552f)
            );
            sky3D.AddChild(moonLight);
            moonLight.Owner = rootNode;

            // Add Skydome
            var skydome = new Node { Name = "Skydome" };
            skydome.SetScript(GD.Load<Script>("res://addons/sky_3d/src/Skydome.gd"));
            skydome.Set("sun_azimuth", -285.5079178078127);
            skydome.Set("sun_altitude", -55.72381487797508);
            skydome.Set("moon_azimuth", -282.21609447769833);
            skydome.Set("moon_altitude", -119.00287765558052);
            sky3D.AddChild(skydome);
            skydome.Owner = rootNode;

            // Add TimeOfDay
            var timeOfDay = new Node { Name = "TimeOfDay" };
            timeOfDay.SetScript(GD.Load<Script>("res://addons/sky_3d/src/TimeOfDay.gd"));
            timeOfDay.Set("update_in_editor", false);
            timeOfDay.Set("dome_path", new NodePath("../Skydome"));
            timeOfDay.Set("total_hours", 13.25f);
            timeOfDay.Set("day", 28);
            timeOfDay.Set("month", 5);
            sky3D.AddChild(timeOfDay);
            timeOfDay.Owner = rootNode;

            var rangeUiScene = GD.Load<PackedScene>("res://UI/range_ui.tscn");
            if (rangeUiScene != null)
            {
                var rangeUiInst = rangeUiScene.Instantiate();
                rangeUiInst.Name = "RangeUI";
                rootNode.AddChild(rangeUiInst);
                rangeUiInst.Owner = rootNode;
            }

            // Set main scene script
            rootNode.SetScript(GD.Load<Script>("res://Courses/Range/range.gd"));

            EmitSignal(SignalName.DownloadProgress, "Saving 3D course files...");
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

            GD.Print($"{LogPrefix} Saving Canned Course files to: {courseDir}...");
            
            // Save TSCN
            var packedScene = new PackedScene();
            packedScene.Pack(rootNode);
            var err = ResourceSaver.Save(packedScene, tscnPath);
            if (err != Error.Ok)
            {
                GD.PrintErr($"{LogPrefix} Failed to save course.tscn. Error: {err}");
                return false;
            }

            // Generate course.json
            var teeColors = holeInfo.Values.SelectMany(h => h.TeeBoxes.Keys).Distinct().ToList();
            if (teeColors.Count == 0) teeColors.Add("Blue");

            var courseConfig = new CourseJsonConfig
            {
                ScenePath = "course.tscn",
                Title = courseName,
                CourseInfo = new CourseInfoConfig
                {
                    TeeColors = teeColors
                },
                HoleInfo = holeInfo
            };

            var options = new JsonSerializerOptions { WriteIndented = true };
            string configJson = JsonSerializer.Serialize(courseConfig, options);
            File.WriteAllText(globalJsonPath, configJson);

            EmitSignal(SignalName.DownloadProgress, "Generating aerial hole overviews...");
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

            await GenerateAerialPreviewsAsync(rootNode, courseDir, globalCourseDir, holeInfo);

            GD.Print($"{LogPrefix} Course '{courseName}' generated successfully.");
            return true;
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Failed to query or build OSM course: {ex}");
            if (string.IsNullOrEmpty(_generationMessage))
            {
                _generationMessage = $"Error: Failed to generate course ({ex.Message}). Please retry the download, and if it continues to fail, please log a bug.";
            }
            return false;
        }
    }

    private async Task GenerateAerialPreviewsAsync(Node3D rootNode, string courseDir, string globalCourseDir, Dictionary<string, HoleConfig> holeInfo)
    {
        try
        {
            GD.Print($"{LogPrefix} Generating top-down aerial snapshots for course and holes...");
            var subViewport = new SubViewport();
            subViewport.Size = new Vector2I(1024, 1024);
            subViewport.RenderTargetUpdateMode = SubViewport.UpdateMode.Always;
            subViewport.OwnWorld3D = true;
            subViewport.World3D = new World3D();

            var tempCam = new Camera3D();
            tempCam.Projection = Camera3D.ProjectionType.Orthogonal;
            subViewport.AddChild(tempCam);

            var courseInstance = rootNode.Duplicate() as Node3D;
            if (courseInstance == null) return;
            subViewport.AddChild(courseInstance);

            AddChild(subViewport);

            // 1. Full Course Aerial View
            double minX = 99999, maxX = -99999, minZ = 99999, maxZ = -99999;
            foreach (var h in holeInfo.Values)
            {
                if (h.HoleLocation != null && h.HoleLocation.Length >= 2)
                {
                    minX = Math.Min(minX, h.HoleLocation[0]);
                    maxX = Math.Max(maxX, h.HoleLocation[0]);
                    minZ = Math.Min(minZ, h.HoleLocation[1]);
                    maxZ = Math.Max(maxZ, h.HoleLocation[1]);
                }
                if (h.TeeBoxes != null)
                {
                    foreach (var t in h.TeeBoxes.Values)
                    {
                        if (t.Length >= 2)
                        {
                            minX = Math.Min(minX, t[0]);
                            maxX = Math.Max(maxX, t[0]);
                            minZ = Math.Min(minZ, t[1]);
                            maxZ = Math.Max(maxZ, t[1]);
                        }
                    }
                }
            }
            if (minX > maxX) { minX = -150; maxX = 150; minZ = -150; maxZ = 150; }

            Vector3 center = new Vector3((float)(minX + maxX) / 2f, 150f, (float)(minZ + maxZ) / 2f);
            float width = (float)(maxX - minX);
            float depth = (float)(maxZ - minZ);
            float fullZoom = Math.Max(Math.Max(width, depth) * 1.25f, 300f);

            tempCam.Size = fullZoom;
            tempCam.Transform = new Transform3D(
                new Basis(new Vector3(1f, 0f, 0f), new Vector3(0f, 0f, -1f), new Vector3(0f, 1f, 0f)),
                center
            );

            await ToSignal(RenderingServer.Singleton, RenderingServer.SignalName.FramePostDraw);
            var courseImg = subViewport.GetTexture().GetImage();
            if (courseImg != null)
            {
                string fullCourseImgPath = Path.Combine(globalCourseDir, "aerial_course.png");
                courseImg.SavePng(fullCourseImgPath);
                GD.Print($"{LogPrefix} Saved full course aerial snapshot: {fullCourseImgPath}");
            }

            // 2. Per-hole Aerial Views
            var holeKeys = holeInfo.Keys.ToList();
            holeKeys.Sort((a, b) =>
            {
                int numA = 0, numB = 0;
                int.TryParse(a.Replace("Hole", "").Trim(), out numA);
                int.TryParse(b.Replace("Hole", "").Trim(), out numB);
                if (numA > 0 && numB > 0) return numA.CompareTo(numB);
                return string.Compare(a, b, StringComparison.Ordinal);
            });

            for (int i = 0; i < holeKeys.Count; i++)
            {
                var hKey = holeKeys[i];
                var h = holeInfo[hKey];
                if (h.HoleLocation == null || h.HoleLocation.Length < 2) continue;

                Vector3 pinPos = new Vector3(h.HoleLocation[0], 0f, h.HoleLocation[1]);
                Vector3 teePos = pinPos + new Vector3(0f, 0f, 150f);
                if (h.TeeBoxes != null && h.TeeBoxes.Count > 0)
                {
                    string firstTeeKey = h.TeeBoxes.ContainsKey("Blue") ? "Blue" : h.TeeBoxes.Keys.First();
                    var tArr = h.TeeBoxes[firstTeeKey];
                    if (tArr.Length >= 2) teePos = new Vector3(tArr[0], 0f, tArr[1]);
                }

                Vector3 dir3D = (pinPos - teePos);
                dir3D.Y = 0;
                if (dir3D.IsZeroApprox()) dir3D = new Vector3(0f, 0f, -1f);
                else dir3D = dir3D.Normalized();

                float dist = teePos.DistanceTo(pinPos);
                float holeZoom = Math.Max(dist * 1.35f, 60f);

                Vector3 rightVec = dir3D.Cross(Vector3.Up).Normalized();
                Vector3 upVec = dir3D;
                Vector3 backVec = Vector3.Up;

                tempCam.Size = holeZoom;
                Vector3 basePos = teePos + dir3D * (0.35f * holeZoom);
                tempCam.Transform = new Transform3D(
                    new Basis(rightVec, upVec, backVec),
                    new Vector3(basePos.X, 150f, basePos.Z)
                );

                await ToSignal(RenderingServer.Singleton, RenderingServer.SignalName.FramePostDraw);
                var holeImg = subViewport.GetTexture().GetImage();
                if (holeImg != null)
                {
                    string holeImgPath = Path.Combine(globalCourseDir, $"aerial_hole_{i + 1}.png");
                    holeImg.SavePng(holeImgPath);
                    GD.Print($"{LogPrefix} Saved aerial snapshot for Hole {i + 1}: {holeImgPath}");
                }
            }

            RemoveChild(subViewport);
            subViewport.QueueFree();
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Exception during aerial preview generation: {ex}");
        }
    }

    public async void SearchGolfCourses(string queryText)
    {
        var results = await SearchGolfCoursesInternalAsync(queryText);
        EmitSignal(SignalName.SearchCompleted, results);
    }

    private async Task<Godot.Collections.Array> SearchGolfCoursesInternalAsync(string queryText)
    {
        var results = new Godot.Collections.Array();
        if (string.IsNullOrWhiteSpace(queryText))
        {
            return results;
        }

        // If search doesn't contain "golf", append " golf" to help target golf courses first
        string query = queryText.Trim();
        if (!query.Contains("golf", StringComparison.OrdinalIgnoreCase))
        {
            query += " golf";
        }

        string escapedQuery = Uri.EscapeDataString(query);
        string url = $"https://nominatim.openstreetmap.org/search?q={escapedQuery}&format=json&limit=15";

        GD.Print($"{LogPrefix} Searching Nominatim for '{query}'...");

        try
        {
            var response = await HttpClient.GetAsync(url);
            if (!response.IsSuccessStatusCode)
            {
                GD.PrintErr($"{LogPrefix} Nominatim search failed with status: {response.StatusCode}");
                return results;
            }

            string jsonString = await response.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(jsonString);
            if (doc.RootElement.ValueKind != JsonValueKind.Array)
            {
                GD.PrintErr($"{LogPrefix} Invalid JSON array received from Nominatim.");
                return results;
            }

            foreach (var element in doc.RootElement.EnumerateArray())
            {
                string name = "";
                if (element.TryGetProperty("name", out var nameProp))
                {
                    name = nameProp.GetString() ?? "";
                }
                if (string.IsNullOrEmpty(name))
                {
                    if (element.TryGetProperty("display_name", out var dispProp))
                    {
                        string disp = dispProp.GetString() ?? "";
                        name = disp.Split(',')[0].Trim();
                    }
                }

                if (string.IsNullOrEmpty(name)) continue;

                double lat = 0;
                double lon = 0;
                
                if (element.TryGetProperty("lat", out var latProp) && double.TryParse(latProp.GetString(), out var parsedLat))
                {
                    lat = parsedLat;
                }
                if (element.TryGetProperty("lon", out var lonProp) && double.TryParse(lonProp.GetString(), out var parsedLon))
                {
                    lon = parsedLon;
                }

                if (lat == 0 && lon == 0) continue;

                string location = "";
                if (element.TryGetProperty("display_name", out var dispNameProp))
                {
                    string displayName = dispNameProp.GetString() ?? "";
                    var parts = displayName.Split(',');
                    if (parts.Length > 1)
                    {
                        var locParts = new List<string>();
                        for (int i = 1; i < Math.Min(parts.Length, 5); i++)
                        {
                            locParts.Add(parts[i].Trim());
                        }
                        location = string.Join(", ", locParts);
                    }
                }

                var dict = new Godot.Collections.Dictionary();
                dict["name"] = name;
                dict["lat"] = lat;
                dict["lon"] = lon;
                dict["location"] = location;

                results.Add(dict);
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Failed to search Nominatim: {ex}");
        }

        return results;
    }

    private ArrayMesh Create3DPolygonMesh(Vector2[] points, int[] indices, float height, Color color, string? golfType = "", List<ExclusionPolygon>? exclusions = null)
    {
        if (points == null || points.Length < 3 || indices == null || indices.Length == 0)
        {
            return new ArrayMesh();
        }

        var queue = new Queue<SubdivisionTriangle>();
        for (int i = 0; i < indices.Length; i += 3)
        {
            queue.Enqueue(new SubdivisionTriangle(points[indices[i]], points[indices[i+1]], points[indices[i+2]]));
        }

        var subdividedTriangles = new List<SubdivisionTriangle>();
        float maxEdgeLengthSq = 12.0f * 12.0f; // Subdivide edges longer than 12m

        while (queue.Count > 0)
        {
            var tri = queue.Dequeue();
            float dAB = tri.A.DistanceSquaredTo(tri.B);
            float dBC = tri.B.DistanceSquaredTo(tri.C);
            float dCA = tri.C.DistanceSquaredTo(tri.A);

            float maxD = Math.Max(dAB, Math.Max(dBC, dCA));
            if (maxD > maxEdgeLengthSq)
            {
                if (maxD == dAB)
                {
                    var m = (tri.A + tri.B) * 0.5f;
                    queue.Enqueue(new SubdivisionTriangle(tri.A, m, tri.C));
                    queue.Enqueue(new SubdivisionTriangle(m, tri.B, tri.C));
                }
                else if (maxD == dBC)
                {
                    var m = (tri.B + tri.C) * 0.5f;
                    queue.Enqueue(new SubdivisionTriangle(tri.B, m, tri.A));
                    queue.Enqueue(new SubdivisionTriangle(m, tri.C, tri.A));
                }
                else
                {
                    var m = (tri.C + tri.A) * 0.5f;
                    queue.Enqueue(new SubdivisionTriangle(tri.C, m, tri.B));
                    queue.Enqueue(new SubdivisionTriangle(m, tri.A, tri.B));
                }
            }
            else
            {
                subdividedTriangles.Add(tri);
            }
        }



        var arrayMesh = new ArrayMesh();
        int numTopVertices = subdividedTriangles.Count * 3;
        int M = points.Length;
        int numSkirtVertices = M * 12;
        int totalVertices = numTopVertices + numSkirtVertices;

        var vertices = new Vector3[totalVertices];
        var normals = new Vector3[totalVertices];
        var colors = new Color[totalVertices];
        var uvs = new Vector2[totalVertices];
        var newIndices = new int[totalVertices];

        // Inward taper width: vertices within this distance of the polygon edge
        // have their height offset smoothly reduced to 0 (matching rough ground)
        float taperWidth = golfType switch
        {
            "green" => 5.0f,
            "fairway" => 4.0f,
            "tee" => 3.0f,
            "bunker" => 2.5f,
            "water" => 0.0f,
            _ => 2.0f
        };

        for (int i = 0; i < subdividedTriangles.Count; i++)
        {
            var tri = subdividedTriangles[i];
            Vector2[] triPts = { tri.A, tri.B, tri.C };

            for (int j = 0; j < 3; j++)
            {
                int idx = i * 3 + j;
                float vx = triPts[j].X;
                float vz = triPts[j].Y;

                // Calculate how far this vertex is from the polygon boundary
                float distToEdge = DistanceToPolygon(new Vector2(vx, vz), points);

                // Smoothstep taper: 0 at edge, 1 at taperWidth inside
                float taperFactor = 1.0f;
                if (taperWidth > 0.0f && distToEdge < taperWidth)
                {
                    float t = distToEdge / taperWidth;
                    taperFactor = t * t * (3.0f - 2.0f * t);
                }

                float vy = GetHeight(vx, vz) + height * taperFactor;
                vertices[idx] = new Vector3(vx, vy, vz);
                normals[idx] = GetTerrainNormal(vx, vz);
                colors[idx] = color;
                uvs[idx] = triPts[j] * 0.1f;
                newIndices[idx] = idx;
            }
        }

        // Compute boundary normals
        float areaSum = 0.0f;
        for (int i = 0; i < M; i++)
        {
            var p1 = points[i];
            var p2 = points[(i + 1) % M];
            areaSum += (p2.X - p1.X) * (p2.Y + p1.Y);
        }
        bool isClockwise = areaSum > 0.0f;

        var normalsOut = new Vector2[M];
        for (int i = 0; i < M; i++)
        {
            int prev = (i - 1 + M) % M;
            int next = (i + 1) % M;

            var diff1 = points[i] - points[prev];
            var diff2 = points[next] - points[i];

            var t1 = diff1.LengthSquared() > 0.0001f ? diff1.Normalized() : Vector2.Zero;
            var t2 = diff2.LengthSquared() > 0.0001f ? diff2.Normalized() : Vector2.Zero;

            Vector2 tangent;
            if (t1 == Vector2.Zero && t2 == Vector2.Zero)
            {
                tangent = Vector2.Right;
            }
            else if (t1 == Vector2.Zero)
            {
                tangent = t2;
            }
            else if (t2 == Vector2.Zero)
            {
                tangent = t1;
            }
            else
            {
                var sum = t1 + t2;
                tangent = sum.LengthSquared() < 0.0001f ? t1 : sum.Normalized();
            }

            Vector2 normal = isClockwise 
                ? new Vector2(-tangent.Y, tangent.X) 
                : new Vector2(tangent.Y, -tangent.X);
            normalsOut[i] = normal.Normalized();
        }

        // Tiny outward skirt just to tuck the edge under the rough mesh
        // The real transition happens via the inward taper above
        float rampWidth = golfType switch
        {
            "water" => 0.05f,
            _ => 0.3f
        };

        float bottomDrop = golfType switch
        {
            "water" => 2.5f,
            "bunker" => 0.10f,
            _ => 0.08f
        };

        for (int i = 0; i < M; i++)
        {
            int next = (i + 1) % M;

            var n_i = normalsOut[i];
            var n_next = normalsOut[next];

            var p_top_i = points[i];
            var p_top_next = points[next];
            var p_mid_i = points[i] + n_i * (rampWidth * 0.5f);
            var p_mid_next = points[next] + n_next * (rampWidth * 0.5f);
            var p_bot_i = points[i] + n_i * rampWidth;
            var p_bot_next = points[next] + n_next * rampWidth;

            // Top: at rough ground level (tapered edge height is ~0 offset)
            var v_top_i = new Vector3(p_top_i.X, GetHeight(p_top_i.X, p_top_i.Y), p_top_i.Y);
            var v_top_next = new Vector3(p_top_next.X, GetHeight(p_top_next.X, p_top_next.Y), p_top_next.Y);

            // Mid: slightly below rough ground
            var v_mid_i = new Vector3(p_mid_i.X, GetHeight(p_mid_i.X, p_mid_i.Y) - bottomDrop * 0.5f, p_mid_i.Y);
            var v_mid_next = new Vector3(p_mid_next.X, GetHeight(p_mid_next.X, p_mid_next.Y) - bottomDrop * 0.5f, p_mid_next.Y);

            // Bottom: just below rough ground to hide the seam
            var v_bot_i = new Vector3(p_bot_i.X, GetHeight(p_bot_i.X, p_bot_i.Y) - bottomDrop, p_bot_i.Y);
            var v_bot_next = new Vector3(p_bot_next.X, GetHeight(p_bot_next.X, p_bot_next.Y) - bottomDrop, p_bot_next.Y);

            var norm_top_i = GetTerrainNormal(p_top_i.X, p_top_i.Y);
            var norm_top_next = GetTerrainNormal(p_top_next.X, p_top_next.Y);
            var norm_mid_i = GetTerrainNormal(p_mid_i.X, p_mid_i.Y);
            var norm_mid_next = GetTerrainNormal(p_mid_next.X, p_mid_next.Y);
            var norm_bot_i = GetTerrainNormal(p_bot_i.X, p_bot_i.Y);
            var norm_bot_next = GetTerrainNormal(p_bot_next.X, p_bot_next.Y);

            var uv_top_i = p_top_i * 0.1f;
            var uv_top_next = p_top_next * 0.1f;
            var uv_mid_i = p_mid_i * 0.1f;
            var uv_mid_next = p_mid_next * 0.1f;
            var uv_bot_i = p_bot_i * 0.1f;
            var uv_bot_next = p_bot_next * 0.1f;

            int baseIdx = numTopVertices + i * 12;

            // UPPER SKIRT (zone surface → mid slope)
            // Triangle 1: V_top_i, V_top_next, V_mid_i
            vertices[baseIdx] = v_top_i;
            normals[baseIdx] = norm_top_i;
            colors[baseIdx] = color;
            uvs[baseIdx] = uv_top_i;
            newIndices[baseIdx] = baseIdx;

            vertices[baseIdx + 1] = v_top_next;
            normals[baseIdx + 1] = norm_top_next;
            colors[baseIdx + 1] = color;
            uvs[baseIdx + 1] = uv_top_next;
            newIndices[baseIdx + 1] = baseIdx + 1;

            vertices[baseIdx + 2] = v_mid_i;
            normals[baseIdx + 2] = norm_mid_i;
            colors[baseIdx + 2] = color;
            uvs[baseIdx + 2] = uv_mid_i;
            newIndices[baseIdx + 2] = baseIdx + 2;

            // Triangle 2: V_top_next, V_mid_next, V_mid_i
            vertices[baseIdx + 3] = v_top_next;
            normals[baseIdx + 3] = norm_top_next;
            colors[baseIdx + 3] = color;
            uvs[baseIdx + 3] = uv_top_next;
            newIndices[baseIdx + 3] = baseIdx + 3;

            vertices[baseIdx + 4] = v_mid_next;
            normals[baseIdx + 4] = norm_mid_next;
            colors[baseIdx + 4] = color;
            uvs[baseIdx + 4] = uv_mid_next;
            newIndices[baseIdx + 4] = baseIdx + 4;

            vertices[baseIdx + 5] = v_mid_i;
            normals[baseIdx + 5] = norm_mid_i;
            colors[baseIdx + 5] = color;
            uvs[baseIdx + 5] = uv_mid_i;
            newIndices[baseIdx + 5] = baseIdx + 5;

            // LOWER SKIRT (mid slope → below rough ground)
            // Triangle 3: V_mid_i, V_mid_next, V_bot_i
            vertices[baseIdx + 6] = v_mid_i;
            normals[baseIdx + 6] = norm_mid_i;
            colors[baseIdx + 6] = color;
            uvs[baseIdx + 6] = uv_mid_i;
            newIndices[baseIdx + 6] = baseIdx + 6;

            vertices[baseIdx + 7] = v_mid_next;
            normals[baseIdx + 7] = norm_mid_next;
            colors[baseIdx + 7] = color;
            uvs[baseIdx + 7] = uv_mid_next;
            newIndices[baseIdx + 7] = baseIdx + 7;

            vertices[baseIdx + 8] = v_bot_i;
            normals[baseIdx + 8] = norm_bot_i;
            colors[baseIdx + 8] = color;
            uvs[baseIdx + 8] = uv_bot_i;
            newIndices[baseIdx + 8] = baseIdx + 8;

            // Triangle 4: V_mid_next, V_bot_next, V_bot_i
            vertices[baseIdx + 9] = v_mid_next;
            normals[baseIdx + 9] = norm_mid_next;
            colors[baseIdx + 9] = color;
            uvs[baseIdx + 9] = uv_mid_next;
            newIndices[baseIdx + 9] = baseIdx + 9;

            vertices[baseIdx + 10] = v_bot_next;
            normals[baseIdx + 10] = norm_bot_next;
            colors[baseIdx + 10] = color;
            uvs[baseIdx + 10] = uv_bot_next;
            newIndices[baseIdx + 10] = baseIdx + 10;

            vertices[baseIdx + 11] = v_bot_i;
            normals[baseIdx + 11] = norm_bot_i;
            colors[baseIdx + 11] = color;
            uvs[baseIdx + 11] = uv_bot_i;
            newIndices[baseIdx + 11] = baseIdx + 11;
        }

        var arr = new Godot.Collections.Array();
        arr.Resize((int)Mesh.ArrayType.Max);
        arr[(int)Mesh.ArrayType.Vertex] = vertices;
        arr[(int)Mesh.ArrayType.Normal] = normals;
        arr[(int)Mesh.ArrayType.Color] = colors;
        arr[(int)Mesh.ArrayType.TexUV] = uvs;
        arr[(int)Mesh.ArrayType.Index] = newIndices;

        arrayMesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arr);

        if (golfType == "water")
        {
            var shaderMat = new ShaderMaterial
            {
                Shader = GD.Load<Shader>("res://Courses/Environments/shaders/water_shader.gdshader")
            };
            
            shaderMat.SetShaderParameter("shallow_color", new Color(0.22f, 0.66f, 1.0f));
            shaderMat.SetShaderParameter("deep_color", new Color(0.01f, 0.15f, 0.3f));
            shaderMat.SetShaderParameter("absorbance", 2.0f);
            shaderMat.SetShaderParameter("depth_fade_distance", 1.0f);
            shaderMat.SetShaderParameter("roughness", 0.08f);
            
            var waveNoise = new FastNoiseLite
            {
                NoiseType = FastNoiseLite.NoiseTypeEnum.Simplex,
                Frequency = 0.03f
            };
            var waveNoiseTex = new NoiseTexture2D
            {
                Noise = waveNoise,
                Seamless = true
            };
            
            var normalNoise = new FastNoiseLite
            {
                NoiseType = FastNoiseLite.NoiseTypeEnum.Simplex,
                Frequency = 0.05f
            };
            var normalNoiseTex1 = new NoiseTexture2D
            {
                Noise = normalNoise,
                Seamless = true,
                AsNormalMap = true,
                BumpStrength = 2.0f
            };
            var normalNoiseTex2 = new NoiseTexture2D
            {
                Noise = normalNoise,
                Seamless = true,
                AsNormalMap = true,
                BumpStrength = 1.5f
            };
            
            shaderMat.SetShaderParameter("wave_texture", waveNoiseTex);
            shaderMat.SetShaderParameter("normal1", normalNoiseTex1);
            shaderMat.SetShaderParameter("normal2", normalNoiseTex2);
            shaderMat.SetShaderParameter("wave_speed", 0.015f);
            shaderMat.SetShaderParameter("wave_scale", 10.0f);
            shaderMat.SetShaderParameter("height_scale", 0.1f);
            
            arrayMesh.SurfaceSetMaterial(0, shaderMat);
            return arrayMesh;
        }

        Material mat;
        if (golfType == "green" || golfType == "tee")
        {
            mat = CreateGrassShaderMaterial("res://Courses/Environments/grass-green/albedo.png", 1, 0.0f, 0.0f, new Color(1f, 1f, 1f), 0.85f);
        }
        else if (golfType == "fairway")
        {
            mat = CreateGrassShaderMaterial("res://Courses/Environments/grass-fairway/albedo.png", 10, 0.06f, 0.4f, new Color(1f, 1f, 1f), 0.9f);
        }
        else if (golfType == "bunker")
        {
            mat = new StandardMaterial3D
            {
                VertexColorUseAsAlbedo = true,
                AlbedoTexture = GD.Load<Texture2D>("res://Courses/Environments/sand-bunker/albedo.png"),
                NormalEnabled = true,
                NormalTexture = GD.Load<Texture2D>("res://Courses/Environments/sand-bunker/normal.png"),
                RoughnessTexture = GD.Load<Texture2D>("res://Courses/Environments/sand-bunker/roughness.png"),
                AOEnabled = true,
                AOTexture = GD.Load<Texture2D>("res://Courses/Environments/sand-bunker/ao.png"),
                NormalScale = 0.5f,
                Roughness = 0.8f,
                Uv1Scale = new Vector3(6f, 6f, 6f)
            };
        }
        else
        {
            mat = new StandardMaterial3D
            {
                VertexColorUseAsAlbedo = true,
                Roughness = 0.8f
            };
        }

        arrayMesh.SurfaceSetMaterial(0, mat);

        return arrayMesh;
    }

    private ShaderMaterial CreateGrassShaderMaterial(string albedoPath, int layers, float depthScale, float depthStrength, Color tintColor, float roughness = 0.8f)
    {
        if (OS.GetName() == "Android" || OS.GetName() == "iOS")
        {
            layers = 1;
            depthScale = 0.0f;
        }

        var shader = GD.Load<Shader>("res://Courses/Environments/shaders/parallax_turf.gdshader");
        var mat = new ShaderMaterial();
        mat.Shader = shader;
        mat.SetShaderParameter("albedo_tex", GD.Load<Texture2D>(albedoPath));
        
        var noise = new FastNoiseLite();
        noise.NoiseType = FastNoiseLite.NoiseTypeEnum.Simplex;
        noise.Frequency = 0.4f;

        var noiseTex = new NoiseTexture2D();
        noiseTex.Noise = noise;
        noiseTex.Seamless = true;

        mat.SetShaderParameter("noise_texture", noiseTex);
        mat.SetShaderParameter("layers", layers);
        mat.SetShaderParameter("depth_scale", depthScale);
        mat.SetShaderParameter("depth_strength", depthStrength);
        mat.SetShaderParameter("grass_color_tint", tintColor);
        mat.SetShaderParameter("roughness", roughness);

        return mat;
    }

    private class ElevationMap
    {
        public int Width { get; set; }
        public int Height { get; set; }
        public double LeftLon { get; set; }
        public double RightLon { get; set; }
        public double TopLat { get; set; }
        public double BottomLat { get; set; }
        public float[] Data { get; set; } = Array.Empty<float>();
        public float Offset { get; set; }
    }

    private int LonToTileX(double lon, int zoom)
    {
        return (int)Math.Floor((lon + 180.0) / 360.0 * (1 << zoom));
    }

    private int LatToTileY(double lat, int zoom)
    {
        double latRad = lat * Math.PI / 180.0;
        return (int)Math.Floor((1.0 - Math.Log(Math.Tan(latRad) + 1.0 / Math.Cos(latRad)) / Math.PI) / 2.0 * (1 << zoom));
    }

    private double TileXToLon(int x, int zoom)
    {
        return x / (double)(1 << zoom) * 360.0 - 180.0;
    }

    private double TileYToLat(int y, int zoom)
    {
        double n = Math.PI - 2.0 * Math.PI * y / (double)(1 << zoom);
        return 180.0 / Math.PI * Math.Atan(0.5 * (Math.Exp(n) - Math.Exp(-n)));
    }

    private async Task<float[]?> DownloadUsgsElevationAsync(BBox bbox, double leftLon, double rightLon, double topLat, double bottomLat, int width, int height)
    {
        string bboxStr = string.Format(System.Globalization.CultureInfo.InvariantCulture, "{0:F7},{1:F7},{2:F7},{3:F7}", leftLon, bottomLat, rightLon, topLat);
        string url = $"https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/exportImage?bbox={bboxStr}&bboxSR=4326&size={width},{height}&imageSR=3857&format=bip&pixelType=F32&f=image";

        GD.Print($"{LogPrefix} Attempting to fetch USGS 3DEP elevation data: size {width}x{height}, bbox {bboxStr}");
        try
        {
            var response = await HttpClient.GetAsync(url);
            if (!response.IsSuccessStatusCode)
            {
                GD.Print($"{LogPrefix} USGS 3DEP request returned status: {response.StatusCode}.");
                return null;
            }

            byte[] bytes = await response.Content.ReadAsByteArrayAsync();
            int expectedFloatBytes = width * height * 4;
            if (bytes.Length < expectedFloatBytes)
            {
                GD.Print($"{LogPrefix} USGS response byte array too small ({bytes.Length} < {expectedFloatBytes}).");
                return null;
            }

            float[] elevationData = new float[width * height];
            Buffer.BlockCopy(bytes, 0, elevationData, 0, expectedFloatBytes);

            // Check for NoData values
            int checkCount = 0;
            int noDataCount = 0;
            int step = Math.Max(1, elevationData.Length / 100);
            for (int i = 0; i < elevationData.Length; i += step)
            {
                checkCount++;
                if (elevationData[i] < -9000f || float.IsNaN(elevationData[i]) || elevationData[i] > 10000f)
                {
                    noDataCount++;
                }
            }

            if (noDataCount > checkCount * 0.5)
            {
                GD.Print($"{LogPrefix} USGS returned mostly NoData values (presumably outside the US).");
                return null;
            }

            GD.Print($"{LogPrefix} Successfully downloaded USGS 3DEP elevation data!");
            return elevationData;
        }
        catch (Exception ex)
        {
            GD.Print($"{LogPrefix} Exception querying USGS 3DEP: {ex.Message}");
            return null;
        }
    }

    private async Task DownloadElevationDataAsync(BBox bbox, string globalCourseDir)
    {
        string elevationPath = Path.Combine(globalCourseDir, "elevation.dat");
        GD.Print($"{LogPrefix} Downloading elevation data for bbox: Lon[{bbox.LonMin}, {bbox.LonMax}], Lat[{bbox.LatMin}, {bbox.LatMax}]");

        int z = 15;
        int minTileX = LonToTileX(bbox.LonMin, z);
        int maxTileX = LonToTileX(bbox.LonMax, z);
        int minTileY = LatToTileY(bbox.LatMax, z);
        int maxTileY = LatToTileY(bbox.LatMin, z);

        int numTilesX = maxTileX - minTileX + 1;
        int numTilesY = maxTileY - minTileY + 1;

        if (numTilesX > 10 || numTilesY > 10)
        {
            GD.PrintErr($"{LogPrefix} Elevation bbox spans too many tiles ({numTilesX}x{numTilesY}). Aborting.");
            return;
        }

        int widthPixels = numTilesX * 256;
        int heightPixels = numTilesY * 256;

        double leftLon = TileXToLon(minTileX, z);
        double rightLon = TileXToLon(maxTileX + 1, z);
        double topLat = TileYToLat(minTileY, z);
        double bottomLat = TileYToLat(maxTileY + 1, z);

        float[]? elevationData = await DownloadUsgsElevationAsync(bbox, leftLon, rightLon, topLat, bottomLat, widthPixels, heightPixels);

        if (elevationData == null)
        {
            GD.Print($"{LogPrefix} USGS 3DEP not available or failed. Falling back to S3 Terrain Tiles.");
            elevationData = new float[widthPixels * heightPixels];

            for (int ty = minTileY; ty <= maxTileY; ty++)
            {
                for (int tx = minTileX; tx <= maxTileX; tx++)
                {
                    string url = $"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{tx}/{ty}.png";
                    try
                    {
                        var response = await HttpClient.GetAsync(url);
                        if (!response.IsSuccessStatusCode)
                        {
                            GD.PrintErr($"{LogPrefix} Failed to download elevation tile {tx},{ty}: {response.StatusCode}");
                            continue;
                        }

                        byte[] pngBytes = await response.Content.ReadAsByteArrayAsync();
                        var img = new Image();
                        var err = img.LoadPngFromBuffer(pngBytes);
                        if (err != Error.Ok)
                        {
                            GD.PrintErr($"{LogPrefix} Failed to parse elevation tile PNG {tx},{ty}: {err}");
                            continue;
                        }

                        int startX = (tx - minTileX) * 256;
                        int startY = (ty - minTileY) * 256;

                        for (int py = 0; py < 256; py++)
                        {
                            for (int px = 0; px < 256; px++)
                            {
                                Color c = img.GetPixel(px, py);
                                float r = c.R * 255.0f;
                                float g = c.G * 255.0f;
                                float b = c.B * 255.0f;
                                float h = (r * 256.0f) + g + (b / 256.0f) - 32768.0f;

                                int destX = startX + px;
                                int destY = startY + py;
                                elevationData[destY * widthPixels + destX] = h;
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        GD.PrintErr($"{LogPrefix} Exception downloading elevation tile {tx},{ty}: {ex.Message}");
                    }
                }
            }
        }

        try
        {
            using (var stream = File.OpenWrite(elevationPath))
            using (var writer = new BinaryWriter(stream))
            {
                writer.Write(2); // Version 2
                writer.Write(widthPixels);
                writer.Write(heightPixels);
                writer.Write(leftLon);
                writer.Write(rightLon);
                writer.Write(topLat);
                writer.Write(bottomLat);
                writer.Write(bbox.RefLat);
                writer.Write(bbox.RefLon);
                writer.Write(bbox.MetersPerLat);
                writer.Write(bbox.MetersPerLon);
                
                float rawCenterHeight = SampleRawHeightFromGrid(bbox.RefLat, bbox.RefLon, leftLon, rightLon, topLat, bottomLat, elevationData, widthPixels, heightPixels);
                writer.Write(rawCenterHeight); // Offset

                for (int i = 0; i < elevationData.Length; i++)
                {
                    writer.Write(elevationData[i]);
                }
            }
            GD.Print($"{LogPrefix} Successfully saved elevation data to: {elevationPath}");
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Failed to write elevation file: {ex.Message}");
        }
    }

    private void LoadElevationMap(string elevationPath, double refLat, double refLon, double metersPerLat, double metersPerLon)
    {
        _currentElevationMap = null;
        if (!File.Exists(elevationPath))
        {
            GD.Print($"{LogPrefix} Elevation file not found: {elevationPath}. Falling back to procedural elevation.");
            return;
        }

        try
        {
            using (var stream = File.OpenRead(elevationPath))
            using (var reader = new BinaryReader(stream))
            {
                int version = reader.ReadInt32();
                if (version != 2)
                {
                    GD.PrintErr($"{LogPrefix} Unsupported elevation file version: {version}");
                    return;
                }

                int w = reader.ReadInt32();
                int h = reader.ReadInt32();
                double leftLon = reader.ReadDouble();
                double rightLon = reader.ReadDouble();
                double topLat = reader.ReadDouble();
                double bottomLat = reader.ReadDouble();
                double rLat = reader.ReadDouble();
                double rLon = reader.ReadDouble();
                double mPerLat = reader.ReadDouble();
                double mPerLon = reader.ReadDouble();
                float offset = reader.ReadSingle();

                float[] data = new float[w * h];
                for (int i = 0; i < data.Length; i++)
                {
                    data[i] = reader.ReadSingle();
                }

                _currentElevationMap = new ElevationMap
                {
                    Width = w,
                    Height = h,
                    LeftLon = leftLon,
                    RightLon = rightLon,
                    TopLat = topLat,
                    BottomLat = bottomLat,
                    Data = data,
                    Offset = offset
                };

                GD.Print($"{LogPrefix} Loaded elevation map: {w}x{h}, center offset subtracted: {offset} meters.");
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Failed to load elevation map: {ex.Message}");
            _currentElevationMap = null;
        }
    }

    private float SampleRawHeight(double lat, double lon)
    {
        if (_currentElevationMap == null) return 0f;

        double leftLon = _currentElevationMap.LeftLon;
        double rightLon = _currentElevationMap.RightLon;
        double topLat = _currentElevationMap.TopLat;
        double bottomLat = _currentElevationMap.BottomLat;

        double u = (lon - leftLon) / (rightLon - leftLon);
        
        double MercatorY(double l)
        {
            return Math.Log(Math.Tan(l * Math.PI / 360.0 + Math.PI / 4.0));
        }

        double yVal = MercatorY(lat);
        double yTop = MercatorY(topLat);
        double yBottom = MercatorY(bottomLat);
        double v = (yVal - yTop) / (yBottom - yTop);

        u = Math.Clamp(u, 0.0, 1.0);
        v = Math.Clamp(v, 0.0, 1.0);

        int w = _currentElevationMap.Width;
        int h = _currentElevationMap.Height;

        float sampleX = (float)(u * (w - 1));
        float sampleY = (float)(v * (h - 1));

        int x0 = Math.Clamp((int)Math.Floor(sampleX), 0, w - 1);
        int x1 = Math.Clamp(x0 + 1, 0, w - 1);
        int y0 = Math.Clamp((int)Math.Floor(sampleY), 0, h - 1);
        int y1 = Math.Clamp(y0 + 1, 0, h - 1);

        float tx = sampleX - x0;
        float ty = sampleY - y0;

        float[] data = _currentElevationMap.Data;
        float h00 = data[y0 * w + x0];
        float h10 = data[y0 * w + x1];
        float h01 = data[y1 * w + x0];
        float h11 = data[y1 * w + x1];

        float h0 = h00 * (1f - tx) + h10 * tx;
        float h1 = h01 * (1f - tx) + h11 * tx;
        return h0 * (1f - ty) + h1 * ty;
    }

    private static float SampleRawHeightFromGrid(double lat, double lon, double leftLon, double rightLon, double topLat, double bottomLat, float[] data, int w, int h)
    {
        double u = (lon - leftLon) / (rightLon - leftLon);
        
        double MercatorY(double l)
        {
            return Math.Log(Math.Tan(l * Math.PI / 360.0 + Math.PI / 4.0));
        }

        double yVal = MercatorY(lat);
        double yTop = MercatorY(topLat);
        double yBottom = MercatorY(bottomLat);
        double v = (yVal - yTop) / (yBottom - yTop);

        u = Math.Clamp(u, 0.0, 1.0);
        v = Math.Clamp(v, 0.0, 1.0);

        float sampleX = (float)(u * (w - 1));
        float sampleY = (float)(v * (h - 1));

        int x0 = Math.Clamp((int)Math.Floor(sampleX), 0, w - 1);
        int x1 = Math.Clamp(x0 + 1, 0, w - 1);
        int y0 = Math.Clamp((int)Math.Floor(sampleY), 0, h - 1);
        int y1 = Math.Clamp(y0 + 1, 0, h - 1);

        float tx = sampleX - x0;
        float ty = sampleY - y0;

        float h00 = data[y0 * w + x0];
        float h10 = data[y0 * w + x1];
        float h01 = data[y1 * w + x0];
        float h11 = data[y1 * w + x1];

        float h0 = h00 * (1f - tx) + h10 * tx;
        float h1 = h01 * (1f - tx) + h11 * tx;
        return h0 * (1f - ty) + h1 * ty;
    }

    private List<Vector2> ResamplePath(List<Vector2> path, int numPoints)
    {
        if (path.Count < 2) return path;
        
        float totalLength = 0f;
        var segLengths = new float[path.Count - 1];
        for (int i = 0; i < path.Count - 1; i++)
        {
            segLengths[i] = path[i].DistanceTo(path[i+1]);
            totalLength += segLengths[i];
        }

        if (totalLength < 0.1f) return path;

        var resampled = new List<Vector2>();
        resampled.Add(path[0]);

        float step = totalLength / (numPoints - 1);
        int segIdx = 0;
        float segStartDist = 0f;

        for (int i = 1; i < numPoints - 1; i++)
        {
            float targetDist = i * step;
            while (segIdx < segLengths.Length && segStartDist + segLengths[segIdx] < targetDist)
            {
                segStartDist += segLengths[segIdx];
                segIdx++;
            }
            if (segIdx >= segLengths.Length) break;

            float t = (targetDist - segStartDist) / segLengths[segIdx];
            Vector2 p = path[segIdx] * (1f - t) + path[segIdx + 1] * t;
            resampled.Add(p);
        }

        resampled.Add(path[path.Count - 1]);
        return resampled;
    }

    private float GetHeight(float x, float z)
    {
        if (_currentElevationMap != null)
        {
            double lon = _refLon + x / _metersPerLon;
            double lat = _refLat - z / _metersPerLat;
            return SampleRawHeight(lat, lon) - _currentElevationMap.Offset;
        }

        // Multi-octave golf course procedural topography with rolling fairways, swales, mounds, and ridges
        double h = Math.Sin(x * 0.022 + z * 0.012) * Math.Cos(z * 0.025 - x * 0.015) * 7.5
                 + Math.Sin(x * 0.045 - z * 0.035) * 3.2
                 + Math.Cos(x * 0.085 + z * 0.065) * 1.6
                 + Math.Sin(x * 0.16 + z * 0.14) * 0.65;
        return (float)h;
    }

    private Vector3 GetTerrainNormal(float vx, float vz)
    {
        float hL = GetHeight(vx - 0.5f, vz);
        float hR = GetHeight(vx + 0.5f, vz);
        float hD = GetHeight(vx, vz - 0.5f);
        float hU = GetHeight(vx, vz + 0.5f);
        return new Vector3(hL - hR, 1.0f, hD - hU).Normalized();
    }

    private void CreateRoughGround(float minX, float maxX, float minZ, float maxZ, int subdivisionsX, int subdivisionsZ, Node3D root, List<ExclusionPolygon> exclusions)
    {
        var arrayMesh = new ArrayMesh();
        int numVertices = (subdivisionsX + 1) * (subdivisionsZ + 1);
        var vertices = new Vector3[numVertices];
        var normals = new Vector3[numVertices];
        var colors = new Color[numVertices];
        var uvs = new Vector2[numVertices];
        
        float width = maxX - minX;
        float depth = maxZ - minZ;
        float cellWidth = width / subdivisionsX;
        float cellDepth = depth / subdivisionsZ;
        float margin = Math.Max(cellWidth, cellDepth) * 1.2f;
        
        int idx = 0;
        for (int z = 0; z <= subdivisionsZ; z++)
        {
            for (int x = 0; x <= subdivisionsX; x++)
            {
                float vx = minX + x * cellWidth;
                float vz = minZ + z * cellDepth;
                float vy = GetHeight(vx, vz);
                
                bool isInsideWater = false;
                float distToWaterBoundary = 0f;
                bool isInsideBunker = false;
                float minDistBunker = float.MaxValue;
                var vertexPoint = new Vector2(vx, vz);
                
                foreach (var excl in exclusions)
                {
                    if (vx >= excl.MinX - margin && vx <= excl.MaxX + margin && vz >= excl.MinY - margin && vz <= excl.MaxY + margin)
                    {
                        bool isInside = Geometry2D.IsPointInPolygon(vertexPoint, excl.Polygon);
                        if (excl.GolfType == "water")
                        {
                            if (isInside)
                            {
                                isInsideWater = true;
                                float dist = DistanceToPolygon(vertexPoint, excl.Polygon);
                                if (dist > distToWaterBoundary) distToWaterBoundary = dist;
                            }
                        }
                        else if (excl.GolfType == "bunker")
                        {
                            if (isInside)
                            {
                                isInsideBunker = true;
                                minDistBunker = 0f;
                            }
                            else
                            {
                                float dist = DistanceToPolygon(vertexPoint, excl.Polygon);
                                if (dist < minDistBunker) minDistBunker = dist;
                            }
                        }
                    }
                }
                
                float depWater = 0f;
                if (isInsideWater)
                {
                    if (distToWaterBoundary < 15.0f)
                    {
                        float t = distToWaterBoundary / 15.0f;
                        float smoothT = t * t * (3.0f - 2.0f * t);
                        depWater = smoothT * 2.0f;
                    }
                    else
                    {
                        depWater = 2.0f;
                    }
                }
                
                float depBunker = 0f;
                if (isInsideBunker)
                {
                    depBunker = 0.45f;
                }
                else if (minDistBunker < 3.0f)
                {
                    float t = 1.0f - (minDistBunker / 3.0f);
                    float smoothT = t * t * (3.0f - 2.0f * t);
                    depBunker = smoothT * 0.45f;
                }
                
                float depPlay = 0f;
                
                float totalDep = Math.Max(depWater, Math.Max(depBunker, depPlay));
                vy -= totalDep;
                
                vertices[idx] = new Vector3(vx, vy, vz);
                
                float hL = GetHeight(vx - 1.0f, vz);
                float hR = GetHeight(vx + 1.0f, vz);
                float hD = GetHeight(vx, vz - 1.0f);
                float hU = GetHeight(vx, vz + 1.0f);
                var normal = new Vector3(hL - hR, 2.0f, hD - hU).Normalized();
                normals[idx] = normal;
                
                colors[idx] = new Color(0.35f, 0.65f, 0.35f);
                uvs[idx] = new Vector2(vx, vz) * 0.1f;
                idx++;
            }
        }
        
        var indicesList = new List<int>();
        for (int z = 0; z < subdivisionsZ; z++)
        {
            for (int x = 0; x < subdivisionsX; x++)
            {
                int row1 = z * (subdivisionsX + 1);
                int row2 = (z + 1) * (subdivisionsX + 1);
                
                indicesList.Add(row1 + x);
                indicesList.Add(row1 + x + 1);
                indicesList.Add(row2 + x);
                
                indicesList.Add(row1 + x + 1);
                indicesList.Add(row2 + x + 1);
                indicesList.Add(row2 + x);
            }
        }
        var indices = indicesList.ToArray();
        
        var arr = new Godot.Collections.Array();
        arr.Resize((int)Mesh.ArrayType.Max);
        arr[(int)Mesh.ArrayType.Vertex] = vertices;
        arr[(int)Mesh.ArrayType.Normal] = normals;
        arr[(int)Mesh.ArrayType.Color] = colors;
        arr[(int)Mesh.ArrayType.TexUV] = uvs;
        arr[(int)Mesh.ArrayType.Index] = indices;
        
        arrayMesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arr);
        
        var mat = CreateGrassShaderMaterial("res://Courses/Environments/grass-rough/albedo.png", 20, 0.18f, 0.4f, new Color(1f, 1f, 1f), 0.8f);
        arrayMesh.SurfaceSetMaterial(0, mat);
        
        var groundMesh = new MeshInstance3D
        {
            Name = "RoughGround",
            Mesh = arrayMesh
        };
        root.AddChild(groundMesh);
        groundMesh.Owner = root;
        
        var groundStatic = new StaticBody3D { Name = "RoughStatic" };
        groundStatic.SetMeta("surface_type", 2);
        
        var colShape = new CollisionShape3D();
        var concaveShape = new ConcavePolygonShape3D();
        
        var collisionVertices = new Vector3[indices.Length];
        for (int i = 0; i < indices.Length; i++)
        {
            collisionVertices[i] = vertices[indices[i]];
        }
        concaveShape.Data = collisionVertices;
        colShape.Shape = concaveShape;
        
        groundStatic.AddChild(colShape);
        root.AddChild(groundStatic);
        
        groundStatic.Owner = root;
        colShape.Owner = root;
    }

    private void AddTreeAt(Node3D root, Vector3 position)
    {
        // Seed Random deterministically using position hash so same tree always has same size
        int posHash = (int)(position.X * 1000f) ^ (int)(position.Z * 1000f);
        var random = new Random(posHash);
        
        string[] treePaths = new string[]
        {
            "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-01-1-staticbody.tscn",
            "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-01-2-staticbody.tscn",
            "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-01-3-staticbody.tscn",
            "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-01-4-staticbody.tscn",
            "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-02-1-staticbody.tscn",
            "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-02-2-staticbody.tscn",
            "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-02-3-staticbody.tscn",
            "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-02-4-staticbody.tscn",
            "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-03-1-staticbody.tscn",
            "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-03-2-staticbody.tscn",
            "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-03-3-staticbody.tscn",
            "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-03-4-staticbody.tscn"
        };
        
        int treeIndex = random.Next(treePaths.Length);
        
        try
        {
            var treeScene = GD.Load<PackedScene>(treePaths[treeIndex]);
            if (treeScene != null)
            {
                var treeInstance = treeScene.Instantiate<Node3D>();
                treeInstance.Name = $"Tree_{position.X:F1}_{position.Z:F1}";
                treeInstance.Position = position;
                
                // Random scale between 2.5 and 5.0 to make trees much larger
                float scaleVal = 2.5f + (float)random.NextDouble() * 2.5f;
                treeInstance.Scale = new Vector3(scaleVal, scaleVal, scaleVal);
                
                // Apply a random Y rotation for organic variety
                float rotationY = (float)(random.NextDouble() * Math.PI * 2.0);
                treeInstance.Rotation = new Vector3(0f, rotationY, 0f);
                
                root.AddChild(treeInstance);
                treeInstance.Owner = root;

                // Shrink and reposition the trunk collision shape so it doesn't extend into foliage
                foreach (Node child in treeInstance.GetChildren())
                {
                    if (child is CollisionShape3D colShapeNode)
                    {
                        if (colShapeNode.Shape is CapsuleShape3D capsule)
                        {
                            var newCapsule = (CapsuleShape3D)capsule.Duplicate();
                            newCapsule.Radius = 0.15f;
                            newCapsule.Height = 1.0f;
                            colShapeNode.Shape = newCapsule;
                            
                            colShapeNode.Transform = new Transform3D(Basis.Identity, new Vector3(0f, 0.5f, 0f));
                        }
                    }
                }

                // Create leaves/canopy Area3D to detect ball passing through
                var canopyArea = new Area3D();
                canopyArea.Name = "CanopyArea";
                canopyArea.SetMeta("is_canopy", true);

                var canopyShape = new CollisionShape3D();
                var sphereShape = new SphereShape3D();
                sphereShape.Radius = 1.8f;
                canopyShape.Shape = sphereShape;
                canopyShape.Position = new Vector3(0f, 3.8f, 0f);

                canopyArea.AddChild(canopyShape);
                treeInstance.AddChild(canopyArea);

                canopyArea.Owner = root;
                canopyShape.Owner = root;
            }
            else
            {
                GD.PrintErr($"{LogPrefix} Failed to load tree scene: {treePaths[treeIndex]}");
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Exception loading tree scene: {ex}");
        }
    }

    private void AddBushAt(Node3D root, Vector3 position)
    {
        int posHash = (int)(position.X * 1000f) ^ (int)(position.Z * 1000f);
        var random = new Random(posHash);
        
        string[] bushPaths = new string[]
        {
            "res://addons/shapespark-low-poly-exterior-plants/bodies/bush-01-staticbody.tscn",
            "res://addons/shapespark-low-poly-exterior-plants/bodies/bush-02-staticbody.tscn",
            "res://addons/shapespark-low-poly-exterior-plants/bodies/bush-03-staticbody.tscn",
            "res://addons/shapespark-low-poly-exterior-plants/bodies/bush-04-staticbody.tscn",
            "res://addons/shapespark-low-poly-exterior-plants/bodies/bush-05-staticbody.tscn"
        };
        
        int bushIndex = random.Next(bushPaths.Length);
        
        try
        {
            var bushScene = GD.Load<PackedScene>(bushPaths[bushIndex]);
            if (bushScene != null)
            {
                var bushInstance = bushScene.Instantiate<Node3D>();
                bushInstance.Name = $"Bush_{position.X:F1}_{position.Z:F1}";
                bushInstance.Position = position;
                
                // Random scale between 1.0 and 2.2 for varied bush sizes
                float scaleVal = 1.0f + (float)random.NextDouble() * 1.2f;
                bushInstance.Scale = new Vector3(scaleVal, scaleVal, scaleVal);
                
                // Apply a random Y rotation for organic variety
                float rotationY = (float)(random.NextDouble() * Math.PI * 2.0);
                bushInstance.Rotation = new Vector3(0f, rotationY, 0f);
                
                root.AddChild(bushInstance);
                bushInstance.Owner = root;
            }
            else
            {
                GD.PrintErr($"{LogPrefix} Failed to load bush scene: {bushPaths[bushIndex]}");
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Exception loading bush scene: {ex}");
        }
    }

    private static string GetHoleKey(string refVal)
    {
        if (int.TryParse(refVal, out var holeInt))
        {
            return $"Hole {holeInt:D2}";
        }
        return $"Hole {refVal}";
    }

    private record OsmWay(long Id, List<long> NodeIds, Dictionary<string, string> Tags);
    private record OsmRelation(long Id, List<(string Type, long Ref, string Role)> Members, Dictionary<string, string> Tags);
    
    private class CourseJsonConfig
    {
        [JsonPropertyName("scene_path")]
        public string ScenePath { get; set; } = "course.tscn";

        [JsonPropertyName("Title")]
        public string Title { get; set; } = "";

        [JsonPropertyName("Course Info")]
        public CourseInfoConfig CourseInfo { get; set; } = new();

        [JsonPropertyName("Hole Info")]
        public Dictionary<string, HoleConfig> HoleInfo { get; set; } = new();
    }

    private class CourseInfoConfig
    {
        [JsonPropertyName("Tee Colors")]
        public List<string> TeeColors { get; set; } = new();
    }

    private class HoleConfig
    {
        [JsonPropertyName("Par")]
        public int Par { get; set; }

        [JsonPropertyName("Distance")]
        public float Distance { get; set; }

        [JsonPropertyName("Handicap")]
        public int Handicap { get; set; }

        [JsonPropertyName("Name")]
        public string Name { get; set; } = "";

        [JsonPropertyName("Hole Location")]
        public float[] HoleLocation { get; set; } = new float[2];

        [JsonPropertyName("Tee Boxes")]
        public Dictionary<string, float[]> TeeBoxes { get; set; } = new();

        [JsonPropertyName("Hole Path")]
        public List<float[]> HolePath { get; set; } = new();
    }

    private class TeeConfig
    {
        public string HoleNum { get; set; } = "1";
        public string Color { get; set; } = "blue";
        public float[] Location { get; set; } = new float[2];
    }

    private class ExclusionPolygon
    {
        public Vector2[] Polygon;
        public float MinX;
        public float MaxX;
        public float MinY;
        public float MaxY;
        public string? GolfType;
        public float? AverageHeight;

        public ExclusionPolygon(Vector2[] polygon, string? golfType = "", OsmMapLoader? loader = null)
        {
            Polygon = polygon;
            GolfType = golfType;
            MinX = float.MaxValue;
            MaxX = float.MinValue;
            MinY = float.MaxValue;
            MaxY = float.MinValue;
            float sum = 0f;
            foreach (var p in polygon)
            {
                if (p.X < MinX) MinX = p.X;
                if (p.X > MaxX) MaxX = p.X;
                if (p.Y < MinY) MinY = p.Y;
                if (p.Y > MaxY) MaxY = p.Y;
                if (loader != null)
                {
                    sum += loader.GetHeight(p.X, p.Y);
                }
            }
            if (loader != null && polygon.Length > 0 && (golfType == "tee" || golfType == "green"))
            {
                AverageHeight = sum / polygon.Length;
            }
        }
    }

    private class SubdivisionTriangle
    {
        public Vector2 A;
        public Vector2 B;
        public Vector2 C;

        public SubdivisionTriangle(Vector2 a, Vector2 b, Vector2 c)
        {
            A = a;
            B = b;
            C = c;
        }
    }

    private static void ColorToHsv(Color color, out float h, out float s, out float v)
    {
        float r = color.R;
        float g = color.G;
        float b = color.B;

        float max = Math.Max(r, Math.Max(g, b));
        float min = Math.Min(r, Math.Min(g, b));
        float delta = max - min;

        v = max;

        if (max > 0.0f)
        {
            s = delta / max;
        }
        else
        {
            s = 0.0f;
            h = 0.0f;
            return;
        }

        if (delta > 0.0f)
        {
            if (max == r)
            {
                h = (g - b) / delta + (g < b ? 6.0f : 0.0f);
            }
            else if (max == g)
            {
                h = (b - r) / delta + 2.0f;
            }
            else
            {
                h = (r - g) / delta + 4.0f;
            }
            h /= 6.0f;
        }
        else
        {
            h = 0.0f;
        }
    }

    private bool IsTreeColor(Color color)
    {
        float r = color.R;
        float g = color.G;
        float b = color.B;

        ColorToHsv(color, out float h, out float s, out float v);

        // Profile 1: Standard / Bright Green Foliage (deciduous, fairway borders, sunlit canopies)
        // Hue: yellow-green to cyan-green (36° to 175°)
        bool isGreenish = (h >= 0.10f && h <= 0.48f) && (s > 0.08f);
        bool isGreenBrightness = (v > 0.03f && v < 0.60f);
        float exG = 2.0f * g - r - b;
        bool hasExG = exG > -0.05f; // Tolerant to varied lighting
        if (isGreenish && isGreenBrightness && hasExG)
        {
            return true;
        }

        // Profile 2: Dark / Conifer / Evergreen / Shadow Canopy (pine, spruce, cedar, deep forest)
        bool isDarkCanopy = (v >= 0.02f && v <= 0.35f) && (s > 0.06f);
        bool isConiferTone = (g >= b * 0.85f) && (g >= r * 0.75f);
        if (isDarkCanopy && isConiferTone)
        {
            return true;
        }

        // Profile 3: Olive / Arid / Autumn / Sunlit warm foliage
        bool isOliveHue = (h >= 0.07f && h <= 0.22f) && (s > 0.08f);
        bool isOliveBrightness = (v > 0.05f && v < 0.55f);
        bool isOliveTone = (g > b * 0.95f) && (g + r > 2.0f * b);
        if (isOliveHue && isOliveBrightness && isOliveTone)
        {
            return true;
        }

        return false;
    }

    private float GetLocalVariance(Image img, int cx, int cy)
    {
        float vSum = 0.0f;
        float vSqSum = 0.0f;
        int count = 0;
        int w = img.GetWidth();
        int h = img.GetHeight();

        for (int dy = -2; dy <= 2; dy++)
        {
            for (int dx = -2; dx <= 2; dx++)
            {
                int px = cx + dx;
                int py = cy + dy;
                if (px >= 0 && px < w && py >= 0 && py < h)
                {
                    Color c = img.GetPixel(px, py);
                    ColorToHsv(c, out _, out _, out float v);
                    vSum += v;
                    vSqSum += v * v;
                    count++;
                }
            }
        }
        float mean = vSum / count;
        return (vSqSum / count) - (mean * mean);
    }

    private Color GetAveragedPixel(Image img, int cx, int cy)
    {
        float rSum = 0f, gSum = 0f, bSum = 0f;
        int count = 0;
        int w = img.GetWidth();
        int h = img.GetHeight();

        for (int dy = -1; dy <= 1; dy++)
        {
            for (int dx = -1; dx <= 1; dx++)
            {
                int px = cx + dx;
                int py = cy + dy;
                if (px >= 0 && px < w && py >= 0 && py < h)
                {
                    Color c = img.GetPixel(px, py);
                    rSum += c.R;
                    gSum += c.G;
                    bSum += c.B;
                    count++;
                }
            }
        }
        return new Color(rSum / count, gSum / count, bSum / count);
    }

    private async Task<byte[]?> DownloadSatelliteImageAsync(double lonMin, double latMin, double lonMax, double latMax, int width = 2048, int height = 2048)
    {
        string bbox = string.Format(System.Globalization.CultureInfo.InvariantCulture, "{0:F6},{1:F6},{2:F6},{3:F6}", lonMin, latMin, lonMax, latMax);
        string url = $"https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?bbox={bbox}&bboxSR=4326&imageSR=4326&size={width},{height}&f=image&format=png";
        
        GD.Print($"{LogPrefix} Downloading satellite image for tree detection from: {url}");
        try
        {
            var response = await HttpClient.GetAsync(url);
            if (!response.IsSuccessStatusCode)
            {
                GD.PrintErr($"{LogPrefix} Satellite image download failed with status: {response.StatusCode}");
                return null;
            }
            return await response.Content.ReadAsByteArrayAsync();
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Failed to download satellite image: {ex}");
            return null;
        }
    }

    private class BBox
    {
        public double LonMin { get; set; }
        public double LatMin { get; set; }
        public double LonMax { get; set; }
        public double LatMax { get; set; }
        public double RefLat { get; set; }
        public double RefLon { get; set; }
        public double MetersPerLat { get; set; }
        public double MetersPerLon { get; set; }
    }

    private BBox? CalculateBBoxFromOsmJson(string jsonString, double lat, double lon)
    {
        try
        {
            using var doc = JsonDocument.Parse(jsonString);
            if (!doc.RootElement.TryGetProperty("elements", out var elements))
            {
                return null;
            }

            var nodes = new Dictionary<long, (double Lat, double Lon)>();
            var nodeTags = new Dictionary<long, Dictionary<string, string>>();
            var ways = new List<OsmWay>();
            var relations = new List<OsmRelation>();
            
            foreach (var element in elements.EnumerateArray())
            {
                string type = element.GetProperty("type").GetString() ?? "";
                long id = element.GetProperty("id").GetInt64();
                
                if (type == "node")
                {
                    double nLat = element.GetProperty("lat").GetDouble();
                    double nLon = element.GetProperty("lon").GetDouble();
                    nodes[id] = (nLat, nLon);

                    var tags = new Dictionary<string, string>();
                    if (element.TryGetProperty("tags", out var tagsProp))
                    {
                        foreach (var tag in tagsProp.EnumerateObject())
                        {
                            tags[tag.Name] = tag.Value.GetString() ?? "";
                        }
                    }
                    nodeTags[id] = tags;
                }
                else if (type == "way")
                {
                    var wayNodes = new List<long>();
                    if (element.TryGetProperty("nodes", out var nodesProp))
                    {
                        foreach (var nodeVal in nodesProp.EnumerateArray())
                        {
                            wayNodes.Add(nodeVal.GetInt64());
                        }
                    }

                    var tags = new Dictionary<string, string>();
                    if (element.TryGetProperty("tags", out var tagsProp))
                    {
                        foreach (var tag in tagsProp.EnumerateObject())
                        {
                            tags[tag.Name] = tag.Value.GetString() ?? "";
                        }
                    }

                    ways.Add(new OsmWay(id, wayNodes, tags));
                }
                else if (type == "relation")
                {
                    var members = new List<(string Type, long Ref, string Role)>();
                    if (element.TryGetProperty("members", out var membersProp))
                    {
                        foreach (var mVal in membersProp.EnumerateArray())
                        {
                            string mType = mVal.GetProperty("type").GetString() ?? "";
                            long mRef = mVal.GetProperty("ref").GetInt64();
                            string mRole = mVal.GetProperty("role").GetString() ?? "";
                            members.Add((mType, mRef, mRole));
                        }
                    }

                    var tags = new Dictionary<string, string>();
                    if (element.TryGetProperty("tags", out var tagsProp))
                    {
                        foreach (var tag in tagsProp.EnumerateObject())
                        {
                            tags[tag.Name] = tag.Value.GetString() ?? "";
                        }
                    }

                    relations.Add(new OsmRelation(id, members, tags));
                }
            }

            if (nodes.Count == 0) return null;

            double refLat = nodes.Values.Average(n => n.Lat);
            double refLon = nodes.Values.Average(n => n.Lon);
            double metersPerLat = 111320.0;
            double metersPerLon = 111320.0 * Math.Cos(refLat * Math.PI / 180.0);

            // Copy tags from relations to member ways and nodes
            foreach (var rel in relations)
            {
                var relTagsToCopy = new Dictionary<string, string>();
                foreach (var tag in rel.Tags)
                {
                    if (tag.Key == "golf" || tag.Key == "natural" || tag.Key == "landuse" || tag.Key == "leisure" || tag.Key == "ref" || tag.Key == "par" || tag.Key == "handicap" || tag.Key == "name")
                    {
                        relTagsToCopy[tag.Key] = tag.Value;
                    }
                }
                
                if (relTagsToCopy.Count > 0)
                {
                    foreach (var member in rel.Members)
                    {
                        if (member.Type == "way")
                        {
                            var targetWay = ways.FirstOrDefault(w => w.Id == member.Ref);
                            if (targetWay != null)
                            {
                                foreach (var kvp in relTagsToCopy)
                                {
                                    if (kvp.Key == "golf" && targetWay.Tags.ContainsKey("golf"))
                                        continue;
                                    targetWay.Tags[kvp.Key] = kvp.Value;
                                }
                            }
                        }
                        else if (member.Type == "node")
                        {
                            if (nodeTags.TryGetValue(member.Ref, out var targetNodeTags))
                            {
                                foreach (var kvp in relTagsToCopy)
                                {
                                    if (kvp.Key == "golf" && targetNodeTags.ContainsKey("golf"))
                                        continue;
                                    targetNodeTags[kvp.Key] = kvp.Value;
                                }
                            }
                        }
                    }
                }
            }

            // Find the main course boundary to filter out other golf courses in the radius
            double closestDist = double.MaxValue;
            OsmWay closestWay = null;
            OsmRelation closestRel = null;

            foreach (var way in ways)
            {
                if (way.Tags.TryGetValue("leisure", out var leisure) && leisure == "golf_course")
                {
                    var wayNodes = way.NodeIds.Where(nodes.ContainsKey).Select(id => nodes[id]).ToList();
                    if (wayNodes.Count > 0)
                    {
                        double avgLat = wayNodes.Average(n => n.Lat);
                        double avgLon = wayNodes.Average(n => n.Lon);
                        double dLat = avgLat - lat;
                        double dLon = avgLon - lon;
                        double dist = dLat * dLat + dLon * dLon;
                        if (dist < closestDist)
                        {
                            closestDist = dist;
                            closestWay = way;
                            closestRel = null;
                        }
                    }
                }
            }

            foreach (var rel in relations)
            {
                if (rel.Tags.TryGetValue("leisure", out var leisure) && leisure == "golf_course")
                {
                    var memberWays = rel.Members
                        .Where(m => m.Type == "way")
                        .Select(m => ways.FirstOrDefault(w => w.Id == m.Ref))
                        .Where(w => w != null)
                        .ToList();

                    var allNodeCoords = memberWays
                        .SelectMany(w => w.NodeIds)
                        .Where(nodes.ContainsKey)
                        .Select(id => nodes[id])
                        .ToList();

                    if (allNodeCoords.Count > 0)
                    {
                        double avgLat = allNodeCoords.Average(n => n.Lat);
                        double avgLon = allNodeCoords.Average(n => n.Lon);
                        double dLat = avgLat - lat;
                        double dLon = avgLon - lon;
                        double dist = dLat * dLat + dLon * dLon;
                        if (dist < closestDist)
                        {
                            closestDist = dist;
                            closestRel = rel;
                            closestWay = null;
                        }
                    }
                }
            }

            string targetCourseName = "";
            if (closestRel != null && closestRel.Tags.TryGetValue("name", out var relName))
            {
                targetCourseName = relName;
            }
            else if (closestWay != null && closestWay.Tags.TryGetValue("name", out var wayName))
            {
                targetCourseName = wayName;
            }

            // Gather all boundary polygons for golf courses with the same name, or just the closest one if nameless
            var coursePolygons = new List<Vector2[]>();
            
            var matchingWays = ways.Where(w => 
                w.Tags.TryGetValue("leisure", out var l) && l == "golf_course" &&
                (string.IsNullOrEmpty(targetCourseName) ? w == closestWay : (w.Tags.TryGetValue("name", out var n) && n == targetCourseName))
            ).ToList();

            foreach (var w in matchingWays)
            {
                var pts = w.NodeIds
                    .Where(nodes.ContainsKey)
                    .Select(id => nodes[id])
                    .Select(coord => new Vector2(
                        (float)((coord.Lon - refLon) * metersPerLon),
                        -(float)((coord.Lat - refLat) * metersPerLat)
                    ))
                    .ToArray();
                if (pts.Length >= 3)
                {
                    coursePolygons.Add(pts);
                }
            }

            var matchingRels = relations.Where(r => 
                r.Tags.TryGetValue("leisure", out var l) && l == "golf_course" &&
                (string.IsNullOrEmpty(targetCourseName) ? r == closestRel : (r.Tags.TryGetValue("name", out var n) && n == targetCourseName))
            ).ToList();

            foreach (var r in matchingRels)
            {
                var assembled = AssembleRelationPolygons(r, ways, nodes, refLat, refLon, metersPerLat, metersPerLon);
                coursePolygons.AddRange(assembled);
            }

            var lineOfPlayPaths = new List<List<Vector2>>();
            var exclusionPolygons = new List<ExclusionPolygon>();

            Func<Vector2, bool> isPointInMainCourse = (pt) => {
                if (coursePolygons.Count == 0) return true;
                foreach (var poly in coursePolygons)
                {
                    if (Geometry2D.IsPointInPolygon(pt, poly))
                        return true;
                    foreach (var vertex in poly)
                    {
                        if (pt.DistanceTo(vertex) < 60f)
                            return true;
                    }
                }
                for (int pIdx = 0; pIdx < lineOfPlayPaths.Count; pIdx++)
                {
                    var path = lineOfPlayPaths[pIdx];
                    for (int i = 0; i < path.Count - 1; i++)
                    {
                        if (DistanceToSegment(pt, path[i], path[i + 1]) < 90.0f)
                            return true;
                    }
                }
                for (int i = 0; i < exclusionPolygons.Count; i++)
                {
                    var excl = exclusionPolygons[i];
                    if (pt.X >= excl.MinX - 50f && pt.X <= excl.MaxX + 50f && pt.Y >= excl.MinY - 50f && pt.Y <= excl.MaxY + 50f)
                    {
                        if (PointInPolygon(pt, excl.Polygon)) return true;
                    }
                }
                return false;
            };

            foreach (var way in ways)
            {
                var points = way.NodeIds
                    .Where(nodes.ContainsKey)
                    .Select(id => nodes[id])
                    .Select(coord => new Vector2(
                        (float)((coord.Lon - refLon) * metersPerLon),
                        -(float)((coord.Lat - refLat) * metersPerLat)
                    ))
                    .ToList();

                if (points.Count < 2) continue;

                // Check if the way belongs to the main course
                var wayCenter = new Vector2(points.Average(p => p.X), points.Average(p => p.Y));
                if (!isPointInMainCourse(wayCenter))
                {
                    bool isMainBoundary = (way.Tags.TryGetValue("leisure", out var l) && l == "golf_course") || way.Tags.ContainsKey("golf");
                    if (!isMainBoundary)
                        continue;
                }

                way.Tags.TryGetValue("golf", out string? golfType);
                if (golfType == "hole")
                {
                    lineOfPlayPaths.Add(new List<Vector2>(points));
                    exclusionPolygons.Add(new ExclusionPolygon(points.ToArray()));
                    continue;
                }

                if (golfType == "tee")
                {
                    if (points.Count >= 3)
                    {
                        if (points.First() != points.Last())
                            points.Add(points.First());
                        var uniquePoints = points.Take(points.Count - 1).ToArray();
                        exclusionPolygons.Add(new ExclusionPolygon(uniquePoints));
                    }
                    continue;
                }

                if (points.Count < 3) continue;

                if (points.First() != points.Last())
                {
                    points.Add(points.First());
                }

                bool isGolfSurface = golfType == "fairway" || golfType == "green" || golfType == "bunker";
                bool isWaterFeature = (way.Tags.TryGetValue("natural", out string? natType) && natType == "water") ||
                                      golfType == "water_hazard" ||
                                      way.Tags.ContainsKey("water");

                if (isGolfSurface || isWaterFeature)
                {
                    var uniquePoints = points.Take(points.Count - 1).ToArray();
                    exclusionPolygons.Add(new ExclusionPolygon(uniquePoints));
                }
            }

            float courseMinX = float.MaxValue;
            float courseMaxX = float.MinValue;
            float courseMinZ = float.MaxValue;
            float courseMaxZ = float.MinValue;
            bool hasValidPoints = false;

            foreach (var excl in exclusionPolygons)
            {
                foreach (var pt in excl.Polygon)
                {
                    if (pt.X < courseMinX) courseMinX = pt.X;
                    if (pt.X > courseMaxX) courseMaxX = pt.X;
                    if (pt.Y < courseMinZ) courseMinZ = pt.Y;
                    if (pt.Y > courseMaxZ) courseMaxZ = pt.Y;
                    hasValidPoints = true;
                }
            }

            foreach (var path in lineOfPlayPaths)
            {
                foreach (var pt in path)
                {
                    if (pt.X < courseMinX) courseMinX = pt.X;
                    if (pt.X > courseMaxX) courseMaxX = pt.X;
                    if (pt.Y < courseMinZ) courseMinZ = pt.Y;
                    if (pt.Y > courseMaxZ) courseMaxZ = pt.Y;
                    hasValidPoints = true;
                }
            }

            foreach (var poly in coursePolygons)
            {
                foreach (var pt in poly)
                {
                    if (pt.X < courseMinX) courseMinX = pt.X;
                    if (pt.X > courseMaxX) courseMaxX = pt.X;
                    if (pt.Y < courseMinZ) courseMinZ = pt.Y;
                    if (pt.Y > courseMaxZ) courseMaxZ = pt.Y;
                    hasValidPoints = true;
                }
            }

            if (!hasValidPoints)
            {
                courseMinX = -1500f;
                courseMaxX = 1500f;
                courseMinZ = -1500f;
                courseMaxZ = 1500f;
            }
            else
            {
                courseMinX -= 300f;
                courseMaxX += 300f;
                courseMinZ -= 300f;
                courseMaxZ += 300f;
            }

            double lonMin = refLon + courseMinX / metersPerLon;
            double lonMax = refLon + courseMaxX / metersPerLon;
            double latMin = refLat - courseMaxZ / metersPerLat;
            double latMax = refLat - courseMinZ / metersPerLat;

            return new BBox { 
                LonMin = lonMin, 
                LatMin = latMin, 
                LonMax = lonMax, 
                LatMax = latMax,
                RefLat = refLat,
                RefLon = refLon,
                MetersPerLat = metersPerLat,
                MetersPerLon = metersPerLon
            };
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Failed to calculate bbox: {ex}");
            return null;
        }
    }

    private static Vector2 GetPointOnPolyline(List<Vector2> points, float distance)
    {
        if (points.Count == 0) return Vector2.Zero;
        if (points.Count == 1 || distance <= 0) return points[0];

        float accumulated = 0f;
        for (int i = 0; i < points.Count - 1; i++)
        {
            float d = points[i].DistanceTo(points[i+1]);
            if (accumulated + d >= distance)
            {
                float t = (distance - accumulated) / d;
                return points[i].Lerp(points[i+1], t);
            }
            accumulated += d;
        }
        return points[points.Count - 1];
    }

    private static List<Vector2> SmoothPath(List<Vector2> path, int iterations)
    {
        var current = new List<Vector2>(path);
        for (int iter = 0; iter < iterations; iter++)
        {
            if (current.Count < 3) break;
            var next = new List<Vector2>();
            next.Add(current[0]);
            for (int i = 0; i < current.Count - 1; i++)
            {
                Vector2 p0 = current[i];
                Vector2 p1 = current[i + 1];
                next.Add(p0 * 0.75f + p1 * 0.25f);
                next.Add(p0 * 0.25f + p1 * 0.75f);
            }
            next.Add(current[current.Count - 1]);
            current = next;
        }
        return current;
    }

    private void CreateGolfSurfaceMesh(Node3D rootNode, Vector2[] uniquePoints, string golfType, string idSuffix, List<ExclusionPolygon> exclusionPolygons)
    {
        exclusionPolygons.Add(new ExclusionPolygon(uniquePoints, golfType, this));
        int surfaceTypeValue = golfType == "green" ? 4 : (golfType == "bunker" ? 2 : 0);

        var staticBody = new StaticBody3D { Name = $"{golfType}_Static_{idSuffix}" };
        staticBody.SetMeta("surface_type", surfaceTypeValue);
        if (golfType == "bunker")
        {
            staticBody.SetMeta("is_sand", true);
        }
        CreateCollisionForPolygon(staticBody, uniquePoints, rootNode, exclusionPolygons);
    }

    private void CreateTeeBoxMesh(Node3D rootNode, Vector2[] uniquePoints, string idSuffix, List<ExclusionPolygon> exclusionPolygons)
    {
        exclusionPolygons.Add(new ExclusionPolygon(uniquePoints, "tee", this));
        var staticBody = new StaticBody3D { Name = $"tee_Static_{idSuffix}" };
        staticBody.SetMeta("surface_type", 0); // Fairway physics for tees
        CreateCollisionForPolygon(staticBody, uniquePoints, rootNode, exclusionPolygons);
    }

    /// <summary>
    /// Creates a collision-only body for a polygon zone (no visual mesh).
    /// The collision shape follows the terrain height.
    /// </summary>
    private void CreateCollisionForPolygon(StaticBody3D staticBody, Vector2[] points, Node3D rootNode, List<ExclusionPolygon>? exclusions = null)
    {
        if (points == null || points.Length < 3) return;
        
        var indices = Geometry2D.TriangulatePolygon(points);
        if (indices.Length == 0) return;

        // Subdivide large triangles for height fidelity
        var queue = new Queue<SubdivisionTriangle>();
        for (int i = 0; i < indices.Length; i += 3)
        {
            queue.Enqueue(new SubdivisionTriangle(points[indices[i]], points[indices[i+1]], points[indices[i+2]]));
        }

        var tris = new List<SubdivisionTriangle>();
        float maxEdgeSq = 12.0f * 12.0f;
        while (queue.Count > 0)
        {
            var tri = queue.Dequeue();
            float dAB = tri.A.DistanceSquaredTo(tri.B);
            float dBC = tri.B.DistanceSquaredTo(tri.C);
            float dCA = tri.C.DistanceSquaredTo(tri.A);
            float maxD = Math.Max(dAB, Math.Max(dBC, dCA));
            if (maxD > maxEdgeSq)
            {
                if (maxD == dAB)
                {
                    var m = (tri.A + tri.B) * 0.5f;
                    queue.Enqueue(new SubdivisionTriangle(tri.A, m, tri.C));
                    queue.Enqueue(new SubdivisionTriangle(m, tri.B, tri.C));
                }
                else if (maxD == dBC)
                {
                    var m = (tri.B + tri.C) * 0.5f;
                    queue.Enqueue(new SubdivisionTriangle(tri.B, m, tri.A));
                    queue.Enqueue(new SubdivisionTriangle(m, tri.C, tri.A));
                }
                else
                {
                    var m = (tri.C + tri.A) * 0.5f;
                    queue.Enqueue(new SubdivisionTriangle(tri.C, m, tri.B));
                    queue.Enqueue(new SubdivisionTriangle(m, tri.A, tri.B));
                }
            }
            else
            {
                tris.Add(tri);
            }
        }

        var collisionVerts = new Vector3[tris.Count * 3];
        for (int i = 0; i < tris.Count; i++)
        {
            var t = tris[i];
            float hA = exclusions != null ? GetHeightWithFeatures(t.A.X, t.A.Y, exclusions) : GetHeight(t.A.X, t.A.Y);
            float hB = exclusions != null ? GetHeightWithFeatures(t.B.X, t.B.Y, exclusions) : GetHeight(t.B.X, t.B.Y);
            float hC = exclusions != null ? GetHeightWithFeatures(t.C.X, t.C.Y, exclusions) : GetHeight(t.C.X, t.C.Y);
            collisionVerts[i * 3] = new Vector3(t.A.X, hA, t.A.Y);
            collisionVerts[i * 3 + 1] = new Vector3(t.B.X, hB, t.B.Y);
            collisionVerts[i * 3 + 2] = new Vector3(t.C.X, hC, t.C.Y);
        }

        var concaveShape = new ConcavePolygonShape3D();
        concaveShape.Data = collisionVerts;
        var colShape = new CollisionShape3D();
        colShape.Shape = concaveShape;

        staticBody.AddChild(colShape);
        rootNode.AddChild(staticBody);
        staticBody.Owner = rootNode;
        colShape.Owner = rootNode;
    }

    /// <summary>
    /// Returns terrain height with smooth bunker bowl depressions applied.
    /// </summary>
    private float GetHeightWithFeatures(float x, float z, List<ExclusionPolygon> exclusions)
    {
        float baseHeight = GetHeight(x, z);
        var point = new Vector2(x, z);

        float bunkerDepression = 0f;
        float waterDepression = 0f;

        float? overrideHeight = null;
        float overrideWeight = 0f;

        for (int i = 0; i < exclusions.Count; i++)
        {
            var excl = exclusions[i];
            if (x < excl.MinX - 5f || x > excl.MaxX + 5f || z < excl.MinY - 5f || z > excl.MaxY + 5f)
                continue;

            bool inside = PointInPolygon(point, excl.Polygon);

            if (excl.GolfType == "bunker")
            {
                if (inside)
                {
                    float dist = DistanceToPolygon(point, excl.Polygon);
                    float bowlRadius = 3.5f;
                    float maxDepth = 1.15f;
                    if (dist < bowlRadius)
                    {
                        float t = dist / bowlRadius;
                        float smoothT = t * t * (3.0f - 2.0f * t);
                        bunkerDepression = Math.Max(bunkerDepression, smoothT * maxDepth);
                    }
                    else
                    {
                        bunkerDepression = Math.Max(bunkerDepression, maxDepth);
                    }
                }
                else
                {
                    // Raised lip outside bunker boundary
                    float dist = DistanceToPolygon(point, excl.Polygon);
                    if (dist < 2.0f)
                    {
                        float t = 1.0f - (dist / 2.0f);
                        float smoothT = t * t * (3.0f - 2.0f * t);
                        bunkerDepression = Math.Max(bunkerDepression, -smoothT * 0.20f);
                    }
                }
            }
            else if (excl.GolfType == "water")
            {
                if (inside)
                {
                    float dist = DistanceToPolygon(point, excl.Polygon);
                    float maxDepth = 2.0f;
                    if (dist < 15.0f)
                    {
                        float t = dist / 15.0f;
                        float smoothT = t * t * (3.0f - 2.0f * t);
                        waterDepression = Math.Max(waterDepression, smoothT * maxDepth);
                    }
                    else
                    {
                        waterDepression = Math.Max(waterDepression, maxDepth);
                    }
                }
            }
            else if (excl.GolfType == "tee" && excl.AverageHeight.HasValue)
            {
                float targetH = excl.AverageHeight.Value;
                if (inside)
                {
                    float dist = DistanceToPolygon(point, excl.Polygon);
                    float blendRadius = 2.0f;
                    if (dist < blendRadius)
                    {
                        float t = dist / blendRadius;
                        float smoothT = t * t * (3.0f - 2.0f * t);
                        overrideHeight = (overrideHeight ?? baseHeight) * (1f - smoothT) + targetH * smoothT;
                        overrideWeight = Math.Max(overrideWeight, smoothT);
                    }
                    else
                    {
                        overrideHeight = targetH;
                        overrideWeight = 1.0f;
                    }
                }
            }
            else if (excl.GolfType == "green" && excl.AverageHeight.HasValue)
            {
                float targetH = excl.AverageHeight.Value;
                if (inside)
                {
                    float dist = DistanceToPolygon(point, excl.Polygon);
                    float blendRadius = 2.0f;
                    // Green smoothing: scale down vertical variation relative to average height
                    float greenSlopeScale = (_currentElevationMap != null) ? 1.0f : 0.35f;
                    float smoothedH = targetH + (baseHeight - targetH) * greenSlopeScale;
                    if (dist < blendRadius)
                    {
                        float t = dist / blendRadius;
                        float smoothT = t * t * (3.0f - 2.0f * t);
                        overrideHeight = (overrideHeight ?? baseHeight) * (1f - smoothT) + smoothedH * smoothT;
                        overrideWeight = Math.Max(overrideWeight, smoothT);
                    }
                    else
                    {
                        overrideHeight = smoothedH;
                        overrideWeight = 1.0f;
                    }
                }
            }
        }

        float finalBase = overrideHeight.HasValue ? overrideHeight.Value : baseHeight;
        return finalBase - Math.Max(bunkerDepression, waterDepression);
    }

    /// <summary>
    /// Generates a splat map texture encoding surface types for the terrain.
    /// R = green, G = fairway/tee, B = bunker, A = mulch. Rough = where all channels are 0.
    /// </summary>
    private ImageTexture GenerateSplatMap(float minX, float maxX, float minZ, float maxZ, List<ExclusionPolygon> exclusions, List<Vector2> treePositions)
    {
        int texSize = 2048;
        byte[] pixelData = new byte[texSize * texSize * 4];

        float worldWidth = maxX - minX;
        float worldDepth = maxZ - minZ;
        float blendRadius = 1.5f; // meters of smooth blending at zone boundaries

        Parallel.For(0, texSize, py =>
        {
            float worldZ = minZ + (py / (float)(texSize - 1)) * worldDepth;
            for (int px = 0; px < texSize; px++)
            {
                float worldX = minX + (px / (float)(texSize - 1)) * worldWidth;
                var point = new Vector2(worldX, worldZ);

                float greenWeight = 0f;
                float fairwayWeight = 0f;
                float bunkerWeight = 0f;

                for (int i = 0; i < exclusions.Count; i++)
                {
                    var excl = exclusions[i];
                    if (worldX < excl.MinX - blendRadius || worldX > excl.MaxX + blendRadius ||
                        worldZ < excl.MinY - blendRadius || worldZ > excl.MaxY + blendRadius)
                        continue;

                    bool inside = PointInPolygon(point, excl.Polygon);
                    float dist = DistanceToPolygon(point, excl.Polygon);

                    float weight = 0f;
                    if (inside)
                    {
                        weight = 1.0f;
                    }
                    else if (dist < blendRadius)
                    {
                        float t = 1.0f - (dist / blendRadius);
                        weight = t * t * (3.0f - 2.0f * t); // smoothstep
                    }

                    if (weight > 0f)
                    {
                        if (excl.GolfType == "green" || excl.GolfType == "tee")
                        {
                            greenWeight = Math.Max(greenWeight, weight);
                        }
                        else if (excl.GolfType == "fairway")
                        {
                            fairwayWeight = Math.Max(fairwayWeight, weight);
                        }
                        else if (excl.GolfType == "bunker")
                        {
                            bunkerWeight = Math.Max(bunkerWeight, weight);
                        }
                    }
                }

                // Priority override: bunker > green/tee > fairway
                if (bunkerWeight >= 1.0f)
                {
                    greenWeight = 0f;
                    fairwayWeight = 0f;
                }
                else if (greenWeight >= 1.0f)
                {
                    fairwayWeight = 0f;
                    bunkerWeight = Math.Min(bunkerWeight, 1.0f - greenWeight);
                }
                else
                {
                    float baseSum = greenWeight + bunkerWeight;
                    if (baseSum > 0f)
                    {
                        fairwayWeight = Math.Min(fairwayWeight, 1.0f - baseSum);
                    }
                }

                int byteIdx = (py * texSize + px) * 4;
                pixelData[byteIdx + 0] = (byte)Math.Clamp((int)(greenWeight * 255.0f), 0, 255);
                pixelData[byteIdx + 1] = (byte)Math.Clamp((int)(fairwayWeight * 255.0f), 0, 255);
                pixelData[byteIdx + 2] = (byte)Math.Clamp((int)(bunkerWeight * 255.0f), 0, 255);
                pixelData[byteIdx + 3] = 0; // Mulch applied in next step
            }
        });

        // Rasterize mulch around tree positions directly (radius = 2.2m)
        float mulchRadius = 2.2f;
        float radiusPixelsX = (mulchRadius / (worldWidth == 0 ? 1f : worldWidth)) * (texSize - 1);
        float radiusPixelsY = (mulchRadius / (worldDepth == 0 ? 1f : worldDepth)) * (texSize - 1);
        int rPx = (int)Math.Ceiling(Math.Max(radiusPixelsX, radiusPixelsY));

        foreach (var treePos in treePositions)
        {
            float normX = (treePos.X - minX) / (worldWidth == 0 ? 1f : worldWidth);
            float normZ = (treePos.Y - minZ) / (worldDepth == 0 ? 1f : worldDepth);
            int centerPx = (int)Math.Round(normX * (texSize - 1));
            int centerPy = (int)Math.Round(normZ * (texSize - 1));

            int minPy = Math.Max(0, centerPy - rPx);
            int maxPy = Math.Min(texSize - 1, centerPy + rPx);
            int minPx = Math.Max(0, centerPx - rPx);
            int maxPx = Math.Min(texSize - 1, centerPx + rPx);

            for (int py = minPy; py <= maxPy; py++)
            {
                float worldZ = minZ + (py / (float)(texSize - 1)) * worldDepth;
                float dz = worldZ - treePos.Y;

                for (int px = minPx; px <= maxPx; px++)
                {
                    float worldX = minX + (px / (float)(texSize - 1)) * worldWidth;
                    float dx = worldX - treePos.X;
                    float distSq = dx * dx + dz * dz;

                    if (distSq < mulchRadius * mulchRadius)
                    {
                        float dist = (float)Math.Sqrt(distSq);
                        float w = 1.0f - (dist / mulchRadius);
                        float mulchWeight = w * w * (3.0f - 2.0f * w); // smoothstep
                        byte mByte = (byte)Math.Clamp((int)(mulchWeight * 255.0f), 0, 255);

                        int byteIdx = (py * texSize + px) * 4;
                        if (mByte > pixelData[byteIdx + 3])
                        {
                            pixelData[byteIdx + 3] = mByte;
                        }
                    }
                }
            }
        }

        var image = Image.CreateFromData(texSize, texSize, false, Image.Format.Rgba8, pixelData);
        return ImageTexture.CreateFromImage(image);
    }

    /// <summary>
    /// Generates a macro ambient occlusion map from course elevation data.
    /// Darkens swales, bunker bowls, and recessed contours while keeping ridges and plateaus bright.
    /// </summary>
    private ImageTexture GenerateTerrainAOMap(float minX, float maxX, float minZ, float maxZ, List<ExclusionPolygon> exclusions)
    {
        int texSize = 1024;
        byte[] pixelData = new byte[texSize * texSize];

        float worldWidth = maxX - minX;
        float worldDepth = maxZ - minZ;
        float sampleRadius = 4.0f; // meters

        Parallel.For(0, texSize, py =>
        {
            float worldZ = minZ + (py / (float)(texSize - 1)) * worldDepth;
            for (int px = 0; px < texSize; px++)
            {
                float worldX = minX + (px / (float)(texSize - 1)) * worldWidth;
                float hCenter = GetHeightWithFeatures(worldX, worldZ, exclusions);
                
                // Sample 8 neighbors around circle
                float hSum = 0f;
                hSum += GetHeightWithFeatures(worldX + sampleRadius, worldZ, exclusions);
                hSum += GetHeightWithFeatures(worldX - sampleRadius, worldZ, exclusions);
                hSum += GetHeightWithFeatures(worldX, worldZ + sampleRadius, exclusions);
                hSum += GetHeightWithFeatures(worldX, worldZ - sampleRadius, exclusions);
                hSum += GetHeightWithFeatures(worldX + sampleRadius * 0.707f, worldZ + sampleRadius * 0.707f, exclusions);
                hSum += GetHeightWithFeatures(worldX - sampleRadius * 0.707f, worldZ + sampleRadius * 0.707f, exclusions);
                hSum += GetHeightWithFeatures(worldX + sampleRadius * 0.707f, worldZ - sampleRadius * 0.707f, exclusions);
                hSum += GetHeightWithFeatures(worldX - sampleRadius * 0.707f, worldZ - sampleRadius * 0.707f, exclusions);
                float hAvg = hSum / 8.0f;

                // If center is lower than surroundings, it's a depression/swale (AO < 1.0)
                float diff = hCenter - hAvg;
                float ao = Mathf.Clamp(1.0f + diff * 0.45f, 0.55f, 1.0f);

                pixelData[py * texSize + px] = (byte)Math.Clamp((int)(ao * 255.0f), 0, 255);
            }
        });

        var image = Image.CreateFromData(texSize, texSize, false, Image.Format.L8, pixelData);
        return ImageTexture.CreateFromImage(image);
    }

    /// <summary>
    /// Creates a single unified terrain mesh covering the entire course, with a splat map
    /// shader to blend between surface textures (green, fairway, rough, bunker).
    /// Replaces the old separate-mesh approach.
    /// </summary>
    private async Task CreateUnifiedTerrainAsync(float minX, float maxX, float minZ, float maxZ, int subdivisionsX, int subdivisionsZ, Node3D root, List<ExclusionPolygon> exclusions, List<Vector2> treePositions)
    {
        GD.Print($"{LogPrefix} Generating unified terrain mesh ({subdivisionsX}x{subdivisionsZ})...");

        // Generate the splat map texture in background thread
        GD.Print($"{LogPrefix} Generating splat map...");
        var splatMap = await Task.Run(() => GenerateSplatMap(minX, maxX, minZ, maxZ, exclusions, treePositions));
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

        // Generate macro terrain ambient occlusion map in background thread
        GD.Print($"{LogPrefix} Generating terrain macro AO map...");
        var terrainAoMap = await Task.Run(() => GenerateTerrainAOMap(minX, maxX, minZ, maxZ, exclusions));
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

        var arrayMesh = new ArrayMesh();
        int numVertices = (subdivisionsX + 1) * (subdivisionsZ + 1);
        var vertices = new Vector3[numVertices];
        var normals = new Vector3[numVertices];
        var colors = new Color[numVertices];
        var uvs = new Vector2[numVertices]; // UV1: world-space tiling for textures
        var uv2s = new Vector2[numVertices]; // UV2: normalized [0,1] for splat map

        float width = maxX - minX;
        float depth = maxZ - minZ;
        float cellWidth = width / subdivisionsX;
        float cellDepth = depth / subdivisionsZ;

        await Task.Run(() =>
        {
            Parallel.For(0, subdivisionsZ + 1, z =>
            {
                for (int x = 0; x <= subdivisionsX; x++)
                {
                    int idx = z * (subdivisionsX + 1) + x;
                    float vx = minX + x * cellWidth;
                    float vz = minZ + z * cellDepth;
                    float vy = GetHeightWithFeatures(vx, vz, exclusions);

                    vertices[idx] = new Vector3(vx, vy, vz);

                    // Compute normal from height differences
                    float hL = GetHeightWithFeatures(vx - 1.0f, vz, exclusions);
                    float hR = GetHeightWithFeatures(vx + 1.0f, vz, exclusions);
                    float hD = GetHeightWithFeatures(vx, vz - 1.0f, exclusions);
                    float hU = GetHeightWithFeatures(vx, vz + 1.0f, exclusions);
                    normals[idx] = new Vector3(hL - hR, 2.0f, hD - hU).Normalized();

                    colors[idx] = new Color(1f, 1f, 1f); // White — shader handles color
                    uvs[idx] = new Vector2(vx, vz) * 0.1f; // World-space UV for texture tiling
                    uv2s[idx] = new Vector2(
                        (vx - minX) / width,
                        (vz - minZ) / depth
                    ); // Normalized UV for splat map
                }
            });
        });

        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

        // Build index buffer (two triangles per grid cell)
        var indicesList = new List<int>(subdivisionsX * subdivisionsZ * 6);
        for (int z = 0; z < subdivisionsZ; z++)
        {
            for (int x = 0; x < subdivisionsX; x++)
            {
                int row1 = z * (subdivisionsX + 1);
                int row2 = (z + 1) * (subdivisionsX + 1);

                indicesList.Add(row1 + x);
                indicesList.Add(row1 + x + 1);
                indicesList.Add(row2 + x);

                indicesList.Add(row1 + x + 1);
                indicesList.Add(row2 + x + 1);
                indicesList.Add(row2 + x);
            }
        }
        var indices = indicesList.ToArray();

        // Build the mesh
        var arr = new Godot.Collections.Array();
        arr.Resize((int)Mesh.ArrayType.Max);
        arr[(int)Mesh.ArrayType.Vertex] = vertices;
        arr[(int)Mesh.ArrayType.Normal] = normals;
        arr[(int)Mesh.ArrayType.Color] = colors;
        arr[(int)Mesh.ArrayType.TexUV] = uvs;
        arr[(int)Mesh.ArrayType.TexUV2] = uv2s;
        arr[(int)Mesh.ArrayType.Index] = indices;

        arrayMesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arr);

        // Create and assign the splat map material
        var shader = GD.Load<Shader>("res://Courses/Environments/shaders/terrain_splat.gdshader");
        var mat = new ShaderMaterial();
        mat.Shader = shader;
        mat.SetShaderParameter("splat_map", splatMap);
        mat.SetShaderParameter("terrain_ao_map", terrainAoMap);

        // Albedo Textures
        mat.SetShaderParameter("tex_rough", GD.Load<Texture2D>("res://Courses/Environments/grass-rough/albedo.png"));
        mat.SetShaderParameter("tex_green", GD.Load<Texture2D>("res://Courses/Environments/grass-green/albedo.png"));
        mat.SetShaderParameter("tex_fairway", GD.Load<Texture2D>("res://Courses/Environments/grass-fairway/albedo.png"));
        mat.SetShaderParameter("tex_bunker", GD.Load<Texture2D>("res://Courses/Environments/sand-bunker/albedo.png"));
        mat.SetShaderParameter("tex_mulch", GD.Load<Texture2D>("res://Courses/Environments/tree-bark/albedo.png"));
        
        // Normal Maps
        mat.SetShaderParameter("normal_rough", GD.Load<Texture2D>("res://Courses/Environments/grass-rough/normal.png"));
        mat.SetShaderParameter("normal_green", GD.Load<Texture2D>("res://Courses/Environments/grass-green/normal.png"));
        mat.SetShaderParameter("normal_fairway", GD.Load<Texture2D>("res://Courses/Environments/grass-fairway/normal.png"));
        mat.SetShaderParameter("normal_bunker", GD.Load<Texture2D>("res://Courses/Environments/sand-bunker/normal.png"));
        mat.SetShaderParameter("normal_mulch", GD.Load<Texture2D>("res://Courses/Environments/tree-bark/normal.png"));

        // Ambient Occlusion Maps
        mat.SetShaderParameter("ao_rough", GD.Load<Texture2D>("res://Courses/Environments/grass-rough/ao.png"));
        mat.SetShaderParameter("ao_green", GD.Load<Texture2D>("res://Courses/Environments/grass-green/ao.png"));
        mat.SetShaderParameter("ao_fairway", GD.Load<Texture2D>("res://Courses/Environments/grass-fairway/ao.png"));
        mat.SetShaderParameter("ao_bunker", GD.Load<Texture2D>("res://Courses/Environments/sand-bunker/ao.png"));
        if (ResourceLoader.Exists("res://Courses/Environments/tree-bark/ao.png"))
            mat.SetShaderParameter("ao_mulch", GD.Load<Texture2D>("res://Courses/Environments/tree-bark/ao.png"));

        // Roughness Maps
        mat.SetShaderParameter("roughness_tex_rough", GD.Load<Texture2D>("res://Courses/Environments/grass-rough/roughness.png"));
        mat.SetShaderParameter("roughness_tex_green", GD.Load<Texture2D>("res://Courses/Environments/grass-green/roughness.png"));
        mat.SetShaderParameter("roughness_tex_fairway", GD.Load<Texture2D>("res://Courses/Environments/grass-fairway/roughness.png"));
        mat.SetShaderParameter("roughness_tex_bunker", GD.Load<Texture2D>("res://Courses/Environments/sand-bunker/roughness.png"));
        if (ResourceLoader.Exists("res://Courses/Environments/tree-bark/roughness.png"))
            mat.SetShaderParameter("roughness_tex_mulch", GD.Load<Texture2D>("res://Courses/Environments/tree-bark/roughness.png"));

        // Height Maps (for height-blended transitions)
        mat.SetShaderParameter("height_rough", GD.Load<Texture2D>("res://Courses/Environments/grass-rough/height.png"));
        mat.SetShaderParameter("height_green", GD.Load<Texture2D>("res://Courses/Environments/grass-green/height.png"));
        mat.SetShaderParameter("height_fairway", GD.Load<Texture2D>("res://Courses/Environments/grass-fairway/height.png"));
        mat.SetShaderParameter("height_bunker", GD.Load<Texture2D>("res://Courses/Environments/sand-bunker/height.png"));
        if (ResourceLoader.Exists("res://Courses/Environments/tree-bark/height.png"))
            mat.SetShaderParameter("height_mulch", GD.Load<Texture2D>("res://Courses/Environments/tree-bark/height.png"));

        // Sun Direction for elevation shading
        mat.SetShaderParameter("sun_direction", new Vector3(-0.45f, -0.65f, -0.60f).Normalized());

        arrayMesh.SurfaceSetMaterial(0, mat);

        var groundMesh = new MeshInstance3D
        {
            Name = "UnifiedTerrain",
            Mesh = arrayMesh
        };
        root.AddChild(groundMesh);
        groundMesh.Owner = root;

        // Create fallback collision body (rough surface type) for the terrain
        var groundStatic = new StaticBody3D { Name = "TerrainStatic" };
        groundStatic.SetMeta("surface_type", 2); // Rough

        var colShape = new CollisionShape3D();
        var concaveShape = new ConcavePolygonShape3D();
        var collisionVertices = new Vector3[indices.Length];
        for (int i = 0; i < indices.Length; i++)
        {
            collisionVertices[i] = vertices[indices[i]];
        }
        concaveShape.Data = collisionVertices;
        colShape.Shape = concaveShape;

        groundStatic.AddChild(colShape);
        root.AddChild(groundStatic);
        groundStatic.Owner = root;
        colShape.Owner = root;

        GD.Print($"{LogPrefix} Unified terrain created successfully.");
    }

    private static List<Vector2[]> AssembleRelationPolygons(
        OsmRelation rel, 
        List<OsmWay> allWays, 
        Dictionary<long, (double Lat, double Lon)> nodes, 
        double refLat, 
        double refLon, 
        double metersPerLat, 
        double metersPerLon)
    {
        var outerMemberWays = rel.Members
            .Where(m => m.Type == "way" && (m.Role == "outer" || string.IsNullOrEmpty(m.Role)))
            .Select(m => allWays.FirstOrDefault(w => w.Id == m.Ref))
            .Where(w => w != null && w.NodeIds.Count >= 2)
            .ToList();

        var resultPolygons = new List<Vector2[]>();
        var unvisitedWays = new List<List<long>>();

        foreach (var w in outerMemberWays)
        {
            if (w == null) continue;
            var validNodes = w.NodeIds.Where(nodes.ContainsKey).ToList();
            if (validNodes.Count >= 2)
            {
                // If already a closed loop
                if (validNodes.First() == validNodes.Last() && validNodes.Count >= 4)
                {
                    var pts = validNodes
                        .Select(id => nodes[id])
                        .Select(coord => new Vector2(
                            (float)((coord.Lon - refLon) * metersPerLon),
                            -(float)((coord.Lat - refLat) * metersPerLat)
                        ))
                        .ToArray();
                    resultPolygons.Add(pts);
                }
                else
                {
                    unvisitedWays.Add(validNodes);
                }
            }
        }

        // Stitch unvisited open ways into closed loops
        int maxIterations = unvisitedWays.Count * 2 + 10;
        int iter = 0;
        while (unvisitedWays.Count > 0 && iter++ < maxIterations)
        {
            var currentChain = new List<long>(unvisitedWays[0]);
            unvisitedWays.RemoveAt(0);

            bool extended = true;
            while (extended && currentChain.First() != currentChain.Last() && unvisitedWays.Count > 0)
            {
                extended = false;
                long endNode = currentChain.Last();
                long startNode = currentChain.First();

                for (int i = 0; i < unvisitedWays.Count; i++)
                {
                    var way = unvisitedWays[i];
                    if (way.First() == endNode)
                    {
                        currentChain.AddRange(way.Skip(1));
                        unvisitedWays.RemoveAt(i);
                        extended = true;
                        break;
                    }
                    else if (way.Last() == endNode)
                    {
                        var rev = way.AsEnumerable().Reverse().ToList();
                        currentChain.AddRange(rev.Skip(1));
                        unvisitedWays.RemoveAt(i);
                        extended = true;
                        break;
                    }
                    else if (way.Last() == startNode)
                    {
                        currentChain.InsertRange(0, way.Take(way.Count - 1));
                        unvisitedWays.RemoveAt(i);
                        extended = true;
                        break;
                    }
                    else if (way.First() == startNode)
                    {
                        var rev = way.AsEnumerable().Reverse().ToList();
                        currentChain.InsertRange(0, rev.Take(rev.Count - 1));
                        unvisitedWays.RemoveAt(i);
                        extended = true;
                        break;
                    }
                }
            }

            if (currentChain.Count >= 4)
            {
                var pts = currentChain
                    .Select(id => nodes[id])
                    .Select(coord => new Vector2(
                        (float)((coord.Lon - refLon) * metersPerLon),
                        -(float)((coord.Lat - refLat) * metersPerLat)
                    ))
                    .ToArray();
                resultPolygons.Add(pts);
            }
            else if (currentChain.Count >= 3)
            {
                currentChain.Add(currentChain.First());
                var pts = currentChain
                    .Select(id => nodes[id])
                    .Select(coord => new Vector2(
                        (float)((coord.Lon - refLon) * metersPerLon),
                        -(float)((coord.Lat - refLat) * metersPerLat)
                    ))
                    .ToArray();
                resultPolygons.Add(pts);
            }
        }

        return resultPolygons;
    }

    private static bool PointInPolygon(Vector2 pt, Vector2[] poly)
    {
        int count = poly.Length;
        if (count < 3) return false;
        bool inside = false;
        for (int i = 0, j = count - 1; i < count; j = i++)
        {
            if (((poly[i].Y > pt.Y) != (poly[j].Y > pt.Y)) &&
                (pt.X < (poly[j].X - poly[i].X) * (pt.Y - poly[i].Y) / (poly[j].Y - poly[i].Y) + poly[i].X))
            {
                inside = !inside;
            }
        }
        return inside;
    }

    private static float DistanceToSegment(Vector2 p, Vector2 a, Vector2 b)
    {
        Vector2 ab = b - a;
        Vector2 ap = p - a;
        float ab2 = ab.LengthSquared();
        if (ab2 == 0f) return ap.Length();
        
        float t = Mathf.Clamp(ap.Dot(ab) / ab2, 0f, 1f);
        Vector2 projection = a + t * ab;
        return p.DistanceTo(projection);
    }

    private static float DistanceToPolygon(Vector2 p, Vector2[] poly)
    {
        float minD = float.MaxValue;
        int n = poly.Length;
        for (int i = 0; i < n; i++)
        {
            float d = DistanceToSegment(p, poly[i], poly[(i + 1) % n]);
            if (d < minD) minD = d;
        }
        return minD;
    }

    private StandardMaterial3D? _rockMaterial;
    private ArrayMesh[]? _rockMeshes;

    private void InitializeRockAssets()
    {
        if (_rockMaterial != null) return;
        
        _rockMaterial = new StandardMaterial3D
        {
            VertexColorUseAsAlbedo = false,
            AlbedoTexture = GD.Load<Texture2D>("res://Courses/Environments/jagged-rocky-ground1-bl/jagged-rocky-ground_albedo.png"),
            NormalEnabled = true,
            NormalTexture = GD.Load<Texture2D>("res://Courses/Environments/jagged-rocky-ground1-bl/jagged-rocky-ground_normal-ogl.png"),
            RoughnessTexture = GD.Load<Texture2D>("res://Courses/Environments/jagged-rocky-ground1-bl/jagged-rocky-ground_roughness.png"),
            AOEnabled = true,
            AOTexture = GD.Load<Texture2D>("res://Courses/Environments/jagged-rocky-ground1-bl/jagged-rocky-ground_ao.png"),
            Roughness = 0.9f,
            NormalScale = 1.0f,
            Uv1Scale = new Vector3(2f, 2f, 2f)
        };
        
        var random = new Random(1337);
        _rockMeshes = new ArrayMesh[3];
        for (int i = 0; i < 3; i++)
        {
            _rockMeshes[i] = CreateSingleRockMesh(_rockMaterial, random);
        }
    }

    private ArrayMesh CreateSingleRockMesh(StandardMaterial3D material, Random random)
    {
        var arrayMesh = new ArrayMesh();
        int rings = 6;
        int slices = 10;
        
        int numVertices = (rings + 1) * (slices + 1);
        var vertices = new Vector3[numVertices];
        var normals = new Vector3[numVertices];
        var uvs = new Vector2[numVertices];
        
        int idx = 0;
        for (int r = 0; r <= rings; r++)
        {
            float phi = Mathf.Pi * r / rings;
            float sinPhi = Mathf.Sin(phi);
            float cosPhi = Mathf.Cos(phi);
            
            for (int s = 0; s <= slices; s++)
            {
                float theta = Mathf.Tau * s / slices;
                float sinTheta = Mathf.Sin(theta);
                float cosTheta = Mathf.Cos(theta);
                
                float x = sinPhi * cosTheta;
                float y = cosPhi;
                float z = sinPhi * sinTheta;
                
                var normal = new Vector3(x, y, z).Normalized();
                
                float radialNoise = 0.7f + (float)random.NextDouble() * 0.5f;
                float heightDeform = 0.5f + (float)random.NextDouble() * 0.4f;
                float bottomFlatten = y < -0.2f ? 0.8f : 1.0f;
                
                var vertex = new Vector3(
                    x * radialNoise,
                    y * heightDeform * bottomFlatten,
                    z * radialNoise
                );
                
                vertices[idx] = vertex;
                normals[idx] = normal;
                uvs[idx] = new Vector2((float)s / slices * 2f, (float)r / rings * 2f);
                
                idx++;
            }
        }
        
        var indices = new List<int>();
        for (int r = 0; r < rings; r++)
        {
            for (int s = 0; s < slices; s++)
            {
                int current = r * (slices + 1) + s;
                int next = current + 1;
                int bottom = (r + 1) * (slices + 1) + s;
                int bottomNext = bottom + 1;
                
                indices.Add(current);
                indices.Add(bottom);
                indices.Add(next);
                
                indices.Add(next);
                indices.Add(bottom);
                indices.Add(bottomNext);
            }
        }
        
        var arr = new Godot.Collections.Array();
        arr.Resize((int)Mesh.ArrayType.Max);
        arr[(int)Mesh.ArrayType.Vertex] = vertices;
        arr[(int)Mesh.ArrayType.Normal] = normals;
        arr[(int)Mesh.ArrayType.TexUV] = uvs;
        arr[(int)Mesh.ArrayType.Index] = indices.ToArray();
        
        arrayMesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arr);
        arrayMesh.SurfaceSetMaterial(0, material);
        return arrayMesh;
    }

    private void SpawnRockAt(Node3D root, Vector3 position, Vector3 scale, float rotationY, ArrayMesh mesh)
    {
        var staticBody = new StaticBody3D
        {
            Name = $"Rock_{position.X:F1}_{position.Z:F1}",
            Position = position,
            Scale = scale,
            Rotation = new Vector3(0f, rotationY, 0f)
        };
        staticBody.SetMeta("surface_type", 2); // Treated as rough collision for the ball
        
        var meshInstance = new MeshInstance3D
        {
            Name = "Mesh",
            Mesh = mesh
        };
        staticBody.AddChild(meshInstance);

        var collisionShape = new CollisionShape3D
        {
            Name = "Collision"
        };
        
        // Generate a convex collision shape from the rock's mesh for realistic non-uniform scale collisions
        var convexShape = mesh.CreateConvexShape();
        collisionShape.Shape = convexShape;
        staticBody.AddChild(collisionShape);

        root.AddChild(staticBody);
        
        staticBody.Owner = root;
        meshInstance.Owner = root;
        collisionShape.Owner = root;
    }

    private Vector2 GetClosestPointOnPolygon(Vector2 p, Vector2[] poly)
    {
        Vector2 closest = p;
        float minD = float.MaxValue;
        int n = poly.Length;
        for (int i = 0; i < n; i++)
        {
            Vector2 a = poly[i];
            Vector2 b = poly[(i + 1) % n];
            Vector2 proj = GetClosestPointOnSegment(p, a, b);
            float d = p.DistanceTo(proj);
            if (d < minD)
            {
                minD = d;
                closest = proj;
            }
        }
        return closest;
    }

    private Vector2 GetClosestPointOnSegment(Vector2 p, Vector2 a, Vector2 b)
    {
        Vector2 ab = b - a;
        float l2 = ab.LengthSquared();
        if (l2 == 0f) return a;
        float t = Math.Max(0f, Math.Min(1f, Vector2Dot(p - a, ab) / l2));
        return a + t * ab;
    }

    private float Vector2Dot(Vector2 v1, Vector2 v2)
    {
        return v1.X * v2.X + v1.Y * v2.Y;
    }
}
