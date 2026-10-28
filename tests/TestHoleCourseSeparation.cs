using System;
using System.Collections.Generic;
using Godot;
using HeckleLinks.Courses;

public partial class TestHoleCourseSeparation : Node
{
    public override void _Ready()
    {
        GD.Print("==================================================");
        GD.Print("Running OSM Course Hole Separation Tests");
        GD.Print("==================================================");

        TestCourseNameMatches();
        TestPolygonDistances();
        TestLittleHavenAndHillyHavenSeparation();
        TestBoundaryToleranceEdgeCases();

        GD.Print("==================================================");
        GD.Print("ALL OSM COURSE HOLE SEPARATION TESTS PASSED!");
        GD.Print("==================================================");
    }

    private static void TestCourseNameMatches()
    {
        GD.Print("\n--- Test 1: CourseNameMatches ---");

        if (!OsmMapLoader.CourseNameMatches("Little Haven Golf Course", "Little Haven"))
            throw new Exception("Expected 'Little Haven Golf Course' to match 'Little Haven'");

        if (!OsmMapLoader.CourseNameMatches("Little Haven", "Little Haven Golf Course"))
            throw new Exception("Expected 'Little Haven' to match 'Little Haven Golf Course'");

        if (OsmMapLoader.CourseNameMatches("Little Haven Golf Course", "Hilly Haven Golf Course"))
            throw new Exception("Did not expect 'Little Haven' to match 'Hilly Haven'");

        if (OsmMapLoader.CourseNameMatches("Hilly Haven", "Little Haven"))
            throw new Exception("Did not expect 'Hilly Haven' to match 'Little Haven'");

        if (!OsmMapLoader.CourseNameMatches("Pebble Beach Golf Links", "Pebble Beach"))
            throw new Exception("Expected 'Pebble Beach Golf Links' to match 'Pebble Beach'");

        if (!OsmMapLoader.CourseNameMatches("Augusta National Golf Club", "Augusta National"))
            throw new Exception("Expected 'Augusta National Golf Club' to match 'Augusta National'");

        GD.Print("  PASS: CourseNameMatches handles variations, club/course suffixes, and prevents false matches.");
    }

    private static void TestPolygonDistances()
    {
        GD.Print("\n--- Test 2: DistancePointToPolygonWithInterior & DistancePointToPolygonList ---");

        // Square polygon from (0,0) to (100, 100)
        var square = new[]
        {
            new Vector2(0f, 0f),
            new Vector2(100f, 0f),
            new Vector2(100f, 100f),
            new Vector2(0f, 100f)
        };

        // Point inside
        float dInside = OsmMapLoader.DistancePointToPolygonWithInterior(new Vector2(50f, 50f), square);
        if (Math.Abs(dInside) > 0.001f)
            throw new Exception($"Expected 0 for inside point, got {dInside}");

        // Point outside perpendicular (at 120, 50 -> distance 20)
        float dOutsideEdge = OsmMapLoader.DistancePointToPolygonWithInterior(new Vector2(120f, 50f), square);
        if (Math.Abs(dOutsideEdge - 20f) > 0.1f)
            throw new Exception($"Expected 20 for outside edge point, got {dOutsideEdge}");

        // List of polygons
        var polys = new List<Vector2[]> { square };
        float dList = OsmMapLoader.DistancePointToPolygonList(new Vector2(-15f, 50f), polys);
        if (Math.Abs(dList - 15f) > 0.1f)
            throw new Exception($"Expected 15 for polygon list distance, got {dList}");

        GD.Print("  PASS: Polygon distance calculations verified.");
    }

    private static void TestLittleHavenAndHillyHavenSeparation()
    {
        GD.Print("\n--- Test 3: Little Haven vs Hilly Haven Hole Separation ---");

        // Nodes
        var nodes = new Dictionary<long, (double Lat, double Lon)>();
        double refLat = 44.35;
        double refLon = -88.04;
        double metersPerLat = 111320.0;
        double metersPerLon = 111320.0 * Math.Cos(refLat * Math.PI / 180.0);

        // Helper to add a node by meter coordinates (x = East, y = North)
        long nextNodeId = 1;
        long AddNode(float x, float y)
        {
            long id = nextNodeId++;
            double lon = refLon + (x / metersPerLon);
            double lat = refLat - (y / metersPerLat); // note: in godot loader, y is -lat
            nodes[id] = (lat, lon);
            return id;
        }

        // Little Haven boundary polygon (small 6-hole course)
        // From (0, 0) to (200, 200)
        long nLh1 = AddNode(0f, 0f);
        long nLh2 = AddNode(200f, 0f);
        long nLh3 = AddNode(200f, 200f);
        long nLh4 = AddNode(0f, 200f);
        var lhBoundaryWay = new OsmMapLoader.OsmWay(1001, new List<long> { nLh1, nLh2, nLh3, nLh4, nLh1 }, new Dictionary<string, string>
        {
            ["leisure"] = "golf_course",
            ["name"] = "Little Haven Golf Course"
        });

        // Hilly Haven boundary polygon (adjacent 18-hole course to the north)
        // From (0, 210) to (800, 1000)
        long nHh1 = AddNode(0f, 210f);
        long nHh2 = AddNode(800f, 210f);
        long nHh3 = AddNode(800f, 1000f);
        long nHh4 = AddNode(0f, 1000f);
        var hhBoundaryWay = new OsmMapLoader.OsmWay(1002, new List<long> { nHh1, nHh2, nHh3, nHh4, nHh1 }, new Dictionary<string, string>
        {
            ["leisure"] = "golf_course",
            ["name"] = "Hilly Haven Golf Course"
        });

        var ways = new List<OsmMapLoader.OsmWay> { lhBoundaryWay, hhBoundaryWay };
        var relations = new List<OsmMapLoader.OsmRelation>();

        // 6 holes for Little Haven (strictly inside Little Haven boundary)
        var lhHoles = new List<OsmMapLoader.OsmWay>();
        for (int i = 1; i <= 6; i++)
        {
            long tNode = AddNode(20f * i, 30f);
            long pNode = AddNode(20f * i, 150f);
            var hWay = new OsmMapLoader.OsmWay(2000 + i, new List<long> { tNode, pNode }, new Dictionary<string, string>
            {
                ["golf"] = "hole",
                ["ref"] = i.ToString()
            });
            ways.Add(hWay);
            lhHoles.Add(hWay);
        }

        // Hilly Haven Hole 15: Tee at (205, 220), Pin at (600, 800), Fairway dogleg at (195, 195)
        // Notice fairway is 10m from Little Haven vertex (200, 200), but both Tee and Pin are in Hilly Haven!
        long tHh15 = AddNode(205f, 220f);
        long mHh15 = AddNode(195f, 195f); // midpoint near LH corner
        long pHh15 = AddNode(600f, 800f);
        var hhHole15 = new OsmMapLoader.OsmWay(3015, new List<long> { tHh15, mHh15, pHh15 }, new Dictionary<string, string>
        {
            ["golf"] = "hole",
            ["ref"] = "15"
        });
        ways.Add(hhHole15);

        // Hilly Haven Hole 1 (strictly in Hilly Haven)
        long tHh1 = AddNode(300f, 300f);
        long pHh1 = AddNode(300f, 600f);
        var hhHole1 = new OsmMapLoader.OsmWay(3001, new List<long> { tHh1, pHh1 }, new Dictionary<string, string>
        {
            ["golf"] = "hole",
            ["ref"] = "1"
        });
        ways.Add(hhHole1);

        // Test loading Little Haven
        var lhBoundaryInfo = OsmMapLoader.IdentifyCourseBoundaries(
            ways, relations, nodes, 44.35, -88.04, "Little Haven", refLat, refLon, metersPerLat, metersPerLon);

        if (lhBoundaryInfo.TargetCourseName != "Little Haven Golf Course")
            throw new Exception($"Expected target course 'Little Haven Golf Course', got '{lhBoundaryInfo.TargetCourseName}'");

        if (lhBoundaryInfo.OtherCourseNames.Count == 0 || !lhBoundaryInfo.OtherCourseNames.Contains("Hilly Haven Golf Course"))
            throw new Exception("Expected Hilly Haven in OtherCourseNames");

        // Verify Little Haven accepts its own 6 holes
        foreach (var h in lhHoles)
        {
            bool accepted = OsmMapLoader.IsHoleBelongingToCourse(h, nodes, refLat, refLon, metersPerLat, metersPerLon, lhBoundaryInfo);
            if (!accepted)
                throw new Exception($"Little Haven failed to accept hole {h.Tags["ref"]}");
        }

        // Verify Little Haven REJECTS Hilly Haven Hole 15 and Hole 1
        bool hh15InLh = OsmMapLoader.IsHoleBelongingToCourse(hhHole15, nodes, refLat, refLon, metersPerLat, metersPerLon, lhBoundaryInfo);
        if (hh15InLh)
            throw new Exception("CRITICAL FAILURE: Little Haven erroneously accepted Hilly Haven Hole 15!");

        bool hh1InLh = OsmMapLoader.IsHoleBelongingToCourse(hhHole1, nodes, refLat, refLon, metersPerLat, metersPerLon, lhBoundaryInfo);
        if (hh1InLh)
            throw new Exception("CRITICAL FAILURE: Little Haven erroneously accepted Hilly Haven Hole 1!");

        // Test loading Hilly Haven
        var hhBoundaryInfo = OsmMapLoader.IdentifyCourseBoundaries(
            ways, relations, nodes, 44.35, -88.04, "Hilly Haven", refLat, refLon, metersPerLat, metersPerLon);

        if (hhBoundaryInfo.TargetCourseName != "Hilly Haven Golf Course")
            throw new Exception($"Expected target course 'Hilly Haven Golf Course', got '{hhBoundaryInfo.TargetCourseName}'");

        // Verify Hilly Haven accepts Hole 15 and Hole 1
        bool hh15InHh = OsmMapLoader.IsHoleBelongingToCourse(hhHole15, nodes, refLat, refLon, metersPerLat, metersPerLon, hhBoundaryInfo);
        if (!hh15InHh)
            throw new Exception("Hilly Haven should accept its own Hole 15");

        bool hh1InHh = OsmMapLoader.IsHoleBelongingToCourse(hhHole1, nodes, refLat, refLon, metersPerLat, metersPerLon, hhBoundaryInfo);
        if (!hh1InHh)
            throw new Exception("Hilly Haven should accept its own Hole 1");

        // Verify Hilly Haven REJECTS Little Haven's holes
        foreach (var h in lhHoles)
        {
            bool accepted = OsmMapLoader.IsHoleBelongingToCourse(h, nodes, refLat, refLon, metersPerLat, metersPerLon, hhBoundaryInfo);
            if (accepted)
                throw new Exception($"Hilly Haven erroneously accepted Little Haven hole {h.Tags["ref"]}");
        }

        GD.Print("  PASS: Little Haven and Hilly Haven holes are strictly segregated.");
    }

    private static void TestBoundaryToleranceEdgeCases()
    {
        GD.Print("\n--- Test 4: Boundary Inaccuracy Tolerances ---");

        var nodes = new Dictionary<long, (double Lat, double Lon)>();
        double refLat = 35.0;
        double refLon = -80.0;
        double metersPerLat = 111320.0;
        double metersPerLon = 111320.0 * Math.Cos(refLat * Math.PI / 180.0);

        long nextId = 5000;
        long AddNode(float x, float y)
        {
            long id = nextId++;
            double lon = refLon + (x / metersPerLon);
            double lat = refLat - (y / metersPerLat);
            nodes[id] = (lat, lon);
            return id;
        }

        // Target Course Boundary from (0,0) to (500, 500)
        long b1 = AddNode(0f, 0f);
        long b2 = AddNode(500f, 0f);
        long b3 = AddNode(500f, 500f);
        long b4 = AddNode(0f, 500f);
        var boundaryWay = new OsmMapLoader.OsmWay(4001, new List<long> { b1, b2, b3, b4, b1 }, new Dictionary<string, string>
        {
            ["leisure"] = "golf_course",
            ["name"] = "Pine Valley"
        });

        var boundaryInfo = OsmMapLoader.IdentifyCourseBoundaries(
            new List<OsmMapLoader.OsmWay> { boundaryWay },
            new List<OsmMapLoader.OsmRelation>(),
            nodes, 35.0, -80.0, "Pine Valley", refLat, refLon, metersPerLat, metersPerLon);

        // Case A: Tee is 15m outside boundary (mapper cut off tee box), pin is 200m inside
        long tA = AddNode(-15f, 250f);
        long pA = AddNode(200f, 250f);
        var holeA = new OsmMapLoader.OsmWay(6001, new List<long> { tA, pA }, new Dictionary<string, string> { ["golf"] = "hole", ["ref"] = "1" });
        if (!OsmMapLoader.IsHoleBelongingToCourse(holeA, nodes, refLat, refLon, metersPerLat, metersPerLon, boundaryInfo))
            throw new Exception("Hole with tee 15m outside should be accepted due to mapper boundary tolerance");

        // Case B: Pin is 15m outside boundary (mapper cut off green), tee is 200m inside
        long tB = AddNode(200f, 250f);
        long pB = AddNode(515f, 250f);
        var holeB = new OsmMapLoader.OsmWay(6002, new List<long> { tB, pB }, new Dictionary<string, string> { ["golf"] = "hole", ["ref"] = "2" });
        if (!OsmMapLoader.IsHoleBelongingToCourse(holeB, nodes, refLat, refLon, metersPerLat, metersPerLon, boundaryInfo))
            throw new Exception("Hole with pin 15m outside should be accepted due to mapper boundary tolerance");

        // Case C: Tee is 11m outside, but Pin is 180m outside (neighbor course hole like H15)
        long tC = AddNode(-11f, 250f);
        long pC = AddNode(-180f, 250f);
        var holeC = new OsmMapLoader.OsmWay(6003, new List<long> { tC, pC }, new Dictionary<string, string> { ["golf"] = "hole", ["ref"] = "3" });
        if (OsmMapLoader.IsHoleBelongingToCourse(holeC, nodes, refLat, refLon, metersPerLat, metersPerLon, boundaryInfo))
            throw new Exception("Hole with pin 180m outside must NOT be accepted");

        GD.Print("  PASS: Boundary tolerances accommodate realistic mapper offsets while blocking stray holes.");
    }
}
