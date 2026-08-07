using System;
using Godot;
using Godot.Collections;

namespace HeckleLinks.Announcer;

[GlobalClass]
public partial class AnnouncerEngine : Node
{
    private static readonly string LogPrefix = "[AnnouncerEngine]";

    [Export] public bool AnnouncerEnabled { get; set; } = true;
    [Export] public bool PraiseEnabled { get; set; } = true;
    [Export] public bool HeckleEnabled { get; set; } = true;
    [Export] public string ActiveVoice { get; set; } = "";
    [Export] public float Pitch { get; set; } = 1.0f;
    [Export] public float Rate { get; set; } = 1.0f;

    // Audio stream player child
    private AudioStreamPlayer _audioPlayer = null!;

    // Idle announcement timer
    private float _idleTimer = 0.0f;
    private const float IdleAnnouncementInterval = 45.0f; // 45 seconds

    // 1. Crushed / Overshot Aim
    private readonly string[] _overshotCrushedTemplates = new[]
    {
        "They got all of that one. They got so much, I think it went further than planned.",
        "Well, that ball was struck with pure, unadulterated anger. It's completely overshot the target.",
        "Good heavens, he absolutely vaporized that. I hope it has a passport, because it's in a different territory now.",
        "I think he forgot his own strength there. That ball is way past the landing zone.",
        "Well, he caught that one flush. And by flush, I mean it's currently orbiting the moon.",
        "They got all of that. Way more than they bargained for, I suspect.",
        "Struck with authority! A bit too much authority, actually. It's sailed right past the target.",
        "That went so far past the aim point, I think it has its own zip code now.",
        "A majestic strike, really. Too bad it's twenty yards past where he actually wanted it.",
        "Well, the good news is he hit it perfectly. The bad news is he's now in the next fairway."
    };

    // 2. Offline / Slice / Curve
    private readonly string[] _offlineSarcasticTemplates = new[]
    {
        "That curve was so sharp, I think the ball is trying to look back at the tee box.",
        "A spectacular slice. If we were playing boomerang, he'd be a champion.",
        "That ball didn't just fade, it migrated for the winter.",
        "I've seen less dramatic curves on a mountain road. That is way offline.",
        "Oh, a beautiful shot... if the hole was located in the parking lot.",
        "He's managed to find an angle of departure that defies modern physics.",
        "That slice had so much bend, I think it just registered as a hurricane.",
        "Offline right and fading. He's playing lawn darts, not golf.",
        "A magnificent hook. Or slice. Either way, it's not on our map anymore.",
        "Well, that ball is heading in a direction usually reserved for fleeing animals."
    };

    // 3. Sand / Bunker
    private readonly string[] _sandTemplates = new[]
    {
        "Well, grab your sunscreen and a bucket, because you're going to the beach.",
        "In the sand. I hope he brought a bucket and shovel to build a sandcastle.",
        "Right in the bunker. Don't forget your beach towel and a cold drink.",
        "A lovely trip to the beach. Too bad he forgot his swim trunks.",
        "He's found the kitty litter. Let's see if he can dig his way out.",
        "Ah, the sand. Perfect place for a picnic, terrible place for a golf ball.",
        "He's landed in the bunker. Better apply some SPF 50 before the next shot.",
        "A classic beach holiday, minus the ocean view.",
        "Buried in the sand. I think I see a crab near his ball.",
        "Well, he's in the bunker. Time to get dirty and play in the sandbox."
    };

    // 4. Water
    private readonly string[] _waterTemplates = new[]
    {
        "You're going to need scuba gear to find that one.",
        "Splash! I think he just awakened the local fish population.",
        "Well, that one is sleeping with the fishes now.",
        "I hope that ball knows how to swim, because it just took a deep dive.",
        "A beautiful splash. He should get extra points for diving style.",
        "That's in the drink. Call the Coast Guard, we have a ball overboard.",
        "He's found the water hazard. I hope he brought a fishing pole.",
        "Submarine shot! It's currently search-and-rescue down there.",
        "Waterlogged! That ball is officially retired from active duty.",
        "A wet and wild adventure. Next time, try aiming for dry land."
    };

    // 5. Long Putt Made
    private readonly string[] _longPuttTemplates = new[]
    {
        "Unbelievable! He drained it from way downtown!",
        "What a magnificent putt! That rolled like it was on a pool table.",
        "Are you kidding me? From that distance? What a sensational putt!",
        "Absolute magic on the green! He read that break perfectly.",
        "In the bottom of the cup! That was a masterclass in putting.",
        "Oh, the crowd goes wild! What a phenomenal stroke from out there.",
        "He dropped it! A truly majestic putt that never looked like missing.",
        "Talk about nerves of steel. That was an absolute beauty of a putt.",
        "Boom! Right in the center. He's got the flatstick working today.",
        "An absolute monster of a putt! Well played, sir."
    };

    // 6. Above Par
    private readonly string[] _aboveParTemplates = new[]
    {
        "Well, that scorecard is starting to look like a phone number.",
        "Oof, above par. I was worried we'd run out of daylight before he finished.",
        "That took a while. I think my hair grew an inch while you were playing that hole.",
        "A bit of a struggle there. Have you considered taking up gardening?",
        "Above par. That wasn't golf, that was a scenic hike with lots of swings.",
        "They say golf builds character. You must have built a mansion on that hole.",
        "I lost count of the strokes. Did we start this hole yesterday?",
        "Well, the score is high, but look on the bright side... actually, there is no bright side.",
        "Double bogey or worse. A performance best forgotten, or at least deleted from memory.",
        "Oof. That was a marathon, not a sprint. A very, very slow marathon."
    };

    // 7. Par
    private readonly string[] _parTemplates = new[]
    {
        "A steady par. Nothing to write home about, but it keeps the scorecard clean.",
        "Par. Safe, sensible, and completely unexciting.",
        "He walks away with a par. A decent result, all things considered.",
        "Right on par. It gets the job done, I suppose.",
        "A solid par. Not a highlight reel shot, but no damage done.",
        "Par is your friend, even if it's a rather boring friend.",
        "A respectable par. No drama, just good old-fashioned golf.",
        "Well, it's a par. Neither heroic nor disastrous.",
        "A par. Keeps you right in the middle of the pack.",
        "Par. The breakfast of champions, or at least the oatmeal."
    };

    // 8. Under Par
    private readonly string[] _underParTemplates = new[]
    {
        "Birdie or better! Now that is how you play this game!",
        "Sensational! A brilliant under-par score on this hole!",
        "Outstanding golf! He absolutely tore this hole apart.",
        "Under par! That is world-class play right there.",
        "Beautifully played! An under-par score that belongs on the pro tour.",
        "Absolutely stellar! He made that hole look incredibly easy.",
        "Under par! That scorecard is looking very red and very beautiful.",
        "Superb! A display of pure golf genius on that hole.",
        "Masterful performance! That's a birdie or better and well deserved.",
        "Simply brilliant. He conquered the hole and left with a smile."
    };

    // 9. Idle / Overthinking
    private readonly string[] _idleTemplates = new[]
    {
        "Are we going to hit today, or are you waiting for the grass to grow?",
        "I've seen glaciers move faster than this pre-shot routine.",
        "Take your time. It's not like the sun is going down or anything.",
        "He's overthinking this so much, I think he's writing a thesis on it.",
        "Is he playing golf, or meditating on the meaning of life?",
        "Any second now. Any... second... now.",
        "I think the ball is starting to gather moss. Hit it already!",
        "Did he fall asleep standing up? Somebody check his pulse.",
        "Overthinking is the enemy of golf. And so is this delay.",
        "We are waiting. The course is waiting. The grass is waiting."
    };

    // 10. Chunked
    private readonly string[] _chunkedTemplates = new[]
    {
        "Oof, did you hit that with your purse? That went absolutely nowhere.",
        "That's a classic chunk. Next time, try hitting the ball instead of the entire planet.",
        "He hit more dirt than ball there. A very dusty shot.",
        "A bit of a stubbed toe on that swing. That ball barely moved.",
        "Well, that was a nice practice swing. Oh wait, that was the actual shot?",
        "He caught that so fat, it needs its own weight-loss program.",
        "That went about ten feet. Did you forget to swing, or did the ball just fall off the tee?",
        "A ground-cutter that didn't even reach the ladies' tee.",
        "A massive chunk. He's practically excavating the fairway out here.",
        "Well, it moved. Not forward, but it definitely moved."
    };

    // Mulligan
    private readonly string[] _mulliganTemplates = new[]
    {
        "Oh, a mulligan? Sure, let's pretend that last shot never happened.",
        "Another mulligan? Are we playing golf, or editing a movie?",
        "Mulligan! Did your mom approve that redo?",
        "A mulligan? Fine, but the announcer saw it. We all saw it."
    };

    // Launch-time commentary templates for fallback
    private readonly string[] _launchSkyballTemplates = new[]
    {
        "Skyball! That one is going to have snow on it.",
        "A high flyer! He got way under that ball.",
        "Wow, that went higher than it went forward! A massive skyball.",
        "Up, up, and away. That is a pop-up skyball."
    };

    private readonly string[] _launchWormburnerTemplates = new[]
    {
        "A classic wormburner! That won't get off the ground.",
        "Kept it extremely low, very low.",
        "Wormburner! Those poor worms never stood a chance.",
        "A low-running bullet, that won't see much air today."
    };

    private readonly string[] _launchSliceTemplates = new[]
    {
        "Oh, he's pushed that way off to the right!",
        "Offline right immediately. She's fading fast.",
        "A big block right. That's heading way offline.",
        "Fore right! That's going way right."
    };

    private readonly string[] _launchHookTemplates = new[]
    {
        "Hooked it left! That's heading way offline.",
        "Pull hook left! That started left and is keeping left.",
        "Way offline to the left. He pulled that one completely."
    };

    private readonly string[] _launchCrushedTemplates = new[]
    {
        "He absolutely smashed that! Caught it right in the sweet spot.",
        "Oh, what a sound off the club face! Absolutely crushed!",
        "He caught that flush! Great power behind that swing.",
        "Boom! That was struck with pure authority."
    };

    private readonly string[] _launchMishitTemplates = new[]
    {
        "Oof, did not catch that clean. Sounded a bit thin.",
        "A bit of a mishit, contact was off.",
        "Not a solid strike there, he didn't get much of it."
    };

    private readonly string[] _launchPuttTemplates = new[]
    {
        "A smooth stroke on the green.",
        "The putt is away.",
        "Nice easy stroke, ball is rolling."
    };

    private readonly string[] _launchGenericTemplates = new[]
    {
        "And he's off! Looks like a clean swing.",
        "In the air, let's see how it tracks.",
        "Nice smooth swing, ball is in flight.",
        "Struck well, tracking down the range."
    };

    private readonly string[] _duffTemplates = new[]
    {
        "Oof, did you even hit the ball? That went nowhere.",
        "That's a classic duff. Next time, try hitting the ball instead of the turf."
    };

    private readonly string[] _praiseTemplates = new[]
    {
        "That is an absolute beauty! Right down the middle!",
        "Oh, what a strike! That one is going to roll forever.",
        "Superb shot! You made that look easy.",
        "Nicely done. Right in the short grass.",
        "Great shot! Beautiful tempo on that swing.",
        "A marvellous result there, right in the heart of the fairway.",
        "Perfect execution. He's exactly where he wanted to be.",
        "Struck that beautifully. A textbook shot.",
        "Excellent distance control. That's a highly respectable shot.",
        "That's in prime position. Absolutely splendid."
    };

    private readonly string[] _heckleTemplates = new[]
    {
        "Did you close your eyes on that one?",
        "My grandmother can hit it further than that, and she's dead!",
        "I've seen better swings on a playground!",
        "Is that your golf swing, or are you swatting a mosquito?",
        "Heckle links! You might want to consider tennis.",
        "You swing like a rusty gate.",
        "Well, that was a swing only a mother could love.",
        "Struck with the precision of a blindfolded caveman.",
        "I've seen happier accidents, but that's in the deep stuff.",
        "Oof. That's going to require a search party."
    };

    private readonly Random _random = new();

    public Array<Dictionary> GetTtsVoices()
    {
        return AndroidTTS.GetVoices();
    }

    public override void _Ready()
    {
        _audioPlayer = new AudioStreamPlayer();
        AddChild(_audioPlayer);
        GD.Print($"{LogPrefix} Ready. Audio player initialized.");
    }

    private void PlayAudioFile(string filename)
    {
        if (!AnnouncerEnabled) return;
        try
        {
            var path = $"res://assets/audio/announcer/{filename}.mp3";
            var stream = GD.Load<AudioStream>(path);
            if (stream != null)
            {
                _audioPlayer.Stream = stream;
                _audioPlayer.Play();
                GD.Print($"{LogPrefix} Playing audio file: {path}");
            }
            else
            {
                GD.PrintErr($"{LogPrefix} Failed to load audio stream from path: {path}");
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Error playing audio file: {ex.Message}");
        }
    }

    private void PlayComment(string categoryName, string[] templates)
    {
        string selected = GetRandomComment(templates);
        int index = System.Array.IndexOf(templates, selected);
        if (index >= 0)
        {
            PlayAudioFile($"{categoryName}_{index}");
        }
    }

    public override void _Process(double delta)
    {
        if (!AnnouncerEnabled || !HeckleEnabled) return;

        // Don't play idle comments if audio is already playing
        if (_audioPlayer != null && _audioPlayer.Playing)
        {
            _idleTimer = 0.0f;
            return;
        }

        var currentScene = GetTree().CurrentScene;
        if (currentScene == null) return;

        // Simple check to ensure we are in a golf game and not the main menu / screens
        if (currentScene.Name == "MainMenu" || currentScene.Name == "CourseSelector" || currentScene.Name == "CoursePlaySetup" || currentScene.Name == "OsmDownloadDialog")
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

    private void SpeakIdleComment()
    {
        PlayComment("idle", _idleTemplates);
    }

    public void AnnounceLaunch(Dictionary shotData)
    {
        if (!AnnouncerEnabled) return;
        _idleTimer = 0.0f; // Reset idle timer!

        float speedMph = shotData.TryGetValue("Speed", out var speedVal) ? (float)speedVal : 0.0f;
        float vla = shotData.TryGetValue("VLA", out var vlaVal) ? (float)vlaVal : 0.0f;
        float hla = shotData.TryGetValue("HLA", out var hlaVal) ? (float)hlaVal : 0.0f;
        string shotType = shotData.TryGetValue("ShotType", out var typeVal) ? (string)typeVal : "";

        bool isPutt = shotType.Equals("putt", StringComparison.OrdinalIgnoreCase);

        if (isPutt)
        {
            PlayComment("launch_putt", _launchPuttTemplates);
        }
        else
        {
            // Evaluate contact quality / smash factor
            float smashFactor = 1.40f; // Default baseline

            if (shotData.TryGetValue("SmashFactor", out var sfVal))
            {
                smashFactor = (float)sfVal;
            }
            else if (shotData.TryGetValue("ClubSpeed", out var csVal) && (float)csVal > 0.0f)
            {
                smashFactor = speedMph / (float)csVal;
            }
            else if (speedMph > 40.0f)
            {
                // Estimate smash factor for commentary variety
                if (shotType.Equals("drive", StringComparison.OrdinalIgnoreCase))
                {
                    if (speedMph > 145.0f)
                        smashFactor = 1.46f + 0.04f * (float)_random.NextDouble();
                    else if (speedMph < 90.0f)
                        smashFactor = 1.25f + 0.10f * (float)_random.NextDouble();
                    else
                        smashFactor = 1.35f + 0.12f * (float)_random.NextDouble();
                }
                else // Iron
                {
                    if (speedMph > 110.0f)
                        smashFactor = 1.36f + 0.04f * (float)_random.NextDouble();
                    else if (speedMph < 50.0f)
                        smashFactor = 1.15f + 0.10f * (float)_random.NextDouble();
                    else
                        smashFactor = 1.25f + 0.12f * (float)_random.NextDouble();
                }
            }

            // Decide launch commentary priority
            if (vla < 4.0f && speedMph > 30.0f) // Wormburner
            {
                if (HeckleEnabled)
                    PlayComment("launch_wormburner", _launchWormburnerTemplates);
            }
            else if (vla > 30.0f && speedMph > 90.0f) // Skyball / Pop-up
            {
                if (HeckleEnabled)
                    PlayComment("launch_skyball", _launchSkyballTemplates);
            }
            else if (hla > 4.5f && speedMph > 40.0f) // Offline right
            {
                if (HeckleEnabled)
                    PlayComment("launch_slice", _launchSliceTemplates);
            }
            else if (hla < -4.5f && speedMph > 40.0f) // Offline left
            {
                if (HeckleEnabled)
                    PlayComment("launch_hook", _launchHookTemplates);
            }
            else if (speedMph > 40.0f && smashFactor > 1.45f) // Crushed it
            {
                if (PraiseEnabled)
                    PlayComment("launch_crushed", _launchCrushedTemplates);
            }
            else if (speedMph > 40.0f && smashFactor < 1.25f) // Mishit
            {
                if (HeckleEnabled)
                    PlayComment("launch_mishit", _launchMishitTemplates);
            }
            else if (speedMph > 30.0f) // Normal hit
            {
                if (PraiseEnabled)
                    PlayComment("launch_generic", _launchGenericTemplates);
            }
        }
    }

    public void EvaluateShot(Dictionary shotData, int surfaceType, float distanceToPinYards, bool isInSand = false, bool isInWater = false)
    {
        if (!AnnouncerEnabled) return;
        _idleTimer = 0.0f; // Reset idle timer!

        float speedMph = shotData.TryGetValue("Speed", out var speedVal) ? (float)speedVal : 0.0f;
        float totalDistYards = shotData.TryGetValue("TotalDistance", out var distVal) ? (float)distVal * 1.09361f : 0.0f;
        float offlineYards = shotData.TryGetValue("SideDistance", out var sideVal) ? (float)sideVal * 1.09361f : 0.0f;
        float targetDistYards = shotData.TryGetValue("TargetDistance", out var targetVal) ? (float)targetVal * 1.09361f : 0.0f;
        string shotType = shotData.TryGetValue("ShotType", out var typeVal) ? (string)typeVal : "";

        bool isPutt = shotType.Equals("putt", StringComparison.OrdinalIgnoreCase);

        if (isPutt)
        {
            if (distanceToPinYards < 0.25f) // Holed out / extremely close
            {
                if (totalDistYards >= 5.0f) // Long putt (>= 15 feet / 5 yards)
                {
                    PlayComment("long_putt", _longPuttTemplates);
                }
                else
                {
                    // For short putts, play one of the praise lines
                    PlayComment("praise", _praiseTemplates);
                }
            }
            else if (totalDistYards < 2.0f && distanceToPinYards > 5.0f)
            {
                // Missed short: play a heckle comment
                PlayComment("heckle", _heckleTemplates);
            }
            else
            {
                // Normal rollout: play praise if close, heckle if far
                if (distanceToPinYards < 2.0f)
                    PlayComment("praise", _praiseTemplates);
                else if (distanceToPinYards > 5.0f)
                    PlayComment("heckle", _heckleTemplates);
            }
        }
        else if (isInWater)
        {
            if (HeckleEnabled)
                PlayComment("water", _waterTemplates);
        }
        else if (isInSand)
        {
            if (HeckleEnabled)
                PlayComment("sand", _sandTemplates);
        }
        else if (targetDistYards > 50.0f && totalDistYards < 30.0f && totalDistYards < targetDistYards * 0.4f) // Chunked!
        {
            if (HeckleEnabled)
                PlayComment("chunked", _chunkedTemplates);
        }
        else if (targetDistYards > 50.0f && totalDistYards > targetDistYards + 15.0f) // Crushed and went further than aimed
        {
            if (PraiseEnabled)
                PlayComment("overshot_crushed", _overshotCrushedTemplates);
        }
        else if (totalDistYards > 50.0f && Math.Abs(offlineYards) > 20.0f) // Offline / Slice / Hook / Curve
        {
            if (HeckleEnabled)
                PlayComment("offline_sarcastic", _offlineSarcasticTemplates);
        }
        else if (totalDistYards < 20.0f) // Duff
        {
            if (HeckleEnabled)
                PlayComment("duff", _duffTemplates);
        }
        else if (distanceToPinYards < 1.0f) // Extremely close to pin
        {
            if (PraiseEnabled)
                PlayComment("praise", _praiseTemplates);
        }
        else if (totalDistYards > 280.0f && Math.Abs(offlineYards) < 15.0f) // Massive bomb
        {
            if (PraiseEnabled)
                PlayComment("praise", _praiseTemplates);
        }
        else
        {
            // Praise if it landed on the fairway or green
            if (PraiseEnabled && (surfaceType == 0 || surfaceType == 4))
            {
                PlayComment("praise", _praiseTemplates);
            }
            // Heckle if it landed in the rough
            else if (HeckleEnabled && surfaceType == 2)
            {
                PlayComment("heckle", _heckleTemplates);
            }
        }
    }

    public void SpeakMulliganHeckle()
    {
        if (!HeckleEnabled) return;
        _idleTimer = 0.0f; // Reset idle timer!
        PlayComment("mulligan", _mulliganTemplates);
    }

    public void SpeakTreeHeckle()
    {
        if (!HeckleEnabled) return;
        _idleTimer = 0.0f; // Reset idle timer!
        PlayComment("heckle", _heckleTemplates);
    }

    public void AnnounceHoleScore(string playerName, int strokes, int par)
    {
        if (!AnnouncerEnabled) return;
        _idleTimer = 0.0f; // Reset idle timer!

        int scoreType = strokes - par;

        if (scoreType > 0)
        {
            if (HeckleEnabled)
                PlayComment("above_par", _aboveParTemplates);
        }
        else if (scoreType == 0)
        {
            if (PraiseEnabled)
                PlayComment("par", _parTemplates);
        }
        else // Under par (scoreType < 0)
        {
            if (PraiseEnabled)
                PlayComment("under_par", _underParTemplates);
        }
    }

    private string GetRandomComment(string[] templates)
    {
        int index = _random.Next(templates.Length);
        return templates[index];
    }
}
