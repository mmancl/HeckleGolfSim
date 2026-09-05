/// <summary>
/// Centralizes all bounce/COR constants from BallPhysics.CalculateBounce.
/// Default values match the prior hardcoded constants for behavioral parity.
/// </summary>
public sealed class BounceProfile
{
    // --- COR curve ---
    public float CorBaseA { get; init; } = 0.45f;
    public float CorBaseB { get; init; } = -0.01f;
    public float CorBaseC { get; init; } = 0.0002f;
    public float CorHighSpeedCap { get; init; } = 0.25f;
    public float CorHighSpeedThreshold { get; init; } = 20.0f;
    public float CorKillThreshold { get; init; } = 2.0f;

    // --- Tangential retention (first bounce from flight) ---
    public float FlightTangentialRetentionBase { get; init; } = 0.60f;
    public float FlightSpinFactorMin { get; init; } = 0.40f;
    public float FlightSpinFactorDivisor { get; init; } = 8000.0f;

    // --- Tangential retention (rollout bounces) ---
    public float RolloutLowSpinRetention { get; init; } = 0.865f;
    public float RolloutHighSpinRetention { get; init; } = 0.725f;
    public float RolloutSpinRatioThreshold { get; init; } = 0.20f;

    // --- Spin COR reduction ---
    public float SpinCorLowSpinThreshold { get; init; } = 1500.0f;
    public float SpinCorLowSpinMaxReduction { get; init; } = 0.30f;
    public float SpinCorHighSpinRangeRpm { get; init; } = 1500.0f;
    public float SpinCorHighSpinAdditionalReduction { get; init; } = 0.40f;

    // --- Velocity scaling for COR reduction ---
    public float CorVelocityLowThreshold { get; init; } = 12.0f;
    public float CorVelocityMidThreshold { get; init; } = 25.0f;
    public float CorVelocityLowScale { get; init; } = 0.50f;

    // --- Rollout bounce COR ---
    public float RolloutBounceCorKillThreshold { get; init; } = 4.0f;
    public float RolloutBounceCorScale { get; init; } = 0.5f;

    // --- Penner model ---
    public float PennerLowEnergyThreshold { get; init; } = 20.0f;

    // --- Metadata ---
    public string Name { get; init; } = "Default";
    public string Version { get; init; } = "1.0";

    public static BounceProfile Default { get; } = new();

    public static BounceProfile Bunker { get; } = new()
    {
        Name = "Bunker",
        Version = "1.0",
        CorBaseA = 0.08f,
        CorBaseB = -0.003f,
        CorBaseC = 0.00004f,
        CorHighSpeedCap = 0.05f,
        CorHighSpeedThreshold = 15.0f,
        CorKillThreshold = 3.5f,
        FlightTangentialRetentionBase = 0.18f,
        FlightSpinFactorMin = 0.20f,
        FlightSpinFactorDivisor = 4000.0f,
        RolloutLowSpinRetention = 0.30f,
        RolloutHighSpinRetention = 0.20f,
        RolloutSpinRatioThreshold = 0.20f,
        RolloutBounceCorKillThreshold = 6.0f,
        RolloutBounceCorScale = 0.15f,
        PennerLowEnergyThreshold = 30.0f
    };
}
