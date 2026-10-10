#!/usr/bin/env python3
"""
Monthly OpenStreetMap Golf Course Sync & Pre-Caching Tool for HeckleGolfSim.

Downloads the latest Geofabrik regional extracts for North America and Europe,
uses Osmium to extract golf courses, generates compressed vector geometries
in res://Courses/CachedGeometry/<slug>.json.gz, and updates the global course
catalog at res://Courses/Catalog/golf_courses.json.

Run this script periodically (e.g. once a month) to keep your offline course
geometries and catalog up to date with the latest OpenStreetMap additions.
"""

import argparse
import concurrent.futures
import gzip
import json
import math
import os
import re
import shutil
import ssl
import sys
import threading
import time
import urllib.request
import urllib.error

try:
    import osmium
except ImportError:
    print("Error: 'osmium' Python package is required. Install it using:")
    print("  pip install osmium")
    sys.exit(1)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_CACHE_DIR = os.path.join(PROJECT_ROOT, "Courses", "CachedGeometry")
DEFAULT_CATALOG_PATH = os.path.join(PROJECT_ROOT, "Courses", "Catalog", "golf_courses.json")
DEFAULT_DOWNLOAD_DIR = os.path.join(PROJECT_ROOT, "tmp", "osm_extracts")

GEOFABRIK_REGIONS = {
    # US Regional extracts (1-3.5 GB each, fast and safe memory footprint on standard PCs):
    "us-midwest": "https://download.geofabrik.de/north-america/us-midwest-latest.osm.pbf",
    "us-northeast": "https://download.geofabrik.de/north-america/us-northeast-latest.osm.pbf",
    "us-pacific": "https://download.geofabrik.de/north-america/us-pacific-latest.osm.pbf",
    "us-south": "https://download.geofabrik.de/north-america/us-south-latest.osm.pbf",
    "us-west": "https://download.geofabrik.de/north-america/us-west-latest.osm.pbf",
    # Top individual golf states (quick 500 MB - 1.2 GB extracts):
    "california": "https://download.geofabrik.de/north-america/us/california-latest.osm.pbf",
    "florida": "https://download.geofabrik.de/north-america/us/florida-latest.osm.pbf",
    "texas": "https://download.geofabrik.de/north-america/us/texas-latest.osm.pbf",
    "new-york": "https://download.geofabrik.de/north-america/us/new-york-latest.osm.pbf",
    "scotland": "https://download.geofabrik.de/europe/great-britain/scotland-latest.osm.pbf",
    # Country-level extracts:
    "us": "https://download.geofabrik.de/north-america/us-latest.osm.pbf",
    "canada": "https://download.geofabrik.de/north-america/canada-latest.osm.pbf",
    "great-britain": "https://download.geofabrik.de/europe/great-britain-latest.osm.pbf",
    "ireland": "https://download.geofabrik.de/europe/ireland-and-northern-ireland-latest.osm.pbf",
    "australia": "https://download.geofabrik.de/australia-oceania/australia-latest.osm.pbf",
    "germany": "https://download.geofabrik.de/europe/germany-latest.osm.pbf",
    "spain": "https://download.geofabrik.de/europe/spain-latest.osm.pbf",
    "japan": "https://download.geofabrik.de/asia/japan-latest.osm.pbf",
    "australia-oceania": "https://download.geofabrik.de/australia-oceania-latest.osm.pbf",
    # Full continent extracts (very large, ~43 GB combined):
    "north-america": "https://download.geofabrik.de/north-america-latest.osm.pbf",
    "europe": "https://download.geofabrik.de/europe-latest.osm.pbf",
}

PRESETS = {
    "top-golf": {
        "name": "Top Golf Countries & US Regions (Recommended)",
        "description": "US Regions (Pacific, South, Midwest, Northeast, West) + UK, Ireland, Canada, Australia (~18 GB total across safe chunks)",
        "regions": ["us-pacific", "us-south", "us-midwest", "us-northeast", "us-west", "great-britain", "ireland", "canada", "australia"]
    },
    "top-states": {
        "name": "Iconic Golf States & Scotland (Fastest)",
        "description": "California, Florida, Texas, New York, Scotland (~3.5 GB total)",
        "regions": ["california", "florida", "texas", "new-york", "scotland"]
    },
    "us-regions": {
        "name": "All 5 US Subregions",
        "description": "US Pacific, South, Midwest, Northeast, West (~11.5 GB in safe regional chunks)",
        "regions": ["us-pacific", "us-south", "us-midwest", "us-northeast", "us-west"]
    },
    "us-only": {
        "name": "United States Monolithic (Large)",
        "description": "US full extract (~11.6 GB monolithic; auto-switches to disk-backed index)",
        "regions": ["us"]
    },
    "uk-ireland": {
        "name": "UK & Ireland Only",
        "description": "Great Britain & Ireland (~2.2 GB)",
        "regions": ["great-britain", "ireland"]
    },
    "continents": {
        "name": "Entire Continents (Very Large)",
        "description": "Full North America + Europe (~43 GB, auto-switches to disk-backed index)",
        "regions": ["north-america", "europe"]
    },
}


def get_ssl_context():
    """Build SSL context that works reliably across Windows Python environments."""
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        pass
    try:
        return ssl.create_default_context()
    except Exception:
        ctx = ssl._create_unverified_context()
        return ctx


def format_size(bytes_val: int) -> str:
    """Format bytes into human-readable string (KB, MB, GB)."""
    if bytes_val >= 1024 * 1024 * 1024:
        return f"{bytes_val / (1024*1024*1024):.2f} GB"
    elif bytes_val >= 1024 * 1024:
        return f"{bytes_val / (1024*1024):.1f} MB"
    elif bytes_val >= 1024:
        return f"{bytes_val / 1024:.1f} KB"
    return f"{bytes_val} B"


def format_time(seconds: float) -> str:
    """Format seconds into HH:MM:SS or MM:SS."""
    if seconds < 0 or seconds > 86400:
        return "--:--"
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    if h > 0:
        return f"{h}h {m:02d}m {s:02d}s"
    return f"{m:02d}m {s:02d}s"


def slugify(text: str) -> str:
    """Generate a normalized, filesystem-safe slug matching C# GetCourseGeometrySlug."""
    clean = re.sub(r'[^a-zA-Z0-9]+', '_', text.lower()).strip('_')
    return clean


def download_file_parallel(
    url: str,
    dest_path: str,
    num_threads: int = 8,
    chunk_size_mb: int = 8
) -> bool:
    """
    High-speed parallel multi-stream chunk downloader.
    Bypasses single-connection throttling from Geofabrik by splitting the download into
    concurrent HTTP Range byte chunks. Resumable via .chunks.json state tracking.
    """
    os.makedirs(os.path.dirname(os.path.abspath(dest_path)), exist_ok=True)
    part_path = dest_path + ".part"
    meta_path = dest_path + ".chunks.json"
    chunk_size = chunk_size_mb * 1024 * 1024
    ctx = get_ssl_context()

    # 1. Inspect server capabilities & file size
    total_size = 0
    accept_ranges = False
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "HeckleGolfSim-OsmSync/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=20, context=ctx) as resp:
            total_size = int(resp.headers.get("Content-Length", 0))
            accept_ranges = resp.headers.get("Accept-Ranges", "").strip().lower() == "bytes"
    except Exception as e:
        print(f"HEAD request failed ({e}), checking Range support via GET...")
        # Fallback check
        try:
            test_req = urllib.request.Request(url, headers={"User-Agent": "HeckleGolfSim-OsmSync/1.0", "Range": "bytes=0-0"})
            with urllib.request.urlopen(test_req, timeout=20, context=ctx) as test_resp:
                if test_resp.status == 206:
                    accept_ranges = True
                    cr = test_resp.headers.get("Content-Range", "")
                    m = re.search(r'/(\d+)', cr)
                    if m:
                        total_size = int(m.group(1))
        except Exception as e2:
            print(f"Range check failed: {e2}")

    # Fallback to single-stream if Range requests or file size are unavailable
    if total_size <= 0 or not accept_ranges:
        print("Notice: Server does not advertise byte ranges or file size is unknown. Falling back to single-stream download.")
        return download_file_resumable(url, dest_path)

    # Check if target file already fully exists
    if os.path.exists(dest_path) and os.path.getsize(dest_path) == total_size:
        print(f"Extract is already fully downloaded: {dest_path} ({format_size(total_size)})")
        return True

    num_chunks = (total_size + chunk_size - 1) // chunk_size

    # Check/prepare .part file
    if not os.path.exists(part_path) or os.path.getsize(part_path) != total_size:
        print(f"Allocating {format_size(total_size)} on disk...")
        with open(part_path, "wb") as f:
            f.truncate(total_size)
        if os.path.exists(meta_path):
            os.remove(meta_path)

    completed_chunks = set()
    if os.path.exists(meta_path):
        try:
            with open(meta_path, "r", encoding="utf-8") as f:
                completed_chunks = set(json.load(f))
        except Exception:
            completed_chunks = set()

    pending_chunks = [i for i in range(num_chunks) if i not in completed_chunks]
    initially_cached = len(completed_chunks)

    print(f"Extract Size     : {format_size(total_size)} ({total_size:,} bytes)")
    print(f"Parallel Streams : {num_threads} concurrent streams ({chunk_size_mb} MB chunk size)")
    if initially_cached > 0:
        print(f"Resuming Download: {initially_cached}/{num_chunks} chunks already on disk ({len(pending_chunks)} remaining)")

    if not pending_chunks:
        print("All chunks already downloaded! Finalizing file...")
        if os.path.exists(dest_path):
            os.remove(dest_path)
        os.replace(part_path, dest_path)
        if os.path.exists(meta_path):
            os.remove(meta_path)
        return True

    lock = threading.Lock()
    file_handle = open(part_path, "r+b")
    last_save = [time.time()]
    last_report = [time.time()]
    bytes_session = [0]
    start_time = time.time()
    abort_event = threading.Event()

    def chunk_worker(chunk_idx: int) -> bool:
        if abort_event.is_set():
            return False
        start = chunk_idx * chunk_size
        end = min(start + chunk_size - 1, total_size - 1)
        expected_len = end - start + 1

        for attempt in range(4):
            if abort_event.is_set():
                return False
            try:
                r = urllib.request.Request(url, headers={
                    "User-Agent": "HeckleGolfSim-OsmSync/1.0",
                    "Range": f"bytes={start}-{end}"
                })
                with urllib.request.urlopen(r, timeout=30, context=ctx) as resp:
                    chunk_data = resp.read()

                if len(chunk_data) != expected_len:
                    raise IOError(f"Incomplete chunk data: got {len(chunk_data)}, expected {expected_len}")

                with lock:
                    file_handle.seek(start)
                    file_handle.write(chunk_data)
                    completed_chunks.add(chunk_idx)
                    bytes_session[0] += len(chunk_data)
                    now = time.time()

                    # Save chunk progress every 4 seconds
                    if now - last_save[0] >= 4.0:
                        last_save[0] = now
                        with open(meta_path, "w", encoding="utf-8") as mf:
                            json.dump(list(completed_chunks), mf)

                    # Update live progress bar every 0.8 seconds
                    if now - last_report[0] >= 0.8:
                        last_report[0] = now
                        total_dl = len(completed_chunks) * chunk_size
                        total_dl = min(total_dl, total_size)
                        pct = (total_dl / total_size) * 100
                        elapsed = now - start_time
                        speed_mb = (bytes_session[0] / (1024 * 1024)) / elapsed if elapsed > 0 else 0
                        speed_mbps = speed_mb * 8
                        remain_bytes = total_size - total_dl
                        eta_s = (remain_bytes / (speed_mb * 1024 * 1024)) if speed_mb > 0 else 0

                        bar_len = 20
                        filled = int(bar_len * (pct / 100))
                        bar = "=" * filled + (">" if filled < bar_len else "") + " " * (bar_len - filled - 1 if filled < bar_len else 0)
                        sys.stdout.write(
                            f"\r  [{bar}] {pct:5.1f}% | {format_size(total_dl)} / {format_size(total_size)} | "
                            f"{speed_mb:5.1f} MB/s ({speed_mbps:5.1f} Mbps) | ETA: {format_time(eta_s)}  "
                        )
                        sys.stdout.flush()

                return True
            except Exception:
                time.sleep(1 + attempt)

        print(f"\nChunk {chunk_idx} failed after multiple attempts.")
        abort_event.set()
        return False

    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=num_threads) as executor:
            futures = [executor.submit(chunk_worker, idx) for idx in pending_chunks]
            concurrent.futures.wait(futures)
    finally:
        file_handle.close()
        with open(meta_path, "w", encoding="utf-8") as mf:
            json.dump(list(completed_chunks), mf)

    print()  # newline after progress bar
    if len(completed_chunks) == num_chunks:
        if os.path.exists(dest_path):
            os.remove(dest_path)
        os.replace(part_path, dest_path)
        if os.path.exists(meta_path):
            os.remove(meta_path)
        total_time = time.time() - start_time
        mb = bytes_session[0] / (1024 * 1024)
        avg_speed = mb / total_time if total_time > 0 else 0
        print(f"Download complete: {dest_path}")
        print(f"Transferred: {mb:.1f} MB in {format_time(total_time)} (Average speed: {avg_speed:.1f} MB/s / {avg_speed*8:.1f} Mbps)")
        return True
    else:
        print(f"Download incomplete ({len(completed_chunks)}/{num_chunks} chunks). Run script again to resume from this point.")
        return False


def download_file_resumable(url: str, dest_path: str, chunk_size: int = 1024 * 1024) -> bool:
    """Download a file with single-stream HTTP Range resume support and progress reporting."""
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    existing_bytes = os.path.getsize(dest_path) if os.path.exists(dest_path) else 0
    ctx = get_ssl_context()

    req = urllib.request.Request(url)
    req.add_header("User-Agent", "HeckleGolfSim-OsmSync/1.0 (contact: github.com/mmancl/HeckleGolfSim)")

    if existing_bytes > 0:
        req.add_header("Range", f"bytes={existing_bytes}-")
        print(f"Resuming download from byte {existing_bytes:,} ({existing_bytes / (1024*1024):.1f} MB)...")

    try:
        with urllib.request.urlopen(req, timeout=60, context=ctx) as resp:
            content_range = resp.headers.get("Content-Range")
            total_bytes = None
            if content_range:
                m = re.search(r'/(\d+)', content_range)
                if m:
                    total_bytes = int(m.group(1))
            elif resp.headers.get("Content-Length"):
                total_bytes = int(resp.headers.get("Content-Length")) + existing_bytes

            mode = "ab" if existing_bytes > 0 and resp.status == 206 else "wb"
            downloaded = existing_bytes if mode == "ab" else 0

            with open(dest_path, mode) as f_out:
                last_report = time.time()
                while True:
                    chunk = resp.read(chunk_size)
                    if not chunk:
                        break
                    f_out.write(chunk)
                    downloaded += len(chunk)

                    now = time.time()
                    if now - last_report >= 2.5:
                        last_report = now
                        mb_dl = downloaded / (1024 * 1024)
                        if total_bytes:
                            mb_total = total_bytes / (1024 * 1024)
                            pct = (downloaded / total_bytes) * 100
                            print(f"  Downloaded: {mb_dl:.1f} MB / {mb_total:.1f} MB ({pct:.1f}%)")
                        else:
                            print(f"  Downloaded: {mb_dl:.1f} MB")

            print(f"Download complete: {dest_path} ({os.path.getsize(dest_path) / (1024*1024):.1f} MB)")
            return True

    except urllib.error.HTTPError as e:
        if e.code == 416:  # Range Not Satisfiable (already fully downloaded)
            print("File is already fully downloaded.")
            return True
        print(f"HTTP Error during download: {e}")
        return False
    except Exception as e:
        print(f"Download exception: {e}")
        return False


class GolfCourseIdentifier(osmium.SimpleHandler):
    """Pass 1: Identifies golf courses and their bounding perimeters from the PBF."""

    def __init__(self):
        super().__init__()
        self.courses = []

    def _extract_course_info(self, obj, geom_type):
        tags = obj.tags
        if tags.get("leisure") != "golf_course":
            return

        name = tags.get("name", "").strip()
        if not name or tags.get("sport") == "disc_golf":
            return

        holes = 18
        if "holes" in tags:
            try:
                holes = int(tags.get("holes"))
            except ValueError:
                pass
        elif tags.get("golf:course") == "9_hole":
            holes = 9

        city = tags.get("addr:city", "")
        state = tags.get("addr:state", "")
        country = tags.get("addr:country", "")
        location_parts = [p for p in [city, state, country] if p]
        location = ", ".join(location_parts)

        # Calculate bounding box from way nodes if available
        lat_sum, lon_sum, count = 0.0, 0.0, 0
        min_lat, max_lat = 90.0, -90.0
        min_lon, max_lon = 180.0, -180.0

        if geom_type == "way":
            for n in obj.nodes:
                if n.is_valid():
                    lat_sum += n.lat
                    lon_sum += n.lon
                    count += 1
                    min_lat = min(min_lat, n.lat)
                    max_lat = max(max_lat, n.lat)
                    min_lon = min(min_lon, n.lon)
                    max_lon = max(max_lon, n.lon)

        center_lat = (lat_sum / count) if count > 0 else 0.0
        center_lon = (lon_sum / count) if count > 0 else 0.0

        if count == 0:
            return

        # Add ~500m margin to bbox for hole features, trees, and hazards
        deg_margin = 0.008
        bbox = (min_lat - deg_margin, min_lon - deg_margin, max_lat + deg_margin, max_lon + deg_margin)

        self.courses.append({
            "id": obj.id,
            "type": geom_type,
            "name": name,
            "slug": slugify(name),
            "lat": center_lat,
            "lon": center_lon,
            "location": location,
            "hole_count": holes,
            "last_updated": time.strftime("%Y-%m-%d"),
            "bbox": bbox
        })

    def way(self, w):
        self._extract_course_info(w, "way")


class CourseFeatureExtractor(osmium.SimpleHandler):
    """Pass 2: Extracts golf ways, nodes, and hazards belonging to course bounding boxes."""

    def __init__(self, course_targets):
        super().__init__()
        self.course_targets = course_targets  # list of course dicts
        self.course_data = {c["slug"]: {"nodes": {}, "ways": [], "relations": []} for c in course_targets}

        # Spatial grid index for O(1) candidate lookup
        self.grid_cell_size = 0.05  # ~5 km grid
        self.grid = {}
        for c in course_targets:
            min_lat, min_lon, max_lat, max_lon = c["bbox"]
            gx_min = int(math.floor(min_lat / self.grid_cell_size))
            gx_max = int(math.floor(max_lat / self.grid_cell_size))
            gy_min = int(math.floor(min_lon / self.grid_cell_size))
            gy_max = int(math.floor(max_lon / self.grid_cell_size))
            for gx in range(gx_min, gx_max + 1):
                for gy in range(gy_min, gy_max + 1):
                    key = (gx, gy)
                    if key not in self.grid:
                        self.grid[key] = []
                    self.grid[key].append(c)

    def _get_matching_courses(self, lat, lon):
        gx = int(math.floor(lat / self.grid_cell_size))
        gy = int(math.floor(lon / self.grid_cell_size))
        candidates = self.grid.get((gx, gy))
        if not candidates:
            return []
        matches = []
        for c in candidates:
            bbox = c["bbox"]
            if bbox[0] <= lat <= bbox[2] and bbox[1] <= lon <= bbox[3]:
                matches.append(c)
        return matches

    def node(self, n):
        if not n.is_valid():
            return
        matches = self._get_matching_courses(n.lat, n.lon)
        if not matches:
            return
        tags = {t.k: t.v for t in n.tags}
        for c in matches:
            self.course_data[c["slug"]]["nodes"][n.id] = {
                "type": "node",
                "id": n.id,
                "lat": n.lat,
                "lon": n.lon,
                "tags": tags
            }

    def way(self, w):
        tags = {t.k: t.v for t in w.tags}
        # Keep relevant golf and landscape layers
        is_relevant = (
            "golf" in tags or
            tags.get("leisure") == "golf_course" or
            tags.get("natural") in ("water", "wood") or
            tags.get("landuse") == "forest"
        )
        if not is_relevant:
            return

        node_refs = []
        way_lats, way_lons = [], []
        for n in w.nodes:
            node_refs.append(n.ref)
            if n.is_valid():
                way_lats.append(n.lat)
                way_lons.append(n.lon)

        if not way_lats:
            return

        avg_lat = sum(way_lats) / len(way_lats)
        avg_lon = sum(way_lons) / len(way_lons)

        matches = self._get_matching_courses(avg_lat, avg_lon)
        if not matches:
            return

        for c in matches:
            self.course_data[c["slug"]]["ways"].append({
                "type": "way",
                "id": w.id,
                "nodes": node_refs,
                "tags": tags
            })
            # Ensure all way nodes are recorded
            for n in w.nodes:
                if n.is_valid():
                    self.course_data[c["slug"]]["nodes"][n.ref] = {
                        "type": "node",
                        "id": n.ref,
                        "lat": n.lat,
                        "lon": n.lon,
                        "tags": {}
                    }


def process_pbf_file(
    pbf_path: str,
    cache_dir: str,
    max_courses: int = 2500,
    idx_type: str = "auto",
    temp_dir: str = None
) -> list:
    """Extract golf courses from a PBF file and write compressed vector geometries."""
    os.makedirs(cache_dir, exist_ok=True)
    file_size_gb = (os.path.getsize(pbf_path) / (1024 * 1024 * 1024)) if os.path.exists(pbf_path) else 0.0

    # Configure adaptive node location indexing strategy
    temp_idx_file = None
    if idx_type == "auto":
        # Extracts >= 2.5 GB have hundreds of millions of nodes; flex_mem causes std::bad_alloc (MemoryError).
        if file_size_gb >= 2.5:
            chosen_idx = "sparse_file_array"
        else:
            chosen_idx = "sparse_mem_array"
    else:
        chosen_idx = idx_type

    if chosen_idx.startswith("sparse_file_array") or chosen_idx.startswith("dense_file_array"):
        if "," in chosen_idx:
            actual_idx = chosen_idx
        else:
            if not temp_dir:
                temp_dir = os.path.dirname(pbf_path)
            temp_idx_file = os.path.join(temp_dir, f"_osmium_node_idx_{os.getpid()}.dat")
            actual_idx = f"{chosen_idx},{temp_idx_file}"

        free_bytes = shutil.disk_usage(os.path.dirname(temp_idx_file or pbf_path)).free
        free_gb = free_bytes / (1024 * 1024 * 1024)
        print(f"Using disk-backed node location index ({chosen_idx}) to prevent memory errors.")
        print(f"  PBF Size: {file_size_gb:.1f} GB | Available Disk: {free_gb:.1f} GB")
        est_needed_gb = file_size_gb * 1.8
        if free_gb < est_needed_gb:
            print(f"  [Warning] Disk-backed index may require ~{est_needed_gb:.1f} GB, but only {free_gb:.1f} GB is free.")
            print(f"  If disk space is limited, consider using regional extracts (e.g. us-pacific, us-midwest, california).")
    else:
        actual_idx = chosen_idx
        print(f"Using in-memory node location index: {actual_idx}")

    print(f"\n[Step 1/2] Scanning '{os.path.basename(pbf_path)}' for golf courses with osmium...")

    try:
        id_handler = GolfCourseIdentifier()
        id_handler.apply_file(pbf_path, locations=True, idx=actual_idx)
        identified = id_handler.courses

        # Deduplicate identified courses by slug and proximity
        unique_courses = {}
        for c in identified:
            slug = c["slug"]
            if slug not in unique_courses:
                unique_courses[slug] = c

        course_list = list(unique_courses.values())
        if max_courses > 0:
            course_list = course_list[:max_courses]

        print(f"Identified {len(course_list)} unique named golf course(s) to extract.")

        print(f"[Step 2/2] Extracting feature geometries and generating compressed packages...")
        feat_handler = CourseFeatureExtractor(course_list)
        feat_handler.apply_file(pbf_path, locations=True, idx=actual_idx)

        generated_catalog_entries = []
        saved_count = 0

        for c in course_list:
            slug = c["slug"]
            data = feat_handler.course_data.get(slug)
            if not data or not data["ways"]:
                continue

            elements = list(data["nodes"].values()) + data["ways"]
            osm_json = {
                "version": 0.6,
                "generator": "HeckleGolfSim-OsmSync/1.0",
                "elements": elements
            }

            json_bytes = json.dumps(osm_json, ensure_ascii=False).encode("utf-8")
            compressed_bytes = gzip.compress(json_bytes, compresslevel=9)

            out_path = os.path.join(cache_dir, f"{slug}.json.gz")
            with open(out_path, "wb") as f_out:
                f_out.write(compressed_bytes)

            generated_catalog_entries.append({
                "name": c["name"],
                "lat": round(c["lat"], 6),
                "lon": round(c["lon"], 6),
                "location": c["location"],
                "hole_count": c["hole_count"],
                "last_updated": c["last_updated"]
            })
            saved_count += 1

        print(f"Successfully generated {saved_count} pre-packaged course geometries in: {cache_dir}")
        return generated_catalog_entries

    finally:
        if temp_idx_file and os.path.exists(temp_idx_file):
            try:
                os.remove(temp_idx_file)
                print(f"Cleaned up temporary node location index: {temp_idx_file}")
            except Exception as e:
                print(f"Notice: Temporary index file {temp_idx_file} can be removed after process exits: {e}")


def update_global_catalog(new_entries: list, catalog_path: str):
    """Merge newly extracted courses into the global catalog JSON."""
    os.makedirs(os.path.dirname(catalog_path), exist_ok=True)
    existing_catalog = []

    if os.path.exists(catalog_path):
        try:
            with open(catalog_path, "r", encoding="utf-8") as f:
                existing_catalog = json.load(f)
        except Exception as e:
            print(f"Warning: Could not read existing catalog ({e}); creating a new one.")

    merged = {c["name"].lower(): c for c in existing_catalog}
    for entry in new_entries:
        key = entry["name"].lower()
        if key not in merged:
            merged[key] = entry
        else:
            # Update hole count or date if newly available
            if entry["hole_count"] > 0:
                merged[key]["hole_count"] = entry["hole_count"]
            merged[key]["last_updated"] = entry["last_updated"]

    final_list = sorted(merged.values(), key=lambda x: x["name"].lower())
    with open(catalog_path, "w", encoding="utf-8") as f:
        json.dump(final_list, f, indent=2, ensure_ascii=False)

    print(f"Updated global catalog: {catalog_path}")
    print(f"Total catalog courses: {len(final_list)} (added/updated {len(new_entries)})")


def run_monthly_sync(
    regions,
    download_dir,
    cache_dir,
    catalog_path,
    max_courses,
    skip_download,
    clean,
    num_threads=8,
    chunk_size_mb=8,
    single_thread=False,
    idx_type="auto",
    temp_dir=None
):
    print("=" * 70)
    print("  HeckleGolfSim Monthly OpenStreetMap Course Sync & Pre-Packager")
    print("=" * 70)
    print(f"Regions to process : {', '.join(regions)}")
    print(f"Download Directory : {download_dir}")
    print(f"Cached Geometries  : {cache_dir}")
    print(f"Global Catalog     : {catalog_path}")
    print(f"Max Courses/Region : {max_courses if max_courses > 0 else 'Unlimited'}")
    print(f"Download Mode      : {'Single-threaded' if single_thread else f'Parallel ({num_threads} threads, {chunk_size_mb} MB chunks)'}")
    print(f"Location Indexing  : {idx_type} (auto switches to disk-backed for large extracts)")
    print("=" * 70)

    all_catalog_entries = []

    for reg in regions:
        url = GEOFABRIK_REGIONS.get(reg.lower())
        if not url:
            print(f"Unknown region '{reg}'. Supported: {', '.join(GEOFABRIK_REGIONS.keys())}")
            continue

        pbf_filename = f"{reg}-latest.osm.pbf"
        pbf_path = os.path.join(download_dir, pbf_filename)

        print(f"\n>>> Processing Region: {reg.upper()} <<<")
        if not skip_download or not os.path.exists(pbf_path):
            print(f"Fetching latest extract from:\n  {url}")
            if single_thread:
                success = download_file_resumable(url, pbf_path)
            else:
                success = download_file_parallel(
                    url,
                    pbf_path,
                    num_threads=num_threads,
                    chunk_size_mb=chunk_size_mb
                )

            if not success:
                print(f"Failed to download {reg}. Skipping.")
                continue
        else:
            print(f"Using existing PBF file: {pbf_path}")

        extracted_entries = process_pbf_file(
            pbf_path,
            cache_dir,
            max_courses=max_courses,
            idx_type=idx_type,
            temp_dir=temp_dir
        )
        all_catalog_entries.extend(extracted_entries)

        if clean and os.path.exists(pbf_path):
            print(f"Cleaning up {pbf_path} to reclaim disk space...")
            os.remove(pbf_path)

    if all_catalog_entries:
        update_global_catalog(all_catalog_entries, catalog_path)

    print("\n" + "=" * 70)
    print("Monthly OpenStreetMap sync complete! Enjoy fast, offline course play.")
    print("=" * 70)


def main():
    parser = argparse.ArgumentParser(
        description="Download OSM extracts and generate pre-packaged course geometries for HeckleGolfSim."
    )
    parser.add_argument(
        "--preset",
        choices=list(PRESETS.keys()) + ["none"],
        default="top-golf",
        help=(
            "Predefined region preset. 'top-golf' downloads safe US regions + UK, Ireland, Canada, Australia. "
            "'top-states' downloads iconic golf states. 'us-regions' downloads all 5 US subregions. (default: top-golf)"
        )
    )
    parser.add_argument(
        "--regions",
        nargs="+",
        default=None,
        help="Custom Geofabrik regions to process (e.g. us-pacific california great-britain). Overrides --preset."
    )
    parser.add_argument(
        "--threads",
        type=int,
        default=8,
        help="Number of concurrent download streams for parallel Range downloading (default: 8)."
    )
    parser.add_argument(
        "--chunk-size-mb",
        type=int,
        default=8,
        help="Size of each chunk in MB for parallel downloads (default: 8 MB)."
    )
    parser.add_argument(
        "--single-thread",
        action="store_true",
        help="Use basic single-stream download instead of parallel chunk streams."
    )
    parser.add_argument(
        "--idx-type",
        choices=["auto", "sparse_file_array", "sparse_mem_array", "flex_mem", "dense_file_array"],
        default="auto",
        help=(
            "Osmium node location index strategy. 'auto' selects sparse_file_array (on-disk) for extracts >= 2.5 GB "
            "to prevent MemoryError: bad allocation, and sparse_mem_array for smaller extracts. (default: auto)"
        )
    )
    parser.add_argument(
        "--temp-dir",
        default=None,
        help="Custom directory for temporary disk-backed index files when using sparse_file_array."
    )
    parser.add_argument(
        "--download-dir",
        default=DEFAULT_DOWNLOAD_DIR,
        help="Directory to store downloaded .osm.pbf extracts."
    )
    parser.add_argument(
        "--cache-dir",
        default=DEFAULT_CACHE_DIR,
        help="Directory to output pre-packaged .json.gz course geometries."
    )
    parser.add_argument(
        "--catalog-path",
        default=DEFAULT_CATALOG_PATH,
        help="Path to the global course catalog JSON file."
    )
    parser.add_argument(
        "--max-courses",
        type=int,
        default=2500,
        help="Maximum courses to extract per region (default: 2500 for a total of ~5000)."
    )
    parser.add_argument(
        "--skip-download",
        action="store_true",
        help="Skip downloading if the .osm.pbf file already exists locally."
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Remove large .osm.pbf extract files after processing to save disk space."
    )

    args = parser.parse_args()

    # Determine regions to process
    if args.regions:
        selected_regions = args.regions
    elif args.preset and args.preset in PRESETS:
        preset_info = PRESETS[args.preset]
        print(f"Applying Preset: {preset_info['name']} - {preset_info['description']}")
        selected_regions = preset_info["regions"]
    else:
        selected_regions = ["us-pacific"]

    run_monthly_sync(
        regions=selected_regions,
        download_dir=args.download_dir,
        cache_dir=args.cache_dir,
        catalog_path=args.catalog_path,
        max_courses=args.max_courses,
        skip_download=args.skip_download,
        clean=args.clean,
        num_threads=args.threads,
        chunk_size_mb=args.chunk_size_mb,
        single_thread=args.single_thread,
        idx_type=args.idx_type,
        temp_dir=args.temp_dir
    )


if __name__ == "__main__":
    main()
