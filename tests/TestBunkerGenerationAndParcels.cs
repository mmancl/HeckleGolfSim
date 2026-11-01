using System;
using System.Collections.Generic;
using Godot;
using HeckleLinks.Courses;

public partial class TestBunkerGenerationAndParcels : Node
{
    public override void _Ready()
    {
        GD.Print("==================================================");
        GD.Print("Running Bunker Generation & Parcels Unit Tests");
        GD.Print("==================================================");

        TestMultiParcelBoundaries();
        TestSyntheticBunkersFallback();

        GD.Print("==================================================");
        GD.Print("ALL BUNKER GENERATION & PARCELS TESTS PASSED!");
        GD.Print("==================================================");
    }

    private static void TestMultiParcelBoundaries()
    {
        GD.Print("\n--- Test 1: Multi-Parcel Course Boundaries ---");

        // Setup a main course parcel named "Westridge Golf Course" and an unnamed secondary parcel
        var mainWay = new OsmMapLoader.OsmWay(
            1,
            new List<long> { 1, 2, 3, 1 },
            new Dictionary<string, string>
            {
                { "leisure", "golf_course" },
                { "name", "Westridge Golf Course" }
            }
        );

        var unnamedParcelWay = new OsmMapLoader.OsmWay(
            2,
            new List<long> { 4, 5, 6, 4 },
            new Dictionary<string, string>
            {
                { "leisure", "golf_course" } // unnamed parcel
            }
        );

        var nodes = new Dictionary<long, (double Lat, double Lon)>
        {
            { 1, (44.200, -88.500) },
            { 2, (44.201, -88.500) },
            { 3, (44.201, -88.501) },
            { 4, (44.202, -88.500) },
            { 5, (44.203, -88.500) },
            { 6, (44.203, -88.501) }
        };

        var ways = new List<OsmMapLoader.OsmWay> { mainWay, unnamedParcelWay };
        var relations = new List<OsmMapLoader.OsmRelation>();

        var boundaryInfo = OsmMapLoader.IdentifyCourseBoundaries(
            ways,
            relations,
            nodes,
            44.200,
            -88.500,
            "Westridge Golf Course",
            44.200,
            -88.500,
            111000.0,
            80000.0
        );

        // Both parcels should be included in CoursePolygons, and OtherCoursePolygons should be empty
        if (boundaryInfo.CoursePolygons.Count != 2)
        {
            throw new Exception($"Expected 2 CoursePolygons for multi-parcel course, got {boundaryInfo.CoursePolygons.Count}");
        }

        if (boundaryInfo.OtherCoursePolygons.Count != 0)
        {
            throw new Exception($"Expected 0 OtherCoursePolygons, got {boundaryInfo.OtherCoursePolygons.Count}");
        }

        GD.Print("  PASS: Unnamed secondary parcel correctly grouped into main course boundaries.");
    }

    private static void TestSyntheticBunkersFallback()
    {
        GD.Print("\n--- Test 2: Synthetic Bunkers Generation When OSM Has 0 Mapped ---");

        var loader = new OsmMapLoader();
        var holeInfo = new Dictionary<string, OsmMapLoader.HoleConfig>();
        holeInfo["1"] = new OsmMapLoader.HoleConfig
        {
            Par = 4,
            HoleLocation = new float[] { 0, -250 },
            HolePath = new List<float[]>
            {
                new float[] { 0, 0 },
                new float[] { 0, -250 }
            }
        };

        var exclusionPolygons = new List<OsmMapLoader.ExclusionPolygon>();
        var coursePolygons = new List<Vector2[]>();
        var rootNode = new Node3D();

        loader.GenerateSyntheticBunkersIfNoneMapped(holeInfo, exclusionPolygons, coursePolygons, rootNode);

        int bunkerCount = 0;
        foreach (Node child in rootNode.GetChildren())
        {
            if (child.Name.ToString().Contains("bunker", StringComparison.OrdinalIgnoreCase) || child.IsInGroup("bunkers"))
            {
                bunkerCount++;
            }
        }

        rootNode.Free();

        if (bunkerCount == 0)
        {
            throw new Exception("Expected synthetic bunkers to be generated when 0 bunkers were mapped, but found none.");
        }

        GD.Print($"  PASS: Successfully generated {bunkerCount} synthetic bunkers (greenside and fairway).");
    }
}
