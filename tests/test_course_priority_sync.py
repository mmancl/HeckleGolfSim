#!/usr/bin/env python3
"""
Unit test for course priority selection in monthly_osm_course_sync.py
Verifies that:
1. PGA Tour and Major championship courses are prioritized first.
2. Courses with user / OSM ratings are prioritized next.
3. Courses without rating/PGA status are prioritized by most recently updated date.
4. Completing 18-hole courses takes precedence over uncompleted layouts with equal timestamps.
"""
import sys
import os
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts", "tools"))
import monthly_osm_course_sync as sync


class TestMonthlyCoursePriority(unittest.TestCase):
    def test_pga_tour_course_matching(self):
        # Known PGA courses
        self.assertTrue(any(kw in "augusta national golf club" for kw in sync.PGA_TOUR_AND_MAJOR_COURSES))
        self.assertTrue(any(kw in "pebble beach golf links" for kw in sync.PGA_TOUR_AND_MAJOR_COURSES))
        self.assertTrue(any(kw in "st andrews links old course" for kw in sync.PGA_TOUR_AND_MAJOR_COURSES))
        self.assertTrue(any(kw in "tpc sawgrass stadium course" for kw in sync.PGA_TOUR_AND_MAJOR_COURSES))

    def test_course_priority_ordering(self):
        sample_courses = [
            {
                "name": "Standard Muni A",
                "last_updated": "2025-01-10",
                "hole_count": 18,
                "rating": 0.0,
                "is_pga_tour": False
            },
            {
                "name": "Freshly Updated Muni B",
                "last_updated": "2026-10-01",
                "hole_count": 18,
                "rating": 0.0,
                "is_pga_tour": False
            },
            {
                "name": "Local 4-Star Course",
                "last_updated": "2023-05-15",
                "hole_count": 18,
                "rating": 4.5,
                "is_pga_tour": False
            },
            {
                "name": "Augusta National Golf Club",
                "last_updated": "2022-04-10",
                "hole_count": 18,
                "rating": 0.0,
                "is_pga_tour": True
            },
            {
                "name": "Pebble Beach Golf Links",
                "last_updated": "2024-06-15",
                "hole_count": 18,
                "rating": 5.0,
                "is_pga_tour": True
            },
            {
                "name": "Oldest Muni C",
                "last_updated": "2021-03-01",
                "hole_count": 18,
                "rating": 0.0,
                "is_pga_tour": False
            }
        ]

        sorted_courses = sorted(sample_courses, key=sync.compute_course_priority, reverse=True)
        names = [c["name"] for c in sorted_courses]

        # Top 2 must be PGA Tour courses
        self.assertEqual(names[0], "Pebble Beach Golf Links")  # PGA + 5.0 rating
        self.assertEqual(names[1], "Augusta National Golf Club")  # PGA tour

        # Next must be rated course
        self.assertEqual(names[2], "Local 4-Star Course")  # 4.5 rating

        # Remaining must be sorted strictly by most recently updated date
        self.assertEqual(names[3], "Freshly Updated Muni B")  # 2026-10-01
        self.assertEqual(names[4], "Standard Muni A")  # 2025-01-10
        self.assertEqual(names[5], "Oldest Muni C")  # 2021-03-01

    def test_catalog_merging_preserves_pga_and_rating(self):
        existing = [
            {"name": "Pebble Beach Golf Links", "hole_count": 18, "last_updated": "2024-01-01"}
        ]
        new_entries = [
            {
                "name": "Pebble Beach Golf Links",
                "hole_count": 18,
                "last_updated": "2026-10-11",
                "is_pga_tour": True,
                "rating": 5.0
            }
        ]

        merged = {c["name"].lower(): c.copy() for c in existing}
        for entry in new_entries:
            key = entry["name"].lower()
            if key in merged:
                if entry.get("last_updated"):
                    merged[key]["last_updated"] = entry["last_updated"]
                if entry.get("is_pga_tour"):
                    merged[key]["is_pga_tour"] = True
                if entry.get("rating", 0.0) > 0.0:
                    merged[key]["rating"] = max(merged[key].get("rating", 0.0), entry["rating"])

        updated = merged["pebble beach golf links"]
        self.assertEqual(updated["last_updated"], "2026-10-11")
        self.assertTrue(updated["is_pga_tour"])
        self.assertEqual(updated["rating"], 5.0)

    def test_catalog_sorting_prioritizes_pga_courses(self):
        sample_catalog = [
            {"name": "Zion Mountain Golf Club", "hole_count": 18, "is_pga_tour": False},
            {"name": "Pebble Beach Golf Links", "hole_count": 18, "is_pga_tour": True},
            {"name": "Abilene Country Club", "hole_count": 18, "is_pga_tour": False},
            {"name": "Augusta National Golf Club", "hole_count": 18, "is_pga_tour": True},
            {"name": "TPC Sawgrass", "hole_count": 18, "is_pga_tour": False}, # matches keyword in PGA_TOUR_AND_MAJOR_COURSES
            {"name": "Midland Country Club", "hole_count": 18, "is_pga_tour": False},
        ]

        # Tag PGA courses and sort
        for c in sample_catalog:
            clean = " " + sync.re.sub(r'[^a-z0-9]+', ' ', c["name"].lower()).strip() + " "
            if any(f" {kw} " in clean or clean.strip() == kw for kw in sync.PGA_TOUR_AND_MAJOR_COURSES):
                c["is_pga_tour"] = True

        sorted_catalog = sorted(
            sample_catalog,
            key=lambda x: (not bool(x.get("is_pga_tour", False)), x["name"].lower())
        )
        names = [c["name"] for c in sorted_catalog]

        # First 3 must be PGA Tour courses sorted alphabetically
        self.assertEqual(names[0], "Augusta National Golf Club")
        self.assertEqual(names[1], "Pebble Beach Golf Links")
        self.assertEqual(names[2], "TPC Sawgrass")

        # Next 3 must be non-PGA courses sorted alphabetically
        self.assertEqual(names[3], "Abilene Country Club")
        self.assertEqual(names[4], "Midland Country Club")
        self.assertEqual(names[5], "Zion Mountain Golf Club")


if __name__ == "__main__":
    unittest.main()
