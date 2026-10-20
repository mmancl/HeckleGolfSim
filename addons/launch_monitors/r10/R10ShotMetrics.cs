namespace LaunchMonitors.R10;

public readonly record struct R10ShotMetrics(
    float BallSpeedMps,
    float VerticalAngle,
    float HorizontalAngle,
    int TotalSpinRpm,
    float SpinAxis,
    int BackSpinRpm,
    int SideSpinRpm,
    string ShotType = "Unknown",
    float ClubSpeedMps = 0.0f,
    float ClubPath = 0.0f,
    float FaceAngle = 0.0f,
    float AttackAngle = 0.0f,
    float DynamicLoft = 0.0f,
    float SmashFactor = 0.0f);

public readonly record struct R10SensorData(
    bool BallReady,
    bool BallDetected,
    int PositionX,
    int PositionY,
    int PositionZ);
