namespace LaunchMonitors.Garmin;

public sealed record GarminShotMetrics(
    uint ShotId,
    float BallSpeedMps,
    float VerticalLaunchAngle,
    float HorizontalLaunchAngle,
    float TotalSpinRpm,
    float SpinAxisDeg,
    float ClubSpeedMps,
    float ClubPathDeg,
    float FaceAngleDeg,
    float AttackAngleDeg);
