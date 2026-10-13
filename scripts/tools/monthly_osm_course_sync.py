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
import subprocess
import sys
import threading
import time
import urllib.request
import urllib.error
import uuid

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
    # 50 US States + DC & Puerto Rico:
    "alabama": "https://download.geofabrik.de/north-america/us/alabama-latest.osm.pbf",
    "alaska": "https://download.geofabrik.de/north-america/us/alaska-latest.osm.pbf",
    "arizona": "https://download.geofabrik.de/north-america/us/arizona-latest.osm.pbf",
    "arkansas": "https://download.geofabrik.de/north-america/us/arkansas-latest.osm.pbf",
    "california": "https://download.geofabrik.de/north-america/us/california-latest.osm.pbf",
    "colorado": "https://download.geofabrik.de/north-america/us/colorado-latest.osm.pbf",
    "connecticut": "https://download.geofabrik.de/north-america/us/connecticut-latest.osm.pbf",
    "delaware": "https://download.geofabrik.de/north-america/us/delaware-latest.osm.pbf",
    "district-of-columbia": "https://download.geofabrik.de/north-america/us/district-of-columbia-latest.osm.pbf",
    "florida": "https://download.geofabrik.de/north-america/us/florida-latest.osm.pbf",
    "georgia": "https://download.geofabrik.de/north-america/us/georgia-latest.osm.pbf",
    "hawaii": "https://download.geofabrik.de/north-america/us/hawaii-latest.osm.pbf",
    "idaho": "https://download.geofabrik.de/north-america/us/idaho-latest.osm.pbf",
    "illinois": "https://download.geofabrik.de/north-america/us/illinois-latest.osm.pbf",
    "indiana": "https://download.geofabrik.de/north-america/us/indiana-latest.osm.pbf",
    "iowa": "https://download.geofabrik.de/north-america/us/iowa-latest.osm.pbf",
    "kansas": "https://download.geofabrik.de/north-america/us/kansas-latest.osm.pbf",
    "kentucky": "https://download.geofabrik.de/north-america/us/kentucky-latest.osm.pbf",
    "louisiana": "https://download.geofabrik.de/north-america/us/louisiana-latest.osm.pbf",
    "maine": "https://download.geofabrik.de/north-america/us/maine-latest.osm.pbf",
    "maryland": "https://download.geofabrik.de/north-america/us/maryland-latest.osm.pbf",
    "massachusetts": "https://download.geofabrik.de/north-america/us/massachusetts-latest.osm.pbf",
    "michigan": "https://download.geofabrik.de/north-america/us/michigan-latest.osm.pbf",
    "minnesota": "https://download.geofabrik.de/north-america/us/minnesota-latest.osm.pbf",
    "mississippi": "https://download.geofabrik.de/north-america/us/mississippi-latest.osm.pbf",
    "missouri": "https://download.geofabrik.de/north-america/us/missouri-latest.osm.pbf",
    "montana": "https://download.geofabrik.de/north-america/us/montana-latest.osm.pbf",
    "nebraska": "https://download.geofabrik.de/north-america/us/nebraska-latest.osm.pbf",
    "nevada": "https://download.geofabrik.de/north-america/us/nevada-latest.osm.pbf",
    "new-hampshire": "https://download.geofabrik.de/north-america/us/new-hampshire-latest.osm.pbf",
    "new-jersey": "https://download.geofabrik.de/north-america/us/new-jersey-latest.osm.pbf",
    "new-mexico": "https://download.geofabrik.de/north-america/us/new-mexico-latest.osm.pbf",
    "new-york": "https://download.geofabrik.de/north-america/us/new-york-latest.osm.pbf",
    "north-carolina": "https://download.geofabrik.de/north-america/us/north-carolina-latest.osm.pbf",
    "north-dakota": "https://download.geofabrik.de/north-america/us/north-dakota-latest.osm.pbf",
    "ohio": "https://download.geofabrik.de/north-america/us/ohio-latest.osm.pbf",
    "oklahoma": "https://download.geofabrik.de/north-america/us/oklahoma-latest.osm.pbf",
    "oregon": "https://download.geofabrik.de/north-america/us/oregon-latest.osm.pbf",
    "pennsylvania": "https://download.geofabrik.de/north-america/us/pennsylvania-latest.osm.pbf",
    "puerto-rico": "https://download.geofabrik.de/north-america/us/puerto-rico-latest.osm.pbf",
    "rhode-island": "https://download.geofabrik.de/north-america/us/rhode-island-latest.osm.pbf",
    "south-carolina": "https://download.geofabrik.de/north-america/us/south-carolina-latest.osm.pbf",
    "south-dakota": "https://download.geofabrik.de/north-america/us/south-dakota-latest.osm.pbf",
    "tennessee": "https://download.geofabrik.de/north-america/us/tennessee-latest.osm.pbf",
    "texas": "https://download.geofabrik.de/north-america/us/texas-latest.osm.pbf",
    "utah": "https://download.geofabrik.de/north-america/us/utah-latest.osm.pbf",
    "vermont": "https://download.geofabrik.de/north-america/us/vermont-latest.osm.pbf",
    "virginia": "https://download.geofabrik.de/north-america/us/virginia-latest.osm.pbf",
    "washington": "https://download.geofabrik.de/north-america/us/washington-latest.osm.pbf",
    "west-virginia": "https://download.geofabrik.de/north-america/us/west-virginia-latest.osm.pbf",
    "wisconsin": "https://download.geofabrik.de/north-america/us/wisconsin-latest.osm.pbf",
    "wyoming": "https://download.geofabrik.de/north-america/us/wyoming-latest.osm.pbf",

    # European Countries & Regions:
    "austria": "https://download.geofabrik.de/europe/austria-latest.osm.pbf",
    "belgium": "https://download.geofabrik.de/europe/belgium-latest.osm.pbf",
    "croatia": "https://download.geofabrik.de/europe/croatia-latest.osm.pbf",
    "cyprus": "https://download.geofabrik.de/europe/cyprus-latest.osm.pbf",
    "czech-republic": "https://download.geofabrik.de/europe/czech-republic-latest.osm.pbf",
    "denmark": "https://download.geofabrik.de/europe/denmark-latest.osm.pbf",
    "estonia": "https://download.geofabrik.de/europe/estonia-latest.osm.pbf",
    "finland": "https://download.geofabrik.de/europe/finland-latest.osm.pbf",
    "france": "https://download.geofabrik.de/europe/france-latest.osm.pbf",
    "germany": "https://download.geofabrik.de/europe/germany-latest.osm.pbf",
    "great-britain": "https://download.geofabrik.de/europe/great-britain-latest.osm.pbf",
    "greece": "https://download.geofabrik.de/europe/greece-latest.osm.pbf",
    "hungary": "https://download.geofabrik.de/europe/hungary-latest.osm.pbf",
    "iceland": "https://download.geofabrik.de/europe/iceland-latest.osm.pbf",
    "ireland": "https://download.geofabrik.de/europe/ireland-and-northern-ireland-latest.osm.pbf",
    "italy": "https://download.geofabrik.de/europe/italy-latest.osm.pbf",
    "latvia": "https://download.geofabrik.de/europe/latvia-latest.osm.pbf",
    "lithuania": "https://download.geofabrik.de/europe/lithuania-latest.osm.pbf",
    "luxembourg": "https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf",
    "netherlands": "https://download.geofabrik.de/europe/netherlands-latest.osm.pbf",
    "norway": "https://download.geofabrik.de/europe/norway-latest.osm.pbf",
    "poland": "https://download.geofabrik.de/europe/poland-latest.osm.pbf",
    "portugal": "https://download.geofabrik.de/europe/portugal-latest.osm.pbf",
    "romania": "https://download.geofabrik.de/europe/romania-latest.osm.pbf",
    "scotland": "https://download.geofabrik.de/europe/great-britain/scotland-latest.osm.pbf",
    "slovakia": "https://download.geofabrik.de/europe/slovakia-latest.osm.pbf",
    "slovenia": "https://download.geofabrik.de/europe/slovenia-latest.osm.pbf",
    "spain": "https://download.geofabrik.de/europe/spain-latest.osm.pbf",
    "sweden": "https://download.geofabrik.de/europe/sweden-latest.osm.pbf",
    "switzerland": "https://download.geofabrik.de/europe/switzerland-latest.osm.pbf",
    "turkey": "https://download.geofabrik.de/europe/turkey-latest.osm.pbf",

    # Other Golf Countries:
    "canada": "https://download.geofabrik.de/north-america/canada-latest.osm.pbf",
    "australia": "https://download.geofabrik.de/australia-oceania/australia-latest.osm.pbf",
    "japan": "https://download.geofabrik.de/asia/japan-latest.osm.pbf",

    # US Multi-State Regional extracts (large chunks):
    "us-midwest": "https://download.geofabrik.de/north-america/us-midwest-latest.osm.pbf",
    "us-northeast": "https://download.geofabrik.de/north-america/us-northeast-latest.osm.pbf",
    "us-pacific": "https://download.geofabrik.de/north-america/us-pacific-latest.osm.pbf",
    "us-south": "https://download.geofabrik.de/north-america/us-south-latest.osm.pbf",
    "us-west": "https://download.geofabrik.de/north-america/us-west-latest.osm.pbf",

    # Full monolithic extracts:
    "us": "https://download.geofabrik.de/north-america/us-latest.osm.pbf",
    "north-america": "https://download.geofabrik.de/north-america-latest.osm.pbf",
    "europe": "https://download.geofabrik.de/europe-latest.osm.pbf",
}

ALL_US_STATES = [
    "alabama", "alaska", "arizona", "arkansas", "california", "colorado", "connecticut", "delaware",
    "district-of-columbia", "florida", "georgia", "hawaii", "idaho", "illinois", "indiana", "iowa",
    "kansas", "kentucky", "louisiana", "maine", "maryland", "massachusetts", "michigan", "minnesota",
    "mississippi", "missouri", "montana", "nebraska", "nevada", "new-hampshire", "new-jersey",
    "new-mexico", "new-york", "north-carolina", "north-dakota", "ohio", "oklahoma", "oregon",
    "pennsylvania", "puerto-rico", "rhode-island", "south-carolina", "south-dakota", "tennessee",
    "texas", "utah", "vermont", "virginia", "washington", "west-virginia", "wisconsin", "wyoming"
]

ALL_EUROPE_COUNTRIES = [
    "great-britain", "ireland", "spain", "france", "germany", "italy", "portugal", "sweden",
    "denmark", "netherlands", "belgium", "austria", "switzerland", "norway", "finland", "czech-republic",
    "poland", "hungary", "greece", "turkey", "slovakia", "slovenia", "croatia", "iceland", "romania",
    "cyprus", "estonia", "latvia", "lithuania", "luxembourg"
]

PRESETS = {
    "us-and-europe": {
        "name": "All 50 US States + Top European Golf Countries (Fastest & Small Extracts)",
        "description": "Iterates individual state & country extracts (<1 GB each) in memory with progress tracking",
        "regions": ALL_US_STATES + ALL_EUROPE_COUNTRIES
    },
    "us-states": {
        "name": "All 50 US States (Individual State Extracts)",
        "description": "All 50 US states + DC & Puerto Rico processed individually using in-memory indexing",
        "regions": ALL_US_STATES
    },
    "europe-countries": {
        "name": "Individual European Golf Countries",
        "description": "UK, Ireland, Spain, France, Germany, and European golfing nations individually",
        "regions": ALL_EUROPE_COUNTRIES
    },
    "top-states": {
        "name": "Iconic Golf States & Scotland (Ultra Fast)",
        "description": "California, Florida, Texas, New York, Scotland (~3.5 GB total)",
        "regions": ["california", "florida", "texas", "new-york", "scotland"]
    },
    "top-golf": {
        "name": "Top Golf Countries & US Regions (Legacy)",
        "description": "US Regions (Pacific, South, Midwest, Northeast, West) + UK, Ireland, Canada, Australia",
        "regions": ["us-pacific", "us-south", "us-midwest", "us-northeast", "us-west", "great-britain", "ireland", "canada", "australia"]
    },
    "us-regions": {
        "name": "All 5 US Subregions (Multi-State Blocks)",
        "description": "US Pacific, South, Midwest, Northeast, West (~11.5 GB in regional chunks)",
        "regions": ["us-pacific", "us-south", "us-midwest", "us-northeast", "us-west"]
    },
    "uk-ireland": {
        "name": "UK & Ireland Only",
        "description": "Great Britain & Ireland (~2.2 GB)",
        "regions": ["great-britain", "ireland"]
    },
    "continents": {
        "name": "Entire Continents (Very Large)",
        "description": "Full North America + Europe (~43 GB, monolithic extracts)",
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


def log_timestamp(message: str):
    """Print message prefixed with current wall-clock timestamp [HH:MM:SS]."""
    now = time.strftime("%H:%M:%S")
    print(f"[{now}] {message}", flush=True)


class StepHeartbeat:
    """Background heartbeat timer that periodically prints progress while long-running steps execute."""

    def __init__(self, step_name: str, interval: float = 60.0):
        self.step_name = step_name
        self.interval = interval
        self.stop_event = threading.Event()
        self.start_time = time.time()
        self.counter_callback = None
        self.thread = threading.Thread(target=self._run, daemon=True)

    def set_counter(self, callback):
        self.counter_callback = callback
        return self

    def start(self):
        self.thread.start()
        return self

    def stop(self):
        self.stop_event.set()
        self.thread.join(timeout=1.0)

    def _run(self):
        while not self.stop_event.wait(self.interval):
            elapsed = time.time() - self.start_time
            m, s = divmod(int(elapsed), 60)
            extra = ""
            if self.counter_callback:
                try:
                    extra = f" | {self.counter_callback()}"
                except Exception:
                    pass
            log_timestamp(f"[Heartbeat] {self.step_name} still running... (elapsed: {m}m {s:02d}s{extra})")



# Well-known PGA Tour, DP World Tour, Major Championship, and prestigious golf venues
PGA_TOUR_AND_MAJOR_COURSES = {
    # Iconic Major & US Open / PGA Championship venues
    "augusta national", "pebble beach", "cypress point", "pinehurst", "oakmont",
    "shinnecock hills", "merion", "winge foot", "winged foot", "baltusrol", "bethpage",
    "oak hill", "southern hills", "whistling straits", "hazeltine", "torrey pines",
    "tpc sawgrass", "tpc scottsdale", "tpc southwind", "tpc river highlands",
    "tpc summerlin", "tpc deer run", "tpc boston", "tpc san antonio", "tpc louisiana",
    "tpc twin cities", "tpc potomac", "quail hollow", "harbour town", "riviera",
    "bay hill", "muirfield village", "innisbrook", "colonial country club",
    "east lake", "kapalua", "waialae", "pete dye golf club", "kiawah island", "ocean course",
    "erin hills", "chambers bay", "olympic club", "medinah", "valhalla", "charlotte country club",
    "scripps ranch", "sea island", "conway farms", "cog hill", "sedgefield", "detroit golf club",
    "tpc craig ranch", "memorial park", "pebble beach golf links", "spyglass hill",
    "monterey peninsula", "cypress point club", "los angeles country club", "lacc",
    "bel air country club", "bellerive", "aronomink", "plainfield", "liberty national",
    "ridgewood country club", "cherry hills", "crooked stick", "scioto", "inverness club",
    "olympia fields", "interlachen", "minikahda", "sand hills", "bandon dunes",
    "pacific dunes", "bandon trails", "old macdonald", "sheep ranch", "bandon preserve",
    "cabot cliffs", "cabot links", "banff springs", "st george's", "hamilton golf",
    # Iconic Open Championship (UK & Europe) venues
    "st andrews", "old course", "carnoustie", "muirfield", "royal troon",
    "royal birkdale", "royal lytham", "royal st george", "royal liverpool", "hoylake",
    "turnberry", "ailsa", "royal portrush", "dunluce", "prestwick",
    "kingsbarns", "north berwick", "gullane", "western gailes", "cruden bay",
    "royal dornoch", "castle stuart", "trump international golf links", "gleneagles",
    "ballyliffin", "lahinch", "ballybunion", "portmarnock", "the k club", "k club",
    "mount juliet", "druids glen", "adare manor", "rosapenna", "waterville",
    "county sligo", "county louth", "baltray", "tralee", "royal county down",
    "wentworth", "sunningdale", "walton heath", "swinley forest", "woodhall spa",
    "the belfry", "belfry", "le golf national", "valderrama", "real club valderrama",
    "rcg sotogrande", "finca cortesin", "pga catalunya", "camiral", "marco simone",
    "olgiata", "crans sur sierre", "golf club gut larchenhof", "green eagle",
    "bro hof slott", "kennemer", "hilversumsche", "bernardus"
}


def compute_course_priority(c: dict) -> tuple:
    """Compute sorting priority for a course:
    1. Rating or PGA tour status (primary selection)
       - Rating score derived from explicit OSM rating/stars tags or known PGA/Major venue status.
    2. Most recently updated timestamp (secondary selection)
    3. Hole count (18-hole courses prioritized over uncompleted layouts)
    """
    has_pga = bool(c.get("is_pga_tour", False))
    rating = float(c.get("rating", 0.0))
    rating_or_pga_score = 0.0

    if has_pga:
        rating_or_pga_score = max(rating_or_pga_score, 100.0 + rating)
    elif rating > 0.0:
        rating_or_pga_score = max(rating_or_pga_score, rating)

    # Secondary selection: last_updated timestamp (YYYY-MM-DD or ISO string)
    updated_str = str(c.get("last_updated", "")).strip()

    # Hole count weighting (prefer 18 or 9 complete layouts over 0/unknown)
    holes = int(c.get("hole_count", 0))

    return (rating_or_pga_score, updated_str, holes)


def validate_course_elements(data: dict) -> tuple:
    """
    Validates whether extracted OSM course elements meet the required metadata
    criteria to build a playable golf course in HeckleGolfSim.

    Criteria:
    1. Valid hole count: Must have 9, 18, 27, 36 holes (or multiples of 9 >= 9).
       Single-hole courses or unmapped/incomplete hole layouts are excluded.
    2. Fairways defined: At least 1 fairway feature (golf=fairway way or relation).
    3. Tee boxes required: At least 1 tee box feature (golf=tee way, node, or relation).
    4. Greens defined: At least 1 green feature (golf=green or golf=pin way, node, or relation).

    Returns:
        (is_valid: bool, verified_holes: int, reason: str)
    """
    if not isinstance(data, dict):
        return False, 0, "Invalid data structure"

    if "elements" in data:
        elements = data["elements"]
        ways = [e for e in elements if isinstance(e, dict) and e.get("type") == "way"]
        nodes = [e for e in elements if isinstance(e, dict) and e.get("type") == "node"]
        relations = [e for e in elements if isinstance(e, dict) and e.get("type") == "relation"]
    else:
        ways = data.get("ways", [])
        raw_nodes = data.get("nodes", {})
        if isinstance(raw_nodes, dict):
            nodes = list(raw_nodes.values())
        elif isinstance(raw_nodes, list):
            nodes = raw_nodes
        else:
            nodes = []
        relations = data.get("relations", [])

    # 1. Fairways
    fairways = [w for w in ways if w.get("tags", {}).get("golf") == "fairway"]
    rel_fairways = [r for r in relations if r.get("tags", {}).get("golf") == "fairway"]
    if (len(fairways) + len(rel_fairways)) == 0:
        return False, 0, "No fairways defined (course requires defined fairways)"

    # 2. Tee boxes
    tee_ways = [w for w in ways if w.get("tags", {}).get("golf") == "tee"]
    tee_nodes = [n for n in nodes if n.get("tags", {}).get("golf") == "tee"]
    tee_rels = [r for r in relations if r.get("tags", {}).get("golf") == "tee"]
    if (len(tee_ways) + len(tee_nodes) + len(tee_rels)) == 0:
        return False, 0, "No tee boxes defined (tee box is required)"

    # 3. Greens
    green_ways = [w for w in ways if w.get("tags", {}).get("golf") in ("green", "pin")]
    green_nodes = [n for n in nodes if n.get("tags", {}).get("golf") in ("green", "pin")]
    green_rels = [r for r in relations if r.get("tags", {}).get("golf") in ("green", "pin")]
    if (len(green_ways) + len(green_nodes) + len(green_rels)) == 0:
        return False, 0, "No greens defined (course requires defined greens)"

    # 4. Holes
    hole_ways = [w for w in ways if w.get("tags", {}).get("golf") == "hole" and len(w.get("nodes", [])) >= 2]
    hole_rels = [r for r in relations if r.get("tags", {}).get("golf") == "hole"]

    hole_keys = set()
    for w in hole_ways:
        tags = w.get("tags", {})
        sub = (tags.get("golf:course:name") or tags.get("course:name") or
               tags.get("golf:course") or tags.get("course") or "").strip().lower()
        ref = tags.get("ref", "").strip()
        name = tags.get("name", "").strip()
        if ref:
            key = f"{sub}:{ref}" if sub else ref
        else:
            m = re.search(r'\b([1-9]|[1-2][0-9]|3[0-6])\b', name)
            if m:
                key = f"{sub}:{m.group(1)}" if sub else m.group(1)
            else:
                key = str(w.get("id"))
        hole_keys.add(key)

    for r in hole_rels:
        tags = r.get("tags", {})
        sub = (tags.get("golf:course:name") or tags.get("course:name") or
               tags.get("golf:course") or tags.get("course") or "").strip().lower()
        ref = tags.get("ref", "").strip()
        name = tags.get("name", "").strip()
        if ref:
            key = f"{sub}:{ref}" if sub else ref
        else:
            m = re.search(r'\b([1-9]|[1-2][0-9]|3[0-6])\b', name)
            if m:
                key = f"{sub}:{m.group(1)}" if sub else m.group(1)
            else:
                key = str(r.get("id"))
        hole_keys.add(key)

    detected_holes = len(hole_keys)
    if detected_holes == 0:
        return False, 0, "No holes defined (courses with 0 holes cannot be built)"

    if detected_holes < 9:
        return False, detected_holes, f"Only {detected_holes} hole(s) defined (search criteria requires 9, 18, 27, or 36 holes)"

    if detected_holes % 9 != 0:
        return False, detected_holes, f"{detected_holes} holes defined (must be a 9, 18, 27, or 36 hole course)"

    return True, detected_holes, f"Valid {detected_holes}-hole course"



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
    """Pass 1: Identifies golf courses, bounding perimeters, and tagged nodes from the PBF."""

    def __init__(self):
        super().__init__()
        self.courses = []
        self.ways_scanned = 0

    def _extract_course_info(self, obj, geom_type):
        tags = obj.tags
        if tags.get("leisure") != "golf_course":
            return

        name = tags.get("name", "").strip()
        if not name or tags.get("sport") == "disc_golf":
            return

        # Exclude individual golf features mistakenly tagged with leisure=golf_course
        if tags.get("golf") in ("green", "tee", "hole", "fairway", "bunker", "water_hazard", "driving_range", "practice_green"):
            return

        # Exclude individual feature names like "#2 Green", "#8 White Tee", "Tee 1", "green #4"
        if re.search(r'^(?:#?\d+\s*(?:green|tee|fairway|hole)|(?:tee|green|hole)\s*#?\d+)', name.lower()):
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
                if n.location.valid():
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

        # Determine rating and PGA Tour / prestigious tournament status
        clean_name = " " + re.sub(r'[^a-z0-9]+', ' ', name.lower()).strip() + " "
        is_pga = False
        for kw in PGA_TOUR_AND_MAJOR_COURSES:
            if f" {kw} " in clean_name or clean_name.strip() == kw:
                is_pga = True
                break

        # Check tags for explicit PGA status or tournament indicators
        tournament_tag = tags.get("tournament", "").lower()
        operator_tag = tags.get("operator", "").lower()
        if "pga" in tournament_tag or "pga" in operator_tag or "pga tour" in tags.get("description", "").lower():
            is_pga = True

        # Extract numeric or stars rating from OSM tags if present
        rating = 0.0
        for r_key in ["rating", "stars", "user_rating", "golf:rating"]:
            if r_key in tags:
                try:
                    val = float(re.findall(r'(\d+(?:\.\d+)?)', str(tags[r_key]))[0])
                    rating = max(rating, val)
                except (IndexError, ValueError):
                    pass

        # Extract object last_updated timestamp if available from OSM metadata
        obj_ts = getattr(obj, "timestamp", None)
        if obj_ts:
            try:
                last_updated = obj_ts.strftime("%Y-%m-%d") if hasattr(obj_ts, "strftime") else str(obj_ts)[:10]
            except Exception:
                last_updated = time.strftime("%Y-%m-%d")
        else:
            last_updated = time.strftime("%Y-%m-%d")

        self.courses.append({
            "id": obj.id,
            "type": geom_type,
            "name": name,
            "slug": slugify(name),
            "lat": center_lat,
            "lon": center_lon,
            "location": location,
            "hole_count": holes,
            "last_updated": last_updated,
            "is_pga_tour": is_pga,
            "rating": rating,
            "bbox": bbox
        })

    def way(self, w):
        self.ways_scanned += 1
        tags = w.tags
        if tags.get("leisure") != "golf_course":
            return
        self._extract_course_info(w, "way")


class CourseFeatureExtractor(osmium.SimpleHandler):
    """Pass 2: Extracts golf ways, nodes, and hazards belonging to course bounding boxes."""

    def __init__(self, course_targets):
        super().__init__()
        self.course_targets = course_targets  # list of course dicts
        self.course_data = {c["slug"]: {"nodes": {}, "ways": [], "relations": []} for c in course_targets}
        self.ways_scanned = 0
        self.ways_matched = 0
        self.relations_scanned = 0
        self.relations_matched = 0

        # Spatial grid index for O(1) candidate lookup
        self.grid_cell_size = 0.05  # ~5 km grid
        self.grid = {}
        self.min_all_lat = 90.0
        self.max_all_lat = -90.0
        self.min_all_lon = 180.0
        self.max_all_lon = -180.0

        for c in course_targets:
            min_lat, min_lon, max_lat, max_lon = c["bbox"]
            self.min_all_lat = min(self.min_all_lat, min_lat)
            self.max_all_lat = max(self.max_all_lat, max_lat)
            self.min_all_lon = min(self.min_all_lon, min_lon)
            self.max_all_lon = max(self.max_all_lon, max_lon)

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
        # Extremely fast global boundary check
        if lat < self.min_all_lat or lat > self.max_all_lat or lon < self.min_all_lon or lon > self.max_all_lon:
            return []
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
        if not n.location.valid():
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
        self.ways_scanned += 1
        tags = {t.k: t.v for t in w.tags}
        # Keep relevant golf and landscape layers, OR untagged ways (which may be relation members e.g. multipolygon fairways/greens)
        is_relevant = (
            not tags or
            "golf" in tags or
            tags.get("leisure") == "golf_course" or
            tags.get("natural") in ("water", "wood", "tree_row", "tree") or
            tags.get("landuse") == "forest"
        )
        if not is_relevant:
            return

        node_refs = []
        way_lats, way_lons = [], []
        first_checked = False
        for n in w.nodes:
            node_refs.append(n.ref)
            if n.location.valid():
                lat = n.lat
                lon = n.lon
                # Fast reject: if the first node is miles outside the overall region bounding box, skip entire way
                if not first_checked:
                    first_checked = True
                    if lat < (self.min_all_lat - 0.1) or lat > (self.max_all_lat + 0.1) or \
                       lon < (self.min_all_lon - 0.1) or lon > (self.max_all_lon + 0.1):
                        return
                way_lats.append(lat)
                way_lons.append(lon)

        if not way_lats:
            return

        avg_lat = sum(way_lats) / len(way_lats)
        avg_lon = sum(way_lons) / len(way_lons)

        matches = self._get_matching_courses(avg_lat, avg_lon)
        if not matches:
            return

        self.ways_matched += 1
        for c in matches:
            self.course_data[c["slug"]]["ways"].append({
                "type": "way",
                "id": w.id,
                "nodes": node_refs,
                "tags": tags
            })
            # Ensure all way nodes are recorded
            for n in w.nodes:
                if n.location.valid():
                    self.course_data[c["slug"]]["nodes"][n.ref] = {
                        "type": "node",
                        "id": n.ref,
                        "lat": n.lat,
                        "lon": n.lon,
                        "tags": {}
                    }

    def relation(self, r):
        self.relations_scanned += 1
        tags = {t.k: t.v for t in r.tags}
        # Keep relevant golf and landscape relations (multipolygons, course boundaries)
        is_relevant = (
            "golf" in tags or
            tags.get("leisure") == "golf_course" or
            tags.get("natural") in ("water", "wood", "tree_row", "tree") or
            tags.get("landuse") == "forest"
        )
        if not is_relevant:
            return

        members = []
        member_way_refs = set()
        for m in r.members:
            m_type = "way" if m.type == 'w' else ("node" if m.type == 'n' else "relation")
            members.append({
                "type": m_type,
                "ref": m.ref,
                "role": m.role
            })
            if m.type == 'w':
                member_way_refs.add(m.ref)

        rel_obj = {
            "type": "relation",
            "id": r.id,
            "members": members,
            "tags": tags
        }

        # Match relation to courses whose extracted ways include any of this relation's member ways
        matched_any = False
        for c in self.course_targets:
            slug = c["slug"]
            c_ways = self.course_data[slug]["ways"]
            if any(w["id"] in member_way_refs for w in c_ways):
                self.course_data[slug]["relations"].append(rel_obj)
                matched_any = True
        if matched_any:
            self.relations_matched += 1


def _worker_extract_pbf(
    pbf_path: str,
    cache_dir: str,
    max_courses: int,
    idx_type: str,
    temp_idx_file: str,
    results_file: str
):
    """Worker process: extracts courses and writes geometry packages.

    Runs in a dedicated process so that on Windows, osmium file mappings are fully
    released by the OS upon process exit, preventing WinError 32 locking.
    """
    os.makedirs(cache_dir, exist_ok=True)
    file_size_gb = (os.path.getsize(pbf_path) / (1024 * 1024 * 1024)) if os.path.exists(pbf_path) else 0.0

    # Configure adaptive node location indexing strategy
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

    log_timestamp(f"[Step 1/2] Scanning '{os.path.basename(pbf_path)}' for golf courses with osmium...")
    step1_start = time.time()

    m = osmium.index.create_map(actual_idx)
    lh = osmium.NodeLocationsForWays(m)
    lh.ignore_errors()

    id_handler = GolfCourseIdentifier()
    hb_step1 = StepHeartbeat(
        "[Step 1/2] Course Scan",
        interval=60.0
    ).set_counter(
        lambda: f"{id_handler.ways_scanned:,} ways scanned, {len(id_handler.courses):,} courses found"
    ).start()

    # Step 1: Stream nodes (populating location index m) and ways (identifying courses and bounding boxes)
    try:
        with osmium.io.Reader(pbf_path, osmium.osm.osm_entity_bits.NODE | osmium.osm.osm_entity_bits.WAY) as rd:
            osmium.apply(rd, lh, id_handler)
    finally:
        hb_step1.stop()

    step1_duration = time.time() - step1_start
    log_timestamp(f"[Step 1/2] Complete! Scanned {id_handler.ways_scanned:,} ways in {format_time(step1_duration)}.")

    identified = id_handler.courses

    # Deduplicate identified courses by slug and proximity
    unique_courses = {}
    for c in identified:
        slug = c["slug"]
        if slug not in unique_courses:
            unique_courses[slug] = c

    # Sort by primary (rating / PGA tour status) and secondary (most recently updated timestamp, hole count)
    all_unique = list(unique_courses.values())
    all_unique.sort(key=compute_course_priority, reverse=True)

    course_list = all_unique
    if max_courses > 0:
        candidate_limit = max(max_courses * 3, 5000)
        course_list = all_unique[:candidate_limit] if len(all_unique) > candidate_limit else all_unique

    pga_count = sum(1 for c in course_list if c.get("is_pga_tour"))
    rated_count = sum(1 for c in course_list if c.get("rating", 0) > 0 and not c.get("is_pga_tour"))
    log_timestamp(f"Identified {len(unique_courses)} total course(s). Selected {len(course_list)} prioritized courses "
                  f"({pga_count} PGA/Major venues, {rated_count} rated, remainder by latest updated date).")

    log_timestamp(f"[Step 2/2] Extracting feature geometries (ways) using pre-populated index...")
    step2_start = time.time()
    feat_handler = CourseFeatureExtractor(course_list)

    hb_step2 = StepHeartbeat(
        "[Step 2/2] Feature Geometry Extraction",
        interval=60.0
    ).set_counter(
        lambda: f"{feat_handler.ways_scanned:,} ways scanned ({feat_handler.ways_matched:,} matched), {feat_handler.relations_scanned:,} relations scanned ({feat_handler.relations_matched:,} matched)"
    ).start()

    # Step 2: Stream WAYS and RELATIONS using the pre-populated index m!
    # Does NOT re-populate the index, does NOT resize the index file on disk, avoiding ENOSPC errors.
    try:
        with osmium.io.Reader(pbf_path, osmium.osm.osm_entity_bits.WAY | osmium.osm.osm_entity_bits.RELATION) as rd:
            osmium.apply(rd, lh, feat_handler)
    finally:
        hb_step2.stop()

    step2_duration = time.time() - step2_start
    log_timestamp(f"[Step 2/2] Complete! Scanned {feat_handler.ways_scanned:,} ways & {feat_handler.relations_scanned:,} relations in {format_time(step2_duration)}.")

    # Attach standalone tagged nodes collected during Step 1
    if hasattr(id_handler, "tagged_nodes"):
        for tn in id_handler.tagged_nodes:
            matches = feat_handler._get_matching_courses(tn["lat"], tn["lon"])
            for c in matches:
                feat_handler.course_data[c["slug"]]["nodes"][tn["id"]] = tn

    generated_catalog_entries = []
    saved_count = 0
    excluded_count = 0
    exclusion_stats = {
        "no_ways": 0,
        "invalid_hole_count": 0,
        "missing_fairways": 0,
        "missing_tees": 0,
        "missing_greens": 0
    }

    for c in course_list:
        if max_courses > 0 and saved_count >= max_courses:
            break

        slug = c["slug"]
        data = feat_handler.course_data.get(slug)
        if not data or not data["ways"]:
            excluded_count += 1
            exclusion_stats["no_ways"] += 1
            continue

        # Prune untagged ways that are not referenced in any relation
        rel_way_refs = {m["ref"] for rel in data.get("relations", []) for m in rel.get("members", []) if m.get("type") == "way"}
        data["ways"] = [w for w in data["ways"] if w.get("tags") or w["id"] in rel_way_refs]

        # Validate course elements to ensure course meets search criteria and has required metadata
        is_valid, verified_holes, reason = validate_course_elements(data)
        if not is_valid:
            excluded_count += 1
            if "fairway" in reason:
                exclusion_stats["missing_fairways"] += 1
            elif "tee" in reason:
                exclusion_stats["missing_tees"] += 1
            elif "green" in reason:
                exclusion_stats["missing_greens"] += 1
            else:
                exclusion_stats["invalid_hole_count"] += 1
            continue

        elements = list(data["nodes"].values()) + data["ways"] + data.get("relations", [])
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

        catalog_entry = {
            "name": c["name"],
            "lat": round(c["lat"], 6),
            "lon": round(c["lon"], 6),
            "location": c["location"],
            "hole_count": verified_holes,
            "last_updated": c["last_updated"]
        }
        if c.get("is_pga_tour"):
            catalog_entry["is_pga_tour"] = True
        if c.get("rating", 0.0) > 0.0:
            catalog_entry["rating"] = round(float(c["rating"]), 1)

        generated_catalog_entries.append(catalog_entry)
        saved_count += 1

    log_timestamp(f"Extraction complete: {saved_count} valid course(s) generated, {excluded_count} invalid course(s) excluded "
                  f"(invalid hole count: {exclusion_stats['invalid_hole_count']}, missing fairways: {exclusion_stats['missing_fairways']}, "
                  f"missing tees: {exclusion_stats['missing_tees']}, missing greens: {exclusion_stats['missing_greens']}, "
                  f"no features: {exclusion_stats['no_ways']}).")
    with open(results_file, "w", encoding="utf-8") as f:
        json.dump(generated_catalog_entries, f)


def process_pbf_file(
    pbf_path: str,
    cache_dir: str,
    max_courses: int = 2500,
    idx_type: str = "auto",
    temp_dir: str = None
) -> list:
    """Extract golf courses from a PBF file and write compressed vector geometries.

    Executes in a dedicated worker subprocess so memory-mapped file handles
    are cleanly dropped by Windows on completion, preventing WinError 32 lockup.
    """
    if not temp_dir:
        temp_dir = os.path.dirname(pbf_path)
    os.makedirs(temp_dir, exist_ok=True)
    os.makedirs(cache_dir, exist_ok=True)

    uid = uuid.uuid4().hex[:8]
    temp_idx_file = os.path.join(temp_dir, f"_osmium_node_idx_{uid}.dat")
    results_file = os.path.join(temp_dir, f"_osmium_results_{uid}.json")

    cmd = [
        sys.executable,
        os.path.abspath(__file__),
        "--worker-extract",
        "--worker-pbf", os.path.abspath(pbf_path),
        "--worker-cache-dir", os.path.abspath(cache_dir),
        "--worker-max-courses", str(max_courses),
        "--worker-idx-type", str(idx_type),
        "--worker-temp-idx", os.path.abspath(temp_idx_file),
        "--worker-results-file", os.path.abspath(results_file)
    ]

    try:
        proc = subprocess.run(cmd)
        if proc.returncode != 0:
            raise RuntimeError(f"OSM extraction worker failed with exit code {proc.returncode}")

        if not os.path.exists(results_file):
            raise RuntimeError(f"OSM extraction worker completed but results file not found: {results_file}")

        with open(results_file, "r", encoding="utf-8") as f:
            catalog_entries = json.load(f)
        return catalog_entries

    finally:
        # Worker subprocess has terminated, so OS has closed all file mappings.
        if os.path.exists(temp_idx_file):
            try:
                os.remove(temp_idx_file)
                print(f"Cleaned up temporary node location index: {temp_idx_file}")
            except Exception as e:
                print(f"Notice: Could not remove temporary index file {temp_idx_file}: {e}")

        if os.path.exists(results_file):
            try:
                os.remove(results_file)
            except Exception:
                pass


def cleanup_osm_temp_files(directories: list, clean_all_pbfs: bool = False):
    """Find and remove leftover temporary index files (_osmium_node_idx_*.dat) and stale artifacts."""
    for d in set(directories):
        if not d or not os.path.exists(d):
            continue
        try:
            for item in os.listdir(d):
                p = os.path.join(d, item)
                if (item.startswith("_osmium_node_idx_") and item.endswith(".dat")) or \
                   (item.startswith("_osmium_results_") and item.endswith(".json")):
                    try:
                        os.remove(p)
                        print(f"Cleaned up orphaned temporary file: {p}")
                    except Exception:
                        pass
                elif clean_all_pbfs and item.endswith(".osm.pbf"):
                    try:
                        os.remove(p)
                        print(f"Cleaned up extract: {p}")
                    except Exception:
                        pass
        except Exception:
            pass


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
            # Update hole count, date, PGA status, or rating if newly available
            if entry.get("hole_count", 0) > 0:
                merged[key]["hole_count"] = entry["hole_count"]
            if entry.get("last_updated"):
                merged[key]["last_updated"] = entry["last_updated"]
            if entry.get("is_pga_tour"):
                merged[key]["is_pga_tour"] = True
            if entry.get("rating", 0.0) > 0.0:
                merged[key]["rating"] = max(merged[key].get("rating", 0.0), entry["rating"])

    for c in merged.values():
        if not c.get("is_pga_tour"):
            clean_name = " " + re.sub(r'[^a-z0-9]+', ' ', c["name"].lower()).strip() + " "
            if any(f" {kw} " in clean_name or clean_name.strip() == kw for kw in PGA_TOUR_AND_MAJOR_COURSES):
                c["is_pga_tour"] = True

    final_list = sorted(merged.values(), key=lambda x: (not bool(x.get("is_pga_tour", False)), x["name"].lower()))
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
    print(f"Auto-Clean Disk    : {'Enabled (reclaims PBF and index files immediately)' if clean else 'Disabled'}")
    print("=" * 70)

    # Initial cleanup to reclaim any disk space from previously aborted runs
    cleanup_osm_temp_files([download_dir, temp_dir])

    all_catalog_entries = []

    total_regions = len(regions)
    try:
        for idx_reg, reg in enumerate(regions, start=1):
            url = GEOFABRIK_REGIONS.get(reg.lower())
            if not url:
                print(f"[{idx_reg}/{total_regions}] Unknown region '{reg}'. Supported: {', '.join(GEOFABRIK_REGIONS.keys())}")
                continue

            pbf_filename = f"{reg}-latest.osm.pbf"
            pbf_path = os.path.join(download_dir, pbf_filename)

            pct = (idx_reg / total_regions) * 100.0
            print(f"\n" + "=" * 70)
            print(f"[{idx_reg}/{total_regions}] ({pct:.1f}% Complete) >>> Processing Region: {reg.upper()} <<<")
            print("=" * 70)
            free_bytes = shutil.disk_usage(download_dir).free
            free_gb = free_bytes / (1024 * 1024 * 1024)
            print(f"Available Disk Space: {free_gb:.1f} GB")

            try:
                if not skip_download or not os.path.exists(pbf_path):
                    print(f"[{idx_reg}/{total_regions}] Downloading ({reg}):\n  {url}")
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

            finally:
                if clean and os.path.exists(pbf_path):
                    print(f"Cleaning up {pbf_path} to reclaim disk space...")
                    try:
                        os.remove(pbf_path)
                    except Exception as e:
                        print(f"Notice: Could not remove {pbf_path}: {e}")

        if all_catalog_entries:
            update_global_catalog(all_catalog_entries, catalog_path)

        print("\n" + "=" * 70)
        print("Monthly OpenStreetMap sync complete! Enjoy fast, offline course play.")
        print("=" * 70)

    finally:
        # Final cleanup of any lingering temporary index files
        cleanup_osm_temp_files([download_dir, temp_dir])


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
    parser.add_argument(
        "--worker-extract",
        action="store_true",
        help=argparse.SUPPRESS
    )
    parser.add_argument(
        "--worker-pbf",
        default="",
        help=argparse.SUPPRESS
    )
    parser.add_argument(
        "--worker-cache-dir",
        default="",
        help=argparse.SUPPRESS
    )
    parser.add_argument(
        "--worker-max-courses",
        type=int,
        default=2500,
        help=argparse.SUPPRESS
    )
    parser.add_argument(
        "--worker-idx-type",
        default="auto",
        help=argparse.SUPPRESS
    )
    parser.add_argument(
        "--worker-temp-idx",
        default="",
        help=argparse.SUPPRESS
    )
    parser.add_argument(
        "--worker-results-file",
        default="",
        help=argparse.SUPPRESS
    )

    args = parser.parse_args()

    # If launched as an isolated extraction worker subprocess, execute and exit immediately
    if args.worker_extract:
        _worker_extract_pbf(
            pbf_path=args.worker_pbf,
            cache_dir=args.worker_cache_dir,
            max_courses=args.worker_max_courses,
            idx_type=args.worker_idx_type,
            temp_idx_file=args.worker_temp_idx,
            results_file=args.worker_results_file
        )
        sys.exit(0)

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
