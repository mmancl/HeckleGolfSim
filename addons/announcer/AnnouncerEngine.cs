using System;
using System.Collections.Generic;
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

    // Audio file cache: Category -> List of resource paths
    private readonly System.Collections.Generic.Dictionary<string, List<string>> _audioCache = new(StringComparer.OrdinalIgnoreCase);
    private string _lastPlayedPath = "";

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
        string hecklerDir = "res://assets/audio/heckler";
        if (!DirAccess.DirExistsAbsolute(hecklerDir)) return;

        var subdirs = DirAccess.GetDirectoriesAt(hecklerDir);
        if (subdirs == null) return;

        foreach (var dir in subdirs)
        {
            GetAvailableClipsForCategory(dir);
        }
    }

    public List<string> GetAvailableClipsForCategory(string categoryName)
    {
        if (_audioCache.TryGetValue(categoryName, out var cached) && cached.Count > 0)
        {
            return cached;
        }

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

    public bool PlayCategory(string categoryName)
    {
        var clips = GetAvailableClipsForCategory(categoryName);
        if (clips == null || clips.Count == 0)
        {
            GD.Print($"{LogPrefix} No audio files found in res://assets/audio/heckler/{categoryName}");
            return false;
        }

        string chosenPath;
        if (clips.Count == 1)
        {
            chosenPath = clips[0];
        }
        else
        {
            int idx = _random.Next(clips.Count);
            if (clips[idx] == _lastPlayedPath)
            {
                idx = (idx + 1) % clips.Count;
            }
            chosenPath = clips[idx];
        }

        try
        {
            var stream = GD.Load<AudioStream>(chosenPath);
            if (stream != null)
            {
                _lastPlayedPath = chosenPath;
                _audioPlayer.Stream = stream;
                _audioPlayer.Play();
                GD.Print($"{LogPrefix} Playing category '{categoryName}': {chosenPath}");
                return true;
            }
            else
            {
                GD.PrintErr($"{LogPrefix} Failed to load stream at {chosenPath}");
                return false;
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Error playing audio stream at {chosenPath}: {ex.Message}");
            return false;
        }
    }

    private bool PlayCategoryGuarded(string categoryName, bool isHeckle = false, bool guaranteed = false)
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
        return PlayCategory(categoryName);
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
        PlayCategory("player_afk_heckles");
    }

    public void SpeakHomeButtonHeckle()
    {
        if (!IsHeckleActiveForCurrentScene()) return;
        _idleTimer = 0.0f;
        PlayCategoryGuarded("home_button_popup", isHeckle: true, guaranteed: true);
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
        var mode = GetCurrentGameMode();
        bool allow = mode switch
        {
            SimGameMode.CoursePlay => HeckleCoursePlay,
            SimGameMode.Range => HeckleRange,
            SimGameMode.MiniGames => HeckleMiniGames,
            _ => HeckleCoursePlay || HeckleRange || HeckleMiniGames
        };

        if (!allow) return;

        _idleTimer = 0.0f;
        PlayCategory("settings_opened");
    }

    public void AnnounceLaunch(Dictionary shotData)
    {
        if (!IsAnnouncerActiveForCurrentScene()) return;
        _idleTimer = 0.0f; // Reset idle timer!
        _shotHadCommentary = false; // Reset per-shot commentary tracking
        _ballHitTree = false; // Reset per-shot tree collision tracking

        float speedMph = shotData.TryGetValue("Speed", out var speedVal) ? (float)speedVal : 0.0f;
        float vla = shotData.TryGetValue("VLA", out var vlaVal) ? (float)vlaVal : 0.0f;
        string shotType = shotData.TryGetValue("ShotType", out var typeVal) ? (string)typeVal : "";

        bool isPutt = shotType.Equals("putt", StringComparison.OrdinalIgnoreCase);

        // Putts are evaluated after they come to rest, not at launch
        if (isPutt)
        {
            return;
        }

        // Check for severe launch catastrophes ONLY (pop-up skyball, wormburner skittering along the turf)
        bool isWormburner = vla < 3.0f && speedMph > 40.0f;
        bool isSkyball = vla > 35.0f && speedMph > 80.0f;

        if (isWormburner)
        {
            PlayCategoryGuarded("really_short_shots", isHeckle: true, guaranteed: false);
            return;
        }

        if (isSkyball)
        {
            PlayCategoryGuarded("crazy_high_apex", isHeckle: true, guaranteed: false);
            return;
        }
    }

    public void EvaluateShot(Dictionary shotData, int surfaceType, float distanceToPinYards, bool isInSand = false, bool isInWater = false, bool hitTree = false)
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

        float speedMph = shotData.TryGetValue("Speed", out var speedVal) ? (float)speedVal : 0.0f;
        float totalDistYards = shotData.TryGetValue("TotalDistance", out var distVal) ? (float)distVal * 1.09361f : 0.0f;
        float offlineYards = shotData.TryGetValue("SideDistance", out var sideVal) ? (float)sideVal * 1.09361f : 0.0f;
        float targetDistYards = shotData.TryGetValue("TargetDistance", out var targetVal) ? (float)targetVal * 1.09361f : 0.0f;
        string shotType = shotData.TryGetValue("ShotType", out var typeVal) ? (string)typeVal : "";

        bool isPutt = shotType.Equals("putt", StringComparison.OrdinalIgnoreCase);

        // --- PUTTING EVALUATION ---
        // Note: good_shot_green is strictly for approach shots, NOT putts.
        if (isPutt)
        {
            if (totalDistYards < 2.0f && distanceToPinYards > 8.0f) // Left way short
            {
                PlayCategoryGuarded("terrible_putts_off_green", isHeckle: true, guaranteed: false);
            }
            else if (distanceToPinYards > 10.0f) // Very far lag putt (>30 ft away)
            {
                PlayCategoryGuarded("terrible_putts_off_green", isHeckle: true, guaranteed: false);
            }
            return;
        }

        // --- FULL SHOT EVALUATION ---

        // 1. Water Hazard (100% Heckle guarantee)
        if (isInWater)
        {
            PlayCategoryGuarded("ball_in_water", isHeckle: true, guaranteed: true);
            return;
        }

        // 2. Sand / Bunker (100% Heckle guarantee)
        if (isInSand || surfaceType == 5)
        {
            PlayCategoryGuarded("ball_in_sand", isHeckle: true, guaranteed: true);
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
            PlayCategoryGuarded("really_short_shots", isHeckle: true, guaranteed: false);
            return;
        }

        if (isSevereOffline)
        {
            if (offlineYards > 0.0f)
            {
                PlayCategoryGuarded("slice_into_rough", isHeckle: true, guaranteed: false);
            }
            else
            {
                PlayCategoryGuarded("hook_into_rough", isHeckle: true, guaranteed: false);
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
                PlayCategoryGuarded("good_shot_green", isHeckle: false, guaranteed: false);
                return;
            }

            // Target-reaching approach shot onto green
            if (effectiveTargetYards > 15.0f && totalDistYards >= effectiveTargetYards * 0.70f)
            {
                PlayCategoryGuarded("good_shot_green", isHeckle: false, guaranteed: false);
                return;
            }
        }

        // B. Fairway Praise (good_shot_fairway: good drive down middle or target-reaching fairway shot)
        if (isOnFairway)
        {
            // Long drive with good control (must be on fairway and well-centered!)
            if (totalDistYards > 240.0f && Math.Abs(offlineYards) < 25.0f)
            {
                PlayCategoryGuarded("good_shot_fairway", isHeckle: false, guaranteed: false);
                return;
            }

            // Target-reaching fairway shot
            if (effectiveTargetYards > 40.0f)
            {
                bool reachedTarget = totalDistYards >= effectiveTargetYards * 0.70f;
                bool isReasonablyOnline = Math.Abs(offlineYards) < 25.0f;

                if (reachedTarget && isReasonablyOnline)
                {
                    PlayCategoryGuarded("good_shot_fairway", isHeckle: false, guaranteed: false);
                    return;
                }
            }
        }
    }

    public void SpeakMulliganHeckle()
    {
        if (!IsHeckleActiveForCurrentScene()) return;

        ulong now = Time.GetTicksMsec();
        if (now - _lastMulliganMsec < 1500) return;
        _lastMulliganMsec = now;

        _idleTimer = 0.0f; // Reset idle timer!
        _shotHadCommentary = false; // Reset so shot commentary tracking is cleared
        PlayCategory("mulligan_heckles");
    }

    public void SpeakTreeHeckle()
    {
        _ballHitTree = true;
        _idleTimer = 0.0f; // Reset idle timer!

        if (_shotHadCommentary)
        {
            GD.Print($"{LogPrefix} Suppressed tree heckle - shot already had launch commentary.");
            return;
        }

        PlayCategoryGuarded("hitting_or_going_through_trees", isHeckle: true, guaranteed: true);
    }

    public void AnnounceHoleScore(string playerName, int strokes, int par)
    {
        if (!IsAnnouncerActiveForCurrentScene()) return;
        _idleTimer = 0.0f; // Reset idle timer!

        int scoreType = strokes - par;

        if (scoreType >= 2)
        {
            // Heckle above par: only on double bogey or worse (scoreType >= 2)
            if (IsHeckleActiveForCurrentScene())
                PlayCategoryGuarded("over_bogey_heckles", isHeckle: true, guaranteed: true);
        }
        else if (scoreType < 0) // Under par (Birdie, Eagle, etc.)
        {
            if (PraiseEnabled)
                PlayCategoryGuarded("under_par", isHeckle: false, guaranteed: true);
        }
    }
}
