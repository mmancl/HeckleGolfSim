#!/usr/bin/env python3
"""
Targeted tests for monthly OSM course sync tool cleanup and worker process isolation.
"""

import os
import sys
import tempfile
import unittest

# Add scripts/tools to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "scripts", "tools")))
from monthly_osm_course_sync import cleanup_osm_temp_files, process_pbf_file, validate_course_elements, GolfCourseIdentifier


class TestMonthlyOsmSync(unittest.TestCase):
    def test_cleanup_osm_temp_files(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            f1 = os.path.join(tmpdir, "_osmium_node_idx_1234.dat")
            f2 = os.path.join(tmpdir, "_osmium_results_abcd.json")
            keep_file = os.path.join(tmpdir, "important_file.txt")

            for f in (f1, f2, keep_file):
                with open(f, "w") as fp:
                    fp.write("test")

            self.assertTrue(os.path.exists(f1))
            self.assertTrue(os.path.exists(f2))
            self.assertTrue(os.path.exists(keep_file))

            cleanup_osm_temp_files([tmpdir])

            self.assertFalse(os.path.exists(f1), "Index file should be deleted")
            self.assertFalse(os.path.exists(f2), "Results file should be deleted")
            self.assertTrue(os.path.exists(keep_file), "Non-temp files should be preserved")

    def _build_mock_course_data(self, hole_count=18, fairway_count=18, tee_count=18, green_count=18, subcourses=None):
        ways = []
        nodes = {}

        # Build hole ways
        if subcourses:
            for sub, count in subcourses:
                for h in range(1, count + 1):
                    w_id = len(ways) + 1
                    ways.append({
                        "type": "way",
                        "id": w_id,
                        "nodes": [w_id * 10, w_id * 10 + 1],
                        "tags": {"golf": "hole", "ref": str(h), "golf:course:name": sub}
                    })
        else:
            for h in range(1, hole_count + 1):
                w_id = len(ways) + 1
                ways.append({
                    "type": "way",
                    "id": w_id,
                    "nodes": [w_id * 10, w_id * 10 + 1],
                    "tags": {"golf": "hole", "ref": str(h)}
                })

        # Build fairways
        for f in range(1, fairway_count + 1):
            w_id = len(ways) + 1
            ways.append({
                "type": "way",
                "id": w_id,
                "nodes": [w_id * 10, w_id * 10 + 1, w_id * 10 + 2],
                "tags": {"golf": "fairway"}
            })

        # Build tees
        for t in range(1, tee_count + 1):
            w_id = len(ways) + 1
            ways.append({
                "type": "way",
                "id": w_id,
                "nodes": [w_id * 10, w_id * 10 + 1, w_id * 10 + 2],
                "tags": {"golf": "tee", "ref": str((t - 1) % hole_count + 1) if hole_count else "1"}
            })

        # Build greens
        for g in range(1, green_count + 1):
            w_id = len(ways) + 1
            ways.append({
                "type": "way",
                "id": w_id,
                "nodes": [w_id * 10, w_id * 10 + 1, w_id * 10 + 2],
                "tags": {"golf": "green", "ref": str((g - 1) % hole_count + 1) if hole_count else "1"}
            })

        return {"ways": ways, "nodes": nodes, "relations": []}

    def test_validate_course_elements_valid_18_hole(self):
        data = self._build_mock_course_data(hole_count=18, fairway_count=18, tee_count=36, green_count=18)
        ok, verified_holes, reason = validate_course_elements(data)
        self.assertTrue(ok)
        self.assertEqual(verified_holes, 18)
        self.assertIn("Valid 18-hole course", reason)

    def test_validate_course_elements_valid_9_hole(self):
        data = self._build_mock_course_data(hole_count=9, fairway_count=9, tee_count=9, green_count=9)
        ok, verified_holes, reason = validate_course_elements(data)
        self.assertTrue(ok)
        self.assertEqual(verified_holes, 9)
        self.assertIn("Valid 9-hole course", reason)

    def test_validate_course_elements_valid_27_hole(self):
        data = self._build_mock_course_data(
            hole_count=0,
            fairway_count=27,
            tee_count=27,
            green_count=27,
            subcourses=[("Red", 9), ("White", 9), ("Blue", 9)]
        )
        ok, verified_holes, reason = validate_course_elements(data)
        self.assertTrue(ok)
        self.assertEqual(verified_holes, 27)
        self.assertIn("Valid 27-hole course", reason)

    def test_validate_course_elements_valid_36_hole(self):
        data = self._build_mock_course_data(
            hole_count=0,
            fairway_count=36,
            tee_count=72,
            green_count=36,
            subcourses=[("North", 18), ("South", 18)]
        )
        ok, verified_holes, reason = validate_course_elements(data)
        self.assertTrue(ok)
        self.assertEqual(verified_holes, 36)
        self.assertIn("Valid 36-hole course", reason)

    def test_validate_course_elements_single_hole_rejected(self):
        data = self._build_mock_course_data(hole_count=1, fairway_count=1, tee_count=1, green_count=1)
        ok, verified_holes, reason = validate_course_elements(data)
        self.assertFalse(ok)
        self.assertEqual(verified_holes, 1)
        self.assertIn("Only 1 hole(s) defined", reason)

    def test_validate_course_elements_zero_holes_rejected(self):
        data = self._build_mock_course_data(hole_count=0, fairway_count=5, tee_count=5, green_count=5)
        ok, verified_holes, reason = validate_course_elements(data)
        self.assertFalse(ok)
        self.assertEqual(verified_holes, 0)
        self.assertIn("No holes defined", reason)

    def test_validate_course_elements_incomplete_17_holes_rejected(self):
        data = self._build_mock_course_data(hole_count=17, fairway_count=17, tee_count=17, green_count=17)
        ok, verified_holes, reason = validate_course_elements(data)
        self.assertFalse(ok)
        self.assertEqual(verified_holes, 17)
        self.assertIn("must be a 9, 18, 27, or 36 hole course", reason)

    def test_validate_course_elements_missing_fairways_rejected(self):
        data = self._build_mock_course_data(hole_count=18, fairway_count=0, tee_count=18, green_count=18)
        ok, verified_holes, reason = validate_course_elements(data)
        self.assertFalse(ok)
        self.assertIn("No fairways defined", reason)

    def test_validate_course_elements_missing_tees_rejected(self):
        data = self._build_mock_course_data(hole_count=18, fairway_count=18, tee_count=0, green_count=18)
        ok, verified_holes, reason = validate_course_elements(data)
        self.assertFalse(ok)
        self.assertIn("No tee boxes defined", reason)

    def test_validate_course_elements_missing_greens_rejected(self):
        data = self._build_mock_course_data(hole_count=18, fairway_count=18, tee_count=18, green_count=0)
        ok, verified_holes, reason = validate_course_elements(data)
        self.assertFalse(ok)
        self.assertIn("No greens defined", reason)

    def test_pass1_feature_name_and_tags_rejected(self):
        class MockNode:
            class Location:
                def valid(self): return True
            lat = 35.0
            lon = -115.0
            location = Location()

        class MockWay:
            id = 999
            nodes = [MockNode(), MockNode()]
            def __init__(self, tags):
                self.tags = tags

        handler = GolfCourseIdentifier()
        # Individual green tagged with leisure=golf_course
        w_green = MockWay({"leisure": "golf_course", "name": "#2 Green", "golf": "green"})
        handler.way(w_green)
        self.assertEqual(len(handler.courses), 0, "Individual green must be rejected in Pass 1")

        # Individual tee tagged with leisure=golf_course
        w_tee = MockWay({"leisure": "golf_course", "name": "#8 White Tee", "golf": "tee"})
        handler.way(w_tee)
        self.assertEqual(len(handler.courses), 0, "Individual tee must be rejected in Pass 1")

        # Full course
        w_course = MockWay({"leisure": "golf_course", "name": "Spyglass Hill Golf Course", "holes": "18"})
        handler.way(w_course)
        self.assertEqual(len(handler.courses), 1, "Full course must be accepted in Pass 1")
        self.assertEqual(handler.courses[0]["name"], "Spyglass Hill Golf Course")


if __name__ == "__main__":
    unittest.main()
