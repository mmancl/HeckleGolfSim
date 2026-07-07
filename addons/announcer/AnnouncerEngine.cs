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

    // Launch-time commentary templates
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

    // Rest-time commentary templates
    private readonly string[] _praiseTemplates = new[]
    {
        "That is an absolute beauty! Right down the middle!",
        "Oh, what a strike! That one is going to roll forever.",
        "Superb shot! You made that look easy.",
        "Nicely done. Right in the short grass.",
        "Great shot! Beautiful tempo on that swing."
    };

    private readonly string[] _heckleTemplates = new[]
    {
        "Did you close your eyes on that one?",
        "My grandmother can hit it further than that, and she's dead!",
        "I've seen better swings on a playground!",
        "Is that your golf swing, or are you swatting a mosquito?",
        "Heckle links! You might want to consider tennis.",
        "You swing like a rusty gate."
    };

    private readonly string[] _duffTemplates = new[]
    {
        "Oof, did you even hit the ball? That went nowhere.",
        "That's a classic duff. Next time, try hitting the ball instead of the turf."
    };

    private readonly string[] _mulliganTemplates = new[]
    {
        "Oh, a mulligan? Sure, let's pretend that last shot never happened.",
        "Another mulligan? Are we playing golf, or editing a movie?",
        "Mulligan! Did your mom approve that redo?",
        "A mulligan? Fine, but the announcer saw it. We all saw it."
    };

    private readonly Random _random = new();

    public Array<Dictionary> GetTtsVoices()
    {
        return AndroidTTS.GetVoices();
    }

    public override void _Ready()
    {
        // Try to select the first English voice as default if not set
        if (string.IsNullOrEmpty(ActiveVoice))
        {
            var voices = AndroidTTS.GetVoices();
            foreach (var voice in voices)
            {
                string lang = voice.ContainsKey("language") ? voice["language"].AsString().ToLower() : "";
                if (lang.StartsWith("en") || lang.Contains("en"))
                {
                    ActiveVoice = voice.ContainsKey("id") ? voice["id"].AsString() : "";
                    break;
                }
            }
        }
        GD.Print($"{LogPrefix} Ready. Active voice is: '{ActiveVoice}'");
    }

    public void AnnounceLaunch(Dictionary shotData)
    {
        if (!AnnouncerEnabled) return;

        float speedMph = shotData.TryGetValue("Speed", out var speedVal) ? (float)speedVal : 0.0f;
        float vla = shotData.TryGetValue("VLA", out var vlaVal) ? (float)vlaVal : 0.0f;
        float hla = shotData.TryGetValue("HLA", out var hlaVal) ? (float)hlaVal : 0.0f;
        string shotType = shotData.TryGetValue("ShotType", out var typeVal) ? (string)typeVal : "";

        bool isPutt = shotType.Equals("putt", StringComparison.OrdinalIgnoreCase);

        string voiceComment = "";

        if (isPutt)
        {
            voiceComment = GetRandomComment(_launchPuttTemplates);
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
                    voiceComment = GetRandomComment(_launchWormburnerTemplates);
            }
            else if (vla > 30.0f && speedMph > 90.0f) // Skyball / Pop-up
            {
                if (HeckleEnabled)
                    voiceComment = GetRandomComment(_launchSkyballTemplates);
            }
            else if (hla > 4.5f && speedMph > 40.0f) // Offline right
            {
                if (HeckleEnabled)
                    voiceComment = GetRandomComment(_launchSliceTemplates);
            }
            else if (hla < -4.5f && speedMph > 40.0f) // Offline left
            {
                if (HeckleEnabled)
                    voiceComment = GetRandomComment(_launchHookTemplates);
            }
            else if (speedMph > 40.0f && smashFactor > 1.45f) // Crushed it
            {
                if (PraiseEnabled)
                    voiceComment = GetRandomComment(_launchCrushedTemplates);
            }
            else if (speedMph > 40.0f && smashFactor < 1.25f) // Mishit
            {
                if (HeckleEnabled)
                    voiceComment = GetRandomComment(_launchMishitTemplates);
            }
            else if (speedMph > 30.0f) // Normal hit
            {
                if (PraiseEnabled)
                    voiceComment = GetRandomComment(_launchGenericTemplates);
            }
        }

        if (!string.IsNullOrEmpty(voiceComment))
        {
            AndroidTTS.Speak(voiceComment, ActiveVoice, Pitch, Rate);
        }
    }

    public void EvaluateShot(Dictionary shotData, int surfaceType, float distanceToPinYards)
    {
        if (!AnnouncerEnabled) return;

        float speedMph = shotData.TryGetValue("Speed", out var speedVal) ? (float)speedVal : 0.0f;
        float totalDistYards = shotData.TryGetValue("TotalDistance", out var distVal) ? (float)distVal * 1.09361f : 0.0f;
        float offlineYards = shotData.TryGetValue("SideDistance", out var sideVal) ? (float)sideVal * 1.09361f : 0.0f;
        string shotType = shotData.TryGetValue("ShotType", out var typeVal) ? (string)typeVal : "";

        bool isPutt = shotType.Equals("putt", StringComparison.OrdinalIgnoreCase);

        string voiceComment = "";

        if (isPutt)
        {
            if (distanceToPinYards < 0.25f) // Holed out / extremely close
            {
                voiceComment = "In the cup! What a beautiful putt.";
            }
            else if (totalDistYards < 2.0f && distanceToPinYards > 5.0f)
            {
                voiceComment = "Left it way short. You need to hit it with some conviction.";
            }
            else
            {
                voiceComment = $"Nice putt. It rolled {totalDistYards:F0} yards, leaving {distanceToPinYards:F0} yards to the hole.";
            }
        }
        else if (totalDistYards < 20.0f) // Duff
        {
            if (HeckleEnabled)
                voiceComment = GetRandomComment(_duffTemplates);
        }
        else if (distanceToPinYards < 1.0f) // Extremely close to pin
        {
            if (PraiseEnabled)
                voiceComment = $"Oh, what a shot! Unbelievable! It stopped just {distanceToPinYards:F1} yards from the pin!";
        }
        else if (totalDistYards > 280.0f && Math.Abs(offlineYards) < 15.0f) // Massive bomb
        {
            if (PraiseEnabled)
                voiceComment = $"What an absolute bomb! {totalDistYards:F0} yards, right down the fairway.";
        }
        else
        {
            // Play-by-play landing zone announcer
            string lieText = surfaceType switch
            {
                0 => "fairway",
                1 => "soft fairway",
                2 => "rough",
                3 => "hard ground",
                4 => "green",
                _ => "grass"
            };

            // Praise if it landed on the fairway or green
            if (PraiseEnabled && (surfaceType == 0 || surfaceType == 4))
            {
                if (surfaceType == 4)
                {
                    voiceComment = $"It found the green! That's on the green, leaving {distanceToPinYards:F0} yards for the putt.";
                }
                else
                {
                    voiceComment = $"Nicely placed in the fairway. The shot traveled {totalDistYards:F0} yards, with {distanceToPinYards:F0} yards left to the pin.";
                }
            }
            // Heckle if it landed in the rough
            else if (HeckleEnabled && surfaceType == 2)
            {
                voiceComment = $"It's landed in the deep rough. That's {totalDistYards:F0} yards from the tee, leaving a tough lie and {distanceToPinYards:F0} yards to the pin.";
            }
            else
            {
                voiceComment = $"That hit went {totalDistYards:F0} yards. The ball is resting in the {lieText}, with {distanceToPinYards:F0} yards remaining to the pin.";
            }
        }

        if (!string.IsNullOrEmpty(voiceComment))
        {
            AndroidTTS.Speak(voiceComment, ActiveVoice, Pitch, Rate);
        }
    }

    public void SpeakMulliganHeckle()
    {
        if (!HeckleEnabled) return;
        string comment = GetRandomComment(_mulliganTemplates);
        AndroidTTS.Speak(comment, ActiveVoice, Pitch, Rate);
    }

    private string GetRandomComment(string[] templates)
    {
        int index = _random.Next(templates.Length);
        return templates[index];
    }
}
