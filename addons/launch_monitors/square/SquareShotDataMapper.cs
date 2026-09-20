using System;
using System.Collections.Generic;

namespace LaunchMonitors.Square;

public static class SquareShotDataMapper
{
    private const float MetersPerSecondToMph = 2.23694f;

    public static IReadOnlyDictionary<string, object> ToOsgBallData(SquareShotMetrics metrics)
    {
        var totalSpin = Math.Max(0, metrics.TotalSpinRpm);
        var backSpin = metrics.BackSpinRpm;
        var sideSpin = metrics.SideSpinRpm;

        if (backSpin == 0 && sideSpin == 0 && totalSpin > 0)
        {
            var spinAxisRadians = MathF.PI * metrics.SpinAxis / 180.0f;
            backSpin = (int)MathF.Round(totalSpin * MathF.Cos(spinAxisRadians));
            sideSpin = (int)MathF.Round(totalSpin * MathF.Sin(spinAxisRadians));
        }

        var speedMph = metrics.BallSpeedMps * MetersPerSecondToMph;

        var data = new Dictionary<string, object>
        {
            { "Speed", speedMph },
            { "BallSpeed", speedMph },
            { "VLA", metrics.VerticalAngle },
            { "HLA", metrics.HorizontalAngle },
            { "TotalSpin", totalSpin },
            { "SpinAxis", metrics.SpinAxis },
            { "BackSpin", backSpin },
            { "SideSpin", sideSpin },
            { "ShotType", metrics.ShotType },
        };

        if (metrics.ClubSpeedMps > 0)
        {
            var clubSpeedMph = metrics.ClubSpeedMps * MetersPerSecondToMph;
            data["ClubSpeed"] = clubSpeedMph;
            if (metrics.SmashFactor > 0)
                data["SmashFactor"] = metrics.SmashFactor;
            else if (clubSpeedMph > 0 && speedMph > 0)
                data["SmashFactor"] = speedMph / clubSpeedMph;
        }
        else if (metrics.SmashFactor > 0)
        {
            data["SmashFactor"] = metrics.SmashFactor;
        }

        // Only include club delivery metrics when the hardware actually measured them.
        // Square Golf's camera system provides these when club stickers are detected.
        if (metrics.HasClubData)
        {
            data["FaceAngle"] = metrics.FaceAngle;
            data["ClubPath"] = metrics.ClubPath;
            data["AttackAngle"] = metrics.AttackAngle;
            data["DynamicLoft"] = metrics.DynamicLoft;
            data["FaceToPath"] = metrics.FaceAngle - metrics.ClubPath;
            data["RawFaceAngle"] = metrics.FaceAngle;
            data["RawClubPath"] = metrics.ClubPath;
        }
        else
        {
            if (MathF.Abs(metrics.FaceAngle) > 0.001f)
                data["FaceAngle"] = metrics.FaceAngle;
            if (MathF.Abs(metrics.ClubPath) > 0.001f)
                data["ClubPath"] = metrics.ClubPath;
            if (MathF.Abs(metrics.AttackAngle) > 0.001f)
                data["AttackAngle"] = metrics.AttackAngle;
            if (metrics.DynamicLoft > 0.001f)
                data["DynamicLoft"] = metrics.DynamicLoft;
            if (data.ContainsKey("FaceAngle") && data.ContainsKey("ClubPath"))
                data["FaceToPath"] = metrics.FaceAngle - metrics.ClubPath;
        }

        return data;
    }
}
