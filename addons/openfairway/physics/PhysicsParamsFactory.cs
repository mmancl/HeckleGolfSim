using Godot;

/// <summary>
/// Resolves environment, surface, and ball-profile inputs into the final
/// parameters consumed by the physics engine.
/// </summary>
[GlobalClass]
public partial class PhysicsParamsFactory : RefCounted
{
	private BallPhysicsProfile _ballProfile = new();

	public BallPhysicsProfile BallProfile
	{
		get => _ballProfile;
		set => _ballProfile = value ?? new BallPhysicsProfile();
	}

	public void LoadProfileFromJson(string json)
	{
		_ballProfile = BallPhysicsProfile.FromJson(json);
	}

	public ResolvedPhysicsParams Create(
		float airDensity,
		float airViscosity,
		float dragScale,
		float liftScale,
		PhysicsEnums.SurfaceType surfaceType,
		Vector3 floorNormal,
		float rolloutImpactSpin = 0.0f,
		BallPhysicsProfile ballProfile = null,
		float initialLaunchAngleDeg = 0.0f,
		float launchSpeedMph = 0.0f,
		float launchSpinRpm = 0.0f,
		bool isPutt = false,
		float lateralCurveScale = 1.0f)
	{
		BallPhysicsProfile profile = ballProfile ?? _ballProfile ?? new BallPhysicsProfile();
		SurfacePhysicsSettings surface = SurfacePhysicsCatalog.Get(surfaceType);
		RegimeScaleOverride regimeScale = profile.ResolveScaleOverride(
			launchSpeedMph,
			initialLaunchAngleDeg,
			launchSpinRpm,
			out string regimeKey,
			out string matchedOverrideKey
		);

		if (!string.IsNullOrEmpty(matchedOverrideKey))
		{
			PhysicsLogger.Info($"[Regime] {regimeKey} matched={matchedOverrideKey} drag={regimeScale.DragScaleMultiplier:F3} lift={regimeScale.LiftScaleMultiplier:F3}");
		}

		return new ResolvedPhysicsParams(
			airDensity,
			airViscosity,
			dragScale * profile.DragScaleMultiplier * regimeScale.DragScaleMultiplier,
			liftScale * profile.LiftScaleMultiplier * regimeScale.LiftScaleMultiplier,
			surface.KineticFriction * profile.KineticFrictionMultiplier * regimeScale.KineticFrictionMultiplier,
			surface.RollingFriction * profile.RollingFrictionMultiplier * regimeScale.RollingFrictionMultiplier,
			surface.GrassViscosity * profile.GrassViscosityMultiplier * regimeScale.GrassViscosityMultiplier,
			surface.CriticalAngle + profile.CriticalAngleOffsetRadians + regimeScale.CriticalAngleOffsetRadians,
			surfaceType,
			floorNormal,
			rolloutImpactSpin,
			surface.SpinbackResponseScale,
			surface.SpinbackThetaBoostMax * profile.SpinbackThetaBoostMultiplier * regimeScale.SpinbackThetaBoostMultiplier,
			surface.SpinbackSpinStartRpm,
			surface.SpinbackSpinEndRpm,
			surface.SpinbackSpeedStartMps,
			surface.SpinbackSpeedEndMps,
			initialLaunchAngleDeg,
			profile.ResolvedFlight,
			isPutt: isPutt,
			lateralCurveScale: lateralCurveScale
		);
	}

	public PhysicsParams CreateParams(
		float airDensity,
		float airViscosity,
		float dragScale,
		float liftScale,
		PhysicsEnums.SurfaceType surfaceType,
		Vector3 floorNormal,
		float rolloutImpactSpin = 0.0f,
		float initialLaunchAngleDeg = 0.0f,
		float launchSpeedMph = 0.0f,
		float launchSpinRpm = 0.0f,
		bool isPutt = false,
		float lateralCurveScale = 1.0f)
	{
		return Create(
			airDensity,
			airViscosity,
			dragScale,
			liftScale,
			surfaceType,
			floorNormal,
			rolloutImpactSpin,
			_ballProfile,
			initialLaunchAngleDeg,
			launchSpeedMph,
			launchSpinRpm,
			isPutt,
			lateralCurveScale
		).ToPhysicsParams();
	}

	public PhysicsParams CreateParams(
		float airDensity,
		float airViscosity,
		float dragScale,
		float liftScale,
		int surfaceType,
		Vector3 floorNormal,
		float rolloutImpactSpin = 0.0f,
		float initialLaunchAngleDeg = 0.0f,
		float launchSpeedMph = 0.0f,
		float launchSpinRpm = 0.0f,
		bool isPutt = false,
		float lateralCurveScale = 1.0f)
	{
		return CreateParams(
			airDensity,
			airViscosity,
			dragScale,
			liftScale,
			(PhysicsEnums.SurfaceType)surfaceType,
			floorNormal,
			rolloutImpactSpin,
			initialLaunchAngleDeg,
			launchSpeedMph,
			launchSpinRpm,
			isPutt,
			lateralCurveScale
		);
	}

	public PhysicsParams CreateParams(
		float airDensity,
		float airViscosity,
		float dragScale,
		float liftScale,
		PhysicsEnums.SurfaceType surfaceType,
		Vector3 floorNormal,
		float rolloutImpactSpin,
		float initialLaunchAngleDeg,
		float launchSpeedMph,
		float launchSpinRpm)
	{
		return CreateParams(
			airDensity,
			airViscosity,
			dragScale,
			liftScale,
			surfaceType,
			floorNormal,
			rolloutImpactSpin,
			initialLaunchAngleDeg,
			launchSpeedMph,
			launchSpinRpm,
			false
		);
	}

	public PhysicsParams CreateParams(
		float airDensity,
		float airViscosity,
		float dragScale,
		float liftScale,
		int surfaceType,
		Vector3 floorNormal,
		float rolloutImpactSpin,
		float initialLaunchAngleDeg,
		float launchSpeedMph,
		float launchSpinRpm)
	{
		return CreateParams(
			airDensity,
			airViscosity,
			dragScale,
			liftScale,
			(PhysicsEnums.SurfaceType)surfaceType,
			floorNormal,
			rolloutImpactSpin,
			initialLaunchAngleDeg,
			launchSpeedMph,
			launchSpinRpm,
			false
		);
	}

	public void ConfigureShot(
		PhysicsParams parameters,
		float airDensity,
		float airViscosity,
		float dragScale,
		float liftScale,
		float initialLaunchAngleDeg,
		float launchSpeedMph,
		float launchSpinRpm,
		bool isPutt = false)
	{
		ConfigureShot(
			parameters,
			airDensity,
			airViscosity,
			dragScale,
			liftScale,
			initialLaunchAngleDeg,
			launchSpeedMph,
			launchSpinRpm,
			isPutt,
			1.0f
		);
	}

	public void ConfigureShot(
		PhysicsParams parameters,
		float airDensity,
		float airViscosity,
		float dragScale,
		float liftScale,
		float initialLaunchAngleDeg,
		float launchSpeedMph,
		float launchSpinRpm,
		bool isPutt,
		float lateralCurveScale)
	{
		if (parameters == null)
			return;

		RegimeScaleOverride regimeScale = _ballProfile.ResolveScaleOverride(
			launchSpeedMph,
			initialLaunchAngleDeg,
			launchSpinRpm,
			out string regimeKey,
			out string matchedOverrideKey
		);

		if (!string.IsNullOrEmpty(matchedOverrideKey))
		{
			PhysicsLogger.Info($"[Regime] {regimeKey} matched={matchedOverrideKey} drag={regimeScale.DragScaleMultiplier:F3} lift={regimeScale.LiftScaleMultiplier:F3}");
		}

		parameters.AirDensity = airDensity;
		parameters.AirViscosity = airViscosity;
		parameters.InitialLaunchAngleDeg = initialLaunchAngleDeg;
		parameters.DragScale = dragScale * _ballProfile.DragScaleMultiplier * regimeScale.DragScaleMultiplier;
		parameters.LiftScale = liftScale * _ballProfile.LiftScaleMultiplier * regimeScale.LiftScaleMultiplier;
		parameters.FlightProfile = _ballProfile.ResolvedFlight;
		parameters.IsPutt = isPutt;
		parameters.LateralCurveScale = lateralCurveScale;
	}

	public Godot.Collections.Dictionary GetRegimeInfo(float launchSpeedMph, float launchAngleDeg, float launchSpinRpm)
	{
		RegimeScaleOverride regimeScale = _ballProfile.ResolveScaleOverride(
			launchSpeedMph,
			launchAngleDeg,
			launchSpinRpm,
			out string regimeKey,
			out string matchedOverrideKey
		);

		return new Godot.Collections.Dictionary
		{
			{ "regime_key", regimeKey },
			{ "matched_key", matchedOverrideKey },
			{ "drag_multiplier", _ballProfile.DragScaleMultiplier * regimeScale.DragScaleMultiplier },
			{ "lift_multiplier", _ballProfile.LiftScaleMultiplier * regimeScale.LiftScaleMultiplier },
			{ "profile_drag_multiplier", _ballProfile.DragScaleMultiplier },
			{ "profile_lift_multiplier", _ballProfile.LiftScaleMultiplier },
			{ "regime_drag_multiplier", regimeScale.DragScaleMultiplier },
			{ "regime_lift_multiplier", regimeScale.LiftScaleMultiplier },
			{ "flight_profile_name", _ballProfile.ResolvedFlight.Name }
		};
	}
}
