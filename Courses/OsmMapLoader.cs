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
    private static readonly System.Net.Http.HttpClient HttpClient = CreateHttpClient();

    private static System.Net.Http.HttpClient CreateHttpClient()
    {
        var client = new System.Net.Http.HttpClient();
        client.DefaultRequestHeaders.Add("User-Agent", "HeckleLinks/1.0 (contact: github.com/mmancl/HeckleGolfSim)");
        return client;
    }

    [Signal]
    public delegate void SearchCompletedEventHandler(Godot.Collections.Array results);

    [Signal]
    public delegate void CourseGeneratedEventHandler(bool success);

    private string _generationMessage = "";

    public string GetGenerationMessage()
    {
        return _generationMessage;
    }

    public async void DownloadAndGenerateCourse(double lat, double lon, string courseName)
    {
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
            EmitSignal(SignalName.CourseGenerated, false);
            return;
        }

        byte[]? satImageBytes = null;
        var bbox = CalculateBBoxFromOsmJson(osmJson, lat, lon);
        if (bbox != null)
        {
            satImageBytes = await DownloadSatelliteImageAsync(bbox.LonMin, bbox.LatMin, bbox.LonMax, bbox.LatMax, 2048, 2048);
        }
        else
        {
            GD.Print($"{LogPrefix} Warning: Could not calculate course bounding box for satellite tree detection.");
        }

        CallDeferred(MethodName.GenerateCourseDeferred, osmJson, courseName, lat, lon, satImageBytes ?? Array.Empty<byte>());
    }

    public void GenerateCourseDeferred(string jsonString, string courseName, double lat, double lon, byte[]? satImageBytes)
    {
        bool success = GenerateCourseFromData(jsonString, courseName, lat, lon, satImageBytes);
        EmitSignal(SignalName.CourseGenerated, success);
    }

    private async Task<string> DownloadOsmDataAsync(double lat, double lon, string courseName)
    {
        GD.Print($"{LogPrefix} Downloading OSM data for course '{courseName}' around {lat}, {lon}...");
        // Reduced radius from 3000 to 1500 to prevent Gateway Timeout (504) on Overpass API, and increased query timeout to 90s
        string query = $@"
        [out:json][timeout:90];
        (
          nwr(around:1500, {lat}, {lon})[""leisure""=""golf_course""];
          nwr(around:1500, {lat}, {lon})[""golf""];
          nwr(around:1500, {lat}, {lon})[""natural""=""water""];
          nwr(around:1500, {lat}, {lon})[""natural""=""tree""];
          nwr(around:1500, {lat}, {lon})[""natural""=""wood""];
          nwr(around:1500, {lat}, {lon})[""landuse""=""forest""];
        );
        out body;
        >;
        out skel qt;
        ";

        try
        {
            var content = new FormUrlEncodedContent(new[] { new KeyValuePair<string, string>("data", query) });
            var response = await HttpClient.PostAsync(OverpassUrl, content);
            if (!response.IsSuccessStatusCode)
            {
                GD.PrintErr($"{LogPrefix} Overpass API request failed with status: {response.StatusCode}");
                return "";
            }
            return await response.Content.ReadAsStringAsync();
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Failed to download OSM data: {ex}");
            return "";
        }
    }

    private bool GenerateCourseFromData(string jsonString, string courseName, double lat, double lon, byte[]? satImageBytes)
    {
        _generationMessage = "";
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
                return false;
            }

            // Reference origin is center of all nodes
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
                var outerWays = r.Members
                    .Where(m => m.Type == "way" && (m.Role == "outer" || string.IsNullOrEmpty(m.Role)))
                    .Select(m => ways.FirstOrDefault(w => w.Id == m.Ref))
                    .Where(w => w != null)
                    .ToList();

                foreach (var w in outerWays)
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
            }

            if (closestWay != null || closestRel != null)
            {
                GD.Print($"{LogPrefix} Identified main golf course boundary: '{targetCourseName}' with {coursePolygons.Count} polygon parts.");
            }
            else
            {
                GD.Print($"{LogPrefix} Warning: No leisure=golf_course boundary found near search coordinates. Allowing all elements.");
            }

            Func<Vector2, bool> isPointInMainCourse = (pt) => {
                if (coursePolygons.Count == 0) return true;
                foreach (var poly in coursePolygons)
                {
                    if (Geometry2D.IsPointInPolygon(pt, poly))
                        return true;
                    foreach (var vertex in poly)
                    {
                        if (pt.DistanceTo(vertex) < 50f)
                            return true;
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

            // Create elevated ground (Rough) as grid base with rolling hills
            var exclusionPolygons = new List<ExclusionPolygon>();

            var holeInfo = new Dictionary<string, HoleConfig>();
            var tees = new List<TeeConfig>();
            var lineOfPlayPaths = new List<List<Vector2>>();

            int parsedFairwaysCount = 0;
            int parsedGreensCount = 0;
            var waterPolygons = new List<Vector2[]>();
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
                        exclusionPolygons.Add(new ExclusionPolygon(uniquePoints, "tee"));
                        var indices = Geometry2D.TriangulatePolygon(uniquePoints);
                        if (indices.Length > 0)
                        {
                            var mesh = Create3DPolygonMesh(uniquePoints, indices, 0.01f, new Color(0.2f, 0.55f, 0.2f), "tee", exclusionPolygons);
                            var meshInstance = new MeshInstance3D
                            {
                                Name = $"tee_{way.Id}",
                                Mesh = mesh
                            };
                            rootNode.AddChild(meshInstance);
                            meshInstance.Owner = rootNode;
                        }
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
                    exclusionPolygons.Add(new ExclusionPolygon(uniquePoints, golfType));
                    var indices = Geometry2D.TriangulatePolygon(uniquePoints);
                    if (indices.Length > 0)
                    {
                        float heightOffset = golfType switch
                        {
                            "green" => 0.02f,
                            "fairway" => 0.01f,
                            _ => -0.15f // bunker
                        };

                        Color color = golfType switch
                        {
                            "green" => new Color(0.55f, 0.85f, 0.55f), // Bright healthy green
                            "fairway" => new Color(0.45f, 0.75f, 0.45f), // Medium fairway green
                            _ => new Color(0.85f, 0.75f, 0.55f) // Sand yellow
                        };

                        int surfaceTypeValue = golfType switch
                        {
                            "green" => 4, // SurfaceType.Green
                            "fairway" => 0, // SurfaceType.Fairway
                            _ => 2 // SurfaceType.Rough/Bunker
                        };

                        var mesh = Create3DPolygonMesh(uniquePoints, indices, heightOffset, color, golfType, exclusionPolygons);
                        var meshInstance = new MeshInstance3D
                        {
                            Name = $"{golfType}_{way.Id}",
                            Mesh = mesh
                        };
                        rootNode.AddChild(meshInstance);
                        meshInstance.Owner = rootNode;

                        // Add static body for specific surface zone
                        var staticBody = new StaticBody3D { Name = $"{golfType}_Static_{way.Id}" };
                        staticBody.SetMeta("surface_type", surfaceTypeValue);

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
                else if (isWaterFeature)
                {
                    var uniquePoints = points.Take(points.Count - 1).ToArray();
                    waterPolygons.Add(uniquePoints);
                    exclusionPolygons.Add(new ExclusionPolygon(uniquePoints, "water"));
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
                    if (satImage == null)
                    {
                        var uniquePoints = points.Take(points.Count - 1).ToArray();
                        if (uniquePoints.Length >= 3)
                        {
                            // Compute bounding box
                            float minX = uniquePoints.Min(p => p.X);
                            float maxX = uniquePoints.Max(p => p.X);
                            float minY = uniquePoints.Min(p => p.Y);
                            float maxY = uniquePoints.Max(p => p.Y);
                            
                            float width = maxX - minX;
                            float height = maxY - minY;
                            float area = width * height;
                            
                            // Spawn trees proportional to area (e.g. 1 tree per 250 sq meters), clamped
                            int numTrees = Mathf.Clamp((int)(area / 250f), 3, 25);
                            
                            var random = new Random((int)way.Id);
                            int spawned = 0;
                            for (int attempt = 0; attempt < numTrees * 3 && spawned < numTrees; attempt++)
                            {
                                float rx = minX + (float)random.NextDouble() * width;
                                float ry = minY + (float)random.NextDouble() * height;
                                var rp = new Vector2(rx, ry);
                                
                                if (Geometry2D.IsPointInPolygon(rp, uniquePoints))
                                {
                                    AddTreeAt(rootNode, new Vector3(rx, GetHeight(rx, ry), ry));
                                    spawned++;
                                }
                            }
                        }
                    }
                }

            }

            // Find the bounding box of the entire course using exclusion polygons
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
            int subdivisionsX = Mathf.Clamp((int)Math.Ceiling(courseWidth / 10.0f), 50, 300);
            int subdivisionsZ = Mathf.Clamp((int)Math.Ceiling(courseDepth / 10.0f), 50, 300);

            CreateRoughGround(courseMinX, courseMaxX, courseMinZ, courseMaxZ, subdivisionsX, subdivisionsZ, rootNode, exclusionPolygons);

            // Spawn individual trees
            foreach (var tId in treeNodeIds)
            {
                if (nodes.TryGetValue(tId, out var coord))
                {
                    float tx = (float)((coord.Lon - refLon) * metersPerLon);
                    float tz = -(float)((coord.Lat - refLat) * metersPerLat);
                    AddTreeAt(rootNode, new Vector3(tx, GetHeight(tx, tz), tz));
                }
            }

            // Spawn trees from satellite imagery
            if (satImage != null)
            {
                GD.Print($"{LogPrefix} Scanning satellite imagery for trees...");
                int satWidth = satImage.GetWidth();
                int satHeight = satImage.GetHeight();

                // Keep track of already placed tree positions to avoid overlap
                var placedTreePositions = new List<Vector2>();

                // Add existing OSM individual trees to placed positions
                foreach (var tId in treeNodeIds)
                {
                    if (nodes.TryGetValue(tId, out var coord))
                    {
                        float tx = (float)((coord.Lon - refLon) * metersPerLon);
                        float tz = -(float)((coord.Lat - refLat) * metersPerLat);
                        placedTreePositions.Add(new Vector2(tx, tz));
                    }
                }

                // Gather all candidate tree positions
                var candidatePoints = new List<Vector2>();
                float spacing = 5.0f; // Grid spacing in meters
                float minDistanceBetweenTrees = 4.0f; // Minimum distance to keep trees apart

                for (float rx = courseMinX; rx <= courseMaxX; rx += spacing)
                {
                    for (float rz = courseMinZ; rz <= courseMaxZ; rz += spacing)
                    {
                        var pt = new Vector2(rx, rz);
                        if (!isPointInMainCourse(pt)) continue;

                        // Check if the point is in any play surface exclusion zone
                        bool insideExclusion = false;
                        foreach (var excl in exclusionPolygons)
                        {
                            if (rx >= excl.MinX && rx <= excl.MaxX && rz >= excl.MinY && rz <= excl.MaxY)
                            {
                                if (Geometry2D.IsPointInPolygon(pt, excl.Polygon))
                                {
                                    insideExclusion = true;
                                    break;
                                }
                            }
                        }
                        if (insideExclusion) continue;

                        // Check if the point is too close to the line of play of any hole (keeps direct shots clear)
                        bool tooCloseToLineOfPlay = false;
                        foreach (var path in lineOfPlayPaths)
                        {
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
                        if (tooCloseToLineOfPlay) continue;

                        // Map local coordinate (rx, rz) to image pixel coordinates (px, py)
                        float normX = (rx - courseMinX) / (courseMaxX - courseMinX);
                        float normY = (rz - courseMinZ) / (courseMaxZ - courseMinZ);
                        int px = Mathf.Clamp((int)(normX * satWidth), 0, satWidth - 1);
                        int py = Mathf.Clamp((int)(normY * satHeight), 0, satHeight - 1);

                        Color pixelColor = GetAveragedPixel(satImage, px, py);
                        float variance = GetLocalVariance(satImage, px, py);
                        if (IsTreeColor(pixelColor) && variance > 0.005f)
                        {
                            candidatePoints.Add(pt);
                        }
                    }
                }

                GD.Print($"{LogPrefix} Found {candidatePoints.Count} tree candidate locations from satellite imagery.");

                // Limit maximum satellite trees to avoid performance issues
                int maxSatelliteTrees = 10000;
                var selectedPoints = new List<Vector2>();
                if (candidatePoints.Count > maxSatelliteTrees)
                {
                    var rnd = new Random(42); // Seeded for deterministic generation
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

                // Spawn selected trees, checking distances to avoid overlapping
                int satelliteTreesCount = 0;
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
                        float height = GetHeight(pt.X, pt.Y);
                        AddTreeAt(rootNode, new Vector3(pt.X, height, pt.Y));
                        placedTreePositions.Add(pt);
                        satelliteTreesCount++;
                    }
                }
                GD.Print($"{LogPrefix} Placed {satelliteTreesCount} trees based on satellite imagery analysis.");

                // Spawn random bushes clustered around a subset of trees rather than randomly everywhere
                if (placedTreePositions.Count > 0)
                {
                    GD.Print($"{LogPrefix} Placing bushes clustered around trees...");
                    var bushRnd = new Random(99); // Seeded for deterministic generation
                    int bushCount = 0;
                    int maxBushes = 1200;
                    var placedBushPositions = new List<Vector2>();

                    // Select a random subset of trees (e.g., 35% of placed trees) to have bushes around them
                    var treeIndices = Enumerable.Range(0, placedTreePositions.Count).OrderBy(x => bushRnd.Next()).ToList();
                    int treesWithBushesCount = (int)(placedTreePositions.Count * 0.35);

                    for (int tIdx = 0; tIdx < treesWithBushesCount && bushCount < maxBushes; tIdx++)
                    {
                        var treePos = placedTreePositions[treeIndices[tIdx]];
                        // Spawn 1 to 3 bushes around this tree
                        int numBushesAroundTree = bushRnd.Next(1, 4);

                        for (int b = 0; b < numBushesAroundTree && bushCount < maxBushes; b++)
                        {
                            // Generate a random angle and distance from the tree base
                            double angle = bushRnd.NextDouble() * Math.PI * 2.0;
                            float distance = 1.5f + (float)bushRnd.NextDouble() * 2.0f; // 1.5m to 3.5m from tree
                            float bx = treePos.X + (float)Math.Cos(angle) * distance;
                            float bz = treePos.Y + (float)Math.Sin(angle) * distance;
                            var pt = new Vector2(bx, bz);

                            if (!isPointInMainCourse(pt)) continue;

                            // Must NOT be inside any exclusion polygon (not green, fairway, bunker, water, tee)
                            bool insideExclusion = false;
                            foreach (var excl in exclusionPolygons)
                            {
                                if (bx >= excl.MinX && bx <= excl.MaxX && bz >= excl.MinY && bz <= excl.MaxY)
                                {
                                    if (Geometry2D.IsPointInPolygon(pt, excl.Polygon))
                                    {
                                        insideExclusion = true;
                                        break;
                                    }
                                }
                            }
                            if (insideExclusion) continue;

                            // Must NOT be too close to line of play
                            bool tooCloseToLineOfPlay = false;
                            foreach (var path in lineOfPlayPaths)
                            {
                                for (int i = 0; i < path.Count - 1; i++)
                                {
                                    if (DistanceToSegment(pt, path[i], path[i + 1]) < 8.0f) // slightly closer is fine near trees
                                    {
                                        tooCloseToLineOfPlay = true;
                                        break;
                                    }
                                }
                                if (tooCloseToLineOfPlay) break;
                            }
                            if (tooCloseToLineOfPlay) continue;

                            // Must NOT be too close to other placed bushes
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

                            // Place the bush!
                            float bh = GetHeight(bx, bz);
                            AddBushAt(rootNode, new Vector3(bx, bh, bz));
                            placedBushPositions.Add(pt);
                            bushCount++;
                        }
                    }
                    GD.Print($"{LogPrefix} Placed {bushCount} bushes clustered around trees.");
                }
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

                    var greenPoints = new Vector2[8];
                    for (int i = 0; i < 8; i++)
                    {
                        float angle = i * Mathf.Pi / 4f;
                        greenPoints[i] = greenCenter + new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * 12.0f;
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
            cameraResource.Set("fov", 25.0f);
            cameraResource.Set("far", 400.0f);
            phantomCam.Set("camera_3d_resource", cameraResource);

            phantomCam.Transform = new Transform3D(
                new Basis(new Vector3(-4.37114e-08f, 0f, -1f), new Vector3(0f, 1f, 0f), new Vector3(1f, 0f, -4.37114e-08f)),
                new Vector3(-6.04467f, 3.02244f, 0f)
            );
            phantomCam.Set("follow_offset", new Vector3(-2f, 1.6f, 0f));
            phantomCam.Set("follow_damping", true);
            phantomCam.Set("follow_damping_value", new Vector3(0.4f, 0.1f, 0.1f));
            phantomCam.Set("dead_zone_height", 0.204f);
            rootNode.AddChild(phantomCam);
            phantomCam.Owner = rootNode;

            var camera3d = new Camera3D { Name = "Camera3D" };
            camera3d.Fov = 25.0f;
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
            sky3D.Set("current_time", 15.682f);
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

            // Clouds
            skyMaterial.SetShaderParameter("clouds_visible", true);
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
            skyMaterial.SetShaderParameter("cumulus_clouds_visible", true);
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

            var sky = new Sky { SkyMaterial = skyMaterial };
            var env = new Godot.Environment
            {
                BackgroundMode = Godot.Environment.BGMode.Sky,
                Sky = sky,
                AmbientLightSource = Godot.Environment.AmbientSource.Sky,
                AmbientLightColor = new Color(0.9631823f, 0.9631823f, 0.9631823f, 1f),
                ReflectedLightSource = Godot.Environment.ReflectionSource.Sky,
                TonemapMode = Godot.Environment.ToneMapper.Aces,
                TonemapWhite = 6.0f,
                GlowEnabled = true,
                GlowIntensity = 0.4f,
                GlowBloom = 0.1f,
                GlowBlendMode = Godot.Environment.GlowBlendModeEnum.Additive
            };
            sky3D.Environment = env;

            var skyCameraAttrs = new CameraAttributesPractical
            {
                DofBlurFarEnabled = true,
                DofBlurFarDistance = 150.0f,
                DofBlurFarTransition = 100.0f,
                DofBlurAmount = 0.08f
            };
            sky3D.CameraAttributes = skyCameraAttrs;

            rootNode.AddChild(sky3D);
            sky3D.Owner = rootNode;

            // Add SunLight
            var sunLight = new DirectionalLight3D { Name = "SunLight" };
            sunLight.LightEnergy = 0.5f;
            sunLight.ShadowEnabled = true;
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
            timeOfDay.Set("total_hours", 15.682f);
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

            GD.Print($"{LogPrefix} Course '{courseName}' generated successfully.");
            return true;
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Failed to query or build OSM course: {ex}");
            return false;
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

        // Helper function to calculate exclusions depression for overlapping surfaces
        float GetExclDepression(Vector2 pt)
        {
            if (exclusions == null) return 0f;
            if (golfType == "fairway" || golfType == "tee" || golfType == "bunker")
            {
                foreach (var excl in exclusions)
                {
                    if (golfType == "fairway")
                    {
                        if ((excl.GolfType == "green" || excl.GolfType == "bunker") && Geometry2D.IsPointInPolygon(pt, excl.Polygon))
                        {
                            return 0.3f;
                        }
                    }
                    else if (golfType == "tee")
                    {
                        if (excl.GolfType == "green" && Geometry2D.IsPointInPolygon(pt, excl.Polygon))
                        {
                            return 0.3f;
                        }
                    }
                    else if (golfType == "bunker")
                    {
                        if (excl.GolfType == "green" && Geometry2D.IsPointInPolygon(pt, excl.Polygon))
                        {
                            return 0.3f;
                        }
                    }
                }
            }
            return 0f;
        }

        var arrayMesh = new ArrayMesh();
        int numTopVertices = subdividedTriangles.Count * 3;
        int M = points.Length;
        int numSkirtVertices = M * 6;
        int totalVertices = numTopVertices + numSkirtVertices;

        var vertices = new Vector3[totalVertices];
        var normals = new Vector3[totalVertices];
        var colors = new Color[totalVertices];
        var uvs = new Vector2[totalVertices];
        var newIndices = new int[totalVertices];

        for (int i = 0; i < subdividedTriangles.Count; i++)
        {
            var tri = subdividedTriangles[i];
            Vector2[] triPts = { tri.A, tri.B, tri.C };

            for (int j = 0; j < 3; j++)
            {
                int idx = i * 3 + j;
                float vx = triPts[j].X;
                float vz = triPts[j].Y;
                float dep = GetExclDepression(triPts[j]);
                float vy = GetHeight(vx, vz) + height - dep;
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

        float rampWidth = golfType switch
        {
            "green" => 4.5f,
            "fairway" => 3.6f,
            "tee" => 3.0f,
            "bunker" => 0.05f,
            "water" => 0.05f,
            _ => 0.5f
        };

        float bottomHeightOffset = golfType switch
        {
            "water" => -2.5f,
            "bunker" => -0.3f,
            _ => -0.8f
        };

        for (int i = 0; i < M; i++)
        {
            int next = (i + 1) % M;

            var n_i = normalsOut[i];
            var n_next = normalsOut[next];

            var p_top_i = points[i];
            var p_top_next = points[next];
            var p_bot_i = points[i] + n_i * rampWidth;
            var p_bot_next = points[next] + n_next * rampWidth;

            float dep_top_i = GetExclDepression(p_top_i);
            float dep_top_next = GetExclDepression(p_top_next);
            float dep_bot_i = GetExclDepression(p_bot_i);
            float dep_bot_next = GetExclDepression(p_bot_next);

            var v_top_i = new Vector3(p_top_i.X, GetHeight(p_top_i.X, p_top_i.Y) + height - dep_top_i, p_top_i.Y);
            var v_top_next = new Vector3(p_top_next.X, GetHeight(p_top_next.X, p_top_next.Y) + height - dep_top_next, p_top_next.Y);
            var v_bot_i = new Vector3(p_bot_i.X, GetHeight(p_bot_i.X, p_bot_i.Y) + bottomHeightOffset - dep_bot_i, p_bot_i.Y);
            var v_bot_next = new Vector3(p_bot_next.X, GetHeight(p_bot_next.X, p_bot_next.Y) + bottomHeightOffset - dep_bot_next, p_bot_next.Y);

            var norm_top_i = GetTerrainNormal(p_top_i.X, p_top_i.Y);
            var norm_top_next = GetTerrainNormal(p_top_next.X, p_top_next.Y);
            var norm_bot_i = GetTerrainNormal(p_bot_i.X, p_bot_i.Y);
            var norm_bot_next = GetTerrainNormal(p_bot_next.X, p_bot_next.Y);

            var uv_top_i = p_top_i * 0.1f;
            var uv_top_next = p_top_next * 0.1f;
            var uv_bot_i = p_bot_i * 0.1f;
            var uv_bot_next = p_bot_next * 0.1f;

            int baseIdx = numTopVertices + i * 6;

            // Triangle 1: V_top_i, V_top_next, V_bot_i
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

            vertices[baseIdx + 2] = v_bot_i;
            normals[baseIdx + 2] = norm_bot_i;
            colors[baseIdx + 2] = color;
            uvs[baseIdx + 2] = uv_bot_i;
            newIndices[baseIdx + 2] = baseIdx + 2;

            // Triangle 2: V_bot_i, V_top_next, V_bot_next
            vertices[baseIdx + 3] = v_bot_i;
            normals[baseIdx + 3] = norm_bot_i;
            colors[baseIdx + 3] = color;
            uvs[baseIdx + 3] = uv_bot_i;
            newIndices[baseIdx + 3] = baseIdx + 3;

            vertices[baseIdx + 4] = v_top_next;
            normals[baseIdx + 4] = norm_top_next;
            colors[baseIdx + 4] = color;
            uvs[baseIdx + 4] = uv_top_next;
            newIndices[baseIdx + 4] = baseIdx + 4;

            vertices[baseIdx + 5] = v_bot_next;
            normals[baseIdx + 5] = norm_bot_next;
            colors[baseIdx + 5] = color;
            uvs[baseIdx + 5] = uv_bot_next;
            newIndices[baseIdx + 5] = baseIdx + 5;
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
        if (golfType == "green")
        {
            mat = CreateGrassShaderMaterial("res://Courses/Environments/grass-green/albedo.png", 1, 0.0f, 0.0f, new Color(1f, 1f, 1f), 0.85f);
        }
        else if (golfType == "fairway" || golfType == "tee")
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

    private float GetHeight(float x, float z)
    {
        double h = Math.Sin(x * 0.01) * Math.Cos(z * 0.01) * 1.5
                 + Math.Sin(x * 0.03 + z * 0.02) * 0.5
                 + Math.Cos(x * 0.07 - z * 0.05) * 0.125;
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
                bool isInsidePlay = false;
                float minDistPlay = float.MaxValue;
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
                        else
                        {
                            if (isInside)
                            {
                                isInsidePlay = true;
                                minDistPlay = 0f;
                            }
                            else
                            {
                                float dist = DistanceToPolygon(vertexPoint, excl.Polygon);
                                if (dist < minDistPlay) minDistPlay = dist;
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
                    depBunker = 0.8f;
                }
                else if (minDistBunker < 3.0f)
                {
                    float t = 1.0f - (minDistBunker / 3.0f);
                    float smoothT = t * t * (3.0f - 2.0f * t);
                    depBunker = smoothT * 0.15f;
                }
                
                float bufferPlay = margin * 0.5f;
                float depPlay = 0f;
                if (isInsidePlay || minDistPlay < bufferPlay)
                {
                    depPlay = 0.8f;
                }
                else if (minDistPlay < margin)
                {
                    float t = 1.0f - ((minDistPlay - bufferPlay) / (margin - bufferPlay));
                    float smoothT = t * t * (3.0f - 2.0f * t);
                    depPlay = smoothT * 0.8f;
                }
                
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

        public ExclusionPolygon(Vector2[] polygon, string? golfType = "")
        {
            Polygon = polygon;
            GolfType = golfType;
            MinX = float.MaxValue;
            MaxX = float.MinValue;
            MinY = float.MaxValue;
            MaxY = float.MinValue;
            foreach (var p in polygon)
            {
                if (p.X < MinX) MinX = p.X;
                if (p.X > MaxX) MaxX = p.X;
                if (p.Y < MinY) MinY = p.Y;
                if (p.Y > MaxY) MaxY = p.Y;
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

        // Vegetation check (Hue: yellow-green to cyan-green, saturation filter)
        // Relaxed saturation threshold from 0.18f to 0.13f to capture olive/desaturated trees
        bool isGreenish = (h >= 0.12f && h <= 0.48f) && (s > 0.13f);

        // Brightness check (trees are darker canopy)
        // Lowered minimum value from 0.08f back to 0.05f to capture darker tree canopy interiors
        bool isDarkEnough = (v > 0.05f && v < 0.28f);

        // Excess green index check to confirm it's actually vegetation
        // Adjusted from 0.02f down to -0.005f to allow less intense green foliage
        float exG = 2.0f * g - r - b;
        bool hasExG = exG > -0.005f;

        return isGreenish && isDarkEnough && hasExG;
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
                var outerWays = r.Members
                    .Where(m => m.Type == "way" && (m.Role == "outer" || string.IsNullOrEmpty(m.Role)))
                    .Select(m => ways.FirstOrDefault(w => w.Id == m.Ref))
                    .Where(w => w != null)
                    .ToList();

                foreach (var w in outerWays)
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
            }

            Func<Vector2, bool> isPointInMainCourse = (pt) => {
                if (coursePolygons.Count == 0) return true;
                foreach (var poly in coursePolygons)
                {
                    if (Geometry2D.IsPointInPolygon(pt, poly))
                        return true;
                    foreach (var vertex in poly)
                    {
                        if (pt.DistanceTo(vertex) < 50f)
                            return true;
                    }
                }
                return false;
            };

            var exclusionPolygons = new List<ExclusionPolygon>();

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
                    bool isMainBoundary = way.Tags.TryGetValue("leisure", out var l) && l == "golf_course";
                    if (!isMainBoundary)
                        continue;
                }

                way.Tags.TryGetValue("golf", out string? golfType);
                if (golfType == "hole")
                {
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

            return new BBox { LonMin = lonMin, LatMin = latMin, LonMax = lonMax, LatMax = latMax };
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
        exclusionPolygons.Add(new ExclusionPolygon(uniquePoints, golfType));
        var indices = Geometry2D.TriangulatePolygon(uniquePoints);
        if (indices.Length > 0)
        {
            float heightOffset = golfType == "green" ? 0.02f : (golfType == "bunker" ? -0.15f : 0.01f);
            Color color = golfType == "green" ? new Color(0.55f, 0.85f, 0.55f) : new Color(0.45f, 0.75f, 0.45f);
            int surfaceTypeValue = golfType == "green" ? 4 : 0;

            var mesh = Create3DPolygonMesh(uniquePoints, indices, heightOffset, color, golfType, exclusionPolygons);
            var meshInstance = new MeshInstance3D
            {
                Name = $"{golfType}_{idSuffix}",
                Mesh = mesh
            };
            rootNode.AddChild(meshInstance);
            meshInstance.Owner = rootNode;

            var staticBody = new StaticBody3D { Name = $"{golfType}_Static_{idSuffix}" };
            staticBody.SetMeta("surface_type", surfaceTypeValue);

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

    private void CreateTeeBoxMesh(Node3D rootNode, Vector2[] uniquePoints, string idSuffix, List<ExclusionPolygon> exclusionPolygons)
    {
        exclusionPolygons.Add(new ExclusionPolygon(uniquePoints, "tee"));
        var indices = Geometry2D.TriangulatePolygon(uniquePoints);
        if (indices.Length > 0)
        {
            var mesh = Create3DPolygonMesh(uniquePoints, indices, 0.01f, new Color(0.45f, 0.75f, 0.45f), "tee", exclusionPolygons);
            var meshInstance = new MeshInstance3D
            {
                Name = $"tee_{idSuffix}",
                Mesh = mesh
            };
            rootNode.AddChild(meshInstance);
            meshInstance.Owner = rootNode;
        }
    }

    private float DistanceToSegment(Vector2 p, Vector2 a, Vector2 b)
    {
        Vector2 ab = b - a;
        Vector2 ap = p - a;
        float ab2 = ab.LengthSquared();
        if (ab2 == 0f) return ap.Length();
        
        float t = Mathf.Clamp(ap.Dot(ab) / ab2, 0f, 1f);
        Vector2 projection = a + t * ab;
        return p.DistanceTo(projection);
    }

    private float DistanceToPolygon(Vector2 p, Vector2[] poly)
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
}
