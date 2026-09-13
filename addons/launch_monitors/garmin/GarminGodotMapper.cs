using System;
using System.Collections.Generic;
using Godot;
using GodotDictionary = Godot.Collections.Dictionary;

namespace LaunchMonitors.Garmin;

public static class GarminGodotMapper
{
    private const float MetersPerSecondToMph = 2.23694f;

    public static GodotDictionary ToBallData(GarminShotMetrics metrics)
    {
        var totalSpin = Math.Max(0, (int)MathF.Round(metrics.TotalSpinRpm));
        var spinAxis = metrics.SpinAxisDeg;

        var spinAxisRadians = MathF.PI * spinAxis / 180.0f;
        var backSpin = (int)MathF.Round(totalSpin * MathF.Cos(spinAxisRadians));
        var sideSpin = (int)MathF.Round(totalSpin * MathF.Sin(spinAxisRadians));

        var speedMph = metrics.BallSpeedMps * MetersPerSecondToMph;
        var clubSpeedMph = metrics.ClubSpeedMps > 0
            ? metrics.ClubSpeedMps * MetersPerSecondToMph
            : (speedMph > 0 ? speedMph / 1.45f : 0.0f);
        var smash = clubSpeedMph > 0 ? speedMph / clubSpeedMph : 1.45f;

        var data = new GodotDictionary
        {
            ["Speed"] = Variant.From(speedMph),
            ["VLA"] = Variant.From(metrics.VerticalLaunchAngle),
            ["HLA"] = Variant.From(metrics.HorizontalLaunchAngle),
            ["TotalSpin"] = Variant.From(totalSpin),
            ["SpinAxis"] = Variant.From(spinAxis),
            ["BackSpin"] = Variant.From(backSpin),
            ["SideSpin"] = Variant.From(sideSpin),
            ["ShotType"] = Variant.From(0),
            ["ClubPath"] = Variant.From(metrics.ClubPathDeg),
            ["FaceAngle"] = Variant.From(metrics.FaceAngleDeg),
            ["AttackAngle"] = Variant.From(metrics.AttackAngleDeg),
            ["DynamicLoft"] = Variant.From(0.0f),
            ["ClubSpeed"] = Variant.From(clubSpeedMph),
            ["SmashFactor"] = Variant.From(smash),
            ["FaceToPath"] = Variant.From(metrics.FaceAngleDeg - metrics.ClubPathDeg)
        };

        return data;
    }
}
