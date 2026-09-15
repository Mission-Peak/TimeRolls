#!/usr/bin/env python3
"""
build_pack.py — assembles a Photo Chronology photo pack from CC0 sources.

Licensing discipline (spec §6.2, §12): this tool accepts CC0 and nothing else.
CC0 is a worldwide waiver, so it sidesteps the fact that "public domain" is
jurisdiction-specific and the App Store is not — an item that is PD in the US can
still be in copyright in the EU. Anything whose licence is not exactly CC0 is
dropped and counted in the rejection tally printed at the end.

CC0 requires no attribution. We record provenance anyway — source, creator, and the
page the item came from — so any item in a shipped pack can be traced back later.

Sources
  commons-geo    Wikimedia Commons geosearch around a coordinate. Gives real
                 coordinates, so these items can carry the Places theme.
  smithsonian    Smithsonian Open Access. ~35k CC0 photographs with dates, which is
                 where historical material comes from.

Usage
  python3 build_pack.py --pack landmarks --out ../../Photo\\ Chronology/Packs
  python3 build_pack.py --pack decades   --out ../../Photo\\ Chronology/Packs
  python3 build_pack.py --list

The Smithsonian API needs a key. DEMO_KEY works for small runs (30 requests/hour);
get a free one at api.data.gov and pass --si-key for anything larger.
"""

import argparse, json, os, re, shutil, subprocess, sys, tempfile, time, urllib.parse, urllib.request

UA = "PhotoChronologyPackBuilder/1.0 (Attimis prototype; +hanna@attimis.co)"
CC0_STATEMENT = "Q6938433"   # Wikidata item for the CC0 1.0 licence
MAX_EDGE = 1200          # long edge, px — enough for a tile on any device
JPEG_QUALITY = "60"      # sips quality step

# --------------------------------------------------------------------------- specs

PACK_SPECS = {
    "geography": {
        "id": "geography",
        "title": "Natural Wonders",
        "blurb": "Mountains, falls, deserts and coastlines around the world.",
        "source": "commons-geo",
        # Modern landscape photography: excellent for "where", no use for "when".
        "themes": ["places", "objects"],
        "targets": [
            # The Americas
            {"place": "the Grand Canyon, Arizona",   "lat": 36.0544,  "lon": -112.1401, "take": 2},
            {"place": "Yosemite, California",        "lat": 37.7456,  "lon": -119.5936, "take": 2},
            {"place": "Monument Valley, Utah",       "lat": 36.9980,  "lon": -110.0985, "take": 2},
            {"place": "Yellowstone, Wyoming",        "lat": 44.4605,  "lon": -110.8281, "take": 2},
            {"place": "Death Valley, California",    "lat": 36.5054,  "lon": -117.0794, "take": 2},
            {"place": "Niagara Falls, Canada",       "lat": 43.0828,  "lon": -79.0742,  "take": 2},
            {"place": "Lake Louise, Canada",         "lat": 51.4254,  "lon": -116.1773, "take": 2},
            {"place": "Machu Picchu, Peru",          "lat": -13.1631, "lon": -72.5450,  "take": 2},
            {"place": "the Iguazú Falls, Brazil",    "lat": -25.6953, "lon": -54.4367,  "take": 2},
            {"place": "Torres del Paine, Chile",     "lat": -50.9423, "lon": -73.4068,  "take": 2},
            # Europe
            {"place": "the Matterhorn, Switzerland", "lat": 45.9763,  "lon": 7.6586,    "take": 2},
            {"place": "Mont Blanc, France",          "lat": 45.8326,  "lon": 6.8652,    "take": 2},
            {"place": "the Giant's Causeway, Northern Ireland", "lat": 55.2408, "lon": -6.5116, "take": 2},
            {"place": "the Cliffs of Moher, Ireland","lat": 52.9715,  "lon": -9.4309,   "take": 2},
            {"place": "Santorini, Greece",           "lat": 36.4618,  "lon": 25.3753,   "take": 2},
            {"place": "the Geirangerfjord, Norway",  "lat": 62.1049,  "lon": 7.0055,    "take": 2},
            {"place": "Plitvice Lakes, Croatia",     "lat": 44.8654,  "lon": 15.5820,   "take": 2},
            {"place": "Skógafoss, Iceland",          "lat": 63.5321,  "lon": -19.5114,  "take": 2},
            # Africa and the Middle East
            {"place": "Victoria Falls, Zimbabwe",    "lat": -17.9243, "lon": 25.8572,   "take": 2},
            {"place": "the Serengeti, Tanzania",     "lat": -2.3333,  "lon": 34.8333,   "take": 2},
            {"place": "the Sahara, Morocco",         "lat": 31.0819,  "lon": -4.0135,   "take": 2},
            {"place": "the Dead Sea, Israel",        "lat": 31.5590,  "lon": 35.4732,   "take": 2},
            # Asia and Oceania
            {"place": "Mount Fuji, Japan",           "lat": 35.3606,  "lon": 138.7274,  "take": 2},
            {"place": "Hạ Long Bay, Vietnam",        "lat": 20.9101,  "lon": 107.1839,  "take": 2},
            {"place": "Zhangjiajie, China",          "lat": 29.3158,  "lon": 110.4344,  "take": 2},
            {"place": "Everest, Nepal",              "lat": 27.9881,  "lon": 86.9250,   "take": 2},
            {"place": "Uluru, Australia",            "lat": -25.3444, "lon": 131.0369,  "take": 2},
            {"place": "Milford Sound, New Zealand",  "lat": -44.6414, "lon": 167.8974,  "take": 2},
        ],
    },
    "landmarks": {
        "id": "travel-landmarks",
        "title": "Travel Landmarks",
        "blurb": "Places worth remembering, from six decades of travel photography.",
        "source": "commons-geo",
        # Modern travel photography: fine for "where", useless for "when".
        "themes": ["places", "objects"],
        # Coordinates are the query; the place name is ours, so Places questions read well.
        # Each target is a well-photographed landmark; the place name is ours, so a
        # Places question reads the way a person would say it. More cities is not just
        # more content — Places picks its distractors by distance from the answer, so a
        # wider spread is what makes the difficulty lever work.
        "targets": [
            # Europe
            {"place": "Paris, France",          "lat": 48.8584,  "lon": 2.2945,   "take": 2},
            {"place": "Rome, Italy",            "lat": 41.8902,  "lon": 12.4922,  "take": 2},
            {"place": "Venice, Italy",          "lat": 45.4341,  "lon": 12.3388,  "take": 2},
            {"place": "London, England",        "lat": 51.5007,  "lon": -0.1246,  "take": 2},
            {"place": "Edinburgh, Scotland",    "lat": 55.9486,  "lon": -3.1999,  "take": 2},
            {"place": "Dublin, Ireland",        "lat": 53.3438,  "lon": -6.2546,  "take": 2},
            {"place": "Barcelona, Spain",       "lat": 41.4036,  "lon": 2.1744,   "take": 2},
            {"place": "Lisbon, Portugal",       "lat": 38.6916,  "lon": -9.2160,  "take": 2},
            {"place": "Amsterdam, Netherlands", "lat": 52.3600,  "lon": 4.8852,   "take": 2},
            {"place": "Berlin, Germany",        "lat": 52.5163,  "lon": 13.3777,  "take": 2},
            {"place": "Prague, Czechia",        "lat": 50.0865,  "lon": 14.4114,  "take": 2},
            {"place": "Vienna, Austria",        "lat": 48.1845,  "lon": 16.3122,  "take": 2},
            {"place": "Athens, Greece",         "lat": 37.9715,  "lon": 23.7267,  "take": 2},
            {"place": "Copenhagen, Denmark",    "lat": 55.6798,  "lon": 12.5912,  "take": 2},
            {"place": "Stockholm, Sweden",      "lat": 59.3251,  "lon": 18.0711,  "take": 2},
            {"place": "Istanbul, Türkiye",      "lat": 41.0086,  "lon": 28.9802,  "take": 2},
            {"place": "Reykjavík, Iceland",     "lat": 64.1418,  "lon": -21.9266, "take": 2},
            # North America
            {"place": "New York, NY",           "lat": 40.6892,  "lon": -74.0445, "take": 2},
            {"place": "San Francisco, CA",      "lat": 37.8199,  "lon": -122.4783,"take": 2},
            {"place": "Chicago, IL",            "lat": 41.8827,  "lon": -87.6233, "take": 2},
            {"place": "Seattle, WA",            "lat": 47.6205,  "lon": -122.3493,"take": 2},
            {"place": "Washington, DC",         "lat": 38.8893,  "lon": -77.0502, "take": 2},
            {"place": "Boston, MA",             "lat": 42.3541,  "lon": -71.0704, "take": 2},
            {"place": "New Orleans, LA",        "lat": 29.9574,  "lon": -90.0629, "take": 2},
            {"place": "Toronto, Canada",        "lat": 43.6426,  "lon": -79.3871, "take": 2},
            {"place": "Mexico City, Mexico",    "lat": 19.4270,  "lon": -99.1677, "take": 2},
            # South America
            {"place": "Rio de Janeiro, Brazil", "lat": -22.9519, "lon": -43.2105, "take": 2},
            {"place": "Buenos Aires, Argentina","lat": -34.6037, "lon": -58.3816, "take": 2},
            # Asia
            {"place": "Tokyo, Japan",           "lat": 35.7148,  "lon": 139.7967, "take": 2},
            {"place": "Kyoto, Japan",           "lat": 34.9671,  "lon": 135.7727, "take": 2},
            {"place": "Hong Kong",              "lat": 22.2940,  "lon": 114.1722, "take": 2},
            {"place": "Singapore",              "lat": 1.2834,   "lon": 103.8607, "take": 2},
            {"place": "Bangkok, Thailand",      "lat": 13.7500,  "lon": 100.4913, "take": 2},
            {"place": "Dubai, UAE",             "lat": 25.1972,  "lon": 55.2744,  "take": 2},
            {"place": "Agra, India",            "lat": 27.1751,  "lon": 78.0421,  "take": 2},
            # Africa
            {"place": "Cairo, Egypt",           "lat": 29.9792,  "lon": 31.1342,  "take": 2},
            {"place": "Cape Town, South Africa","lat": -33.9628, "lon": 18.4098,  "take": 2},
            # Oceania
            {"place": "Sydney, Australia",      "lat": -33.8568, "lon": 151.2153, "take": 2},
            {"place": "Melbourne, Australia",   "lat": -37.8183, "lon": 144.9671, "take": 2},
            {"place": "Auckland, New Zealand",  "lat": -36.8485, "lon": 174.7622, "take": 2},
        ],
    },
    "everyday": {
        "id": "everyday-life",
        "title": "Everyday Life",
        "blurb": "Ordinary things, photographed by people all over the world.",
        "source": "commons-subject",
        "queries": [
            {"q": "kitchen", "take": 18},        {"q": "garden flowers", "take": 18},
            {"q": "dog", "take": 18},            {"q": "cat", "take": 18},
            {"q": "beach", "take": 18},          {"q": "market stall", "take": 18},
            {"q": "bicycle", "take": 16},        {"q": "train station", "take": 16},
            {"q": "birthday cake", "take": 16},  {"q": "farm harvest", "take": 16},
            {"q": "village street", "take": 16}, {"q": "mountains", "take": 16},
            {"q": "boat harbour", "take": 16},   {"q": "forest path", "take": 16},
            {"q": "snow winter", "take": 16},    {"q": "horses field", "take": 16},
            {"q": "bakery bread", "take": 14},   {"q": "fishing boats", "take": 14},
            {"q": "autumn leaves", "take": 14},  {"q": "picnic park", "take": 14},
            {"q": "teapot tea", "take": 12},     {"q": "knitting sewing", "take": 12},
            {"q": "vintage car", "take": 14},    {"q": "church village", "take": 14},
        ],
    },
    "sports": {
        "id": "sports",
        "title": "Sports",
        "blurb": "A century of games, players and crowds.",
        "source": "smithsonian",
        "themes": ["chronology", "objects"],
        "spreadAcrossDecades": True,
        "queries": [
            {"take": 60,
             "q": 'online_media_type:"Images" AND media_usage:"CC0" AND '
                  'object_type:"Photographs" AND (baseball OR football OR boxing OR olympic OR tennis OR cycling OR rowing OR athlete)'},
        ],
    },
    "entertainment": {
        "id": "entertainment",
        "title": "Stage and Screen",
        "blurb": "Performers, bands and theatres, decade by decade.",
        "source": "smithsonian",
        "themes": ["chronology", "objects"],
        "spreadAcrossDecades": True,
        "queries": [
            {"take": 60,
             "q": 'online_media_type:"Images" AND media_usage:"CC0" AND '
                  'object_type:"Photographs" AND (actress OR actor OR musician OR jazz OR theater OR band OR singer OR dancer OR circus)'},
        ],
    },
    "space": {
        "id": "space",
        "title": "Space",
        "blurb": "Photographs almost everyone has seen, from Mercury to Mars.",
        "source": "nasa-curated",
        "themes": ["chronology", "objects"],
        "photographs": [
            {"year": 1962, "title": "John Glenn boards Friendship 7", "q": "John Glenn Friendship 7 1962"},
            {"year": 1965, "title": "The first American spacewalk", "q": "Ed White Gemini 4 EVA"},
            {"year": 1966, "title": "Gemini in orbit", "q": "Gemini 7 spacecraft in orbit"},
            {"year": 1968, "title": "Earthrise, seen from Apollo 8", "q": "Earthrise Apollo 8"},
            {"year": 1969, "title": "A footprint on the Moon", "q": "Apollo 11 bootprint lunar surface"},
            {"year": 1969, "title": "Buzz Aldrin on the Moon", "q": "Aldrin Apollo 11 visor reflection"},
            {"year": 1971, "title": "The lunar rover", "q": "Apollo 15 lunar roving vehicle"},
            {"year": 1972, "title": "The Blue Marble", "q": "Blue Marble Apollo 17 Earth"},
            {"year": 1973, "title": "Skylab above the Earth", "q": "Skylab space station orbit"},
            {"year": 1975, "title": "Apollo and Soyuz meet in orbit", "q": "Apollo Soyuz Test Project"},
            {"year": 1981, "title": "The first Space Shuttle launch", "q": "STS-1 Columbia first launch 1981"},
            {"year": 1984, "title": "Untethered above the Earth", "q": "McCandless manned maneuvering unit"},
            {"year": 1990, "title": "Hubble leaves the payload bay", "q": "Hubble Space Telescope deployment 1990"},
            {"year": 1995, "title": "Shuttle docks with Mir", "q": "Space Shuttle Atlantis Mir docking"},
            {"year": 1997, "title": "A rover on Mars", "q": "Mars Pathfinder Sojourner rover surface"},
            {"year": 1998, "title": "The Space Station begins", "q": "International Space Station Unity Zarya 1998"},
            {"year": 2004, "title": "Opportunity on Mars", "q": "Mars Exploration Rover Opportunity"},
            {"year": 2005, "title": "The Space Station takes shape", "q": "International Space Station assembly 2005"},
            {"year": 2012, "title": "Curiosity lands", "q": "Curiosity rover Mars self portrait"},
            {"year": 2015, "title": "Pluto, close up", "q": "New Horizons Pluto"},
            {"year": 2019, "title": "A spacewalk at the Station", "q": "spacewalk International Space Station 2019"},
            {"year": 2021, "title": "A helicopter flies on Mars", "q": "Ingenuity Mars helicopter"},
            {"year": 2022, "title": "The Webb telescope's first look", "q": "James Webb Space Telescope first images"},
            {"year": 2024, "title": "Artemis prepares to return", "q": "Artemis Space Launch System rollout"},
        ],
    },
    "faces": {
        "id": "famous-faces",
        "title": "Famous Faces",
        "blurb": "People almost everyone has seen a photograph of.",
        "source": "commons-curated",
        "themes": ["chronology", "objects"],
        "licences": {"CC0", "Public domain", "No restrictions"},
        "photographs": [
            {"year": 1863, "title": "Abraham Lincoln", "q": "Abraham Lincoln 1863 portrait photograph"},
            {"year": 1876, "title": "Alexander Graham Bell", "q": "Alexander Graham Bell portrait"},
            {"year": 1888, "title": "Thomas Edison", "q": "Thomas Edison phonograph portrait"},
            {"year": 1901, "title": "Theodore Roosevelt", "q": "Theodore Roosevelt portrait 1901"},
            {"year": 1907, "title": "Mark Twain", "q": "Mark Twain white suit portrait"},
            {"year": 1912, "title": "Jim Thorpe at the Olympics", "q": "Jim Thorpe 1912 Olympics"},
            {"year": 1920, "title": "Babe Ruth", "q": "Babe Ruth baseball portrait"},
            {"year": 1921, "title": "Albert Einstein", "q": "Albert Einstein 1921 portrait"},
            {"year": 1928, "title": "Amelia Earhart", "q": "Amelia Earhart portrait aircraft"},
            {"year": 1933, "title": "Franklin D. Roosevelt", "q": "Franklin Roosevelt 1933 portrait"},
            {"year": 1936, "title": "Jesse Owens in Berlin", "q": "Jesse Owens 1936 Olympics"},
            {"year": 1945, "title": "Harry Truman", "q": "Harry Truman official portrait"},
            {"year": 1953, "title": "Dwight Eisenhower", "q": "Dwight Eisenhower official portrait"},
            {"year": 1956, "title": "Louis Armstrong", "q": "Louis Armstrong trumpet photograph"},
            {"year": 1961, "title": "John F. Kennedy", "q": "John F Kennedy White House portrait"},
            {"year": 1963, "title": "Martin Luther King Jr.", "q": "Martin Luther King Jr March on Washington"},
            {"year": 1964, "title": "Lyndon Johnson", "q": "Lyndon Johnson official portrait"},
            {"year": 1969, "title": "Neil Armstrong", "q": "Neil Armstrong portrait spacesuit"},
            {"year": 1977, "title": "Jimmy Carter", "q": "Jimmy Carter official portrait"},
            {"year": 1981, "title": "Ronald Reagan", "q": "Ronald Reagan official portrait"},
            {"year": 1984, "title": "Sandra Day O'Connor", "q": "Sandra Day O'Connor official portrait"},
            {"year": 1993, "title": "Bill Clinton", "q": "Bill Clinton official portrait"},
        ],
    },
    "animals": {
        "id": "animals",
        "title": "Animals",
        "blurb": "Creatures large and small.",
        "source": "commons-subject",
        "themes": ["objects"],
        "minYear": 1990,
        "queries": [
            {"q": "dog portrait", "take": 10, "tags": ["dog"]},
            {"q": "puppy", "take": 8, "tags": ["dog"]},
            {"q": "dog running grass", "take": 8, "tags": ["dog"]},
            {"q": "cat sitting", "take": 10, "tags": ["cat"]},
            {"q": "kitten", "take": 8, "tags": ["cat"]},
            {"q": "cat window", "take": 8, "tags": ["cat"]},
            {"q": "horse field", "take": 10, "tags": ["horse"]},
            {"q": "horses grazing", "take": 8, "tags": ["horse"]},
            {"q": "bird perched branch", "take": 10, "tags": ["bird"]},
            {"q": "birds flying", "take": 8, "tags": ["bird"]},
        ],
    },
    "science": {
        "id": "science",
        "title": "Science and Invention",
        "blurb": "Laboratories, instruments and the people who used them.",
        "source": "smithsonian",
        "themes": ["chronology", "objects"],
        "spreadAcrossDecades": True,
        "queries": [
            {"take": 60,
             "q": 'online_media_type:"Images" AND media_usage:"CC0" AND '
                  'object_type:"Photographs" AND (laboratory OR telescope OR microscope OR inventor OR engine OR machine OR experiment)'},
        ],
    },
    "milestones": {
        "id": "milestones",
        "title": "Milestones",
        "blurb": "Moments and machines people remember.",
        "source": "commons-curated",
        "themes": ["chronology", "objects"],
        "licences": {"CC0", "Public domain", "No restrictions"},
        "photographs": [
            {"year": 1883, "title": "The Brooklyn Bridge opens", "q": "Brooklyn Bridge 1883 photograph"},
            {"year": 1889, "title": "The Eiffel Tower is finished", "q": "Eiffel Tower 1889 construction"},
            {"year": 1903, "title": "The Wright brothers fly", "q": "Wright brothers first flight 1903"},
            {"year": 1908, "title": "The Ford Model T", "q": "Ford Model T 1908 photograph"},
            {"year": 1912, "title": "The Titanic", "q": "RMS Titanic 1912 photograph"},
            {"year": 1927, "title": "The Spirit of St. Louis", "q": "Spirit of St Louis Lindbergh 1927"},
            {"year": 1931, "title": "The Empire State Building", "q": "Empire State Building 1931"},
            {"year": 1936, "title": "Migrant Mother", "q": "Migrant Mother Dorothea Lange"},
            {"year": 1937, "title": "The Golden Gate Bridge opens", "q": "Golden Gate Bridge 1937 opening"},
            {"year": 1947, "title": "Breaking the sound barrier", "q": "Bell X-1 Chuck Yeager 1947"},
            {"year": 1955, "title": "Rosa Parks in Montgomery", "q": "Rosa Parks 1955 Montgomery"},
            {"year": 1959, "title": "The Mini arrives", "q": "Austin Mini 1959 car"},
            {"year": 1964, "title": "The Beatles arrive in America", "q": "Beatles 1964 arrival New York"},
            {"year": 1970, "title": "The Boeing 747 enters service", "q": "Boeing 747 1970 Pan Am"},
            {"year": 1976, "title": "Concorde begins flying", "q": "Concorde 1976 first commercial flight"},
            {"year": 1981, "title": "The personal computer arrives", "q": "IBM Personal Computer 1981"},
            {"year": 1989, "title": "The Berlin Wall comes down", "q": "Berlin Wall 1989 Brandenburg Gate"},
            {"year": 1994, "title": "The Channel Tunnel opens", "q": "Channel Tunnel 1994 opening"},
            {"year": 1997, "title": "Mars Pathfinder lands", "q": "Mars Pathfinder 1997 landing"},
        ],
    },
}

# --------------------------------------------------------------------------- helpers

class Rejections:
    def __init__(self):
        self.counts = {}
    def add(self, reason):
        self.counts[reason] = self.counts.get(reason, 0) + 1
    def report(self):
        if not self.counts:
            return "  (none)"
        return "\n".join(f"  {v:4d}  {k}" for k, v in sorted(self.counts.items(), key=lambda kv: -kv[1]))


def fetch_json(url, timeout=45):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def commons_file_url(title):
    """Special:FilePath is the form Commons recommends for linking to a file: it follows
    renames, and takes a width so we ask for a tile-sized rendition rather than a
    40-megapixel original."""
    return ("https://commons.wikimedia.org/wiki/Special:FilePath/"
            + urllib.parse.quote(title) + f"?width={MAX_EDGE}")


def strip_html(text):
    return re.sub(r"<[^>]+>", " ", str(text or "")).strip()


def parse_year(text):
    """Pull a plausible 4-digit year out of the messy date strings these sources use."""
    cleaned = strip_html(text)
    match = re.search(r"\b(1[89]\d{2}|20[0-2]\d)\b", cleaned)
    return int(match.group(1)) if match else None


# Geosearch returns whatever is pinned at a coordinate — maps, diagrams, webcam
# grabs and video posters included. A photo pack wants photographs.
NOT_A_PHOTOGRAPH = re.compile(
    r"\b(map|diagram|chart|plan|logo|icon|screenshot|cam|webcam|panorama|"
    r"schematic|drawing|poster|sign|graph)\b", re.IGNORECASE)
PHOTO_MIMES = {"image/jpeg", "image/png"}

# Smithsonian object types that are actually photographs. Paintings and drawings are
# lovely, but "which of these is older" is a question about photographs.
PHOTOGRAPHIC_TYPES = re.compile(
    r"photograph|photoprint|daguerreotype|ambrotype|tintype|negative|slide|albumen",
    re.IGNORECASE)


# Curation, not prudishness. The audience for this game is older adults, some living
# with dementia, and the whole design is built to avoid distress. An archive search will
# happily return a lynching victim's funeral, a machine-gun company and a train wreck
# alongside the picnics. None of that belongs in a gentle reminiscence game, so it is
# filtered by subject before anyone ever sees it. Word boundaries matter here: without
# them "Ward" matches "war" and a cassowary matches on "Wattled".
DISTRESSING = re.compile(
    r"\b(funeral|cemet\w+|grave|graves|burial|buried|lynch\w*|riot\w*|murder\w*|"
    r"killed|death|deaths|dead|wounded|casualt\w+|war|wars|battle|combat|"
    r"disaster|flood|famine|epidemic|hospital|asylum|prison|jail|slave\w*|corpse|autopsy|"
    # Military, including the abbreviations these catalogues actually use: a title like
    # "366 Inf. 92nd Div." never trips a filter looking for the word "infantry".
    r"soldier\w*|infantry|inf|regiment\w*|brigade|battalion|squadron|div|division|troops?|"
    r"military|legion|officers?|hdqrs|headquarters|"
    r"army|navy|naval|marine|marines|corps|uniform|camouflag\w+|supply train|"
    r"cpl|sgt|lt|lieutenant|capt|captain|gen|general|col|colonel|major|admiral|"
    r"weapon\w*|rifle|gun|guns|bomb\w*|wreck\w*|crash\w*|"
    # Proper nouns carry the same weight as the topic words above and none of the same
    # spelling. A photo captioned only "Hitler at the Charles Bridge" is a picture of an
    # occupation to anyone old enough to remember it, and nothing in a list of topics
    # catches it.
    r"hitler|nazi\w*|f[uü]hrer|reich|gestapo|wehrmacht|swastika|holocaust|"
    r"concentration camp|genocide|mussolini|stalin|apartheid|ku klux|lynching|"
    r"execution|hanged|hanging|massacre|atrocit\w+|occupation|invasion)\b",
    re.IGNORECASE)

# The Smithsonian documents itself thoroughly: building interiors, gallery halls,
# construction sites and scanned album pages. All fine records, all dull as a photo to
# reminisce over.
INSTITUTIONAL = re.compile(
    r"\b(national museum|smithsonian institution|smithsonian building|the castle|"
    # Bare "museum" and "gallery" too: a landmark geosearch otherwise returns exhibit
    # labels and gallery interiors, and a photograph of a wall of text makes a poor tile.
    r"national gallery|museum|gallery|zoological park|hall of|regents|"
    r"secretary'?s parlor|si commons|sorting center|exhibits?|exhibition|construction|"
    r"installation|supplement|arts and industries|south yard|bureau building|centennial|"
    r"first ladies|album|sign for)\b|pages? \d+",
    re.IGNORECASE)


# Commons holds a great deal of digitised art, and a search for "cat" happily returns a
# 19th-century engraving of one. Fine pictures; not photographs, and "when was this
# taken?" is the wrong question to ask about them.
ARTWORK = re.compile(
    r"\b(design for|stereograph|engraving|lithograph|etching|woodcut|aquatint|"
    r"drawing|illustration|sketch|painting|watercolou?r|plate \d+|folio|"
    r"from the complete works|met d[pt]\d+|yale|b\d{4}\.\d+)\b",
    re.IGNORECASE)


def title_stem(title):
    """Collapse "Beach near Otaru -22903" and "Beach near Otaru -39689" to one key, so a
    pack doesn't end up with five photographs of the same afternoon."""
    stem = re.sub(r"\.(jpe?g|png)$", "", title, flags=re.IGNORECASE)
    stem = re.sub(r"[-_(\s]*\d+\)?\s*$", "", stem)
    stem = re.sub(r"[^a-zA-Z]+", " ", stem).strip().lower()
    return " ".join(stem.split()[:5])


def unsuitable_subject(title):
    """Reasons a photograph shouldn't go in a pack, whatever its licence."""
    if DISTRESSING.search(title):
        return "distressing subject"
    if INSTITUTIONAL.search(title):
        return "institutional record, not a scene"
    if ARTWORK.search(title):
        return "artwork, not a photograph"
    return None


def looks_like_a_photograph(title, mime, width):
    if mime is None:
        # Some listings omit it; fall back to the filename.
        if not re.search(r"\.(jpe?g|png)$", title, re.IGNORECASE):
            return "not a photo file"
    elif mime not in PHOTO_MIMES:
        return "not a photo file (%s)" % mime
    if width and width < 800:
        return "too small (%dpx)" % width
    if NOT_A_PHOTOGRAPH.search(title):
        return "title suggests it isn't a photograph"
    return None


def parse_month(text):
    cleaned = strip_html(text)
    iso = re.search(r"\b(1[89]\d{2}|20[0-2]\d)-(\d{2})\b", cleaned)
    if iso:
        month = int(iso.group(2))
        return month if 1 <= month <= 12 else 6
    for index, name in enumerate(
        ["january","february","march","april","may","june",
         "july","august","september","october","november","december"], start=1):
        if name in cleaned.lower():
            return index
    return 6


def download_and_resize(url, destination):
    """Fetch an image and normalise it to a bundle-friendly JPEG. Returns True on success."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=90) as response:
            payload = response.read()
    except Exception:
        return False
    if len(payload) < 8_000:          # a stub or an error page, not a photograph
        return False

    with tempfile.NamedTemporaryFile(delete=False, suffix=".img") as handle:
        handle.write(payload)
        raw = handle.name
    try:
        result = subprocess.run(
            ["sips", "-s", "format", "jpeg", "-s", "formatOptions", JPEG_QUALITY,
             "-Z", str(MAX_EDGE), raw, "--out", destination],
            capture_output=True, text=True)
        return result.returncode == 0 and os.path.exists(destination)
    finally:
        os.unlink(raw)

# --------------------------------------------------------------------------- sources

def from_commons(spec, rejections, limit_per_target=80):
    """Geosearch around each landmark, keeping only strict-CC0 files with a date."""
    items = []
    for target in spec["targets"]:
        params = {
            "action": "query", "format": "json", "generator": "geosearch",
            "ggsnamespace": 6, "ggsradius": 2500,
            "ggscoord": f"{target['lat']}|{target['lon']}", "ggslimit": limit_per_target,
            "prop": "imageinfo", "iiprop": "url|extmetadata|size|mime", "iiurlwidth": 1400,
        }
        url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)
        try:
            payload = fetch_json(url)
        except Exception as error:
            print(f"    ! {target['place']}: {error}")
            continue

        taken = 0
        for page in ((payload.get("query") or {}).get("pages") or {}).values():
            if taken >= target["take"]:
                break
            info = (page.get("imageinfo") or [{}])[0]
            extra = info.get("extmetadata") or {}

            licence = strip_html((extra.get("LicenseShortName") or {}).get("value"))
            if licence != "CC0":
                rejections.add(f"licence not CC0 ({licence or 'unknown'})")
                continue
            title = strip_html(page.get("title", "")).replace("File:", "")
            complaint = (looks_like_a_photograph(title, info.get("mime"), info.get("width"))
                         or unsuitable_subject(title))
            if complaint:
                rejections.add(complaint)
                continue
            year = parse_year((extra.get("DateTimeOriginal") or {}).get("value"))
            if not year:
                rejections.add("no usable date")
                continue
            if not info.get("thumburl"):
                rejections.add("no image URL")
                continue

            items.append({
                "remote": commons_file_url(title),
                "title": title,
                "year": year,
                "month": parse_month((extra.get("DateTimeOriginal") or {}).get("value")),
                "place": target["place"],
                "lat": target["lat"], "lon": target["lon"],
                "image": info["thumburl"],
                "credit": strip_html((extra.get("Artist") or {}).get("value")) or "Unknown",
                "source": "Wikimedia Commons",
                "source_url": info.get("descriptionurl", ""),
            })
            taken += 1
        print(f"    {target['place']}: {taken} kept")
        time.sleep(0.4)
    return items


def from_commons_subject(spec, rejections):
    """Commons CC0 search by subject. The licence statement is part of the query, so the
    pool is CC0 from the start; everything else is verified again client-side."""
    items = []
    seen = set()
    for query in spec["queries"]:
        search = (f'haswbstatement:P275={CC0_STATEMENT} {query["q"]} '
                  f'filemime:image/jpeg')
        params = {
            "action": "query", "format": "json", "generator": "search",
            "gsrsearch": search, "gsrnamespace": 6, "gsrlimit": 100,
            "prop": "imageinfo", "iiprop": "url|extmetadata|size|mime", "iiurlwidth": 1400,
        }
        url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)
        try:
            payload = fetch_json(url)
        except Exception as error:
            print(f"    ! {query['q']}: {error}")
            continue

        taken = 0
        for page in ((payload.get("query") or {}).get("pages") or {}).values():
            if taken >= query["take"]:
                break
            info = (page.get("imageinfo") or [{}])[0]
            extra = info.get("extmetadata") or {}

            licence = strip_html((extra.get("LicenseShortName") or {}).get("value"))
            if licence != "CC0":
                rejections.add(f"licence not CC0 ({licence or 'unknown'})")
                continue
            title = strip_html(page.get("title", "")).replace("File:", "")
            stem = title_stem(title)
            if stem in seen:
                rejections.add("near-duplicate of one already taken")
                continue
            complaint = (looks_like_a_photograph(title, info.get("mime"), info.get("width"))
                         or unsuitable_subject(title))
            if complaint:
                rejections.add(complaint)
                continue
            year = parse_year((extra.get("DateTimeOriginal") or {}).get("value"))
            if not year:
                rejections.add("no usable date")
                continue
            if year < spec.get("minYear", 0):
                rejections.add(f"older than {spec['minYear']} (likely artwork, not a photo)")
                continue
            if not info.get("thumburl"):
                rejections.add("no image URL")
                continue

            seen.add(stem)
            items.append({
                "tags": query.get("tags", []),
                "remote": commons_file_url(title),
                "title": title,
                "year": year,
                "month": parse_month((extra.get("DateTimeOriginal") or {}).get("value")),
                "place": None, "lat": None, "lon": None,
                "image": info["thumburl"],
                "credit": strip_html((extra.get("Artist") or {}).get("value")) or "Unknown",
                "source": "Wikimedia Commons",
                "source_url": info.get("descriptionurl", ""),
            })
            taken += 1
        print(f"    {query['q']}: kept {taken}")
        time.sleep(0.4)
    return items


def licence_allowed(spec, licence):
    """Which licences a pack accepts.

    CC0 is the default and the safest: a worldwide waiver. A pack of famous photographs
    cannot live on it, though — almost nothing iconic was ever CC0-released. Those rest on
    two other footings, declared per pack rather than quietly assumed: copyright that has
    expired, and US federal government work, which carries none by statute."""
    allowed = spec.get("licences", {"CC0"})
    return any(licence.lower().startswith(a.lower()) for a in allowed)


def from_commons_curated(spec, rejections):
    """A written list of photographs people recognise, looked up on Commons.

    Significance cannot be searched for — an archive has no idea which of its holdings
    everyone has already seen — and the year belongs to the event rather than to whenever
    a scan was uploaded. So both are written down."""
    items = []
    seen = set()
    for entry in spec["photographs"]:
        params = {
            "action": "query", "format": "json", "generator": "search",
            "gsrsearch": f'{entry["q"]} filemime:image/jpeg', "gsrnamespace": 6, "gsrlimit": 12,
            "prop": "imageinfo", "iiprop": "url|extmetadata|size|mime", "iiurlwidth": 1400,
        }
        url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)
        try:
            payload = fetch_json(url, timeout=90)
        except Exception as error:
            print(f"    ! {entry['title']}: {error}")
            continue

        picked = None
        for page in ((payload.get("query") or {}).get("pages") or {}).values():
            info = (page.get("imageinfo") or [{}])[0]
            extra = info.get("extmetadata") or {}
            title = strip_html(page.get("title", "")).replace("File:", "")
            licence = strip_html((extra.get("LicenseShortName") or {}).get("value"))
            if not licence_allowed(spec, licence):
                rejections.add(f"licence not allowed ({licence or 'unknown'})")
                continue
            if title in seen:
                continue
            if looks_like_a_photograph(title, info.get("mime"), info.get("width")):
                continue
            if not info.get("thumburl"):
                continue
            # Check the photograph against the year claimed for it. A keyword search for
            # "Neil Armstrong 1969" will happily return a 2020 photograph of a museum
            # display, and a dating game that teaches the wrong date is worse than one
            # with fewer photographs.
            found_year = parse_year((extra.get("DateTimeOriginal") or {}).get("value")) \
                or parse_year(title)
            if found_year and abs(found_year - entry["year"]) > 3:
                rejections.add(f"found a {found_year} photograph for {entry['year']}")
                continue
            picked = (title, licence,
                      strip_html((extra.get("Artist") or {}).get("value")) or "Unknown",
                      info.get("descriptionurl", ""), info["thumburl"])
            break

        if not picked:
            rejections.add(f"nothing usable for {entry['title']!r}")
            continue

        title, licence, artist, page_url, thumb = picked
        seen.add(title)
        items.append({
            "remote": commons_file_url(title),
            "title": entry["title"],
            "year": entry["year"],
            "month": entry.get("month", 6),
            "place": None, "lat": None, "lon": None,
            "image": thumb,
            "credit": artist,
            "source": "Wikimedia Commons",
            "source_url": page_url,
            "licence": licence,
        })
        print(f"    {entry['year']}  {entry['title']}")
        time.sleep(0.3)
    return items


def from_nasa_curated(spec, rejections):
    """A hand-picked list of photographs people recognise, each with the date of the
    event rather than of the upload.

    Significance cannot be found by keyword search — an archive has no idea which of its
    photographs everyone has seen. And NASA's own metadata dates many Apollo pictures to
    the anniversary that reposted them, so the year comes from the list, not the API.
    NASA imagery is public domain, which is what makes a pack of famous photographs
    possible at all: almost every other iconic 20th-century photograph is owned by an
    agency."""
    items = []
    seen = set()
    for entry in spec["photographs"]:
        url = "https://images-api.nasa.gov/search?" + urllib.parse.urlencode(
            {"q": entry["q"], "media_type": "image"})
        try:
            payload = fetch_json(url, timeout=60)
        except Exception as error:
            print(f"    ! {entry['title']}: {error}")
            continue

        picked = None
        for candidate in payload.get("collection", {}).get("items", []):
            data = (candidate.get("data") or [{}])[0]
            links = candidate.get("links") or []
            if not links:
                continue
            title = strip_html(data.get("title", ""))
            if title in seen:
                continue
            if unsuitable_subject(title):
                rejections.add("distressing or institutional subject")
                continue
            href = links[0].get("href", "")
            if not href:
                continue
            picked = (title, href)
            break

        if not picked:
            rejections.add(f"nothing usable for {entry['title']!r}")
            continue

        title, href = picked
        seen.add(title)
        items.append({
            # NASA serves several renditions; the medium one is tile-sized.
            "remote": href.replace("~thumb.jpg", "~medium.jpg"),
            "title": entry["title"],
            "year": entry["year"],
            "month": entry.get("month", 6),
            "place": None, "lat": None, "lon": None,
            "image": href.replace("~thumb.jpg", "~medium.jpg"),
            "credit": "NASA",
            "source": "NASA Image and Video Library",
            "source_url": "https://images.nasa.gov/",
        })
        print(f"    {entry['year']}  {entry['title']}")
        time.sleep(0.3)
    return items


def from_commons_category(spec, rejections):
    """Commons, inside a category, one query per decade. Used for US government
    photography: public domain by statute rather than by licence, which is how the
    1960s to 1990s become reachable at all."""
    items = []
    seen = set()
    for query in spec["queries"]:
        years = " OR ".join(str(query["decade"] + offset) for offset in range(0, 10))
        search = (f'deepcategory:"{spec["category"]}" filemime:image/jpeg ({years})'
                  + (f' ({spec["terms"]})' if spec.get("terms") else ""))
        params = {
            "action": "query", "format": "json", "generator": "search",
            "gsrsearch": search, "gsrnamespace": 6, "gsrlimit": 80,
            "prop": "imageinfo", "iiprop": "url|extmetadata|size|mime", "iiurlwidth": 1400,
        }
        url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)
        try:
            payload = fetch_json(url, timeout=180)
        except Exception as error:
            print(f"    ! {query['decade']}s: {error}")
            continue

        taken = 0
        for page in ((payload.get("query") or {}).get("pages") or {}).values():
            if taken >= query["take"]:
                break
            info = (page.get("imageinfo") or [{}])[0]
            extra = info.get("extmetadata") or {}
            title = strip_html(page.get("title", "")).replace("File:", "")

            stem = title_stem(title)
            if stem in seen:
                rejections.add("near-duplicate of one already taken")
                continue
            complaint = (looks_like_a_photograph(title, info.get("mime"), info.get("width"))
                         or unsuitable_subject(title))
            if complaint:
                rejections.add(complaint)
                continue
            year = parse_year((extra.get("DateTimeOriginal") or {}).get("value")) \
                or parse_year(title)
            if not year or not (query["decade"] <= year < query["decade"] + 10):
                rejections.add("outside the decade asked for")
                continue
            if not info.get("thumburl"):
                rejections.add("no image URL")
                continue

            seen.add(stem)
            items.append({
                "remote": commons_file_url(title),
                "title": title,
                "year": year,
                "month": parse_month((extra.get("DateTimeOriginal") or {}).get("value")),
                "place": None, "lat": None, "lon": None,
                "image": info["thumburl"],
                "credit": strip_html((extra.get("Artist") or {}).get("value")) or "US Government",
                "source": "US National Archives via Wikimedia Commons",
                "source_url": info.get("descriptionurl", ""),
            })
            taken += 1
        print(f"    {query['decade']}s: kept {taken}")
        time.sleep(0.4)
    return items


def from_smithsonian(spec, rejections, api_key):
    """Smithsonian Open Access, filtered to items whose media is explicitly CC0."""
    items = []
    seen_titles = set()
    for query in spec["queries"]:
        taken = 0
        rows = []
        # Filtering is aggressive, so one page of results often isn't enough.
        for page in range(3):
            params = {"q": query["q"], "rows": 100, "start": page * 100, "api_key": api_key}
            url = "https://api.si.edu/openaccess/api/v1.0/search?" + urllib.parse.urlencode(params)
            try:
                payload = fetch_json(url)
            except Exception as error:
                if "429" in str(error):
                    print("    ! rate limited. DEMO_KEY allows about 30 requests an hour —")
                    print("      get a free key at https://api.data.gov/signup and pass --si-key.")
                else:
                    print(f"    ! query failed: {error}")
                break
            batch = payload.get("response", {}).get("rows", [])
            rows.extend(batch)
            if len(batch) < 100:
                break
            time.sleep(0.4)

        for row in rows:
            if taken >= query["take"]:
                break
            content = row.get("content", {})
            media = ((content.get("descriptiveNonRepeating") or {}).get("online_media") or {}).get("media") or []
            if not media:
                rejections.add("no media")
                continue
            first = media[0]
            if (first.get("usage") or {}).get("access") != "CC0":
                rejections.add("media not marked CC0")
                continue

            object_types = (content.get("indexedStructured") or {}).get("object_type") or []
            if not any(PHOTOGRAPHIC_TYPES.search(str(kind)) for kind in object_types):
                rejections.add("not a photograph (%s)" % (", ".join(map(str, object_types))[:36] or "no type"))
                continue

            dates = [entry.get("content") for entry in (content.get("freetext", {}).get("date") or [])]
            year = next((parse_year(value) for value in dates if parse_year(value)), None)
            if not year:
                rejections.add("no usable date")
                continue

            title = strip_html(row.get("title"))
            if title in seen_titles:
                rejections.add("duplicate title")
                continue
            complaint = unsuitable_subject(title)
            if complaint:
                rejections.add(complaint)
                continue
            image = first.get("content")
            if not image:
                rejections.add("no image URL")
                continue

            wanted_decade = query.get("decade")
            if wanted_decade and not (wanted_decade <= year < wanted_decade + 10):
                rejections.add("outside the decade asked for")
                continue

            makers = [strip_html(entry.get("content"))
                      for entry in (content.get("freetext", {}).get("name") or [])]
            seen_titles.add(title)
            items.append({
                "remote": f"{image}&max={MAX_EDGE}" if "?" in image else image,
                "title": title[:80],
                "year": year,
                "month": 6,
                "place": None, "lat": None, "lon": None,
                "image": image,
                "credit": makers[0] if makers else "Smithsonian Institution",
                "source": "Smithsonian Open Access",
                "source_url": f"https://www.si.edu/object/{row.get('id','')}",
            })
            taken += 1
        label = str(query.get("decade") or query["q"][:40])
        print(f"    {label}: kept {taken}")
        time.sleep(1.0)
    return items

# --------------------------------------------------------------------------- build

def build(pack_name, out_root, api_key, metadata_only=False):
    spec = PACK_SPECS[pack_name]
    rejections = Rejections()

    print(f"\nBuilding '{spec['title']}' from {spec['source']} — CC0 only\n")
    if spec["source"] == "commons-geo":
        candidates = from_commons(spec, rejections)
    elif spec["source"] == "commons-subject":
        candidates = from_commons_subject(spec, rejections)
    elif spec["source"] == "commons-category":
        candidates = from_commons_category(spec, rejections)
    elif spec["source"] == "nasa-curated":
        candidates = from_nasa_curated(spec, rejections)
    elif spec["source"] == "commons-curated":
        candidates = from_commons_curated(spec, rejections)
    else:
        candidates = from_smithsonian(spec, rejections, api_key)

    if spec.get("spreadAcrossDecades") and candidates:
        # Keep at most a handful per decade, so a collection that happens to be deep in
        # the 1880s doesn't become the whole pack.
        per_decade = spec.get("perDecadeCap", 6)
        buckets = {}
        spread = []
        for candidate in candidates:
            decade = candidate["year"] // 10 * 10
            if buckets.get(decade, 0) >= per_decade:
                rejections.add("decade already full")
                continue
            buckets[decade] = buckets.get(decade, 0) + 1
            spread.append(candidate)
        candidates = spread
        print(f"\n  kept across decades: {dict(sorted(buckets.items()))}")

    if not candidates:
        print("\nNothing passed the licence gate. Rejections:")
        print(rejections.report())
        return 1

    pack_dir = os.path.join(out_root, spec["id"])
    staging = pack_dir + ".building"
    if os.path.exists(staging):
        shutil.rmtree(staging)
    os.makedirs(staging)

    if metadata_only:
        print(f"\nRecording {len(candidates)} photographs (no images copied)…")
    else:
        print(f"\nDownloading {len(candidates)} images…")
    items = []
    for index, candidate in enumerate(candidates, start=1):
        item_id = f"{spec['id']}-{index:03d}"
        filename = f"{item_id}.jpg"
        if not metadata_only:
            if not download_and_resize(candidate["image"], os.path.join(staging, filename)):
                rejections.add("download or resize failed")
                continue
        entry = {
            "id": item_id,
            "objectTags": candidate.get("tags") or [],
            "remoteURL": candidate.get("remote") or candidate["image"],
            "title": candidate["title"],
            "year": candidate["year"],
            "month": candidate["month"],
            "credit": candidate["credit"],
            "source": candidate["source"],
            "sourceURL": candidate["source_url"],
            "license": candidate.get("licence", "CC0"),
        }
        if not metadata_only:
            entry["file"] = filename
        if candidate["place"]:
            entry.update({"place": candidate["place"],
                          "latitude": candidate["lat"],
                          "longitude": candidate["lon"]})
        items.append(entry)
        if not metadata_only:
            print(f"  {index:3d}/{len(candidates)}  {candidate['year']}  {candidate['title'][:52]}")

    manifest = {
        "formatVersion": 2,
        "themes": spec.get("themes", ["chronology", "places", "objects"]),
        "id": spec["id"],
        "title": spec["title"],
        "blurb": spec["blurb"],
        "license": ", ".join(sorted(spec.get("licences", {"CC0"}))),
        "builtAt": time.strftime("%Y-%m-%d"),
        "items": items,
    }
    existing = 0
    if os.path.isdir(pack_dir) and not metadata_only:
        existing = len([name for name in os.listdir(pack_dir) if name.endswith(".jpg")])
    if items and existing > len(items):
        print(f"\nStopping: this run produced {len(items)} photos but {pack_dir} already "
              f"has {existing}. Refusing to replace a fuller pack with a thinner one —")
        print("rerun with --si-key once you have a key, or delete the pack directory to force it.")
        shutil.rmtree(staging)
        print("\nRejected along the way:")
        print(rejections.report())
        return 1

    manifest_name = f"{spec['id']}.pack.json"
    with open(os.path.join(staging, manifest_name), "w") as handle:
        json.dump(manifest, handle, indent=2)

    if os.path.exists(pack_dir):
        shutil.rmtree(pack_dir)
    os.rename(staging, pack_dir)

    total_bytes = sum(os.path.getsize(os.path.join(pack_dir, entry["file"]))
                      for entry in items if "file" in entry)
    years = sorted(entry["year"] for entry in items)
    spread = {}
    for entry in items:
        spread[entry["year"] // 10 * 10] = spread.get(entry["year"] // 10 * 10, 0) + 1
    print(f"\nWrote {len(items)} items to {pack_dir}")
    print(f"  years  {years[0]}–{years[-1]}")
    print(f"  spread {dict(sorted(spread.items()))}")
    print(f"  size   {total_bytes/1_000_000:.1f} MB")
    print(f"  places {len({entry.get('place') for entry in items if entry.get('place')})}")
    print("\nRejected along the way:")
    print(rejections.report())
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pack", choices=sorted(PACK_SPECS))
    parser.add_argument("--out", default="../../Photo Chronology/Packs")
    parser.add_argument("--si-key", default=os.environ.get("SI_API_KEY", "DEMO_KEY"))
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--metadata-only", action="store_true",
                        help="record where each photograph lives instead of copying it")
    args = parser.parse_args()

    if args.list or not args.pack:
        print("Packs this tool can build:\n")
        for name, spec in sorted(PACK_SPECS.items()):
            print(f"  {name:12} {spec['title']:20} via {spec['source']}")
        return 0
    return build(args.pack, os.path.abspath(args.out), args.si_key, args.metadata_only)


if __name__ == "__main__":
    sys.exit(main())
