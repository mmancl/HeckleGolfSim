using Godot;

/// <summary>
/// Bounce physics calculations extracted from BallPhysics.
/// Handles impact bounce resolution, coefficient of restitution, and critical angle computation.
/// </summary>
[GlobalClass]
public partial class BounceCalculator : RefCounted
{
    /// <summary>
    /// Calculate bounce physics when ball impacts surface
    /// </summary>
    public BounceResult CalculateBounce(
        Vector3 vel,
        Vector3 omega,
        Vector3 normal,
        PhysicsEnums.BallState currentState,
        PhysicsParams parameters)
    {
        bool isBunker = (parameters?.SurfaceType == PhysicsEnums.SurfaceType.Bunker) || (parameters?.IsInSand == true);
        BounceProfile profile = isBunker ? BounceProfile.Bunker : BounceProfile.Default;
        return CalculateBounce(vel, omega, normal, currentState, parameters, profile);
    }

    /// <summary>
    /// Get coefficient of restitution based on impact speed
    /// </summary>
    public float GetCoefficientOfRestitution(float speedNormal)
    {
        return GetCoefficientOfRestitution(speedNormal, BounceProfile.Default);
    }

    public float GetCoefficientOfRestitution(float speedNormal, BounceProfile bp)
    {
        if (speedNormal > bp.CorHighSpeedThreshold)
            return bp.CorHighSpeedCap;
        else if (speedNormal < bp.CorKillThreshold)
            return 0.0f;
        else
        {
            return bp.CorBaseA + bp.CorBaseB * speedNormal + bp.CorBaseC * speedNormal * speedNormal;
        }
    }

    // ── Profile-aware overload ──

    public BounceResult CalculateBounce(
        Vector3 vel,
        Vector3 omega,
        Vector3 normal,
        PhysicsEnums.BallState currentState,
        PhysicsParams parameters,
        BounceProfile bp)
    {
        bool isBunker = (parameters?.SurfaceType == PhysicsEnums.SurfaceType.Bunker) || (parameters?.IsInSand == true);
        if (isBunker && (bp == null || bp == BounceProfile.Default))
        {
            bp = BounceProfile.Bunker;
        }
        else if (bp == null)
        {
            bp = BounceProfile.Default;
        }

        PhysicsEnums.BallState newState = currentState == PhysicsEnums.BallState.Flight
            ? PhysicsEnums.BallState.Rollout
            : currentState;

        Vector3 velNormal = vel.Project(normal);
        float speedNormal = velNormal.Length();
        Vector3 velTangent = vel - velNormal;
        float speedTangent = velTangent.Length();

        Vector3 omegaNormal = omega.Project(normal);
        Vector3 omegaTangent = omega - omegaNormal;

        float angleToNormal = vel.AngleTo(normal);
        float impactAngle = Mathf.Abs(angleToNormal - Mathf.Pi / 2.0f);

        float omegaTangentMagnitude = omegaTangent.Length();
        float currentSpinRpm = omega.Length() / ShotSetup.RAD_PER_RPM;

        float tangentialRetention;

        if (currentState == PhysicsEnums.BallState.Flight)
        {
            float spinFactor = Mathf.Clamp(1.0f - (currentSpinRpm / bp.FlightSpinFactorDivisor), bp.FlightSpinFactorMin, 1.0f);
            tangentialRetention = bp.FlightTangentialRetentionBase * spinFactor;
        }
        else
        {
            float ballSpeed = vel.Length();
            float spinRatio = ballSpeed > 0.1f ? (omega.Length() * BallPhysics.RADIUS) / ballSpeed : 0.0f;

            if (spinRatio < bp.RolloutSpinRatioThreshold)
            {
                tangentialRetention = Mathf.Lerp(bp.RolloutLowSpinRetention, bp.RolloutHighSpinRetention, spinRatio / bp.RolloutSpinRatioThreshold);
            }
            else
            {
                tangentialRetention = bp.RolloutHighSpinRetention;
            }
        }

        if (newState == PhysicsEnums.BallState.Rollout)
        {
            PhysicsLogger.Verbose($"  Bounce: spin={currentSpinRpm:F0} rpm, retention={tangentialRetention:F3}");
        }

        float newTangentSpeed;

        if (currentState == PhysicsEnums.BallState.Flight)
        {
            float impactSpeed = vel.Length();
            bool hasSpinbackSurface = parameters.SpinbackThetaBoostMax > 0.0f || parameters.SpinbackResponseScale > 1.0f;
            float effectiveCriticalAngle = GetEffectiveCriticalAngle(parameters, currentSpinRpm, impactSpeed, currentState);
            float impactAngleDeg = Mathf.RadToDeg(impactAngle);
            float criticalAngleDeg = Mathf.RadToDeg(effectiveCriticalAngle);
            bool isSteepImpact = impactAngle >= effectiveCriticalAngle;

            bool shouldUsePenner = isSteepImpact && (impactSpeed >= bp.PennerLowEnergyThreshold || hasSpinbackSurface);

            if (!shouldUsePenner)
            {
                newTangentSpeed = speedTangent * tangentialRetention;
                if (!isSteepImpact)
                    PhysicsLogger.Verbose($"  Bounce: Shallow angle ({impactAngleDeg:F2}° < {criticalAngleDeg:F2}°) - using simple retention");
                else if (impactSpeed < bp.PennerLowEnergyThreshold && !hasSpinbackSurface)
                    PhysicsLogger.Verbose($"  Bounce: Low energy ({impactSpeed:F2} m/s < {bp.PennerLowEnergyThreshold:F1} m/s) - using simple retention");
                else
                    PhysicsLogger.Verbose($"  Bounce: Using simple retention (surface={parameters.SurfaceType}, speed={impactSpeed:F2} m/s)");
                PhysicsLogger.Verbose($"    speedTangent={speedTangent:F2} m/s, newTangentSpeed={newTangentSpeed:F2} m/s");
            }
            else
            {
                float spinbackTerm = 2.0f * BallPhysics.RADIUS * omegaTangentMagnitude * Mathf.Max(parameters.SpinbackResponseScale, 0.0f) / 7.0f;
                newTangentSpeed = tangentialRetention * vel.Length() * Mathf.Sin(impactAngle - effectiveCriticalAngle) -
                    spinbackTerm;
                PhysicsLogger.Verbose($"  Bounce: Penner model ({parameters.SurfaceType}) speed={impactSpeed:F2} m/s angle={impactAngleDeg:F2}° crit={criticalAngleDeg:F2}°");
                PhysicsLogger.Verbose($"    speedTangent={speedTangent:F2} m/s, spinbackScale={parameters.SpinbackResponseScale:F2}, newTangentSpeed={newTangentSpeed:F2} m/s");
            }
        }
        else
        {
            newTangentSpeed = speedTangent * tangentialRetention;
        }

        if (speedTangent < 0.01f && Mathf.Abs(newTangentSpeed) < 0.01f)
        {
            velTangent = Vector3.Zero;
        }
        else if (newTangentSpeed < 0.0f)
        {
            velTangent = -velTangent.Normalized() * Mathf.Abs(newTangentSpeed);
        }
        else
        {
            velTangent = velTangent.LimitLength(newTangentSpeed);
        }

        if (currentState == PhysicsEnums.BallState.Flight)
        {
            float newOmegaTangent = Mathf.Abs(newTangentSpeed) / BallPhysics.RADIUS;
            if (omegaTangent.Length() < 0.1f || newOmegaTangent < 0.01f)
            {
                omegaTangent = Vector3.Zero;
            }
            else if (newTangentSpeed < 0.0f)
            {
                omegaTangent = -omegaTangent.Normalized() * newOmegaTangent;
            }
            else
            {
                omegaTangent = omegaTangent.LimitLength(newOmegaTangent);
            }
        }
        else
        {
            if (newTangentSpeed > 0.05f)
            {
                float existingSpinMag = omegaTangent.Length();
                Vector3 tangentDir = velTangent.Length() > 0.01f ? velTangent.Normalized() : Vector3.Right;
                Vector3 rollingAxis = normal.Cross(tangentDir).Normalized();

                if (existingSpinMag > 0.05f)
                {
                    omegaTangent = rollingAxis * existingSpinMag;
                }
                else
                {
                    omegaTangent = Vector3.Zero;
                }
            }
            else
            {
                omegaTangent = Vector3.Zero;
            }
        }

        if (isBunker)
        {
            omegaTangent *= 0.15f;
            omegaNormal *= 0.10f;
        }

        float cor;
        if (currentState == PhysicsEnums.BallState.Flight)
        {
            float baseCor = GetCoefficientOfRestitution(speedNormal, bp);
            float spinRpm = omega.Length() / ShotSetup.RAD_PER_RPM;
            float spinCORReduction = 0.0f;

            if (isBunker)
            {
                cor = baseCor;
            }
            else
            {

                float corVelocityScale;
                if (speedNormal < bp.CorVelocityLowThreshold)
                {
                    corVelocityScale = Mathf.Lerp(0.0f, bp.CorVelocityLowScale, speedNormal / bp.CorVelocityLowThreshold);
                }
                else if (speedNormal < bp.CorVelocityMidThreshold)
                {
                    corVelocityScale = Mathf.Lerp(bp.CorVelocityLowScale, 1.0f, (speedNormal - bp.CorVelocityLowThreshold) / (bp.CorVelocityMidThreshold - bp.CorVelocityLowThreshold));
                }
                else
                {
                    corVelocityScale = 1.0f;
                }

                if (spinRpm < bp.SpinCorLowSpinThreshold)
                {
                    spinCORReduction = (spinRpm / bp.SpinCorLowSpinThreshold) * bp.SpinCorLowSpinMaxReduction;
                }
                else
                {
                    float excessSpin = spinRpm - bp.SpinCorLowSpinThreshold;
                    float spinFactor = Mathf.Min(excessSpin / bp.SpinCorHighSpinRangeRpm, 1.0f);
                    float maxReduction = bp.SpinCorLowSpinMaxReduction + spinFactor * bp.SpinCorHighSpinAdditionalReduction;
                    spinCORReduction = maxReduction * corVelocityScale;
                }

                cor = baseCor * (1.0f - spinCORReduction);
            }

            if (newState == PhysicsEnums.BallState.Rollout)
            {
                PhysicsLogger.Verbose($"    speedNormal={speedNormal:F2} m/s, spin={spinRpm:F0} rpm");
                PhysicsLogger.Verbose($"    baseCOR={baseCor:F3}, spinReduction={spinCORReduction:F2}, finalCOR={cor:F3}");
                PhysicsLogger.Verbose($"    velNormal will be {speedNormal * cor:F2} m/s");
            }
        }
        else
        {
            if (speedNormal < bp.RolloutBounceCorKillThreshold)
            {
                cor = 0.0f;
            }
            else
            {
                cor = GetCoefficientOfRestitution(speedNormal, bp) * bp.RolloutBounceCorScale;
            }

            if (speedNormal > 0.5f)
            {
                PhysicsLogger.Verbose($"    speedNormal={speedNormal:F2} m/s, COR={cor:F3}, velNormal will be {speedNormal * cor:F2} m/s");
            }
        }

        velNormal = velNormal * -cor;

        Vector3 newOmega = omegaNormal + omegaTangent;
        Vector3 newVelocity = velNormal + velTangent;

        return new BounceResult(newVelocity, newOmega, newState);
    }

    /// <summary>
    /// Greens can exhibit stronger check/spinback on steep, high-spin impacts.
    /// Model this as an effective increase in critical angle for high-spin wedge/flop
    /// impacts, while leaving lower-spin/low-speed impacts unchanged.
    /// </summary>
    internal static float GetEffectiveCriticalAngle(
        PhysicsParams parameters,
        float currentSpinRpm,
        float impactSpeed,
        PhysicsEnums.BallState currentState)
    {
        if (currentState != PhysicsEnums.BallState.Flight ||
            parameters.SpinbackThetaBoostMax <= 0.0f)
        {
            return parameters.CriticalAngle;
        }

        float spinRange = parameters.SpinbackSpinEndRpm - parameters.SpinbackSpinStartRpm;
        float spinT = spinRange > 0.0f
            ? Mathf.Clamp((currentSpinRpm - parameters.SpinbackSpinStartRpm) / spinRange, 0.0f, 1.0f)
            : 0.0f;
        spinT = spinT * spinT * (3.0f - 2.0f * spinT);

        float speedRange = parameters.SpinbackSpeedEndMps - parameters.SpinbackSpeedStartMps;
        float speedT = speedRange > 0.0f
            ? Mathf.Clamp((impactSpeed - parameters.SpinbackSpeedStartMps) / speedRange, 0.0f, 1.0f)
            : 0.0f;
        speedT = speedT * speedT * (3.0f - 2.0f * speedT);

        float boost = parameters.SpinbackThetaBoostMax * spinT * speedT;
        return parameters.CriticalAngle + boost;
    }
}
