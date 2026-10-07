#!/usr/bin/env python3
"""Draw the Geography pack: maps of countries, US states and a few countries that no longer
exist, each one with the place picked out in deep sage.

Drawn, not found. Commons has plenty of locator maps, but every one is in a different style,
half carry a label that gives the answer away, and a round of four maps in four styles is a
round about styles. Natural Earth's outlines are public domain, so the maps here are ours to
draw however reads best: no labels, the place filled in, its neighbours in light stone, the
sea in pale sage — the app's own palette.

What a round can ask, and where each fact comes from:

* **"Which one is a map of Florida?"** — the title.
* **"Which country is in Europe?"** — Wikidata's continent (P30), which lists both continents
  for a country that spans two. Russia is in Europe *and* Asia, so it can never be the wrong
  answer to either.
* **"Which country borders Germany?"** — two sources that must agree before a border is
  *asked about*: the outlines touch along a real stretch of border, and Wikidata says they
  share one. For ruling a distractor *out*, either source is enough. A question can be wrong
  in two ways and the cautious direction differs for each.
* **"Which country is in NATO?" / "…in the European Union?"** — Wikidata membership (P463).
* **"Which state is in the Midwest?"** — the Census Bureau's four regions.
* **"Which state borders Texas?"** — the outlines, as above. Four Corners states touch at a
  point; that is never asked as a border, and never allowed as a distractor either.

The three countries that no longer exist are drawn as the union of their successors, and are
only ever asked about by name ("Which one is a map of the Soviet Union?"). They are kept out
of every round with one of their successors, because a map of Russia beside a map of the
Soviet Union is a spot-the-difference, not a geography question.

    python3 Tools/PackBuilder/build_geography.py            # dry run: counts
    python3 Tools/PackBuilder/build_geography.py --apply    # draw the maps, write the pack
"""

import argparse, json, math, os, re, sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager, patheffects
from matplotlib.patches import Circle, PathPatch
from matplotlib.path import Path
from shapely.geometry import shape, MultiPolygon, Polygon
from shapely.ops import unary_union

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import quiz_common as q

NE = os.path.join(q.ROOT, "build", "naturalearth")
PACK_ID = "geography"
OUT = os.path.join(q.PACKS, PACK_ID)

# The app's palette (MeadowTheme.swift).
SEA = "#E3E8DA"
LAND = "#F7F1E3"
EDGE = "#A8A293"
TARGET = "#46593D"
TARGET_EDGE = "#2E3B29"
RING = "#A9744E"

PIXELS = 800
# 4:3, not square. An iPad tile is wider than tall, and a square map in it was padded
# out with a blur of itself. The extra width is extra map; everything that matters —
# the place, the ring, the labels — stays in the central square, which is exactly what
# a phone's square tile shows when it fills from the middle.
ASPECT = 4 / 3

INK = "#4F5450"      # charcoal, for city names
SEA_INK = "#6B7A78"  # slate, for seas
ROUNDED = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
FONT = font_manager.FontProperties(fname=ROUNDED) if os.path.exists(ROUNDED) else None

# Filled in by main(): what may be written on a map. See `annotate`.
LABELS = {"cities": [], "seas": [], "banned": []}

COUNTRY_COUNT = 147

# Well known despite a small population; the rest of the list is by population.
ALSO = ["Iceland", "Estonia", "Latvia", "Slovenia", "North Macedonia", "Montenegro",
        "Cyprus", "Botswana", "Namibia", "Luxembourg", "Bahamas", "Fiji"]

# How a country is said in a sentence. Wikidata's label, with "the" where English has it.
WITH_THE = {"United States", "Bahamas", "Federated States of Micronesia", "United Kingdom", "Netherlands", "Philippines",
            "Czech Republic", "Democratic Republic of the Congo", "Republic of the Congo",
            "Central African Republic", "Dominican Republic", "Gambia", "Bahamas",
            "United Arab Emirates", "Maldives", "Comoros", "Solomon Islands"}
RENAME = {"United States of America": "United States",
          "People's Republic of China": "China",
          "Kingdom of the Netherlands": "Netherlands",
          "State of Palestine": "Palestine"}

CONTINENTS = {"Q15": "Africa", "Q46": "Europe", "Q48": "Asia", "Q49": "North America",
              "Q18": "South America", "Q538": "Oceania", "Q55643": "Oceania",
              "Q3960": "Oceania", "Q27611": "North America"}  # Central America

REGIONS = {  # US Census Bureau regions
    "Northeast": "Connecticut Maine Massachusetts New_Hampshire Rhode_Island Vermont "
                 "New_Jersey New_York Pennsylvania",
    "Midwest": "Illinois Indiana Michigan Ohio Wisconsin Iowa Kansas Minnesota Missouri "
               "Nebraska North_Dakota South_Dakota",
    "South": "Delaware Florida Georgia Maryland North_Carolina South_Carolina Virginia "
             "West_Virginia Alabama Kentucky Mississippi Tennessee Arkansas Louisiana "
             "Oklahoma Texas",
    "West": "Arizona Colorado Idaho Montana Nevada New_Mexico Utah Wyoming Alaska "
            "California Hawaii Oregon Washington",
}
STATE_REGION = {name.replace("_", " "): region
                for region, names in REGIONS.items() for name in names.split()}

FORMER = [
    # title, Wikidata id, successors (Natural Earth names), years, cluster
    ("the Soviet Union", "Q15180",
     ["Russia", "Ukraine", "Belarus", "Moldova", "Estonia", "Latvia", "Lithuania", "Georgia",
      "Armenia", "Azerbaijan", "Kazakhstan", "Uzbekistan", "Turkmenistan", "Kyrgyzstan",
      "Tajikistan"], "1922–1991", "Asia"),
    ("Yugoslavia", "Q83286",
     ["Slovenia", "Croatia", "Bosnia and Herz.", "Serbia", "Montenegro", "Kosovo",
      "North Macedonia"], "1945–1992", "Europe"),
    ("Czechoslovakia", "Q33946", ["Czechia", "Slovakia"], "1918–1992", "Europe"),
]

SUBREGION_WORDS = {"Northern America": "North America", "South-Eastern Asia": "Southeast Asia",
                   "Australia and New Zealand": "Australasia"}


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower().removeprefix("the ")).strip("-")


def load(name):
    return json.load(open(os.path.join(NE, name + ".geojson")))["features"]


# MARK: - Projection

class Azimuthal:
    """Lambert azimuthal equal-area, centred on the place being drawn, in kilometres.

    Equal-area so a country is the size it is; centred so nothing near the middle of the
    map is bent, which is what makes Russia and Canada look like themselves.
    """

    def __init__(self, lon, lat):
        self.l0 = math.radians(lon)
        self.p0 = math.radians(lat)

    def cos_c(self, lon, lat):
        l, p = math.radians(lon), math.radians(lat)
        return (math.sin(self.p0) * math.sin(p)
                + math.cos(self.p0) * math.cos(p) * math.cos(l - self.l0))

    def __call__(self, lon, lat):
        l, p = math.radians(lon), math.radians(lat)
        cc = (math.sin(self.p0) * math.sin(p)
              + math.cos(self.p0) * math.cos(p) * math.cos(l - self.l0))
        k = math.sqrt(2 / max(1 + cc, 1e-9))
        x = k * math.cos(p) * math.sin(l - self.l0)
        y = k * (math.cos(self.p0) * math.sin(p)
                 - math.sin(self.p0) * math.cos(p) * math.cos(l - self.l0))
        return x * 6371, y * 6371


def polygons(geometry):
    if isinstance(geometry, Polygon):
        return [geometry]
    if isinstance(geometry, MultiPolygon):
        return list(geometry.geoms)
    return [g for g in getattr(geometry, "geoms", []) if isinstance(g, Polygon)]


def projected_path(polygon, project):
    """A matplotlib path for one polygon, or None when it lies on the far side."""
    rings = [polygon.exterior, *polygon.interiors]
    verts, codes = [], []
    for ring in rings:
        coords = list(ring.coords)
        # Anything near the antipode explodes across the whole map in this projection.
        if any(project.cos_c(x, y) < -0.3 for x, y in coords):
            return None
        points = [project(x, y) for x, y in coords]
        verts += points
        codes += [Path.MOVETO] + [Path.LINETO] * (len(points) - 2) + [Path.CLOSEPOLY]
    return Path(verts, codes)


def main_part(geometry):
    """The mainland, plus whatever lies close to it — so France is framed on France and not
    on France and French Guiana."""
    parts = sorted(polygons(geometry), key=lambda p: p.area, reverse=True)
    if not parts:
        return geometry
    main = parts[0]
    near = [p for p in parts if p.distance(main) < 6 or p.area > main.area * 0.25]
    return unary_union(near)


def draw(path, target, context, lakes, frame=None, centre=None, min_span=1400,
         keep_borders=True):
    """One map. `target` and every geometry in `context` are in longitude/latitude."""
    focus = main_part(target)
    lon, lat = centre or (focus.centroid.x, focus.centroid.y)
    project = Azimuthal(lon, lat)

    if frame is None:
        xs, ys = [], []
        for polygon in polygons(focus):
            for x, y in polygon.exterior.coords:
                px, py = project(x, y)
                xs.append(px)
                ys.append(py)
        width, height = max(xs) - min(xs), max(ys) - min(ys)
        span = max(width, height)
        # Room to see the neighbours: three times the place itself for a small one, a
        # little less for a large one so Russia still fills the frame.
        span = max(span * (2.6 if span < 1500 else 1.5 if span < 4000 else 1.18), min_span)
        cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
        frame = (cx - span / 2, cx + span / 2, cy - span / 2, cy + span / 2)
    x0, x1, y0, y1 = frame
    span = y1 - y0
    # Widen the square frame into 4:3 about its centre.
    mid = (x0 + x1) / 2
    x0, x1 = mid - span * ASPECT / 2, mid + span * ASPECT / 2
    frame = (x0, x1, y0, y1)

    figure = plt.figure(figsize=(PIXELS * ASPECT / 100, PIXELS / 100), dpi=100)
    axes = figure.add_axes([0, 0, 1, 1])
    axes.set_xlim(x0, x1)
    axes.set_ylim(y0, y1)
    axes.set_aspect("equal")
    axes.axis("off")
    figure.patch.set_facecolor(SEA)
    axes.set_facecolor(SEA)

    def fill(geometry, face, edge, width, z):
        for polygon in polygons(geometry):
            p = projected_path(polygon, project)
            if p is None:
                continue
            ex = p.get_extents()
            if ex.x1 < x0 - span or ex.x0 > x1 + span or ex.y1 < y0 - span or ex.y0 > y1 + span:
                continue
            axes.add_patch(PathPatch(p, facecolor=face, edgecolor=edge, linewidth=width,
                                     zorder=z, joinstyle="round"))

    for geometry in context:
        fill(geometry, LAND, EDGE, 0.6 if keep_borders else 0, 1)
    fill(target, TARGET, TARGET_EDGE, 0.9, 2)
    for lake in lakes:
        fill(lake, SEA, EDGE, 0.4, 3)

    # A small place gets a ring round it, or it is a speck that could be anywhere.
    tx = [project(x, y) for polygon in polygons(focus) for x, y in polygon.exterior.coords]
    width = max(p[0] for p in tx) - min(p[0] for p in tx)
    height = max(p[1] for p in tx) - min(p[1] for p in tx)
    if max(width, height) < span * 0.08:
        cx = (max(p[0] for p in tx) + min(p[0] for p in tx)) / 2
        cy = (max(p[1] for p in tx) + min(p[1] for p in tx)) / 2
        axes.add_patch(Circle((cx, cy), span * 0.075, fill=False, edgecolor=RING,
                              linewidth=3.2, zorder=4))

    annotate(figure, axes, project, frame, target)

    figure.savefig(path, dpi=100, facecolor=SEA, pil_kwargs={"quality": 84, "optimize": True})
    plt.close(figure)


# MARK: - Labels

def banned(name):
    """A city named after something a round can ask about. "New York" printed on a map of
    Pennsylvania, in a round asking which one is New York, points at the wrong tile."""
    # Punctuation to spaces, or "Washington, D.C." never matches "washington".
    lowered = " " + re.sub(r"[^a-z]+", " ", name.lower()) + " "
    return any(f" {title} " in lowered for title in LABELS["banned"])


def annotate(figure, axes, project, frame, target):
    """Big cities and seas, for finding your way — never the place itself.

    Only things that can never be an answer: a city is not a country or a state, and a
    sea is neither. Neighbouring countries and states are deliberately *not* named. In
    "Which state borders Texas?" the right tile would be the only one with "Texas" written
    on it, and the round would be reading, not geography. Nothing is written inside the
    highlighted place either, or "which one is France?" is answered by the word Paris.
    """
    fx0, fx1, y0, y1 = frame
    span = y1 - y0
    # Labels live in the central square, which every tile shows; the wings are only
    # seen on an iPad.
    mid = (fx0 + fx1) / 2
    x0, x1 = mid - span / 2, mid + span / 2
    margin = span * 0.07
    inside = lambda px, py: x0 + margin < px < x1 - margin and y0 + margin < py < y1 - margin

    # The highlighted place, in map coordinates, for keeping words off it.
    shapes = []
    for polygon in polygons(target):
        coords = list(polygon.exterior.coords)
        if any(project.cos_c(x, y) < -0.3 for x, y in coords):
            continue
        shapes.append(Polygon([project(x, y) for x, y in coords]).buffer(span * 0.012))
    keep_off = unary_union(shapes) if shapes else Polygon()

    # The tile puts its number badge in the top-left corner and the magnifying glass in
    # the bottom-left, both over the picture. A word under either is a word cut in half.
    # The badge and the magnifying glass sit in the tile's left corners — the square's
    # on a phone, the full width's on an iPad. Keep words out of both.
    corners = unary_union([
        Polygon.from_bounds(x0, y1 - span * 0.24, x0 + span * 0.26, y1),
        Polygon.from_bounds(x0, y0, x0 + span * 0.24, y0 + span * 0.22),
        Polygon.from_bounds(fx0, y1 - span * 0.24, fx0 + span * 0.26, y1),
        Polygon.from_bounds(fx0, y0, fx0 + span * 0.24, y0 + span * 0.22),
    ])

    renderer = figure.canvas.get_renderer()
    placed = []
    inverse = axes.transData.inverted()

    def fits(text):
        box = text.get_window_extent(renderer).expanded(1.08, 1.25)
        if any(box.overlaps(other) for other in placed):
            return False
        (bx0, by0), (bx1, by1) = inverse.transform([(box.x0, box.y0), (box.x1, box.y1)])
        if not (x0 < bx0 and bx1 < x1 and y0 < by0 and by1 < y1):
            return False
        box_shape = Polygon([(bx0, by0), (bx1, by0), (bx1, by1), (bx0, by1)])
        if keep_off.intersects(box_shape) or corners.intersects(box_shape):
            return False
        placed.append(box)
        return True

    halo = [patheffects.withStroke(linewidth=5, foreground=LAND)]
    cities = 0
    for name, lon, lat, _ in LABELS["cities"]:
        if cities >= 3:
            break
        if project.cos_c(lon, lat) < 0.2 or banned(name):
            continue
        px, py = project(lon, lat)
        if not inside(px, py) or keep_off.contains(Polygon.from_bounds(px, py, px + 1, py + 1)):
            continue
        dot = axes.plot([px], [py], "o", color=INK, markersize=9, zorder=6,
                        markeredgecolor=LAND, markeredgewidth=1.5)[0]
        # Beside the dot, whichever side has room.
        for dx, ha in ((span * 0.014, "left"), (-span * 0.014, "right")):
            text = axes.text(px + dx, py, name, fontsize=27, color=INK, ha=ha, va="center",
                             zorder=7, fontproperties=FONT, path_effects=halo)
            text.set_fontsize(27)
            if fits(text):
                cities += 1
                break
            text.remove()
        else:
            dot.remove()

    sea_halo = [patheffects.withStroke(linewidth=4, foreground=SEA)]
    seas = 0
    for name, point in LABELS["seas"]:
        if seas >= 2:
            break
        lon, lat = point
        if project.cos_c(lon, lat) < 0.2:
            continue
        px, py = project(lon, lat)
        if not inside(px, py):
            continue
        text = axes.text(px, py, name, fontsize=23, color=SEA_INK, ha="center", va="center",
                         style="italic", zorder=5, fontproperties=FONT, path_effects=sea_halo)
        text.set_fontsize(23)
        if fits(text):
            seas += 1
        else:
            text.remove()


# MARK: - Borders

def shared_border_km(a, b):
    """How much border two places share, roughly, in kilometres. Zero for a corner."""
    meeting = a.buffer(0.004).intersection(b.buffer(0.004))
    if meeting.is_empty:
        return 0.0
    # A thin sliver along the border; its long side is the shared length.
    lat = meeting.centroid.y
    return meeting.area / 0.008 * 111 * max(math.cos(math.radians(lat)), 0.2)


def touches(a, b):
    return a.buffer(0.01).intersects(b.buffer(0.01))


# MARK: - Build

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    countries = [f for f in load("ne_50m_admin_0_countries")]
    states = [f for f in load("ne_50m_admin_1_states_provinces")
              if f["properties"]["adm0_a3"] == "USA"
              and f["properties"]["name"] != "District of Columbia"]
    lakes = [shape(f["geometry"]) for f in load("ne_50m_lakes")
             # Not `or 9`: the Great Lakes are scalerank 0, and 0 is falsy.
             if f["properties"].get("scalerank", 9) <= 2]
    geometry = {f["properties"]["NAME"]: shape(f["geometry"]).buffer(0) for f in countries}
    every_country = list(geometry.values())

    # Sovereign UN members only: "which country" has to mean a country.
    ids = {f["properties"]["NAME"]: f["properties"]["WIKIDATAID"] for f in countries
           if f["properties"].get("WIKIDATAID")}
    print("reading Wikidata for", len(ids), "countries")
    wd = q.entities(list(ids.values()), props="claims|labels|sitelinks")
    members = {}
    for name, item in ids.items():
        entity = wd.get(item) or {}
        if "Q1065" in q.claim_ids(entity, "P463") and "Q3624078" in q.claim_ids(entity, "P31"):
            members[name] = entity
    population = {f["properties"]["NAME"]: f["properties"]["POP_EST"] for f in countries}
    def spoken(name):
        title = RENAME.get(q.label(members[name]), q.label(members[name]))
        title = title.removeprefix("The ")
        return f"the {title}" if title in WITH_THE else title
    by_spoken = {spoken(n): n for n in members}
    chosen = sorted(members, key=lambda n: -population.get(n, 0))
    extra = [by_spoken[n] for n in ALSO if n in by_spoken]
    chosen = [n for n in chosen if n not in extra][:COUNTRY_COUNT - len(extra)] + extra
    print(f"{len(members)} UN member states drawn by Natural Earth; using {len(chosen)}")

    names = {n: spoken(n) for n in chosen}
    # Every neighbour gets a name, chosen or not, so a border is never silently missing.
    def any_name(ne_name):
        return names.get(ne_name) or (spoken(ne_name) if ne_name in members else ne_name)

    items = []
    descriptions = q.wikipedia_intros(
        [ids[n] for n in chosen] + [s["properties"]["wikidataid"] for s in states]
        + [f[1] for f in FORMER])

    # Countries
    for name in chosen:
        entity = members[name]
        shape_ = geometry[name]
        props = next(f["properties"] for f in countries if f["properties"]["NAME"] == name)
        continents = sorted({CONTINENTS[c] for c in q.claim_ids(entity, "P30") if c in CONTINENTS})
        if not continents:
            continents = [props["CONTINENT"]]
        wikidata_ne = {n for n, i in ids.items() if i in set(q.claim_ids(entity, "P47"))}
        asked, ruled_out = [], set()
        for other, other_shape in geometry.items():
            if other == name:
                continue
            near = touches(shape_, other_shape)
            if near or other in wikidata_ne:
                ruled_out.add(any_name(other))
            # Asked about only when both sources agree, there is a real stretch of
            # border, and the neighbour is a country the pack itself knows.
            if (near and other in wikidata_ne and other in names
                    and shared_border_km(shape_, other_shape) > 8):
                asked.append(any_name(other))
        memberships = []
        if "Q458" in q.claim_ids(entity, "P463"):
            memberships.append("the European Union")
        if "Q7184" in q.claim_ids(entity, "P463"):
            memberships.append("NATO")
        subregion = SUBREGION_WORDS.get(props["SUBREGION"], props["SUBREGION"])
        items.append({
            "kind": "country", "name": name, "title": names[name], "qid": ids[name],
            "cluster": props["CONTINENT"],
            "group": f"a country in {subregion}",
            # Asked by the one continent the outlines put it on; ruled out by every
            # continent either source names. Wikidata puts the United States in Asia and
            # Oceania too, by way of Guam and Hawaii — true in its way, and not something
            # to build "which country is in Asia?" on.
            "facts": {"continent": [props["CONTINENT"]],
                      "continentAny": sorted(set(continents) | {props["CONTINENT"]}),
                      "borders": sorted(asked),
                      "bordersAny": sorted(ruled_out), "memberOf": memberships},
            "knownBy": q.sitelink_count(entity),
        })

    # States
    state_shapes = {s["properties"]["name"]: shape(s["geometry"]).buffer(0) for s in states}
    for s in states:
        name = s["properties"]["name"]
        asked = sorted(o for o, g in state_shapes.items()
                       if o != name and touches(state_shapes[name], g)
                       and shared_border_km(state_shapes[name], g) > 8)
        ruled_out = sorted(o for o, g in state_shapes.items()
                           if o != name and touches(state_shapes[name], g))
        region = STATE_REGION[name]
        items.append({
            "kind": "state", "name": name, "title": name, "qid": s["properties"]["wikidataid"],
            "cluster": "US state", "group": f"a state in the {region}",
            "facts": {"region": [region], "stateBorders": asked, "stateBordersAny": ruled_out},
            "knownBy": 0,
        })

    # Countries that no longer exist
    for title, item, successors, years, cluster in FORMER:
        items.append({
            "kind": "former", "name": title, "title": title, "qid": item,
            "successors": successors, "cluster": cluster,
            "group": f"a country that no longer exists ({years})",
            "facts": {}, "knownBy": 0,
            "keepApartFrom": sorted(any_name(n) for n in successors),
        })

    shipped, missing_fact = [], []
    for entry in items:
        described = descriptions.get(entry["qid"])
        if not described:
            missing_fact.append(entry["title"])
            continue
        entry["fact"], entry["factSource"] = described
        shipped.append(entry)
    print(f"{len(shipped)} with a Wikipedia description; missing: {missing_fact}")

    if not args.apply:
        for e in shipped[:3] + shipped[-6:]:
            print(e["title"], e["cluster"], e["facts"])
        return

    os.makedirs(OUT, exist_ok=True)
    # Cities by size, capitals first among equals; seas by how big a name they are.
    from fontTools.ttLib import TTFont
    drawable = set(TTFont(ROUNDED).getBestCmap()) if FONT else set(range(0x250))
    for f in load("ne_50m_populated_places_simple"):
        p = f["properties"]
        if p.get("pop_max", 0) >= 750_000 or p.get("adm0cap"):
            # The plain spelling where the font cannot draw the real one — İzmir and Ōsaka
            # came out with a box where a letter should be — and Natural Earth's own
            # misspelling of Shenyang put right.
            name = p["name"] if all(ord(c) in drawable for c in p["name"]) else p["nameascii"]
            name = {"Shenyeng": "Shenyang"}.get(name, name)
            LABELS["cities"].append((name, p["longitude"], p["latitude"],
                                     p.get("pop_max", 0) * (1.6 if p.get("adm0cap") else 1)))
    LABELS["cities"].sort(key=lambda c: -c[3])
    for f in load("ne_50m_geography_marine_polys"):
        p = f["properties"]
        if (p.get("scalerank") if p.get("scalerank") is not None else 9) > 2 or not p.get("name"):
            continue
        # "North Atlantic Ocean" reads as the Atlantic; "North Sea" is its own name.
        name = re.sub(r"^(North|South) (?=Atlantic|Pacific)", "", p["name"].title())
        name = name.replace(" Of ", " of ")
        point = shape(f["geometry"]).representative_point()
        LABELS["seas"].append((name, (point.x, point.y)))
    LABELS["banned"] = sorted({e["title"].lower().removeprefix("the ") for e in shipped}
                              | {"washington", "new york", "mexico", "panama", "kuwait",
                                 "guatemala", "singapore", "luxembourg", "djibouti"})
    state_context = list(state_shapes.values()) + [geometry["Canada"], geometry["Mexico"]] + [
        g for n, g in geometry.items() if n not in ("United States of America",)]
    pack_items = []
    for entry in shipped:
        # "state-" keeps Georgia the state from overwriting Georgia the country.
        key = ("state-" if entry["kind"] == "state" else "") + slug(entry["title"])
        file = f"{PACK_ID}-{key}.jpg"
        out = os.path.join(OUT, file)
        if entry["kind"] == "country":
            draw(out, geometry[entry["name"]], every_country, lakes)
        elif entry["kind"] == "state":
            target = state_shapes[entry["name"]]
            if entry["name"] in ("Alaska", "Hawaii"):
                draw(out, target, state_context, lakes,
                     min_span=1800 if entry["name"] == "Alaska" else 900)
            else:
                # Its own close-up, not a dot on the whole country: big enough to see the
                # shape, with the neighbours round it and a city or two to steer by.
                draw(out, target, state_context, lakes, min_span=1150)
        else:
            union = unary_union([geometry[n] for n in entry["successors"]])
            draw(out, union, [g for n, g in geometry.items() if n not in entry["successors"]],
                 lakes, min_span=2600)
        pack_items.append({
            "id": f"{PACK_ID}-{key}",
            "file": file,
            "subjectID": entry["qid"],
            "title": entry["title"],
            "objectTags": [],
            "year": 2026, "month": 6,
            "credit": "Drawn for Time Rolls from Natural Earth",
            "source": "Natural Earth",
            "sourceURL": "https://www.naturalearthdata.com/",
            "license": "Public domain",
            "licenseURL": "https://www.naturalearthdata.com/about/terms-of-use/",
            "isResizedCopy": False,
            "knownBy": entry["knownBy"],
            "cluster": entry["cluster"],
            "group": entry["group"],
            "facts": entry["facts"],
            **({"keepApartFrom": entry["keepApartFrom"]} if "keepApartFrom" in entry else {}),
            "fact": entry["fact"],
            "factSource": entry["factSource"],
        })
        print("drew", file, flush=True)

    meta = {
        "title": "Geography", "blurb": "Maps of countries, states, and a few that are gone.",
        "themes": ["geography"], # Taken in turn by the game — see QuizCurator.namedLevel.
        "namedSubjectPrompt": "Which one is a map of {name}?|Which map shows {name}?",
        "questions": [
            {"id": "continent", "ask": "continent", "exclude": "continentAny",
             "prompt": "Which country is in {value}?"},
            {"id": "borders", "ask": "borders", "exclude": "bordersAny",
             "prompt": "Which country borders {value}?"},
            {"id": "member", "ask": "memberOf", "exclude": "memberOf",
             "prompt": "Which country is in {value}?"},
            {"id": "region", "ask": "region", "exclude": "region",
             "prompt": "Which state is in the {value}?"},
            {"id": "stateBorders", "ask": "stateBorders", "exclude": "stateBordersAny",
             "prompt": "Which state borders {value}?"},
        ],
    }
    q.write_pack(PACK_ID, meta, pack_items, force=args.force)


if __name__ == "__main__":
    main()
