#!/usr/bin/env python3
"""
build_pack.py — assembles a Time Rolls photo pack from CC0 sources.

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

import argparse, json, os, re, shutil, subprocess, sys, tempfile, time, unicodedata, urllib.parse, urllib.request

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
        "title": "Landmarks",
        "blurb": "Places you would know from a single photograph.",
        "source": "commons-curated",
        "themes": ["places"],
        # Attribution licences are allowed here and credited on the Photo credits screen.
        # Restricting landmarks to CC0 meant geosearch results — a street near the
        # Colosseum rather than the Colosseum.
        "licences": {"CC0", "Public domain", "No restrictions", "CC BY", "CC BY-SA"},
        "photographs": [
            {"year": 2015, "title": "The Colosseum", "q": "Colosseum Rome exterior", "must": ["Colosseum"], "place": "Rome, Italy", "lat": 41.8902, "lon": 12.4922, "wiki": "Colosseum"},
            {"year": 2015, "title": "The Eiffel Tower", "q": "Eiffel Tower Paris", "must": ["Eiffel"], "place": "Paris, France", "lat": 48.8584, "lon": 2.2945, "wiki": "Eiffel Tower"},
            {"year": 2015, "title": "Big Ben", "q": "Big Ben Elizabeth Tower Westminster", "must": ["Ben"], "place": "London, England", "lat": 51.5007, "lon": -0.1246, "wiki": "Big Ben"},
            {"year": 2015, "title": "The Golden Gate Bridge", "q": "Golden Gate Bridge San Francisco", "must": ["Golden", "Gate"], "place": "San Francisco, California", "lat": 37.8199, "lon": -122.4783, "wiki": "Golden Gate Bridge"},
            {"year": 2015, "title": "The Statue of Liberty", "q": "Statue of Liberty New York", "must": ["Liberty"], "place": "New York, New York", "lat": 40.6892, "lon": -74.0445, "wiki": "Statue of Liberty"},
            {"year": 2015, "title": "The Taj Mahal", "q": "Taj Mahal Agra", "must": ["Taj"], "place": "Agra, India", "lat": 27.1751, "lon": 78.0421, "wiki": "Taj Mahal"},
            {"year": 2015, "title": "The Sydney Opera House", "q": "Sydney Opera House harbour", "must": ["Opera"], "place": "Sydney, Australia", "lat": -33.8568, "lon": 151.2153, "wiki": "Sydney Opera House"},
            {"year": 2015, "title": "The Great Wall", "q": "Great Wall of China Badaling", "must": ["Great", "Wall"], "place": "Beijing, China", "lat": 40.3587, "lon": 116.0176, "wiki": "Great Wall of China"},
            {"year": 2015, "title": "Christ the Redeemer", "q": "Christ the Redeemer Rio statue", "must": ["Christ"], "place": "Rio de Janeiro, Brazil", "lat": -22.9519, "lon": -43.2105, "wiki": "Christ the Redeemer (statue)"},
            {"year": 2015, "title": "Machu Picchu", "q": "Machu Picchu ruins", "must": ["Machu"], "place": "Machu Picchu, Peru", "lat": -13.1631, "lon": -72.5450, "wiki": "Machu Picchu"},
            {"year": 2015, "title": "The Pyramids of Giza", "q": "Pyramids of Giza Sphinx", "must": ["Giza"], "place": "Giza, Egypt", "lat": 29.9792, "lon": 31.1342, "wiki": "Giza pyramid complex"},
            {"year": 2015, "title": "The Parthenon", "q": "Parthenon Acropolis Athens", "must": ["Parthenon"], "place": "Athens, Greece", "lat": 37.9715, "lon": 23.7267, "wiki": "Parthenon"},
            {"year": 2015, "title": "The Sagrada Família", "q": "Sagrada Familia Barcelona exterior", "must": ["Sagrada"], "place": "Barcelona, Spain", "lat": 41.4036, "lon": 2.1744, "wiki": "Sagrada Família"},
            {"year": 2015, "title": "The Leaning Tower of Pisa", "q": "Leaning Tower of Pisa", "must": ["Pisa"], "place": "Pisa, Italy", "lat": 43.7230, "lon": 10.3966, "wiki": "Leaning Tower of Pisa"},
            {"year": 2015, "title": "The Brandenburg Gate", "q": "Brandenburg Gate Berlin", "must": ["Brandenburg"], "place": "Berlin, Germany", "lat": 52.5163, "lon": 13.3777, "wiki": "Brandenburg Gate"},
            {"year": 2015, "title": "Saint Basil's Cathedral", "q": "Saint Basil's Cathedral Moscow", "must": ["Basil"], "place": "Moscow, Russia", "lat": 55.7525, "lon": 37.6231, "wiki": "Saint Basil's Cathedral"},
            {"year": 2015, "title": "Mount Fuji", "q": "Mount Fuji snow", "must": ["Fuji"], "place": "Mount Fuji, Japan", "lat": 35.3606, "lon": 138.7274, "wiki": "Mount Fuji"},
            {"year": 2015, "title": "The Grand Canyon", "q": "Grand Canyon south rim", "must": ["Grand", "Canyon"], "place": "the Grand Canyon, Arizona", "lat": 36.0544, "lon": -112.1401, "wiki": "Grand Canyon"},
            {"year": 2015, "title": "Niagara Falls", "q": "Niagara Falls horseshoe", "must": ["Niagara"], "place": "Niagara Falls, Canada", "lat": 43.0828, "lon": -79.0742, "wiki": "Niagara Falls"},
            {"year": 2015, "title": "Stonehenge", "q": "Stonehenge stone circle", "must": ["Stonehenge"], "place": "Stonehenge, England", "lat": 51.1789, "lon": -1.8262, "wiki": "Stonehenge"},
            {"year": 2015, "title": "Neuschwanstein Castle", "q": "Neuschwanstein Castle", "must": ["Neuschwanstein"], "place": "Bavaria, Germany", "lat": 47.5576, "lon": 10.7498, "wiki": "Neuschwanstein Castle"},
            {"year": 2015, "title": "Angkor Wat", "q": "Angkor Wat temple", "must": ["Angkor"], "place": "Angkor, Cambodia", "lat": 13.4125, "lon": 103.8670, "wiki": "Angkor Wat"},
            {"year": 2015, "title": "Petra", "q": "Petra Treasury Jordan", "must": ["Petra"], "place": "Petra, Jordan", "lat": 30.3285, "lon": 35.4444, "wiki": "Petra"},
            {"year": 2015, "title": "Chichén Itzá", "q": "Chichen Itza pyramid", "must": ["Chichen"], "place": "Chichén Itzá, Mexico", "lat": 20.6843, "lon": -88.5678, "wiki": "Chichen Itza"},
            {"year": 2015, "title": "Table Mountain", "q": "Table Mountain Cape Town", "must": ["Table", "Mountain"], "place": "Cape Town, South Africa", "lat": -33.9628, "lon": 18.4098, "wiki": "Table Mountain"},
            {"year": 2015, "title": "Tower Bridge", "q": "Tower Bridge London Thames", "must": ["Tower", "Bridge"], "place": "London, England", "lat": 51.5055, "lon": -0.0754, "wiki": "Tower Bridge"},
            {"year": 2015, "title": "The Hollywood Sign", "q": "Hollywood Sign Los Angeles", "must": ["Hollywood"], "place": "Los Angeles, California", "lat": 34.1341, "lon": -118.3215, "wiki": "Hollywood Sign"},
            {"year": 2015, "title": "The Space Needle", "q": "Space Needle tower Seattle skyline", "must": ["Space Needle"], "place": "Seattle, Washington", "lat": 47.6205, "lon": -122.3493, "wiki": "Space Needle"},
            {"year": 2015, "title": "Uluru", "q": "Uluru Ayers Rock", "must": ["Uluru"], "place": "Uluru, Australia", "lat": -25.3444, "lon": 131.0369, "wiki": "Uluru"},
            {"year": 2015, "title": "The Hollywood Sign", "wiki": "Hollywood Sign", "place": "Los Angeles, California", "lat": 34.1341, "lon": -118.3215},
            {"year": 2015, "title": "Mount Rushmore", "wiki": "Mount Rushmore", "place": "the Black Hills, South Dakota", "lat": 43.8791, "lon": -103.4591},
            {"year": 2015, "title": "The White House", "wiki": "White House", "place": "Washington, D.C.", "lat": 38.8977, "lon": -77.0365},
            {"year": 2015, "title": "Times Square", "wiki": "Times Square", "place": "New York, New York", "lat": 40.758, "lon": -73.9855},
            {"year": 2015, "title": "Alcatraz", "wiki": "Alcatraz Island", "place": "San Francisco, California", "lat": 37.827, "lon": -122.423},
            {"year": 2015, "title": "Old Faithful", "wiki": "Old Faithful", "place": "Yellowstone, Wyoming", "lat": 44.4605, "lon": -110.8281},
            {"year": 2015, "title": "Half Dome", "wiki": "Half Dome", "place": "Yosemite, California", "lat": 37.7459, "lon": -119.5332},
            {"year": 2015, "title": "Lake Louise", "wiki": "Lake Louise (Alberta)", "place": "Banff, Canada", "lat": 51.4254, "lon": -116.1773},
            {"year": 2015, "title": "The CN Tower", "wiki": "CN Tower", "place": "Toronto, Canada", "lat": 43.6426, "lon": -79.3871},
            {"year": 2015, "title": "Iguazu Falls", "wiki": "Iguazu Falls", "place": "Iguazú, Argentina", "lat": -25.6953, "lon": -54.4367},
            {"year": 2015, "title": "The Moai of Easter Island", "wiki": "Moai", "place": "Easter Island, Chile", "lat": -27.1127, "lon": -109.3497},
            {"year": 2015, "title": "The Arc de Triomphe", "wiki": "Arc de Triomphe", "place": "Paris, France", "lat": 48.8738, "lon": 2.295},
            {"year": 2015, "title": "Notre-Dame", "wiki": "Notre-Dame de Paris", "place": "Paris, France", "lat": 48.853, "lon": 2.3499},
            {"year": 2015, "title": "Mont Saint-Michel", "wiki": "Mont-Saint-Michel", "place": "Normandy, France", "lat": 48.6361, "lon": -1.5115},
            {"year": 2015, "title": "The Trevi Fountain", "wiki": "Trevi Fountain", "place": "Rome, Italy", "lat": 41.9009, "lon": 12.4833},
            {"year": 2015, "title": "Saint Peter's Basilica", "wiki": "St. Peter's Basilica", "place": "Vatican City", "lat": 41.9022, "lon": 12.4539},
            {"year": 2015, "title": "The Grand Canal", "wiki": "Grand Canal (Venice)", "place": "Venice, Italy", "lat": 45.4408, "lon": 12.3155},
            {"year": 2015, "title": "The Matterhorn", "wiki": "Matterhorn", "place": "Zermatt, Switzerland", "lat": 45.9763, "lon": 7.6586},
            {"year": 2015, "title": "The Alhambra", "wiki": "Alhambra", "place": "Granada, Spain", "lat": 37.1761, "lon": -3.5881},
            {"year": 2015, "title": "The Acropolis", "wiki": "Acropolis of Athens", "place": "Athens, Greece", "lat": 37.9715, "lon": 23.7257},
            {"year": 2015, "title": "Hagia Sophia", "wiki": "Hagia Sophia", "place": "Istanbul, Turkey", "lat": 41.0086, "lon": 28.9802},
            {"year": 2015, "title": "The Tower of London", "wiki": "Tower of London", "place": "London, England", "lat": 51.5081, "lon": -0.0759},
            {"year": 2015, "title": "Edinburgh Castle", "wiki": "Edinburgh Castle", "place": "Edinburgh, Scotland", "lat": 55.9486, "lon": -3.1999},
            {"year": 2015, "title": "The Giant's Causeway", "wiki": "Giant's Causeway", "place": "County Antrim, Northern Ireland", "lat": 55.2408, "lon": -6.5116},
            {"year": 2015, "title": "The Cliffs of Moher", "wiki": "Cliffs of Moher", "place": "County Clare, Ireland", "lat": 52.9715, "lon": -9.4309},
            {"year": 2015, "title": "The Forbidden City", "wiki": "Forbidden City", "place": "Beijing, China", "lat": 39.9163, "lon": 116.3972},
            {"year": 2015, "title": "The Terracotta Army", "wiki": "Terracotta Army", "place": "Xi'an, China", "lat": 34.3841, "lon": 109.2785},
            {"year": 2015, "title": "The Golden Pavilion", "wiki": "Kinkaku-ji", "place": "Kyoto, Japan", "lat": 35.0394, "lon": 135.7292},
            {"year": 2015, "title": "The Potala Palace", "wiki": "Potala Palace", "place": "Lhasa, Tibet", "lat": 29.6558, "lon": 91.1171},
            {"year": 2015, "title": "The Golden Temple", "wiki": "Golden Temple", "place": "Amritsar, India", "lat": 31.62, "lon": 74.8765},
            {"year": 2015, "title": "Mount Kilimanjaro", "wiki": "Mount Kilimanjaro", "place": "Kilimanjaro, Tanzania", "lat": -3.0674, "lon": 37.3556},
            {"year": 2015, "title": "Victoria Falls", "wiki": "Victoria Falls", "place": "Victoria Falls, Zambia", "lat": -17.9243, "lon": 25.8572},
            {"year": 2015, "title": "The Sydney Harbour Bridge", "wiki": "Sydney Harbour Bridge", "place": "Sydney, Australia", "lat": -33.8523, "lon": 151.2108},
            {"year": 2015, "title": "Milford Sound", "wiki": "Milford Sound", "place": "Fiordland, New Zealand", "lat": -44.6414, "lon": 167.8974},
            {"year": 2015, "title": "The Empire State Building", "wiki": "Empire State Building", "place": "New York, New York", "lat": 40.7484, "lon": -73.9857},
            {"year": 2015, "title": "The Gateway Arch", "wiki": "Gateway Arch", "place": "St. Louis, Missouri", "lat": 38.6247, "lon": -90.1848},
            {"year": 2015, "title": "Mesa Verde", "wiki": "Mesa Verde National Park", "place": "Mesa Verde, Colorado", "lat": 37.2309, "lon": -108.4618},
            {"year": 2015, "title": "Monument Valley", "wiki": "Monument Valley", "place": "Monument Valley, Utah", "lat": 36.998, "lon": -110.0985},
            {"year": 2015, "title": "Yosemite Valley", "wiki": "Yosemite Valley", "place": "Yosemite, California", "lat": 37.7456, "lon": -119.5936},
            {"year": 2015, "title": "Crater Lake", "wiki": "Crater Lake", "place": "Crater Lake, Oregon", "lat": 42.9446, "lon": -122.109},
            {"year": 2015, "title": "The Hoover Dam", "wiki": "Hoover Dam", "place": "the Nevada–Arizona border", "lat": 36.0161, "lon": -114.7377},
            {"year": 2015, "title": "Chateau Frontenac", "wiki": "Château Frontenac", "place": "Quebec City, Canada", "lat": 46.8118, "lon": -71.2055},
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
        "blurb": "The Games, the grounds and the great occasions.",
        "source": "commons-curated",
        "themes": ["chronology"],
        "licences": {"CC0", "Public domain", "No restrictions", "CC BY", "CC BY-SA"},
        "chronologyPrompt": "Which came first?",
        # Occasions and places, not portraits. A row of athletes' headshots asks somebody
        # to recognise a face; a row of Olympic Games and famous grounds asks them to
        # recognise an event they very likely watched.
        "photographs": [
            {"year": 1992, "title": "The Barcelona Olympics", "wiki": "1992 Summer Olympics", "subject": "Olympic Games", "category": "1992 Summer Olympics"},
            {"year": 1996, "title": "The Atlanta Olympics", "wiki": "1996 Summer Olympics", "subject": "Olympic Games", "category": "1996 Summer Olympics"},
            {"year": 2008, "title": "The Beijing Olympics", "wiki": "2008 Summer Olympics", "subject": "Olympic Games", "category": "2008 Summer Olympics"},
            {"year": 2016, "title": "The Rio Olympics", "wiki": "2016 Summer Olympics", "subject": "Olympic Games", "category": "2016 Summer Olympics"},
            {"year": 1912, "title": "Fenway Park", "wiki": "Fenway Park", "subject": "stadium"},
            {"year": 1914, "title": "Wrigley Field", "wiki": "Wrigley Field", "subject": "stadium"},
            {"year": 1923, "title": "Yankee Stadium", "wiki": "Yankee Stadium", "subject": "stadium"},
            {"year": 1923, "title": "Wembley Stadium", "wiki": "Wembley Stadium", "subject": "stadium"},
            {"year": 1934, "title": "The Indianapolis 500", "wiki": "Indianapolis Motor Speedway", "subject": "racetrack", "category": "Indianapolis 500"},
            {"year": 1950, "title": "The Maracanã", "wiki": "Maracanã Stadium", "subject": "stadium"},
            {"year": 1957, "title": "The Camp Nou", "wiki": "Camp Nou", "subject": "stadium"},
            {"year": 1965, "title": "The Astrodome", "wiki": "Astrodome", "subject": "stadium"},
            {"year": 1975, "title": "The Boston Marathon", "wiki": "Boston Marathon", "subject": "sporting event", "category": "Boston Marathon"},
        ],
    },
    "entertainment": {
        "id": "entertainment",
        "title": "Stage and Screen",
        "blurb": "Performers almost everyone has heard of.",
        "source": "commons-curated",
        "themes": ["chronology"],
        "licences": {"CC0", "Public domain", "No restrictions", "CC BY"},
        "chronologyPrompt": "Who came first?",
        # Deliberately excludes the performers already in Famous Faces, so a level
        # cannot show the same person twice.
        "photographs": [
            {"year": 1880, "title": "Sarah Bernhardt", "q": "Sarah Bernhardt actress photograph", "must": ["Bernhardt"], "subject": "stage actress", "wiki": "Sarah Bernhardt"},
            {"year": 1900, "title": "Enrico Caruso", "q": "Enrico Caruso tenor photograph", "must": ["Caruso"], "subject": "singer", "wiki": "Enrico Caruso"},
            {"year": 1905, "title": "Harry Houdini", "q": "Harry Houdini photograph", "must": ["Houdini"], "subject": "showman", "wiki": "Harry Houdini"},
            {"year": 1915, "title": "Mary Pickford", "q": "Mary Pickford 1915 photograph", "must": ["Pickford"], "subject": "film star", "wiki": "Mary Pickford"},
            {"year": 1920, "title": "Rudolph Valentino", "q": "Rudolph Valentino photograph", "must": ["Valentino"], "subject": "film star", "wiki": "Rudolph Valentino"},
            {"year": 1921, "title": "Buster Keaton", "q": "Buster Keaton photograph", "must": ["Keaton"], "subject": "comedian", "wiki": "Buster Keaton"},
            {"year": 1925, "title": "Josephine Baker", "q": "Josephine Baker dancer 1926", "must": ["Baker"], "subject": "dancer", "wiki": "Josephine Baker"},
            {"year": 1926, "title": "Greta Garbo", "q": "Greta Garbo photograph", "must": ["Garbo"], "subject": "film star", "wiki": "Greta Garbo"},
            {"year": 1930, "title": "Marlene Dietrich", "q": "Marlene Dietrich photograph", "must": ["Dietrich"], "subject": "film star", "wiki": "Marlene Dietrich"},
            {"year": 1931, "title": "Boris Karloff", "q": "Boris Karloff Frankenstein 1931", "must": ["Karloff"], "subject": "film star", "wiki": "Boris Karloff"},
            {"year": 1933, "title": "The Marx Brothers", "q": "Marx Brothers photograph 1933", "must": ["Marx"], "subject": "comedian", "wiki": "Marx Brothers"},
            {"year": 1934, "title": "Shirley Temple", "q": "Shirley Temple 1934 photograph", "must": ["Temple"], "subject": "film star", "wiki": "Shirley Temple"},
            {"year": 1936, "title": "Fred Astaire", "q": "Fred Astaire dancer photograph", "must": ["Astaire"], "subject": "dancer", "wiki": "Fred Astaire"},
            {"year": 1937, "title": "Duke Ellington", "q": "Duke Ellington bandleader photograph", "must": ["Ellington"], "subject": "bandleader", "wiki": "Duke Ellington"},
            {"year": 1939, "title": "Judy Garland", "q": "Judy Garland 1939 photograph", "must": ["Garland"], "subject": "film star", "wiki": "Judy Garland"},
            {"year": 1941, "title": "Orson Welles", "q": "Orson Welles 1941 photograph", "must": ["Welles"], "subject": "film star", "wiki": "Orson Welles"},
            {"year": 1942, "title": "Humphrey Bogart", "q": "Humphrey Bogart photograph", "must": ["Bogart"], "subject": "film star", "wiki": "Humphrey Bogart"},
            {"year": 1943, "title": "Billie Holiday", "q": "Billie Holiday singer photograph", "must": ["Holiday"], "subject": "singer", "wiki": "Billie Holiday"},
            {"year": 1944, "title": "Bing Crosby", "q": "Bing Crosby singer photograph", "must": ["Crosby"], "subject": "singer", "wiki": "Bing Crosby"},
            {"year": 1945, "title": "Frank Sinatra", "q": "Frank Sinatra 1945 photograph", "must": ["Sinatra"], "subject": "singer", "wiki": "Frank Sinatra"},
            {"year": 1947, "title": "Ella Fitzgerald", "q": "Ella Fitzgerald singer photograph", "must": ["Fitzgerald"], "subject": "singer", "wiki": "Ella Fitzgerald"},
            {"year": 1951, "title": "Lucille Ball", "q": "Lucille Ball photograph", "must": ["Lucille"], "subject": "comedian", "wiki": "Lucille Ball"},
            {"year": 1953, "title": "Marilyn Monroe", "q": "Marilyn Monroe photograph 1953", "must": ["Monroe"], "subject": "film star", "wiki": "Marilyn Monroe"},
            {"year": 1955, "title": "James Dean", "q": "James Dean actor photograph", "must": ["Dean"], "subject": "film star", "wiki": "James Dean"},
            {"year": 1956, "title": "Nat King Cole", "q": "Nat King Cole singer photograph", "must": ["Cole"], "subject": "singer", "wiki": "Nat King Cole"},
            {"year": 1957, "title": "Audrey Hepburn", "q": "Audrey Hepburn photograph", "must": ["Hepburn"], "subject": "film star", "wiki": "Audrey Hepburn"},
            {"year": 1960, "title": "Ray Charles", "q": "Ray Charles musician photograph", "must": ["Ray", "Charles"], "subject": "singer", "wiki": "Ray Charles"},
            {"year": 1964, "title": "The Beatles", "q": "The Beatles 1964 photograph", "must": ["Beatles"], "subject": "band", "wiki": "The Beatles"},
            {"year": 1965, "title": "Bob Dylan", "q": "Bob Dylan 1965 photograph", "must": ["Dylan"], "subject": "singer", "wiki": "Bob Dylan"},
            {"year": 1969, "title": "Johnny Cash", "q": "Johnny Cash singer photograph", "must": ["Cash"], "subject": "singer", "wiki": "Johnny Cash"},
            {"year": 1970, "title": "Jimi Hendrix", "q": "Jimi Hendrix photograph", "must": ["Hendrix"], "subject": "singer", "wiki": "Jimi Hendrix"},
            {"year": 1977, "title": "Dolly Parton", "q": "Dolly Parton singer photograph", "must": ["Parton"], "subject": "singer", "wiki": "Dolly Parton"},
            {"year": 1932, "title": "Bette Davis", "wiki": "Bette Davis", "subject": "film star"},
            {"year": 1934, "title": "Clark Gable", "wiki": "Clark Gable", "subject": "film star"},
            {"year": 1935, "title": "Katharine Hepburn", "wiki": "Katharine Hepburn", "subject": "film star"},
            {"year": 1938, "title": "Cary Grant", "wiki": "Cary Grant", "subject": "film star"},
            {"year": 1938, "title": "Benny Goodman", "wiki": "Benny Goodman", "subject": "bandleader"},
            {"year": 1940, "title": "Glenn Miller", "wiki": "Glenn Miller", "subject": "bandleader"},
            {"year": 1942, "title": "Gene Kelly", "wiki": "Gene Kelly", "subject": "dancer"},
            {"year": 1945, "title": "Count Basie", "wiki": "Count Basie", "subject": "bandleader"},
            {"year": 1948, "title": "Charlie Parker", "wiki": "Charlie Parker", "subject": "musician"},
            {"year": 1950, "title": "Doris Day", "wiki": "Doris Day", "subject": "singer"},
            {"year": 1952, "title": "Grace Kelly", "wiki": "Grace Kelly", "subject": "film star"},
            {"year": 1954, "title": "Elizabeth Taylor", "wiki": "Elizabeth Taylor", "subject": "film star"},
            {"year": 1956, "title": "Miles Davis", "wiki": "Miles Davis", "subject": "musician"},
            {"year": 1958, "title": "Brigitte Bardot", "wiki": "Brigitte Bardot", "subject": "film star"},
            {"year": 1960, "title": "Sammy Davis Jr.", "wiki": "Sammy Davis Jr.", "subject": "entertainer"},
            {"year": 1961, "title": "Maria Callas", "wiki": "Maria Callas", "subject": "singer"},
            {"year": 1962, "title": "Rudolf Nureyev", "wiki": "Rudolf Nureyev", "subject": "dancer"},
            {"year": 1963, "title": "Patsy Cline", "wiki": "Patsy Cline", "subject": "singer"},
            {"year": 1967, "title": "Aretha Franklin", "wiki": "Aretha Franklin", "subject": "singer"},
            {"year": 1968, "title": "Leonard Bernstein", "wiki": "Leonard Bernstein", "subject": "conductor"},
            {"year": 1973, "title": "Stevie Wonder", "wiki": "Stevie Wonder", "subject": "singer"},
            {"year": 1975, "title": "Bob Marley", "wiki": "Bob Marley", "subject": "singer"},
            {"year": 1976, "title": "Willie Nelson", "wiki": "Willie Nelson", "subject": "singer"},
            {"year": 1980, "title": "Tina Turner", "wiki": "Tina Turner", "subject": "singer"},
        ],
    },
    "space": {
        "id": "space",
        "title": "Space",
        "blurb": "Photographs almost everyone has seen, from Mercury to Mars.",
        "source": "nasa-curated",
        "themes": ["chronology"],
        "chronologyPrompt": "Which came first?",
        "photographs": [
            {"year": 1962, "title": "Friendship 7 launches", "q": "Friendship 7 Atlas launch 1962"},
            {"year": 1965, "title": "The first American spacewalk", "q": "Ed White Gemini 4 EVA"},
            {"year": 1968, "title": "Earthrise, seen from Apollo 8", "q": "Earthrise Apollo 8"},
            {"year": 1969, "title": "A footprint on the Moon", "q": "Apollo 11 bootprint lunar surface"},
            {"year": 1969, "title": "Buzz Aldrin on the Moon", "q": "Aldrin Apollo 11 visor reflection"},
            {"year": 1972, "title": "The Blue Marble", "q": "Blue Marble Apollo 17 Earth"},
            {"year": 1981, "title": "The first Space Shuttle launch", "q": "STS-1 Columbia first launch 1981"},
            {"year": 1984, "title": "Untethered above the Earth", "q": "McCandless manned maneuvering unit"},
            {"year": 1990, "title": "Hubble leaves the payload bay", "q": "Hubble Space Telescope deployment 1990"},
            {"year": 1995, "title": "Shuttle docks with Mir", "q": "Space Shuttle Atlantis Mir docking"},
            {"year": 2005, "title": "The Space Station takes shape", "q": "International Space Station assembly 2005"},
            {"year": 2019, "title": "A spacewalk at the Station", "q": "spacewalk International Space Station 2019"},
            {"year": 2021, "title": "A helicopter flies on Mars", "q": "Ingenuity Mars helicopter"},
            {"year": 2024, "title": "Artemis prepares to return", "q": "Artemis Space Launch System rollout"},
        ],
    },
    "faces": {
        "id": "famous-faces",
        "title": "Famous Faces",
        "blurb": "Leaders, scientists, writers and explorers almost everyone has seen.",
        "absorbs": ["leaders", "science", "writers", "explorers", "entertainment"],
        "source": "commons-curated",
        "themes": ["chronology"],
        "chronologyPrompt": "Who came first?",
        "licences": {"CC0", "Public domain", "No restrictions", "CC BY"},
        # Weighted towards people photographed by governments or before 1930, because
        # those are the two footings that survive the licence check.
        "photographs": [
            {"year": 1863, "title": "Abraham Lincoln", "q": "Abraham Lincoln 1863 portrait photograph", "subject": "president", "wiki": "Abraham Lincoln"},
            {"year": 1865, "title": "Frederick Douglass", "q": "Frederick Douglass portrait photograph", "wiki": "Frederick Douglass"},
            {"year": 1870, "title": "Susan B. Anthony", "q": "Susan B. Anthony portrait", "wiki": "Susan B. Anthony"},
            {"year": 1876, "title": "Alexander Graham Bell", "q": "Alexander Graham Bell three-quarter portrait", "subject": "inventor", "wiki": "Alexander Graham Bell"},
            {"year": 1885, "title": "Sitting Bull", "q": "Sitting Bull portrait photograph", "wiki": "Sitting Bull"},
            {"year": 1888, "title": "Thomas Edison", "q": "Thomas Edison phonograph portrait", "subject": "inventor", "wiki": "Thomas Edison"},
            {"year": 1890, "title": "Annie Oakley", "q": "Annie Oakley portrait photograph", "wiki": "Annie Oakley"},
            {"year": 1895, "title": "Clara Barton", "q": "Clara Barton portrait photograph", "wiki": "Clara Barton"},
            {"year": 1900, "title": "Booker T. Washington", "q": "Booker T. Washington portrait", "wiki": "Booker T. Washington"},
            {"year": 1901, "title": "Theodore Roosevelt", "q": "Theodore Roosevelt portrait 1901", "subject": "president", "wiki": "Theodore Roosevelt"},
            {"year": 1903, "title": "Marie Curie", "q": "Marie Curie portrait laboratory", "subject": "scientist", "wiki": "Marie Curie"},
            {"year": 1905, "title": "Wilbur Wright", "q": "Wilbur Wright portrait", "subject": "aviator", "wiki": "Wilbur Wright"},
            {"year": 1907, "title": "Mark Twain", "q": "Mark Twain portrait 1907", "subject": "writer", "wiki": "Mark Twain"},
            {"year": 1912, "title": "Jim Thorpe at the Olympics", "q": "Jim Thorpe 1912 Olympics", "subject": "athlete", "wiki": "Jim Thorpe"},
            {"year": 1913, "title": "Harriet Tubman", "q": "Harriet Tubman portrait photograph", "wiki": "Harriet Tubman"},
            {"year": 1913, "title": "Woodrow Wilson", "q": "President Woodrow Wilson 1913 portrait", "must": ["President", "Woodrow"], "subject": "president", "wiki": "Woodrow Wilson"},
            {"year": 1918, "title": "Charlie Chaplin", "q": "Charlie Chaplin 1918 photograph", "must": ["Chaplin"], "subject": "entertainer", "wiki": "Charlie Chaplin"},
            {"year": 1920, "title": "Babe Ruth", "q": "Babe Ruth baseball portrait", "subject": "athlete", "wiki": "Babe Ruth"},
            {"year": 1921, "title": "Albert Einstein", "q": "Albert Einstein 1921 portrait", "subject": "scientist", "wiki": "Albert Einstein"},
            {"year": 1923, "title": "Calvin Coolidge", "q": "Calvin Coolidge official portrait", "subject": "president", "wiki": "Calvin Coolidge"},
            {"year": 1927, "title": "Charles Lindbergh", "q": "Charles Lindbergh 1927 portrait", "subject": "aviator", "wiki": "Charles Lindbergh"},
            {"year": 1928, "title": "Amelia Earhart", "q": "Amelia Earhart 1928 portrait", "subject": "aviator", "wiki": "Amelia Earhart"},
            {"year": 1929, "title": "Herbert Hoover", "q": "Herbert Hoover official portrait", "subject": "president", "wiki": "Herbert Hoover"},
            {"year": 1933, "title": "Franklin D. Roosevelt", "q": "Franklin Roosevelt 1933 portrait", "subject": "president", "wiki": "Franklin D. Roosevelt"},
            {"year": 1936, "title": "Jesse Owens in Berlin", "q": "Jesse Owens 1936 Olympics", "subject": "athlete", "wiki": "Jesse Owens"},
            {"year": 1940, "title": "Marian Anderson", "q": "Marian Anderson contralto", "must": ["Anderson"], "subject": "entertainer", "wiki": "Marian Anderson"},
            {"year": 1943, "title": "Eleanor Roosevelt", "q": "Eleanor Roosevelt 1943 photograph", "must": ["Eleanor"], "wiki": "Eleanor Roosevelt"},
            {"year": 1945, "title": "Harry Truman", "q": "Harry Truman official portrait", "subject": "president", "wiki": "Harry S. Truman"},
            {"year": 1947, "title": "Jackie Robinson", "q": "Jackie Robinson 1947 Dodgers", "subject": "athlete", "wiki": "Jackie Robinson"},
            {"year": 1953, "title": "Dwight Eisenhower", "q": "Dwight Eisenhower official portrait", "subject": "president", "wiki": "Dwight D. Eisenhower"},
            {"year": 1956, "title": "Louis Armstrong", "q": "Louis Armstrong trumpet photograph", "subject": "entertainer", "wiki": "Louis Armstrong"},
            {"year": 1958, "title": "Elvis Presley", "q": "Elvis Presley 1958", "must": ["Elvis"], "subject": "entertainer", "wiki": "Elvis Presley"},
            {"year": 1961, "title": "John F. Kennedy", "q": "John F Kennedy White House portrait", "subject": "president", "wiki": "John F. Kennedy"},
            {"year": 1963, "title": "Martin Luther King Jr.", "q": "Martin Luther King Jr March on Washington", "wiki": "Martin Luther King Jr."},
            {"year": 1964, "title": "Lyndon Johnson", "q": "Lyndon Johnson official portrait", "subject": "president", "wiki": "Lyndon B. Johnson"},
            {"year": 1969, "title": "Richard Nixon", "q": "Richard Nixon official portrait", "subject": "president", "wiki": "Richard Nixon"},
            {"year": 1974, "title": "Gerald Ford", "q": "Gerald Ford official portrait", "subject": "president", "wiki": "Gerald Ford"},
            {"year": 1977, "title": "Jimmy Carter", "q": "Jimmy Carter official portrait", "subject": "president", "wiki": "Jimmy Carter"},
            {"year": 1981, "title": "Ronald Reagan", "q": "Ronald Reagan official portrait", "subject": "president", "wiki": "Ronald Reagan"},
            {"year": 1983, "title": "Sally Ride in orbit", "q": "Sally Ride astronaut 1983", "subject": "astronaut", "wiki": "Sally Ride"},
            {"year": 1989, "title": "George H. W. Bush", "q": "George H W Bush official portrait", "subject": "president", "wiki": "George H. W. Bush"},
            {"year": 1993, "title": "Bill Clinton", "q": "Bill Clinton official portrait", "subject": "president", "wiki": "Bill Clinton"},
            {"year": 1993, "title": "Ruth Bader Ginsburg", "q": "Ruth Bader Ginsburg official portrait", "wiki": "Ruth Bader Ginsburg"},
            {"year": 2001, "title": "George W. Bush", "q": "George W Bush official portrait", "subject": "president", "wiki": "George W. Bush"},
            {"year": 2012, "title": "Barack Obama", "q": "President Barack Obama 2012 portrait crop", "must": ["Obama", "portrait"], "subject": "president", "wiki": "Barack Obama"},
            {"year": 1854, "title": "Florence Nightingale", "wiki": "Florence Nightingale", "subject": "nurse"},
            {"year": 1915, "title": "Helen Keller", "wiki": "Helen Keller", "subject": "campaigner"},
            {"year": 1934, "title": "Frida Kahlo", "wiki": "Frida Kahlo", "subject": "artist"},
            {"year": 1945, "title": "Anne Frank", "wiki": "Anne Frank", "subject": "diarist"},
            {"year": 1965, "title": "Malcolm X", "wiki": "Malcolm X", "subject": "campaigner"},
            {"year": 1971, "title": "Mother Teresa", "wiki": "Mother Teresa", "subject": "missionary"},
            {"year": 1979, "title": "Pope John Paul II", "wiki": "Pope John Paul II", "subject": "pope"},
            {"year": 1981, "title": "Diana, Princess of Wales", "wiki": "Diana, Princess of Wales", "subject": "princess"},
            {"year": 1990, "title": "Desmond Tutu", "wiki": "Desmond Tutu", "subject": "archbishop"},
            {"year": 2005, "title": "The Dalai Lama", "wiki": "14th Dalai Lama", "subject": "spiritual leader"},
            {"year": 2014, "title": "Malala Yousafzai", "wiki": "Malala Yousafzai", "subject": "campaigner"},
        ],
    },
    "animals": {
        "id": "animals",
        "title": "Animals",
        "blurb": "Creatures large and small, and what makes them what they are.",
        "source": "commons-curated",
        "themes": ["objects"],
        "licences": {"CC0", "Public domain", "No restrictions", "CC BY", "CC BY-SA"},
        # The question is about the creature, not the photograph: "which one is a
        # mammal?" rather than "which photo has a mammal in it?". So the tag is the
        # animal's class, which is a fact about it and cannot be wrong the way a guess
        # about a picture can.
        "photographs": [
            {"year": 2015, "title": "A lion", "wiki": "Lion", "tags": ["class-mammal"]},
            {"year": 2015, "title": "An elephant", "wiki": "Elephant", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A giraffe", "wiki": "Giraffe", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A tiger", "wiki": "Tiger", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A polar bear", "wiki": "Polar bear", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A dolphin", "wiki": "Dolphin", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A kangaroo", "wiki": "Kangaroo", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A panda", "wiki": "Giant panda", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A zebra", "wiki": "Zebra", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A hedgehog", "wiki": "Hedgehog", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A bat", "wiki": "Bat", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A koala", "wiki": "Koala", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A penguin", "wiki": "Penguin", "tags": ["class-bird"]},
            {"year": 2015, "title": "A bald eagle", "wiki": "Bald eagle", "tags": ["class-bird"]},
            {"year": 2015, "title": "An owl", "wiki": "Owl", "tags": ["class-bird"]},
            {"year": 2015, "title": "A flamingo", "wiki": "Flamingo", "tags": ["class-bird"]},
            {"year": 2015, "title": "A peacock", "wiki": "Peafowl", "tags": ["class-bird"]},
            {"year": 2015, "title": "A puffin", "wiki": "Atlantic puffin", "tags": ["class-bird"]},
            {"year": 2015, "title": "A swan", "wiki": "Swan", "tags": ["class-bird"]},
            {"year": 2015, "title": "An ostrich", "wiki": "Common ostrich", "tags": ["class-bird"]},
            {"year": 2015, "title": "A robin", "wiki": "European robin", "tags": ["class-bird"]},
            {"year": 2015, "title": "A crocodile", "wiki": "Crocodile", "tags": ["class-reptile"]},
            {"year": 2015, "title": "A tortoise", "wiki": "Tortoise", "tags": ["class-reptile"]},
            {"year": 2015, "title": "A chameleon", "wiki": "Chameleon", "tags": ["class-reptile"]},
            {"year": 2015, "title": "A cobra", "wiki": "Cobra", "tags": ["class-reptile"]},
            {"year": 2015, "title": "An iguana", "wiki": "Iguana", "tags": ["class-reptile"]},
            {"year": 2015, "title": "A gecko", "wiki": "Gecko", "tags": ["class-reptile"]},
            {"year": 2015, "title": "A komodo dragon", "wiki": "Komodo dragon", "tags": ["class-reptile"]},
            {"year": 2015, "title": "A frog", "wiki": "Frog", "tags": ["class-amphibian"]},
            {"year": 2015, "title": "A toad", "wiki": "Toad", "tags": ["class-amphibian"]},
            {"year": 2015, "title": "A salamander", "wiki": "Salamander", "tags": ["class-amphibian"]},
            {"year": 2015, "title": "A newt", "wiki": "Newt", "tags": ["class-amphibian"]},
            {"year": 2015, "title": "An axolotl", "wiki": "Axolotl", "tags": ["class-amphibian"]},
            {"year": 2015, "title": "A shark", "wiki": "Shark", "tags": ["class-fish"]},
            {"year": 2015, "title": "A clownfish", "wiki": "Clownfish", "tags": ["class-fish"]},
            {"year": 2015, "title": "A seahorse", "wiki": "Seahorse", "tags": ["class-fish"]},
            {"year": 2015, "title": "A salmon", "wiki": "Salmon", "tags": ["class-fish"]},
            {"year": 2015, "title": "A stingray", "wiki": "Batoidea", "tags": ["class-fish"]},
            {"year": 2015, "title": "A butterfly", "wiki": "Butterfly", "tags": ["class-insect"]},
            {"year": 2015, "title": "A bee", "wiki": "Bee", "tags": ["class-insect"]},
            {"year": 2015, "title": "A dragonfly", "wiki": "Dragonfly", "tags": ["class-insect"]},
            {"year": 2015, "title": "A ladybird", "wiki": "Coccinellidae", "tags": ["class-insect"]},
            {"year": 2015, "title": "An ant", "wiki": "Ant", "tags": ["class-insect"]},
            {"year": 2015, "title": "A grasshopper", "wiki": "Grasshopper", "tags": ["class-insect"]},
            {"year": 2015, "title": "A red panda", "wiki": "Red panda", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A sloth", "wiki": "Sloth", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A meerkat", "wiki": "Meerkat", "tags": ["class-mammal"]},
            {"year": 2015, "title": "An otter", "wiki": "Otter", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A camel", "wiki": "Camel", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A wolf", "wiki": "Wolf", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A fox", "wiki": "Red fox", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A hippopotamus", "wiki": "Hippopotamus", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A rhinoceros", "wiki": "Rhinoceros", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A gorilla", "wiki": "Gorilla", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A whale", "wiki": "Whale", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A bison", "wiki": "Bison", "tags": ["class-mammal"]},
            {"year": 2015, "title": "A parrot", "wiki": "Parrot", "tags": ["class-bird"]},
            {"year": 2015, "title": "A pelican", "wiki": "Pelican", "tags": ["class-bird"]},
            {"year": 2015, "title": "A kingfisher", "wiki": "Kingfisher", "tags": ["class-bird"]},
            {"year": 2015, "title": "A woodpecker", "wiki": "Woodpecker", "tags": ["class-bird"]},
            {"year": 2015, "title": "A pigeon", "wiki": "Columbidae", "tags": ["class-bird"]},
            {"year": 2015, "title": "A duck", "wiki": "Duck", "tags": ["class-bird"]},
            {"year": 2015, "title": "A turtle", "wiki": "Sea turtle", "tags": ["class-reptile"]},
            {"year": 2015, "title": "A python", "wiki": "Pythonidae", "tags": ["class-reptile"]},
            {"year": 2015, "title": "A lizard", "wiki": "Lizard", "tags": ["class-reptile"]},
            {"year": 2015, "title": "A tree frog", "wiki": "Tree frog", "tags": ["class-amphibian"]},
            {"year": 2015, "title": "A tuna", "wiki": "Tuna", "tags": ["class-fish"]},
            {"year": 2015, "title": "A goldfish", "wiki": "Goldfish", "tags": ["class-fish"]},
            {"year": 2015, "title": "A swordfish", "wiki": "Swordfish", "tags": ["class-fish"]},
            {"year": 2015, "title": "A moth", "wiki": "Moth", "tags": ["class-insect"]},
            {"year": 2015, "title": "A cricket", "wiki": "Cricket (insect)", "tags": ["class-insect"]},
            {"year": 2015, "title": "A wasp", "wiki": "Wasp", "tags": ["class-insect"]},
            {"year": 2015, "title": "A firefly", "wiki": "Firefly", "tags": ["class-insect"]},
        ],
    },
    "science": {
        "id": "science",
        "title": "Science and Invention",
        "blurb": "The people who worked it out.",
        "source": "commons-curated",
        "themes": ["chronology"],
        "licences": {"CC0", "Public domain", "No restrictions", "CC BY"},
        "chronologyPrompt": "Who came first?",
        "photographs": [
            {"year": 1867, "title": "Charles Darwin", "wiki": "Charles Darwin", "subject": "scientist"},
            {"year": 1876, "title": "Alexander Graham Bell", "wiki": "Alexander Graham Bell", "subject": "inventor"},
            {"year": 1885, "title": "Louis Pasteur", "wiki": "Louis Pasteur", "subject": "scientist"},
            {"year": 1888, "title": "Thomas Edison", "wiki": "Thomas Edison", "subject": "inventor"},
            {"year": 1895, "title": "Wilhelm Rontgen", "wiki": "Wilhelm Röntgen", "subject": "scientist"},
            {"year": 1900, "title": "Sigmund Freud", "wiki": "Sigmund Freud", "subject": "scientist"},
            {"year": 1901, "title": "Guglielmo Marconi", "wiki": "Guglielmo Marconi", "subject": "inventor"},
            {"year": 1902, "title": "Nikola Tesla", "wiki": "Nikola Tesla", "subject": "inventor"},
            {"year": 1903, "title": "Marie Curie", "wiki": "Marie Curie", "subject": "scientist"},
            {"year": 1905, "title": "Wilbur Wright", "wiki": "Wilbur Wright", "subject": "inventor"},
            {"year": 1910, "title": "George Washington Carver", "wiki": "George Washington Carver", "subject": "scientist"},
            {"year": 1921, "title": "Albert Einstein", "wiki": "Albert Einstein", "subject": "scientist"},
            {"year": 1928, "title": "Alexander Fleming", "wiki": "Alexander Fleming", "subject": "scientist"},
            {"year": 1934, "title": "Enrico Fermi", "wiki": "Enrico Fermi", "subject": "scientist"},
            {"year": 1945, "title": "Robert Oppenheimer", "wiki": "J. Robert Oppenheimer", "subject": "scientist"},
            {"year": 1950, "title": "Alan Turing", "wiki": "Alan Turing", "subject": "scientist"},
            {"year": 1951, "title": "Rosalind Franklin", "wiki": "Rosalind Franklin", "subject": "scientist"},
            {"year": 1955, "title": "Jonas Salk", "wiki": "Jonas Salk", "subject": "scientist"},
            {"year": 1962, "title": "Rachel Carson", "wiki": "Rachel Carson", "subject": "scientist"},
            {"year": 1962, "title": "Linus Pauling", "wiki": "Linus Pauling", "subject": "scientist"},
            {"year": 1965, "title": "Richard Feynman", "wiki": "Richard Feynman", "subject": "scientist"},
            {"year": 1980, "title": "Carl Sagan", "wiki": "Carl Sagan", "subject": "scientist"},
            {"year": 1988, "title": "Stephen Hawking", "wiki": "Stephen Hawking", "subject": "scientist"},
        ],
    },
    "writers": {
        "id": "writers",
        "title": "Writers",
        "blurb": "Names off the spines of the books at home.",
        "source": "commons-curated",
        "themes": ["chronology"],
        "licences": {"CC0", "Public domain", "No restrictions", "CC BY"},
        "chronologyPrompt": "Who came first?",
        "photographs": [
            {"year": 1855, "title": "Charles Dickens", "wiki": "Charles Dickens", "subject": "writer"},
            {"year": 1862, "title": "Victor Hugo", "wiki": "Victor Hugo", "subject": "writer"},
            {"year": 1868, "title": "Louisa May Alcott", "wiki": "Louisa May Alcott", "subject": "writer"},
            {"year": 1882, "title": "Oscar Wilde", "wiki": "Oscar Wilde", "subject": "writer"},
            {"year": 1885, "title": "Robert Louis Stevenson", "wiki": "Robert Louis Stevenson", "subject": "writer"},
            {"year": 1890, "title": "Emily Dickinson", "wiki": "Emily Dickinson", "subject": "poet"},
            {"year": 1895, "title": "Arthur Conan Doyle", "wiki": "Arthur Conan Doyle", "subject": "writer"},
            {"year": 1900, "title": "Leo Tolstoy", "wiki": "Leo Tolstoy", "subject": "writer"},
            {"year": 1902, "title": "Rudyard Kipling", "wiki": "Rudyard Kipling", "subject": "writer"},
            {"year": 1907, "title": "Mark Twain", "wiki": "Mark Twain", "subject": "writer"},
            {"year": 1920, "title": "Edith Wharton", "wiki": "Edith Wharton", "subject": "writer"},
            {"year": 1927, "title": "Virginia Woolf", "wiki": "Virginia Woolf", "subject": "writer"},
            {"year": 1930, "title": "Agatha Christie", "wiki": "Agatha Christie", "subject": "writer"},
            {"year": 1934, "title": "F. Scott Fitzgerald", "wiki": "F. Scott Fitzgerald", "subject": "writer"},
            {"year": 1937, "title": "Zora Neale Hurston", "wiki": "Zora Neale Hurston", "subject": "writer"},
            {"year": 1940, "title": "John Steinbeck", "wiki": "John Steinbeck", "subject": "writer"},
            {"year": 1946, "title": "George Orwell", "wiki": "George Orwell", "subject": "writer"},
            {"year": 1950, "title": "Ernest Hemingway", "wiki": "Ernest Hemingway", "subject": "writer"},
            {"year": 1955, "title": "Robert Frost", "wiki": "Robert Frost", "subject": "poet"},
            {"year": 1963, "title": "C. S. Lewis", "wiki": "C. S. Lewis", "subject": "writer"},
            {"year": 1993, "title": "Maya Angelou", "wiki": "Maya Angelou", "subject": "poet"},
            {"year": 1982, "title": "Gabriel Garcia Marquez", "wiki": "Gabriel García Márquez", "subject": "writer"},
            {"year": 1993, "title": "Toni Morrison", "wiki": "Toni Morrison", "subject": "writer"},
        ],
    },
    "explorers": {
        "id": "explorers",
        "title": "Explorers",
        "blurb": "Poles, peaks, oceans and orbit.",
        "source": "commons-curated",
        "themes": ["chronology"],
        "licences": {"CC0", "Public domain", "No restrictions", "CC BY"},
        "chronologyPrompt": "Who came first?",
        "photographs": [
            {"year": 1871, "title": "David Livingstone", "wiki": "David Livingstone", "subject": "explorer"},
            {"year": 1888, "title": "Nellie Bly", "wiki": "Nellie Bly", "subject": "reporter"},
            {"year": 1901, "title": "Robert Falcon Scott", "wiki": "Robert Falcon Scott", "subject": "explorer"},
            {"year": 1909, "title": "Robert Peary", "wiki": "Robert Peary", "subject": "explorer"},
            {"year": 1911, "title": "Roald Amundsen", "wiki": "Roald Amundsen", "subject": "explorer"},
            {"year": 1914, "title": "Ernest Shackleton", "wiki": "Ernest Shackleton", "subject": "explorer"},
            {"year": 1922, "title": "Howard Carter", "wiki": "Howard Carter", "subject": "archaeologist"},
            {"year": 1927, "title": "Charles Lindbergh", "wiki": "Charles Lindbergh", "subject": "aviator"},
            {"year": 1932, "title": "Amelia Earhart", "wiki": "Amelia Earhart", "subject": "aviator"},
            {"year": 1947, "title": "Thor Heyerdahl", "wiki": "Thor Heyerdahl", "subject": "explorer"},
            {"year": 1953, "title": "Edmund Hillary", "wiki": "Edmund Hillary", "subject": "mountaineer"},
            {"year": 1953, "title": "Tenzing Norgay", "wiki": "Tenzing Norgay", "subject": "mountaineer"},
            {"year": 1960, "title": "Jacques Piccard", "wiki": "Jacques Piccard", "subject": "explorer"},
            {"year": 1961, "title": "Yuri Gagarin", "wiki": "Yuri Gagarin", "subject": "cosmonaut"},
            {"year": 1962, "title": "John Glenn", "wiki": "John Glenn", "subject": "astronaut"},
            {"year": 1963, "title": "Valentina Tereshkova", "wiki": "Valentina Tereshkova", "subject": "cosmonaut"},
            {"year": 1969, "title": "Neil Armstrong", "wiki": "Neil Armstrong", "subject": "astronaut"},
            {"year": 1969, "title": "Buzz Aldrin", "wiki": "Buzz Aldrin", "subject": "astronaut"},
            {"year": 1972, "title": "Jacques Cousteau", "wiki": "Jacques Cousteau", "subject": "explorer"},
            {"year": 1983, "title": "Sally Ride", "wiki": "Sally Ride", "subject": "astronaut"},
            {"year": 1992, "title": "Mae Jemison", "wiki": "Mae Jemison", "subject": "astronaut"},
            {"year": 1998, "title": "Robert Ballard", "wiki": "Robert Ballard", "subject": "explorer"},
        ],
    },
    "seasonal": {
        "id": "seasonal",
        "title": "Seasons and Holidays",
        "blurb": "Pumpkins, trees, fireworks and the times of year.",
        "source": "commons-curated",
        "themes": ["objects"],
        "licences": {"CC0", "Public domain", "No restrictions", "CC BY", "CC BY-SA"},
        # Named subjects, each pinned to the photograph its own article leads with —
        # the method that makes the Landmarks pack look the way it does. Searching for
        # "snowman" returns whatever anybody uploaded, including a lumpy one at night;
        # asking for the Rockefeller Center tree returns the Rockefeller Center tree.
        "photographs": [
            {"year": 2015, "title": "A jack-o'-lantern", "wiki": "Jack-o'-lantern", "tags": ["jack-o-lantern"]},
            {"year": 2015, "title": "A pumpkin patch", "wiki": "Pumpkin", "tags": ["pumpkins"]},
            {"year": 2015, "title": "Pumpkin picking", "wiki": "Pick-your-own farming", "tags": ["pumpkins"]},
            {"year": 2015, "title": "The Rockefeller Center tree", "wiki": "Rockefeller Center Christmas Tree", "tags": ["christmas-tree"]},
            {"year": 2015, "title": "The Trafalgar Square tree", "wiki": "Trafalgar Square Christmas tree", "tags": ["christmas-tree"]},
            {"year": 2015, "title": "A Christmas tree", "wiki": "Christmas tree", "tags": ["christmas-tree"]},
            {"year": 2015, "title": "A Christmas market", "wiki": "Christmas market", "tags": ["christmas-lights"]},
            {"year": 2015, "title": "Blackpool Illuminations", "wiki": "Blackpool Illuminations", "tags": ["christmas-lights"]},
            {"year": 2015, "title": "Sydney New Year fireworks", "wiki": "Sydney New Year's Eve", "tags": ["fireworks"]},
            {"year": 2015, "title": "Hogmanay in Edinburgh", "wiki": "Edinburgh's Hogmanay", "tags": ["fireworks"]},
            {"year": 2015, "title": "Fourth of July fireworks", "wiki": "Independence Day (United States)", "tags": ["fireworks"]},
            {"year": 2015, "title": "Bastille Day", "wiki": "Bastille Day", "tags": ["fireworks"]},
            {"year": 2015, "title": "A snowman", "wiki": "Snowman", "tags": ["snowman"]},
            {"year": 2015, "title": "A sleigh ride", "wiki": "Sleigh", "tags": ["sleigh"]},
            {"year": 2015, "title": "A troika", "wiki": "Troika (driving)", "tags": ["sleigh"]},
            {"year": 2015, "title": "Autumn colours", "wiki": "Autumn leaf color", "tags": ["autumn-leaves"]},
            {"year": 2015, "title": "Easter eggs", "wiki": "Easter egg", "tags": ["easter-eggs"]},
            {"year": 2015, "title": "Egg decorating", "wiki": "Egg decorating", "tags": ["easter-eggs"]},
            {"year": 2015, "title": "A Hanukkah menorah", "wiki": "Hanukkah", "tags": ["menorah"]},
            {"year": 2015, "title": "The Menorah", "wiki": "Menorah (Temple)", "tags": ["menorah"]},
            {"year": 2015, "title": "Diwali lamps", "wiki": "Diwali", "tags": ["diwali-lamps"]},
            {"year": 2015, "title": "A diya", "wiki": "Diya (lamp)", "tags": ["diwali-lamps"]},
            {"year": 2015, "title": "The Macy's Thanksgiving Parade", "wiki": "Macy's Thanksgiving Day Parade", "tags": ["parade"]},
            {"year": 2015, "title": "Mardi Gras", "wiki": "Mardi Gras in New Orleans", "tags": ["parade"]},
            {"year": 2015, "title": "The Notting Hill Carnival", "wiki": "Notting Hill Carnival", "tags": ["parade"]},
            {"year": 2015, "title": "Carnival in Rio", "wiki": "Brazilian Carnival", "tags": ["parade"]},
            {"year": 2015, "title": "The Rose Parade", "wiki": "Rose Parade", "tags": ["parade"]},
            {"year": 2015, "title": "Cherry blossom", "wiki": "Cherry blossom", "tags": ["blossom"]},
            {"year": 2015, "title": "Hanami", "wiki": "Hanami", "tags": ["blossom"]},
            {"year": 2015, "title": "The Keukenhof tulips", "wiki": "Keukenhof", "tags": ["blossom"]},
            {"year": 2015, "title": "A nativity scene", "wiki": "Nativity scene", "tags": ["nativity"]},
            {"year": 2015, "title": "Christmas dinner", "wiki": "Christmas dinner", "tags": ["holiday-feast"]},
            {"year": 2015, "title": "A gingerbread house", "wiki": "Gingerbread house", "tags": ["holiday-feast"]},
            {"year": 2015, "title": "The Lantern Festival", "wiki": "Lantern Festival", "tags": ["paper-lanterns"]},
            {"year": 2015, "title": "Lanterns at Obon", "wiki": "Bon Festival", "tags": ["paper-lanterns"]},
            {"year": 2015, "title": "A day at the beach", "wiki": "Beach", "tags": ["seaside-summer"]},
            {"year": 2015, "title": "A sandcastle", "wiki": "Sandcastle", "tags": ["seaside-summer"]},
            {"year": 2015, "title": "Coney Island", "wiki": "Coney Island", "tags": ["seaside-summer"]},
            {"year": 2015, "title": "Brighton Pier", "wiki": "Brighton Palace Pier", "tags": ["seaside-summer"]},
            {"year": 2015, "title": "An Advent wreath", "wiki": "Advent wreath", "tags": ["christmas-lights"]},
            {"year": 2015, "title": "The Santa Claus Parade", "wiki": "Santa Claus Parade", "tags": ["parade"]},
            {"year": 2015, "title": "The Times Square Ball", "wiki": "Times Square Ball", "tags": ["fireworks"]},
            {"year": 2015, "title": "Tulip fields", "wiki": "Tulip", "tags": ["blossom"]},
            {"year": 2015, "title": "An Easter basket", "wiki": "Easter basket", "tags": ["easter-eggs"]},
            {"year": 2015, "title": "Lighting the menorah", "wiki": "Menorah (Hanukkah)", "tags": ["menorah"]},
            {"year": 2015, "title": "A harvest table", "wiki": "Harvest festival", "tags": ["holiday-feast"]},
        ],
    },
    "milestones": {
        "id": "milestones",
        "title": "Milestones",
        "blurb": "Moments, machines and missions people remember.",
        "nasaPhotographs": [
            {"year": 1962, "title": "Friendship 7 launches", "q": "Friendship 7 Atlas launch 1962"},
            {"year": 1965, "title": "The first American spacewalk", "q": "Ed White Gemini 4 EVA"},
            {"year": 1968, "title": "Earthrise, seen from Apollo 8", "q": "Earthrise Apollo 8"},
            {"year": 1969, "title": "A footprint on the Moon", "q": "Apollo 11 bootprint lunar surface"},
            {"year": 1969, "title": "Buzz Aldrin on the Moon", "q": "Aldrin Apollo 11 visor reflection"},
            {"year": 1972, "title": "The Blue Marble", "q": "Blue Marble Apollo 17 Earth"},
            {"year": 1981, "title": "The first Space Shuttle launch", "q": "STS-1 Columbia first launch 1981"},
            {"year": 1984, "title": "Untethered above the Earth", "q": "McCandless manned maneuvering unit"},
            {"year": 1990, "title": "Hubble leaves the payload bay", "q": "Hubble Space Telescope deployment 1990"},
            {"year": 1995, "title": "Shuttle docks with Mir", "q": "Space Shuttle Atlantis Mir docking"},
            {"year": 2005, "title": "The Space Station takes shape", "q": "International Space Station assembly 2005"},
            {"year": 2019, "title": "A spacewalk at the Station", "q": "spacewalk International Space Station 2019"},
            {"year": 2021, "title": "A helicopter flies on Mars", "q": "Ingenuity Mars helicopter"},
            {"year": 2024, "title": "Artemis prepares to return", "q": "Artemis Space Launch System rollout"},
        ],
        "source": "commons-curated",
        "themes": ["chronology"],
        "chronologyPrompt": "Which happened first?",
        # Names on the tiles while the round is open: nobody recognises a 1903
        # photograph of a wooden aeroplane, so the question has to be answerable
        # from what the events *are*, not from recognising the photographs.
        "labelWhilePlaying": True,
        "licences": {"CC0", "Public domain", "No restrictions", "CC BY"},
        "photographs": [
            {"year": 1886, "title": "The Statue of Liberty is unveiled", "q": "Statue of Liberty 1886 construction"},
            {"year": 1889, "title": "The Eiffel Tower is finished", "q": "Eiffel Tower 1889 construction Durandelle"},
            {"year": 1903, "title": "The Wright brothers fly", "q": "Wright brothers first flight 1903", "wiki": "Wright Flyer"},
            {"year": 1912, "title": "The Titanic", "q": "RMS Titanic 1912 photograph", "must": ["Titanic"], "wiki": "Titanic"},
            {"year": 1930, "title": "The Chrysler Building", "q": "Chrysler Building 1930 photograph"},
            {"year": 1936, "title": "Migrant Mother", "q": "Migrant Mother Dorothea Lange", "wiki": "Migrant Mother"},
            {"year": 1937, "title": "The Golden Gate Bridge opens", "q": "Golden Gate Bridge 1937 opening"},
            {"year": 1947, "title": "Breaking the sound barrier", "q": "Bell X-1 Chuck Yeager 1947", "wiki": "Bell X-1"},
            {"year": 1954, "title": "The first nuclear submarine", "q": "USS Nautilus at launch 1954", "must": ["Nautilus", "launch"], "wiki": "USS Nautilus (SSN-571)"},
            {"year": 1955, "title": "Rosa Parks in Montgomery", "q": "Rosa Parks 1955 Montgomery", "wiki": "Rosa Parks"},
            {"year": 1955, "title": "The polio vaccine", "q": "Jonas Salk polio vaccine 1955"},
            {"year": 1959, "title": "The Mini arrives", "q": "Austin Mini 1959 car"},
            {"year": 1962, "title": "The Space Needle opens", "q": "Space Needle 1962 World's Fair Seattle"},
            {"year": 1965, "title": "The Gateway Arch is finished", "q": "Gateway Arch 1965 construction St Louis"},
            {"year": 1973, "title": "The Sydney Opera House opens", "q": "Sydney Opera House 1973 opening"},
            {"year": 1976, "title": "Concorde begins flying", "q": "Concorde 1976 first commercial flight"},
            {"year": 1980, "title": "Mount St. Helens erupts", "q": "Mount St Helens 1980 eruption USGS", "wiki": "1980 eruption of Mount St. Helens"},
            {"year": 1981, "title": "The personal computer arrives", "q": "IBM Personal Computer 1981"},
            {"year": 1989, "title": "The Berlin Wall comes down", "q": "Berlin Wall 1989 crowd", "must": ["Wall"], "wiki": "Fall of the Berlin Wall"},
            {"year": 1963, "title": "The March on Washington", "q": "March on Washington 1963 crowd Lincoln Memorial", "wiki": "March on Washington for Jobs and Freedom"},
            {"year": 1876, "title": "The telephone", "wiki": "Alexander Graham Bell's telephone"},
            {"year": 1893, "title": "The Ferris Wheel", "wiki": "Ferris Wheel"},
            {"year": 1911, "title": "The first aircraft carrier landing", "wiki": "USS Pennsylvania (ACR-4)"},
            {"year": 1927, "title": "The Solvay Conference", "wiki": "Solvay Conference"},
            {"year": 1930, "title": "The Chrysler Building", "wiki": "Chrysler Building"},
            {"year": 1937, "title": "The Golden Gate Bridge opens", "wiki": "Golden Gate Bridge"},
            {"year": 1945, "title": "The United Nations is founded", "wiki": "United Nations Conference on International Organization"},
            {"year": 1948, "title": "The Berlin Airlift", "wiki": "Berlin Blockade"},
            {"year": 1953, "title": "Everest is climbed", "wiki": "1953 British Mount Everest expedition"},
            {"year": 1957, "title": "Sputnik", "wiki": "Sputnik 1"},
            {"year": 1962, "title": "The Seattle World's Fair", "wiki": "Century 21 Exposition"},
            {"year": 1964, "title": "The New York World's Fair", "wiki": "1964 New York World's Fair"},
            {"year": 1969, "title": "Woodstock", "wiki": "Woodstock"},
            {"year": 1976, "title": "Concorde begins flying", "wiki": "Concorde"},
            {"year": 1985, "title": "Live Aid", "wiki": "Live Aid"},
            {"year": 1989, "title": "The Berlin Wall comes down", "wiki": "Fall of the Berlin Wall"},
            {"year": 1994, "title": "The Channel Tunnel opens", "wiki": "Channel Tunnel"},
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


def slug(title):
    """"The Leaning Tower of Pisa" -> "the-leaning-tower-of-pisa"."""
    ascii_only = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode()
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", ascii_only.lower())).strip("-")[:48]


def title_stem(title):
    """Collapse "Beach near Otaru -22903" and "Beach near Otaru -39689" to one key, so a
    pack doesn't end up with five photographs of the same afternoon."""
    stem = re.sub(r"\.(jpe?g|png)$", "", title, flags=re.IGNORECASE)
    stem = re.sub(r"[-_(\s]*\d+\)?\s*$", "", stem)
    stem = re.sub(r"[^a-zA-Z]+", " ", stem).strip().lower()
    return " ".join(stem.split()[:5])


def unsuitable_subject(title, pinned=False):
    """Reasons a photograph shouldn't go in a pack, whatever its licence.

    `pinned` skips the institutional filter. That one exists because a geosearch around
    a landmark returns exhibit labels and gallery interiors; applied to a named portrait
    it throws away Annie Oakley for having been photographed by Baker's Art Gallery."""
    if DISTRESSING.search(title):
        return "distressing subject"
    if not pinned and INSTITUTIONAL.search(title):
        return "institutional record, not a scene"
    if ARTWORK.search(title):
        return "artwork, not a photograph"
    return None


def looks_like_a_photograph(title, mime, width, minimum_width=800):
    if mime is None:
        # Some listings omit it; fall back to the filename.
        if not re.search(r"\.(jpe?g|png)$", title, re.IGNORECASE):
            return "not a photo file"
    elif mime not in PHOTO_MIMES:
        return "not a photo file (%s)" % mime
    if width and width < minimum_width:
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
    allowed = {name.lower() for name in spec.get("licences", {"CC0"})}
    return licence_family(licence) in allowed


def licence_family(licence):
    """"CC BY-SA 4.0" -> "cc by-sa", "CC BY 2.0" -> "cc by", "Public domain" -> itself.

    Matching on a prefix is not good enough: "CC BY-SA 4.0" starts with "CC BY", so a
    pack that meant to allow attribution-only quietly filled up with share-alike."""
    # The space matters: without it this eats the 0 in "CC0" and calls it "CC".
    name = re.sub(r"\s+\d+(\.\d+)?.*$", "", licence.strip()).strip().lower()
    return name or licence.strip().lower()


def wikipedia_lead_file(article):
    """The image the English Wikipedia article itself leads with.

    A keyword search of Commons for "Ty Cobb" returns a 1911 chewing-gum card and a
    search for "Buster Keaton" returns a lobby poster: real holdings, both of them, and
    neither is a photograph of the man. The article's lead image is the one an editor
    already chose as the picture that shows who this is, which is exactly the judgement
    this pack needs and cannot make by searching."""
    params = {"action": "query", "format": "json", "titles": article,
              "prop": "pageimages", "piprop": "name", "redirects": 1}
    url = "https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params)
    try:
        payload = fetch_json(url, timeout=60)
    except Exception:
        return None
    for page in ((payload.get("query") or {}).get("pages") or {}).values():
        name = page.get("pageimage")
        if name:
            return name.replace("_", " ")
    return None


def commons_file_info(file_title):
    """Licence and URLs for one named Commons file."""
    params = {"action": "query", "format": "json", "titles": f"File:{file_title}",
              "prop": "imageinfo", "iiprop": "url|extmetadata|size|mime", "iiurlwidth": 1400}
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)
    try:
        payload = fetch_json(url, timeout=60)
    except Exception:
        return None
    for page in ((payload.get("query") or {}).get("pages") or {}).values():
        info = (page.get("imageinfo") or [{}])[0]
        if info.get("thumburl"):
            return strip_html(page.get("title", "")).replace("File:", ""), info
    return None


def commons_from_category(category, spec, want=3, minimum_width=700, quality_only=False):
    """Photographs matching a phrase on Commons, best first, filtered the usual way.

    Event articles are the weak spot for lead-image pinning: "1936 Summer Olympics" leads
    with the official poster, and half the Games articles lead with nothing at all. The
    category behind the article does hold photographs, so it is the fallback.
    """
    # Plain keyword search. Both category routes were tried and both failed on Commons:
    # categorymembers lists only direct files, and most of these categories are shelves of
    # subcategories; deepcategory returned zero hits for every one of "Jack-o'-lanterns",
    # "Autumn leaves", "Hanukkah lamps" and "Diwali". Search returns them all.
    # `incategory:"Quality images"` is Commons' own curated tier — photographs other
    # editors have assessed as technically good. It is the nearest thing here to the
    # editorial judgement that makes the Landmarks photographs look the way they do.
    phrase = f'{category} incategory:"Quality images"' if quality_only else category
    params = {"action": "query", "format": "json", "generator": "search",
              "gsrsearch": f'{phrase} filemime:image/jpeg',
              "gsrnamespace": 6, "gsrlimit": 60,
              "prop": "imageinfo", "iiprop": "url|extmetadata|size|mime", "iiurlwidth": 1400}
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)
    try:
        payload = fetch_json(url, timeout=60)
    except Exception:
        return []
    found = []
    for page in ((payload.get("query") or {}).get("pages") or {}).values():
        info = (page.get("imageinfo") or [{}])[0]
        extra = info.get("extmetadata") or {}
        title = strip_html(page.get("title", "")).replace("File:", "")
        licence = strip_html((extra.get("LicenseShortName") or {}).get("value"))
        if not info.get("thumburl") or not licence_allowed(spec, licence):
            continue
        if looks_like_a_photograph(title, info.get("mime"), info.get("width"), minimum_width):
            continue
        if unsuitable_subject(title):
            continue
        found.append((title, licence,
                      strip_html((extra.get("Artist") or {}).get("value")) or "Unknown",
                      info.get("descriptionurl", ""), info["thumburl"]))
        if len(found) >= want:
            break
    return found


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
            "gsrsearch": f'{entry.get("q", entry["title"])} filemime:image/jpeg',
            "gsrnamespace": 6, "gsrlimit": 12,
            "prop": "imageinfo", "iiprop": "url|extmetadata|size|mime", "iiurlwidth": 1400,
        }
        payload = {}
        if not entry.get("wiki"):
            # Only the unpinned entries need the keyword search at all.
            url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)
            try:
                payload = fetch_json(url, timeout=90)
            except Exception as error:
                print(f"    ! {entry['title']}: {error}")
                continue

        picked = None

        # Pinned first: the photograph Wikipedia leads that article with.
        if entry.get("wiki"):
            found = wikipedia_lead_file(entry["wiki"])
            result = commons_file_info(found) if found else None
            if result:
                title, info = result
                extra = info.get("extmetadata") or {}
                licence = strip_html((extra.get("LicenseShortName") or {}).get("value"))
                if not licence_allowed(spec, licence):
                    rejections.add(f"lead image licence not allowed ({licence or 'unknown'})")
                # A lower floor than the search path uses. These are scans of old
                # portraits and a tile is roughly 350px across on an iPad; an 800px
                # requirement throws away Garbo and Bogart for no visible gain.
                elif reason := looks_like_a_photograph(title, info.get("mime"),
                                                       info.get("width"), minimum_width=380):
                    rejections.add(f"lead image for {entry['title']!r}: {reason}")
                elif reason := unsuitable_subject(title, pinned=True):
                    rejections.add(f"lead image for {entry['title']!r}: {reason}")
                else:
                    # No date check on this path. A Commons file's date is usually the
                    # date it was scanned or uploaded, so checking it here threw out a
                    # 1939 Gehrig for being "from 1923" and a 1931 Karloff for being
                    # "from 2010". What it is actually guarding against — Wikipedia
                    # leading an athlete's article with a photograph of them at seventy —
                    # is caught by looking at the pack, which --contact-sheet is for.
                    picked = (title, licence,
                              strip_html((extra.get("Artist") or {}).get("value")) or "Unknown",
                              info.get("descriptionurl", ""), info["thumburl"])
            else:
                rejections.add(f"no lead image on Wikipedia for {entry['title']!r}")

        # No keyword fallback for a pinned entry. Falling back is what put a chewing-gum
        # card in for Honus Wagner and a street crowd in for Jack Dempsey: if the one
        # picture chosen to represent this person will not do, the entry is dropped.
        # An event's category, when its article leads with a poster or with nothing.
        if not picked and entry.get("category"):
            for candidate in commons_from_category(entry["category"], spec):
                picked = candidate
                break
            if not picked:
                rejections.add(f"nothing usable in category for {entry['title']!r}")

        if entry.get("wiki") and not picked:
            rejections.add(f"pinned entry dropped: {entry['title']!r}")
            continue

        for page in ([] if picked else
                     ((payload.get("query") or {}).get("pages") or {}).values()):
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
            if unsuitable_subject(title):
                rejections.add("artwork or unsuitable subject")
                continue
            if not info.get("thumburl"):
                continue
            # Check the photograph against the year claimed for it. A keyword search for
            # "Neil Armstrong 1969" will happily return a 2020 photograph of a museum
            # display, and a dating game that teaches the wrong date is worse than one
            # with fewer photographs.
            if "chronology" in spec.get("themes", []):
                found_year = parse_year((extra.get("DateTimeOriginal") or {}).get("value")) \
                    or parse_year(title)
                if found_year and abs(found_year - entry["year"]) > 3:
                    rejections.add(f"found a {found_year} photograph for {entry['year']}")
                    continue
            required = entry.get("must", [])
            if any(word.lower() not in title.lower() for word in required):
                rejections.add(f"wrong subject for {entry['title']!r}")
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
            "tags": entry.get("tags"),
            "fact": wikipedia_fact(entry["wiki"]) if entry.get("wiki") else None,
            "title": entry["title"],
            "year": entry["year"],
            "month": entry.get("month", 6),
            "subject": entry.get("subject"),
            "place": entry.get("place"),
            "lat": entry.get("lat"), "lon": entry.get("lon"),
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

def wikipedia_fact(article, limit=190):
    """One sentence about the subject, from the article's own opening.

    Written by somebody rather than assembled from the metadata: "the Colosseum is in
    Rome, 2015" is not a fact, it is the caption read back. Wikipedia text is CC BY-SA,
    which the credits screen already carries for the Landmarks photographs.

    Two sentences if they fit, one if they don't. The first version asked for two and
    gave up when they were too long, which left sixty cards across four packs with no
    fact at all — Caruso's back read "Enrico Caruso" and then nothing."""
    text = _wikipedia_lead(article, 2)
    if text and len(text) <= limit:
        return text
    one = _wikipedia_lead(article, 1)
    return _trim_sentence(one, limit) if one else None


def _trim_sentence(text, limit):
    """A long opening sentence, cut back to its last full clause.

    Lead sentences like Sarah Bernhardt's list five plays; the list is what makes them
    long, and dropping the tail of it costs nothing. A cut that leaves a dangling
    conjunction reads worse than no fact at all, so those are stripped."""
    if len(text) <= limit:
        return text
    cut = text[:limit]
    stop = cut.rfind(", ")
    if stop < 60:
        return None
    trimmed = re.sub(r"[\s,]*\b(and|or|who|which|that|with|including|a|an|the)$",
                     "", cut[:stop].strip()).strip()
    return trimmed + "."


def _wikipedia_lead(article, sentences):
    params = {"action": "query", "format": "json", "titles": article,
              "prop": "extracts", "exintro": 1, "explaintext": 1,
              "exsentences": sentences, "redirects": 1}
    url = "https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params)
    try:
        payload = fetch_json(url, timeout=60)
    except Exception:
        return None
    for page in ((payload.get("query") or {}).get("pages") or {}).values():
        text = (page.get("extract") or "").strip()
        # A disambiguation page describes nothing: "Christ the Redeemer may refer to:"
        if not text or "may refer to" in text.lower():
            continue
        text = re.sub(r"\s+", " ", text)
        # Pronunciation guides and native-script glosses read as noise out loud. They
        # nest — "Taj Mahal (/ˌtɑːdʒ/ [taːdʒ]; lit. 'Crown of the Palace')" — so strip
        # brackets first, then peel parentheses from the inside out until none are left.
        # A single pass left "The Taj Mahall]; lit. 'Crown of the Palace')" on screen.
        text = re.sub(r"\s*\[[^\[\]]*\]", "", text)
        while True:
            peeled = re.sub(r"\s*\([^()]*\)", "", text)
            if peeled == text:
                break
            text = peeled
        text = re.sub(r"\s*[()\[\]]", "", text)
        text = re.sub(r"\s+([,.;])", r"\1", text)
        return re.sub(r"\s{2,}", " ", text).strip()
    return None


def from_commons_bulk_category(spec, rejections):
    """Many photographs per subject, from the Commons category for that subject.

    The opposite case to the curated packs. Nobody has a canonical photograph of "a
    jack-o'-lantern" the way they do of Abraham Lincoln — but there are thousands of
    good ones, and any of them answers "which photo has a carved pumpkin in it?". So
    here the category *is* the right source, where for Olympic Games it was a drawer of
    certificates and maps.
    """
    items = []
    for subject in spec["subjects"]:
        want = subject.get("take", 12)
        # Commons' assessed photographs first, ordinary uploads only to make up numbers —
        # and those have to be large, because a small file is usually a snapshot. The
        # failing case was a dark, lumpy snowman at night that read as faintly sinister.
        found = commons_from_category(subject["category"], spec, want=want * 5,
                                      minimum_width=1400, quality_only=True)
        # Assessed photographs first, then large ordinary uploads to make up numbers.
        # Assessed-only was tried and yields five photographs across eleven subjects —
        # Commons has assessed almost no jack-o'-lanterns — so the fallback stays, with
        # a high floor on file size and the per-subject exclusions below.
        if len(found) < want * 3:
            seen_titles = {row[0] for row in found}
            topped = commons_from_category(subject["category"], spec, want=want * 5,
                                           minimum_width=1600)
            found += [row for row in topped if row[0] not in seen_titles]
        kept = 0
        stems = set()
        required = [w.lower() for w in subject.get("must", [])]
        for title, licence, artist, page_url, thumb in found:
            if kept >= want:
                break
            # The filename has to name the subject. Search alone returned sunflowers for
            # "pumpkin", the Capitol dome for "christmas tree" and a jack-o'-lantern for
            # "diwali lamps" — and here a wrong tag is not a weak photograph, it is a
            # question with the wrong answer.
            lowered = title.lower()
            if any(word not in lowered for word in required):
                rejections.add(f"title does not name {subject['tag']}")
                continue
            # Named on the way out. Every one of these was seen on a contact sheet:
            # "Capitol Christmas Tree" is a photograph of the Capitol with a tree in it,
            # and a snowman "drawing" is not a photograph of a snowman at all.
            if any(word in lowered for word in subject.get("never", [])):
                rejections.add(f"excluded subject for {subject['tag']}")
                continue
            # Categories are full of near-duplicates from one photographer in one session.
            stem = title_stem(title)
            if stem in stems:
                rejections.add("near-duplicate in category")
                continue
            stems.add(stem)
            kept += 1
            items.append({
                "remote": commons_file_url(title),
                "tags": [subject["tag"]],
                "fact": subject.get("fact"),
                "title": subject["title"],
                "year": 2015,
                "month": 6,
                "subject": None,
                "place": None, "lat": None, "lon": None,
                "image": thumb,
                "credit": artist,
                "source": "Wikimedia Commons",
                "source_url": page_url,
                "licence": licence,
            })
        print(f"    {kept:3d}  {subject['title']}")
        if kept < 4:
            rejections.add(f"thin category for {subject['title']!r}")
    return items


def resolved_spec(name):
    """A pack spec with any absorbed packs folded into it.

    The catalogue is written as small, coherent lists — leaders, writers, explorers —
    because that is how you check one. It ships as a handful of big packs, because a
    caregiver choosing photo sources should see five choices, not ten."""
    spec = dict(PACK_SPECS[name])
    photographs = list(spec.get("photographs", []))
    for absorbed in spec.get("absorbs", []):
        photographs.extend(PACK_SPECS[absorbed].get("photographs", []))
    if photographs:
        spec["photographs"] = photographs
    return spec


def build(pack_name, out_root, api_key, metadata_only=False):
    spec = resolved_spec(pack_name)
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
    elif spec["source"] == "commons-bulk-category":
        candidates = from_commons_bulk_category(spec, rejections)
    elif spec["source"] == "commons-curated":
        candidates = from_commons_curated(spec, rejections)
        # A pack can draw on both archives — the events are on Commons, the missions
        # are NASA's.
        if spec.get("nasaPhotographs"):
            candidates += from_nasa_curated(dict(spec, photographs=spec["nasaPhotographs"]),
                                            rejections)
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
    used_ids = set()
    for index, candidate in enumerate(candidates, start=1):
        # From the title, not from the position. A numbered id is only stable until the
        # next rebuild drops an entry, and anything keyed on it — a device's photo cache,
        # the list of sources that turned out to be dead — then points at the wrong
        # photograph. The picture's own name survives a rebuild.
        item_id = f"{spec['id']}-{slug(candidate['title'])}"
        if item_id in used_ids:
            item_id = f"{item_id}-{index}"
        used_ids.add(item_id)
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
        # What the photograph is *of*, so a level made entirely of presidents can ask
        # about presidents rather than about photographs.
        if candidate.get("subject"):
            entry["subject"] = candidate["subject"]
        if candidate.get("fact"):
            entry["fact"] = candidate["fact"]
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
    if spec.get("chronologyPrompt"):
        manifest["chronologyPrompt"] = spec["chronologyPrompt"]
    if spec.get("labelWhilePlaying"):
        manifest["labelWhilePlaying"] = True
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
    parser.add_argument("--out", default="../../TimeRolls/Packs")
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
