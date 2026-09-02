namespace LaunchMonitors.Square;

public readonly record struct SquareShotMetrics(
    float BallSpeedMps,
    float VerticalAngle,
    float HorizontalAngle,
    int TotalSpinRpm,
    float SpinAxis,
    int BackSpinRpm,
    int SideSpinRpm,
    string ShotType,
    float ClubPath = 0.0f,
    float FaceAngle = 0.0f,
    float AttackAngle = 0.0f,
    float DynamicLoft = 0.0f,
    float ClubSpeedMps = 0.0f,
    float SmashFactor = 0.0f);

public readonly record struct SquareSensorData(
    bool BallReady,
    bool BallDetected,
    int PositionX,
    int PositionY,
    int PositionZ);
