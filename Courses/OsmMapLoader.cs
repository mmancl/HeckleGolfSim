using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Security;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;
using Godot;

namespace HeckleLinks.Courses;

[GlobalClass]
public partial class OsmMapLoader : Node
{
    private static readonly string LogPrefix = "[OsmMapLoader]";
    private static readonly string[] OverpassEndpoints = new[]
    {
        "https://lz4.overpass-api.de/api/interpreter",
        "https://overpass-api.de/api/interpreter",
        "https://z.overpass-api.de/api/interpreter"
    };
    private static readonly System.Net.Http.HttpClient HttpClient = CreateHttpClient();

    private static System.Net.Http.HttpClient CreateHttpClient()
    {
        var handler = new SocketsHttpHandler
        {
            PooledConnectionLifetime = TimeSpan.FromMinutes(15),
            ConnectTimeout = TimeSpan.FromSeconds(30),
            SslOptions = new SslClientAuthenticationOptions
            {
                AllowRenegotiation = true,
                RemoteCertificateValidationCallback = (sender, cert, chain, errors) =>
                {
                    if (errors == SslPolicyErrors.None)
                        return true;

                    // Allow trusted domain patterns for public GIS and map services when system root stores fail
                    if (sender is HttpRequestMessage request && request.RequestUri != null)
                    {
                        string host = request.RequestUri.Host.ToLowerInvariant();
                        if (host.EndsWith("overpass-api.de") ||
                            host.EndsWith("openstreetmap.de") ||
                            host.EndsWith("openstreetmap.org") ||
                            host.EndsWith("komoot.io") ||
                            host.EndsWith("nationalmap.gov") ||
                            host.EndsWith("open-meteo.com") ||
                            host.EndsWith("amazonaws.com") ||
                            host.EndsWith("arcgisonline.com"))
                        {
                            return true;
                        }
                    }

                    if (cert != null)
                    {
                        string subject = cert.Subject?.ToLowerInvariant() ?? "";
                        string issuer = cert.Issuer?.ToLowerInvariant() ?? "";
                        if (subject.Contains("openstreetmap") ||
                            subject.Contains("overpass") ||
                            subject.Contains("komoot") ||
                            subject.Contains("arcgis") ||
                            subject.Contains("nationalmap") ||
                            issuer.Contains("let's encrypt") ||
                            issuer.Contains("isrg root"))
                        {
                            return true;
                        }
                    }

                    return false;
                }
            }
        };

        var client = new System.Net.Http.HttpClient(handler);
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

    private record GolfSearchResult(string Name, double Lat, double Lon, string Location, int HoleCount = 0, string LastUpdated = "", bool IsCatalog = false, bool IsPgaTour = false);

    private void ReportProgress(string message)
    {
        Callable.From(() =>
        {
            if (IsInstanceValid(this))
            {
                EmitSignal(SignalName.DownloadProgress, message);
            }
        }).CallDeferred();
    }

    private void EmitCourseGenerated(bool success)
    {
        Callable.From(() =>
        {
            if (IsInstanceValid(this))
            {
                EmitSignal(SignalName.CourseGenerated, success);
            }
        }).CallDeferred();
    }

    private string _generationMessage = "";
    private ElevationMap? _currentElevationMap;
    private double[]? _downloadedSatelliteImageBounds;
    private byte[]? _downloadedCoursePhotoBytes;
    private double _refLat;
    private double _refLon;
    private const double SatelliteImageAspectRatio = 1.0;
    private double _metersPerLat = 111320.0;
    private double _metersPerLon = 111320.0;

    public string GetGenerationMessage()
    {
        return _generationMessage;
    }

    public int MaxTrees { get; set; } = 6000;
    public bool GenerateWaterLongGrass { get; set; } = true;
    public bool Create18HolePermutations { get; set; } = false;
    public bool GenerateBushes { get; set; } = true;
    public bool GenerateCartPaths { get; set; } = true;
    public bool Generate3dBunkers { get; set; } = true;
    public bool HasCustomGenerationSettings { get; set; } = false;

    public void LoadCourseGenerationSettings(bool forceReload = false)
    {
        if (HasCustomGenerationSettings && !forceReload)
        {
            return;
        }

        try
        {
            var cfg = new ConfigFile();
            if (cfg.Load("user://osm_download_settings.cfg") == Error.Ok)
            {
                if (cfg.HasSection("course_generation"))
                {
                    MaxTrees = (int)cfg.GetValue("course_generation", "max_trees", 6000);
                    GenerateWaterLongGrass = (bool)cfg.GetValue("course_generation", "generate_water_long_grass", true);
                    Create18HolePermutations = (bool)cfg.GetValue("course_generation", "create_18_hole_permutations", false);
                    GenerateBushes = (bool)cfg.GetValue("course_generation", "generate_bushes", true);
                    GenerateCartPaths = (bool)cfg.GetValue("course_generation", "generate_cart_paths", true);
                    Generate3dBunkers = (bool)cfg.GetValue("course_generation", "generate_3d_bunkers", true);
                    HasCustomGenerationSettings = true;
                    GD.Print($"{LogPrefix} Loaded course generation settings from user config: MaxTrees={MaxTrees}, WaterLongGrass={GenerateWaterLongGrass}, 18HolePermutations={Create18HolePermutations}, Bushes={GenerateBushes}, CartPaths={GenerateCartPaths}, 3dBunkers={Generate3dBunkers}.");
                }
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Failed to read user course generation settings: {ex.Message}");
        }
    }

    public void DownloadAndGenerateCourse(double lat, double lon, string courseName)
    {
        DownloadAndGenerateCourse(lat, lon, courseName, false, "");
    }

    public void DownloadAndGenerateCourse(double lat, double lon, string courseName, bool isCached)
    {
        DownloadAndGenerateCourse(lat, lon, courseName, isCached, "");
    }

    public async void DownloadAndGenerateCourse(double lat, double lon, string courseName, bool isCached, string location = "")
    {
        LoadCourseGenerationSettings();
        _generationMessage = "";
        var (safeName, courseDir, globalCourseDir, _) = ResolveCoursePathAndTitle(courseName, lat, lon, location);

        if (!Directory.Exists(globalCourseDir))
        {
            Directory.CreateDirectory(globalCourseDir);
        }

        string tscnPath = $"{courseDir}/course.tscn";
        string jsonPath = $"{courseDir}/course.json";
        string globalTscnPath = ProjectSettings.GlobalizePath(tscnPath);
        string globalJsonPath = ProjectSettings.GlobalizePath(jsonPath);

        ReportProgress(isCached ? $"Loading cached map for '{courseName}'..." : $"Preparing map for '{courseName}'...");
        string osmJson = await DownloadOsmDataAsync(lat, lon, courseName, isCached);
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
                _generationMessage = isCached
                    ? $"Error: Cached course geometry for '{courseName}' could not be loaded. Please check that cached geometry assets are installed."
                    : "Error: Course download timed out or failed. Please retry the download, and if it continues to fail, please log a bug.";
            }
            EmitCourseGenerated(false);
            return;
        }

        _downloadedCoursePhotoBytes = null;
        ReportProgress("Downloading course photo...");
        _downloadedCoursePhotoBytes = await DownloadCoursePhotoAsync(courseName, location, lat, lon);

        byte[]? satImageBytes = null;
        _downloadedSatelliteImageBounds = null;
        var bbox = CalculateBBoxFromOsmJson(osmJson, lat, lon, courseName);
        if (bbox != null)
        {
            bool isMobilePlatform = OS.GetName() == "Android" || OS.GetName() == "iOS";
            int satResolution = isMobilePlatform ? 1024 : 2048;
            int satWidth = satResolution;
            int satHeight = satResolution;
            var satelliteBbox = GetSatelliteBBoxForAspectRatio(bbox, SatelliteImageAspectRatio);
            ReportProgress("Downloading satellite imagery...");
            var satelliteResult = await DownloadSatelliteImageAsync(satelliteBbox, satWidth, satHeight);
            if (satelliteResult != null)
            {
                satImageBytes = satelliteResult.ImageBytes;
                _downloadedSatelliteImageBounds = satelliteResult.LocalBounds;
            }
            
            ReportProgress("Downloading terrain elevation data...");
            await DownloadElevationDataAsync(bbox, globalCourseDir);
        }
        else
        {
            GD.Print($"{LogPrefix} Warning: Could not calculate course bounding box for satellite tree detection.");
        }

        CallDeferred(MethodName.GenerateCourseDeferred, osmJson, courseName, lat, lon, satImageBytes ?? Array.Empty<byte>(), location);
    }

    public void GenerateCourseDeferred(string jsonString, string courseName, double lat, double lon, byte[]? satImageBytes)
    {
        GenerateCourseDeferred(jsonString, courseName, lat, lon, satImageBytes, "");
    }

    public async void GenerateCourseDeferred(string jsonString, string courseName, double lat, double lon, byte[]? satImageBytes, string location = "")
    {
        LoadCourseGenerationSettings();
        bool success = await GenerateCourseFromDataAsync(jsonString, courseName, lat, lon, satImageBytes, location);
        EmitCourseGenerated(success);
    }

    private sealed record CourseVariant(
        string Title,
        string SourceCourse,
        string VariantType,
        string[] SubCourses,
        HashSet<long> HoleWayIds,
        string OsmRelationName,
        string OsmRelationId);

    private async Task<bool> GenerateCourseFromDataAsync(string jsonString, string courseName, double lat, double lon, byte[]? satImageBytes, string location = "")
    {
        LoadCourseGenerationSettings();

        List<CourseVariant> variants = new();
        if (Create18HolePermutations)
        {
            try
            {
                variants = BuildCourseVariants(jsonString, courseName);
            }
            catch (JsonException ex)
            {
                GD.PrintErr($"{LogPrefix} Failed to inspect OSM course variants: {ex.Message}");
                _generationMessage = "Error: Could not read course layout data from OpenStreetMap.";
                return false;
            }
        }
        else
        {
            GD.Print($"{LogPrefix} 18-hole permutations disabled by course generation settings. Generating single course with all holes.");
        }

        if (variants.Count == 0)
        {
            return await GenerateCourseVariantCoreAsync(jsonString, courseName, lat, lon, satImageBytes, null, null, location);
        }

        string baseSafeName = string.Concat(courseName.Split(Path.GetInvalidFileNameChars())).Replace(" ", "_");
        string sourceElevationPath = Path.Combine(
            ProjectSettings.GlobalizePath($"user://courses/{baseSafeName}"),
            "elevation.dat");
        var availableVariants = variants.Select(variant => variant.Title).ToList();
        var generatedVariants = new List<string>();

        for (int i = 0; i < variants.Count; i++)
        {
            var variant = variants[i];
            ReportProgress($"Generating course variant {i + 1} of {variants.Count}: {variant.Title}...");

            string variantSafeName = string.Concat(variant.Title.Split(Path.GetInvalidFileNameChars())).Replace(" ", "_");
            string variantDirectory = ProjectSettings.GlobalizePath($"user://courses/{variantSafeName}");
            try
            {
                Directory.CreateDirectory(variantDirectory);
                string variantElevationPath = Path.Combine(variantDirectory, "elevation.dat");
                if (File.Exists(sourceElevationPath) && !string.Equals(sourceElevationPath, variantElevationPath, StringComparison.OrdinalIgnoreCase))
                {
                    File.Copy(sourceElevationPath, variantElevationPath, true);
                }
            }
            catch (IOException ex)
            {
                GD.PrintErr($"{LogPrefix} Failed to prepare elevation data for '{variant.Title}': {ex.Message}");
                _generationMessage = $"Error: Could not prepare elevation data for '{variant.Title}'.";
                return false;
            }
            catch (UnauthorizedAccessException ex)
            {
                GD.PrintErr($"{LogPrefix} Access denied preparing files for '{variant.Title}': {ex.Message}");
                _generationMessage = $"Error: Access denied while preparing '{variant.Title}'.";
                return false;
            }

            bool success = await GenerateCourseVariantCoreAsync(
                jsonString,
                variant.Title,
                lat,
                lon,
                satImageBytes,
                variant,
                availableVariants,
                location);
            if (!success)
            {
                string failure = _generationMessage;
                _generationMessage = $"Generated {generatedVariants.Count} of {variants.Count} course variants. Failed on '{variant.Title}'. {failure}";
                return false;
            }

            generatedVariants.Add(variant.Title);
        }

        _generationMessage = $"Successfully generated {generatedVariants.Count} course variants: {string.Join(", ", generatedVariants)}.";
        return true;
    }

    private static List<CourseVariant> BuildCourseVariants(string jsonString, string courseName)
    {
        using var doc = JsonDocument.Parse(jsonString);
        if (!doc.RootElement.TryGetProperty("elements", out var elements) || elements.ValueKind != JsonValueKind.Array)
        {
            return new List<CourseVariant>();
        }

        var routeByHoleId = new Dictionary<long, string>();
        var routes = new Dictionary<string, (string Name, HashSet<string> Refs, HashSet<long> HoleWayIds)>(StringComparer.OrdinalIgnoreCase);

        foreach (var element in elements.EnumerateArray())
        {
            if (!element.TryGetProperty("type", out var typeProp) || typeProp.GetString() != "way" ||
                !element.TryGetProperty("id", out var idProp) || !idProp.TryGetInt64(out long wayId) ||
                !element.TryGetProperty("tags", out var tagsProp) || tagsProp.ValueKind != JsonValueKind.Object ||
                !tagsProp.TryGetProperty("golf", out var golfProp) || golfProp.GetString() != "hole")
            {
                continue;
            }

            if (!element.TryGetProperty("nodes", out var nodesProp) || nodesProp.ValueKind != JsonValueKind.Array || nodesProp.GetArrayLength() < 2)
            {
                continue;
            }

            var tags = tagsProp.EnumerateObject().ToDictionary(tag => tag.Name, tag => tag.Value.GetString() ?? "");
            string subCourse = ExtractSubCourseName(tags);
            if (string.IsNullOrWhiteSpace(subCourse))
            {
                continue;
            }

            string refValue = tags.GetValueOrDefault("ref", "").Trim();
            if (string.IsNullOrWhiteSpace(refValue))
            {
                continue;
            }

            if (!routes.TryGetValue(subCourse, out var route))
            {
                route = (subCourse, new HashSet<string>(StringComparer.OrdinalIgnoreCase), new HashSet<long>());
            }

            if (route.Refs.Add(refValue))
            {
                route.HoleWayIds.Add(wayId);
            }
            routeByHoleId[wayId] = route.Name;
            routes[subCourse] = route;
        }

        var nineHoleRoutes = routes.Values
            .Where(route => route.Refs.Count == 9)
            .OrderBy(route => route.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (nineHoleRoutes.Count == 0)
        {
            return new List<CourseVariant>();
        }

        var routeByName = nineHoleRoutes.ToDictionary(route => route.Name, StringComparer.OrdinalIgnoreCase);
        var relationVariants = new Dictionary<string, (string Id, string[] SubCourses, string Name, HashSet<long> HoleWayIds)>(StringComparer.Ordinal);
        foreach (var element in elements.EnumerateArray())
        {
            if (!element.TryGetProperty("type", out var typeProp) || typeProp.GetString() != "relation" ||
                !element.TryGetProperty("tags", out var tagsProp) || tagsProp.ValueKind != JsonValueKind.Object)
            {
                continue;
            }

            bool isCourseRelation =
                (tagsProp.TryGetProperty("golf", out var golfProp) && golfProp.GetString() == "course") ||
                (tagsProp.TryGetProperty("golf:course", out var courseProp) && courseProp.GetString() == "18_hole");
            if (!isCourseRelation || !element.TryGetProperty("members", out var membersProp) || membersProp.ValueKind != JsonValueKind.Array)
            {
                continue;
            }

            if (!element.TryGetProperty("id", out var relationIdProp))
            {
                continue;
            }
            string relationId = relationIdProp.ToString();
            string relationName = tagsProp.TryGetProperty("name", out var nameProp) ? nameProp.GetString() ?? "" : "";

            var memberRouteOrder = new List<string>();
            foreach (var member in membersProp.EnumerateArray())
            {
                if (!member.TryGetProperty("type", out var memberType) || memberType.GetString() != "way" ||
                    !member.TryGetProperty("ref", out var memberRef) || !memberRef.TryGetInt64(out long memberWayId) ||
                    !routeByHoleId.TryGetValue(memberWayId, out var routeName))
                {
                    continue;
                }
                if (!memberRouteOrder.Contains(routeName, StringComparer.OrdinalIgnoreCase))
                {
                    memberRouteOrder.Add(routeName);
                }
            }

            var namedRoutes = routeByName.Keys
                .Select(routeName => new
                {
                    Name = routeName,
                    Index = System.Text.RegularExpressions.Regex.IsMatch(
                        relationName,
                        $@"(?<![\p{{L}}\p{{N}}]){System.Text.RegularExpressions.Regex.Escape(routeName)}(?![\p{{L}}\p{{N}}])",
                        System.Text.RegularExpressions.RegexOptions.IgnoreCase)
                            ? relationName.IndexOf(routeName, StringComparison.OrdinalIgnoreCase)
                            : -1
                })
                .Where(route => route.Index >= 0)
                .OrderBy(route => route.Index)
                .Select(route => route.Name)
                .ToList();
            var orderedRoutes = namedRoutes.Count == 2
                ? namedRoutes
                : memberRouteOrder;
            if (orderedRoutes.Count != 2 ||
                orderedRoutes.Any(routeName => !routeByName.ContainsKey(routeName)) ||
                orderedRoutes.Any(routeName => !memberRouteOrder.Contains(routeName, StringComparer.OrdinalIgnoreCase)))
            {
                continue;
            }

            string[] pair = orderedRoutes.ToArray();
            var holeWayIds = new HashSet<long>(routeByName[pair[0]].HoleWayIds);
            holeWayIds.UnionWith(routeByName[pair[1]].HoleWayIds);
            relationVariants[relationId] = (relationId, pair, relationName, holeWayIds);
        }

        string[] availableRoutes = nineHoleRoutes.Select(route => route.Name).ToArray();
        var variants = new List<CourseVariant>();
        foreach (var route in nineHoleRoutes)
        {
            variants.Add(new CourseVariant(
                $"{courseName} - {route.Name} (9 Holes)",
                courseName,
                "9-hole",
                new[] { route.Name },
                new HashSet<long>(route.HoleWayIds),
                "",
                ""));
        }

        var usedTitles = new HashSet<string>(variants.Select(variant => variant.Title), StringComparer.OrdinalIgnoreCase);
        foreach (var relation in relationVariants.Values
                     .OrderBy(item => item.Name, StringComparer.OrdinalIgnoreCase)
                     .ThenBy(item => item.Id, StringComparer.Ordinal))
        {
            if (relation.HoleWayIds.Count == 0)
            {
                continue;
            }

            string pairTitle = string.IsNullOrWhiteSpace(relation.Name)
                ? string.Join(" + ", relation.SubCourses)
                : relation.Name;
            string title = $"{courseName} - {pairTitle} (18 Holes)";
            if (!usedTitles.Add(title))
            {
                title = $"{title} [OSM {relation.Id}]";
                usedTitles.Add(title);
            }
            variants.Add(new CourseVariant(
                title,
                courseName,
                "18-hole",
                relation.SubCourses,
                relation.HoleWayIds,
                relation.Name,
                relation.Id));
        }

        GD.Print($"{LogPrefix} Found {availableRoutes.Length} nine-hole sub-courses and generated {variants.Count - availableRoutes.Length} OSM-defined 18-hole combinations for '{courseName}'.");
        return variants;
    }

    public Godot.Collections.Array<Godot.Collections.Dictionary> GetCourseVariantPlan(string jsonString, string courseName)
    {
        var plan = new Godot.Collections.Array<Godot.Collections.Dictionary>();
        foreach (var variant in BuildCourseVariants(jsonString, courseName))
        {
            var subCourses = new Godot.Collections.Array<string>();
            foreach (string subCourse in variant.SubCourses)
            {
                subCourses.Add(subCourse);
            }

            plan.Add(new Godot.Collections.Dictionary
            {
                ["title"] = variant.Title,
                ["variant_type"] = variant.VariantType,
                ["sub_courses"] = subCourses,
                ["hole_count"] = variant.HoleWayIds.Count,
                ["osm_relation"] = variant.OsmRelationName,
                ["osm_relation_id"] = variant.OsmRelationId
            });
        }
        return plan;
    }

    private static List<string> GetCourseGeometryCandidateSlugs(string courseName)
    {
        var slugs = new List<string>();
        if (string.IsNullOrWhiteSpace(courseName))
            return slugs;

        // 1. Python-compatible slug: replace any sequence of non-alphanumeric chars with '_'
        var sbPy = new StringBuilder();
        foreach (char c in courseName.ToLowerInvariant())
        {
            if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
                sbPy.Append(c);
            else if (sbPy.Length > 0 && sbPy[sbPy.Length - 1] != '_')
                sbPy.Append('_');
        }
        string pySlug = sbPy.ToString().Trim('_');
        if (!string.IsNullOrEmpty(pySlug))
            slugs.Add(pySlug);

        // 2. Legacy C# slug (where punctuation was skipped rather than converted to '_')
        var sbLegacy = new StringBuilder();
        foreach (char c in courseName.ToLowerInvariant())
        {
            if (char.IsLetterOrDigit(c))
                sbLegacy.Append(c);
            else if (c == ' ' || c == '_' || c == '-' || c == '(' || c == ')' || c == '.')
            {
                if (sbLegacy.Length > 0 && sbLegacy[sbLegacy.Length - 1] != '_')
                    sbLegacy.Append('_');
            }
        }
        string legacySlug = sbLegacy.ToString().Trim('_');
        if (!string.IsNullOrEmpty(legacySlug) && !slugs.Contains(legacySlug))
            slugs.Add(legacySlug);

        // Common suffix variations (e.g. "Erin Hills Golf Course" -> "erin_hills")
        string baseSlug = pySlug;
        string[] suffixes = { "_golf_course", "_golf_club", "_country_club", "_golf_links", "_golf_and_country_club", "_resort", "_club", "_links", "_golf" };
        foreach (var suf in suffixes)
        {
            if (baseSlug.EndsWith(suf, StringComparison.OrdinalIgnoreCase))
            {
                string trimmed = baseSlug.Substring(0, baseSlug.Length - suf.Length).Trim('_');
                if (!string.IsNullOrEmpty(trimmed))
                {
                    string[] alts = { trimmed, $"{trimmed}_golf_course", $"{trimmed}_golf_club", $"{trimmed}_country_club" };
                    foreach (var alt in alts)
                    {
                        if (!slugs.Contains(alt))
                            slugs.Add(alt);
                    }
                }
                break;
            }
        }

        // Parentheses variations (e.g. "Torrey Pines Golf Course (North)" -> "torrey_pines_north_course")
        string lower = courseName.ToLowerInvariant();
        int openParen = lower.IndexOf('(');
        int closeParen = lower.IndexOf(')');
        if (openParen >= 0 && closeParen > openParen)
        {
            string parenSub = lower.Substring(openParen + 1, closeParen - openParen - 1).Trim();
            string noParen = (lower.Substring(0, openParen) + lower.Substring(closeParen + 1)).Trim();

            var sbNoParen = new StringBuilder();
            foreach (char c in noParen)
            {
                if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
                    sbNoParen.Append(c);
                else if (sbNoParen.Length > 0 && sbNoParen[sbNoParen.Length - 1] != '_')
                    sbNoParen.Append('_');
            }
            string noParenSlug = sbNoParen.ToString().Trim('_');

            var sbParen = new StringBuilder();
            foreach (char c in parenSub)
            {
                if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
                    sbParen.Append(c);
                else if (sbParen.Length > 0 && sbParen[sbParen.Length - 1] != '_')
                    sbParen.Append('_');
            }
            string parenSlug = sbParen.ToString().Trim('_');

            if (!string.IsNullOrEmpty(noParenSlug))
            {
                if (!slugs.Contains(noParenSlug)) slugs.Add(noParenSlug);
                if (!string.IsNullOrEmpty(parenSlug))
                {
                    string combined = $"{noParenSlug}_{parenSlug}";
                    if (!slugs.Contains(combined)) slugs.Add(combined);

                    string mainBase = noParenSlug;
                    foreach (var suf in suffixes)
                    {
                        if (mainBase.EndsWith(suf, StringComparison.OrdinalIgnoreCase))
                        {
                            mainBase = mainBase.Substring(0, mainBase.Length - suf.Length).Trim('_');
                            break;
                        }
                    }
                    string altCourse = $"{mainBase}_{parenSlug}_course";
                    if (!slugs.Contains(altCourse)) slugs.Add(altCourse);
                    string altGolf = $"{mainBase}_{parenSlug}_golf_course";
                    if (!slugs.Contains(altGolf)) slugs.Add(altGolf);
                }
            }
        }

        return slugs;
    }

    private static string GetCourseGeometrySlug(string courseName)
    {
        var slugs = GetCourseGeometryCandidateSlugs(courseName);
        return slugs.Count > 0 ? slugs[0] : "";
    }

    private static readonly Dictionary<string, List<(double Lat, double Lon)>> _cachedSlugCoordinates = new(StringComparer.OrdinalIgnoreCase);
    private static readonly object _slugCoordsLock = new();

    private static void EnsureCachedSlugCoordinatesLoaded()
    {
        lock (_slugCoordsLock)
        {
            if (_cachedSlugCoordinates.Count > 0) return;
            var catalog = LoadBundledCatalog();
            foreach (var course in catalog)
            {
                if (course.Lat == 0 && course.Lon == 0) continue;
                var slugs = GetCourseGeometryCandidateSlugs(course.Name);
                foreach (var slug in slugs)
                {
                    if (!_cachedSlugCoordinates.TryGetValue(slug, out var list))
                    {
                        list = new List<(double Lat, double Lon)>();
                        _cachedSlugCoordinates[slug] = list;
                    }
                    if (!list.Any(c => HaversineDistanceMeters(c.Lat, c.Lon, course.Lat, course.Lon) < 1000.0))
                    {
                        list.Add((course.Lat, course.Lon));
                    }
                }
            }
        }
    }

    private static bool TryGetCachedCourseCoordinates(string slug, out List<(double Lat, double Lon)> coordsList)
    {
        EnsureCachedSlugCoordinatesLoaded();
        lock (_slugCoordsLock)
        {
            return _cachedSlugCoordinates.TryGetValue(slug, out coordsList!);
        }
    }

    private static void RegisterCachedSlugCoordinate(string slug, double lat, double lon)
    {
        lock (_slugCoordsLock)
        {
            if (!_cachedSlugCoordinates.TryGetValue(slug, out var list))
            {
                list = new List<(double Lat, double Lon)>();
                _cachedSlugCoordinates[slug] = list;
            }
            if (!list.Any(c => HaversineDistanceMeters(c.Lat, c.Lon, lat, lon) < 1000.0))
            {
                list.Add((lat, lon));
            }
        }
    }

    private static bool TryExtractFirstNodeFromJson(string json, out double lat, out double lon)
    {
        lat = 0;
        lon = 0;
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("elements", out var elements) && elements.ValueKind == JsonValueKind.Array)
            {
                foreach (var el in elements.EnumerateArray())
                {
                    if (el.TryGetProperty("type", out var typeProp) && typeProp.GetString() == "node" &&
                        el.TryGetProperty("lat", out var latProp) && el.TryGetProperty("lon", out var lonProp))
                    {
                        lat = latProp.GetDouble();
                        lon = lonProp.GetDouble();
                        return true;
                    }
                }
            }
        }
        catch
        {
        }
        return false;
    }

    private static bool TryExtractFirstNodeFromPath(string path, out double lat, out double lon)
    {
        lat = 0;
        lon = 0;
        try
        {
            if (!Godot.FileAccess.FileExists(path)) return false;
            using var fa = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Read);
            if (fa == null) return false;
            if (path.EndsWith(".gz", StringComparison.OrdinalIgnoreCase))
            {
                byte[] gzBytes = fa.GetBuffer((long)fa.GetLength());
                using var ms = new MemoryStream(gzBytes);
                using var gzStream = new System.IO.Compression.GZipStream(ms, System.IO.Compression.CompressionMode.Decompress);
                using var reader = new StreamReader(gzStream, Encoding.UTF8);
                string json = reader.ReadToEnd();
                return TryExtractFirstNodeFromJson(json, out lat, out lon);
            }
            else
            {
                string json = fa.GetAsText();
                return TryExtractFirstNodeFromJson(json, out lat, out lon);
            }
        }
        catch
        {
        }
        return false;
    }

    private static (string SafeName, string CourseDir, string GlobalCourseDir, string Title) ResolveCoursePathAndTitle(
        string courseName, double lat, double lon, string location = "")
    {
        string baseName = string.Concat(courseName.Split(Path.GetInvalidFileNameChars())).Replace(" ", "_");
        string safeName = baseName;
        string courseDir = $"user://courses/{safeName}";
        string globalCourseDir = ProjectSettings.GlobalizePath(courseDir);
        string title = courseName;

        string existingJsonPath = Path.Combine(globalCourseDir, "course.json");
        if (File.Exists(existingJsonPath))
        {
            try
            {
                string existingJson = File.ReadAllText(existingJsonPath);
                using var doc = JsonDocument.Parse(existingJson);
                double existingLat = 0, existingLon = 0;
                if (doc.RootElement.TryGetProperty("Latitude", out var latProp))
                    existingLat = latProp.GetDouble();
                if (doc.RootElement.TryGetProperty("Longitude", out var lonProp))
                    existingLon = lonProp.GetDouble();

                // If coordinates differ significantly (> 25 km), disambiguate folder and title
                if ((existingLat != 0 || existingLon != 0) && (lat != 0 || lon != 0))
                {
                    double dist = HaversineDistanceMeters(lat, lon, existingLat, existingLon);
                    if (dist > 25000.0)
                    {
                        string locFirst = !string.IsNullOrWhiteSpace(location) ? location.Split(',')[0].Trim() : "";
                        string disambig = !string.IsNullOrEmpty(locFirst)
                            ? string.Concat(locFirst.Split(Path.GetInvalidFileNameChars())).Replace(" ", "_")
                            : $"{Math.Round(lat, 2)}_{Math.Round(lon, 2)}".Replace("-", "m").Replace(".", "_");
                        safeName = $"{baseName}_{disambig}";
                        courseDir = $"user://courses/{safeName}";
                        globalCourseDir = ProjectSettings.GlobalizePath(courseDir);
                        if (!string.IsNullOrEmpty(locFirst))
                        {
                            title = $"{courseName} ({locFirst})";
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                GD.PrintErr($"{LogPrefix} Error checking existing course.json for disambiguation: {ex.Message}");
            }
        }

        return (safeName, courseDir, globalCourseDir, title);
    }

    private static Task<string> TryLoadPrepackagedGeometryAsync(string courseName)
    {
        return TryLoadPrepackagedGeometryAsync(courseName, 0, 0);
    }

    private static async Task<string> TryLoadPrepackagedGeometryAsync(string courseName, double targetLat, double targetLon)
    {
        var slugs = GetCourseGeometryCandidateSlugs(courseName);
        if (slugs.Count == 0)
            return "";

        var candidatePaths = new List<string>();
        foreach (var slug in slugs)
        {
            if (targetLat != 0 || targetLon != 0)
            {
                if (TryGetCachedCourseCoordinates(slug, out var coordsList) &&
                    !coordsList.Any(c => HaversineDistanceMeters(targetLat, targetLon, c.Lat, c.Lon) <= 25000.0))
                {
                    GD.Print($"{LogPrefix} Candidate cached slug '{slug}' is located > 25 km from requested coordinates ({targetLat}, {targetLon}). Skipping.");
                    continue;
                }
            }

            candidatePaths.Add($"res://Courses/CachedGeometry/{slug}.json.gz");
            candidatePaths.Add($"res://Courses/CachedGeometry/{slug}.json");
            candidatePaths.Add($"user://cached_geometry/{slug}.json.gz");
            candidatePaths.Add($"user://cached_geometry/{slug}.json");
        }

        foreach (var path in candidatePaths)
        {
            if (!Godot.FileAccess.FileExists(path))
                continue;

            try
            {
                using var fa = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Read);
                if (fa == null) continue;

                string? decompressed = null;
                if (path.EndsWith(".gz", StringComparison.OrdinalIgnoreCase))
                {
                    byte[] gzBytes = fa.GetBuffer((long)fa.GetLength());
                    using var ms = new MemoryStream(gzBytes);
                    using var gzStream = new System.IO.Compression.GZipStream(ms, System.IO.Compression.CompressionMode.Decompress);
                    using var reader = new StreamReader(gzStream, Encoding.UTF8);
                    decompressed = await reader.ReadToEndAsync();
                }
                else
                {
                    decompressed = fa.GetAsText();
                }

                if (!string.IsNullOrWhiteSpace(decompressed))
                {
                    if (targetLat != 0 || targetLon != 0)
                    {
                        if (TryExtractFirstNodeFromJson(decompressed, out double nLat, out double nLon))
                        {
                            double dist = HaversineDistanceMeters(targetLat, targetLon, nLat, nLon);
                            if (dist > 25000.0)
                            {
                                GD.Print($"{LogPrefix} Cached geometry at {path} ({nLat}, {nLon}) is {dist / 1000.0:F1} km away from target ({targetLat}, {targetLon}). Skipping.");
                                continue;
                            }
                        }
                    }

                    GD.Print($"{LogPrefix} Successfully loaded pre-packaged geometry for '{courseName}' from {path} (0 API calls)!");
                    return decompressed;
                }
            }
            catch (Exception ex)
            {
                GD.PrintErr($"{LogPrefix} Error reading pre-packaged geometry at {path}: {ex.Message}");
            }
        }

        return "";
    }

    public string LoadPrepackagedGeometry(string courseName)
    {
        return TryLoadPrepackagedGeometryAsync(courseName).GetAwaiter().GetResult();
    }

    private static void TrySaveUserCachedGeometry(string courseName, string json)
    {
        try
        {
            string slug = GetCourseGeometrySlug(courseName);
            if (string.IsNullOrWhiteSpace(slug)) return;

            string userCacheDir = "user://cached_geometry";
            string globalUserCacheDir = ProjectSettings.GlobalizePath(userCacheDir);
            if (!Directory.Exists(globalUserCacheDir))
            {
                Directory.CreateDirectory(globalUserCacheDir);
            }

            string gzPath = $"{userCacheDir}/{slug}.json.gz";
            byte[] utf8Bytes = Encoding.UTF8.GetBytes(json);
            using var ms = new MemoryStream();
            using (var gz = new System.IO.Compression.GZipStream(ms, System.IO.Compression.CompressionLevel.Optimal, true))
            {
                gz.Write(utf8Bytes, 0, utf8Bytes.Length);
            }
            byte[] compressed = ms.ToArray();

            using var fa = Godot.FileAccess.Open(gzPath, Godot.FileAccess.ModeFlags.Write);
            if (fa != null)
            {
                fa.StoreBuffer(compressed);
                GD.Print($"{LogPrefix} Saved geometry to user cache at {gzPath} ({utf8Bytes.Length / 1024} KB -> {compressed.Length / 1024} KB).");
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Failed to save geometry to user cache: {ex.Message}");
        }
    }

    private async Task<string> DownloadOsmDataAsync(double lat, double lon, string courseName, bool isCached = false)
    {
        // 1. Check if pre-packaged or locally cached geometry exists near requested coordinates
        string prepackaged = await TryLoadPrepackagedGeometryAsync(courseName, lat, lon);
        if (!string.IsNullOrWhiteSpace(prepackaged))
        {
            ReportProgress($"Loaded pre-packaged map data for '{courseName}' (0 API calls)...");
            return prepackaged;
        }

        // 2. Only enforce cache restriction if coordinates are missing (cannot query Overpass without coordinates)
        if (lat == 0 && lon == 0)
        {
            GD.PrintErr($"{LogPrefix} Cached geometry for '{courseName}' was requested but could not be loaded from local files and no coordinates were provided. OpenStreetMap was not queried.");
            _generationMessage = $"Error: Cached map geometry for '{courseName}' could not be loaded from local files. OpenStreetMap was not queried.";
            return "";
        }

        ReportProgress($"Connecting to OpenStreetMap for '{courseName}'...");
        GD.Print($"{LogPrefix} No pre-packaged geometry found for '{courseName}'. Downloading from Overpass around {lat}, {lon}...");
        // Query includes natural=tree, natural=tree_row, and golf=tree to accurately place all OSM course trees
        // Use FormattableString.Invariant to ensure lat/lon always use '.' as decimal separator regardless of system locale
        string latStr = lat.ToString(CultureInfo.InvariantCulture);
        string lonStr = lon.ToString(CultureInfo.InvariantCulture);
        string query = $@"
        [out:json][timeout:60];
        (
          nwr(around:1800, {latStr}, {lonStr})[""leisure""=""golf_course""];
          nwr(around:1800, {latStr}, {lonStr})[""golf""];
          nwr(around:1800, {latStr}, {lonStr})[""natural""=""water""];
          nwr(around:1800, {latStr}, {lonStr})[""natural""=""wood""];
          nwr(around:1800, {latStr}, {lonStr})[""natural""=""tree""];
          nwr(around:1800, {latStr}, {lonStr})[""natural""=""tree_row""];
          nwr(around:1800, {latStr}, {lonStr})[""golf""=""tree""];
          nwr(around:1800, {latStr}, {lonStr})[""landuse""=""forest""];
        );
        out body;
        >;
        out skel qt;
        ";

        int maxAttempts = OverpassEndpoints.Length;
        for (int attempt = 1; attempt <= maxAttempts; attempt++)
        {
            string endpoint = OverpassEndpoints[(attempt - 1) % OverpassEndpoints.Length];
            GD.Print($"{LogPrefix} Overpass query attempt {attempt}/{maxAttempts} using endpoint: {endpoint}");

            try
            {
                // Timeout must exceed Overpass [timeout:60] to avoid cancelling before server responds
                using var cts = new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(65));
                var content = new FormUrlEncodedContent(new[] { new KeyValuePair<string, string>("data", query) });
                var response = await HttpClient.PostAsync(endpoint, content, cts.Token);

                if (response.IsSuccessStatusCode)
                {
                    string result = await response.Content.ReadAsStringAsync();
                    if (!string.IsNullOrWhiteSpace(result))
                    {
                        TrySaveUserCachedGeometry(courseName, result);
                        return result;
                    }
                }

                GD.PrintErr($"{LogPrefix} Attempt {attempt} failed with HTTP status {response.StatusCode} from {endpoint}");
            }
            catch (Exception ex)
            {
                GD.PrintErr($"{LogPrefix} Attempt {attempt} exception querying {endpoint}: {ex.Message}{(ex.InnerException != null ? $" (Inner: {ex.InnerException.Message})" : "")}");
            }

            if (attempt < maxAttempts)
            {
                _generationMessage = $"Overpass server busy or timed out, trying mirror (attempt {attempt + 1}/{maxAttempts})...";
                ReportProgress(_generationMessage);
                await Task.Delay(500);
            }
        }

        _generationMessage = "Error: Overpass API request timed out after multiple retries. Please retry the download, and if it continues to fail, please log a bug.";
        return "";
    }

    private async Task<bool> GenerateCourseVariantCoreAsync(
        string jsonString,
        string courseName,
        double lat,
        double lon,
        byte[]? satImageBytes,
        CourseVariant? variant,
        List<string>? availableVariants,
        string location = "")
    {
        _generationMessage = "";
        ReportProgress("Parsing course layout and golf features...");
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

        var (safeName, courseDir, globalCourseDir, courseTitle) = ResolveCoursePathAndTitle(courseName, lat, lon, location);
        string tscnPath = $"{courseDir}/course.tscn";
        string jsonPath = $"{courseDir}/course.json";
        string globalJsonPath = ProjectSettings.GlobalizePath(jsonPath);
        if (!string.IsNullOrEmpty(globalCourseDir) && !Directory.Exists(globalCourseDir))
        {
            Directory.CreateDirectory(globalCourseDir);
        }
        bool isMobilePlatform = OS.GetName() == "Android" || OS.GetName() == "iOS";
        bool isComputerPlatform = OS.GetName() == "Windows" || OS.GetName() == "macOS" || OS.GetName() == "Linux";

        if (_downloadedCoursePhotoBytes != null && _downloadedCoursePhotoBytes.Length > 0)
        {
            try
            {
                File.WriteAllBytes(Path.Combine(globalCourseDir, "course_photo.jpg"), _downloadedCoursePhotoBytes);
            }
            catch (Exception ex)
            {
                GD.PrintErr($"{LogPrefix} Failed to save course_photo.jpg: {ex.Message}");
            }
        }

        Image? satImage = null;
        if (satImageBytes != null && satImageBytes.Length > 0)
        {
            try
            {
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

            // Assemble multipolygon surface relations (fairway, green, bunker, water, wood, forest, tee)
            // into unified synthetic OsmWay objects. Outer member ways are stitched together,
            // while inner member ways (greens, bunkers, cutouts) are preserved.
            var waysToRemove = new HashSet<long>();
            var syntheticWays = new List<OsmWay>();
            long nextSyntheticWayId = -100000;

            foreach (var rel in relations)
            {
                if (rel.Tags.TryGetValue("type", out var relType) && relType == "multipolygon")
                {
                    bool isSurface = rel.Tags.ContainsKey("golf") ||
                                     (rel.Tags.TryGetValue("natural", out var n) && (n == "water" || n == "wood")) ||
                                     (rel.Tags.TryGetValue("landuse", out var lu) && lu == "forest");

                    if (isSurface)
                    {
                        var chains = AssembleRelationNodeChains(rel, ways, nodes);
                        foreach (var chain in chains)
                        {
                            if (chain.Count >= 3)
                            {
                                var synTags = new Dictionary<string, string>(rel.Tags);
                                syntheticWays.Add(new OsmWay(nextSyntheticWayId--, chain, synTags));
                            }
                        }

                        // Mark outer member ways of this relation for removal so they aren't processed as fragmented pieces
                        foreach (var member in rel.Members)
                        {
                            if (member.Type == "way" && (member.Role == "outer" || string.IsNullOrEmpty(member.Role)))
                            {
                                waysToRemove.Add(member.Ref);
                            }
                        }
                    }
                }
            }

            if (waysToRemove.Count > 0)
            {
                ways.RemoveAll(w => waysToRemove.Contains(w.Id));
            }
            if (syntheticWays.Count > 0)
            {
                ways.AddRange(syntheticWays);
            }

            // Copy tags from relations to member ways and nodes
            foreach (var rel in relations)
            {
                // Multipolygon surface relations have already been assembled into synthetic ways above
                if (rel.Tags.TryGetValue("type", out var rType) && rType == "multipolygon")
                    continue;

                var relTagsToCopy = new Dictionary<string, string>();
                foreach (var tag in rel.Tags)
                {
                    if (tag.Key == "golf" || tag.Key == "natural" || tag.Key == "landuse" || tag.Key == "leisure" || tag.Key == "ref" || tag.Key == "par" || tag.Key == "handicap" || tag.Key == "name" || tag.Key.StartsWith("dist:", StringComparison.OrdinalIgnoreCase))
                    {
                        relTagsToCopy[tag.Key] = tag.Value;
                    }
                }
                
                if (relTagsToCopy.Count > 0)
                {
                    foreach (var member in rel.Members)
                    {
                        if (member.Role == "inner")
                            continue;

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
                                    if (kvp.Key == "name" && targetWay.Tags.GetValueOrDefault("golf") == "hole")
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

            if (variant != null)
            {
                ways.RemoveAll(way =>
                    way.Tags.TryGetValue("golf", out var golfType) &&
                    golfType == "hole" &&
                    !variant.HoleWayIds.Contains(way.Id));
            }

            // Identify target and neighboring golf course boundaries
            string preferredName = variant != null && !string.IsNullOrWhiteSpace(variant.SourceCourse)
                ? variant.SourceCourse
                : courseName;
            var boundaryInfo = IdentifyCourseBoundaries(ways, relations, nodes, lat, lon, preferredName, refLat, refLon, metersPerLat, metersPerLon);
            string targetCourseName = boundaryInfo.TargetCourseName;
            var coursePolygons = boundaryInfo.CoursePolygons;
            var otherCoursePolygons = boundaryInfo.OtherCoursePolygons;
            var otherCourseNames = boundaryInfo.OtherCourseNames;

            if (coursePolygons.Count > 0)
            {
                GD.Print($"{LogPrefix} Identified main golf course boundary: '{targetCourseName}' with {coursePolygons.Count} polygon parts ({otherCoursePolygons.Count} other course polygon parts, {otherCourseNames.Count} neighboring courses).");
            }
            else
            {
                GD.Print($"{LogPrefix} Warning: No leisure=golf_course boundary found near search coordinates. Allowing all elements.");
            }

            var exclusionPolygons = new List<ExclusionPolygon>();
            var holeInfo = new Dictionary<string, HoleConfig>();
            var tees = new List<TeeConfig>();
            var unreferencedTees = new List<(List<string> Colors, Vector2 Location, Vector2[]? Polygon)>();
            var teeCandidatesByHole = new Dictionary<(string HoleKey, string Color), List<TeeConfig>>();
            var lineOfPlayPaths = new List<List<Vector2>>();
            var cartPaths = new List<List<Vector2>>();

            Func<Vector2, bool> isPointInMainCourse = (pt) => IsPointInMainCourse(pt, boundaryInfo, lineOfPlayPaths, exclusionPolygons);

            // Build individual tree nodes list from nodeTags and ways
            var treeNodeIds = new List<long>();
            var additionalTreePositions = new List<Vector2>();
            foreach (var kvp in nodeTags)
            {
                bool isTree = (kvp.Value.TryGetValue("natural", out var nat) && nat == "tree")
                    || (kvp.Value.TryGetValue("golf", out var g) && g == "tree")
                    || (kvp.Value.TryGetValue("tree", out var t) && (t == "yes" || t == "true"));

                if (isTree)
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

            // Pre-process hole ways to assign consecutive unique hole keys ("Hole 01", "Hole 02", ...)
            // and support multi-course / sub-course layouts (e.g. golf:course:name="Red", "White", "Blue").
            // When course boundary polygons are identified, strictly filter hole ways so neighboring courses' holes are excluded.
            Func<OsmWay, bool> isHoleBelongingToCourse = (hw) => IsHoleBelongingToCourse(hw, nodes, refLat, refLon, metersPerLat, metersPerLon, boundaryInfo);

            var holeWays = ways
                .Where(w => w.Tags.TryGetValue("golf", out var g) && g == "hole" && w.NodeIds.Count(nodes.ContainsKey) >= 2)
                .Where(isHoleBelongingToCourse)
                .ToList();

            var holeWayMapping = new Dictionary<long, (string HoleKey, string DisplayName, string SubCourse, string OriginalRef)>();
            if (holeWays.Count > 0)
            {
                bool hasSubCourses = holeWays.Any(w => !string.IsNullOrEmpty(ExtractSubCourseName(w.Tags)));
                if (hasSubCourses)
                {
                    var groupedHoles = holeWays
                        .GroupBy(w => ExtractSubCourseName(w.Tags))
                        .ToDictionary(g => g.Key, g => g);
                    var groupOrder = variant != null
                        ? variant.SubCourses
                        : groupedHoles.Keys.OrderBy(name => name, StringComparer.OrdinalIgnoreCase).ToArray();
                    var groups = groupOrder
                        .Where(groupedHoles.ContainsKey)
                        .Select(name => groupedHoles[name])
                        .ToList();

                    int assignedIdx = 1;
                    foreach (var grp in groups)
                    {
                        string subName = grp.Key;
                        var sortedHoles = grp
                            .OrderBy(w => int.TryParse(w.Tags.GetValueOrDefault("ref", "0"), out int r) ? r : 999)
                            .ThenBy(w => w.Tags.GetValueOrDefault("name", ""))
                            .ToList();

                        foreach (var hw in sortedHoles)
                        {
                            string origRef = hw.Tags.GetValueOrDefault("ref", assignedIdx.ToString());
                            string holeKey = GetHoleKey(assignedIdx.ToString());
                            string displayName = hw.Tags.GetValueOrDefault("name", "");
                            if (string.IsNullOrWhiteSpace(displayName) || displayName.Equals($"Hole {origRef}", StringComparison.OrdinalIgnoreCase))
                            {
                                displayName = !string.IsNullOrWhiteSpace(subName) ? $"{subName} {origRef}" : $"Hole {assignedIdx}";
                            }
                            holeWayMapping[hw.Id] = (holeKey, displayName, subName, origRef);
                            assignedIdx++;
                        }
                    }
                }
                else
                {
                    var refsCount = holeWays.GroupBy(w => w.Tags.GetValueOrDefault("ref", "")).ToDictionary(g => g.Key, g => g.Count());
                    bool hasDuplicateRefs = refsCount.Values.Any(cnt => cnt > 1);

                    if (hasDuplicateRefs)
                    {
                        int assignedIdx = 1;
                        var sortedHoles = holeWays
                            .OrderBy(w => int.TryParse(w.Tags.GetValueOrDefault("ref", "0"), out int r) ? r : 999)
                            .ThenBy(w => w.Tags.GetValueOrDefault("name", ""))
                            .ToList();

                        foreach (var hw in sortedHoles)
                        {
                            string origRef = hw.Tags.GetValueOrDefault("ref", assignedIdx.ToString());
                            string holeKey = GetHoleKey(assignedIdx.ToString());
                            string displayName = hw.Tags.GetValueOrDefault("name", $"Hole {assignedIdx}");
                            holeWayMapping[hw.Id] = (holeKey, displayName, "", origRef);
                            assignedIdx++;
                        }
                    }
                    else
                    {
                        foreach (var hw in holeWays)
                        {
                            string origRef = hw.Tags.GetValueOrDefault("ref", "1");
                            string holeKey = GetHoleKey(origRef);
                            string displayName = hw.Tags.GetValueOrDefault("name", $"Hole {origRef}");
                            holeWayMapping[hw.Id] = (holeKey, displayName, "", origRef);
                        }
                    }
                }
            }

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

                way.Tags.TryGetValue("golf", out string? golfType);
                bool isCartPath = (golfType != null
                    && (golfType.Equals("cartpath", StringComparison.OrdinalIgnoreCase)
                        || golfType.Equals("cart_path", StringComparison.OrdinalIgnoreCase)))
                    || (way.Tags.TryGetValue("highway", out var hWayTag)
                        && (hWayTag.Equals("path", StringComparison.OrdinalIgnoreCase)
                            || hWayTag.Equals("footway", StringComparison.OrdinalIgnoreCase)));

                // Check if the way belongs to the main course
                var wayCenter = new Vector2(points.Average(p => p.X), points.Average(p => p.Y));
                // If this is a golf=hole way, strictly check whether it was accepted into holeWays
                if (golfType == "hole")
                {
                    if (!holeWays.Any(hw => hw.Id == way.Id))
                        continue;
                }
                else if (isCartPath)
                {
                    if (otherCoursePolygons.Count > 0 &&
                        otherCoursePolygons.Any(p => PointInPolygon(wayCenter, p)) &&
                        !coursePolygons.Any(p => PointInPolygon(wayCenter, p)))
                    {
                        continue;
                    }
                }
                else if (!isPointInMainCourse(wayCenter))
                {
                    // Do not skip the main golf course boundary ways/relations themselves
                    bool isMainBoundary = way.Tags.TryGetValue("leisure", out var l) && l == "golf_course";
                    if (!isMainBoundary)
                        continue;
                }

                // Extract tree rows or area-mapped trees
                if (way.Tags.TryGetValue("natural", out var wayNat))
                {
                    if (wayNat == "tree_row")
                    {
                        foreach (var nId in way.NodeIds)
                        {
                            if (nodes.TryGetValue(nId, out var coord))
                            {
                                float tx = (float)((coord.Lon - refLon) * metersPerLon);
                                float tz = -(float)((coord.Lat - refLat) * metersPerLat);
                                if (isPointInMainCourse(new Vector2(tx, tz)) && !treeNodeIds.Contains(nId))
                                {
                                    treeNodeIds.Add(nId);
                                }
                            }
                        }
                    }
                    else if (wayNat == "tree")
                    {
                        var wayPoints = way.NodeIds
                            .Where(nodes.ContainsKey)
                            .Select(id => nodes[id])
                            .Select(coord => new Vector2(
                                (float)((coord.Lon - refLon) * metersPerLon),
                                -(float)((coord.Lat - refLat) * metersPerLat)
                            ))
                            .ToList();
                        if (wayPoints.Count > 0)
                        {
                            var center = new Vector2(wayPoints.Average(p => p.X), wayPoints.Average(p => p.Y));
                            if (isPointInMainCourse(center))
                            {
                                additionalTreePositions.Add(center);
                            }
                        }
                    }
                }

                // Determine golf type early so line features (hole, tee) are handled before polygon guard
                if (isCartPath)
                {
                    cartPaths.Add(points);
                    continue;
                }
                // Handle golf=hole as a LINE of play (tee → green), not a polygon
                if (golfType == "hole")
                {
                    string holeKey = GetHoleKey(way.Tags.GetValueOrDefault("ref", "1"));
                    string hName = way.Tags.GetValueOrDefault("name", "");
                    string subCourse = "";
                    string origRef = way.Tags.GetValueOrDefault("ref", "1");

                    if (holeWayMapping.TryGetValue(way.Id, out var mapping))
                    {
                        holeKey = mapping.HoleKey;
                        hName = mapping.DisplayName;
                        subCourse = mapping.SubCourse;
                        origRef = mapping.OriginalRef;
                    }
                    else
                    {
                        if (string.IsNullOrWhiteSpace(hName)) hName = $"Hole {origRef}";
                    }

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

                    if (holeInfo.TryGetValue(holeKey, out var existingHole))
                    {
                        // Avoid junior/pitch-and-putt mini holes (< 100 yds) replacing regulation holes
                        if (existingHole.Distance >= 100f && distanceYards < 100f)
                        {
                            GD.Print($"{LogPrefix} Ignoring junior/short hole {hName} ({distanceYards:F0} yds) in favor of regulation hole ({existingHole.Distance:F0} yds)");
                            continue;
                        }
                        if (existingHole.Distance < 100f && distanceYards >= 100f)
                        {
                            GD.Print($"{LogPrefix} Replacing short/junior hole {hName} ({existingHole.Distance:F0} yds) with regulation hole ({distanceYards:F0} yds)");
                        }
                        else if (distanceYards < existingHole.Distance)
                        {
                            GD.Print($"{LogPrefix} Keeping longer hole {hName} ({existingHole.Distance:F0} yds) over shorter one ({distanceYards:F0} yds)");
                            continue;
                        }
                    }

                    GD.Print($"{LogPrefix} Parsed hole {holeKey} ({hName}): par {par}, {distanceYards:F0} yards, tee ({teePos.X:F1}, {teePos.Y:F1}) → pin ({pinPos.X:F1}, {pinPos.Y:F1})");

                    holeInfo[holeKey] = new HoleConfig
                    {
                        Par = par,
                        Handicap = handicap,
                        Name = hName,
                        Distance = distanceYards,
                        HoleLocation = new float[] { pinPos.X, pinPos.Y },
                        TeeBoxes = existingHole?.TeeBoxes ?? new Dictionary<string, float[]>(),
                        HolePath = pathList,
                        TeeDistancesMeters = ParseTeeDistances(way.Tags),
                        SubCourse = subCourse,
                        OriginalRef = origRef
                    };
                    lineOfPlayPaths.Add(new List<Vector2>(points));
                    continue;
                }

                // Handle golf=tee (can be polygon or small way)
                if (golfType == "tee")
                {
                    var parsedColors = ParseTeeColors(way.Tags);
                    var center = new Vector2(points.Average(pt => pt.X), points.Average(pt => pt.Y));
                    string teeSubCourse = ExtractSubCourseName(way.Tags);
                    Vector2[]? teePolygon = points.Count >= 3
                        ? (points.First() == points.Last() ? points.Take(points.Count - 1).ToArray() : points.ToArray())
                        : null;

                    string? refHole = null;
                    if (way.Tags.TryGetValue("ref", out refHole) && !string.IsNullOrWhiteSpace(refHole))
                    {
                        var holeRefs = ParseHoleRefs(refHole);
                        foreach (var hNum in holeRefs)
                        {
                            foreach (var col in parsedColors)
                            {
                                tees.Add(new TeeConfig
                                {
                                    HoleNum = hNum,
                                    Color = col,
                                    Location = new float[] { center.X, center.Y },
                                    SubCourse = teeSubCourse,
                                    Polygon = teePolygon
                                });
                            }
                        }
                    }
                    else
                    {
                        unreferencedTees.Add((parsedColors, center, teePolygon));
                    }

                    // Also render the tee box visually if it has polygon geometry
                    if (points.Count >= 3)
                    {
                        if (!string.IsNullOrWhiteSpace(refHole))
                        {
                            foreach (var hNum in ParseHoleRefs(refHole))
                            {
                                holesWithTeePolygons.Add(GetHoleKey(hNum));
                            }
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
                        "bunker" => 5,
                        _ => 2
                    };

                    var staticBody = new StaticBody3D { Name = $"{golfType}_Static_{way.Id}" };
                    staticBody.SetMeta("surface_type", surfaceTypeValue);
                    if (golfType == "bunker")
                    {
                        staticBody.SetMeta("is_sand", true);
                        staticBody.SetMeta("boundary_polygon", uniquePoints);
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

            // Gather node-based tees from nodeTags list
            foreach (var kvp in nodeTags)
            {
                if (kvp.Value.TryGetValue("golf", out var golfVal) && golfVal == "tee")
                {
                    if (nodes.TryGetValue(kvp.Key, out var coord))
                    {
                        float tx = (float)((coord.Lon - refLon) * metersPerLon);
                        float tz = -(float)((coord.Lat - refLat) * metersPerLat);
                        var nodePos = new Vector2(tx, tz);
                        if (!isPointInMainCourse(nodePos))
                            continue;

                        var parsedColors = ParseTeeColors(kvp.Value);
                        string teeSubCourse = ExtractSubCourseName(kvp.Value);

                        if (kvp.Value.TryGetValue("ref", out string? refHole) && !string.IsNullOrWhiteSpace(refHole))
                        {
                            var holeRefs = ParseHoleRefs(refHole);
                            foreach (var hNum in holeRefs)
                            {
                                foreach (var col in parsedColors)
                                {
                                    tees.Add(new TeeConfig
                                    {
                                        HoleNum = hNum,
                                        Color = col,
                                        Location = new float[] { tx, tz },
                                        SubCourse = teeSubCourse
                                    });
                                }
                            }
                        }
                        else
                        {
                            unreferencedTees.Add((parsedColors, nodePos, null));
                        }
                    }
                }
            }

            // Map referenced tees to their respective holes first
            foreach (var tee in tees)
            {
                string? matchedHoleKey = null;
                float minTeeDist = float.MaxValue;

                foreach (var kp in holeInfo)
                {
                    var hole = kp.Value;
                    bool refMatch = hole.OriginalRef == tee.HoleNum || kp.Key == GetHoleKey(tee.HoleNum);
                    if (!refMatch) continue;

                    if (!string.IsNullOrEmpty(tee.SubCourse) && !string.IsNullOrEmpty(hole.SubCourse))
                    {
                        if (!string.Equals(tee.SubCourse, hole.SubCourse, StringComparison.OrdinalIgnoreCase))
                            continue;
                    }

                    if (hole.HolePath != null && hole.HolePath.Count > 0)
                    {
                        var hStart = new Vector2(hole.HolePath[0][0], hole.HolePath[0][1]);
                        float dist = new Vector2(tee.Location[0], tee.Location[1]).DistanceTo(hStart);
                        if (dist < minTeeDist)
                        {
                            minTeeDist = dist;
                            matchedHoleKey = kp.Key;
                        }
                    }
                    else if (matchedHoleKey == null)
                    {
                        matchedHoleKey = kp.Key;
                    }
                }

                if (matchedHoleKey != null && holeInfo.TryGetValue(matchedHoleKey, out var matchedHole))
                {
                    AddTeeCandidate(teeCandidatesByHole, matchedHoleKey, tee);
                }
            }

            // Match unreferenced tee boxes to the closest hole
            foreach (var unref in unreferencedTees)
            {
                string? bestHoleKey = null;
                float minDistance = float.MaxValue;

                foreach (var kp in holeInfo)
                {
                    var hole = kp.Value;
                    if (hole.HolePath == null || hole.HolePath.Count == 0) continue;

                    Vector2 holeStart = new Vector2(hole.HolePath[0][0], hole.HolePath[0][1]);
                    float dist = unref.Location.DistanceTo(holeStart);

                    // Referenced tees are staged until distance-based placement is resolved,
                    // so include those candidates when associating unreferenced tee markers.
                    foreach (var teeGroup in teeCandidatesByHole)
                    {
                        if (!string.Equals(teeGroup.Key.HoleKey, kp.Key, StringComparison.OrdinalIgnoreCase))
                            continue;

                        foreach (var existingTee in teeGroup.Value)
                        {
                            if (existingTee.Location == null || existingTee.Location.Length < 2)
                                continue;
                            float teeDistance = GetDistanceToTeeCandidate(
                                unref.Location,
                                new Vector2(existingTee.Location[0], existingTee.Location[1]),
                                existingTee.Polygon);
                            if (teeDistance < dist)
                                dist = teeDistance;
                        }
                    }

                    if (dist < minDistance)
                    {
                        minDistance = dist;
                        bestHoleKey = kp.Key;
                    }
                }

                // Associate if within 150 meters of the hole start / tee area
                if (bestHoleKey != null && minDistance <= 150f && holeInfo.TryGetValue(bestHoleKey, out var matchedHole))
                {
                    foreach (var col in unref.Colors)
                    {
                        AddTeeCandidate(teeCandidatesByHole, bestHoleKey, new TeeConfig
                        {
                            Color = col,
                            Location = new[] { unref.Location.X, unref.Location.Y },
                            Polygon = unref.Polygon
                        });
                    }
                    GD.Print($"{LogPrefix} Matched unreferenced tee ({string.Join("/", unref.Colors)}) at ({unref.Location.X:F1}, {unref.Location.Y:F1}) to {bestHoleKey} (dist: {minDistance:F1}m)");
                }
            }

            foreach (var candidateGroup in teeCandidatesByHole)
            {
                if (!holeInfo.TryGetValue(candidateGroup.Key.HoleKey, out var hole))
                    continue;

                var candidates = candidateGroup.Value;
                var selectedPosition = candidates[^1].Location;
                if (hole.HolePath.Count > 0 &&
                    hole.TeeDistancesMeters.TryGetValue(candidateGroup.Key.Color, out float teeDistanceMeters))
                {
                    Vector2 distanceTarget = GetPointAtDistanceFromHoleEnd(hole.HolePath, teeDistanceMeters);
                    float nearestDistance = float.MaxValue;
                    foreach (var candidate in candidates)
                    {
                        Vector2 candidatePosition = new(candidate.Location[0], candidate.Location[1]);
                        if (candidate.Polygon != null && candidate.Polygon.Length >= 3)
                        {
                            candidatePosition = GetClosestPointInPolygon(distanceTarget, candidate.Polygon);
                        }

                        float distance = candidatePosition.DistanceTo(distanceTarget);
                        if (distance < nearestDistance)
                        {
                            nearestDistance = distance;
                            selectedPosition = new[] { candidatePosition.X, candidatePosition.Y };
                        }
                    }
                }

                hole.TeeBoxes[candidateGroup.Key.Color] = selectedPosition;
            }

            foreach (var hole in holeInfo.Values)
            {
                ApplyLegacyTeeFallbacks(hole);
            }

            // Ensure every hole has tee data
            foreach (var kp in holeInfo)
            {
                var hole = kp.Value;
                if (hole.TeeBoxes.Count == 0)
                {
                    // No explicit tees at all: use the first node of the hole line
                    float defX = (hole.HolePath != null && hole.HolePath.Count > 0) ? hole.HolePath[0][0] : 0.0f;
                    float defZ = (hole.HolePath != null && hole.HolePath.Count > 0) ? hole.HolePath[0][1] : 0.0f;
                    hole.TeeBoxes["Blue"] = new float[] { defX, defZ };
                    hole.TeeBoxes["White"] = new float[] { defX, defZ };
                    hole.TeeBoxes["Red"] = new float[] { defX, defZ };
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

            // Note: forestPolygons are excluded from course bounds calculation so bounds remain
            // strictly anchored to the playable course features and stay aligned with satellite imagery.

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
            var bunkerPolys = exclusionPolygons.Where(e => e.GolfType == "bunker").ToList();
            var greenPolys = exclusionPolygons.Where(e => e.GolfType == "green").ToList();

            Func<Vector2, float, bool> isTooCloseToBunker = (pt, minDist) =>
            {
                for (int i = 0; i < bunkerPolys.Count; i++)
                {
                    var bk = bunkerPolys[i];
                    if (pt.X >= bk.MinX - minDist && pt.X <= bk.MaxX + minDist &&
                        pt.Y >= bk.MinY - minDist && pt.Y <= bk.MaxY + minDist)
                    {
                        if (PointInPolygon(pt, bk.Polygon))
                        {
                            return true;
                        }
                        if (DistanceToPolygon(pt, bk.Polygon) < minDist)
                        {
                            return true;
                        }
                    }
                }
                return false;
            };

            Func<Vector2, float, bool> isTooCloseToGreen = (pt, minDist) =>
            {
                for (int i = 0; i < greenPolys.Count; i++)
                {
                    var gr = greenPolys[i];
                    if (pt.X >= gr.MinX - minDist && pt.X <= gr.MaxX + minDist &&
                        pt.Y >= gr.MinY - minDist && pt.Y <= gr.MaxY + minDist)
                    {
                        if (PointInPolygon(pt, gr.Polygon))
                        {
                            return true;
                        }
                        if (DistanceToPolygon(pt, gr.Polygon) < minDist)
                        {
                            return true;
                        }
                    }
                }
                return false;
            };

            Func<Vector2, float, bool> isTooCloseToCartPath = (pt, minDist) =>
            {
                if (cartPaths == null || cartPaths.Count == 0) return false;
                return IsTreeTooCloseToCartPath(pt, cartPaths, minDist);
            };
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

            // 1. Gather tree positions directly from OSM course data.
            // Any tree listed in the OSM course data is placed right where it belongs (even if close to the fairway).
            var placedTreePositions = new List<Vector2>();
            foreach (var tId in treeNodeIds)
            {
                if (nodes.TryGetValue(tId, out var coord))
                {
                    float tx = (float)((coord.Lon - refLon) * metersPerLon);
                    float tz = -(float)((coord.Lat - refLat) * metersPerLat);
                    var pt = new Vector2(tx, tz);

                    // Trees must never generate inside or too close to sand traps (< 5.0m), greens (< 8.0m), or cart paths (< 2.2m)
                    if (isTooCloseToCartPath(pt, 2.2f)) continue;
                    if (isTooCloseToBunker(pt, 5.0f)) continue;
                    if (isTooCloseToGreen(pt, 8.0f)) continue;

                    // Place tree directly where OSM specified (avoiding duplicates within 0.5m)
                    bool isDuplicate = false;
                    for (int i = 0; i < placedTreePositions.Count; i++)
                    {
                        if (placedTreePositions[i].DistanceSquaredTo(pt) < 0.25f)
                        {
                            isDuplicate = true;
                            break;
                        }
                    }
                    if (!isDuplicate)
                    {
                        placedTreePositions.Add(pt);
                    }
                }
            }

            foreach (var pt in additionalTreePositions)
            {
                if (isTooCloseToCartPath(pt, 2.2f)) continue;
                if (isTooCloseToBunker(pt, 5.0f)) continue;
                if (isTooCloseToGreen(pt, 8.0f)) continue;

                bool isDuplicate = false;
                for (int i = 0; i < placedTreePositions.Count; i++)
                {
                    if (placedTreePositions[i].DistanceSquaredTo(pt) < 0.25f)
                    {
                        isDuplicate = true;
                        break;
                    }
                }
                if (!isDuplicate)
                {
                    placedTreePositions.Add(pt);
                }
            }

            GD.Print($"{LogPrefix} Placed {placedTreePositions.Count} authentic trees directly from OSM course data.");

            // Distance calculation to closest fairway polygon (or hole corridor if no fairways parsed)
            Func<Vector2, float> getDistToFairway = (pt) =>
            {
                float minFairwayD = float.MaxValue;
                if (fairwayPolys.Count > 0)
                {
                    for (int i = 0; i < fairwayPolys.Count; i++)
                    {
                        var fw = fairwayPolys[i];
                        if (pt.X >= fw.MinX && pt.X <= fw.MaxX && pt.Y >= fw.MinY && pt.Y <= fw.MaxY)
                        {
                            if (PointInPolygon(pt, fw.Polygon))
                            {
                                return 0f; // Inside fairway polygon!
                            }
                        }

                        float dx = 0f;
                        if (pt.X < fw.MinX) dx = fw.MinX - pt.X;
                        else if (pt.X > fw.MaxX) dx = pt.X - fw.MaxX;

                        float dy = 0f;
                        if (pt.Y < fw.MinY) dy = fw.MinY - pt.Y;
                        else if (pt.Y > fw.MaxY) dy = pt.Y - fw.MaxY;

                        if (dx >= minFairwayD || dy >= minFairwayD) continue;
                        if (dx * dx + dy * dy >= minFairwayD * minFairwayD) continue;

                        float d = DistanceToPolygon(pt, fw.Polygon);
                        if (d < minFairwayD) minFairwayD = d;
                    }
                    return minFairwayD;
                }
                else if (lineOfPlayPaths.Count > 0)
                {
                    float minCorridorD = float.MaxValue;
                    for (int pIdx = 0; pIdx < lineOfPlayPaths.Count; pIdx++)
                    {
                        var path = lineOfPlayPaths[pIdx];
                        for (int i = 0; i < path.Count - 1; i++)
                        {
                            float d = DistanceToSegment(pt, path[i], path[i + 1]);
                            if (d < minCorridorD) minCorridorD = d;
                        }
                    }
                    return Math.Max(0f, minCorridorD - 16.0f);
                }

                return float.MaxValue;
            };

            // Flight corridor obstruction guard: ensures no generated trees are placed between any tee box and fairway target
            Func<Vector2, bool> isBetweenTeeAndFairway = (pt) =>
            {
                foreach (var kp in holeInfo)
                {
                    var h = kp.Value;
                    if (h.TeeBoxes == null || h.TeeBoxes.Count == 0) continue;

                    Vector2 target;
                    if (h.HolePath != null && h.HolePath.Count > 1)
                    {
                        target = new Vector2(h.HolePath[1][0], h.HolePath[1][1]);
                    }
                    else if (h.HoleLocation != null && h.HoleLocation.Length >= 2)
                    {
                        target = new Vector2(h.HoleLocation[0], h.HoleLocation[1]);
                    }
                    else
                    {
                        continue;
                    }

                    foreach (var teeKvp in h.TeeBoxes)
                    {
                        if (teeKvp.Value == null || teeKvp.Value.Length < 2) continue;
                        var teePos = new Vector2(teeKvp.Value[0], teeKvp.Value[1]);
                        if (IsTreeBetweenTeeAndFairway(pt, teePos, target, 18.0f, 35.0f))
                        {
                            return true;
                        }
                    }
                }
                return false;
            };

            int effectiveMaxTrees = MaxTrees;

            // Scan satellite imagery for additional trees in the rough and background
            var candidatePoints = new List<Vector2>();
            if (satImage != null && effectiveMaxTrees > 0)
            {
                ReportProgress("Scanning foliage from satellite imagery...");
                await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

                GD.Print($"{LogPrefix} Scanning satellite imagery for tree positions...");
                int satWidth = satImage.GetWidth();
                int satHeight = satImage.GetHeight();
                float spacing = effectiveMaxTrees > 4000
                    ? (isComputerPlatform ? 5.0f : 6.5f)
                    : (effectiveMaxTrees > 1800
                        ? (isComputerPlatform ? 6.5f : (isMobilePlatform ? 9.0f : 8.0f))
                        : (isComputerPlatform ? 9.0f : 11.0f));
                float minDistanceBetweenTrees = effectiveMaxTrees > 4000
                    ? (isComputerPlatform ? 7.5f : 9.0f)
                    : (effectiveMaxTrees > 1800
                        ? (isComputerPlatform ? 10.0f : 12.0f)
                        : (isComputerPlatform ? 14.0f : 16.0f));

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

                        // Strictly no generated trees on or close to cart paths (< 2.2m)
                        if (isTooCloseToCartPath(pt, 2.2f)) return;

                        // Strictly no generated trees inside or close to bunker (< 5.0m)
                        if (isTooCloseToBunker(pt, 5.0f)) return;

                        // Strictly no generated trees inside or close to green (< 10.0m)
                        if (isTooCloseToGreen(pt, 10.0f)) return;

                        // Strictly no generated trees close to fairway (< 11m)
                        if (getDistToFairway(pt) < 11.0f) return;

                        // Strictly no generated trees between tee box and fairway
                        if (isBetweenTeeAndFairway(pt)) return;

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
                                    if (DistanceToSegment(pt, path[i], path[i + 1]) < 15.0f)
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
                        ColorToHsv(pixelColor, out _, out _, out float v);

                        // Differentiate real 3D tree canopies/shadows from smooth fairway/rough turf.
                        // Real tree crowns have dark values and pronounced shadow texture variance,
                        // whereas mowed rough turf has low variance and mid-range brightness.
                        bool isTreeCandidate = IsTreeColor(pixelColor) && (
                            (v <= 0.26f && variance >= 0.0028f) ||
                            (v > 0.26f && v <= 0.38f && variance >= 0.0042f) ||
                            (v > 0.40f && variance >= 0.0080f)
                        );

                        if (isTreeCandidate)
                        {
                            localCandidates.Add(pt);
                        }
                    });

                    candidatePoints.AddRange(localCandidates);
                });

                await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

                GD.Print($"{LogPrefix} Found {candidatePoints.Count} tree candidate locations from satellite imagery.");

                // Build fast 2D spatial hash grid so placing thousands of trees evaluates in milliseconds
                float cellSz = minDistanceBetweenTrees;
                float minDstSq = minDistanceBetweenTrees * minDistanceBetweenTrees;
                var spatialGrid = new Dictionary<long, List<Vector2>>();

                long GetGridKey(float gx_val, float gz_val)
                {
                    int g_x = (int)Math.Floor(gx_val / cellSz);
                    int g_z = (int)Math.Floor(gz_val / cellSz);
                    return ((long)g_x << 32) ^ (uint)g_z;
                }

                void RegisterTree(Vector2 pos)
                {
                    placedTreePositions.Add(pos);
                    long k = GetGridKey(pos.X, pos.Y);
                    if (!spatialGrid.TryGetValue(k, out var list))
                    {
                        list = new List<Vector2>(4);
                        spatialGrid[k] = list;
                    }
                    list.Add(pos);
                }

                // Register all authentic OSM trees into spatial hash
                var initialOsmTrees = placedTreePositions.ToArray();
                placedTreePositions.Clear();
                foreach (var pos in initialOsmTrees)
                {
                    RegisterTree(pos);
                }

                // Evaluate all candidate points from satellite imagery against spatial hash grid
                // to build the complete, uncorrupted set of valid tree positions.
                var validSatelliteTrees = new List<Vector2>();
                foreach (var pt in candidatePoints)
                {
                    int gx = (int)Math.Floor(pt.X / cellSz);
                    int gz = (int)Math.Floor(pt.Y / cellSz);
                    bool tooClose = false;

                    for (int dx = -1; dx <= 1 && !tooClose; dx++)
                    {
                        for (int dz = -1; dz <= 1; dz++)
                        {
                            long nk = ((long)(gx + dx) << 32) ^ (uint)(gz + dz);
                            if (spatialGrid.TryGetValue(nk, out var cellList))
                            {
                                for (int c = 0; c < cellList.Count; c++)
                                {
                                    if (pt.DistanceSquaredTo(cellList[c]) < minDstSq)
                                    {
                                        tooClose = true;
                                        break;
                                    }
                                }
                                if (tooClose) break;
                            }
                        }
                    }

                    if (!tooClose)
                    {
                        RegisterTree(pt);
                        validSatelliteTrees.Add(pt);
                    }
                }

                // If placed trees exceed user-configured limit, retain authentic OSM trees and prioritize
                // satellite trees along the hole corridors so every hole looks lush and properly framed.
                if (effectiveMaxTrees > 0 && placedTreePositions.Count > effectiveMaxTrees)
                {
                    int satBudget = Math.Max(0, effectiveMaxTrees - initialOsmTrees.Length);
                    if (validSatelliteTrees.Count > satBudget)
                    {
                        float GetMinDistanceToHoles(Vector2 pt)
                        {
                            float minDist = float.MaxValue;
                            for (int pIdx = 0; pIdx < lineOfPlayPaths.Count; pIdx++)
                            {
                                var path = lineOfPlayPaths[pIdx];
                                for (int i = 0; i < path.Count - 1; i++)
                                {
                                    float d = DistanceToSegment(pt, path[i], path[i + 1]);
                                    if (d < minDist) minDist = d;
                                }
                            }
                            return minDist;
                        }

                        // Keep trees framing hole corridors first, then remaining budget
                        var sortedSatelliteTrees = validSatelliteTrees.OrderBy(pt => GetMinDistanceToHoles(pt)).ToList();
                        var keptSet = sortedSatelliteTrees.Take(satBudget).ToHashSet();

                        placedTreePositions.Clear();
                        spatialGrid.Clear();
                        foreach (var pos in initialOsmTrees)
                        {
                            RegisterTree(pos);
                        }
                        foreach (var pos in validSatelliteTrees)
                        {
                            if (keptSet.Contains(pos))
                            {
                                RegisterTree(pos);
                            }
                        }
                        GD.Print($"{LogPrefix} Satellite trees capped to {satBudget} with hole-corridor framing prioritized (total placed: {placedTreePositions.Count}).");
                    }
                }
                else
                {
                    GD.Print($"{LogPrefix} Retaining all {validSatelliteTrees.Count} valid satellite trees (total placed: {placedTreePositions.Count}, cap: {effectiveMaxTrees}).");
                }
            }

            // Populate all OSM forest and wood polygons
            if (effectiveMaxTrees > 0 && placedTreePositions.Count < effectiveMaxTrees && forestPolygons.Count > 0)
            {
                GD.Print($"{LogPrefix} Populating {forestPolygons.Count} OSM forest/wood polygons with trees...");
                foreach (var forestPoly in forestPolygons)
                {
                    if (placedTreePositions.Count >= effectiveMaxTrees) break;
                    if (forestPoly.Length < 3) continue;
                    float minX = forestPoly.Min(p => p.X);
                    float maxX = forestPoly.Max(p => p.X);
                    float minY = forestPoly.Min(p => p.Y);
                    float maxY = forestPoly.Max(p => p.Y);
                    float width = maxX - minX;
                    float height = maxY - minY;
                    float area = width * height;
                    int targetForestTrees = Math.Max(3, (int)(area / (isComputerPlatform ? 80f : (isMobilePlatform ? 250f : 180f))));
                    targetForestTrees = Math.Min(targetForestTrees, effectiveMaxTrees - placedTreePositions.Count);

                    var fRnd = new Random((int)(minX * 100f) ^ (int)(minY * 100f));
                    int forestSpawned = 0;
                    float forestMinDist = isComputerPlatform ? 5.0f : 7.0f;
                    for (int attempt = 0; attempt < targetForestTrees * 5 && forestSpawned < targetForestTrees; attempt++)
                    {
                        float rx = minX + (float)fRnd.NextDouble() * width;
                        float rz = minY + (float)fRnd.NextDouble() * height;
                        var rp = new Vector2(rx, rz);
                        if (Geometry2D.IsPointInPolygon(rp, forestPoly))
                        {
                            // Check play surface exclusions
                            bool insideExclusion = false;
                            for (int i = 0; i < exclusionPolygons.Count; i++)
                            {
                                var excl = exclusionPolygons[i];
                                if (rx >= excl.MinX && rx <= excl.MaxX && rz >= excl.MinY && rz <= excl.MaxY)
                                {
                                    if (PointInPolygon(rp, excl.Polygon))
                                    {
                                        insideExclusion = true;
                                        break;
                                    }
                                }
                            }
                            if (insideExclusion) continue;

                            // Strictly no generated trees on or close to cart paths (< 2.2m)
                            if (isTooCloseToCartPath(rp, 2.2f)) continue;

                            // Strictly no generated trees inside or close to bunker (< 5.0m)
                            if (isTooCloseToBunker(rp, 5.0f)) continue;

                            // Strictly no generated trees inside or close to green (< 10.0m)
                            if (isTooCloseToGreen(rp, 10.0f)) continue;

                            // Strictly no generated trees close to fairway (< 11m)
                            if (getDistToFairway(rp) < 11.0f) continue;

                            // Strictly no generated trees between tee box and fairway
                            if (isBetweenTeeAndFairway(rp)) continue;

                            bool tooClose = false;
                            for (int i = 0; i < placedTreePositions.Count; i++)
                            {
                                if (rp.DistanceTo(placedTreePositions[i]) < forestMinDist)
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
            int targetTreesPerHole = effectiveMaxTrees > 4000 ? 120 : (effectiveMaxTrees > 1800 ? 65 : 35);
            int targetTreeCount = isComputerPlatform
                ? Math.Max(240, Math.Max(lineOfPlayPaths.Count, holeInfo.Count) * targetTreesPerHole)
                : (isMobilePlatform
                    ? Math.Clamp(Math.Max(lineOfPlayPaths.Count, holeInfo.Count) * Math.Min(24, targetTreesPerHole), 100, 1000)
                    : Math.Max(120, Math.Max(lineOfPlayPaths.Count, holeInfo.Count) * targetTreesPerHole));

            if (effectiveMaxTrees > 0)
            {
                targetTreeCount = Math.Min(targetTreeCount, effectiveMaxTrees);
            }
            else
            {
                targetTreeCount = 0;
            }

            if (effectiveMaxTrees > 0 && placedTreePositions.Count < targetTreeCount)
            {
                GD.Print($"{LogPrefix} Tree count ({placedTreePositions.Count}) is below target ({targetTreeCount}). Generating procedural tree placement fallback...");
                var procRnd = new Random(54321);

                float minProcTreeDist = isComputerPlatform ? 10.0f : 12.0f;
                Func<Vector2, bool> isProceduralPointValid = (pt) =>
                {
                    if (placedTreePositions.Count >= effectiveMaxTrees) return false;
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

                    // Strictly no generated trees on or close to cart paths (< 2.2m)
                    if (isTooCloseToCartPath(pt, 2.2f)) return false;

                    // Strictly no generated trees inside or close to bunker (< 5.0m)
                    if (isTooCloseToBunker(pt, 5.0f)) return false;

                    // Strictly no generated trees inside or close to green (< 10.0m)
                    if (isTooCloseToGreen(pt, 10.0f)) return false;

                    // Strictly no generated trees close to fairway (< 11m)
                    if (getDistToFairway(pt) < 11.0f) return false;

                    // Strictly no generated trees between tee box and fairway
                    if (isBetweenTeeAndFairway(pt)) return false;

                    for (int pIdx = 0; pIdx < lineOfPlayPaths.Count; pIdx++)
                    {
                        var path = lineOfPlayPaths[pIdx];
                        for (int i = 0; i < path.Count - 1; i++)
                        {
                            if (DistanceToSegment(pt, path[i], path[i + 1]) < 15.0f)
                                return false;
                        }
                    }

                    for (int i = 0; i < placedTreePositions.Count; i++)
                    {
                        if (pt.DistanceTo(placedTreePositions[i]) < minProcTreeDist)
                            return false;
                    }

                    return true;
                };

                // Pass A: Hole corridor fairway framing stands
                float stepA = isComputerPlatform ? 14f : 18f;
                float[] leftOffsets = isComputerPlatform ? new float[] { -28f, -38f, -48f } : new float[] { -28f, -40f };
                float[] rightOffsets = isComputerPlatform ? new float[] { 28f, 38f, 48f } : new float[] { 28f, 40f };
                foreach (var path in lineOfPlayPaths)
                {
                    if (placedTreePositions.Count >= effectiveMaxTrees) break;
                    if (path.Count < 2) continue;
                    float totalLength = 0f;
                    for (int i = 0; i < path.Count - 1; i++) totalLength += path[i].DistanceTo(path[i + 1]);
                    if (totalLength < 40f) continue;

                    for (float d = 30f; d < totalLength - 20f && placedTreePositions.Count < effectiveMaxTrees; d += stepA)
                    {
                        var centerPt = GetPointOnPolyline(path, d);
                        var nextPt = GetPointOnPolyline(path, Math.Min(d + 5f, totalLength));
                        var fwd = (nextPt - centerPt).Normalized();
                        if (fwd.LengthSquared() < 0.001f) fwd = new Vector2(1, 0);
                        var perp = new Vector2(-fwd.Y, fwd.X);

                        // Left stands
                        foreach (var off in leftOffsets)
                        {
                            if (placedTreePositions.Count >= effectiveMaxTrees) break;
                            var cand = centerPt + perp * (off + (float)(procRnd.NextDouble() * 8.0 - 4.0)) + fwd * (float)(procRnd.NextDouble() * 6.0 - 3.0);
                            if (isProceduralPointValid(cand))
                            {
                                placedTreePositions.Add(cand);
                            }
                        }

                        // Right stands
                        foreach (var off in rightOffsets)
                        {
                            if (placedTreePositions.Count >= effectiveMaxTrees) break;
                            var cand = centerPt + perp * (off + (float)(procRnd.NextDouble() * 8.0 - 4.0)) + fwd * (float)(procRnd.NextDouble() * 6.0 - 3.0);
                            if (isProceduralPointValid(cand))
                            {
                                placedTreePositions.Add(cand);
                            }
                        }
                    }
                }

                // Pass B: Green backdrop clusters (strictly BEHIND green away from approach)
                int greenAttempts = isComputerPlatform ? 16 : 8;
                foreach (var kp in holeInfo)
                {
                    if (placedTreePositions.Count >= effectiveMaxTrees) break;
                    if (kp.Value.HoleLocation == null || kp.Value.HoleLocation.Length < 2) continue;
                    var pinPos = new Vector2(kp.Value.HoleLocation[0], kp.Value.HoleLocation[1]);

                    Vector2 approachDir = new Vector2(0, 1);
                    if (kp.Value.HolePath != null && kp.Value.HolePath.Count >= 2)
                    {
                        var lastPathPt = new Vector2(kp.Value.HolePath[kp.Value.HolePath.Count - 2][0], kp.Value.HolePath[kp.Value.HolePath.Count - 2][1]);
                        if (lastPathPt.DistanceSquaredTo(pinPos) > 1.0f)
                        {
                            approachDir = (pinPos - lastPathPt).Normalized();
                        }
                    }
                    float baseRearAngle = Mathf.Atan2(approachDir.Y, approachDir.X);

                    for (int attempt = 0; attempt < greenAttempts && placedTreePositions.Count < effectiveMaxTrees; attempt++)
                    {
                        // Fan out strictly in the rear hemisphere (+/- 60 degrees) behind the green
                        float angle = baseRearAngle + (float)(procRnd.NextDouble() * 2.0 - 1.0) * (Mathf.Pi / 3.0f);
                        float dist = 22f + (float)procRnd.NextDouble() * 14f;
                        var cand = pinPos + new Vector2(Mathf.Cos(angle) * dist, Mathf.Sin(angle) * dist);
                        if (isProceduralPointValid(cand))
                        {
                            placedTreePositions.Add(cand);
                        }
                    }
                }

                // Pass C: Tee backdrops (strictly BEHIND tee boxes, away from fairway)
                int teeAttempts = isComputerPlatform ? 12 : 6;
                foreach (var kp in holeInfo)
                {
                    if (placedTreePositions.Count >= effectiveMaxTrees) break;
                    if (kp.Value.TeeBoxes != null)
                    {
                        Vector2 target;
                        if (kp.Value.HolePath != null && kp.Value.HolePath.Count > 1)
                        {
                            target = new Vector2(kp.Value.HolePath[1][0], kp.Value.HolePath[1][1]);
                        }
                        else if (kp.Value.HoleLocation != null && kp.Value.HoleLocation.Length >= 2)
                        {
                            target = new Vector2(kp.Value.HoleLocation[0], kp.Value.HoleLocation[1]);
                        }
                        else
                        {
                            target = Vector2.Zero;
                        }

                        foreach (var teeKvp in kp.Value.TeeBoxes)
                        {
                            if (placedTreePositions.Count >= effectiveMaxTrees) break;
                            if (teeKvp.Value == null || teeKvp.Value.Length < 2) continue;
                            var teePos = new Vector2(teeKvp.Value[0], teeKvp.Value[1]);

                            Vector2 fwd = (target != Vector2.Zero && target != teePos)
                                ? (target - teePos).Normalized()
                                : new Vector2(0, 1);
                            float baseRearAngle = Mathf.Atan2(-fwd.Y, -fwd.X);

                            for (int attempt = 0; attempt < teeAttempts && placedTreePositions.Count < effectiveMaxTrees; attempt++)
                            {
                                // Fan out strictly in the rear hemisphere (+/- 60 degrees) behind the tee box
                                float angle = baseRearAngle + (float)(procRnd.NextDouble() * 2.0 - 1.0) * (Mathf.Pi / 3.0f);
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
                    float stepD = isComputerPlatform ? 24f : 30f;
                    for (float rx = courseMinX + 15f; rx <= courseMaxX - 15f && placedTreePositions.Count < targetTreeCount && placedTreePositions.Count < effectiveMaxTrees; rx += stepD)
                    {
                        for (float rz = courseMinZ + 15f; rz <= courseMaxZ - 15f && placedTreePositions.Count < targetTreeCount && placedTreePositions.Count < effectiveMaxTrees; rz += stepD)
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

                GD.Print($"{LogPrefix} Normal tree generation completed. Total trees placed: {placedTreePositions.Count}.");
            }

            if (effectiveMaxTrees <= 0)
            {
                placedTreePositions.Clear();
            }

            float cellSize = isMobilePlatform ? 5.0f : 2.0f;
            int maxSubdiv = isMobilePlatform ? 250 : 600;
            int subdivisionsX = Mathf.Clamp((int)Math.Ceiling(courseWidth / cellSize), 40, maxSubdiv);
            int subdivisionsZ = Mathf.Clamp((int)Math.Ceiling(courseDepth / cellSize), 40, maxSubdiv);

            ReportProgress("Generating 3D terrain and surface blend maps...");
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

            // Generate unified terrain with mulch mapped around all tree positions!
            await CreateUnifiedTerrainAsync(courseMinX, courseMaxX, courseMinZ, courseMaxZ, subdivisionsX, subdivisionsZ, rootNode, exclusionPolygons, placedTreePositions);

            if (GenerateCartPaths)
            {
                cartPaths = MergeCartPaths(cartPaths, 2.0f);
                for (int pathIndex = 0; pathIndex < cartPaths.Count; pathIndex++)
                {
                    CreateCartPath(rootNode, cartPaths[pathIndex], pathIndex, exclusionPolygons);
                }
            }

            ReportProgress("Placing trees, greens, and course objects...");
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

            // Identify exactly 1 (or infrequently 2 max) weeping willows per water feature, and none anywhere else
            var willowTreePositions = new HashSet<Vector2>();
            if (waterPolygons != null && waterPolygons.Count > 0)
            {
                for (int wIdx = 0; wIdx < waterPolygons.Count; wIdx++)
                {
                    var waterPoly = waterPolygons[wIdx];
                    if (waterPoly == null || waterPoly.Length < 3) continue;

                    // Centroid of water polygon to deterministically seed random selection for this feature
                    float cX = 0f, cY = 0f;
                    foreach (var p in waterPoly) { cX += p.X; cY += p.Y; }
                    cX /= waterPoly.Length;
                    cY /= waterPoly.Length;
                    int polySeed = (int)(cX * 137.0f) ^ (int)(cY * 269.0f) ^ wIdx;
                    var waterRnd = new Random(polySeed);

                    // Infrequent across water hazards: exactly 15% of water hazards spawn a willow
                    if (waterRnd.NextDouble() >= 0.15)
                        continue;

                    // Find all placed trees within shoreline range of this water feature (2.5m to 32.0m)
                    var shorelineCandidates = new List<Vector2>();
                    foreach (var pt in placedTreePositions)
                    {
                        float d = DistanceToPolygon(pt, waterPoly);
                        if (d >= 2.5f && d <= 32.0f)
                        {
                            shorelineCandidates.Add(pt);
                        }
                    }

                    if (shorelineCandidates.Count == 0)
                        continue;

                    // Check if any candidates are already designated as willows (e.g. from an adjacent/overlapping water feature)
                    int alreadyAssignedCount = shorelineCandidates.Count(c => willowTreePositions.Contains(c));
                    if (alreadyAssignedCount >= 2)
                        continue; // Already has 2 willows for this water feature

                    // 1 or infrequently 2 max per water feature
                    // Only 15% chance of 2 willows if enough shoreline candidates (>= 4) exist, otherwise exactly 1
                    int targetWillows = (shorelineCandidates.Count >= 4 && waterRnd.NextDouble() < 0.15) ? 2 : 1;
                    int needed = targetWillows - alreadyAssignedCount;
                    if (needed <= 0)
                        continue;

                    // Sort unassigned candidates by distance to water with slight jitter so it prefers trees on the bank
                    var available = shorelineCandidates.Where(c => !willowTreePositions.Contains(c))
                                                       .OrderBy(c => DistanceToPolygon(c, waterPoly) + (float)waterRnd.NextDouble() * 5.0f)
                                                       .ToList();

                    if (available.Count > 0)
                    {
                        var firstWillow = available[0];
                        willowTreePositions.Add(firstWillow);
                        needed--;

                        // If 2nd willow is allowed, pick one spaced well apart (at least 20m) so they don't bunch together
                        if (needed > 0 && available.Count > 1)
                        {
                            for (int i = 1; i < available.Count; i++)
                            {
                                if (available[i].DistanceTo(firstWillow) >= 20.0f)
                                {
                                    willowTreePositions.Add(available[i]);
                                    break;
                                }
                            }
                        }
                    }
                }
            }

            // Spawn all trees (OSM + satellite selected) with weeping willows ONLY at designated water feature spots (1 or infrequently 2 max)
            int placedWillowCount = 0;
            foreach (var pt in placedTreePositions)
            {
                float height = GetHeight(pt.X, pt.Y);
                bool isWillow = willowTreePositions.Contains(pt);
                if (isWillow) placedWillowCount++;
                AddTreeAt(rootNode, new Vector3(pt.X, height, pt.Y), isWillow);
            }
            GD.Print($"{LogPrefix} Placed {placedTreePositions.Count} trees total ({placedWillowCount} weeping willows: 1 or infrequently 2 max per water feature, none elsewhere).");

            // Spawn random bushes clustered around a subset of trees (capped at 100 on mobile, 2400 on computer, 1200 on desktop)
            if (GenerateBushes && placedTreePositions.Count > 0)
            {
                GD.Print($"{LogPrefix} Placing bushes clustered around trees...");
                var bushRnd = new Random(99);
                int bushCount = 0;
                int maxBushes = isComputerPlatform ? 2400 : (isMobilePlatform ? 100 : 1200);
                if (effectiveMaxTrees <= 1500)
                {
                    maxBushes = (int)(maxBushes * 0.25f);
                }
                else if (effectiveMaxTrees <= 3500)
                {
                    maxBushes = (int)(maxBushes * 0.50f);
                }
                var placedBushPositions = new List<Vector2>();

                var treeIndices = Enumerable.Range(0, placedTreePositions.Count).OrderBy(x => bushRnd.Next()).ToList();
                int treesWithBushesCount = (int)(placedTreePositions.Count * (isComputerPlatform ? 0.70 : 0.35));
                float minBushDist = isComputerPlatform ? 0.9f : 1.2f;

                for (int tIdx = 0; tIdx < treesWithBushesCount && bushCount < maxBushes; tIdx++)
                {
                    var treePos = placedTreePositions[treeIndices[tIdx]];
                    int numBushesAroundTree = bushRnd.Next(1, isComputerPlatform ? 5 : 4);

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
                        if (isTooCloseToCartPath(pt, 2.2f)) continue;
                        if (isTooCloseToBunker(pt, 3.5f)) continue;
                        if (isTooCloseToGreen(pt, 5.0f)) continue;

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
                            if (pt.DistanceTo(bushPos) < minBushDist)
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

            // Tall grass around water hazards is procedurally generated all the way around every water hazard
            // in CourseDetailEnhancer._build_shoreline_reeds (replacing legacy limited rock decorations).

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

            ReportProgress("Generating aerial hole overviews...");
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

            await GenerateAerialPreviewsAsync(rootNode, courseDir, globalCourseDir, holeInfo, isMobilePlatform);

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
                ProcessMode = Sky.ProcessModeEnum.Quality,
                RadianceSize = isMobilePlatform ? Sky.RadianceSizeEnum.Size128 : Sky.RadianceSizeEnum.Size256
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

            // Extract OSM cart path polylines if available
            var cartPathPolylines = new Godot.Collections.Array();
            if (cartPaths != null && cartPaths.Count > 0)
            {
                foreach (var path in cartPaths)
                {
                    if (path.Count >= 2)
                    {
                        cartPathPolylines.Add(path.ToArray());
                    }
                }
            }
            else
            {
                foreach (var w in ways)
                {
                    bool isCartPath = (w.Tags.TryGetValue("golf", out var gTag) && (gTag == "cartpath" || gTag == "cart_path")) ||
                                      (w.Tags.TryGetValue("highway", out var hTag) && (hTag == "path" || hTag == "footway"));
                    if (!isCartPath || w.NodeIds.Count < 2)
                        continue;
                    var pts = w.NodeIds
                        .Where(nodes.ContainsKey)
                        .Select(id => nodes[id])
                        .Select(coord => new Vector2(
                            (float)((coord.Lon - refLon) * metersPerLon),
                            -(float)((coord.Lat - refLat) * metersPerLat)
                        ))
                        .ToArray();
                    if (pts.Length >= 2)
                    {
                        cartPathPolylines.Add(pts);
                    }
                }
            }
            if (cartPathPolylines.Count > 0)
            {
                rootNode.SetMeta("cart_path_polylines", cartPathPolylines);
            }

            // Expose hole line of play paths so detail enhancers (thick rough fescue, bushes, cart paths)
            // can generate rich vegetation across every hole on the course.
            if (lineOfPlayPaths.Count > 0)
            {
                var gdHoleLines = new Godot.Collections.Array();
                foreach (var path in lineOfPlayPaths)
                {
                    if (path != null && path.Count >= 2)
                    {
                        gdHoleLines.Add(path.ToArray());
                    }
                }
                rootNode.SetMeta("hole_paths", gdHoleLines);
            }

            // Convert individual foliage nodes into spatial MultiMesh chunks & build 3D recessed bunkers/reeds/horizon/cart paths
            var treeGenScript = GD.Load<Script>("res://HighFidelity/Foliage/procedural_tree_generator.gd");
            treeGenScript?.Call("convert_scene_foliage_to_multimesh", rootNode, true);

            rootNode.SetMeta("generate_water_long_grass", GenerateWaterLongGrass);
            rootNode.SetMeta("generate_bushes", GenerateBushes);
            rootNode.SetMeta("generate_cart_paths", GenerateCartPaths);
            rootNode.SetMeta("generate_3d_bunkers", Generate3dBunkers);
            rootNode.SetMeta("max_trees", MaxTrees);
            rootNode.SetMeta("create_18_hole_permutations", Create18HolePermutations);

            var detailEnhancerScript = GD.Load<Script>("res://HighFidelity/Terrain/course_detail_enhancer.gd");
            detailEnhancerScript?.Call("enhance_course_scene", rootNode, true);

            // Set main scene script
            rootNode.SetScript(GD.Load<Script>("res://Courses/Range/range.gd"));

            ReportProgress("Saving 3D course files...");
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
            var preferredOrder = new[] { "Black", "Gold", "Blue", "White", "Red", "Green", "Orange" };
            var teeColors = holeInfo.Values
                .SelectMany(h => h.TeeBoxes.Keys)
                .Distinct()
                .OrderBy(c => {
                    int idx = Array.IndexOf(preferredOrder, c);
                    return idx >= 0 ? idx : 99;
                })
                .ToList();
            if (teeColors.Count == 0) teeColors.Add("Blue");

            var courseConfig = new CourseJsonConfig
            {
                ScenePath = "course.tscn",
                Title = courseTitle,
                Latitude = lat,
                Longitude = lon,
                Location = location,
                CourseInfo = new CourseInfoConfig
                {
                    TeeColors = teeColors,
                    SatelliteImageBounds = _downloadedSatelliteImageBounds,
                    SatelliteImageBoundsVersion = 5,
                    CartPaths = cartPaths.Count == 0
                        ? null
                        : cartPaths.Select(path => path.Select(point => new[] { point.X, point.Y }).ToList()).ToList(),
                    SourceCourse = variant?.SourceCourse,
                    SubCourses = variant?.SubCourses.ToList(),
                    VariantType = variant?.VariantType,
                    OsmRelation = string.IsNullOrWhiteSpace(variant?.OsmRelationName) ? null : variant.OsmRelationName,
                    OsmRelationId = string.IsNullOrWhiteSpace(variant?.OsmRelationId) ? null : variant.OsmRelationId,
                    AvailableVariants = availableVariants
                },
                HoleInfo = holeInfo
            };

            var options = new JsonSerializerOptions { WriteIndented = true };
            string configJson = JsonSerializer.Serialize(courseConfig, options);
            File.WriteAllText(globalJsonPath, configJson);

            // Free the course node tree from memory now that it has been saved to disk
            rootNode.QueueFree();

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

    private async Task GenerateAerialPreviewsAsync(Node3D rootNode, string courseDir, string globalCourseDir, Dictionary<string, HoleConfig> holeInfo, bool isMobilePlatform)
    {
        if (DisplayServer.GetName() == "headless")
        {
            GD.Print($"{LogPrefix} Headless mode: skipping top-down aerial snapshot generation.");
            return;
        }

        SubViewport? subViewport = null;
        try
        {
            GD.Print($"{LogPrefix} Generating top-down aerial snapshots for course and holes...");
            int vpSize = isMobilePlatform ? 512 : 1024;
            subViewport = new SubViewport();
            subViewport.Size = new Vector2I(vpSize, vpSize);
            subViewport.RenderTargetUpdateMode = SubViewport.UpdateMode.Always;
            subViewport.OwnWorld3D = true;
            subViewport.World3D = new World3D();

            var env = new Godot.Environment
            {
                BackgroundMode = Godot.Environment.BGMode.Color,
                BackgroundColor = new Color(0.18f, 0.32f, 0.15f),
                AmbientLightSource = Godot.Environment.AmbientSource.Color,
                AmbientLightColor = new Color(0.95f, 0.95f, 0.95f),
                AmbientLightEnergy = 0.85f
            };
            var worldEnv = new WorldEnvironment { Environment = env };
            subViewport.AddChild(worldEnv);

            var topSun = new DirectionalLight3D
            {
                LightEnergy = 1.0f,
                Transform = new Transform3D(
                    new Basis(new Vector3(1f, 0f, 0f), Mathf.DegToRad(-65f)) *
                    new Basis(new Vector3(0f, 1f, 0f), Mathf.DegToRad(35f)),
                    new Vector3(0, 200, 0)
                )
            };
            subViewport.AddChild(topSun);

            var tempCam = new Camera3D();
            tempCam.Projection = Camera3D.ProjectionType.Orthogonal;
            subViewport.AddChild(tempCam);

            // Attach rootNode directly before gameplay scripts/nodes were added to avoid scene duplication
            subViewport.AddChild(rootNode);
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

            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
            if (DisplayServer.GetName() != "headless")
            {
                await ToSignal(RenderingServer.Singleton, RenderingServer.SignalName.FramePostDraw);
            }
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

                await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
                if (DisplayServer.GetName() != "headless")
                {
                    await ToSignal(RenderingServer.Singleton, RenderingServer.SignalName.FramePostDraw);
                }
                var holeImg = subViewport.GetTexture().GetImage();
                if (holeImg != null)
                {
                    string holeImgPath = Path.Combine(globalCourseDir, $"aerial_hole_{i + 1}.png");
                    holeImg.SavePng(holeImgPath);
                    GD.Print($"{LogPrefix} Saved aerial snapshot for Hole {i + 1}: {holeImgPath}");
                }
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Exception during aerial preview generation: {ex}");
        }
        finally
        {
            if (subViewport != null)
            {
                if (rootNode.GetParent() == subViewport)
                {
                    subViewport.RemoveChild(rootNode);
                }
                if (subViewport.GetParent() == this)
                {
                    RemoveChild(subViewport);
                }
                subViewport.QueueFree();
            }
        }
    }

    public void SearchGolfCourses(string queryText)
    {
        SearchGolfCourses(queryText, null);
    }

    public async void SearchGolfCourses(string queryText, Godot.Collections.Dictionary? options)
    {
        try
        {
            var rawResults = await Task.Run(() => SearchGolfCoursesInternalAsync(queryText, options));
            Callable.From(() =>
            {
                if (!IsInstanceValid(this)) return;
                var godotResults = new Godot.Collections.Array();
                bool forceOnline = options != null && options.ContainsKey("force_online") && options["force_online"].AsBool();
                foreach (var item in rawResults)
                {
                    var dict = new Godot.Collections.Dictionary();
                    dict["name"] = item.Name;
                    dict["lat"] = item.Lat;
                    dict["lon"] = item.Lon;
                    dict["location"] = item.Location;
                    dict["hole_count"] = item.HoleCount;
                    dict["last_updated"] = item.LastUpdated;
                    dict["is_catalog"] = item.IsCatalog;
                    dict["is_cached"] = forceOnline ? false : IsCourseCached(item.Name, item.Lat, item.Lon);
                    dict["is_pga_tour"] = item.IsPgaTour;
                    dict["force_online"] = forceOnline;
                    godotResults.Add(dict);
                }
                EmitSignal(SignalName.SearchCompleted, godotResults);
            }).CallDeferred();
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Exception in SearchGolfCourses: {ex.Message}");
            Callable.From(() =>
            {
                if (IsInstanceValid(this))
                {
                    EmitSignal(SignalName.SearchCompleted, new Godot.Collections.Array());
                }
            }).CallDeferred();
        }
    }

    public Godot.Collections.Array GetCachedCourses()
    {
        return GetCachedCourses(null);
    }

    public Godot.Collections.Array GetCachedCourses(Godot.Collections.Dictionary? options)
    {
        var list = LoadBundledCatalog();
        bool include9 = true;
        bool include18 = true;
        bool includeAll = false;
        if (options != null)
        {
            if (options.ContainsKey("include_9_hole")) include9 = options["include_9_hole"].AsBool();
            if (options.ContainsKey("include_18_hole")) include18 = options["include_18_hole"].AsBool();
            if (options.ContainsKey("include_all_holes")) includeAll = options["include_all_holes"].AsBool();
        }

        var results = new Godot.Collections.Array();
        var sorted = list
            .OrderByDescending(c => c.IsPgaTour)
            .ThenBy(c => c.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
        foreach (var item in sorted)
        {
            if (!includeAll)
            {
                if (!include9 && (item.HoleCount == 9 || (item.HoleCount > 9 && item.HoleCount % 9 == 0))) continue;
                if (!include18 && (item.HoleCount == 18 || item.HoleCount >= 18)) continue;
            }

            if (!IsCourseCached(item.Name, item.Lat, item.Lon)) continue;

            var dict = new Godot.Collections.Dictionary();
            dict["name"] = item.Name;
            dict["lat"] = item.Lat;
            dict["lon"] = item.Lon;
            dict["location"] = item.Location;
            dict["hole_count"] = item.HoleCount;
            dict["last_updated"] = item.LastUpdated;
            dict["is_catalog"] = true;
            dict["is_cached"] = true;
            dict["is_pga_tour"] = item.IsPgaTour;
            results.Add(dict);
        }

        // Also discover any loose cached geometry files not in the catalog
        var seenSlugs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in sorted)
        {
            var candidateSlugs = GetCourseGeometryCandidateSlugs(item.Name);
            foreach (var s in candidateSlugs)
            {
                if (!string.IsNullOrEmpty(s))
                    seenSlugs.Add(s);
            }
        }

        string[] cacheDirs = new[] { "res://Courses/CachedGeometry" };
        foreach (var cDir in cacheDirs)
        {
            if (!Godot.DirAccess.DirExistsAbsolute(cDir)) continue;
            using var dir = Godot.DirAccess.Open(cDir);
            if (dir == null) continue;
            dir.ListDirBegin();
            string f = dir.GetNext();
            while (!string.IsNullOrEmpty(f))
            {
                if (!dir.CurrentIsDir() && (f.EndsWith(".json.gz", StringComparison.OrdinalIgnoreCase) || f.EndsWith(".json", StringComparison.OrdinalIgnoreCase)))
                {
                    string fSlug = f.EndsWith(".json.gz", StringComparison.OrdinalIgnoreCase)
                        ? f.Substring(0, f.Length - 8)
                        : f.Substring(0, f.Length - 5);
                    if (!seenSlugs.Contains(fSlug))
                    {
                        seenSlugs.Add(fSlug);
                        string title = System.Globalization.CultureInfo.InvariantCulture.TextInfo.ToTitleCase(fSlug.Replace('_', ' '));
                        var dict = new Godot.Collections.Dictionary();
                        dict["name"] = title;
                        dict["lat"] = 0.0;
                        dict["lon"] = 0.0;
                        dict["location"] = "Cached Course";
                        dict["hole_count"] = 18;
                        dict["last_updated"] = "";
                        dict["is_catalog"] = false;
                        dict["is_cached"] = true;
                        dict["is_pga_tour"] = false;
                        results.Add(dict);
                    }
                }
                f = dir.GetNext();
            }
            dir.ListDirEnd();
        }

        return results;
    }

    public bool IsCourseCached(string courseName)
    {
        return IsCourseCached(courseName, 0, 0);
    }

    public bool IsCourseCached(string courseName, double targetLat, double targetLon)
    {
        if (string.IsNullOrWhiteSpace(courseName)) return false;
        var slugs = GetCourseGeometryCandidateSlugs(courseName);
        foreach (var slug in slugs)
        {
            string gzPath = $"res://Courses/CachedGeometry/{slug}.json.gz";
            string jsonPath = $"res://Courses/CachedGeometry/{slug}.json";
            string? foundPath = null;
            if (Godot.FileAccess.FileExists(gzPath)) foundPath = gzPath;
            else if (Godot.FileAccess.FileExists(jsonPath)) foundPath = jsonPath;

            if (foundPath == null) continue;

            if (targetLat == 0 && targetLon == 0)
            {
                return true;
            }

            // Verify proximity to target coordinates
            if (TryGetCachedCourseCoordinates(slug, out var coordsList))
            {
                if (coordsList.Any(c => HaversineDistanceMeters(targetLat, targetLon, c.Lat, c.Lon) <= 25000.0))
                {
                    return true;
                }
            }
            else
            {
                if (TryExtractFirstNodeFromPath(foundPath, out double fLat, out double fLon))
                {
                    RegisterCachedSlugCoordinate(slug, fLat, fLon);
                    if (HaversineDistanceMeters(targetLat, targetLon, fLat, fLon) <= 25000.0)
                    {
                        return true;
                    }
                }
                else
                {
                    return true;
                }
            }
        }
        return false;
    }

    public Godot.Collections.Array SearchCachedCourses(string queryText)
    {
        return SearchCachedCourses(queryText, null);
    }

    public Godot.Collections.Array SearchCachedCourses(string queryText, Godot.Collections.Dictionary? options)
    {
        if (string.IsNullOrWhiteSpace(queryText))
        {
            return GetCachedCourses(options);
        }

        var list = LoadBundledCatalog();
        bool include9 = true;
        bool include18 = true;
        bool includeAll = false;
        if (options != null)
        {
            if (options.ContainsKey("include_9_hole")) include9 = options["include_9_hole"].AsBool();
            if (options.ContainsKey("include_18_hole")) include18 = options["include_18_hole"].AsBool();
            if (options.ContainsKey("include_all_holes")) includeAll = options["include_all_holes"].AsBool();
        }

        string cleanQuery = queryText.Trim();
        var queryTokens = cleanQuery.ToLowerInvariant()
            .Split(new[] { ' ', ',', '-', '/', '.', '(', ')' }, StringSplitOptions.RemoveEmptyEntries);

        var matches = new List<GolfSearchResult>();
        foreach (var course in list)
        {
            if (!includeAll)
            {
                if (!include9 && (course.HoleCount == 9 || (course.HoleCount > 9 && course.HoleCount % 9 == 0))) continue;
                if (!include18 && (course.HoleCount == 18 || course.HoleCount >= 18)) continue;
            }

            string courseNameLower = course.Name.ToLowerInvariant();
            string courseLocLower = course.Location.ToLowerInvariant();

            bool allTokensMatch = true;
            foreach (var token in queryTokens)
            {
                if (!courseNameLower.Contains(token) && !courseLocLower.Contains(token))
                {
                    allTokensMatch = false;
                    break;
                }
            }

            if (allTokensMatch)
            {
                matches.Add(course);
            }
        }

        var sorted = matches.OrderBy(c => c.Name, StringComparer.OrdinalIgnoreCase).ToList();
        var results = new Godot.Collections.Array();
        foreach (var item in sorted)
        {
            if (!IsCourseCached(item.Name, item.Lat, item.Lon)) continue;

            var dict = new Godot.Collections.Dictionary();
            dict["name"] = item.Name;
            dict["lat"] = item.Lat;
            dict["lon"] = item.Lon;
            dict["location"] = item.Location;
            dict["hole_count"] = item.HoleCount;
            dict["last_updated"] = item.LastUpdated;
            dict["is_catalog"] = true;
            dict["is_cached"] = true;
            dict["is_pga_tour"] = item.IsPgaTour;
            results.Add(dict);
        }
        return results;
    }

    private static List<GolfSearchResult>? _bundledCatalogCache = null;
    private static readonly object _catalogLock = new();

    private static List<GolfSearchResult> LoadBundledCatalog()
    {
        lock (_catalogLock)
        {
            if (_bundledCatalogCache != null)
                return _bundledCatalogCache;

            var list = new List<GolfSearchResult>();
            string catalogResPath = "res://Courses/Catalog/golf_courses.json";

            if (Godot.FileAccess.FileExists(catalogResPath))
            {
                try
                {
                    using var fa = Godot.FileAccess.Open(catalogResPath, Godot.FileAccess.ModeFlags.Read);
                    if (fa != null)
                    {
                        string json = fa.GetAsText();
                        if (!string.IsNullOrWhiteSpace(json))
                        {
                            using var doc = JsonDocument.Parse(json);
                            if (doc.RootElement.ValueKind == JsonValueKind.Array)
                            {
                                foreach (var elem in doc.RootElement.EnumerateArray())
                                {
                                    string name = elem.TryGetProperty("name", out var np) ? np.GetString() ?? "" : "";
                                    double lat = 0;
                                    double lon = 0;

                                    if (elem.TryGetProperty("lat", out var lp))
                                    {
                                        if (lp.ValueKind == JsonValueKind.Number)
                                            lat = lp.GetDouble();
                                        else if (lp.ValueKind == JsonValueKind.String && double.TryParse(lp.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var pLat))
                                            lat = pLat;
                                    }

                                    if (elem.TryGetProperty("lon", out var lnp))
                                    {
                                        if (lnp.ValueKind == JsonValueKind.Number)
                                            lon = lnp.GetDouble();
                                        else if (lnp.ValueKind == JsonValueKind.String && double.TryParse(lnp.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var pLon))
                                            lon = pLon;
                                    }

                                    string location = elem.TryGetProperty("location", out var locp) ? locp.GetString() ?? "" : "";
                                    int holes = 18;
                                    if (elem.TryGetProperty("hole_count", out var hp))
                                    {
                                        if (hp.ValueKind == JsonValueKind.Number)
                                            holes = hp.GetInt32();
                                        else if (hp.ValueKind == JsonValueKind.String && int.TryParse(hp.GetString(), out var pHoles))
                                            holes = pHoles;
                                    }

                                    string updated = elem.TryGetProperty("last_updated", out var up) ? up.GetString() ?? "" : "";
                                    bool isPga = elem.TryGetProperty("is_pga_tour", out var pp) &&
                                        (pp.ValueKind == JsonValueKind.True || (pp.ValueKind == JsonValueKind.String && bool.TryParse(pp.GetString(), out var bp) && bp));

                                    if (!string.IsNullOrWhiteSpace(name) && (lat != 0 || lon != 0))
                                    {
                                        list.Add(new GolfSearchResult(name, lat, lon, location, holes, updated, IsCatalog: true, IsPgaTour: isPga));
                                    }
                                }
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    GD.PrintErr($"{LogPrefix} Failed to load bundled golf catalog: {ex.Message}");
                }
            }
            else
            {
                GD.Print($"{LogPrefix} Bundled catalog file not found at {catalogResPath}");
            }

            _bundledCatalogCache = list;
            GD.Print($"{LogPrefix} Loaded {_bundledCatalogCache.Count} courses into offline catalog cache.");
            return _bundledCatalogCache;
        }
    }

    private class SearchCandidate
    {
        public string Name { get; set; } = "";
        public double Lat { get; set; }
        public double Lon { get; set; }
        public string Location { get; set; } = "";
        public int HoleCount { get; set; }
        public string LastUpdated { get; set; } = "";
        public HashSet<int> HoleRefs { get; } = new();
        public HashSet<string> DistinctHoleKeys { get; } = new();
        public int BoundaryHoles { get; set; }
    }

    private static double HaversineDistanceMeters(double lat1, double lon1, double lat2, double lon2)
    {
        const double r = 6371000.0;
        double dLat = (lat2 - lat1) * Math.PI / 180.0;
        double dLon = (lon2 - lon1) * Math.PI / 180.0;
        double a = Math.Sin(dLat / 2.0) * Math.Sin(dLat / 2.0) +
                   Math.Cos(lat1 * Math.PI / 180.0) * Math.Cos(lat2 * Math.PI / 180.0) *
                   Math.Sin(dLon / 2.0) * Math.Sin(dLon / 2.0);
        double c = 2.0 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1.0 - a));
        return r * c;
    }

    private async Task<List<GolfSearchResult>> SearchGolfCoursesInternalAsync(string queryText, Godot.Collections.Dictionary? options = null)
    {
        var results = new List<GolfSearchResult>();
        if (string.IsNullOrWhiteSpace(queryText))
        {
            return results;
        }

        bool include9Hole = true;
        bool include18Hole = true;
        bool includeAllHoles = false;
        bool requireLeisureGolf = true;
        bool forceOnline = false;
        bool cachedOnly = false;
        string customTagsRaw = "";

        if (options != null)
        {
            if (options.ContainsKey("include_9_hole"))
                include9Hole = options["include_9_hole"].AsBool();
            if (options.ContainsKey("include_18_hole"))
                include18Hole = options["include_18_hole"].AsBool();
            if (options.ContainsKey("include_all_holes"))
                includeAllHoles = options["include_all_holes"].AsBool();
            if (options.ContainsKey("require_leisure_golf"))
                requireLeisureGolf = options["require_leisure_golf"].AsBool();
            if (options.ContainsKey("force_online"))
                forceOnline = options["force_online"].AsBool();
            if (options.ContainsKey("cached_only"))
                cachedOnly = options["cached_only"].AsBool();
            if (options.ContainsKey("custom_tags"))
                customTagsRaw = options["custom_tags"].AsString() ?? "";
        }

        string cleanQuery = queryText.Trim();

        // 0. Check bundled offline course catalog first (unless force_online is requested)
        if (!forceOnline)
        {
            var catalog = LoadBundledCatalog();
            if (catalog.Count > 0)
            {
                var queryTokens = cleanQuery.ToLowerInvariant()
                    .Split(new[] { ' ', ',', '-', '/', '.', '(', ')' }, StringSplitOptions.RemoveEmptyEntries);

                var catalogMatches = new List<GolfSearchResult>();
                foreach (var course in catalog)
                {
                    bool holeMatch = false;
                    if (includeAllHoles)
                    {
                        holeMatch = true;
                    }
                    else
                    {
                        if (include9Hole && (course.HoleCount == 9 || (course.HoleCount > 9 && course.HoleCount % 9 == 0))) holeMatch = true;
                        if (include18Hole && (course.HoleCount == 18 || course.HoleCount >= 18)) holeMatch = true;
                        if (course.HoleCount != 9 && course.HoleCount != 18 && includeAllHoles) holeMatch = true;
                    }
                    if (!holeMatch) continue;

                    string courseNameLower = course.Name.ToLowerInvariant();
                    string courseLocLower = course.Location.ToLowerInvariant();

                    bool allTokensMatch = true;
                    foreach (var token in queryTokens)
                    {
                        if (!courseNameLower.Contains(token) && !courseLocLower.Contains(token))
                        {
                            allTokensMatch = false;
                            break;
                        }
                    }

                    if (allTokensMatch)
                    {
                        catalogMatches.Add(course);
                    }
                }

                if (catalogMatches.Count > 0)
                {
                    catalogMatches.Sort((a, b) =>
                    {
                        bool aStarts = a.Name.StartsWith(cleanQuery, StringComparison.OrdinalIgnoreCase);
                        bool bStarts = b.Name.StartsWith(cleanQuery, StringComparison.OrdinalIgnoreCase);
                        if (aStarts && !bStarts) return -1;
                        if (!aStarts && bStarts) return 1;

                        bool aContains = a.Name.IndexOf(cleanQuery, StringComparison.OrdinalIgnoreCase) >= 0;
                        bool bContains = b.Name.IndexOf(cleanQuery, StringComparison.OrdinalIgnoreCase) >= 0;
                        if (aContains && !bContains) return -1;
                        if (!aContains && bContains) return 1;

                        return string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase);
                    });

                    GD.Print($"{LogPrefix} Found {catalogMatches.Count} course(s) in bundled offline catalog matching '{cleanQuery}'. Skipping online queries.");
                    return catalogMatches.Take(cachedOnly ? 100 : 25).ToList();
                }
            }
        }

        if (cachedOnly)
        {
            GD.Print($"{LogPrefix} Cached-only search requested for '{cleanQuery}'. Skipping online queries.");
            return new List<GolfSearchResult>();
        }

        GD.Print($"{LogPrefix} No matches in bundled catalog (or force_online={forceOnline}). Searching online OpenStreetMap for '{cleanQuery}' (Photon -> Nominatim -> Overpass)...");

        var customTagList = new List<string>();
        if (!string.IsNullOrWhiteSpace(customTagsRaw))
        {
            var rawTags = customTagsRaw.Split(new[] { ',', ';' }, StringSplitOptions.RemoveEmptyEntries);
            foreach (var rt in rawTags)
            {
                string tr = rt.Trim();
                if (!string.IsNullOrWhiteSpace(tr) && !customTagList.Contains(tr, StringComparer.OrdinalIgnoreCase))
                {
                    customTagList.Add(tr);
                }
            }
        }

        var rawCandidates = new List<SearchCandidate>();

        // 1. Primary Search: Query Photon API
        try
        {
            var photonTags = new List<string>();
            if (requireLeisureGolf)
            {
                photonTags.Add("leisure:golf_course");
            }
            foreach (var ct in customTagList)
            {
                string pt = ct.Replace('=', ':');
                if (!photonTags.Contains(pt, StringComparer.OrdinalIgnoreCase))
                {
                    photonTags.Add(pt);
                }
            }

            var urlBuilder = new StringBuilder($"https://photon.komoot.io/api/?q={Uri.EscapeDataString(cleanQuery)}");
            foreach (var pt in photonTags)
            {
                urlBuilder.Append($"&osm_tag={Uri.EscapeDataString(pt)}");
            }
            urlBuilder.Append("&limit=15");
            string photonUrl = urlBuilder.ToString();

            GD.Print($"{LogPrefix} Searching Photon for '{cleanQuery}' with url: {photonUrl}...");
            var photonResp = await HttpClient.GetAsync(photonUrl);
            if (photonResp.IsSuccessStatusCode)
            {
                string photonJson = await photonResp.Content.ReadAsStringAsync();
                using var doc = JsonDocument.Parse(photonJson);
                if (doc.RootElement.TryGetProperty("features", out var featuresProp) && featuresProp.ValueKind == JsonValueKind.Array)
                {
                    foreach (var feat in featuresProp.EnumerateArray())
                    {
                        if (!feat.TryGetProperty("properties", out var props) || !feat.TryGetProperty("geometry", out var geom))
                            continue;

                        string name = props.TryGetProperty("name", out var np) ? np.GetString() ?? "" : "";
                        if (string.IsNullOrWhiteSpace(name))
                            continue;

                        double lon = 0, lat = 0;
                        if (geom.TryGetProperty("coordinates", out var coordsProp) && coordsProp.ValueKind == JsonValueKind.Array)
                        {
                            var coords = coordsProp.EnumerateArray().ToArray();
                            if (coords.Length >= 2)
                            {
                                lon = coords[0].GetDouble();
                                lat = coords[1].GetDouble();
                            }
                        }
                        if (lat == 0 && lon == 0) continue;

                        var locParts = new List<string>();
                        foreach (var key in new[] { "city", "district", "county", "state", "country" })
                        {
                            if (props.TryGetProperty(key, out var kp))
                            {
                                string val = kp.GetString() ?? "";
                                if (!string.IsNullOrWhiteSpace(val) && !locParts.Contains(val))
                                    locParts.Add(val);
                            }
                        }
                        string location = string.Join(", ", locParts);
                        rawCandidates.Add(new SearchCandidate { Name = name, Lat = lat, Lon = lon, Location = location });
                    }
                }
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Photon search exception: {ex.Message}");
        }

        // 2. Fallback to Nominatim if Photon returned no results
        if (rawCandidates.Count == 0)
        {
            GD.Print($"{LogPrefix} Photon yielded no results; falling back to Nominatim for '{cleanQuery}'...");
            try
            {
                // Try clean query first
                string nomUrl = $"https://nominatim.openstreetmap.org/search?q={Uri.EscapeDataString(cleanQuery)}&format=json&limit=15";
                var nomResp = await HttpClient.GetAsync(nomUrl);
                string nomJson = (nomResp.IsSuccessStatusCode) ? await nomResp.Content.ReadAsStringAsync() : "";

                // If empty and didn't have "golf", retry with " golf" if leisure_golf is enabled
                if ((string.IsNullOrWhiteSpace(nomJson) || nomJson == "[]") && requireLeisureGolf && !cleanQuery.Contains("golf", StringComparison.OrdinalIgnoreCase))
                {
                    string nomRetryUrl = $"https://nominatim.openstreetmap.org/search?q={Uri.EscapeDataString(cleanQuery + " golf")}&format=json&limit=15";
                    nomResp = await HttpClient.GetAsync(nomRetryUrl);
                    if (nomResp.IsSuccessStatusCode)
                    {
                        nomJson = await nomResp.Content.ReadAsStringAsync();
                    }
                }

                // If still empty and cleanQuery has "valley", retry with "vallee", and vice-versa
                if ((string.IsNullOrWhiteSpace(nomJson) || nomJson == "[]") && cleanQuery.Contains("valley", StringComparison.OrdinalIgnoreCase))
                {
                    string altQuery = System.Text.RegularExpressions.Regex.Replace(cleanQuery, "(?i)valley", "vallee");
                    string nomRetryUrl = $"https://nominatim.openstreetmap.org/search?q={Uri.EscapeDataString(altQuery)}&format=json&limit=15";
                    nomResp = await HttpClient.GetAsync(nomRetryUrl);
                    if (nomResp.IsSuccessStatusCode)
                    {
                        nomJson = await nomResp.Content.ReadAsStringAsync();
                    }
                }
                else if ((string.IsNullOrWhiteSpace(nomJson) || nomJson == "[]") && cleanQuery.Contains("vallee", StringComparison.OrdinalIgnoreCase))
                {
                    string altQuery = System.Text.RegularExpressions.Regex.Replace(cleanQuery, "(?i)vallee", "valley");
                    string nomRetryUrl = $"https://nominatim.openstreetmap.org/search?q={Uri.EscapeDataString(altQuery)}&format=json&limit=15";
                    nomResp = await HttpClient.GetAsync(nomRetryUrl);
                    if (nomResp.IsSuccessStatusCode)
                    {
                        nomJson = await nomResp.Content.ReadAsStringAsync();
                    }
                }

                if (!string.IsNullOrWhiteSpace(nomJson) && nomJson != "[]")
                {
                    using var doc = JsonDocument.Parse(nomJson);
                    if (doc.RootElement.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var element in doc.RootElement.EnumerateArray())
                        {
                            string name = "";
                            if (element.TryGetProperty("name", out var nameProp))
                                name = nameProp.GetString() ?? "";
                            if (string.IsNullOrEmpty(name) && element.TryGetProperty("display_name", out var dispProp))
                                name = (dispProp.GetString() ?? "").Split(',')[0].Trim();

                            if (string.IsNullOrEmpty(name)) continue;

                            double lat = 0, lon = 0;
                            if (element.TryGetProperty("lat", out var latProp) && double.TryParse(latProp.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var parsedLat))
                                lat = parsedLat;
                            if (element.TryGetProperty("lon", out var lonProp) && double.TryParse(lonProp.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var parsedLon))
                                lon = parsedLon;

                            if (lat == 0 && lon == 0) continue;

                            string location = "";
                            if (element.TryGetProperty("display_name", out var dispNameProp))
                            {
                                var parts = (dispNameProp.GetString() ?? "").Split(',');
                                if (parts.Length > 1)
                                {
                                    var locParts = new List<string>();
                                    for (int i = 1; i < Math.Min(parts.Length, 5); i++)
                                        locParts.Add(parts[i].Trim());
                                    location = string.Join(", ", locParts);
                                }
                            }
                            rawCandidates.Add(new SearchCandidate { Name = name, Lat = lat, Lon = lon, Location = location });
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                GD.PrintErr($"{LogPrefix} Nominatim fallback search exception: {ex.Message}");
            }
        }

        if (rawCandidates.Count == 0)
        {
            GD.Print($"{LogPrefix} No candidate golf courses found for '{cleanQuery}'.");
            return results;
        }

        // 3. Deduplicate candidates by name and proximity (< 300 meters)
        var deduped = new List<SearchCandidate>();
        foreach (var cand in rawCandidates)
        {
            bool isDuplicate = deduped.Any(d =>
                HaversineDistanceMeters(d.Lat, d.Lon, cand.Lat, cand.Lon) < 300.0 &&
                string.Equals(d.Name, cand.Name, StringComparison.OrdinalIgnoreCase));
            if (!isDuplicate)
            {
                deduped.Add(cand);
            }
        }

        // Limit verification batch to top 8 candidates to guarantee snappy response times
        var candidatesToVerify = deduped.Take(8).ToList();
        GD.Print($"{LogPrefix} Verifying hole counts and timestamps for {candidatesToVerify.Count} candidate courses via Overpass...");

        // 4. Batch query Overpass for hole definitions and course metadata
        var sb = new StringBuilder();
        sb.AppendLine("[out:json][timeout:25];");
        sb.AppendLine("(");
        foreach (var c in candidatesToVerify)
        {
            sb.AppendLine(CultureInfo.InvariantCulture, $"  nwr(around:1500, {c.Lat}, {c.Lon})[\"golf\"=\"hole\"];");
            if (requireLeisureGolf)
            {
                sb.AppendLine(CultureInfo.InvariantCulture, $"  nwr(around:1500, {c.Lat}, {c.Lon})[\"leisure\"=\"golf_course\"];");
            }
            foreach (var ct in customTagList)
            {
                int sep = ct.IndexOfAny(new[] { '=', ':' });
                if (sep > 0)
                {
                    string k = ct.Substring(0, sep).Trim();
                    string v = ct.Substring(sep + 1).Trim();
                    sb.AppendLine(CultureInfo.InvariantCulture, $"  nwr(around:1500, {c.Lat}, {c.Lon})[\"{k}\"=\"{v}\"];");
                }
                else
                {
                    sb.AppendLine(CultureInfo.InvariantCulture, $"  nwr(around:1500, {c.Lat}, {c.Lon})[\"{ct.Trim()}\"];");
                }
            }
        }
        sb.AppendLine(");");
        sb.AppendLine("out center tags meta;");
        string overpassQuery = sb.ToString();

        string overpassJson = "";
        for (int attempt = 1; attempt <= OverpassEndpoints.Length; attempt++)
        {
            string endpoint = OverpassEndpoints[(attempt - 1) % OverpassEndpoints.Length];
            try
            {
                using var cts = new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(12));
                var content = new FormUrlEncodedContent(new[] { new KeyValuePair<string, string>("data", overpassQuery) });
                var response = await HttpClient.PostAsync(endpoint, content, cts.Token);
                if (response.IsSuccessStatusCode)
                {
                    overpassJson = await response.Content.ReadAsStringAsync();
                    if (!string.IsNullOrWhiteSpace(overpassJson))
                        break;
                }
            }
            catch (Exception ex)
            {
                GD.PrintErr($"{LogPrefix} Overpass verification attempt {attempt} failed on {endpoint}: {ex.Message}{(ex.InnerException != null ? $" (Inner: {ex.InnerException.Message})" : "")}");
            }
        }

        // 5. Parse Overpass elements to inspect holes and latest updated timestamps
        if (!string.IsNullOrWhiteSpace(overpassJson))
        {
            try
            {
                using var doc = JsonDocument.Parse(overpassJson);
                if (doc.RootElement.TryGetProperty("elements", out var elementsProp) && elementsProp.ValueKind == JsonValueKind.Array)
                {
                    foreach (var el in elementsProp.EnumerateArray())
                    {
                        double elLat = 0, elLon = 0;
                        if (el.TryGetProperty("lat", out var latProp))
                            elLat = latProp.GetDouble();
                        else if (el.TryGetProperty("center", out var centerProp) && centerProp.TryGetProperty("lat", out var cLat))
                            elLat = cLat.GetDouble();

                        if (el.TryGetProperty("lon", out var lonProp))
                            elLon = lonProp.GetDouble();
                        else if (el.TryGetProperty("center", out var centerProp2) && centerProp2.TryGetProperty("lon", out var cLon))
                            elLon = cLon.GetDouble();

                        if (elLat == 0 && elLon == 0) continue;

                        string ts = el.TryGetProperty("timestamp", out var tsProp) ? tsProp.GetString() ?? "" : "";

                        if (!el.TryGetProperty("tags", out var tagsProp) || tagsProp.ValueKind != JsonValueKind.Object)
                            continue;

                        string golfVal = tagsProp.TryGetProperty("golf", out var gProp) ? gProp.GetString() ?? "" : "";
                        string leisureVal = tagsProp.TryGetProperty("leisure", out var lProp) ? lProp.GetString() ?? "" : "";

                        foreach (var c in candidatesToVerify)
                        {
                            double dist = HaversineDistanceMeters(c.Lat, c.Lon, elLat, elLon);
                            if (dist > 1500.0) continue;

                            if (!string.IsNullOrEmpty(ts) && string.Compare(ts, c.LastUpdated, StringComparison.Ordinal) > 0)
                            {
                                c.LastUpdated = ts;
                            }

                            if (golfVal == "hole")
                            {
                                string subCourse = "";
                                if (tagsProp.TryGetProperty("golf:course:name", out var gcnProp))
                                    subCourse = gcnProp.GetString() ?? "";
                                else if (tagsProp.TryGetProperty("course:name", out var cnProp))
                                    subCourse = cnProp.GetString() ?? "";
                                else if (tagsProp.TryGetProperty("golf:course", out var gcProp2))
                                    subCourse = gcProp2.GetString() ?? "";
                                else if (tagsProp.TryGetProperty("course", out var cProp))
                                    subCourse = cProp.GetString() ?? "";

                                string refStr = "";
                                if (tagsProp.TryGetProperty("ref", out var refProp))
                                {
                                    refStr = refProp.GetString() ?? "";
                                    if (int.TryParse(refStr, out int hNum) && hNum >= 1 && hNum <= 36)
                                    {
                                        c.HoleRefs.Add(hNum);
                                    }
                                }
                                else if (tagsProp.TryGetProperty("name", out var nProp))
                                {
                                    string nStr = nProp.GetString() ?? "";
                                    var match = System.Text.RegularExpressions.Regex.Match(nStr, @"\b([1-9]|[1-2][0-9]|3[0-6])\b");
                                    if (match.Success && int.TryParse(match.Groups[1].Value, out int hNum))
                                    {
                                        refStr = match.Groups[1].Value;
                                        c.HoleRefs.Add(hNum);
                                    }
                                }

                                if (!string.IsNullOrWhiteSpace(refStr))
                                {
                                    string dKey = !string.IsNullOrWhiteSpace(subCourse)
                                        ? $"{subCourse.Trim().ToLowerInvariant()}:{refStr.Trim()}"
                                        : refStr.Trim();
                                    c.DistinctHoleKeys.Add(dKey);
                                }
                            }

                            if (leisureVal == "golf_course" || !requireLeisureGolf || customTagList.Count > 0)
                            {
                                if (tagsProp.TryGetProperty("golf:holes", out var ghProp) && int.TryParse(ghProp.GetString(), out int gh))
                                    c.BoundaryHoles = gh;
                                else if (tagsProp.TryGetProperty("holes", out var hProp) && int.TryParse(hProp.GetString(), out int h))
                                    c.BoundaryHoles = h;
                                else if (tagsProp.TryGetProperty("golf:course", out var gcProp))
                                {
                                    string gcStr = gcProp.GetString() ?? "";
                                    if (gcStr == "18_hole") c.BoundaryHoles = 18;
                                    else if (gcStr == "9_hole") c.BoundaryHoles = 9;
                                }
                                else if (tagsProp.TryGetProperty("description", out var descProp))
                                {
                                    string desc = descProp.GetString() ?? "";
                                    if (desc.Contains("18 hole", StringComparison.OrdinalIgnoreCase) || desc.Contains("18-hole", StringComparison.OrdinalIgnoreCase))
                                        c.BoundaryHoles = 18;
                                    else if (desc.Contains("9 hole", StringComparison.OrdinalIgnoreCase) || desc.Contains("9-hole", StringComparison.OrdinalIgnoreCase))
                                        c.BoundaryHoles = 9;
                                }
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                GD.PrintErr($"{LogPrefix} Error parsing Overpass verification JSON: {ex.Message}");
            }
        }

        // 6. Filter results by hole count settings
        var validCandidates = new List<SearchCandidate>();
        foreach (var c in candidatesToVerify)
        {
            int holes = c.DistinctHoleKeys.Count > 0 ? c.DistinctHoleKeys.Count : (c.HoleRefs.Count > 0 ? c.HoleRefs.Count : c.BoundaryHoles);
            c.HoleCount = holes;

            bool matches = false;
            if (includeAllHoles)
            {
                matches = true;
            }
            else
            {
                if (include9Hole && (holes == 9 || (holes > 9 && holes % 9 == 0))) matches = true;
                if (include18Hole && (holes == 18 || holes >= 18)) matches = true;
            }

            if (matches)
            {
                validCandidates.Add(c);
            }
            else
            {
                GD.Print($"{LogPrefix} Filtering out '{c.Name}' (holes detected: {holes}, options: 9={include9Hole}, 18={include18Hole}, all={includeAllHoles}).");
            }
        }

        // 7. Order results by most recently updated course first
        validCandidates.Sort((a, b) => string.Compare(b.LastUpdated, a.LastUpdated, StringComparison.Ordinal));

        // If Overpass was completely unreachable, fallback gracefully to returning candidates
        if (validCandidates.Count == 0 && string.IsNullOrWhiteSpace(overpassJson))
        {
            GD.Print($"{LogPrefix} Overpass verification was unreachable; returning unverified candidates as fallback.");
            foreach (var c in candidatesToVerify)
            {
                results.Add(new GolfSearchResult(c.Name, c.Lat, c.Lon, c.Location, c.BoundaryHoles, c.LastUpdated));
            }
            return results;
        }

        foreach (var c in validCandidates)
        {
            results.Add(new GolfSearchResult(c.Name, c.Lat, c.Lon, c.Location, c.HoleCount, c.LastUpdated));
        }

        GD.Print($"{LogPrefix} Returning {results.Count} qualified course(s) (ordered by latest update).");
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
                    taperFactor = QuinticSmoothstep(t);
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
            
            shaderMat.SetShaderParameter("shallow_color", new Color(0.12f, 0.23f, 0.18f));
            shaderMat.SetShaderParameter("deep_color", new Color(0.03f, 0.09f, 0.11f));
            shaderMat.SetShaderParameter("absorbance", 2.6f);
            shaderMat.SetShaderParameter("depth_fade_distance", 1.2f);
            shaderMat.SetShaderParameter("roughness", 0.04f);
            shaderMat.SetShaderParameter("foam_amount", 0.12f);
            shaderMat.SetShaderParameter("foam_color", new Color(0.68f, 0.74f, 0.70f));
            
            EnsureWaterNoiseTextures();
            shaderMat.SetShaderParameter("wave_texture", _cachedWaterWaveNoiseTex!);
            shaderMat.SetShaderParameter("normal1", _cachedWaterNormalTex1!);
            shaderMat.SetShaderParameter("normal2", _cachedWaterNormalTex2!);
            shaderMat.SetShaderParameter("wave_speed", 0.015f);
            shaderMat.SetShaderParameter("wave_scale", 12.0f);
            shaderMat.SetShaderParameter("height_scale", 0.025f);
            
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

            float usgsMin = float.MaxValue;
            float usgsMax = float.MinValue;
            for (int i = 0; i < elevationData.Length; i += step)
            {
                if (elevationData[i] >= -9000f && !float.IsNaN(elevationData[i]) && elevationData[i] <= 10000f)
                {
                    if (elevationData[i] < usgsMin) usgsMin = elevationData[i];
                    if (elevationData[i] > usgsMax) usgsMax = elevationData[i];
                }
            }

            if (usgsMax - usgsMin < 0.5f)
            {
                GD.Print($"{LogPrefix} USGS returned completely flat/zero values (range: {usgsMax - usgsMin:F2}m, outside US coverage). Falling back.");
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

    private async Task<float[]?> DownloadOpenMeteoElevationAsync(BBox bbox, double leftLon, double rightLon, double topLat, double bottomLat, int widthPixels, int heightPixels)
    {
        GD.Print($"{LogPrefix} Attempting to fetch global Open-Meteo elevation data...");
        try
        {
            // Sample a 24x24 grid across bounding box (576 coordinates total, queried in chunks of 96)
            int sampleCountX = 24;
            int sampleCountY = 24;
            int totalSamples = sampleCountX * sampleCountY;
            float[] sampleHeights = new float[totalSamples];

            var coords = new List<(double lat, double lon, int index)>(totalSamples);
            for (int gy = 0; gy < sampleCountY; gy++)
            {
                double lat = topLat - (gy / (double)(sampleCountY - 1)) * (topLat - bottomLat);
                for (int gx = 0; gx < sampleCountX; gx++)
                {
                    double lon = leftLon + (gx / (double)(sampleCountX - 1)) * (rightLon - leftLon);
                    coords.Add((lat, lon, gy * sampleCountX + gx));
                }
            }

            int chunkSize = 96; // Open-Meteo max is 100 per request
            for (int i = 0; i < coords.Count; i += chunkSize)
            {
                var chunk = coords.Skip(i).Take(chunkSize).ToList();
                string latStr = string.Join(",", chunk.Select(c => c.lat.ToString("F6", System.Globalization.CultureInfo.InvariantCulture)));
                string lonStr = string.Join(",", chunk.Select(c => c.lon.ToString("F6", System.Globalization.CultureInfo.InvariantCulture)));

                string url = $"https://api.open-meteo.com/v1/elevation?latitude={latStr}&longitude={lonStr}";
                using var cts = new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(10));
                using var request = new HttpRequestMessage(HttpMethod.Get, url);
                request.Headers.TryAddWithoutValidation("User-Agent", "HeckleGolfSimulator/1.0");
                var response = await HttpClient.SendAsync(request, cts.Token);
                if (!response.IsSuccessStatusCode)
                {
                    GD.PrintErr($"{LogPrefix} Open-Meteo request failed with status: {response.StatusCode}");
                    return null;
                }

                string jsonStr = await response.Content.ReadAsStringAsync();
                using var doc = System.Text.Json.JsonDocument.Parse(jsonStr);
                if (!doc.RootElement.TryGetProperty("elevation", out var elevArray))
                {
                    GD.PrintErr($"{LogPrefix} Open-Meteo response did not contain 'elevation' array.");
                    return null;
                }

                int elemIdx = 0;
                foreach (var el in elevArray.EnumerateArray())
                {
                    if (elemIdx < chunk.Count)
                    {
                        sampleHeights[chunk[elemIdx].index] = el.GetSingle();
                        elemIdx++;
                    }
                }
            }

            // Validate the sample heights
            float minH = float.MaxValue;
            float maxH = float.MinValue;
            for (int i = 0; i < sampleHeights.Length; i++)
            {
                if (float.IsNaN(sampleHeights[i]) || sampleHeights[i] < -500f || sampleHeights[i] > 9000f)
                    return null;
                if (sampleHeights[i] < minH) minH = sampleHeights[i];
                if (sampleHeights[i] > maxH) maxH = sampleHeights[i];
            }

            GD.Print($"{LogPrefix} Successfully fetched Open-Meteo elevation (range: {minH:F1}m to {maxH:F1}m).");

            // Bicubic Catmull-Rom interpolate sample heights to widthPixels x heightPixels for seamless slope continuity
            float[] elevationData = new float[widthPixels * heightPixels];
            for (int destY = 0; destY < heightPixels; destY++)
            {
                float v = destY / (float)(heightPixels - 1) * (sampleCountY - 1);
                for (int destX = 0; destX < widthPixels; destX++)
                {
                    float u = destX / (float)(widthPixels - 1) * (sampleCountX - 1);
                    elevationData[destY * widthPixels + destX] = BicubicSample(sampleHeights, sampleCountX, sampleCountY, u, v);
                }
            }

            return elevationData;
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Exception fetching Open-Meteo elevation: {ex.Message}");
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
            elevationData = await DownloadOpenMeteoElevationAsync(bbox, leftLon, rightLon, topLat, bottomLat, widthPixels, heightPixels);
        }

        if (elevationData == null)
        {
            GD.Print($"{LogPrefix} USGS 3DEP and Open-Meteo not available or failed. Falling back to S3 Terrain Tiles.");
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

        // Validate elevationData across the board: if flat or invalid, synthesize procedural golf course topography
        float minVal = float.MaxValue;
        float maxVal = float.MinValue;
        for (int i = 0; i < elevationData.Length; i++)
        {
            if (elevationData[i] < minVal) minVal = elevationData[i];
            if (elevationData[i] > maxVal) maxVal = elevationData[i];
        }

        if (maxVal - minVal < 0.5f)
        {
            GD.Print($"{LogPrefix} Downloaded elevation data is flat (range: {maxVal - minVal:F2}m). Generating procedural golf course elevation.");
            for (int destY = 0; destY < heightPixels; destY++)
            {
                double lat = topLat - (destY / (double)(heightPixels - 1)) * (topLat - bottomLat);
                float zCoord = (float)(-(lat - bbox.RefLat) * bbox.MetersPerLat);
                for (int destX = 0; destX < widthPixels; destX++)
                {
                    double lon = leftLon + (destX / (double)(widthPixels - 1)) * (rightLon - leftLon);
                    float xCoord = (float)((lon - bbox.RefLon) * bbox.MetersPerLon);
                    elevationData[destY * widthPixels + destX] = OsmMapLoader.GetProceduralHeight(xCoord, zCoord);
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

    [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.AggressiveInlining)]
    private static float CatmullRom1D(float p0, float p1, float p2, float p3, float t)
    {
        // Standard Catmull-Rom cubic spline ensuring continuous C1 derivatives across grid cells
        float a0 = -0.5f * p0 + 1.5f * p1 - 1.5f * p2 + 0.5f * p3;
        float a1 = p0 - 2.5f * p1 + 2.0f * p2 - 0.5f * p3;
        float a2 = -0.5f * p0 + 0.5f * p2;
        float a3 = p1;
        return ((a0 * t + a1) * t + a2) * t + a3;
    }

    private static float BicubicSample(float[] data, int w, int h, float sampleX, float sampleY)
    {
        int x1 = Math.Clamp((int)Math.Floor(sampleX), 0, w - 1);
        int y1 = Math.Clamp((int)Math.Floor(sampleY), 0, h - 1);
        int x0 = Math.Clamp(x1 - 1, 0, w - 1);
        int x2 = Math.Clamp(x1 + 1, 0, w - 1);
        int x3 = Math.Clamp(x1 + 2, 0, w - 1);
        int y0 = Math.Clamp(y1 - 1, 0, h - 1);
        int y2 = Math.Clamp(y1 + 1, 0, h - 1);
        int y3 = Math.Clamp(y1 + 2, 0, h - 1);

        float tx = sampleX - x1;
        float ty = sampleY - y1;

        // Evaluate 4 horizontal lines with Catmull-Rom cubic spline
        float r0 = CatmullRom1D(data[y0 * w + x0], data[y0 * w + x1], data[y0 * w + x2], data[y0 * w + x3], tx);
        float r1 = CatmullRom1D(data[y1 * w + x0], data[y1 * w + x1], data[y1 * w + x2], data[y1 * w + x3], tx);
        float r2 = CatmullRom1D(data[y2 * w + x0], data[y2 * w + x1], data[y2 * w + x2], data[y2 * w + x3], tx);
        float r3 = CatmullRom1D(data[y3 * w + x0], data[y3 * w + x1], data[y3 * w + x2], data[y3 * w + x3], tx);

        // Interpolate vertically across the 4 rows
        return CatmullRom1D(r0, r1, r2, r3, ty);
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

        return BicubicSample(_currentElevationMap.Data, w, h, sampleX, sampleY);
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

        return BicubicSample(data, w, h, sampleX, sampleY);
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

    public static float GetProceduralHeight(float x, float z)
    {
        // Gradual, natural golf course topography with broad wavelengths (800m - 1500m)
        // producing gentle ~1% grades with at most 1 gradual rise or fall across an entire hole.
        double h = Math.Sin(x * 0.0042 + z * 0.0031) * Math.Cos(z * 0.0051 - x * 0.0036) * 1.2
                 + Math.Sin(x * 0.0078 - z * 0.0062) * 0.5;
        return (float)h;
    }

    private float GetHeight(float x, float z)
    {
        if (_currentElevationMap != null)
        {
            double lon = _refLon + x / _metersPerLon;
            double lat = _refLat - z / _metersPerLat;
            return SampleRawHeight(lat, lon) - _currentElevationMap.Offset;
        }

        return GetProceduralHeight(x, z);
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
                        float smoothT = QuinticSmoothstep(t);
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
                    float dist = DistanceToPolygon(vertexPoint, exclusions.First(e => e.GolfType == "bunker" && Geometry2D.IsPointInPolygon(vertexPoint, e.Polygon)).Polygon);
                    float bowlRadius = 7.0f;
                    float maxDepth = 1.0f;
                    if (dist < bowlRadius)
                    {
                        float t = dist / bowlRadius;
                        depBunker = QuinticSmoothstep(t) * maxDepth;
                    }
                    else
                    {
                        depBunker = maxDepth;
                    }
                }
                else if (minDistBunker < 4.0f)
                {
                    float t = 1.0f - (minDistBunker / 4.0f);
                    depBunker = -QuinticSmoothstep(t) * 0.12f; // gentle raised lip
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

    private static readonly string[] StandardTreePaths = new string[]
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

    private static readonly string[] WillowTreePaths = new string[]
    {
        "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-willow-1-staticbody.tscn",
        "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-willow-2-staticbody.tscn",
        "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-willow-3-staticbody.tscn"
    };

    private static readonly string[] BirchTreePaths = new string[]
    {
        "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-birch-1-staticbody.tscn",
        "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-birch-2-staticbody.tscn"
    };

    private static readonly string[] PineTreePaths = new string[]
    {
        "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-pine-1-staticbody.tscn",
        "res://addons/shapespark-low-poly-exterior-plants/bodies/tree-pine-2-staticbody.tscn"
    };

    private static readonly string[] TreePaths = StandardTreePaths;

    private static readonly string[] BushPaths = new string[]
    {
        "res://addons/shapespark-low-poly-exterior-plants/bodies/bush-01-staticbody.tscn",
        "res://addons/shapespark-low-poly-exterior-plants/bodies/bush-02-staticbody.tscn",
        "res://addons/shapespark-low-poly-exterior-plants/bodies/bush-03-staticbody.tscn",
        "res://addons/shapespark-low-poly-exterior-plants/bodies/bush-04-staticbody.tscn",
        "res://addons/shapespark-low-poly-exterior-plants/bodies/bush-05-staticbody.tscn"
    };

    private List<PackedScene>? _cachedStandardTreeScenes;
    private List<PackedScene>? _cachedWillowTreeScenes;
    private List<PackedScene>? _cachedBirchTreeScenes;
    private List<PackedScene>? _cachedPineTreeScenes;
    private const bool BushesEnabled = false;
    private List<PackedScene>? _cachedBushScenes;

    private static List<PackedScene> LoadSceneList(string[] paths)
    {
        var list = new List<PackedScene>();
        foreach (var path in paths)
        {
            if (ResourceLoader.Exists(path))
            {
                var s = GD.Load<PackedScene>(path);
                if (s != null) list.Add(s);
            }
        }
        return list;
    }

    private void EnsurePlantScenesLoaded()
    {
        if (_cachedStandardTreeScenes == null)
            _cachedStandardTreeScenes = LoadSceneList(StandardTreePaths);
        if (_cachedWillowTreeScenes == null)
            _cachedWillowTreeScenes = LoadSceneList(WillowTreePaths);
        if (_cachedBirchTreeScenes == null)
            _cachedBirchTreeScenes = LoadSceneList(BirchTreePaths);
        if (_cachedPineTreeScenes == null)
            _cachedPineTreeScenes = LoadSceneList(PineTreePaths);
        if (_cachedBushScenes == null)
            _cachedBushScenes = LoadSceneList(BushPaths);
    }

    private void AddTreeAt(Node3D root, Vector3 position, bool isWillow = false)
    {
        EnsurePlantScenesLoaded();
        if (_cachedStandardTreeScenes == null || _cachedStandardTreeScenes.Count == 0) return;

        // Seed Random deterministically using position hash so same tree always has same type and size
        int posHash = (int)(position.X * 1000f) ^ (int)(position.Z * 1000f);
        var random = new Random(posHash);

        PackedScene selectedScene;
        double roll = random.NextDouble();
        bool isPine = false;
        bool isBirch = false;

        if (isWillow && _cachedWillowTreeScenes != null && _cachedWillowTreeScenes.Count > 0)
        {
            selectedScene = _cachedWillowTreeScenes[random.Next(_cachedWillowTreeScenes.Count)];
        }
        else
        {
            isWillow = false;
            // Standard golf course mix: lush oaks (72%), pines (16%), birches (12%)
            // Weeping willows are NEVER spawned here (only at designated water feature spots)
            if (roll < 0.72)
            {
                selectedScene = _cachedStandardTreeScenes[random.Next(_cachedStandardTreeScenes.Count)];
            }
            else if (roll < 0.88 && _cachedPineTreeScenes != null && _cachedPineTreeScenes.Count > 0)
            {
                selectedScene = _cachedPineTreeScenes[random.Next(_cachedPineTreeScenes.Count)];
                isPine = true;
            }
            else if (_cachedBirchTreeScenes != null && _cachedBirchTreeScenes.Count > 0)
            {
                selectedScene = _cachedBirchTreeScenes[random.Next(_cachedBirchTreeScenes.Count)];
                isBirch = true;
            }
            else
            {
                selectedScene = _cachedStandardTreeScenes[random.Next(_cachedStandardTreeScenes.Count)];
            }
        }

        try
        {
            var treeInstance = selectedScene.Instantiate<Node3D>();
            treeInstance.Name = $"Tree_{position.X:F1}_{position.Z:F1}";
            // Slightly sink tree base into ground to bed roots naturally on sloped terrain
            treeInstance.Position = new Vector3(position.X, position.Y - 0.15f, position.Z);

            // Standard tree scaling: halfway between earlier sizes (1.95 to 3.65)
            float scaleVal = 1.95f + (float)random.NextDouble() * 1.70f; // 1.95 to 3.65
            if (isWillow)
            {
                // Weeping willows: mature, balanced scale (~14m - 18m tall/wide) so they feel grand without being overwhelmingly oversized
                float willowScale = 2.0f + (float)random.NextDouble() * 0.6f; // 2.0 to 2.6
                treeInstance.Scale = new Vector3(willowScale, willowScale, willowScale);
            }
            else if (isPine)
            {
                // Pines: conical, taller upright silhouette
                treeInstance.Scale = new Vector3(scaleVal * 0.86f, scaleVal * 1.25f, scaleVal * 0.86f);
            }
            else if (isBirch)
            {
                // Birches: slender, elegant trunk
                treeInstance.Scale = new Vector3(scaleVal * 0.90f, scaleVal * 1.15f, scaleVal * 0.90f);
            }
            else
            {
                treeInstance.Scale = new Vector3(scaleVal, scaleVal, scaleVal);
            }

            // Apply a random Y rotation for organic variety
            float rotationY = (float)(random.NextDouble() * Math.PI * 2.0);
            treeInstance.Rotation = new Vector3(0f, rotationY, 0f);

            root.AddChild(treeInstance);
            treeInstance.Owner = root;
            treeInstance.SetMeta("is_tree", true);
            treeInstance.AddToGroup("trees");
            if (treeInstance is CollisionObject3D colObj)
            {
                colObj.SetMeta("is_tree", true);
            }

            // Ensure leaves/canopy Area3D is present to detect ball passing through
            var existingCanopy = treeInstance.GetNodeOrNull<Area3D>("CanopyArea");
            if (existingCanopy != null)
            {
                existingCanopy.Owner = root;
                foreach (Node canopyChild in existingCanopy.GetChildren())
                {
                    canopyChild.Owner = root;
                }
            }
            else
            {
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
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Exception instantiating tree scene: {ex}");
        }
    }

    private void AddBushAt(Node3D root, Vector3 position)
    {
        EnsurePlantScenesLoaded();
        // Low-poly spiky bush meshes looked like floating grass blades; skipped entirely.
        if (!BushesEnabled || _cachedBushScenes == null || _cachedBushScenes.Count == 0) return;

        int posHash = (int)(position.X * 1000f) ^ (int)(position.Z * 1000f);
        var random = new Random(posHash);
        int bushIndex = random.Next(_cachedBushScenes.Count);
        
        try
        {
            var bushScene = _cachedBushScenes[bushIndex];
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
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Exception instantiating bush scene: {ex}");
        }
    }

    public string ExtractSubCourseName(Godot.Collections.Dictionary tags)
    {
        if (tags == null) return "";
        var sysDict = new Dictionary<string, string>();
        foreach (var key in tags.Keys)
        {
            sysDict[key.AsString()] = tags[key].AsString();
        }
        return ExtractSubCourseName(sysDict);
    }

    public static string ExtractSubCourseName(Dictionary<string, string> tags)
    {
        if (tags == null) return "";
        if (tags.TryGetValue("golf:course:name", out var gcn) && !string.IsNullOrWhiteSpace(gcn))
            return gcn.Trim();
        if (tags.TryGetValue("course:name", out var cn) && !string.IsNullOrWhiteSpace(cn))
            return cn.Trim();
        if (tags.TryGetValue("golf:course", out var gc) && !string.IsNullOrWhiteSpace(gc) && gc != "18_hole" && gc != "9_hole")
            return gc.Trim();
        if (tags.TryGetValue("course", out var c) && !string.IsNullOrWhiteSpace(c))
            return c.Trim();
        return "";
    }

    private static string GetHoleKey(string refVal)
    {
        if (int.TryParse(refVal, out var holeInt))
        {
            return $"Hole {holeInt:D2}";
        }
        return $"Hole {refVal}";
    }

    public static List<string> ParseHoleRefs(string refVal)
    {
        var list = new List<string>();
        if (string.IsNullOrWhiteSpace(refVal)) return list;
        var parts = refVal.Split(new[] { ';', ',', '/' }, StringSplitOptions.RemoveEmptyEntries);
        foreach (var part in parts)
        {
            var cleaned = part.Trim();
            cleaned = System.Text.RegularExpressions.Regex.Replace(cleaned, @"(?i)^hole\s*", "");
            cleaned = cleaned.TrimStart('#').Trim();
            if (!string.IsNullOrWhiteSpace(cleaned))
            {
                list.Add(cleaned);
            }
        }
        return list;
    }

    public static List<string> ParseTeeColors(Dictionary<string, string> tags, string? role = null)
    {
        var colors = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // 1. Check "tee" tag (e.g. "blue;white", "gold", "red")
        if (tags.TryGetValue("tee", out var teeVal) && !string.IsNullOrWhiteSpace(teeVal))
        {
            foreach (var part in teeVal.Split(new[] { ';', ',', '/' }, StringSplitOptions.RemoveEmptyEntries))
            {
                var trimmed = part.Trim();
                if (!string.IsNullOrWhiteSpace(trimmed) &&
                    !trimmed.Equals("yes", StringComparison.OrdinalIgnoreCase) &&
                    !trimmed.Equals("true", StringComparison.OrdinalIgnoreCase))
                {
                    colors.Add(trimmed);
                }
            }
        }

        // 2. Check "colour", "color", "tee:colour", "tee:color"
        foreach (var key in new[] { "colour", "color", "tee:colour", "tee:color" })
        {
            if (tags.TryGetValue(key, out var colVal) && !string.IsNullOrWhiteSpace(colVal))
            {
                foreach (var part in colVal.Split(new[] { ';', ',', '/' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    var trimmed = part.Trim();
                    if (!string.IsNullOrWhiteSpace(trimmed) &&
                        !trimmed.Equals("yes", StringComparison.OrdinalIgnoreCase) &&
                        !trimmed.Equals("true", StringComparison.OrdinalIgnoreCase))
                    {
                        colors.Add(trimmed);
                    }
                }
            }
        }

        // 3. Check role if provided, e.g. "tee:blue", "white", "tee_white"
        if (!string.IsNullOrWhiteSpace(role))
        {
            string roleClean = role.Replace("tee:", "").Replace("tee_", "").Replace("tee", "").Trim();
            if (!string.IsNullOrWhiteSpace(roleClean) &&
                !roleClean.Equals("yes", StringComparison.OrdinalIgnoreCase) &&
                !roleClean.Equals("true", StringComparison.OrdinalIgnoreCase))
            {
                colors.Add(roleClean);
            }
        }

        // 4. Check name if no color found yet (e.g. "White Tee", "Blue Tees", "Gold")
        if (colors.Count == 0 && tags.TryGetValue("name", out var nameVal) && !string.IsNullOrWhiteSpace(nameVal))
        {
            var knownColors = new[] { "black", "gold", "blue", "white", "red", "green", "orange", "yellow", "silver" };
            foreach (var kc in knownColors)
            {
                if (nameVal.IndexOf(kc, StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    colors.Add(kc);
                }
            }
        }

        // Default if still empty:
        if (colors.Count == 0)
        {
            colors.Add("Blue");
        }

        return colors
            .Where(c => !string.IsNullOrWhiteSpace(c))
            .Select(c => char.ToUpper(c[0]) + (c.Length > 1 ? c.Substring(1).ToLower() : ""))
            .ToList();
    }

    private static NoiseTexture2D? _cachedWaterWaveNoiseTex;
    private static NoiseTexture2D? _cachedWaterNormalTex1;
    private static NoiseTexture2D? _cachedWaterNormalTex2;

    private static void EnsureWaterNoiseTextures()
    {
        if (_cachedWaterWaveNoiseTex != null && _cachedWaterNormalTex1 != null && _cachedWaterNormalTex2 != null)
            return;

        var waveNoise = new FastNoiseLite
        {
            NoiseType = FastNoiseLite.NoiseTypeEnum.Simplex,
            Frequency = 0.03f
        };
        _cachedWaterWaveNoiseTex = new NoiseTexture2D
        {
            Noise = waveNoise,
            Seamless = true
        };

        var normalNoise = new FastNoiseLite
        {
            NoiseType = FastNoiseLite.NoiseTypeEnum.Simplex,
            Frequency = 0.05f
        };
        _cachedWaterNormalTex1 = new NoiseTexture2D
        {
            Noise = normalNoise,
            Seamless = true,
            AsNormalMap = true,
            BumpStrength = 2.0f
        };
        _cachedWaterNormalTex2 = new NoiseTexture2D
        {
            Noise = normalNoise,
            Seamless = true,
            AsNormalMap = true,
            BumpStrength = 1.5f
        };
    }

    public static Dictionary<string, float> ParseTeeDistances(Dictionary<string, string> tags)
    {
        var distances = new Dictionary<string, float>(StringComparer.OrdinalIgnoreCase);
        foreach (var tag in tags)
        {
            if (!tag.Key.StartsWith("dist:", StringComparison.OrdinalIgnoreCase))
                continue;

            string color = NormalizeTeeColor(tag.Key.Substring("dist:".Length));
            if (string.IsNullOrWhiteSpace(color))
                continue;

            var match = System.Text.RegularExpressions.Regex.Match(
                tag.Value,
                @"^\s*(?<distance>\d+(?:[.,]\d+)?)\s*(?<unit>yards?|yds?|meters?|metres?|m)?\s*$",
                System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            if (!match.Success ||
                !double.TryParse(match.Groups["distance"].Value.Replace(',', '.'),
                    NumberStyles.Float, CultureInfo.InvariantCulture, out double value) ||
                value <= 0)
            {
                GD.PrintErr($"{LogPrefix} Ignoring invalid tee distance tag {tag.Key}={tag.Value}");
                continue;
            }

            string unit = match.Groups["unit"].Value.ToLowerInvariant();
            bool isMeters = unit == "m" || unit.StartsWith("meter") || unit.StartsWith("metre");
            // Unitless dist:* values default to yards, as used by existing course data.
            distances[color] = (float)(isMeters ? value : value * 0.9144);
        }

        return distances;
    }

    public static void ApplyLegacyTeeFallbacks(HoleConfig hole)
    {
        if (hole.TeeBoxes.Count == 0)
            return;

        string fallbackKey = hole.TeeBoxes.ContainsKey("Blue") ? "Blue" : hole.TeeBoxes.Keys.First();
        var fallbackPosition = hole.TeeBoxes[fallbackKey];
        if (!hole.TeeBoxes.ContainsKey("Blue") && !hole.TeeDistancesMeters.ContainsKey("Blue"))
            hole.TeeBoxes["Blue"] = (float[])fallbackPosition.Clone();
        if (!hole.TeeBoxes.ContainsKey("White") && !hole.TeeDistancesMeters.ContainsKey("White"))
            hole.TeeBoxes["White"] = (float[])fallbackPosition.Clone();

        if (!hole.TeeBoxes.ContainsKey("Red") && !hole.TeeDistancesMeters.ContainsKey("Red"))
        {
            Vector2 pin = hole.HoleLocation != null && hole.HoleLocation.Length >= 2
                ? new Vector2(hole.HoleLocation[0], hole.HoleLocation[1])
                : Vector2.Zero;
            string forwardKey = fallbackKey;
            float minPinDistance = float.MaxValue;
            foreach (var tee in hole.TeeBoxes)
            {
                float distance = new Vector2(tee.Value[0], tee.Value[1]).DistanceTo(pin);
                if (distance < minPinDistance)
                {
                    minPinDistance = distance;
                    forwardKey = tee.Key;
                }
            }

            hole.TeeBoxes["Red"] = (float[])hole.TeeBoxes[forwardKey].Clone();
        }
    }

    private static string NormalizeTeeColor(string color)
    {
        string trimmed = color.Trim();
        return string.IsNullOrEmpty(trimmed)
            ? ""
            : char.ToUpperInvariant(trimmed[0]) + trimmed.Substring(1).ToLowerInvariant();
    }

    private static void AddTeeCandidate(
        Dictionary<(string HoleKey, string Color), List<TeeConfig>> candidatesByHole,
        string holeKey,
        TeeConfig candidate)
    {
        string color = NormalizeTeeColor(candidate.Color);
        var key = (holeKey, color);
        if (!candidatesByHole.TryGetValue(key, out var candidates))
        {
            candidates = new List<TeeConfig>();
            candidatesByHole[key] = candidates;
        }

        candidates.Add(candidate);
    }

    public static Vector2 GetPointAtDistanceFromHoleEnd(List<float[]> holePath, float distanceMeters)
    {
        if (holePath == null || holePath.Count == 0)
            return Vector2.Zero;

        var end = new Vector2(holePath[^1][0], holePath[^1][1]);
        float remainingDistance = Math.Max(0f, distanceMeters);
        for (int i = holePath.Count - 1; i > 0; i--)
        {
            var start = new Vector2(holePath[i - 1][0], holePath[i - 1][1]);
            var segment = start - end;
            float segmentLength = segment.Length();
            if (segmentLength <= 0f)
            {
                end = start;
                continue;
            }

            if (remainingDistance <= segmentLength)
                return end + segment * (remainingDistance / segmentLength);

            remainingDistance -= segmentLength;
            end = start;
        }

        return end;
    }

    public static Vector2 GetClosestPointInPolygon(Vector2 target, Vector2[] polygon)
    {
        if (polygon == null || polygon.Length == 0)
            return target;
        if (polygon.Length < 3)
            return polygon[0];
        if (PointInPolygon(target, polygon))
            return target;

        Vector2 closest = polygon[0];
        float closestDistanceSquared = float.MaxValue;
        for (int i = 0; i < polygon.Length; i++)
        {
            Vector2 start = polygon[i];
            Vector2 segment = polygon[(i + 1) % polygon.Length] - start;
            float segmentLengthSquared = segment.LengthSquared();
            float t = segmentLengthSquared <= 0f
                ? 0f
                : Mathf.Clamp((target - start).Dot(segment) / segmentLengthSquared, 0f, 1f);
            Vector2 point = start + segment * t;
            float distanceSquared = target.DistanceSquaredTo(point);
            if (distanceSquared < closestDistanceSquared)
            {
                closest = point;
                closestDistanceSquared = distanceSquared;
            }
        }

        return closest;
    }

    public static float GetDistanceToTeeCandidate(Vector2 point, Vector2 marker, Vector2[]? polygon)
    {
        float distance = point.DistanceTo(marker);
        if (polygon != null && polygon.Length >= 3)
            distance = Math.Min(distance, DistanceToPolygon(point, polygon));
        return distance;
    }

    public record OsmWay(long Id, List<long> NodeIds, Dictionary<string, string> Tags);
    public record OsmRelation(long Id, List<(string Type, long Ref, string Role)> Members, Dictionary<string, string> Tags);

    public sealed record CourseBoundaryInfo(
        string TargetCourseName,
        List<Vector2[]> CoursePolygons,
        List<Vector2[]> OtherCoursePolygons,
        HashSet<string> OtherCourseNames
    );
    
    private class CourseJsonConfig
    {
        [JsonPropertyName("graphics_version")]
        public int GraphicsVersion { get; set; } = 13;

        [JsonPropertyName("scene_path")]
        public string ScenePath { get; set; } = "course.tscn";

        [JsonPropertyName("Title")]
        public string Title { get; set; } = "";

        [JsonPropertyName("Latitude")]
        public double Latitude { get; set; }

        [JsonPropertyName("Longitude")]
        public double Longitude { get; set; }

        [JsonPropertyName("Location")]
        public string Location { get; set; } = "";

        [JsonPropertyName("Course Info")]
        public CourseInfoConfig CourseInfo { get; set; } = new();

        [JsonPropertyName("Hole Info")]
        public Dictionary<string, HoleConfig> HoleInfo { get; set; } = new();
    }

    private class CourseInfoConfig
    {
        [JsonPropertyName("Tee Colors")]
        public List<string> TeeColors { get; set; } = new();

        [JsonPropertyName("Satellite Image Bounds")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public double[]? SatelliteImageBounds { get; set; }

        [JsonPropertyName("Satellite Image Bounds Version")]
        public int SatelliteImageBoundsVersion { get; set; }

        [JsonPropertyName("Cart Paths")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public List<List<float[]>>? CartPaths { get; set; }

        [JsonPropertyName("Source Course")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? SourceCourse { get; set; }

        [JsonPropertyName("Sub-Courses")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public List<string>? SubCourses { get; set; }

        [JsonPropertyName("Variant Type")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? VariantType { get; set; }

        [JsonPropertyName("OSM Relation")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? OsmRelation { get; set; }

        [JsonPropertyName("OSM Relation ID")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? OsmRelationId { get; set; }

        [JsonPropertyName("Available Variants")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public List<string>? AvailableVariants { get; set; }
    }

    private static BBox GetSatelliteBBoxForAspectRatio(BBox bbox, double targetAspectRatio)
    {
        double centerLon = (bbox.LonMin + bbox.LonMax) * 0.5;
        double centerLat = (bbox.LatMin + bbox.LatMax) * 0.5;
        double widthMeters = (bbox.LonMax - bbox.LonMin) * bbox.MetersPerLon;
        double heightMeters = (bbox.LatMax - bbox.LatMin) * bbox.MetersPerLat;
        if (widthMeters / heightMeters < targetAspectRatio)
        {
            widthMeters = heightMeters * targetAspectRatio;
        }
        else
        {
            heightMeters = widthMeters / targetAspectRatio;
        }
        double halfWidthLon = widthMeters / bbox.MetersPerLon * 0.5;
        double halfHeightLat = heightMeters / bbox.MetersPerLat * 0.5;
        return new BBox
        {
            LonMin = centerLon - halfWidthLon,
            LonMax = centerLon + halfWidthLon,
            LatMin = centerLat - halfHeightLat,
            LatMax = centerLat + halfHeightLat,
            RefLat = bbox.RefLat,
            RefLon = bbox.RefLon,
            MetersPerLat = bbox.MetersPerLat,
            MetersPerLon = bbox.MetersPerLon
        };
    }

    public class HoleConfig
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

        [JsonIgnore]
        public Dictionary<string, float> TeeDistancesMeters { get; set; } = new(StringComparer.OrdinalIgnoreCase);

        [JsonIgnore]
        public string SubCourse { get; set; } = "";

        [JsonIgnore]
        public string OriginalRef { get; set; } = "";
    }

    private class TeeConfig
    {
        public string HoleNum { get; set; } = "1";
        public string Color { get; set; } = "blue";
        public float[] Location { get; set; } = new float[2];
        public string SubCourse { get; set; } = "";
        public Vector2[]? Polygon { get; set; }
    }

    public class ExclusionPolygon
    {
        public Vector2[] Polygon;
        public float MinX;
        public float MaxX;
        public float MinY;
        public float MaxY;
        public string? GolfType;
        public float? AverageHeight;

        public float CenterX;
        public float CenterY;
        public float CenterHeight;
        public float SlopeX;
        public float SlopeY;

        public ExclusionPolygon(Vector2[] polygon, string? golfType = "", OsmMapLoader? loader = null)
        {
            Polygon = polygon;
            GolfType = golfType;
            MinX = float.MaxValue;
            MaxX = float.MinValue;
            MinY = float.MaxValue;
            MaxY = float.MinValue;
            float sum = 0f;
            float sumX = 0f;
            float sumY = 0f;
            foreach (var p in polygon)
            {
                if (p.X < MinX) MinX = p.X;
                if (p.X > MaxX) MaxX = p.X;
                if (p.Y < MinY) MinY = p.Y;
                if (p.Y > MaxY) MaxY = p.Y;
                sumX += p.X;
                sumY += p.Y;
                if (loader != null)
                {
                    sum += loader.GetHeight(p.X, p.Y);
                }
            }
            if (loader != null && polygon.Length > 0 && (golfType == "tee" || golfType == "green"))
            {
                AverageHeight = sum / polygon.Length;
                CenterX = sumX / polygon.Length;
                CenterY = sumY / polygon.Length;
                CenterHeight = loader.GetHeight(CenterX, CenterY);

                if (golfType == "green")
                {
                    // Sample terrain gradient across green center to establish an authentic putting slope
                    float span = 8.0f;
                    float hL = loader.GetHeight(CenterX - span, CenterY);
                    float hR = loader.GetHeight(CenterX + span, CenterY);
                    float hD = loader.GetHeight(CenterX, CenterY - span);
                    float hU = loader.GetHeight(CenterX, CenterY + span);
                    float rawSlopeX = (hR - hL) / (2f * span);
                    float rawSlopeY = (hU - hD) / (2f * span);
                    float slopeMag = Mathf.Sqrt(rawSlopeX * rawSlopeX + rawSlopeY * rawSlopeY);

                    // Cap green putting slope to a gentle, playable 2.0% grade (0.020) so the ball has natural roll and break
                    // while perfectly conforming to the hill's natural slope direction without creating a tabletop shelf
                    float maxGrade = 0.020f;
                    if (slopeMag > maxGrade && slopeMag > 0.0001f)
                    {
                        SlopeX = rawSlopeX * (maxGrade / slopeMag);
                        SlopeY = rawSlopeY * (maxGrade / slopeMag);
                    }
                    else
                    {
                        SlopeX = rawSlopeX;
                        SlopeY = rawSlopeY;
                    }
                }
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

        // Reject sand trap / bunker colors (high brightness warm tan/sand tones)
        if (v > 0.52f && r > 0.48f && (r >= b + 0.05f))
        {
            return false;
        }

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

    private sealed record SatelliteImageResult(byte[] ImageBytes, double[] LocalBounds);

    /// <summary>
    /// Downloads a representative photo of the course (the one Google shows when searching the address).
    /// Uses the Google Places API (New) when an API key is configured via the
    /// GOOGLE_PLACES_API_KEY environment variable or the "heckle/google_places_api_key" project setting.
    /// Falls back to the Wikipedia lead image. Returns null when nothing is found; never throws.
    /// </summary>
    private async Task<byte[]?> DownloadCoursePhotoAsync(string courseName, string location, double lat, double lon)
    {
        try
        {
            string? apiKey = System.Environment.GetEnvironmentVariable("GOOGLE_PLACES_API_KEY");
            if (string.IsNullOrWhiteSpace(apiKey) && ProjectSettings.HasSetting("heckle/google_places_api_key"))
            {
                apiKey = ProjectSettings.GetSetting("heckle/google_places_api_key").AsString();
            }

            using var cts = new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(15));
            if (!string.IsNullOrWhiteSpace(apiKey))
            {
                string query = string.IsNullOrWhiteSpace(location) ? courseName : $"{courseName} {location}";
                var body = new Dictionary<string, object> { ["textQuery"] = query, ["maxResultCount"] = 1 };
                if (lat != 0 || lon != 0)
                {
                    body["locationBias"] = new Dictionary<string, object>
                    {
                        ["circle"] = new Dictionary<string, object>
                        {
                            ["center"] = new Dictionary<string, object> { ["latitude"] = lat, ["longitude"] = lon },
                            ["radius"] = 20000.0
                        }
                    };
                }

                using var searchRequest = new HttpRequestMessage(HttpMethod.Post, "https://places.googleapis.com/v1/places:searchText");
                searchRequest.Headers.Add("X-Goog-Api-Key", apiKey);
                searchRequest.Headers.Add("X-Goog-FieldMask", "places.photos");
                searchRequest.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");
                using var searchResponse = await HttpClient.SendAsync(searchRequest, cts.Token);
                if (searchResponse.IsSuccessStatusCode)
                {
                    using var doc = JsonDocument.Parse(await searchResponse.Content.ReadAsStringAsync(cts.Token));
                    if (doc.RootElement.TryGetProperty("places", out var places) && places.GetArrayLength() > 0 &&
                        places[0].TryGetProperty("photos", out var photos) && photos.GetArrayLength() > 0 &&
                        photos[0].TryGetProperty("name", out var photoName))
                    {
                        string mediaUrl = $"https://places.googleapis.com/v1/{photoName.GetString()}/media?maxWidthPx=1600&key={Uri.EscapeDataString(apiKey)}";
                        using var photoResponse = await HttpClient.GetAsync(mediaUrl, cts.Token);
                        if (photoResponse.IsSuccessStatusCode)
                        {
                            var bytes = await photoResponse.Content.ReadAsByteArrayAsync(cts.Token);
                            if (bytes.Length > 0)
                            {
                                GD.Print($"{LogPrefix} Downloaded Google Places photo for '{courseName}' ({bytes.Length} bytes).");
                                return bytes;
                            }
                        }
                    }
                }
                else
                {
                    GD.PrintErr($"{LogPrefix} Google Places search failed: {(int)searchResponse.StatusCode}");
                }
            }

            // Keyless web image search (Google Images requires JavaScript, so Bing Images is used)
            var searchPhoto = await DownloadPhotoFromWebImageSearchAsync(
                string.IsNullOrWhiteSpace(location) ? $"{courseName} golf course" : $"{courseName} {location} golf course", cts.Token);
            if (searchPhoto != null)
            {
                GD.Print($"{LogPrefix} Downloaded web search photo for '{courseName}' ({searchPhoto.Length} bytes).");
                return searchPhoto;
            }

            // Fallback: Wikipedia lead image for the course
            string wikiUrl = "https://en.wikipedia.org/w/api.php?action=query&generator=search&gsrlimit=1&prop=pageimages&piprop=thumbnail&pithumbsize=1280&format=json&gsrsearch="
                + Uri.EscapeDataString($"{courseName} golf");
            using var wikiResponse = await HttpClient.GetAsync(wikiUrl, cts.Token);
            if (wikiResponse.IsSuccessStatusCode)
            {
                using var wikiDoc = JsonDocument.Parse(await wikiResponse.Content.ReadAsStringAsync(cts.Token));
                if (wikiDoc.RootElement.TryGetProperty("query", out var q) && q.TryGetProperty("pages", out var pages))
                {
                    foreach (var page in pages.EnumerateObject())
                    {
                        if (page.Value.TryGetProperty("thumbnail", out var thumb) && thumb.TryGetProperty("source", out var src))
                        {
                            using var imgResponse = await HttpClient.GetAsync(src.GetString(), cts.Token);
                            if (imgResponse.IsSuccessStatusCode)
                            {
                                return await imgResponse.Content.ReadAsByteArrayAsync(cts.Token);
                            }
                        }
                    }
                }
            }
            // Last resort: nearest geotagged Wikimedia Commons photo (within 1 km of the course)
            if (lat != 0 || lon != 0)
            {
                string commonsUrl = "https://commons.wikimedia.org/w/api.php?action=query&generator=geosearch&ggsnamespace=6&ggsradius=1000&ggslimit=10"
                    + "&prop=imageinfo&iiprop=url|mime&iiurlwidth=1280&format=json&ggscoord="
                    + Uri.EscapeDataString(string.Format(CultureInfo.InvariantCulture, "{0}|{1}", lat, lon));
                using var commonsResponse = await HttpClient.GetAsync(commonsUrl, cts.Token);
                if (commonsResponse.IsSuccessStatusCode)
                {
                    using var commonsDoc = JsonDocument.Parse(await commonsResponse.Content.ReadAsStringAsync(cts.Token));
                    if (commonsDoc.RootElement.TryGetProperty("query", out var cq) && cq.TryGetProperty("pages", out var cpages))
                    {
                        foreach (var page in cpages.EnumerateObject())
                        {
                            if (!page.Value.TryGetProperty("imageinfo", out var infos) || infos.GetArrayLength() == 0)
                                continue;
                            var info = infos[0];
                            if (!info.TryGetProperty("mime", out var mime) || mime.GetString() != "image/jpeg")
                                continue;
                            string? thumb = info.TryGetProperty("thumburl", out var t) ? t.GetString() : null;
                            if (string.IsNullOrEmpty(thumb))
                                continue;
                            using var imgResponse = await HttpClient.GetAsync(thumb, cts.Token);
                            if (imgResponse.IsSuccessStatusCode)
                            {
                                GD.Print($"{LogPrefix} Using Wikimedia Commons photo for '{courseName}'.");
                                return await imgResponse.Content.ReadAsByteArrayAsync(cts.Token);
                            }
                        }
                    }
                }
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Course photo download failed: {ex.Message}");
        }
        return null;
    }

    private static async Task<byte[]?> DownloadPhotoFromWebImageSearchAsync(string query, System.Threading.CancellationToken token)
    {
        const string browserUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/115.0";
        try
        {
            using var searchRequest = new HttpRequestMessage(HttpMethod.Get,
                $"https://www.bing.com/images/search?q={Uri.EscapeDataString(query)}&form=HDRSC2&first=1");
            searchRequest.Headers.TryAddWithoutValidation("User-Agent", browserUserAgent);
            using var searchResponse = await HttpClient.SendAsync(searchRequest, token);
            if (!searchResponse.IsSuccessStatusCode)
                return null;

            string html = await searchResponse.Content.ReadAsStringAsync(token);
            var matches = System.Text.RegularExpressions.Regex.Matches(html, "murl&quot;:&quot;(https?://[^&]+)&quot;");
            int attempts = 0;
            foreach (System.Text.RegularExpressions.Match match in matches)
            {
                if (attempts++ >= 6)
                    break;
                try
                {
                    using var imageRequest = new HttpRequestMessage(HttpMethod.Get, System.Net.WebUtility.HtmlDecode(match.Groups[1].Value));
                    imageRequest.Headers.TryAddWithoutValidation("User-Agent", browserUserAgent);
                    using var imageResponse = await HttpClient.SendAsync(imageRequest, token);
                    if (!imageResponse.IsSuccessStatusCode)
                        continue;
                    string? mediaType = imageResponse.Content.Headers.ContentType?.MediaType;
                    if (mediaType != "image/jpeg" && mediaType != "image/png" && mediaType != "image/webp")
                        continue;
                    var bytes = await imageResponse.Content.ReadAsByteArrayAsync(token);
                    if (bytes.Length > 20_000 && bytes.Length < 10_000_000)
                        return bytes;
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    // Try the next result
                }
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Web image search failed: {ex.Message}");
        }
        return null;
    }

    private async Task<SatelliteImageResult?> DownloadSatelliteImageAsync(BBox bbox, int width, int height)
    {
        string bboxParameter = string.Format(
            System.Globalization.CultureInfo.InvariantCulture,
            "{0:R},{1:R},{2:R},{3:R}",
            bbox.LonMin,
            bbox.LatMin,
            bbox.LonMax,
            bbox.LatMax);
        string url = $"https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?bbox={bboxParameter}&bboxSR=4326&imageSR=4326&size={width},{height}&adjustAspectRatio=false&f=json&format=png";
        
        GD.Print($"{LogPrefix} Requesting satellite image and rendered extent for tree detection.");
        try
        {
            using var metadataResponse = await HttpClient.GetAsync(url);
            if (!metadataResponse.IsSuccessStatusCode)
            {
                GD.PrintErr($"{LogPrefix} Satellite image export request failed with status: {metadataResponse.StatusCode}");
                return null;
            }
            using var metadataDocument = JsonDocument.Parse(await metadataResponse.Content.ReadAsStringAsync());
            var root = metadataDocument.RootElement;
            if (!root.TryGetProperty("href", out var hrefElement)
                || !root.TryGetProperty("extent", out var extent)
                || !extent.TryGetProperty("spatialReference", out var spatialReference)
                || !spatialReference.TryGetProperty("wkid", out var wkidElement))
            {
                GD.PrintErr($"{LogPrefix} Satellite image export response did not include its image URL and geographic extent.");
                return null;
            }

            int wkid = wkidElement.GetInt32();
            if (wkid != 4326 && wkid != 4269)
            {
                GD.PrintErr($"{LogPrefix} Satellite image export returned unsupported spatial reference {wkid}; refusing to save unaligned imagery.");
                return null;
            }

            double lonMin = extent.GetProperty("xmin").GetDouble();
            double latMin = extent.GetProperty("ymin").GetDouble();
            double lonMax = extent.GetProperty("xmax").GetDouble();
            double latMax = extent.GetProperty("ymax").GetDouble();
            if (!double.IsFinite(lonMin) || !double.IsFinite(latMin)
                || !double.IsFinite(lonMax) || !double.IsFinite(latMax)
                || lonMax <= lonMin || latMax <= latMin)
            {
                GD.PrintErr($"{LogPrefix} Satellite image export returned invalid geographic bounds.");
                return null;
            }

            string imageUrl = hrefElement.GetString() ?? "";
            if (!Uri.TryCreate(imageUrl, UriKind.Absolute, out var imageUri))
            {
                imageUri = new Uri(new Uri("https://services.arcgisonline.com"), imageUrl);
            }
            using var imageResponse = await HttpClient.GetAsync(imageUri);
            if (!imageResponse.IsSuccessStatusCode)
            {
                GD.PrintErr($"{LogPrefix} Satellite image download failed with status: {imageResponse.StatusCode}");
                return null;
            }

            var localBounds = new[]
            {
                (lonMin - bbox.RefLon) * bbox.MetersPerLon,
                -(latMax - bbox.RefLat) * bbox.MetersPerLat,
                (lonMax - bbox.RefLon) * bbox.MetersPerLon,
                -(latMin - bbox.RefLat) * bbox.MetersPerLat
            };
            return new SatelliteImageResult(await imageResponse.Content.ReadAsByteArrayAsync(), localBounds);
        }
        catch (JsonException ex)
        {
            GD.PrintErr($"{LogPrefix} Satellite image export returned invalid metadata: {ex.Message}");
            return null;
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Failed to retrieve satellite image and extent: {ex}");
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

    private BBox? CalculateBBoxFromOsmJson(string jsonString, double lat, double lon, string courseName = "")
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

            var boundaryInfo = IdentifyCourseBoundaries(ways, relations, nodes, lat, lon, courseName, refLat, refLon, metersPerLat, metersPerLon);
            string targetCourseName = boundaryInfo.TargetCourseName;
            var coursePolygons = boundaryInfo.CoursePolygons;
            var otherCoursePolygons = boundaryInfo.OtherCoursePolygons;
            var otherCourseNames = boundaryInfo.OtherCourseNames;

            var lineOfPlayPaths = new List<List<Vector2>>();
            var exclusionPolygons = new List<ExclusionPolygon>();

            Func<Vector2, bool> isPointInMainCourse = (pt) => IsPointInMainCourse(pt, boundaryInfo, lineOfPlayPaths, exclusionPolygons);
            Func<OsmWay, bool> isHoleBelongingToCourse = (hw) => IsHoleBelongingToCourse(hw, nodes, refLat, refLon, metersPerLat, metersPerLon, boundaryInfo);

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
                way.Tags.TryGetValue("golf", out string? golfType);

                if (golfType == "hole")
                {
                    if (!isHoleBelongingToCourse(way))
                        continue;
                }
                else if (!isPointInMainCourse(wayCenter))
                {
                    bool isMainBoundary = (way.Tags.TryGetValue("leisure", out var l) && l == "golf_course") || way.Tags.ContainsKey("golf");
                    if (!isMainBoundary)
                        continue;
                }

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
        int surfaceTypeValue = golfType == "green" ? 4 : (golfType == "bunker" ? 5 : 0);

        var staticBody = new StaticBody3D { Name = $"{golfType}_Static_{idSuffix}" };
        staticBody.SetMeta("surface_type", surfaceTypeValue);
        if (golfType == "bunker")
        {
            staticBody.SetMeta("is_sand", true);
            staticBody.SetMeta("boundary_polygon", uniquePoints);
        }
        CreateCollisionForPolygon(staticBody, uniquePoints, rootNode, exclusionPolygons);
    }

    private static List<List<Vector2>> MergeCartPaths(List<List<Vector2>> paths, float maximumJoinDistance)
    {
        var merged = paths
            .Where(path => path.Count >= 2)
            .Select(path => new List<Vector2>(path))
            .ToList();
        bool didMerge = true;
        while (didMerge)
        {
            didMerge = false;
            for (int firstIndex = 0; firstIndex < merged.Count && !didMerge; firstIndex++)
            {
                for (int secondIndex = firstIndex + 1; secondIndex < merged.Count; secondIndex++)
                {
                    var first = merged[firstIndex];
                    var second = merged[secondIndex];
                    float bestDistance = maximumJoinDistance;
                    bool reverseFirst = false;
                    bool reverseSecond = false;
                    var endpointPairs = new[]
                    {
                        (First: first[^1], Second: second[0], ReverseFirst: false, ReverseSecond: false),
                        (First: first[^1], Second: second[^1], ReverseFirst: false, ReverseSecond: true),
                        (First: first[0], Second: second[0], ReverseFirst: true, ReverseSecond: false),
                        (First: first[0], Second: second[^1], ReverseFirst: true, ReverseSecond: true)
                    };
                    var join = endpointPairs
                        .Select(candidate => (Candidate: candidate, Distance: candidate.First.DistanceTo(candidate.Second)))
                        .OrderBy(candidate => candidate.Distance)
                        .First();
                    if (join.Distance > bestDistance)
                    {
                        continue;
                    }

                    reverseFirst = join.Candidate.ReverseFirst;
                    reverseSecond = join.Candidate.ReverseSecond;
                    if (reverseFirst)
                    {
                        first.Reverse();
                    }
                    if (reverseSecond)
                    {
                        second.Reverse();
                    }
                    if (first[^1].DistanceTo(second[0]) > 0.001f)
                    {
                        first.Add((first[^1] + second[0]) * 0.5f);
                    }
                    first.AddRange(second.Skip(1));
                    merged.RemoveAt(secondIndex);
                    didMerge = true;
                    break;
                }
            }
        }
        return merged;
    }

    private void CreateCartPath(Node3D rootNode, List<Vector2> points, int pathIndex, List<ExclusionPolygon> exclusions)
    {
        if (points.Count < 2)
        {
            return;
        }

        const float halfWidth = 1.25f;
        const float maximumPointSpacing = 1.0f;
        const float visualHeightOffset = 0.035f;
        const float collisionHeightOffset = 0.020f;
        var cleanPoints = new List<Vector2>();
        foreach (var point in points)
        {
            if (cleanPoints.Count == 0 || cleanPoints[^1].DistanceSquaredTo(point) > 0.0001f)
            {
                cleanPoints.Add(point);
            }
        }
        if (cleanPoints.Count < 2)
        {
            return;
        }

        var sampledPoints = new List<Vector2> { cleanPoints[0] };
        for (int pointIndex = 1; pointIndex < cleanPoints.Count; pointIndex++)
        {
            Vector2 start = cleanPoints[pointIndex - 1];
            Vector2 end = cleanPoints[pointIndex];
            int subdivisions = Mathf.Max(1, Mathf.CeilToInt(start.DistanceTo(end) / maximumPointSpacing));
            for (int subdivision = 1; subdivision <= subdivisions; subdivision++)
            {
                sampledPoints.Add(start.Lerp(end, subdivision / (float)subdivisions));
            }
        }
        cleanPoints = sampledPoints;

        var leftEdge = new Vector2[cleanPoints.Count];
        var rightEdge = new Vector2[cleanPoints.Count];
        for (int pointIndex = 0; pointIndex < cleanPoints.Count; pointIndex++)
        {
            Vector2 point = cleanPoints[pointIndex];
            Vector2 previousDirection = pointIndex > 0
                ? (point - cleanPoints[pointIndex - 1]).Normalized()
                : (cleanPoints[1] - point).Normalized();
            Vector2 nextDirection = pointIndex < cleanPoints.Count - 1
                ? (cleanPoints[pointIndex + 1] - point).Normalized()
                : previousDirection;
            Vector2 previousNormal = new Vector2(-previousDirection.Y, previousDirection.X);
            Vector2 nextNormal = new Vector2(-nextDirection.Y, nextDirection.X);
            Vector2 miter = (previousNormal + nextNormal).Normalized();
            if (miter.LengthSquared() < 0.001f)
            {
                miter = nextNormal;
            }
            float miterLength = Mathf.Min(halfWidth / Mathf.Max(Mathf.Abs(miter.Dot(nextNormal)), 0.25f), halfWidth * 2.5f);
            Vector2 offset = miter * miterLength;
            leftEdge[pointIndex] = point + offset;
            rightEdge[pointIndex] = point - offset;
        }

        var vertices = new Vector3[cleanPoints.Count * 2];
        var normals = new Vector3[vertices.Length];
        var uvs = new Vector2[vertices.Length];
        var indices = new int[(cleanPoints.Count - 1) * 6];
        float accumulatedDistance = 0f;
        for (int pointIndex = 0; pointIndex < cleanPoints.Count; pointIndex++)
        {
            if (pointIndex > 0)
            {
                accumulatedDistance += cleanPoints[pointIndex].DistanceTo(cleanPoints[pointIndex - 1]);
            }
            float v = accumulatedDistance * 0.25f;
            Vector2 left = leftEdge[pointIndex];
            Vector2 right = rightEdge[pointIndex];
            vertices[pointIndex * 2] = new Vector3(left.X, GetHeightWithFeatures(left.X, left.Y, exclusions) + visualHeightOffset, left.Y);
            vertices[pointIndex * 2 + 1] = new Vector3(right.X, GetHeightWithFeatures(right.X, right.Y, exclusions) + visualHeightOffset, right.Y);
            normals[pointIndex * 2] = Vector3.Up;
            normals[pointIndex * 2 + 1] = Vector3.Up;
            uvs[pointIndex * 2] = new Vector2(0f, v);
            uvs[pointIndex * 2 + 1] = new Vector2(1f, v);
        }
        for (int segmentIndex = 0; segmentIndex < cleanPoints.Count - 1; segmentIndex++)
        {
            int vertex = segmentIndex * 2;
            int index = segmentIndex * 6;
            indices[index] = vertex;
            indices[index + 1] = vertex + 2;
            indices[index + 2] = vertex + 1;
            indices[index + 3] = vertex + 1;
            indices[index + 4] = vertex + 2;
            indices[index + 5] = vertex + 3;
        }

        var meshArrays = new Godot.Collections.Array();
        meshArrays.Resize((int)Mesh.ArrayType.Max);
        meshArrays[(int)Mesh.ArrayType.Vertex] = vertices;
        meshArrays[(int)Mesh.ArrayType.Normal] = normals;
        meshArrays[(int)Mesh.ArrayType.TexUV] = uvs;
        meshArrays[(int)Mesh.ArrayType.Index] = indices;
        var mesh = new ArrayMesh();
        mesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, meshArrays);

        if (ResourceLoader.Exists("res://Courses/Environments/shaders/cart_path.gdshader"))
        {
            var shaderMat = new ShaderMaterial
            {
                Shader = GD.Load<Shader>("res://Courses/Environments/shaders/cart_path.gdshader")
            };
            mesh.SurfaceSetMaterial(0, shaderMat);
        }
        else
        {
            var material = new StandardMaterial3D
            {
                AlbedoColor = new Color(0.79f, 0.63f, 0.39f),
                Roughness = 0.90f,
                MetallicSpecular = 0.10f,
                CullMode = BaseMaterial3D.CullModeEnum.Disabled
            };
            mesh.SurfaceSetMaterial(0, material);
        }
        var meshInstance = new MeshInstance3D
        {
            Name = $"cartpath_{pathIndex}",
            Mesh = mesh
        };
        rootNode.AddChild(meshInstance);
        meshInstance.Owner = rootNode;

        var staticBody = new StaticBody3D { Name = $"cartpath_Static_{pathIndex}" };
        staticBody.SetMeta("surface_type", (int)PhysicsEnums.SurfaceType.CartPath);
        staticBody.SetMeta("is_cart_path", true);
        var collisionShape = new CollisionShape3D();
        var collisionFaces = mesh.GetFaces();
        float collisionOffset = visualHeightOffset - collisionHeightOffset;
        for (int faceIndex = 0; faceIndex < collisionFaces.Length; faceIndex++)
        {
            Vector3 faceVertex = collisionFaces[faceIndex];
            faceVertex.Y -= collisionOffset;
            collisionFaces[faceIndex] = faceVertex;
        }
        var collision = new ConcavePolygonShape3D
        {
            Data = collisionFaces,
            BackfaceCollision = true
        };
        collisionShape.Shape = collision;
        staticBody.AddChild(collisionShape);
        rootNode.AddChild(staticBody);
        staticBody.Owner = rootNode;
        collisionShape.Owner = rootNode;
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
        bool isMobile = OS.GetName() == "Android" || OS.GetName() == "iOS";
        float maxEdge = isMobile ? 8.0f : 5.0f;
        float maxEdgeSq = maxEdge * maxEdge;
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
    /// Quintic smoothstep (C2 continuous: smooth first and second derivatives).
    /// Eliminates angular curvature kinks at transition boundaries.
    /// </summary>
    private static float QuinticSmoothstep(float t)
    {
        float c = Math.Clamp(t, 0f, 1f);
        return c * c * c * (c * (c * 6f - 15f) + 10f);
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
        bool inPlayArea = false;

        for (int i = 0; i < exclusions.Count; i++)
        {
            var excl = exclusions[i];
            if (x < excl.MinX - 10.0f || x > excl.MaxX + 10.0f || z < excl.MinY - 10.0f || z > excl.MaxY + 10.0f)
                continue;

            bool inside = PointInPolygon(point, excl.Polygon);
            if (inside && (excl.GolfType == "fairway" || excl.GolfType == "green" || excl.GolfType == "tee" || excl.GolfType == "bunker" || excl.GolfType == "water"))
            {
                inPlayArea = true;
            }

            if (excl.GolfType == "bunker")
            {
                if (inside)
                {
                    float dist = DistanceToPolygon(point, excl.Polygon);
                    float bowlRadius = 7.0f;
                    float maxDepth = 1.0f;
                    if (dist < bowlRadius)
                    {
                        float t = dist / bowlRadius;
                        float smoothT = QuinticSmoothstep(t);
                        bunkerDepression = Math.Max(bunkerDepression, smoothT * maxDepth);
                    }
                    else
                    {
                        bunkerDepression = Math.Max(bunkerDepression, maxDepth);
                    }
                }
                else
                {
                    // Raised lip outside bunker boundary: wider and gentler transition
                    float dist = DistanceToPolygon(point, excl.Polygon);
                    float lipRadius = 4.0f;
                    if (dist < lipRadius)
                    {
                        float t = 1.0f - (dist / lipRadius);
                        float smoothT = QuinticSmoothstep(t);
                        bunkerDepression = Math.Max(bunkerDepression, -smoothT * 0.12f);
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
                        float smoothT = QuinticSmoothstep(t);
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
                float dist = DistanceToPolygon(point, excl.Polygon);
                float signedDist = inside ? dist : -dist;
                float rOutTee = 2.5f;
                float rInTee = 2.5f;
                if (signedDist > -rOutTee)
                {
                    if (signedDist >= rInTee)
                    {
                        overrideHeight = (overrideHeight.HasValue && overrideWeight >= 1.0f) ? overrideHeight.Value : targetH;
                        overrideWeight = 1.0f;
                    }
                    else
                    {
                        float u = (signedDist + rOutTee) / (rInTee + rOutTee);
                        float smoothT = QuinticSmoothstep(u);
                        float blendedH = baseHeight * (1f - smoothT) + targetH * smoothT;
                        if (!overrideHeight.HasValue || smoothT > overrideWeight)
                        {
                            overrideHeight = blendedH;
                            overrideWeight = smoothT;
                        }
                    }
                }
            }
            else if (excl.GolfType == "green")
            {
                // Calculate signed distance: positive inside green, negative outside in fairway/apron
                float dist = DistanceToPolygon(point, excl.Polygon);
                float signedDist = inside ? dist : -dist;

                // Wide, smooth bidirectional C2 rounding transition across apron, fringe, collar, and green
                // Extends from 6m outside the green into the fairway/apron to 5m inside the green
                float rOut = 6.0f;
                float rIn = 5.0f;

                if (signedDist > -rOut)
                {
                    // Ideal putting surface plane: gentle ~2% putting grade conforming to natural hill direction
                    float puttH = excl.CenterHeight + excl.SlopeX * (x - excl.CenterX) + excl.SlopeY * (z - excl.CenterY);

                    if (signedDist >= rIn)
                    {
                        // Fully on the smooth putting green
                        overrideHeight = (overrideHeight.HasValue && overrideWeight >= 1.0f) ? overrideHeight.Value : puttH;
                        overrideWeight = 1.0f;
                    }
                    else
                    {
                        // In the smooth C2 rounded transition zone (collar/fringe)
                        float u = (signedDist + rOut) / (rIn + rOut);
                        float smoothT = QuinticSmoothstep(u);
                        float blendedH = baseHeight * (1f - smoothT) + puttH * smoothT;
                        if (!overrideHeight.HasValue || smoothT > overrideWeight)
                        {
                            overrideHeight = blendedH;
                            overrideWeight = smoothT;
                        }
                    }
                }
            }
        }

        // Very subtle natural variation in the rough (at most +/- 0.08m) while keeping in-play turf smooth
        float roughMounds = 0f;
        if (!inPlayArea && !overrideHeight.HasValue)
        {
            roughMounds = (float)(Math.Sin(x * 0.015 + z * 0.012) * 0.08);
        }

        float finalBase = (overrideHeight.HasValue ? overrideHeight.Value : baseHeight) + roughMounds;
        return finalBase - Math.Max(bunkerDepression, waterDepression);
    }

    /// <summary>
    /// Generates a splat map texture encoding surface types for the terrain.
    /// R = green, G = fairway/tee, B = bunker, A = mulch. Rough = where all channels are 0.
    /// </summary>
    private Image GenerateSplatMap(float minX, float maxX, float minZ, float maxZ, List<ExclusionPolygon> exclusions, List<Vector2> treePositions)
    {
        bool isMobile = OS.GetName() == "Android" || OS.GetName() == "iOS";
        int texSize = isMobile ? 1024 : 2048;
        byte[] pixelData = new byte[texSize * texSize * 4];

        float worldWidth = maxX - minX;
        float worldDepth = maxZ - minZ;
        float blendRadius = 3.0f; // meters of smooth blending at zone boundaries (widened for gentle transitions)

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
                        weight = QuinticSmoothstep(t); // C2 quintic smoothstep
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
                        float mulchWeight = QuinticSmoothstep(w); // C2 quintic smoothstep
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
        return image;
    }

    /// <summary>
    /// Generates a macro ambient occlusion map from course elevation data.
    /// Darkens swales, bunker bowls, and recessed contours while keeping ridges and plateaus bright.
    /// </summary>
    private Image GenerateTerrainAOMap(float minX, float maxX, float minZ, float maxZ, List<ExclusionPolygon> exclusions)
    {
        bool isMobile = OS.GetName() == "Android" || OS.GetName() == "iOS";
        int texSize = isMobile ? 512 : 1024;
        byte[] pixelData = new byte[texSize * texSize];

        float worldWidth = maxX - minX;
        float worldDepth = maxZ - minZ;
        float sampleRadius = 6.0f; // meters (widened from 4.0m to match gentler bowls and valleys)

        Parallel.For(0, texSize, py =>
        {
            float worldZ = minZ + (py / (float)(texSize - 1)) * worldDepth;
            for (int px = 0; px < texSize; px++)
            {
                float worldX = minX + (px / (float)(texSize - 1)) * worldWidth;
                float hCenter = GetHeightWithFeatures(worldX, worldZ, exclusions);
                
                // Sample 12 neighbors around circle for smooth angular coverage
                float hSum = 0f;
                for (int i = 0; i < 12; i++)
                {
                    float angle = i * (Mathf.Pi / 6.0f);
                    hSum += GetHeightWithFeatures(worldX + MathF.Cos(angle) * sampleRadius, worldZ + MathF.Sin(angle) * sampleRadius, exclusions);
                }
                float hAvg = hSum / 12.0f;

                // If center is lower than surroundings, it's a depression/swale (AO < 1.0)
                float diff = hCenter - hAvg;
                float ao = Mathf.Clamp(1.0f + diff * 0.45f, 0.55f, 1.0f);

                pixelData[py * texSize + px] = (byte)Math.Clamp((int)(ao * 255.0f), 0, 255);
            }
        });

        var image = Image.CreateFromData(texSize, texSize, false, Image.Format.L8, pixelData);
        return image;
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
        var splatImage = await Task.Run(() => GenerateSplatMap(minX, maxX, minZ, maxZ, exclusions, treePositions));
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        var splatMap = ImageTexture.CreateFromImage(splatImage);

        // Generate macro terrain ambient occlusion map in background thread
        GD.Print($"{LogPrefix} Generating terrain macro AO map...");
        var terrainAoImage = await Task.Run(() => GenerateTerrainAOMap(minX, maxX, minZ, maxZ, exclusions));
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        var terrainAoMap = ImageTexture.CreateFromImage(terrainAoImage);

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

    private static List<List<long>> AssembleRelationNodeChains(
        OsmRelation rel, 
        List<OsmWay> allWays, 
        Dictionary<long, (double Lat, double Lon)> nodes)
    {
        var outerMemberWays = rel.Members
            .Where(m => m.Type == "way" && (m.Role == "outer" || string.IsNullOrEmpty(m.Role)))
            .Select(m => allWays.FirstOrDefault(w => w.Id == m.Ref))
            .Where(w => w != null && w.NodeIds.Count >= 2)
            .ToList();

        var resultChains = new List<List<long>>();
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
                    resultChains.Add(validNodes);
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

            if (currentChain.Count >= 4 && currentChain.First() == currentChain.Last())
            {
                resultChains.Add(currentChain);
            }
            else if (currentChain.Count >= 3)
            {
                currentChain.Add(currentChain.First());
                resultChains.Add(currentChain);
            }
        }

        return resultChains;
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
        var chains = AssembleRelationNodeChains(rel, allWays, nodes);
        var resultPolygons = new List<Vector2[]>();

        foreach (var chain in chains)
        {
            var pts = chain
                .Where(nodes.ContainsKey)
                .Select(id => nodes[id])
                .Select(coord => new Vector2(
                    (float)((coord.Lon - refLon) * metersPerLon),
                    -(float)((coord.Lat - refLat) * metersPerLat)
                ))
                .ToArray();

            if (pts.Length >= 3)
            {
                resultPolygons.Add(pts);
            }
        }

        return resultPolygons;
    }

    public static bool PointInPolygon(Vector2 pt, Vector2[] poly)
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

    public static float DistanceToSegment(Vector2 p, Vector2 a, Vector2 b)
    {
        Vector2 ab = b - a;
        Vector2 ap = p - a;
        float ab2 = ab.LengthSquared();
        if (ab2 == 0f) return ap.Length();
        
        float t = Mathf.Clamp(ap.Dot(ab) / ab2, 0f, 1f);
        Vector2 projection = a + t * ab;
        return p.DistanceTo(projection);
    }

    public static float DistanceToPolygon(Vector2 p, Vector2[] poly)
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

    public static float DistancePointToPolygonWithInterior(Vector2 p, Vector2[] poly)
    {
        if (poly == null || poly.Length < 3) return float.MaxValue;
        if (PointInPolygon(p, poly)) return 0f;
        return DistanceToPolygon(p, poly);
    }

    public static float DistancePointToPolygonList(Vector2 p, List<Vector2[]> polys)
    {
        if (polys == null || polys.Count == 0) return float.MaxValue;
        float minD = float.MaxValue;
        for (int i = 0; i < polys.Count; i++)
        {
            var poly = polys[i];
            if (poly == null || poly.Length < 3) continue;
            float d = DistancePointToPolygonWithInterior(p, poly);
            if (d < minD)
            {
                minD = d;
                if (minD == 0f) return 0f;
            }
        }
        return minD;
    }

    public static bool CourseNameMatches(string? osmName, string? targetName)
    {
        if (string.IsNullOrWhiteSpace(osmName) || string.IsNullOrWhiteSpace(targetName)) return false;
        string s1 = osmName.Trim();
        string s2 = targetName.Trim();
        if (s1.Equals(s2, StringComparison.OrdinalIgnoreCase)) return true;
        if (s1.Contains(s2, StringComparison.OrdinalIgnoreCase) || s2.Contains(s1, StringComparison.OrdinalIgnoreCase)) return true;

        string Clean(string s) => s.Replace("Golf Course", "", StringComparison.OrdinalIgnoreCase)
                                   .Replace("Golf Club", "", StringComparison.OrdinalIgnoreCase)
                                   .Replace("Golf Links", "", StringComparison.OrdinalIgnoreCase)
                                   .Replace("Country Club", "", StringComparison.OrdinalIgnoreCase)
                                   .Replace("Golf", "", StringComparison.OrdinalIgnoreCase)
                                   .Trim();
        string c1 = Clean(s1);
        string c2 = Clean(s2);
        if (!string.IsNullOrWhiteSpace(c1) && !string.IsNullOrWhiteSpace(c2))
        {
            if (c1.Equals(c2, StringComparison.OrdinalIgnoreCase) || c1.Contains(c2, StringComparison.OrdinalIgnoreCase) || c2.Contains(c1, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    public static CourseBoundaryInfo IdentifyCourseBoundaries(
        List<OsmWay> ways,
        List<OsmRelation> relations,
        Dictionary<long, (double Lat, double Lon)> nodes,
        double lat,
        double lon,
        string preferredCourseName,
        double refLat,
        double refLon,
        double metersPerLat,
        double metersPerLon)
    {
        OsmWay? targetWay = null;
        OsmRelation? targetRel = null;

        // 1. Try to find a way or relation matching preferredCourseName
        if (!string.IsNullOrWhiteSpace(preferredCourseName))
        {
            double bestNamedDist = double.MaxValue;
            foreach (var way in ways)
            {
                if (way.Tags.TryGetValue("leisure", out var leisure) && leisure == "golf_course" &&
                    way.Tags.TryGetValue("name", out var wayName) && CourseNameMatches(wayName, preferredCourseName))
                {
                    var wayNodes = way.NodeIds.Where(nodes.ContainsKey).Select(id => nodes[id]).ToList();
                    if (wayNodes.Count > 0)
                    {
                        double avgLat = wayNodes.Average(n => n.Lat);
                        double avgLon = wayNodes.Average(n => n.Lon);
                        double dLat = avgLat - lat;
                        double dLon = avgLon - lon;
                        double dist = dLat * dLat + dLon * dLon;
                        if (dist < bestNamedDist)
                        {
                            bestNamedDist = dist;
                            targetWay = way;
                            targetRel = null;
                        }
                    }
                }
            }

            foreach (var rel in relations)
            {
                if (rel.Tags.TryGetValue("leisure", out var leisure) && leisure == "golf_course" &&
                    rel.Tags.TryGetValue("name", out var relName) && CourseNameMatches(relName, preferredCourseName))
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
                        if (dist < bestNamedDist)
                        {
                            bestNamedDist = dist;
                            targetRel = rel;
                            targetWay = null;
                        }
                    }
                }
            }
        }

        // 2. If no name match, fallback to closest by coordinates
        if (targetWay == null && targetRel == null)
        {
            double closestDist = double.MaxValue;
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
                            targetWay = way;
                            targetRel = null;
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
                            targetRel = rel;
                            targetWay = null;
                        }
                    }
                }
            }
        }

        string targetCourseName = "";
        if (targetRel != null && targetRel.Tags.TryGetValue("name", out var rName))
        {
            targetCourseName = rName;
        }
        else if (targetWay != null && targetWay.Tags.TryGetValue("name", out var wName))
        {
            targetCourseName = wName;
        }
        else if (!string.IsNullOrWhiteSpace(preferredCourseName))
        {
            targetCourseName = preferredCourseName;
        }

        var coursePolygons = new List<Vector2[]>();
        var otherCoursePolygons = new List<Vector2[]>();
        var otherCourseNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        var matchingWays = ways.Where(w =>
            w.Tags.TryGetValue("leisure", out var l) && l == "golf_course" &&
            (string.IsNullOrEmpty(targetCourseName) ? w == targetWay : CourseNameMatches(w.Tags.GetValueOrDefault("name"), targetCourseName))
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
            (string.IsNullOrEmpty(targetCourseName) ? r == targetRel : CourseNameMatches(r.Tags.GetValueOrDefault("name"), targetCourseName))
        ).ToList();

        foreach (var r in matchingRels)
        {
            var assembled = AssembleRelationPolygons(r, ways, nodes, refLat, refLon, metersPerLat, metersPerLon);
            coursePolygons.AddRange(assembled);
        }

        var otherWays = ways.Where(w =>
            w.Tags.TryGetValue("leisure", out var l) && l == "golf_course" &&
            !matchingWays.Contains(w)
        ).ToList();

        foreach (var w in otherWays)
        {
            if (w.Tags.TryGetValue("name", out var on) && !string.IsNullOrWhiteSpace(on))
            {
                otherCourseNames.Add(on);
            }
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
                otherCoursePolygons.Add(pts);
            }
        }

        var otherRels = relations.Where(r =>
            r.Tags.TryGetValue("leisure", out var l) && l == "golf_course" &&
            !matchingRels.Contains(r)
        ).ToList();

        foreach (var r in otherRels)
        {
            if (r.Tags.TryGetValue("name", out var on) && !string.IsNullOrWhiteSpace(on))
            {
                otherCourseNames.Add(on);
            }
            var assembled = AssembleRelationPolygons(r, ways, nodes, refLat, refLon, metersPerLat, metersPerLon);
            otherCoursePolygons.AddRange(assembled);
        }

        return new CourseBoundaryInfo(targetCourseName, coursePolygons, otherCoursePolygons, otherCourseNames);
    }

    public static bool IsHoleBelongingToCourse(
        OsmWay hw,
        Dictionary<long, (double Lat, double Lon)> nodes,
        double refLat,
        double refLon,
        double metersPerLat,
        double metersPerLon,
        CourseBoundaryInfo boundaryInfo)
    {
        var hPts = hw.NodeIds
            .Where(nodes.ContainsKey)
            .Select(id => nodes[id])
            .Select(coord => new Vector2(
                (float)((coord.Lon - refLon) * metersPerLon),
                -(float)((coord.Lat - refLat) * metersPerLat)
            ))
            .ToList();

        if (hPts.Count < 2) return false;

        Vector2 tee = hPts.First();
        Vector2 pin = hPts.Last();

        string holeCourse = ExtractSubCourseName(hw.Tags);
        if (!string.IsNullOrEmpty(holeCourse))
        {
            if (!string.IsNullOrEmpty(boundaryInfo.TargetCourseName) && CourseNameMatches(holeCourse, boundaryInfo.TargetCourseName))
            {
                return true;
            }
            if (boundaryInfo.OtherCourseNames.Any(ocn => CourseNameMatches(holeCourse, ocn)))
            {
                return false;
            }
        }

        if (boundaryInfo.CoursePolygons.Count == 0)
        {
            if (boundaryInfo.OtherCoursePolygons.Count > 0)
            {
                bool teeInOther = boundaryInfo.OtherCoursePolygons.Any(p => PointInPolygon(tee, p));
                bool pinInOther = boundaryInfo.OtherCoursePolygons.Any(p => PointInPolygon(pin, p));
                if (teeInOther && pinInOther) return false;
            }
            return true;
        }

        if (boundaryInfo.OtherCoursePolygons.Count > 0)
        {
            bool teeInOther = boundaryInfo.OtherCoursePolygons.Any(p => PointInPolygon(tee, p));
            bool pinInOther = boundaryInfo.OtherCoursePolygons.Any(p => PointInPolygon(pin, p));
            bool teeInTarget = boundaryInfo.CoursePolygons.Any(p => PointInPolygon(tee, p));
            bool pinInTarget = boundaryInfo.CoursePolygons.Any(p => PointInPolygon(pin, p));

            if ((teeInOther && !teeInTarget) && (pinInOther && !pinInTarget))
                return false;

            if ((teeInOther && !teeInTarget) || (pinInOther && !pinInTarget))
            {
                float dTargetMin = Math.Min(DistancePointToPolygonList(tee, boundaryInfo.CoursePolygons), DistancePointToPolygonList(pin, boundaryInfo.CoursePolygons));
                float dOtherMin = Math.Min(DistancePointToPolygonList(tee, boundaryInfo.OtherCoursePolygons), DistancePointToPolygonList(pin, boundaryInfo.OtherCoursePolygons));
                if (dOtherMin < dTargetMin)
                    return false;
            }
        }

        float teeDist = DistancePointToPolygonList(tee, boundaryInfo.CoursePolygons);
        float pinDist = DistancePointToPolygonList(pin, boundaryInfo.CoursePolygons);

        // Both endpoints strictly inside
        if (teeDist == 0f && pinDist == 0f) return true;

        // One inside, other close to boundary (within 35m tolerance for mapper drawing inaccuracy)
        if (teeDist == 0f && pinDist <= 35f) return true;
        if (pinDist == 0f && teeDist <= 35f) return true;

        // Both slightly outside near boundary (within 25m tolerance)
        if (teeDist <= 25f && pinDist <= 25f) return true;

        return false;
    }

    public static bool IsPointInMainCourse(
        Vector2 pt,
        CourseBoundaryInfo boundaryInfo,
        List<List<Vector2>> lineOfPlayPaths,
        List<ExclusionPolygon> exclusionPolygons)
    {
        if (boundaryInfo.CoursePolygons.Count == 0) return true;

        // If point is strictly inside an other course's boundary and not in target course, exclude it
        if (boundaryInfo.OtherCoursePolygons.Count > 0 &&
            boundaryInfo.OtherCoursePolygons.Any(p => PointInPolygon(pt, p)) &&
            !boundaryInfo.CoursePolygons.Any(p => PointInPolygon(pt, p)))
        {
            return false;
        }

        foreach (var poly in boundaryInfo.CoursePolygons)
        {
            if (PointInPolygon(pt, poly)) return true;
            if (DistancePointToPolygonWithInterior(pt, poly) < 35f) return true;
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
    }

    /// <summary>
    /// Checks whether a tree position is too close to any fairway polygon (closer than minDistance meters).
    /// </summary>
    public static bool IsTreeTooCloseToFairway(Vector2 pt, IEnumerable<Vector2[]> fairwayPolygons, float minDistance = 14.0f)
    {
        if (fairwayPolygons == null) return false;
        foreach (var fw in fairwayPolygons)
        {
            if (fw == null || fw.Length < 3) continue;
            if (PointInPolygon(pt, fw))
            {
                return true;
            }
            if (DistanceToPolygon(pt, fw) < minDistance)
            {
                return true;
            }
        }
        return false;
    }

    /// <summary>
    /// Checks whether a tree position is located in the way between any tee box and the fairway target.
    /// </summary>
    public static bool IsTreeBetweenTeeAndFairway(Vector2 pt, Vector2 teePos, Vector2 fairwayTarget, float corridorHalfWidth = 18.0f, float minTeeFrontDist = 35.0f)
    {
        Vector2 toTarget = fairwayTarget - teePos;
        float totalDist = toTarget.Length();
        if (totalDist < 0.001f) return false;

        Vector2 driveDir = toTarget / totalDist;
        Vector2 toPt = pt - teePos;
        float forwardProj = toPt.Dot(driveDir);

        // If candidate is behind or at the tee box, it's not between tee and fairway
        if (forwardProj <= 0f) return false;

        // If candidate is beyond the fairway target, it's not between tee and fairway
        if (forwardProj > totalDist) return false;

        // Perpendicular distance to drive axis
        float perpDist = Math.Abs(toPt.X * driveDir.Y - toPt.Y * driveDir.X);
        if (perpDist < corridorHalfWidth)
        {
            return true;
        }

        // Direct obstruction in front cone of tee
        if (toPt.Length() < minTeeFrontDist)
        {
            float cosAngle = forwardProj / toPt.Length();
            if (cosAngle > 0.34f) // within ~70 degrees forward cone
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>
    /// Checks whether a tree position is inside or too close to any cart path line/polyline.
    /// Default minDistance is 2.2m (cart path half-width ~1.25m + clearance ~0.95m).
    /// </summary>
    public static bool IsTreeTooCloseToCartPath(Vector2 pt, IEnumerable<IEnumerable<Vector2>>? cartPaths, float minDistance = 2.2f)
    {
        if (cartPaths == null) return false;
        float minDstSq = minDistance * minDistance;
        foreach (var path in cartPaths)
        {
            if (path == null) continue;
            Vector2? prev = null;
            foreach (var curr in path)
            {
                if (prev.HasValue)
                {
                    Vector2 a = prev.Value;
                    Vector2 b = curr;
                    float minX = Math.Min(a.X, b.X) - minDistance;
                    float maxX = Math.Max(a.X, b.X) + minDistance;
                    float minY = Math.Min(a.Y, b.Y) - minDistance;
                    float maxY = Math.Max(a.Y, b.Y) + minDistance;

                    if (pt.X >= minX && pt.X <= maxX && pt.Y >= minY && pt.Y <= maxY)
                    {
                        float d = DistanceToSegment(pt, a, b);
                        if (d < minDistance)
                        {
                            return true;
                        }
                    }
                }
                prev = curr;
            }
        }
        return false;
    }

    /// <summary>
    /// Checks whether a tree position is inside or too close to any bunker / sand trap polygon.
    /// </summary>
    public static bool IsTreeTooCloseToBunker(Vector2 pt, IEnumerable<Vector2[]> bunkerPolygons, float minDistance = 5.0f)
    {
        if (bunkerPolygons == null) return false;
        foreach (var bk in bunkerPolygons)
        {
            if (bk == null || bk.Length < 3) continue;
            if (PointInPolygon(pt, bk))
            {
                return true;
            }
            if (DistanceToPolygon(pt, bk) < minDistance)
            {
                return true;
            }
        }
        return false;
    }

    /// <summary>
    /// Checks whether a tree position is inside or too close to any green polygon.
    /// </summary>
    public static bool IsTreeTooCloseToGreen(Vector2 pt, IEnumerable<Vector2[]> greenPolygons, float minDistance = 10.0f)
    {
        if (greenPolygons == null) return false;
        foreach (var gr in greenPolygons)
        {
            if (gr == null || gr.Length < 3) continue;
            if (PointInPolygon(pt, gr))
            {
                return true;
            }
            if (DistanceToPolygon(pt, gr) < minDistance)
            {
                return true;
            }
        }
        return false;
    }

    /// <summary>
    /// Validates whether a candidate tree point respects fairway, bunker, green, and tee box clearance rules.
    /// </summary>
    public static bool IsProceduralTreePointValid(
        Vector2 pt,
        IEnumerable<Vector2[]> fairwayPolygons,
        Dictionary<string, HoleConfig>? holeData,
        float minFairwayDist = 14.0f,
        float corridorHalfWidth = 18.0f,
        IEnumerable<Vector2[]>? bunkerPolygons = null,
        float minBunkerDist = 5.0f,
        IEnumerable<Vector2[]>? greenPolygons = null,
        float minGreenDist = 10.0f,
        IEnumerable<IEnumerable<Vector2>>? cartPaths = null,
        float minCartPathDist = 2.2f)
    {
        // 1. Ensure no trees inside or too close to cart paths (< 2.2m)
        if (cartPaths != null && IsTreeTooCloseToCartPath(pt, cartPaths, minCartPathDist))
        {
            return false;
        }

        // 2. Ensure no trees inside or too close to bunker (< 5.0m)
        if (bunkerPolygons != null && IsTreeTooCloseToBunker(pt, bunkerPolygons, minBunkerDist))
        {
            return false;
        }

        // 3. Ensure no trees inside or too close to green (< 10.0m)
        if (greenPolygons != null && IsTreeTooCloseToGreen(pt, greenPolygons, minGreenDist))
        {
            return false;
        }

        // 4. Ensure no trees too close to fairway
        if (IsTreeTooCloseToFairway(pt, fairwayPolygons, minFairwayDist))
        {
            return false;
        }

        // 5. Ensure no trees between any tee box and fairway
        if (holeData != null)
        {
            foreach (var kvp in holeData)
            {
                var h = kvp.Value;
                if (h.TeeBoxes == null) continue;

                Vector2 target;
                if (h.HolePath != null && h.HolePath.Count > 1)
                {
                    target = new Vector2(h.HolePath[1][0], h.HolePath[1][1]);
                }
                else if (h.HoleLocation != null && h.HoleLocation.Length >= 2)
                {
                    target = new Vector2(h.HoleLocation[0], h.HoleLocation[1]);
                }
                else
                {
                    continue;
                }

                foreach (var teeKvp in h.TeeBoxes)
                {
                    if (teeKvp.Value == null || teeKvp.Value.Length < 2) continue;
                    var teePos = new Vector2(teeKvp.Value[0], teeKvp.Value[1]);
                    if (IsTreeBetweenTeeAndFairway(pt, teePos, target, corridorHalfWidth))
                    {
                        return false;
                    }
                }
            }
        }

        return true;
    }

    public bool CheckTreeTooCloseToBunker(Vector2 pt, Godot.Collections.Array bunkerPolygons, float minDistance = 5.0f)
    {
        var list = new List<Vector2[]>();
        if (bunkerPolygons != null)
        {
            foreach (var item in bunkerPolygons)
            {
                if (item.VariantType == Variant.Type.PackedVector2Array)
                {
                    list.Add(item.AsVector2Array());
                }
                else if (item.Obj is Vector2[] vArr)
                {
                    list.Add(vArr);
                }
            }
        }
        return IsTreeTooCloseToBunker(pt, list, minDistance);
    }

    public bool CheckTreeTooCloseToGreen(Vector2 pt, Godot.Collections.Array greenPolygons, float minDistance = 10.0f)
    {
        var list = new List<Vector2[]>();
        if (greenPolygons != null)
        {
            foreach (var item in greenPolygons)
            {
                if (item.VariantType == Variant.Type.PackedVector2Array)
                {
                    list.Add(item.AsVector2Array());
                }
                else if (item.Obj is Vector2[] vArr)
                {
                    list.Add(vArr);
                }
            }
        }
        return IsTreeTooCloseToGreen(pt, list, minDistance);
    }

    public bool CheckTreeTooCloseToFairway(Vector2 pt, Godot.Collections.Array fairwayPolygons, float minDistance = 14.0f)
    {
        var list = new List<Vector2[]>();
        if (fairwayPolygons != null)
        {
            foreach (var item in fairwayPolygons)
            {
                if (item.VariantType == Variant.Type.PackedVector2Array)
                {
                    list.Add(item.AsVector2Array());
                }
                else if (item.Obj is Vector2[] vArr)
                {
                    list.Add(vArr);
                }
            }
        }
        return IsTreeTooCloseToFairway(pt, list, minDistance);
    }

    public bool CheckTreeBetweenTeeAndFairway(Vector2 pt, Vector2 teePos, Vector2 fairwayTarget, float corridorHalfWidth = 18.0f, float minTeeFrontDist = 35.0f)
    {
        return IsTreeBetweenTeeAndFairway(pt, teePos, fairwayTarget, corridorHalfWidth, minTeeFrontDist);
    }

    public bool CheckTreeTooCloseToCartPath(Vector2 pt, Godot.Collections.Array cartPaths, float minDistance = 2.2f)
    {
        var list = new List<List<Vector2>>();
        if (cartPaths != null)
        {
            foreach (var item in cartPaths)
            {
                if (item.VariantType == Variant.Type.PackedVector2Array)
                {
                    list.Add(new List<Vector2>(item.AsVector2Array()));
                }
                else if (item.Obj is Vector2[] vArr)
                {
                    list.Add(new List<Vector2>(vArr));
                }
                else if (item.Obj is List<Vector2> vList)
                {
                    list.Add(vList);
                }
                else if (item.Obj is IEnumerable<Vector2> vEnum)
                {
                    list.Add(new List<Vector2>(vEnum));
                }
                else if (item.VariantType == Variant.Type.Array)
                {
                    var innerArr = item.AsGodotArray();
                    var pList = new List<Vector2>();
                    foreach (var p in innerArr)
                    {
                        if (p.VariantType == Variant.Type.Vector2)
                        {
                            pList.Add(p.AsVector2());
                        }
                    }
                    if (pList.Count > 0)
                    {
                        list.Add(pList);
                    }
                }
            }
        }
        return IsTreeTooCloseToCartPath(pt, list, minDistance);
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
        staticBody.SetMeta("is_rock", true);
        staticBody.AddToGroup("rocks");
        
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
