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
        var clubSpeedMph = metrics.ClubSpeedMps > 0 ? metrics.ClubSpeedMps * MetersPerSecondToMph : (speedMph > 0 ? speedMph / 1.45f : 0.0f);
        var smash = metrics.SmashFactor > 0 ? metrics.SmashFactor : (clubSpeedMph > 0 ? speedMph / clubSpeedMph : 1.45f);

        return new Dictionary<string, object>
        {
            { "Speed", speedMph },
            { "VLA", metrics.VerticalAngle },
            { "HLA", metrics.HorizontalAngle },
            { "TotalSpin", totalSpin },
            { "SpinAxis", metrics.SpinAxis },
            { "BackSpin", backSpin },
            { "SideSpin", sideSpin },
            { "ShotType", metrics.ShotType },
            { "ClubPath", metrics.ClubPath },
            { "FaceAngle", metrics.FaceAngle },
            { "AttackAngle", metrics.AttackAngle },
            { "DynamicLoft", metrics.DynamicLoft },
            { "ClubSpeed", clubSpeedMph },
            { "SmashFactor", smash },
            { "FaceToPath", metrics.FaceAngle - metrics.ClubPath }
        };
    }
}
