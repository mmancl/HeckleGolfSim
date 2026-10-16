using System;
using System.Collections.Generic;
using System.Linq;
using Godot;
using HeckleLinks.Courses;

public partial class TestTeeBoxParsing : Node
{
    public override void _Ready()
    {
        GD.Print("==================================================");
        GD.Print("Running OSM Tee Box & Color Parsing Unit Tests");
        GD.Print("==================================================");

        TestParseHoleRefs();
        TestParseTeeColors();
        TestTeeDistancesAndPlacement();
        TestLegacyTeeFallbacksWithoutDistances();

        GD.Print("==================================================");
        GD.Print("ALL TEE BOX & COLOR PARSING TESTS PASSED!");
        GD.Print("==================================================");
    }

    private static void TestParseHoleRefs()
    {
        GD.Print("\n--- Test 1: ParseHoleRefs ---");

        var r1 = OsmMapLoader.ParseHoleRefs("1");
        if (r1.Count != 1 || r1[0] != "1")
            throw new Exception($"Expected ['1'], got [{string.Join(", ", r1)}]");

        var r2 = OsmMapLoader.ParseHoleRefs("1;2; 3");
        if (r2.Count != 3 || r2[0] != "1" || r2[1] != "2" || r2[2] != "3")
            throw new Exception($"Expected ['1', '2', '3'], got [{string.Join(", ", r2)}]");

        var r3 = OsmMapLoader.ParseHoleRefs("hole 4/Hole 5");
        if (r3.Count != 2 || r3[0] != "4" || r3[1] != "5")
            throw new Exception($"Expected ['4', '5'], got [{string.Join(", ", r3)}]");

        var r4 = OsmMapLoader.ParseHoleRefs("#9");
        if (r4.Count != 1 || r4[0] != "9")
            throw new Exception($"Expected ['9'], got [{string.Join(", ", r4)}]");

        GD.Print("  PASS: ParseHoleRefs correctly parsed multi-hole and formatted refs.");
    }

    private static void TestParseTeeColors()
    {
        GD.Print("\n--- Test 2: ParseTeeColors ---");

        // Semicolon multi-color tag (like Hilly Haven)
        var tags1 = new Dictionary<string, string> { { "tee", "blue;white" } };
        var c1 = OsmMapLoader.ParseTeeColors(tags1);
        if (c1.Count != 2 || !c1.Contains("Blue") || !c1.Contains("White"))
            throw new Exception($"Expected Blue and White, got [{string.Join(", ", c1)}]");

        // 4 colors semicolon-separated
        var tags2 = new Dictionary<string, string> { { "tee", "blue;white;gold;red" } };
        var c2 = OsmMapLoader.ParseTeeColors(tags2);
        if (c2.Count != 4 || !c2.Contains("Blue") || !c2.Contains("White") || !c2.Contains("Gold") || !c2.Contains("Red"))
            throw new Exception($"Expected Blue, White, Gold, Red, got [{string.Join(", ", c2)}]");

        // colour / color tags
        var tags3 = new Dictionary<string, string> { { "colour", "orange" } };
        var c3 = OsmMapLoader.ParseTeeColors(tags3);
        if (c3.Count != 1 || c3[0] != "Orange")
            throw new Exception($"Expected Orange, got [{string.Join(", ", c3)}]");

        var tags4 = new Dictionary<string, string> { { "tee:color", "green" } };
        var c4 = OsmMapLoader.ParseTeeColors(tags4);
        if (c4.Count != 1 || c4[0] != "Green")
            throw new Exception($"Expected Green, got [{string.Join(", ", c4)}]");

        // tee=yes with role
        var tags5 = new Dictionary<string, string> { { "tee", "yes" } };
        var c5 = OsmMapLoader.ParseTeeColors(tags5, "tee:gold");
        if (c5.Count != 1 || c5[0] != "Gold")
            throw new Exception($"Expected Gold, got [{string.Join(", ", c5)}]");

        // tee=yes with name fallback
        var tags6 = new Dictionary<string, string> { { "tee", "yes" }, { "name", "Black Tee Pad" } };
        var c6 = OsmMapLoader.ParseTeeColors(tags6);
        if (c6.Count != 1 || c6[0] != "Black")
            throw new Exception($"Expected Black, got [{string.Join(", ", c6)}]");

        // No tags fallback
        var tags7 = new Dictionary<string, string>();
        var c7 = OsmMapLoader.ParseTeeColors(tags7);
        if (c7.Count != 1 || c7[0] != "Blue")
            throw new Exception($"Expected fallback Blue, got [{string.Join(", ", c7)}]");

        GD.Print("  PASS: ParseTeeColors correctly extracted single and multi-color tees.");
    }

    private static void TestTeeDistancesAndPlacement()
    {
        GD.Print("\n--- Test 3: Tee distances and placement ---");

        var distances = OsmMapLoader.ParseTeeDistances(new Dictionary<string, string>
        {
            { "dist:blue", "440" },
            { "dist:white", "128 m" }
        });
        if (Math.Abs(distances["Blue"] - 402.336f) > 0.01f)
            throw new Exception($"Unitless dist:blue should parse as 440 yards, got {distances["Blue"]} meters");
        if (Math.Abs(distances["White"] - 128f) > 0.01f)
            throw new Exception($"Explicit meter dist:white should remain 128 meters, got {distances["White"]}");

        var holePath = new List<float[]>
        {
            new[] { 0f, 0f },
            new[] { 0f, 100f },
            new[] { 100f, 100f }
        };
        var target = OsmMapLoader.GetPointAtDistanceFromHoleEnd(holePath, 50f);
        if (target.DistanceTo(new Vector2(50f, 100f)) > 0.01f)
            throw new Exception($"Distance should be measured backward from the hole end, got {target}");

        var teePolygon = new[]
        {
            new Vector2(40f, 90f),
            new Vector2(60f, 90f),
            new Vector2(60f, 110f),
            new Vector2(40f, 110f)
        };
        var closestTeePoint = OsmMapLoader.GetClosestPointInPolygon(new Vector2(20f, 100f), teePolygon);
        if (closestTeePoint.DistanceTo(new Vector2(40f, 100f)) > 0.01f)
            throw new Exception($"Tee placement should project to the closest point inside its color polygon, got {closestTeePoint}");
        if (OsmMapLoader.GetDistanceToTeeCandidate(new Vector2(50f, 100f), new Vector2(0f, 0f), teePolygon) > 0.01f)
            throw new Exception("An unreferenced tee inside an existing tee polygon should match that tee area by proximity.");

        GD.Print("  PASS: dist:* units, backward path measurement, and tee-area projection.");
    }

    private static void TestLegacyTeeFallbacksWithoutDistances()
    {
        GD.Print("\n--- Test 4: Legacy tee fallbacks without distance tags ---");

        var hole = new OsmMapLoader.HoleConfig
        {
            HoleLocation = new[] { 100f, 0f },
            TeeBoxes = new Dictionary<string, float[]>
            {
                { "Gold", new[] { 0f, 0f } },
                { "Orange", new[] { 80f, 0f } }
            }
        };
        OsmMapLoader.ApplyLegacyTeeFallbacks(hole);

        if (hole.TeeBoxes["Blue"][0] != 0f || hole.TeeBoxes["White"][0] != 0f)
            throw new Exception("Without dist:* tags, Blue and White should retain the legacy fallback tee.");
        if (hole.TeeBoxes["Red"][0] != 80f)
            throw new Exception("Without dist:* tags, Red should retain the legacy tee closest to the pin.");

        GD.Print("  PASS: Legacy standard-color tee fallbacks remain active without dist:* tags.");
    }
}
