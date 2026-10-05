"""
Golf Course Catalog Generator & Updater for HeckleGolfSim.

Generates the bundled offline course catalog at res://Courses/Catalog/golf_courses.json.
This catalog allows players to search and select golf courses instantly without hitting
external geocoding (Photon/Nominatim) or Overpass APIs, preventing rate-limiting and bans.
"""

import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
CATALOG_PATH = os.path.join(PROJECT_ROOT, "Courses", "Catalog", "golf_courses.json")

# Curated catalog of iconic, championship, and popular golf courses worldwide
# Each entry contains: name, lat, lon, location, hole_count, last_updated
DEFAULT_COURSES = [
    # California, USA
    {"name": "Pebble Beach Golf Links", "lat": 36.5688, "lon": -121.9507, "location": "Pebble Beach, California, United States", "hole_count": 18, "last_updated": "2024-01-15"},
    {"name": "Spyglass Hill Golf Course", "lat": 36.5856, "lon": -121.9610, "location": "Pebble Beach, California, United States", "hole_count": 18, "last_updated": "2024-01-15"},
    {"name": "The Links at Spanish Bay", "lat": 36.6186, "lon": -121.9517, "location": "Pebble Beach, California, United States", "hole_count": 18, "last_updated": "2024-01-15"},
    {"name": "Torrey Pines Golf Course (South)", "lat": 32.8986, "lon": -117.2514, "location": "La Jolla, San Diego, California, United States", "hole_count": 18, "last_updated": "2024-02-10"},
    {"name": "Torrey Pines Golf Course (North)", "lat": 32.9056, "lon": -117.2486, "location": "La Jolla, San Diego, California, United States", "hole_count": 18, "last_updated": "2024-02-10"},
    {"name": "Airways Golf Club", "lat": 36.7644, "lon": -119.7188, "location": "Fresno, California, United States", "hole_count": 18, "last_updated": "2024-01-01"},
    {"name": "Dragonfly Golf Club", "lat": 36.9427, "lon": -119.8661, "location": "Madera, California, United States", "hole_count": 18, "last_updated": "2024-01-01"},
    {"name": "Riviera Country Club", "lat": 34.0500, "lon": -118.5028, "location": "Pacific Palisades, Los Angeles, California, United States", "hole_count": 18, "last_updated": "2024-03-01"},
    {"name": "The Olympic Club (Lake Course)", "lat": 37.7083, "lon": -122.4939, "location": "San Francisco, California, United States", "hole_count": 18, "last_updated": "2024-01-20"},
    {"name": "Presidio Golf Course", "lat": 37.7889, "lon": -122.4639, "location": "San Francisco, California, United States", "hole_count": 18, "last_updated": "2024-01-10"},
    {"name": "Harding Park Golf Course (TPC Harding Park)", "lat": 37.7247, "lon": -122.4933, "location": "San Francisco, California, United States", "hole_count": 18, "last_updated": "2024-02-01"},
    {"name": "Pasatiempo Golf Club", "lat": 36.9972, "lon": -122.0319, "location": "Santa Cruz, California, United States", "hole_count": 18, "last_updated": "2024-01-25"},
    {"name": "Cypress Point Club", "lat": 36.5772, "lon": -121.9753, "location": "Pebble Beach, California, United States", "hole_count": 18, "last_updated": "2024-01-15"},
    {"name": "PGA West (Stadium Course)", "lat": 33.6425, "lon": -116.2731, "location": "La Quinta, California, United States", "hole_count": 18, "last_updated": "2024-01-18"},
    {"name": "Silverado Resort (North Course)", "lat": 38.3517, "lon": -122.2611, "location": "Napa, California, United States", "hole_count": 18, "last_updated": "2024-02-12"},
    {"name": "Half Moon Bay Golf Links (Old Course)", "lat": 37.4339, "lon": -122.4411, "location": "Half Moon Bay, California, United States", "hole_count": 18, "last_updated": "2024-01-22"},
    {"name": "Half Moon Bay Golf Links (Ocean Course)", "lat": 37.4308, "lon": -122.4389, "location": "Half Moon Bay, California, United States", "hole_count": 18, "last_updated": "2024-01-22"},

    # Georgia, USA
    {"name": "Augusta National Golf Club", "lat": 33.5022, "lon": -82.0225, "location": "Augusta, Georgia, United States", "hole_count": 18, "last_updated": "2024-04-01"},
    {"name": "East Lake Golf Club", "lat": 33.7431, "lon": -84.3039, "location": "Atlanta, Georgia, United States", "hole_count": 18, "last_updated": "2024-03-15"},
    {"name": "Sea Island Golf Club (Seaside Course)", "lat": 31.1394, "lon": -81.4089, "location": "St. Simons Island, Georgia, United States", "hole_count": 18, "last_updated": "2024-01-30"},

    # North Carolina, USA
    {"name": "Pinehurst Resort (No. 2)", "lat": 35.1897, "lon": -79.4678, "location": "Pinehurst, North Carolina, United States", "hole_count": 18, "last_updated": "2024-06-01"},
    {"name": "Pinehurst Resort (No. 4)", "lat": 35.1869, "lon": -79.4719, "location": "Pinehurst, North Carolina, United States", "hole_count": 18, "last_updated": "2024-06-01"},
    {"name": "Quail Hollow Club", "lat": 35.1092, "lon": -80.8406, "location": "Charlotte, North Carolina, United States", "hole_count": 18, "last_updated": "2024-05-01"},
    {"name": "Pine Needles Lodge & Golf Club", "lat": 35.2036, "lon": -79.4131, "location": "Southern Pines, North Carolina, United States", "hole_count": 18, "last_updated": "2024-02-15"},

    # Florida, USA
    {"name": "TPC Sawgrass (The Players Stadium)", "lat": 30.1983, "lon": -81.3939, "location": "Ponte Vedra Beach, Florida, United States", "hole_count": 18, "last_updated": "2024-03-10"},
    {"name": "TPC Sawgrass (Dye's Valley Course)", "lat": 30.1950, "lon": -81.3889, "location": "Ponte Vedra Beach, Florida, United States", "hole_count": 18, "last_updated": "2024-03-10"},
    {"name": "Bay Hill Club and Lodge", "lat": 28.4578, "lon": -81.5108, "location": "Orlando, Florida, United States", "hole_count": 18, "last_updated": "2024-03-01"},
    {"name": "PGA National Resort (Champion Course)", "lat": 26.8286, "lon": -80.1444, "location": "Palm Beach Gardens, Florida, United States", "hole_count": 18, "last_updated": "2024-02-20"},
    {"name": "Streamsong Resort (Red Course)", "lat": 27.6978, "lon": -81.9339, "location": "Bowling Green, Florida, United States", "hole_count": 18, "last_updated": "2024-01-20"},
    {"name": "Streamsong Resort (Blue Course)", "lat": 27.7011, "lon": -81.9372, "location": "Bowling Green, Florida, United States", "hole_count": 18, "last_updated": "2024-01-20"},
    {"name": "Streamsong Resort (Black Course)", "lat": 27.6894, "lon": -81.9483, "location": "Bowling Green, Florida, United States", "hole_count": 18, "last_updated": "2024-01-20"},
    {"name": "Innisbrook Resort (Copperhead Course)", "lat": 28.1136, "lon": -82.7561, "location": "Palm Harbor, Florida, United States", "hole_count": 18, "last_updated": "2024-03-05"},

    # New York, USA
    {"name": "Bethpage State Park (Black Course)", "lat": 40.7444, "lon": -73.4561, "location": "Farmingdale, New York, United States", "hole_count": 18, "last_updated": "2024-05-15"},
    {"name": "Bethpage State Park (Red Course)", "lat": 40.7417, "lon": -73.4597, "location": "Farmingdale, New York, United States", "hole_count": 18, "last_updated": "2024-05-15"},
    {"name": "Bethpage State Park (Blue Course)", "lat": 40.7500, "lon": -73.4639, "location": "Farmingdale, New York, United States", "hole_count": 18, "last_updated": "2024-05-15"},
    {"name": "Bethpage State Park (Green Course)", "lat": 40.7472, "lon": -73.4528, "location": "Farmingdale, New York, United States", "hole_count": 18, "last_updated": "2024-05-15"},
    {"name": "Bethpage State Park (Yellow Course)", "lat": 40.7528, "lon": -73.4583, "location": "Farmingdale, New York, United States", "hole_count": 18, "last_updated": "2024-05-15"},
    {"name": "Shinnecock Hills Golf Club", "lat": 40.8925, "lon": -72.4397, "location": "Southampton, New York, United States", "hole_count": 18, "last_updated": "2024-04-10"},
    {"name": "National Golf Links of America", "lat": 40.9083, "lon": -72.4472, "location": "Southampton, New York, United States", "hole_count": 18, "last_updated": "2024-04-10"},
    {"name": "Winged Foot Golf Club (West Course)", "lat": 40.9575, "lon": -73.7547, "location": "Mamaroneck, New York, United States", "hole_count": 18, "last_updated": "2024-03-25"},
    {"name": "Oak Hill Country Club (East Course)", "lat": 43.1097, "lon": -77.5333, "location": "Rochester, New York, United States", "hole_count": 18, "last_updated": "2024-05-20"},

    # Wisconsin, USA
    {"name": "Whistling Straits (Straits Course)", "lat": 43.8508, "lon": -87.7347, "location": "Sheboygan, Wisconsin, United States", "hole_count": 18, "last_updated": "2024-06-15"},
    {"name": "Whistling Straits (Irish Course)", "lat": 43.8458, "lon": -87.7389, "location": "Sheboygan, Wisconsin, United States", "hole_count": 18, "last_updated": "2024-06-15"},
    {"name": "Blackwolf Run (River Course)", "lat": 43.7317, "lon": -87.7761, "location": "Kohler, Wisconsin, United States", "hole_count": 18, "last_updated": "2024-06-10"},
    {"name": "Erin Hills Golf Course", "lat": 43.2508, "lon": -88.4239, "location": "Erin, Wisconsin, United States", "hole_count": 18, "last_updated": "2024-06-05"},
    {"name": "Sand Valley Golf Resort (Sand Valley)", "lat": 44.2081, "lon": -89.8731, "location": "Nekoosa, Wisconsin, United States", "hole_count": 18, "last_updated": "2024-06-01"},
    {"name": "Sand Valley Golf Resort (Mammoth Dunes)", "lat": 44.2125, "lon": -89.8803, "location": "Nekoosa, Wisconsin, United States", "hole_count": 18, "last_updated": "2024-06-01"},
    {"name": "The Sandbox at Sand Valley", "lat": 44.2056, "lon": -89.8711, "location": "Nekoosa, Wisconsin, United States", "hole_count": 17, "last_updated": "2024-06-01"},

    # Oregon, USA
    {"name": "Bandon Dunes Golf Resort (Bandon Dunes)", "lat": 43.1906, "lon": -124.3986, "location": "Bandon, Oregon, United States", "hole_count": 18, "last_updated": "2024-05-01"},
    {"name": "Bandon Dunes Golf Resort (Pacific Dunes)", "lat": 43.2017, "lon": -124.3958, "location": "Bandon, Oregon, United States", "hole_count": 18, "last_updated": "2024-05-01"},
    {"name": "Bandon Dunes Golf Resort (Bandon Trails)", "lat": 43.1869, "lon": -124.3889, "location": "Bandon, Oregon, United States", "hole_count": 18, "last_updated": "2024-05-01"},
    {"name": "Bandon Dunes Golf Resort (Old Macdonald)", "lat": 43.2117, "lon": -124.3917, "location": "Bandon, Oregon, United States", "hole_count": 18, "last_updated": "2024-05-01"},
    {"name": "Bandon Dunes Golf Resort (Sheep Ranch)", "lat": 43.2267, "lon": -124.4014, "location": "Bandon, Oregon, United States", "hole_count": 18, "last_updated": "2024-05-01"},
    {"name": "Bandon Preserve", "lat": 43.1894, "lon": -124.3944, "location": "Bandon, Oregon, United States", "hole_count": 13, "last_updated": "2024-05-01"},

    # Arizona, USA
    {"name": "TPC Scottsdale (Stadium Course)", "lat": 33.6406, "lon": -111.9103, "location": "Scottsdale, Arizona, United States", "hole_count": 18, "last_updated": "2024-02-05"},
    {"name": "TPC Scottsdale (Champions Course)", "lat": 33.6469, "lon": -111.9056, "location": "Scottsdale, Arizona, United States", "hole_count": 18, "last_updated": "2024-02-05"},
    {"name": "Troon North Golf Club (Monument Course)", "lat": 33.7389, "lon": -111.8542, "location": "Scottsdale, Arizona, United States", "hole_count": 18, "last_updated": "2024-01-20"},
    {"name": "Grayhawk Golf Club (Raptor Course)", "lat": 33.6806, "lon": -111.9139, "location": "Scottsdale, Arizona, United States", "hole_count": 18, "last_updated": "2024-01-18"},
    {"name": "We-Ko-Pa Golf Club (Saguaro Course)", "lat": 33.6069, "lon": -111.6961, "location": "Fort McDowell, Arizona, United States", "hole_count": 18, "last_updated": "2024-01-22"},

    # Washington, USA
    {"name": "Chambers Bay", "lat": 47.2039, "lon": -122.5769, "location": "University Place, Washington, United States", "hole_count": 18, "last_updated": "2024-05-25"},
    {"name": "Gamble Sands", "lat": 48.0933, "lon": -119.6806, "location": "Brewster, Washington, United States", "hole_count": 18, "last_updated": "2024-05-10"},

    # Pennsylvania, USA
    {"name": "Oakmont Country Club", "lat": 40.5258, "lon": -79.8267, "location": "Oakmont, Pennsylvania, United States", "hole_count": 18, "last_updated": "2024-05-30"},
    {"name": "Merion Golf Club (East Course)", "lat": 40.0000, "lon": -75.3117, "location": "Ardmore, Pennsylvania, United States", "hole_count": 18, "last_updated": "2024-04-18"},

    # New Jersey, USA
    {"name": "Baltusrol Golf Club (Lower Course)", "lat": 40.7061, "lon": -74.3317, "location": "Springfield, New Jersey, United States", "hole_count": 18, "last_updated": "2024-04-22"},
    {"name": "Pine Valley Golf Club", "lat": 39.7892, "lon": -74.9708, "location": "Pine Valley, New Jersey, United States", "hole_count": 18, "last_updated": "2024-04-15"},

    # Illinois, USA
    {"name": "Medinah Country Club (Course No. 3)", "lat": 41.9708, "lon": -88.0489, "location": "Medinah, Illinois, United States", "hole_count": 18, "last_updated": "2024-05-12"},
    {"name": "Cog Hill Golf & Country Club (Dubsdread)", "lat": 41.6708, "lon": -87.9422, "location": "Lemont, Illinois, United States", "hole_count": 18, "last_updated": "2024-05-08"},

    # Oklahoma & Texas, USA
    {"name": "Southern Hills Country Club", "lat": 36.0717, "lon": -95.9406, "location": "Tulsa, Oklahoma, United States", "hole_count": 18, "last_updated": "2024-05-18"},
    {"name": "Colonial Country Club", "lat": 32.7161, "lon": -97.3756, "location": "Fort Worth, Texas, United States", "hole_count": 18, "last_updated": "2024-05-22"},
    {"name": "TPC Craig Ranch", "lat": 33.1539, "lon": -96.7028, "location": "McKinney, Texas, United States", "hole_count": 18, "last_updated": "2024-05-02"},

    # Scotland, UK
    {"name": "St Andrews Links (Old Course)", "lat": 56.3431, "lon": -2.8027, "location": "St Andrews, Fife, Scotland, United Kingdom", "hole_count": 18, "last_updated": "2024-07-10"},
    {"name": "St Andrews Links (New Course)", "lat": 56.3486, "lon": -2.8067, "location": "St Andrews, Fife, Scotland, United Kingdom", "hole_count": 18, "last_updated": "2024-07-10"},
    {"name": "St Andrews Links (Jubilee Course)", "lat": 56.3536, "lon": -2.8089, "location": "St Andrews, Fife, Scotland, United Kingdom", "hole_count": 18, "last_updated": "2024-07-10"},
    {"name": "St Andrews Links (Castle Course)", "lat": 56.3314, "lon": -2.7533, "location": "St Andrews, Fife, Scotland, United Kingdom", "hole_count": 18, "last_updated": "2024-07-10"},
    {"name": "St Andrews Links (Eden Course)", "lat": 56.3481, "lon": -2.8228, "location": "St Andrews, Fife, Scotland, United Kingdom", "hole_count": 18, "last_updated": "2024-07-10"},
    {"name": "St Andrews Links (Strathtyrum Course)", "lat": 56.3444, "lon": -2.8272, "location": "St Andrews, Fife, Scotland, United Kingdom", "hole_count": 18, "last_updated": "2024-07-10"},
    {"name": "St Andrews Links (Balgove Course)", "lat": 56.3456, "lon": -2.8206, "location": "St Andrews, Fife, Scotland, United Kingdom", "hole_count": 9, "last_updated": "2024-07-10"},
    {"name": "Carnoustie Golf Links (Championship Course)", "lat": 56.4975, "lon": -2.7161, "location": "Carnoustie, Angus, Scotland, United Kingdom", "hole_count": 18, "last_updated": "2024-07-15"},
    {"name": "Royal Troon Golf Club (Old Course)", "lat": 55.5306, "lon": -4.6467, "location": "Troon, South Ayrshire, Scotland, United Kingdom", "hole_count": 18, "last_updated": "2024-07-20"},
    {"name": "Turnberry (Ailsa Course)", "lat": 55.3161, "lon": -4.8394, "location": "Turnberry, South Ayrshire, Scotland, United Kingdom", "hole_count": 18, "last_updated": "2024-07-05"},
    {"name": "Muirfield (The Honourable Company of Edinburgh Golfers)", "lat": 56.0425, "lon": -2.8217, "location": "Gullane, East Lothian, Scotland, United Kingdom", "hole_count": 18, "last_updated": "2024-06-25"},
    {"name": "North Berwick Golf Club (West Links)", "lat": 56.0594, "lon": -2.7297, "location": "North Berwick, East Lothian, Scotland, United Kingdom", "hole_count": 18, "last_updated": "2024-06-20"},
    {"name": "Royal Dornoch Golf Club (Championship Course)", "lat": 57.8825, "lon": -4.0267, "location": "Dornoch, Sutherland, Scotland, United Kingdom", "hole_count": 18, "last_updated": "2024-06-18"},
    {"name": "Castle Stuart Golf Links (Cabot Highlands)", "lat": 57.5147, "lon": -4.1039, "location": "Inverness, Highland, Scotland, United Kingdom", "hole_count": 18, "last_updated": "2024-06-15"},
    {"name": "Gleneagles (King's Course)", "lat": 56.2847, "lon": -3.7556, "location": "Auchterarder, Perth and Kinross, Scotland, United Kingdom", "hole_count": 18, "last_updated": "2024-06-12"},
    {"name": "Gleneagles (PGA Centenary Course)", "lat": 56.2883, "lon": -3.7431, "location": "Auchterarder, Perth and Kinross, Scotland, United Kingdom", "hole_count": 18, "last_updated": "2024-06-12"},

    # England, UK
    {"name": "Royal Birkdale Golf Club", "lat": 53.6219, "lon": -3.0361, "location": "Southport, Merseyside, England, United Kingdom", "hole_count": 18, "last_updated": "2024-07-08"},
    {"name": "Royal Lytham & St Annes Golf Club", "lat": 53.7444, "lon": -3.0239, "location": "Lytham St Annes, Lancashire, England, United Kingdom", "hole_count": 18, "last_updated": "2024-07-06"},
    {"name": "Royal Liverpool Golf Club (Hoylake)", "lat": 53.3933, "lon": -3.1867, "location": "Hoylake, Merseyside, England, United Kingdom", "hole_count": 18, "last_updated": "2024-07-02"},
    {"name": "Royal St George's Golf Club", "lat": 51.2758, "lon": 1.3653, "location": "Sandwich, Kent, England, United Kingdom", "hole_count": 18, "last_updated": "2024-07-01"},
    {"name": "Sunmessage Dale Golf Club (Old Course)", "lat": 51.3789, "lon": -0.6389, "location": "Sunningdale, Berkshire, England, United Kingdom", "hole_count": 18, "last_updated": "2024-06-10"},
    {"name": "Wentworth Club (West Course)", "lat": 51.3986, "lon": -0.5969, "location": "Virginia Water, Surrey, England, United Kingdom", "hole_count": 18, "last_updated": "2024-09-01"},
    {"name": "The Belfry (Brabazon Course)", "lat": 52.5539, "lon": -1.7583, "location": "Wishaw, Warwickshire, England, United Kingdom", "hole_count": 18, "last_updated": "2024-08-15"},

    # Ireland & Northern Ireland
    {"name": "Royal County Down Golf Club (Championship Links)", "lat": 54.2181, "lon": -5.8789, "location": "Newcastle, County Down, Northern Ireland, United Kingdom", "hole_count": 18, "last_updated": "2024-07-12"},
    {"name": "Royal Portrush Golf Club (Dunluce Links)", "lat": 55.1983, "lon": -6.6389, "location": "Portrush, County Antrim, Northern Ireland, United Kingdom", "hole_count": 18, "last_updated": "2024-07-14"},
    {"name": "Lahinch Golf Club (Old Course)", "lat": 52.9347, "lon": -9.3494, "location": "Lahinch, County Clare, Ireland", "hole_count": 18, "last_updated": "2024-06-18"},
    {"name": "Ballybunion Golf Club (Old Course)", "lat": 52.5186, "lon": -9.6739, "location": "Ballybunion, County Kerry, Ireland", "hole_count": 18, "last_updated": "2024-06-22"},
    {"name": "Portmarnock Golf Club", "lat": 53.4144, "lon": -6.1133, "location": "Portmarnock, County Dublin, Ireland", "hole_count": 18, "last_updated": "2024-06-15"},
    {"name": "The K Club (Palmer Ryder Cup Course)", "lat": 53.3089, "lon": -6.6319, "location": "Straffan, County Kildare, Ireland", "hole_count": 18, "last_updated": "2024-06-08"},
    {"name": "Waterville Golf Links", "lat": 51.8286, "lon": -10.1839, "location": "Waterville, County Kerry, Ireland", "hole_count": 18, "last_updated": "2024-06-20"},

    # Canada
    {"name": "Cabot Cliffs", "lat": 46.2239, "lon": -61.2986, "location": "Inverness, Nova Scotia, Canada", "hole_count": 18, "last_updated": "2024-06-30"},
    {"name": "Cabot Links", "lat": 46.2361, "lon": -61.3097, "location": "Inverness, Nova Scotia, Canada", "hole_count": 18, "last_updated": "2024-06-30"},
    {"name": "Banff Springs Golf Course", "lat": 51.1639, "lon": -115.5583, "location": "Banff, Alberta, Canada", "hole_count": 18, "last_updated": "2024-06-20"},
    {"name": "Jasper Park Lodge Golf Club", "lat": 52.8806, "lon": -118.0583, "location": "Jasper, Alberta, Canada", "hole_count": 18, "last_updated": "2024-06-20"},
    {"name": "St. George's Golf and Country Club", "lat": 43.6769, "lon": -79.5317, "location": "Etobicoke, Toronto, Ontario, Canada", "hole_count": 18, "last_updated": "2024-06-10"},
    {"name": "Hamilton Golf and Country Club", "lat": 43.2278, "lon": -79.9722, "location": "Ancaster, Ontario, Canada", "hole_count": 18, "last_updated": "2024-06-05"},
    {"name": "Glen Abbey Golf Club", "lat": 43.4472, "lon": -79.7222, "location": "Oakville, Ontario, Canada", "hole_count": 18, "last_updated": "2024-06-12"},

    # Australia & New Zealand
    {"name": "Royal Melbourne Golf Club (West Course)", "lat": -37.9731, "lon": 145.0239, "location": "Black Rock, Victoria, Australia", "hole_count": 18, "last_updated": "2024-03-01"},
    {"name": "Royal Melbourne Golf Club (East Course)", "lat": -37.9767, "lon": 145.0289, "location": "Black Rock, Victoria, Australia", "hole_count": 18, "last_updated": "2024-03-01"},
    {"name": "Kingston Heath Golf Club", "lat": -37.9625, "lon": 145.0767, "location": "Cheltenham, Victoria, Australia", "hole_count": 18, "last_updated": "2024-03-05"},
    {"name": "Victoria Golf Club", "lat": -37.9719, "lon": 145.0506, "location": "Cheltenham, Victoria, Australia", "hole_count": 18, "last_updated": "2024-03-02"},
    {"name": "New South Wales Golf Club", "lat": -33.9878, "lon": 151.2472, "location": "La Perouse, Sydney, New South Wales, Australia", "hole_count": 18, "last_updated": "2024-02-28"},
    {"name": "Cape Wickham Golf Links", "lat": -39.5856, "lon": 143.9483, "location": "King Island, Tasmania, Australia", "hole_count": 18, "last_updated": "2024-02-15"},
    {"name": "Barnbougle Dunes", "lat": -40.9708, "lon": 147.3878, "location": "Bridport, Tasmania, Australia", "hole_count": 18, "last_updated": "2024-02-18"},
    {"name": "Barnbougle Lost Farm", "lat": -40.9739, "lon": 147.4089, "location": "Bridport, Tasmania, Australia", "hole_count": 20, "last_updated": "2024-02-18"},
    {"name": "Cape Kidnappers Golf Course", "lat": -39.6456, "lon": 177.0867, "location": "Te Awanga, Hawke's Bay, New Zealand", "hole_count": 18, "last_updated": "2024-01-20"},
    {"name": "Kauri Cliffs", "lat": -35.0089, "lon": 173.8967, "location": "Matauri Bay, Northland, New Zealand", "hole_count": 18, "last_updated": "2024-01-22"},
    {"name": "Tara Iti Golf Club", "lat": -36.2167, "lon": 174.6722, "location": "Mangawhai, Northland, New Zealand", "hole_count": 18, "last_updated": "2024-01-25"},

    # Continental Europe
    {"name": "Le Golf National (Albatros Course)", "lat": 48.7533, "lon": 2.0733, "location": "Guyancourt, Île-de-France, France", "hole_count": 18, "last_updated": "2024-08-01"},
    {"name": "Morfontaine Golf Club", "lat": 49.1417, "lon": 2.6056, "location": "Morfontaine, Oise, France", "hole_count": 18, "last_updated": "2024-07-20"},
    {"name": "Real Club Valderrama", "lat": 36.2942, "lon": -5.3253, "location": "Sotogrande, San Roque, Andalusia, Spain", "hole_count": 18, "last_updated": "2024-07-15"},
    {"name": "PGA Catalunya Golf and Wellness (Stadium Course)", "lat": 41.8703, "lon": 2.7583, "location": "Caldes de Malavella, Girona, Catalonia, Spain", "hole_count": 18, "last_updated": "2024-06-25"},
    {"name": "Real Club de Golf Sotogrande", "lat": 36.2817, "lon": -5.2894, "location": "Sotogrande, Andalusia, Spain", "hole_count": 18, "last_updated": "2024-06-20"},
    {"name": "Marco Simone Golf & Country Club", "lat": 41.9619, "lon": 12.6306, "location": "Guidonia Montecelio, Rome, Lazio, Italy", "hole_count": 18, "last_updated": "2024-05-15"},
    {"name": "Golf Club Villa d'Este", "lat": 45.7861, "lon": 9.1556, "location": "Montorfano, Como, Lombardy, Italy", "hole_count": 18, "last_updated": "2024-05-10"},
    {"name": "Golf Club Gut Larchenhof", "lat": 51.0472, "lon": 6.8194, "location": "Pulheim, North Rhine-Westphalia, Germany", "hole_count": 18, "last_updated": "2024-06-15"},
    {"name": "Utrechtse Golfclub 'de Pan'", "lat": 52.1278, "lon": 5.2472, "location": "Bosch en Duin, Utrecht, Netherlands", "hole_count": 18, "last_updated": "2024-06-01"},
    {"name": "The Royal Melbourne Golf Club of Belgium (Royal Zoute)", "lat": 51.3472, "lon": 3.2972, "location": "Knokke-Heist, West Flanders, Belgium", "hole_count": 18, "last_updated": "2024-06-05"},

    # Japan & Asia
    {"name": "Hirono Golf Club", "lat": 34.7733, "lon": 135.0089, "location": "Miki, Hyogo Prefecture, Japan", "hole_count": 18, "last_updated": "2024-04-10"},
    {"name": "Kawana Hotel Golf Course (Fuji Course)", "lat": 34.9389, "lon": 139.1361, "location": "Ito, Shizuoka Prefecture, Japan", "hole_count": 18, "last_updated": "2024-04-15"},
    {"name": "Kasumigaseki Country Club (East Course)", "lat": 35.9083, "lon": 139.4000, "location": "Kawagoe, Saitama Prefecture, Japan", "hole_count": 18, "last_updated": "2024-04-20"},
    {"name": "Naruo Golf Club", "lat": 34.8861, "lon": 135.3472, "location": "Kawanishi, Hyogo Prefecture, Japan", "hole_count": 18, "last_updated": "2024-04-12"},
    {"name": "The Club at Nine Bridges", "lat": 33.3556, "lon": 126.4028, "location": "Seogwipo, Jeju Province, South Korea", "hole_count": 18, "last_updated": "2024-05-01"},
    {"name": "Sentosa Golf Club (Serapong Course)", "lat": 1.2486, "lon": 103.8294, "location": "Sentosa Island, Singapore", "hole_count": 18, "last_updated": "2024-03-10"},
    {"name": "Emirates Golf Club (Majlis Course)", "lat": 25.0833, "lon": 55.1611, "location": "Dubai, United Arab Emirates", "hole_count": 18, "last_updated": "2024-02-01"},
    {"name": "Jumeirah Golf Estates (Earth Course)", "lat": 25.0250, "lon": 55.2028, "location": "Dubai, United Arab Emirates", "hole_count": 18, "last_updated": "2024-02-05"},
    {"name": "Yas Links Abu Dhabi", "lat": 24.4861, "lon": 54.5972, "location": "Yas Island, Abu Dhabi, United Arab Emirates", "hole_count": 18, "last_updated": "2024-02-08"},

    # Africa
    {"name": "Leopard Creek Country Club", "lat": -25.4333, "lon": 31.5306, "location": "Malelane, Mpumalanga, South Africa", "hole_count": 18, "last_updated": "2024-01-15"},
    {"name": "Fancourt (The Links)", "lat": -33.9556, "lon": 22.3944, "location": "George, Western Cape, South Africa", "hole_count": 18, "last_updated": "2024-01-20"},
    {"name": "Gary Player Country Club", "lat": -25.3444, "lon": 27.1083, "location": "Sun City, North West, South Africa", "hole_count": 18, "last_updated": "2024-01-18"},

    # Popular 9-Hole Courses
    {"name": "Sweetens Cove Golf Club", "lat": 35.1056, "lon": -85.7361, "location": "South Pittsburg, Tennessee, United States", "hole_count": 9, "last_updated": "2024-05-15"},
    {"name": "Winter Park Golf Course (WP9)", "lat": 28.6019, "lon": -81.3533, "location": "Winter Park, Florida, United States", "hole_count": 9, "last_updated": "2024-03-20"},
    {"name": "The Dunes Club", "lat": 41.8306, "lon": -86.7417, "location": "New Buffalo, Michigan, United States", "hole_count": 9, "last_updated": "2024-05-10"},
    {"name": "Whitinsville Golf Club", "lat": 42.1278, "lon": -71.6722, "location": "Northbridge, Massachusetts, United States", "hole_count": 9, "last_updated": "2024-05-05"},
    {"name": "Milham Park Golf Course (Front 9)", "lat": 42.2472, "lon": -85.5722, "location": "Kalamazoo, Michigan, United States", "hole_count": 9, "last_updated": "2024-05-01"},
]


def generate_catalog():
    os.makedirs(os.path.dirname(CATALOG_PATH), exist_ok=True)

    # Sort courses alphabetically by name
    courses = sorted(DEFAULT_COURSES, key=lambda c: c["name"].lower())

    with open(CATALOG_PATH, "w", encoding="utf-8") as f:
        json.dump(courses, f, indent=2, ensure_ascii=False)

    print(f"Successfully generated offline golf catalog at:\n  {CATALOG_PATH}")
    print(f"Total courses: {len(courses)}")


if __name__ == "__main__":
    generate_catalog()
