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
        BounceProfile profile = BounceProfile.ForSurface(parameters?.SurfaceType ?? PhysicsEnums.SurfaceType.Fairway, isBunker);
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
        if (bp == null)
        {
            bp = BounceProfile.ForSurface(parameters?.SurfaceType ?? PhysicsEnums.SurfaceType.Fairway, isBunker);
        }
        else if (isBunker && bp == BounceProfile.Default)
        {
            bp = BounceProfile.Bunker;
        }

        PhysicsEnums.BallState newState = currentState == PhysicsEnums.BallState.Flight
            ? PhysicsEnums.BallState.Rollout
            : currentState;

        Vector3 velNormal = vel.Project(normal);
        float speedNormal = velNormal.Length();
        Vector3 velTangent = vel - velNormal;
        float speedTangent = velTangent.Length();
        Vector3 incomingTangentDir = speedTangent > 0.0001f ? (velTangent / speedTangent) : Vector3.Right;
        Vector3 incomingRollingAxis = normal.Cross(incomingTangentDir);
        if (incomingRollingAxis.LengthSquared() > 0.0001f)
            incomingRollingAxis = incomingRollingAxis.Normalized();
        else
            incomingRollingAxis = Vector3.Forward;
        Vector3 incomingBackspinAxis = -incomingRollingAxis;

        Vector3 omegaNormal = omega.Project(normal);
        Vector3 omegaTangent = omega - omegaNormal;

        float angleToNormal = vel.AngleTo(normal);
        float impactAngle = Mathf.Abs(angleToNormal - Mathf.Pi / 2.0f);

        float omegaTangentMagnitude = omegaTangent.Length();
        float currentSpinRpm = omega.Length() / ShotSetup.RAD_PER_RPM;

        float tangentialRetention;
        float tangentSpinFactor = 1.0f;

        if (currentState == PhysicsEnums.BallState.Flight)
        {
            float excessSpin = Mathf.Max(0.0f, currentSpinRpm - bp.FlightLowSpinThreshold);
            float spinReduction = excessSpin / bp.FlightSpinFactorDivisor;
            tangentSpinFactor = Mathf.Clamp(1.0f - spinReduction * (1.0f - bp.FlightSpinFactorMin), bp.FlightSpinFactorMin, 1.0f);
            tangentialRetention = bp.FlightTangentialRetentionBase * tangentSpinFactor;
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

            bool canSpinback = hasSpinbackSurface && currentSpinRpm >= 4000.0f;
            bool shouldUsePenner = isSteepImpact && (impactSpeed >= bp.PennerLowEnergyThreshold || canSpinback);

            if (!shouldUsePenner)
            {
                float lowEnergyScale = Mathf.Clamp(impactSpeed / bp.PennerLowEnergyThreshold, 0.45f, 1.0f);

                if (!isSteepImpact)
                {
                    float angleRatio = effectiveCriticalAngle > 0.001f
                        ? Mathf.Clamp(impactAngle / effectiveCriticalAngle, 0.0f, 1.0f)
                        : 0.0f;
                    float baseRetention = Mathf.Lerp(bp.ShallowImpactRetentionMin, bp.ShallowImpactRetentionMax, 1.0f - angleRatio);

                    if (parameters != null && parameters.InitialLaunchAngleDeg < 12.0f)
                    {
                        float vlaFactor = Mathf.Clamp(parameters.InitialLaunchAngleDeg / 12.0f, 0.80f, 1.0f);
                        baseRetention *= vlaFactor;
                    }

                    newTangentSpeed = speedTangent * baseRetention * lowEnergyScale;
                    PhysicsLogger.Verbose($"  Bounce: Shallow angle ({impactAngleDeg:F2}° < {criticalAngleDeg:F2}°, retention={baseRetention * lowEnergyScale:F3}) - newTangentSpeed={newTangentSpeed:F2} m/s");
                }
                else
                {
                    newTangentSpeed = speedTangent * tangentialRetention * lowEnergyScale;
                    if (impactSpeed < bp.PennerLowEnergyThreshold && !hasSpinbackSurface)
                        PhysicsLogger.Verbose($"  Bounce: Low energy ({impactSpeed:F2} m/s < {bp.PennerLowEnergyThreshold:F1} m/s) - using simple retention");
                    else
                        PhysicsLogger.Verbose($"  Bounce: Using simple retention (surface={parameters.SurfaceType}, speed={impactSpeed:F2} m/s)");
                    PhysicsLogger.Verbose($"    speedTangent={speedTangent:F2} m/s, newTangentSpeed={newTangentSpeed:F2} m/s");
                }
            }
            else
            {
                float steepDamping = 1.0f;
                if (impactAngleDeg > 45.0f)
                {
                    steepDamping = Mathf.Clamp(1.0f - (impactAngleDeg - 45.0f) * 0.015f, 0.65f, 1.0f);
                }
                float spinbackTerm = 2.0f * BallPhysics.RADIUS * omegaTangentMagnitude * Mathf.Max(parameters.SpinbackResponseScale, 0.0f) / 7.0f;
                float rawNewTangentSpeed = (speedTangent * bp.FlightTangentialRetentionBase * steepDamping) - spinbackTerm;
                newTangentSpeed = rawNewTangentSpeed;

                if (!hasSpinbackSurface)
                {
                    // Non-spinback surfaces (fairway, rough, firm, bunker) never bounce backwards in mid-air
                    newTangentSpeed = Mathf.Max(0.0f, newTangentSpeed);
                }
                else if (speedTangent > 2.0f)
                {
                    // Forward momentum carries the ball forward on first bounce; rollout and 2nd bounce handle spinback
                    // Allow a controlled, realistic check-hop forward (0.20m/s to 0.65m/s) if raw is negative/checking hard
                    if (newTangentSpeed < 0.20f)
                    {
                        newTangentSpeed = Mathf.Clamp(speedTangent * 0.04f, 0.20f, 0.65f);
                    }
                }
                else
                {
                    // High flop shot or vertical drop can check backwards, bounded
                    newTangentSpeed = Mathf.Max(-1.25f, newTangentSpeed);
                }

                PhysicsLogger.Verbose($"  Bounce: Penner model ({parameters.SurfaceType}) speed={impactSpeed:F2} m/s angle={impactAngleDeg:F2}° crit={criticalAngleDeg:F2}°");
                PhysicsLogger.Verbose($"    speedTangent={speedTangent:F2} m/s, spinbackScale={parameters.SpinbackResponseScale:F2}, newTangentSpeed={newTangentSpeed:F2} m/s (raw={rawNewTangentSpeed:F2})");
            }
        }
        else
        {
            // BallState.Rollout (second or subsequent bounce)
            float activeBackspinRad = omegaTangent.Dot(incomingBackspinAxis);
            float activeBackspinRpm = activeBackspinRad / ShotSetup.RAD_PER_RPM;
            float impactAngleDeg = Mathf.RadToDeg(impactAngle);

            bool isSpinbackSurface = parameters != null && (parameters.SpinbackThetaBoostMax > 0.0f || parameters.SpinbackResponseScale > 1.0f);
            bool canReverseBackwards = isSpinbackSurface && activeBackspinRpm >= 3800.0f && impactAngleDeg >= 47.0f;

            if (canReverseBackwards)
            {
                // Active backspin bite into reverse spinback! Only for ultra-high-spin wedge shots landing steep.
                float rolloutSpinbackTerm = (2.0f / 7.0f) * BallPhysics.RADIUS * activeBackspinRad * Mathf.Max(parameters.SpinbackResponseScale, 0.5f);
                newTangentSpeed = (speedTangent * tangentialRetention) - rolloutSpinbackTerm;
                newTangentSpeed = Mathf.Max(-2.6f, newTangentSpeed);
                PhysicsLogger.Verbose($"  Rollout Bounce Spinback: backspin={activeBackspinRpm:F0} rpm, spinbackTerm={rolloutSpinbackTerm:F2}, newTangentSpeed={newTangentSpeed:F2} m/s");
            }
            else if (isSpinbackSurface && activeBackspinRpm > 1800.0f)
            {
                // Moderate backspin (~5,000 - 7,500 RPM launch, ~1,800 - 3,700 RPM residual):
                // Checks forward speed down quickly without ever reversing backwards!
                float rolloutCheckTerm = (2.0f / 7.0f) * BallPhysics.RADIUS * activeBackspinRad * 0.45f;
                float rawSpeed = (speedTangent * tangentialRetention) - rolloutCheckTerm;
                newTangentSpeed = Mathf.Max(0.25f, rawSpeed);
                PhysicsLogger.Verbose($"  Rollout Bounce Forward Check: backspin={activeBackspinRpm:F0} rpm, checkTerm={rolloutCheckTerm:F2}, newTangentSpeed={newTangentSpeed:F2} m/s");
            }
            else
            {
                newTangentSpeed = speedTangent * tangentialRetention;
            }
        }

        if (speedTangent < 0.01f && Mathf.Abs(newTangentSpeed) < 0.01f)
        {
            velTangent = Vector3.Zero;
        }
        else if (newTangentSpeed < 0.0f)
        {
            if (velTangent.LengthSquared() > 0.0001f)
            {
                velTangent = -velTangent.Normalized() * Mathf.Abs(newTangentSpeed);
            }
            else
            {
                // Ball landed nearly vertically; derive spinback direction from ground normal cross spin axis
                Vector3 spinDirection = normal.Cross(omegaTangent);
                velTangent = spinDirection.LengthSquared() > 0.0001f
                    ? spinDirection.Normalized() * Mathf.Abs(newTangentSpeed)
                    : Vector3.Zero;
            }
        }
        else
        {
            velTangent = velTangent.LengthSquared() > 0.0001f
                ? velTangent.Normalized() * newTangentSpeed
                : Vector3.Zero;
        }

        // Add subtle lateral kick from vertical-axis sidespin on impact
        if (currentState == PhysicsEnums.BallState.Flight && velTangent.LengthSquared() > 0.0001f && omegaNormal.LengthSquared() > 0.01f)
        {
            Vector3 tDir = velTangent.Normalized();
            Vector3 lateralDir = normal.Cross(tDir);
            float sideSpinY = omegaNormal.Dot(normal);
            // Sliced ball (sidespin > 0, omega.Y < 0 in standard frame) kicks right
            float kickMag = -sideSpinY * BallPhysics.RADIUS * 0.06f;
            velTangent += lateralDir * Mathf.Clamp(kickMag, -0.6f, 0.6f);
        }

        if (currentState == PhysicsEnums.BallState.Flight)
        {
            float incomingBackspin = omegaTangent.Dot(incomingBackspinAxis);
            float impactAngleDeg = Mathf.RadToDeg(impactAngle);
            bool hasSpinbackSurface = parameters != null && (parameters.SpinbackThetaBoostMax > 0.0f || parameters.SpinbackResponseScale > 1.0f);
            bool inHighSpinCheckRegime = hasSpinbackSurface && (incomingBackspin / ShotSetup.RAD_PER_RPM) >= 8000.0f && impactAngleDeg >= 47.0f;

            if (inHighSpinCheckRegime)
            {
                // High-spin steep check impact: ball checks forward but retains high backspin for second bounce & rollout
                float spinRetentionRatio = Mathf.Clamp(0.55f + (parameters.SpinbackResponseScale - 1.0f) * 0.35f, 0.45f, 0.72f);
                float retainedBackspin = incomingBackspin * spinRetentionRatio;
                omegaTangent = incomingBackspinAxis * retainedBackspin;
            }
            else
            {
                float newOmegaTangent = Mathf.Abs(newTangentSpeed) / BallPhysics.RADIUS;
                if (omegaTangent.Length() < 0.1f || newOmegaTangent < 0.01f)
                {
                    omegaTangent = Vector3.Zero;
                }
                else if (newTangentSpeed < 0.0f)
                {
                    omegaTangent = incomingBackspinAxis * newOmegaTangent;
                }
                else
                {
                    omegaTangent = omegaTangent.LengthSquared() > 0.0001f
                        ? omegaTangent.LimitLength(newOmegaTangent)
                        : Vector3.Zero;
                }
            }
        }
        else
        {
            // Rollout bounces: preserve any active backspin or transition to rolling
            float incomingBackspin = omegaTangent.Dot(incomingBackspinAxis);
            if (incomingBackspin > 40.0f)
            {
                // Still spinning backwards: retain backspin to continue spinback/check on rollout
                float retainedBackspin = incomingBackspin * 0.55f;
                float minBackspinForNegativeVel = Mathf.Abs(newTangentSpeed) / BallPhysics.RADIUS;
                if (newTangentSpeed < 0.0f && retainedBackspin < minBackspinForNegativeVel)
                {
                    retainedBackspin = minBackspinForNegativeVel;
                }
                omegaTangent = incomingBackspinAxis * retainedBackspin;
            }
            else if (newTangentSpeed > 0.05f)
            {
                float existingSpinMag = omegaTangent.Length();
                if (existingSpinMag > 0.05f)
                {
                    omegaTangent = incomingRollingAxis * existingSpinMag;
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
        else
        {
            // Turf impacts damp vertical-axis drill spin
            omegaNormal *= 0.30f;
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

        if (!float.IsFinite(newVelocity.X) || !float.IsFinite(newVelocity.Y) || !float.IsFinite(newVelocity.Z))
        {
            PhysicsLogger.Error("BounceCalculator: Non-finite bounce velocity calculated; resetting to zero.");
            newVelocity = Vector3.Zero;
        }

        if (!float.IsFinite(newOmega.X) || !float.IsFinite(newOmega.Y) || !float.IsFinite(newOmega.Z))
        {
            PhysicsLogger.Error("BounceCalculator: Non-finite bounce omega calculated; resetting to zero.");
            newOmega = Vector3.Zero;
        }

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
