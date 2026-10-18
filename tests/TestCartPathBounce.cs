using System;
using Godot;

public partial class TestCartPathBounce : Node
{
    public override void _Ready()
    {
        var cartPathProfile = BounceProfile.ForSurface(PhysicsEnums.SurfaceType.CartPath);
        var firmProfile = BounceProfile.ForSurface(PhysicsEnums.SurfaceType.Firm);
        var calculator = new BounceCalculator();

        if (cartPathProfile != BounceProfile.CartPath)
            throw new Exception("Cart-path surface should resolve to the dedicated cart-path bounce profile.");
        if (calculator.GetCoefficientOfRestitution(15f, cartPathProfile) <=
            calculator.GetCoefficientOfRestitution(15f, firmProfile))
        {
            throw new Exception("Cart paths should produce a stronger direct-impact bounce than Firm.");
        }
        if (cartPathProfile.RolloutBounceCorScale <= firmProfile.RolloutBounceCorScale)
            throw new Exception("Cart paths should retain more bounce during rollout than Firm.");

        GD.Print("PASS: Cart-path impacts use a stronger dedicated bounce profile.");
    }
}
