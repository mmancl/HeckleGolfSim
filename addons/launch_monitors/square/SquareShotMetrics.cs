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
    float ClubPath = 0.0f);

public readonly record struct SquareSensorData(
    bool BallReady,
    bool BallDetected,
    int PositionX,
    int PositionY,
    int PositionZ);
