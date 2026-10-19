using System;
using System.Collections.Generic;
using System.Linq;
using Godot;
using Godot.Collections;

namespace HeckleLinks.Announcer;

[GlobalClass]
public partial class AnnouncerEngine : Node
{
    private static readonly string LogPrefix = "[AnnouncerEngine]";

    [Export] public bool AnnouncerCoursePlay { get; set; } = true;
    [Export] public bool HeckleCoursePlay { get; set; } = true;
    [Export] public bool AnnouncerRange { get; set; } = false;
    [Export] public bool HeckleRange { get; set; } = false;
    [Export] public bool AnnouncerMiniGames { get; set; } = false;
    [Export] public bool HeckleMiniGames { get; set; } = false;
    [Export] public bool PraiseEnabled { get; set; } = true;
    [Export] public string ActiveVoice { get; set; } = "";
    [Export] public float Pitch { get; set; } = 1.0f;
    [Export] public float Rate { get; set; } = 1.0f;

    // Backward compatibility properties
    public bool AnnouncerEnabled
    {
        get => IsAnnouncerActiveForCurrentScene();
        set
        {
            var mode = GetCurrentGameMode();
            switch (mode)
            {
                case SimGameMode.CoursePlay: AnnouncerCoursePlay = value; break;
                case SimGameMode.Range: AnnouncerRange = value; break;
                case SimGameMode.MiniGames: AnnouncerMiniGames = value; break;
                default:
                    AnnouncerCoursePlay = value;
                    AnnouncerRange = value;
                    AnnouncerMiniGames = value;
                    break;
            }
        }
    }

    public bool HeckleEnabled
    {
        get => IsHeckleActiveForCurrentScene();
        set
        {
            var mode = GetCurrentGameMode();
            switch (mode)
            {
                case SimGameMode.CoursePlay: HeckleCoursePlay = value; break;
                case SimGameMode.Range: HeckleRange = value; break;
                case SimGameMode.MiniGames: HeckleMiniGames = value; break;
                default:
                    HeckleCoursePlay = value;
                    HeckleRange = value;
                    HeckleMiniGames = value;
                    break;
            }
        }
    }

    // Audio stream player child
    private AudioStreamPlayer _audioPlayer = null!;

    // Idle announcement timer
    private float _idleTimer = 0.0f;
    private const float IdleAnnouncementInterval = 45.0f; // 45 seconds

    private readonly Random _random = new();
    private bool _shotHadCommentary = false;
    private bool _ballHitTree = false;
    private const double BadShotHeckleProbability = 0.65;
    private ulong _lastMulliganMsec = 0;

    public class HecklePromptDefinition
    {
        public string Name { get; set; } = "";
        public string Audio { get; set; } = "";
        public string Prompt { get; set; } = "";
        public string Filepath { get; set; } = "";
        public bool Enabled { get; set; } = true;
        public System.Collections.Generic.Dictionary<string, object> Qualifiers { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    }

    // Audio file cache: Category -> List of resource paths (fallback for non-json categories)
    private readonly System.Collections.Generic.Dictionary<string, List<string>> _audioCache = new(StringComparer.OrdinalIgnoreCase);
    // JSON prompt cache: Category -> List of HecklePromptDefinitions with enabled flag and qualifiers
    private readonly System.Collections.Generic.Dictionary<string, List<HecklePromptDefinition>> _promptDefinitions = new(StringComparer.OrdinalIgnoreCase);
    private string _lastPlayedPath = "";
    // Tracks played audio line filepaths to prevent repeated voice lines until all matching lines have played
    private readonly HashSet<string> _playedAudioLines = new(StringComparer.OrdinalIgnoreCase);

    public Array<Dictionary> GetTtsVoices()
    {
        return AndroidTTS.GetVoices();
    }

    public override void _Ready()
    {
        _audioPlayer = new AudioStreamPlayer();
        AddChild(_audioPlayer);
        PreloadCategoryClips();
        GD.Print($"{LogPrefix} Ready. Audio player initialized with heckler clips.");
    }

    private void PreloadCategoryClips()
    {
        LoadPromptDefinitions();

        string hecklerDir = "res://assets/audio/heckler";
        if (!DirAccess.DirExistsAbsolute(hecklerDir)) return;

        var subdirs = DirAccess.GetDirectoriesAt(hecklerDir);
        if (subdirs == null) return;

        foreach (var dir in subdirs)
        {
            if (!_promptDefinitions.ContainsKey(dir))
            {
                ScanFolderClips(dir);
            }
        }
    }

    private void LoadPromptDefinitions()
    {
        string[] candidatePaths = {
            "res://assets/audio/heckler/heckle_prompts.json",
            "res://scripts/tools/heckle_generator/heckle_prompts.json"
        };

        string jsonContent = "";
        string loadedPath = "";
        foreach (var path in candidatePaths)
        {
            if (FileAccess.FileExists(path))
            {
                jsonContent = FileAccess.GetFileAsString(path);
                if (!string.IsNullOrWhiteSpace(jsonContent))
                {
                    loadedPath = path;
                    break;
                }
            }
        }

        if (string.IsNullOrWhiteSpace(jsonContent))
        {
            GD.Print($"{LogPrefix} No heckle_prompts.json found. Falling back to directory scan.");
            return;
        }

        try
        {
            using var doc = System.Text.Json.JsonDocument.Parse(jsonContent);
            if (doc.RootElement.TryGetProperty("categories", out var categoriesElem))
            {
                _promptDefinitions.Clear();
                foreach (var catProp in categoriesElem.EnumerateObject())
                {
                    string catName = catProp.Name;
                    var promptList = new List<HecklePromptDefinition>();

                    foreach (var itemElem in catProp.Value.EnumerateArray())
                    {
                        var def = new HecklePromptDefinition();
                        if (itemElem.TryGetProperty("name", out var n)) def.Name = n.GetString() ?? "";
                        if (itemElem.TryGetProperty("audio", out var a)) def.Audio = a.GetString() ?? "";
                        if (itemElem.TryGetProperty("prompt", out var p)) def.Prompt = p.GetString() ?? "";
                        if (itemElem.TryGetProperty("filepath", out var fp)) def.Filepath = fp.GetString() ?? "";
                        if (itemElem.TryGetProperty("enabled", out var en)) def.Enabled = en.GetBoolean();

                        if (itemElem.TryGetProperty("qualifiers", out var qElem) && qElem.ValueKind == System.Text.Json.JsonValueKind.Object)
                        {
                            foreach (var qProp in qElem.EnumerateObject())
                            {
                                switch (qProp.Value.ValueKind)
                                {
                                    case System.Text.Json.JsonValueKind.True:
                                    case System.Text.Json.JsonValueKind.False:
                                        def.Qualifiers[qProp.Name] = qProp.Value.GetBoolean();
                                        break;
                                    case System.Text.Json.JsonValueKind.Number:
                                        if (qProp.Value.TryGetInt32(out int intVal))
                                            def.Qualifiers[qProp.Name] = intVal;
                                        else if (qProp.Value.TryGetDouble(out double dblVal))
                                            def.Qualifiers[qProp.Name] = dblVal;
                                        break;
                                    case System.Text.Json.JsonValueKind.String:
                                        def.Qualifiers[qProp.Name] = qProp.Value.GetString() ?? "";
                                        break;
                                }
                            }
                        }

                        promptList.Add(def);
                    }

                    _promptDefinitions[catName] = promptList;
                }

                GD.Print($"{LogPrefix} Loaded {_promptDefinitions.Count} categories from {loadedPath}");
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Failed to parse heckle_prompts.json: {ex.Message}");
        }
    }

    public Array<string> GetAvailableClipsForCategory(string categoryName)
    {
        return GetAvailableClipsForCategory(categoryName, null);
    }

    public Array<string> GetAvailableClipsForCategory(string categoryName, Dictionary? context)
    {
        var result = new Array<string>();
        if (_promptDefinitions.TryGetValue(categoryName, out var defs) && defs.Count > 0)
        {
            // 1. Filter out prompts disabled via audio JSON flag
            var enabledDefs = defs.Where(d => d.Enabled).ToList();
            if (enabledDefs.Count == 0)
            {
                GD.Print($"{LogPrefix} All clips for category '{categoryName}' are disabled in JSON.");
                return result;
            }

            // 2. If no context provided, return general clips (or all enabled if none are purely general)
            if (context == null || context.Count == 0)
            {
                var generalClips = enabledDefs
                    .Where(d => d.Qualifiers.Count == 0)
                    .Select(d => d.Filepath)
                    .Where(fp => !string.IsNullOrEmpty(fp))
                    .ToList();

                if (generalClips.Count > 0)
                {
                    foreach (var c in generalClips) result.Add(c);
                    return result;
                }

                foreach (var d in enabledDefs)
                {
                    if (!string.IsNullOrEmpty(d.Filepath)) result.Add(d.Filepath);
                }
                return result;
            }

            // 3. Match against context qualifiers
            var qualifiedMatches = new List<string>();
            var generalMatches = new List<string>();

            foreach (var def in enabledDefs)
            {
                if (string.IsNullOrEmpty(def.Filepath)) continue;

                if (def.Qualifiers.Count == 0)
                {
                    generalMatches.Add(def.Filepath);
                    continue;
                }

                if (MatchesQualifiers(def.Qualifiers, context))
                {
                    qualifiedMatches.Add(def.Filepath);
                }
            }

            // Prioritize specific contextual matches when available; fall back to general
            if (qualifiedMatches.Count > 0)
            {
                foreach (var c in qualifiedMatches) result.Add(c);
                return result;
            }

            foreach (var c in generalMatches) result.Add(c);
            return result;
        }

        // Fallback to legacy filesystem audio cache if category not defined in JSON
        if (_audioCache.TryGetValue(categoryName, out var cached) && cached.Count > 0)
        {
            foreach (var c in cached) result.Add(c);
            return result;
        }

        var scanned = ScanFolderClips(categoryName);
        foreach (var c in scanned) result.Add(c);
        return result;
    }

    private List<string> ScanFolderClips(string categoryName)
    {
        var clips = new List<string>();
        string folderPath = $"res://assets/audio/heckler/{categoryName}";

        if (DirAccess.DirExistsAbsolute(folderPath))
        {
            var files = DirAccess.GetFilesAt(folderPath);
            if (files != null)
            {
                var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var file in files)
                {
                    string f = file;
                    if (f.EndsWith(".import", StringComparison.OrdinalIgnoreCase))
                        f = f.Substring(0, f.Length - 7);
                    if (f.EndsWith(".remap", StringComparison.OrdinalIgnoreCase))
                        f = f.Substring(0, f.Length - 6);

                    if (f.EndsWith(".wav", StringComparison.OrdinalIgnoreCase) ||
                        f.EndsWith(".mp3", StringComparison.OrdinalIgnoreCase) ||
                        f.EndsWith(".ogg", StringComparison.OrdinalIgnoreCase))
                    {
                        if (seen.Add(f))
                        {
                            clips.Add($"{folderPath}/{f}");
                        }
                    }
                }
            }
        }

        _audioCache[categoryName] = clips;
        return clips;
    }

    public enum SimGameMode
    {
        CoursePlay,
        Range,
        MiniGames,
        MenuOrOther
    }

    public SimGameMode GetCurrentGameMode()
    {
        var tree = GetTree();
        if (tree == null) return SimGameMode.MenuOrOther;

        var currentScene = tree.CurrentScene;
        if (currentScene == null) return SimGameMode.MenuOrOther;

        string sceneName = currentScene.Name.ToString().ToLowerInvariant();
        string scenePath = currentScene.SceneFilePath != null ? currentScene.SceneFilePath.ToLowerInvariant() : "";

        var script = currentScene.GetScript();
        string scriptPath = "";
        if (script.VariantType == Variant.Type.Object)
        {
            var res = script.As<Resource>();
            if (res != null && !string.IsNullOrEmpty(res.ResourcePath))
                scriptPath = res.ResourcePath.ToLowerInvariant();
        }

        string fullId = $"{sceneName} {scriptPath} {scenePath}".ToLowerInvariant();

        // 1. Check if Menu / UI screen
        if (fullId.Contains("main_menu") || fullId.Contains("mainmenu") ||
            fullId.Contains("course_selector") || fullId.Contains("courseselector") ||
            fullId.Contains("course_play_setup") || fullId.Contains("courseplaysetup") ||
            fullId.Contains("minigames_menu") || fullId.Contains("minigamesmenu") ||
            fullId.Contains("players_menu") || fullId.Contains("playersmenu") ||
            fullId.Contains("analytics") || fullId.Contains("history") ||
            fullId.Contains("custom_course_creator") || fullId.Contains("osm_download") ||
            fullId.Contains("course_preview"))
        {
            return SimGameMode.MenuOrOther;
        }

        // 2. Check Minigames (Putting Practice, Chipping, etc.)
        if (fullId.Contains("chipping") || fullId.Contains("putting") ||
            fullId.Contains("minigame") || fullId.Contains("minigames"))
        {
            return SimGameMode.MiniGames;
        }

        // 3. Driving Range vs Course Play
        if (currentScene.HasNode("MultiplayerController"))
        {
            return SimGameMode.CoursePlay;
        }

        if (sceneName == "range" || scenePath.EndsWith("range.tscn"))
        {
            return SimGameMode.Range;
        }

        // 4. Any loaded Course scene
        if (sceneName.Contains("course") || scenePath.Contains("course") ||
            scenePath.Contains("usercourses") || sceneName.Contains("coursemanager"))
        {
            return SimGameMode.CoursePlay;
        }

        // 5. Fallback if Player or MultiplayerManager is in scene
        if (currentScene.HasNode("Player") || currentScene.HasNode("MultiplayerManager"))
        {
            return SimGameMode.CoursePlay;
        }

        return SimGameMode.MenuOrOther;
    }

    public bool IsAnnouncerActiveForCurrentScene()
    {
        var mode = GetCurrentGameMode();
        return mode switch
        {
            SimGameMode.CoursePlay => AnnouncerCoursePlay,
            SimGameMode.Range => AnnouncerRange,
            SimGameMode.MiniGames => AnnouncerMiniGames,
            _ => false
        };
    }

    public bool IsHeckleActiveForCurrentScene()
    {
        if (!IsAnnouncerActiveForCurrentScene())
            return false;

        var mode = GetCurrentGameMode();
        return mode switch
        {
            SimGameMode.CoursePlay => HeckleCoursePlay,
            SimGameMode.Range => HeckleRange,
            SimGameMode.MiniGames => HeckleMiniGames,
            _ => false
        };
    }

    public string SelectNextClipForCategory(string categoryName)
    {
        return SelectNextClipForCategory(categoryName, null, false);
    }

    public string SelectNextClipForCategory(string categoryName, Dictionary? context)
    {
        return SelectNextClipForCategory(categoryName, context, false);
    }

    public string SelectNextClipForCategory(string categoryName, Dictionary? context, bool markAsPlayed)
    {
        var clips = GetAvailableClipsForCategory(categoryName, context);
        if (clips == null || clips.Count == 0)
        {
            return "";
        }

        var distinctClips = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var clip in clips)
        {
            if (!string.IsNullOrEmpty(clip) && seen.Add(clip))
            {
                distinctClips.Add(clip);
            }
        }

        if (distinctClips.Count == 0)
        {
            return "";
        }

        var unplayedClips = new List<string>();
        foreach (var clip in distinctClips)
        {
            if (!_playedAudioLines.Contains(clip))
            {
                unplayedClips.Add(clip);
            }
        }

        // If all clips meeting the criteria for this hit have been played,
        // reset played status for this criteria set before repeating.
        if (unplayedClips.Count == 0)
        {
            GD.Print($"{LogPrefix} All {distinctClips.Count} clips for '{categoryName}' criteria set have been played. Resetting played tracking for these clips.");
            if (markAsPlayed)
            {
                foreach (var clip in distinctClips)
                {
                    _playedAudioLines.Remove(clip);
                }
            }
            unplayedClips.AddRange(distinctClips);
        }

        string chosenPath;
        if (unplayedClips.Count == 1)
        {
            chosenPath = unplayedClips[0];
        }
        else
        {
            int idx = _random.Next(unplayedClips.Count);
            if (unplayedClips[idx] == _lastPlayedPath)
            {
                idx = (idx + 1) % unplayedClips.Count;
            }
            chosenPath = unplayedClips[idx];
        }

        if (markAsPlayed && !string.IsNullOrEmpty(chosenPath))
        {
            _playedAudioLines.Add(chosenPath);
            _lastPlayedPath = chosenPath;
        }

        return chosenPath;
    }

    public bool PlayCategory(string categoryName)
    {
        return PlayCategory(categoryName, null);
    }

    public bool PlayCategory(string categoryName, Dictionary? context)
    {
        string chosenPath = SelectNextClipForCategory(categoryName, context, markAsPlayed: true);
        if (string.IsNullOrEmpty(chosenPath))
        {
            GD.Print($"{LogPrefix} No eligible audio clips found for category '{categoryName}' (with context).");
            return false;
        }

        try
        {
            var stream = GD.Load<AudioStream>(chosenPath);
            if (stream != null)
            {
                _audioPlayer.Stream = stream;
                _audioPlayer.Play();
                GD.Print($"{LogPrefix} Playing category '{categoryName}': {chosenPath} (Played total: {_playedAudioLines.Count})");
                return true;
            }
            else
            {
                _playedAudioLines.Remove(chosenPath);
                GD.PrintErr($"{LogPrefix} Failed to load stream at {chosenPath}");
                return false;
            }
        }
        catch (Exception ex)
        {
            _playedAudioLines.Remove(chosenPath);
            GD.PrintErr($"{LogPrefix} Error playing audio stream at {chosenPath}: {ex.Message}");
            return false;
        }
    }

    public void ResetPlayedAudioLines()
    {
        _playedAudioLines.Clear();
        _lastPlayedPath = "";
        GD.Print($"{LogPrefix} Reset all played audio lines tracking.");
    }

    public void MarkAudioLinePlayed(string filePath)
    {
        if (!string.IsNullOrEmpty(filePath))
        {
            _playedAudioLines.Add(filePath);
        }
    }

    public bool HasAudioLinePlayed(string filePath)
    {
        return !string.IsNullOrEmpty(filePath) && _playedAudioLines.Contains(filePath);
    }

    public int GetPlayedAudioLinesCount()
    {
        return _playedAudioLines.Count;
    }

    public Array<string> GetPlayedAudioLines()
    {
        var arr = new Array<string>();
        foreach (var path in _playedAudioLines)
        {
            arr.Add(path);
        }
        return arr;
    }

    private bool PlayCategoryGuarded(string categoryName, bool isHeckle = false, bool guaranteed = false, Dictionary? context = null)
    {
        if (!IsAnnouncerActiveForCurrentScene())
            return false;

        // STRICT RULE: Only ONE voice line may ever play on a single shot!
        if (_shotHadCommentary)
        {
            GD.Print($"{LogPrefix} Suppressed '{categoryName}' commentary - shot already had voice line.");
            return false;
        }

        if (isHeckle)
        {
            if (!IsHeckleActiveForCurrentScene())
                return false;

            if (!guaranteed && _random.NextDouble() >= BadShotHeckleProbability)
            {
                GD.Print($"{LogPrefix} Skipped heckle '{categoryName}' due to probability roll.");
                return false;
            }
        }
        else
        {
            if (!PraiseEnabled)
                return false;
        }

        _shotHadCommentary = true;
        return PlayCategory(categoryName, context);
    }

    public Dictionary GetAmbientContext(Dictionary? explicitContext = null)
    {
        var ctx = new Dictionary();

        var mode = GetCurrentGameMode();
        string modeStr = mode switch
        {
            SimGameMode.CoursePlay => "course_play",
            SimGameMode.Range => "range",
            SimGameMode.MiniGames => "minigames",
            _ => "menu"
        };
        ctx["game_mode"] = modeStr;

        if (mode == SimGameMode.CoursePlay)
        {
            try
            {
                var mpNode = GetTree()?.Root?.GetNodeOrNull("MultiplayerManager");
                if (mpNode != null)
                {
                    int holeIdx = 0;
                    var curHoleVar = mpNode.Get("current_hole_index");
                    if (curHoleVar.VariantType == Variant.Type.Int)
                    {
                        holeIdx = (int)curHoleVar;
                    }

                    int holeNum = holeIdx + 1;
                    ctx["hole_number"] = holeNum;
                    ctx["hole_range"] = holeIdx < 9 ? "front_nine" : "back_nine";

                    var holeIdsVar = mpNode.Get("hole_ids");
                    if (holeIdsVar.VariantType == Variant.Type.Array)
                    {
                        var holeIds = holeIdsVar.AsGodotArray();
                        ctx["holes_remaining"] = Math.Max(0, holeIds.Count - holeIdx);
                    }

                    if (mpNode.HasMethod("get_active_player"))
                    {
                        var activePVar = mpNode.Call("get_active_player");
                        if (activePVar.VariantType == Variant.Type.Dictionary)
                        {
                            var activeP = activePVar.AsGodotDictionary();
                            int holeStrokes = activeP.TryGetValue("strokes", out var sVal) ? Convert.ToInt32(sVal) : 0;
                            ctx["strokes"] = holeStrokes;
                            ctx["tee_box"] = (holeStrokes <= 1);

                            int totalDiff = 0;
                            if (activeP.TryGetValue("hole_scores", out var scoresVar) && scoresVar.VariantType == Variant.Type.Dictionary)
                            {
                                var scoresDict = scoresVar.AsGodotDictionary();
                                var holeInfoVar = mpNode.Get("hole_info");
                                if (holeInfoVar.VariantType == Variant.Type.Dictionary)
                                {
                                    var holeInfoDict = holeInfoVar.AsGodotDictionary();
                                    foreach (var kvp in scoresDict)
                                    {
                                        int sc = Convert.ToInt32(kvp.Value);
                                        if (sc > 0)
                                        {
                                            int par = 4;
                                            if (holeInfoDict.TryGetValue(kvp.Key, out var hInfo) && hInfo.VariantType == Variant.Type.Dictionary)
                                            {
                                                var hDict = hInfo.AsGodotDictionary();
                                                if (hDict.TryGetValue("Par", out var parVal))
                                                    par = Convert.ToInt32(parVal);
                                            }
                                            totalDiff += (sc - par);
                                        }
                                    }
                                }
                            }

                            ctx["score_relative_to_par"] = totalDiff;
                            ctx["total_score_relative_to_par"] = totalDiff;

                            string status = totalDiff > 0 ? "over_par" : (totalDiff < 0 ? "under_par" : "even_par");
                            ctx["score_status"] = status;
                            ctx["overall_score"] = status;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                GD.Print($"{LogPrefix} Ambient context gathering exception: {ex.Message}");
            }
        }
        else if (mode == SimGameMode.Range)
        {
            ctx["score_relative_to_par"] = 0;
            ctx["total_score_relative_to_par"] = 0;
            ctx["score_status"] = "even_par";
            ctx["overall_score"] = "even_par";
            ctx["tee_box"] = false;
        }

        if (explicitContext != null)
        {
            foreach (var kvp in explicitContext)
            {
                ctx[kvp.Key] = kvp.Value;
            }
        }

        return ctx;
    }

    private static bool MatchesQualifiers(System.Collections.Generic.Dictionary<string, object> qualifiers, Dictionary context)
    {
        foreach (var kvp in qualifiers)
        {
            string key = kvp.Key;
            object qualVal = kvp.Value;

            switch (key.ToLowerInvariant())
            {
                case "score_type":
                {
                    string targetType = qualVal.ToString()?.ToLowerInvariant() ?? "";
                    string actualType = GetStringSafe(context, "score_type").ToLowerInvariant();
                    int relToPar = (int)GetFloatSafe(context, "score_relative_to_par", 999.0f);

                    if (targetType == "birdie")
                    {
                        if (actualType != "birdie" && relToPar != -1) return false;
                    }
                    else if (targetType == "eagle")
                    {
                        if (actualType != "eagle" && relToPar != -2) return false;
                    }
                    else if (targetType == "double_bogey")
                    {
                        if (actualType != "double_bogey" && relToPar != 2) return false;
                    }
                    else if (targetType == "triple_bogey")
                    {
                        if (actualType != "triple_bogey" && relToPar < 3) return false;
                    }
                    else if (targetType == "under_par")
                    {
                        if (relToPar >= 0 && actualType != "birdie" && actualType != "eagle" && actualType != "albatross") return false;
                    }
                    else if (targetType == "over_bogey")
                    {
                        if (relToPar < 2) return false;
                    }
                    else if (actualType != targetType)
                    {
                        return false;
                    }
                    break;
                }
                case "min_score_relative_to_par":
                {
                    int requiredMin = Convert.ToInt32(qualVal);
                    int actualRel = (int)GetFloatSafe(context, "score_relative_to_par", -999.0f);
                    if (actualRel == -999)
                        actualRel = (int)GetFloatSafe(context, "total_score_relative_to_par", -999.0f);
                    if (actualRel < requiredMin) return false;
                    break;
                }
                case "max_score_relative_to_par":
                {
                    int requiredMax = Convert.ToInt32(qualVal);
                    int actualRel = (int)GetFloatSafe(context, "score_relative_to_par", 999.0f);
                    if (actualRel == 999)
                        actualRel = (int)GetFloatSafe(context, "total_score_relative_to_par", 999.0f);
                    if (actualRel > requiredMax) return false;
                    break;
                }
                case "score_status":
                {
                    string reqStatus = qualVal.ToString()?.ToLowerInvariant() ?? "";
                    string actStatus = GetStringSafe(context, "score_status").ToLowerInvariant();
                    int actualRel = (int)GetFloatSafe(context, "score_relative_to_par", -999.0f);
                    if (actualRel == -999)
                        actualRel = (int)GetFloatSafe(context, "total_score_relative_to_par", -999.0f);

                    if (reqStatus == "over_par")
                    {
                        if (actStatus != "over_par" && actualRel <= 0) return false;
                    }
                    else if (reqStatus == "under_par")
                    {
                        if (actStatus != "under_par" && actualRel >= 0) return false;
                    }
                    else if (reqStatus == "even_par")
                    {
                        if (actStatus != "even_par" && actualRel != 0) return false;
                    }
                    else if (actStatus != reqStatus)
                    {
                        return false;
                    }
                    break;
                }
                case "overall_score":
                {
                    string reqScore = qualVal.ToString()?.ToLowerInvariant() ?? "";
                    string actScore = GetStringSafe(context, "overall_score").ToLowerInvariant();
                    int actualRel = (int)GetFloatSafe(context, "total_score_relative_to_par", -999.0f);
                    if (actualRel == -999)
                        actualRel = (int)GetFloatSafe(context, "score_relative_to_par", -999.0f);

                    if (reqScore == "over_par")
                    {
                        if (actScore != "over_par" && actualRel <= 0) return false;
                    }
                    else if (reqScore == "under_par")
                    {
                        if (actScore != "under_par" && actualRel >= 0) return false;
                    }
                    else if (reqScore == "even_par")
                    {
                        if (actScore != "even_par" && actualRel != 0) return false;
                    }
                    else if (actScore != reqScore)
                    {
                        return false;
                    }
                    break;
                }
                case "game_mode":
                {
                    string reqMode = qualVal.ToString()?.ToLowerInvariant() ?? "";
                    string actMode = GetStringSafe(context, "game_mode").ToLowerInvariant();
                    if (actMode != reqMode) return false;
                    break;
                }
                case "hole_range":
                {
                    string reqRange = qualVal.ToString()?.ToLowerInvariant() ?? "";
                    string actRange = GetStringSafe(context, "hole_range").ToLowerInvariant();
                    int holeNum = (int)GetFloatSafe(context, "hole_number", -1.0f);

                    if (reqRange == "front_nine")
                    {
                        if (actRange == "back_nine" || (holeNum > 9 && holeNum != -1)) return false;
                    }
                    else if (reqRange == "back_nine")
                    {
                        if (actRange == "front_nine" || (holeNum <= 9 && holeNum != -1)) return false;
                    }
                    else if (actRange != reqRange)
                    {
                        return false;
                    }
                    break;
                }
                case "min_hole":
                {
                    int minHole = Convert.ToInt32(qualVal);
                    int holeNum = (int)GetFloatSafe(context, "hole_number", -1.0f);
                    if (holeNum != -1 && holeNum < minHole) return false;
                    break;
                }
                case "max_hole":
                {
                    int maxHole = Convert.ToInt32(qualVal);
                    int holeNum = (int)GetFloatSafe(context, "hole_number", -1.0f);
                    if (holeNum != -1 && holeNum > maxHole) return false;
                    break;
                }
                case "surface":
                {
                    string reqSurf = qualVal.ToString()?.ToLowerInvariant() ?? "";
                    string actSurf = GetStringSafe(context, "surface").ToLowerInvariant();
                    bool isInSand = GetBoolSafe(context, "is_in_sand", false);
                    bool isInWater = GetBoolSafe(context, "is_in_water", false);
                    if (reqSurf == "sand" && !isInSand && actSurf != "sand") return false;
                    if (reqSurf == "water" && !isInWater && actSurf != "water") return false;
                    if (reqSurf != "sand" && reqSurf != "water" && actSurf != reqSurf) return false;
                    break;
                }
                case "tee_box":
                {
                    bool reqTeeBox = Convert.ToBoolean(qualVal);
                    bool actTeeBox = GetBoolSafe(context, "tee_box", false);
                    bool teeShot = GetBoolSafe(context, "tee_shot", false);
                    int strokes = (int)GetFloatSafe(context, "strokes", -1.0f);
                    if (strokes == 1 || teeShot) actTeeBox = true;
                    if (actTeeBox != reqTeeBox) return false;
                    break;
                }
                case "strokes":
                {
                    int requiredStrokes = Convert.ToInt32(qualVal);
                    int actualStrokes = (int)GetFloatSafe(context, "strokes", -1.0f);
                    if (actualStrokes != requiredStrokes) return false;
                    break;
                }
                case "gir":
                {
                    bool requiredGir = Convert.ToBoolean(qualVal);
                    bool actualGir = GetBoolSafe(context, "gir", false);
                    if (actualGir != requiredGir) return false;
                    break;
                }
                case "birdie_chance":
                {
                    bool requiredChance = Convert.ToBoolean(qualVal);
                    bool actualChance = GetBoolSafe(context, "birdie_chance", false);
                    if (actualChance != requiredChance) return false;
                    break;
                }
                case "tee_shot":
                {
                    bool requiredTee = Convert.ToBoolean(qualVal);
                    bool actualTee = GetBoolSafe(context, "tee_shot", false);
                    int actualStrokes = (int)GetFloatSafe(context, "strokes", -1.0f);
                    if (actualStrokes == 1) actualTee = true;
                    if (actualTee != requiredTee) return false;
                    break;
                }
                case "tree_hit_type":
                {
                    string requiredHit = qualVal.ToString()?.ToLowerInvariant() ?? "";
                    string actualHit = GetStringSafe(context, "tree_hit_type").ToLowerInvariant();

                    if (requiredHit == "trunk")
                    {
                        if (actualHit != "trunk") return false;
                    }
                    else if (requiredHit == "leaves" || requiredHit == "branches")
                    {
                        if (actualHit != "leaves" && actualHit != "branches") return false;
                    }
                    else if (actualHit != requiredHit)
                    {
                        return false;
                    }
                    break;
                }
                case "close_to_pin":
                {
                    bool requiredClose = Convert.ToBoolean(qualVal);
                    bool actualClose = GetBoolSafe(context, "close_to_pin", false);
                    float distYds = GetFloatSafe(context, "distance_to_pin_yards", 999.0f);
                    if (distYds <= 4.0f) actualClose = true;
                    if (actualClose != requiredClose) return false;
                    break;
                }
                default:
                {
                    if (context.TryGetValue(key, out var ctxVal))
                    {
                        string ctxStr = ctxVal.AsString()?.ToLowerInvariant() ?? "";
                        string qStr = qualVal.ToString()?.ToLowerInvariant() ?? "";
                        if (ctxStr != qStr) return false;
                    }
                    else
                    {
                        return false;
                    }
                    break;
                }
            }
        }

        return true;
    }

    public override void _Process(double delta)
    {
        if (!IsAnnouncerActiveForCurrentScene() || !IsHeckleActiveForCurrentScene()) return;

        // Don't play idle comments if audio is already playing
        if (_audioPlayer != null && _audioPlayer.Playing)
        {
            _idleTimer = 0.0f;
            return;
        }

        var currentScene = GetTree().CurrentScene;
        if (currentScene == null) return;

        // Simple check to ensure we are in a golf game and not the main menu / screens
        if (GetCurrentGameMode() == SimGameMode.MenuOrOther)
        {
            _idleTimer = 0.0f;
            return;
        }

        // Check if there is a player/ball or MultiplayerManager in the scene
        bool gameActive = currentScene.HasNode("Player") || currentScene.HasNode("MultiplayerManager");
        if (!gameActive)
        {
            _idleTimer = 0.0f;
            return;
        }

        // Only run idle timer when the ball is at rest
        var playerNode = currentScene.GetNodeOrNull("Player");
        if (playerNode != null)
        {
            var ball = playerNode.GetNodeOrNull("ball");
            if (ball != null)
            {
                int ballState = (int)ball.Get("state");
                if (ballState != 0) // REST is 0
                {
                    _idleTimer = 0.0f;
                    return;
                }
            }
        }

        _idleTimer += (float)delta;
        if (_idleTimer >= IdleAnnouncementInterval)
        {
            _idleTimer = 0.0f;
            SpeakIdleComment();
        }
    }

    public void SpeakIdleComment()
    {
        SpeakIdleComment(null);
    }

    public void SpeakIdleComment(Dictionary? context)
    {
        if (!IsHeckleActiveForCurrentScene()) return;
        var ambient = GetAmbientContext(context);
        PlayCategory("player_afk_heckles", ambient);
    }

    public void SpeakHomeButtonHeckle()
    {
        SpeakHomeButtonHeckle(null);
    }

    public void SpeakHomeButtonHeckle(Dictionary? context)
    {
        if (!IsHeckleActiveForCurrentScene()) return;
        _idleTimer = 0.0f;
        var ambient = GetAmbientContext(context);
        PlayCategoryGuarded("home_button_popup", isHeckle: true, guaranteed: true, context: ambient);
    }

    public void SpeakHecklesEnabled()
    {
        _idleTimer = 0.0f;
        PlayCategory("heckles_enabled");
    }

    public void SpeakHecklesDisabled()
    {
        _idleTimer = 0.0f;
        PlayCategory("heckles_disabled");
    }

    public void SpeakSettingsOpened()
    {
        SpeakSettingsOpened(null);
    }

    public void SpeakSettingsOpened(Dictionary? context)
    {
        if (!IsHeckleActiveForCurrentScene()) return;

        _idleTimer = 0.0f;
        var ambient = GetAmbientContext(context);
        PlayCategory("settings_opened", ambient);
    }

    public void AnnounceLaunch(Dictionary shotData)
    {
        if (!IsAnnouncerActiveForCurrentScene()) return;
        _idleTimer = 0.0f; // Reset idle timer!
        _shotHadCommentary = false; // Reset per-shot commentary tracking
        _ballHitTree = false; // Reset per-shot tree collision tracking

        float speedMph = GetFloatSafe(shotData, "Speed");
        float vla = GetFloatSafe(shotData, "VLA");
        string shotType = GetStringSafe(shotData, "ShotType");

        bool isPutt = shotType.Equals("putt", StringComparison.OrdinalIgnoreCase);

        // Putts are evaluated after they come to rest, not at launch
        if (isPutt)
        {
            return;
        }

        var launchContext = new Dictionary
        {
            ["tee_shot"] = true
        };

        // Check for severe launch catastrophes ONLY (pop-up skyball, wormburner skittering along the turf)
        bool isWormburner = vla < 3.0f && speedMph > 40.0f;
        bool isSkyball = vla > 35.0f && speedMph > 80.0f;

        if (isWormburner)
        {
            PlayCategoryGuarded("really_short_shots", isHeckle: true, guaranteed: false, launchContext);
            return;
        }

        if (isSkyball)
        {
            PlayCategoryGuarded("crazy_high_apex", isHeckle: true, guaranteed: false, launchContext);
            return;
        }
    }

    public void EvaluateShot(Dictionary shotData, int surfaceType, float distanceToPinYards, bool isInSand = false, bool isInWater = false, bool hitTree = false)
    {
        EvaluateShot(shotData, surfaceType, distanceToPinYards, isInSand, isInWater, hitTree, null);
    }

    public void EvaluateShot(Dictionary shotData, int surfaceType, float distanceToPinYards, bool isInSand, bool isInWater, bool hitTree, Dictionary? gameContext)
    {
        if (!IsAnnouncerActiveForCurrentScene()) return;
        _idleTimer = 0.0f; // Reset idle timer!

        if (hitTree)
        {
            _ballHitTree = true;
        }

        // 1. Strict single-commentary guard:
        // If a voice line already played for this shot (launch heckle, tree heckle, etc.), return immediately!
        if (_shotHadCommentary)
        {
            GD.Print($"{LogPrefix} EvaluateShot: Shot already had commentary. Suppressing rest evaluation.");
            return;
        }

        // Resolve game context (strokes, par, GIR, birdie chance, etc.)
        int strokes = 1;
        int par = 0;
        bool isGir = false;
        bool birdieChance = false;
        bool teeShot = false;

        if (gameContext != null)
        {
            strokes = (int)GetFloatSafe(gameContext, "strokes", 1.0f);
            par = (int)GetFloatSafe(gameContext, "par", 0.0f);
            isGir = GetBoolSafe(gameContext, "gir", false);
            birdieChance = GetBoolSafe(gameContext, "birdie_chance", false);
            teeShot = GetBoolSafe(gameContext, "tee_shot", strokes == 1);
        }
        else
        {
            var mpMgr = GetNodeOrNull("/root/MultiplayerManager");
            if (mpMgr != null)
            {
                var players = mpMgr.Get("players");
                if (players.VariantType == Variant.Type.Array && ((Godot.Collections.Array)players).Count > 0)
                {
                    var activeP = mpMgr.Call("get_active_player");
                    if (activeP.VariantType == Variant.Type.Dictionary)
                    {
                        var pDict = (Dictionary)activeP;
                        // Prior to record_shot, the stroke currently finishing is strokes + 1
                        strokes = (int)GetFloatSafe(pDict, "strokes", 0.0f) + 1;
                    }

                    var holeIds = mpMgr.Get("hole_ids");
                    var holeInfo = mpMgr.Get("hole_info");
                    var curHoleIdx = (int)mpMgr.Get("current_hole_index");
                    if (holeIds.VariantType == Variant.Type.Array && holeInfo.VariantType == Variant.Type.Dictionary)
                    {
                        var hArray = (Godot.Collections.Array)holeIds;
                        if (curHoleIdx >= 0 && curHoleIdx < hArray.Count)
                        {
                            string hId = hArray[curHoleIdx].AsString();
                            var hDict = (Dictionary)holeInfo;
                            if (hDict.TryGetValue(hId, out var curHoleVar) && curHoleVar.VariantType == Variant.Type.Dictionary)
                            {
                                par = (int)GetFloatSafe((Dictionary)curHoleVar, "Par", 4.0f);
                            }
                        }
                    }
                }
            }

            teeShot = (strokes == 1);
            if (par >= 3)
            {
                isGir = (strokes <= par - 2);
                birdieChance = isGir;
            }
        }

        bool closeToPin = (distanceToPinYards <= 4.0f);

        var context = new Dictionary
        {
            ["strokes"] = strokes,
            ["par"] = par,
            ["score_relative_to_par"] = strokes - par,
            ["gir"] = isGir,
            ["birdie_chance"] = birdieChance,
            ["tee_shot"] = teeShot,
            ["close_to_pin"] = closeToPin,
            ["distance_to_pin_yards"] = distanceToPinYards
        };

        float speedMph = GetFloatSafe(shotData, "Speed");
        float totalDistYards = GetFloatSafe(shotData, "TotalDistance") * 1.09361f;
        float offlineYards = GetFloatSafe(shotData, "SideDistance") * 1.09361f;
        float targetDistYards = GetFloatSafe(shotData, "TargetDistance") * 1.09361f;
        string shotType = GetStringSafe(shotData, "ShotType");

        bool isPutt = shotType.Equals("putt", StringComparison.OrdinalIgnoreCase);

        // --- PUTTING EVALUATION ---
        // Note: good_shot_green is strictly for approach shots, NOT putts.
        if (isPutt)
        {
            if (totalDistYards < 2.0f && distanceToPinYards > 8.0f) // Left way short
            {
                PlayCategoryGuarded("terrible_putts_off_green", isHeckle: true, guaranteed: false, context);
            }
            else if (distanceToPinYards > 10.0f) // Very far lag putt (>30 ft away)
            {
                PlayCategoryGuarded("terrible_putts_off_green", isHeckle: true, guaranteed: false, context);
            }
            return;
        }

        // --- FULL SHOT EVALUATION ---

        // 1. Water Hazard (100% Heckle guarantee)
        if (isInWater)
        {
            PlayCategoryGuarded("ball_in_water", isHeckle: true, guaranteed: true, context);
            return;
        }

        // 2. Sand / Bunker (100% Heckle guarantee)
        if (isInSand || surfaceType == 5)
        {
            PlayCategoryGuarded("ball_in_sand", isHeckle: true, guaranteed: true, context);
            return;
        }

        // 3. Tree collision guard: NEVER praise a shot that hit a tree!
        if (_ballHitTree)
        {
            GD.Print($"{LogPrefix} EvaluateShot: Ball struck a tree during flight. Suppressing all praise.");
            return;
        }

        // Surface definitions:
        // 0: Fairway, 1: FairwaySoft, 2: Rough, 3: Firm, 4: Green, 5: Bunker
        bool isOnGreen = (surfaceType == 4);
        bool isOnFairway = (surfaceType == 0 || surfaceType == 1 || surfaceType == 3);
        bool isOnShortGrass = isOnGreen || isOnFairway;

        // Determine intended target distance (Aim-Awareness)
        float effectiveTargetYards = targetDistYards > 5.0f ? targetDistYards : (distanceToPinYards > 5.0f ? distanceToPinYards : 0.0f);

        // 4. Bad Shot Outliers (Aim-Aware Chunks, Duffs, Severe Offlines)
        bool isChunked = effectiveTargetYards > 50.0f && totalDistYards < 25.0f && totalDistYards < effectiveTargetYards * 0.35f;
        bool isDuff = false;
        if (effectiveTargetYards > 35.0f)
        {
            isDuff = totalDistYards < 18.0f && totalDistYards < effectiveTargetYards * 0.35f && speedMph > 20.0f;
        }
        else if (effectiveTargetYards <= 0.0f)
        {
            isDuff = totalDistYards < 15.0f && speedMph > 40.0f;
        }

        // Severe Offline / Slice / Hook into Rough:
        bool isSevereOffline = !isOnShortGrass && (Math.Abs(offlineYards) >= 45.0f || (totalDistYards > 40.0f && Math.Abs(offlineYards) >= 30.0f && (Math.Abs(offlineYards) / totalDistYards) > 0.28f));

        if (isChunked || isDuff)
        {
            PlayCategoryGuarded("really_short_shots", isHeckle: true, guaranteed: false, context);
            return;
        }

        if (isSevereOffline)
        {
            if (offlineYards > 0.0f)
            {
                PlayCategoryGuarded("slice_into_rough", isHeckle: true, guaranteed: false, context);
            }
            else
            {
                PlayCategoryGuarded("hook_into_rough", isHeckle: true, guaranteed: false, context);
            }
            return;
        }

        // 5. PRAISE EVALUATION (Good Shots)
        // STRICT RULE: NEVER praise if ball is in the rough or on bad surfaces!
        if (!isOnShortGrass)
        {
            GD.Print($"{LogPrefix} EvaluateShot: Ball landed on surface {surfaceType} (not short grass). No praise.");
            return;
        }

        // A. Green Praise (good_shot_green: strictly for approach shots landing on green!)
        if (isOnGreen)
        {
            // Close approach to pin on green
            if (distanceToPinYards < 4.0f && totalDistYards > 15.0f)
            {
                PlayCategoryGuarded("good_shot_green", isHeckle: false, guaranteed: false, context);
                return;
            }

            // Target-reaching approach shot onto green
            if (effectiveTargetYards > 15.0f && totalDistYards >= effectiveTargetYards * 0.70f)
            {
                PlayCategoryGuarded("good_shot_green", isHeckle: false, guaranteed: false, context);
                return;
            }
        }

        // B. Fairway Praise (good_shot_fairway: good drive down middle or target-reaching fairway shot)
        if (isOnFairway)
        {
            // Long drive with good control (must be on fairway and well-centered!)
            if (totalDistYards > 240.0f && Math.Abs(offlineYards) < 25.0f)
            {
                PlayCategoryGuarded("good_shot_fairway", isHeckle: false, guaranteed: false, context);
                return;
            }

            // Target-reaching fairway shot
            if (effectiveTargetYards > 40.0f)
            {
                bool reachedTarget = totalDistYards >= effectiveTargetYards * 0.70f;
                bool isReasonablyOnline = Math.Abs(offlineYards) < 25.0f;

                if (reachedTarget && isReasonablyOnline)
                {
                    PlayCategoryGuarded("good_shot_fairway", isHeckle: false, guaranteed: false, context);
                    return;
                }
            }
        }
    }

    public void SpeakMulliganHeckle()
    {
        SpeakMulliganHeckle(null);
    }

    public void SpeakMulliganHeckle(Dictionary? context)
    {
        if (!IsHeckleActiveForCurrentScene()) return;

        ulong now = Time.GetTicksMsec();
        if (now - _lastMulliganMsec < 1500) return;
        _lastMulliganMsec = now;

        _idleTimer = 0.0f; // Reset idle timer!
        _shotHadCommentary = false; // Reset so shot commentary tracking is cleared
        var ambient = GetAmbientContext(context);
        PlayCategory("mulligan_heckles", ambient);
    }

    public void SpeakTreeHeckle()
    {
        SpeakTreeHeckle("trunk");
    }

    public void SpeakTreeHeckle(string hitType)
    {
        _ballHitTree = true;
        _idleTimer = 0.0f; // Reset idle timer!

        if (_shotHadCommentary)
        {
            GD.Print($"{LogPrefix} Suppressed tree heckle - shot already had launch commentary.");
            return;
        }

        var context = new Dictionary
        {
            ["tree_hit_type"] = hitType
        };

        PlayCategoryGuarded("hitting_or_going_through_trees", isHeckle: true, guaranteed: true, context);
    }

    public void AnnounceHoleScore(string playerName, int strokes, int par)
    {
        if (!IsAnnouncerActiveForCurrentScene()) return;
        _idleTimer = 0.0f; // Reset idle timer!

        int scoreType = strokes - par;
        string scoreTypeName = scoreType switch
        {
            <= -3 => "albatross",
            -2 => "eagle",
            -1 => "birdie",
            0 => "par",
            1 => "bogey",
            2 => "double_bogey",
            3 => "triple_bogey",
            _ => "over_bogey"
        };

        var context = new Dictionary
        {
            ["strokes"] = strokes,
            ["par"] = par,
            ["score_relative_to_par"] = scoreType,
            ["score_type"] = scoreTypeName
        };

        if (strokes == 8)
        {
            context["strokes"] = 8;
        }

        var ambient = GetAmbientContext(context);

        if (scoreType >= 2)
        {
            // Heckle above par: only on double bogey or worse (scoreType >= 2)
            if (IsHeckleActiveForCurrentScene())
                PlayCategoryGuarded("over_bogey_heckles", isHeckle: true, guaranteed: true, ambient);
        }
        else if (scoreType < 0) // Under par (Birdie, Eagle, etc.)
        {
            if (PraiseEnabled)
                PlayCategoryGuarded("under_par", isHeckle: false, guaranteed: true, ambient);
        }
    }

    private static bool GetBoolSafe(Dictionary dict, string key, bool defaultValue = false)
    {
        if (dict.TryGetValue(key, out var val))
        {
            if (val.VariantType == Variant.Type.Bool)
            {
                return (bool)val;
            }
            if (val.VariantType == Variant.Type.Int)
            {
                return ((int)val) != 0;
            }
        }
        return defaultValue;
    }

    private static float GetFloatSafe(Dictionary dict, string key, float defaultValue = 0.0f)
    {
        if (dict.TryGetValue(key, out var val))
        {
            if (val.VariantType == Variant.Type.Float || val.VariantType == Variant.Type.Int)
            {
                return (float)val;
            }
        }
        return defaultValue;
    }

    private static string GetStringSafe(Dictionary dict, string key, string defaultValue = "")
    {
        if (dict.TryGetValue(key, out var val) && val.VariantType != Variant.Type.Nil)
        {
            return val.AsString() ?? defaultValue;
        }
        return defaultValue;
    }
}
