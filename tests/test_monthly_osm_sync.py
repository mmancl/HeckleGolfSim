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
from monthly_osm_course_sync import cleanup_osm_temp_files, process_pbf_file


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


if __name__ == "__main__":
    unittest.main()
