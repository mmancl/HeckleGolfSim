using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace LaunchMonitors.R10;

public static partial class R10Protocol
{
    public static bool TryParseShot(byte[]? value, out R10ShotMetrics metrics)
    {
        metrics = default;
        if (value is null || value.Length == 0)
        {
            return false;
        }

        var text = Encoding.UTF8.GetString(value).Trim();
        if (TryParseTextShot(text, out metrics))
        {
            return true;
        }

            if (TryParseFramedShot(value, out metrics))
            {
                return true;
            }

            return TryParseBinaryShot(value, out metrics);
        }

    public static bool TryParseSensor(byte[]? value, out R10SensorData sensor)
    {
        sensor = default;
        if (value is null || value.Length == 0)
        {
            return false;
        }

        var floats = ExtractFloats(value, out _);
        if (floats.Count >= 5)
        {
            sensor = new R10SensorData(
                BallReady: floats[3] > 0.0f,
                BallDetected: floats[4] > 0.0f,
                PositionX: (int)MathF.Round(floats[0]),
                PositionY: (int)MathF.Round(floats[1]),
                PositionZ: (int)MathF.Round(floats[2]));
            return true;
        }

        return false;
    }

    public static bool TryParseReady(byte[]? value, out bool ready)
    {
        ready = false;
        if (value is null || value.Length == 0)
        {
            return false;
        }

        var text = Encoding.ASCII.GetString(value).Trim();
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        if (text.Contains("not ready", StringComparison.OrdinalIgnoreCase)
            || text.Contains("busy", StringComparison.OrdinalIgnoreCase)
            || text.Contains("error", StringComparison.OrdinalIgnoreCase))
        {
            ready = false;
            return true;
        }

        if (text.Contains("ready", StringComparison.OrdinalIgnoreCase)
            || text.Contains("waiting", StringComparison.OrdinalIgnoreCase))
        {
            ready = true;
            return true;
        }

        var floats = ExtractFloats(value, out _);
        if (floats.Count >= 1)
        {
            ready = floats[0] > 0.0f;
            return true;
        }

        return false;
    }

    private static bool TryParseTextShot(string text, out R10ShotMetrics metrics)
    {
        metrics = default;
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        var ballSpeed = TryReadFloat(text, "ballSpeed") ?? TryReadFloat(text, "speed") ?? TryReadFloat(text, "ball_speed");
        var vertical = TryReadFloat(text, "vla") ?? TryReadFloat(text, "vertical") ?? TryReadFloat(text, "launchAngle");
        var horizontal = TryReadFloat(text, "hla") ?? TryReadFloat(text, "horizontal") ?? TryReadFloat(text, "launchDirection");
        var totalSpin = TryReadInt(text, "totalSpin") ?? TryReadInt(text, "total_spin") ?? TryReadInt(text, "spin");
        var spinAxis = TryReadFloat(text, "spinAxis") ?? TryReadFloat(text, "spin_axis");

        if (ballSpeed is null && vertical is null && horizontal is null && totalSpin is null && spinAxis is null)
        {
            return false;
        }

        var ballMps = ballSpeed ?? 0.0f;
        var verticalAngle = vertical ?? 0.0f;
        var horizontalAngle = horizontal ?? 0.0f;
        var totalSpinRpm = totalSpin ?? 0;
        var axis = spinAxis ?? 0.0f;
        var clubSpeedMps = MathF.Max(0.0f, ballMps / 1.45f);
        var smash = clubSpeedMps > 0.0f ? ballMps / clubSpeedMps : 1.45f;

        metrics = new R10ShotMetrics(
            BallSpeedMps: ballMps,
            VerticalAngle: verticalAngle,
            HorizontalAngle: horizontalAngle,
            TotalSpinRpm: totalSpinRpm,
            SpinAxis: axis,
            BackSpinRpm: totalSpinRpm,
            SideSpinRpm: 0,
            ShotType: "Unknown",
            ClubSpeedMps: clubSpeedMps,
            SmashFactor: smash);
        return true;
    }

    private static bool TryParseFramedShot(byte[] value, out R10ShotMetrics metrics)
    {
        metrics = default;
        try
        {
            // Try treating value as a COBS-framed message with CRC and embedded protobuf payload (gsp-r10 framing)
            var decoded = COBS.Decode(value).ToArray();
            if (decoded == null || decoded.Length < 6)
                return false;

            // Verify CRC (last 2 bytes)
            var body = decoded.Take(decoded.Length - 2).ToArray();
            var crc = Crc16.ComputeChecksum(body);
            var stated = decoded.Skip(decoded.Length - 2).Take(2).ToArray();
            if (crc == null || crc.Length < 2)
                return false;
            if (BitConverter.ToUInt16(crc, 0) != BitConverter.ToUInt16(stated, 0))
                return false;

            // Following the other project's logic: skip first 2 header bytes and final 2 CRC bytes, then skip 16-byte header inside message
            if (body.Length <= 2)
                return false;
            var msg = body.Skip(2).ToArray();
            if (msg.Length <= 16)
                return false;
            var proto = msg.Skip(16).ToArray();

            // Heuristic: scan protobuf payload for float fields (wiretype=5) for field numbers 1..4.
            // float field key = (fieldNumber << 3) | 5. Common ball fields: launch_angle(1), launch_direction(2), ball_speed(3)
            byte keyLA = (byte)((1 << 3) | 5); // 0x0D
            byte keyLD = (byte)((2 << 3) | 5); // 0x15
            byte keyBS = (byte)((3 << 3) | 5); // 0x1D

            for (int i = 0; i + 4 < proto.Length; i++)
            {
                if (proto[i] == keyBS)
                {
                    float speed = BitConverter.ToSingle(proto, i + 1);
                    if (float.IsNaN(speed) || float.IsInfinity(speed)) continue;
                    // plausible speed check (could be mph or m/s)
                    if (speed < 2.0f || speed > 400.0f) continue;

                    // find nearest LA and LD after this position
                    float la = 0.0f; float ld = 0.0f;
                    for (int j = i + 5; j + 4 < proto.Length; j++)
                    {
                        if (proto[j] == keyLA)
                        {
                            la = BitConverter.ToSingle(proto, j + 1);
                        }
                        else if (proto[j] == keyLD)
                        {
                            ld = BitConverter.ToSingle(proto, j + 1);
                        }
                        if (la != 0.0f && ld != 0.0f) break;
                    }

                    // Normalize speed: if it's large (e.g., >50) it's likely mph; convert to m/s
                    var ballSpeedMps = ClampNonNegative(speed);
                    if (ballSpeedMps > 50.0f)
                        ballSpeedMps = ballSpeedMps * 0.44704f;

                    var clubSpeedMps = MathF.Max(0.0f, ballSpeedMps / 1.45f);
                    var smash = clubSpeedMps > 0.0f ? ballSpeedMps / clubSpeedMps : 1.45f;

                    metrics = new R10ShotMetrics(
                        BallSpeedMps: ballSpeedMps,
                        VerticalAngle: la,
                        HorizontalAngle: ld,
                        TotalSpinRpm: 0,
                        SpinAxis: 0.0f,
                        BackSpinRpm: 0,
                        SideSpinRpm: 0,
                        ShotType: "Shot",
                        ClubSpeedMps: clubSpeedMps,
                        SmashFactor: smash);

                    return true;
                }
            }
        }
        catch { }

        return false;
    }

    private static bool TryParseBinaryShot(byte[] value, out R10ShotMetrics metrics)
    {
        metrics = default;
        var floats = ExtractFloats(value, out var chosenOffset);
        // Known R10 formats observed: a compact 3-float tuple (speed, vla, hla)
        // and a longer 6+ float tuple including spin/backspin. Support both.
        if (floats.Count >= 6)
        {
            var ballSpeedMps = ClampNonNegative(floats[0]);
            var verticalAngle = floats[1];
            var horizontalAngle = floats[2];
            var totalSpinRpm = Math.Max(0, (int)MathF.Round(floats[3]));
            var spinAxis = floats[4];
            var backSpin = Math.Max(0, (int)MathF.Round(floats[5]));
            var sideSpin = totalSpinRpm > 0 ? Math.Max(0, (int)MathF.Round(totalSpinRpm * MathF.Sin(MathF.PI * spinAxis / 180.0f))) : 0;
            var clubSpeedMps = MathF.Max(0.0f, ballSpeedMps / 1.45f);
            var smash = clubSpeedMps > 0.0f ? ballSpeedMps / clubSpeedMps : 1.45f;

            metrics = new R10ShotMetrics(
                BallSpeedMps: ballSpeedMps,
                VerticalAngle: verticalAngle,
                HorizontalAngle: horizontalAngle,
                TotalSpinRpm: totalSpinRpm,
                SpinAxis: spinAxis,
                BackSpinRpm: backSpin,
                SideSpinRpm: sideSpin,
                ShotType: ballSpeedMps > 0.0f ? "Shot" : "Unknown",
                ClubSpeedMps: clubSpeedMps,
                SmashFactor: smash);
            return true;
        }

        if (floats.Count >= 3)
        {
            // Fallback compact format: try to find a plausible speed value inside the float list.
            int FindSpeedIndex(List<float> f)
            {
                var bestIdx = -1;
                var bestScore = -1;
                for (int i = 0; i < f.Count; i++)
                {
                    var v = f[i];
                    if (float.IsNaN(v) || float.IsInfinity(v)) continue;
                    var score = 0;
                    // Prefer speeds in a plausible ball-speed range (units vary across firmwares)
                    if (v >= 10.0f && v <= 200.0f) score += 4; // strong candidate (likely in km/h or mph)
                    if (v >= 2.0f && v <= 100.0f) score += 3; // plausible m/s or scaled values
                    if (v >= -180.0f && v <= 180.0f) score += 1; // small bonus for non-gibberish
                    if (score > bestScore) { bestScore = score; bestIdx = i; }
                }
                return bestIdx;
            }

            var idx = FindSpeedIndex(floats);
            if (idx >= 0)
            {
                var ballSpeedMps = ClampNonNegative(floats[idx]);
                var verticalAngle = (idx + 1) < floats.Count ? floats[idx + 1] : 0.0f;
                var horizontalAngle = (idx + 2) < floats.Count ? floats[idx + 2] : 0.0f;
                var totalSpinRpm = 0;
                var spinAxis = 0.0f;
                var backSpin = 0;
                var sideSpin = 0;
                var clubSpeedMps = MathF.Max(0.0f, ballSpeedMps / 1.45f);
                var smash = clubSpeedMps > 0.0f ? ballSpeedMps / clubSpeedMps : 1.45f;

                metrics = new R10ShotMetrics(
                    BallSpeedMps: ballSpeedMps,
                    VerticalAngle: verticalAngle,
                    HorizontalAngle: horizontalAngle,
                    TotalSpinRpm: totalSpinRpm,
                    SpinAxis: spinAxis,
                    BackSpinRpm: backSpin,
                    SideSpinRpm: sideSpin,
                    ShotType: ballSpeedMps > 0.0f ? "Shot" : "Unknown",
                    ClubSpeedMps: clubSpeedMps,
                    SmashFactor: smash);
                return true;
            }
        }

        // Fallback: scan payload for 32-bit/16-bit integer candidates at any offset and try common scales.
        try
        {
            // Scan 32-bit signed/unsigned values
            for (int i = 0; i + 3 < value.Length; i++)
            {
                try
                {
                    var v32 = BitConverter.ToInt32(value, i);
                    var uv32 = (uint)v32;
                    var cands32 = new[] { v32 / 1000.0f, v32 / 100.0f, v32 / 10.0f, uv32 / 1000.0f, uv32 / 100.0f };
                    foreach (var cand in cands32)
                    {
                        if (cand >= 5.0f && cand <= 200.0f)
                        {
                            var ballSpeedMps = cand;
                            var clubSpeedMps = MathF.Max(0.0f, ballSpeedMps / 1.45f);
                            var smash = clubSpeedMps > 0.0f ? ballSpeedMps / clubSpeedMps : 1.45f;
                            metrics = new R10ShotMetrics(
                                BallSpeedMps: ballSpeedMps,
                                VerticalAngle: 0.0f,
                                HorizontalAngle: 0.0f,
                                TotalSpinRpm: 0,
                                SpinAxis: 0.0f,
                                BackSpinRpm: 0,
                                SideSpinRpm: 0,
                                ShotType: "Shot",
                                ClubSpeedMps: clubSpeedMps,
                                SmashFactor: smash);
                            return true;
                        }
                    }
                }
                catch { }
            }

            // Scan 16-bit signed values
            for (int i = 0; i + 1 < value.Length; i++)
            {
                try
                {
                    short sLe = BitConverter.ToInt16(value, i);
                    short sBe = (short)((value[i] << 8) | value[i + 1]);
                    var list = new[] { (float)sLe, (float)sBe };
                    foreach (var raw in list)
                    {
                        var cands16 = new[] { raw / 1000.0f, raw / 100.0f, raw / 10.0f };
                        foreach (var cand in cands16)
                        {
                            if (cand >= 5.0f && cand <= 200.0f)
                            {
                                var ballSpeedMps = cand;
                                var clubSpeedMps = MathF.Max(0.0f, ballSpeedMps / 1.45f);
                                var smash = clubSpeedMps > 0.0f ? ballSpeedMps / clubSpeedMps : 1.45f;
                                metrics = new R10ShotMetrics(
                                    BallSpeedMps: ballSpeedMps,
                                    VerticalAngle: 0.0f,
                                    HorizontalAngle: 0.0f,
                                    TotalSpinRpm: 0,
                                    SpinAxis: 0.0f,
                                    BackSpinRpm: 0,
                                    SideSpinRpm: 0,
                                    ShotType: "Shot",
                                    ClubSpeedMps: clubSpeedMps,
                                    SmashFactor: smash);
                                return true;
                            }
                        }
                    }
                }
                catch { }
            }
        }
        catch { }

        return false;
    }

    private static List<float> ExtractFloats(byte[] value, out int chosenOffset)
    {
        // Try offsets 0..3 and multiple 4-byte interpretations per chunk; pick best-scoring sequence.
        chosenOffset = 0;
        List<float> best = new List<float>();
        int bestScore = -1;

        for (int offset = 0; offset < 4; offset++)
        {
            var le = new List<float>();
            var be = new List<float>();
            var swapWords = new List<float>();
            var swapWordsBe = new List<float>();

            for (var i = offset; i + 3 < value.Length; i += 4)
            {
                try
                {
                    var chunk = new byte[4];
                    Array.Copy(value, i, chunk, 0, 4);

                    // little-endian as-is
                    try
                    {
                        var vLe = BitConverter.ToSingle(chunk, 0);
                        if (!float.IsNaN(vLe) && !float.IsInfinity(vLe)) le.Add(vLe);
                    }
                    catch { }

                    // big-endian: reverse bytes
                    try
                    {
                        var chunkBe = new byte[4] { chunk[3], chunk[2], chunk[1], chunk[0] };
                        var vBe = BitConverter.ToSingle(chunkBe, 0);
                        if (!float.IsNaN(vBe) && !float.IsInfinity(vBe)) be.Add(vBe);
                    }
                    catch { }

                    // 16-bit word-swapped: [2,3,0,1]
                    try
                    {
                        var chunkSwap = new byte[4] { chunk[2], chunk[3], chunk[0], chunk[1] };
                        var vSwap = BitConverter.ToSingle(chunkSwap, 0);
                        if (!float.IsNaN(vSwap) && !float.IsInfinity(vSwap)) swapWords.Add(vSwap);
                    }
                    catch { }

                    // word-swapped and byte-reversed: [1,0,3,2]
                    try
                    {
                        var chunkSwapBe = new byte[4] { chunk[1], chunk[0], chunk[3], chunk[2] };
                        var vSwapBe = BitConverter.ToSingle(chunkSwapBe, 0);
                        if (!float.IsNaN(vSwapBe) && !float.IsInfinity(vSwapBe)) swapWordsBe.Add(vSwapBe);
                    }
                    catch { }
                }
                catch
                {
                    break;
                }
            }

            var scoreLe = PlausibilityScore(le);
            var scoreBe = PlausibilityScore(be);
            var scoreSwap = PlausibilityScore(swapWords);
            var scoreSwapBe = PlausibilityScore(swapWordsBe);

            // choose best interpretation for this offset
            if (scoreBe > scoreLe && scoreBe >= scoreSwap && scoreBe >= scoreSwapBe)
            {
                if (scoreBe > bestScore) { bestScore = scoreBe; best = be; chosenOffset = offset; }
            }
            else if (scoreSwap > scoreLe && scoreSwap >= scoreBe && scoreSwap >= scoreSwapBe)
            {
                if (scoreSwap > bestScore) { bestScore = scoreSwap; best = swapWords; chosenOffset = offset; }
            }
            else if (scoreSwapBe > scoreLe && scoreSwapBe >= scoreBe && scoreSwapBe >= scoreSwap)
            {
                if (scoreSwapBe > bestScore) { bestScore = scoreSwapBe; best = swapWordsBe; chosenOffset = offset; }
            }
            else
            {
                if (scoreLe > bestScore) { bestScore = scoreLe; best = le; chosenOffset = offset; }
            }
        }

        return best;
    }

    public static int DetectBestOffset(byte[] value)
    {
        ExtractFloats(value, out var off);
        return off;
    }

    private static int PlausibilityScore(List<float> floats)
    {
        // Score based on how many of the first three floats fall into expected ranges:
        // [0] speed (m/s): 0..100, [1] vertical angle: -90..90, [2] horizontal angle: -180..180
        var score = 0;
        if (floats == null || floats.Count == 0)
            return score;
        if (floats.Count >= 1)
        {
            var s = floats[0];
            if (!float.IsNaN(s) && !float.IsInfinity(s) && s >= 0.0f && s <= 100.0f)
                score += 3;
            else if (!float.IsNaN(s) && !float.IsInfinity(s) && s >= -1000f && s <= 1000f)
                score += 1; // small bonus for non-gibberish
        }
        if (floats.Count >= 2)
        {
            var v = floats[1];
            if (!float.IsNaN(v) && !float.IsInfinity(v) && v >= -90.0f && v <= 90.0f)
                score += 2;
        }
        if (floats.Count >= 3)
        {
            var h = floats[2];
            if (!float.IsNaN(h) && !float.IsInfinity(h) && h >= -180.0f && h <= 180.0f)
                score += 2;
        }
        return score;
    }

    private static float ClampNonNegative(float value)
    {
        if (float.IsNaN(value) || float.IsInfinity(value))
        {
            return 0.0f;
        }

        return MathF.Max(0.0f, value);
    }

    private static float? TryReadFloat(string text, string key)
    {
        var pattern = $@"{Regex.Escape(key)}[^0-9-]*(-?\d+(?:\.\d+)?)";
        var match = Regex.Match(text, pattern, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        if (!match.Success)
        {
            return null;
        }

        if (float.TryParse(match.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var value))
        {
            return value;
        }

        return null;
    }

    private static int? TryReadInt(string text, string key)
    {
        var pattern = $@"{Regex.Escape(key)}[^0-9-]*(-?\d+)";
        var match = Regex.Match(text, pattern, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        if (!match.Success)
        {
            return null;
        }

        if (int.TryParse(match.Groups[1].Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value))
        {
            return value;
        }

        return null;
    }
}
