"""
Vector Geometry Pre-Caching Tool for HeckleGolfSim.

Fetches and compresses raw OSM vector geometry for courses in the catalog,
saving them to res://Courses/CachedGeometry/<course_slug>.json.gz.

Pre-caching vector geometries allows HeckleGolfSim to bypass the Overpass API entirely
for common courses, eliminating 90%+ of network queries and avoiding rate limits/bans.
"""

import gzip
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
CATALOG_PATH = os.path.join(PROJECT_ROOT, "Courses", "Catalog", "golf_courses.json")
CACHE_DIR = os.path.join(PROJECT_ROOT, "Courses", "CachedGeometry")

OVERPASS_ENDPOINTS = [
    "https://lz4.overpass-api.de/api/interpreter",
    "https://overpass-api.de/api/interpreter",
    "https://z.overpass-api.de/api/interpreter"
]


def slugify(text: str) -> str:
    """Generate a clean, normalized filesystem slug from a course name."""
    clean = re.sub(r'[^a-zA-Z0-9]+', '_', text.lower()).strip('_')
    return clean


def fetch_course_geometry(lat: float, lon: float, course_name: str, timeout: int = 60) -> str:
    """Query Overpass API for golf course vector geometries around lat, lon."""
    query = f"""
    [out:json][timeout:{timeout}];
    (
      nwr(around:1000, {lat:.6f}, {lon:.6f})["leisure"="golf_course"];
      nwr(around:1000, {lat:.6f}, {lon:.6f})["golf"];
      nwr(around:1000, {lat:.6f}, {lon:.6f})["natural"="water"];
      nwr(around:1000, {lat:.6f}, {lon:.6f})["natural"="wood"];
      nwr(around:1000, {lat:.6f}, {lon:.6f})["landuse"="forest"];
    );
    out body;
    >;
    out skel qt;
    """
    data_payload = urllib.parse.urlencode({"data": query}).encode("utf-8")

    for attempt, endpoint in enumerate(OVERPASS_ENDPOINTS, 1):
        try:
            req = urllib.request.Request(endpoint, data=data_payload)
            req.add_header("User-Agent", "HeckleLinks-CourseArchiver/1.0 (contact: github.com/mmancl/HeckleGolfSim)")
            with urllib.request.urlopen(req, timeout=timeout + 5) as resp:
                if resp.status == 200:
                    raw_text = resp.read().decode("utf-8")
                    if raw_text and '"elements"' in raw_text:
                        return raw_text
        except Exception as e:
            print(f"  Attempt {attempt} on {endpoint} failed: {e}")
            time.sleep(1)

    return ""


def cache_courses(limit: int = 10, delay_sec: float = 2.0, force: bool = False):
    """Batch cache vector geometries for courses in the catalog."""
    os.makedirs(CACHE_DIR, exist_ok=True)

    if not os.path.exists(CATALOG_PATH):
        print(f"Catalog not found at: {CATALOG_PATH}")
        return

    with open(CATALOG_PATH, "r", encoding="utf-8") as f:
        catalog = json.load(f)

    print(f"Loaded {len(catalog)} courses from catalog.")
    cached_count = 0
    skipped_count = 0

    for i, course in enumerate(catalog):
        if cached_count >= limit:
            break

        name = course.get("name", "")
        lat = course.get("lat", 0.0)
        lon = course.get("lon", 0.0)
        slug = slugify(name)

        if not slug or (lat == 0.0 and lon == 0.0):
            continue

        gz_path = os.path.join(CACHE_DIR, f"{slug}.json.gz")
        json_path = os.path.join(CACHE_DIR, f"{slug}.json")

        if not force and (os.path.exists(gz_path) or os.path.exists(json_path)):
            skipped_count += 1
            continue

        print(f"[{cached_count + 1}/{limit}] Fetching geometry for: {name} ({lat}, {lon})...")
        geom_json = fetch_course_geometry(lat, lon, name)

        if geom_json:
            compressed = gzip.compress(geom_json.encode("utf-8"), compresslevel=9)
            with open(gz_path, "wb") as f_out:
                f_out.write(compressed)
            raw_kb = len(geom_json) / 1024
            gz_kb = len(compressed) / 1024
            print(f"  Saved {gz_path} ({raw_kb:.1f} KB raw -> {gz_kb:.1f} KB compressed)")
            cached_count += 1
            if cached_count < limit:
                time.sleep(delay_sec)
        else:
            print(f"  Failed to fetch geometry for {name}.")

    print(f"\nCaching complete! Newly cached: {cached_count}, Already cached/skipped: {skipped_count}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Cache OSM vector geometries for golf courses.")
    parser.add_argument("--limit", type=int, default=10, help="Max courses to cache in this run")
    parser.add_argument("--delay", type=float, default=2.5, help="Polite delay between requests in seconds")
    parser.add_argument("--force", action="store_true", help="Re-download even if already cached")
    args = parser.parse_args()

    cache_courses(limit=args.limit, delay_sec=args.delay, force=args.force)
