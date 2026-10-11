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
}
