#!/usr/bin/env python3
"""Build the Cars pack: one photograph per generation of a well-known car model line.

Two kinds of round are built from it:

* **Named** — "Which car is a Ford Mustang?" beside three cars of other model lines from the
  same `cluster`, close in years.
* **Generation** — "Which car is a 2020 Ford Mustang?": four photographs of one `family`, every
  pair of `askYear`s at least twenty years apart and no two generations' `years` overlapping.

So the list below is written by hand — which lines, which generations, which Commons
categories — and everything a player could check is then checked against a source rather
than trusted from the list:

* `years` must agree (±1) with a range in the generation's Wikipedia infobox (model years or
  production), or carry a written reason in `ok=` for why it differs.
* `fact` is the opening of the generation's own English article, or the model line's.
* The photograph is chosen from the generation's Commons category (and that model's
  per-year categories, which Commons keeps for most American cars), filtered by file title,
  then scored by the app's own SigLIP tower; the best-scoring clean exterior wins.

Everything fetched is cached under build/quiz-cache/cars-*, so a rerun resumes.

  python3 Tools/PackBuilder/build_cars.py            # build and write
  python3 Tools/PackBuilder/build_cars.py --dry-run  # build, report, do not write
"""

import argparse, hashlib, json, os, re, sys, time, urllib.parse
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import quiz_common as q  # noqa: E402

PACK = "cars"
NOW = 2026          # "present" in an infobox means production continues into this year
CACHE = q.CACHE

META = {
    "title": "Cars",
    "blurb": "Classic and modern cars, from the showroom to the open road.",
    "themes": ["cars"],
    "namedSubjectPrompt": "Which {noun} is a {name}?",
    "questions": [
        {"id": "maker", "ask": "maker", "exclude": "maker",
         "prompt": "Which {noun} was made by {value}?|What {noun} was made by {value}?"},
    ],
}

# MARK: - What goes in the pack


class G:
    """One generation. `art` is its own English article (None: the line's); `sec` picks its
    infobox out of an article that covers several; `cats` are Commons categories to search;
    `strict` means those categories are shared with other generations, so a file only counts
    when its title or its year category puts it inside `years`."""

    def __init__(self, slug, years, ask, art=None, sec=None, cats=(), strict=False,
                 cluster=None, maker=None, ok=None, exclude=(), must=None):
        self.slug, self.years, self.ask = slug, tuple(years), ask
        self.art, self.sec, self.cats, self.strict = art, sec, list(cats), strict
        self.cluster, self.maker, self.ok = cluster, maker, ok
        self.exclude, self.must = tuple(exclude), must


class F:
    def __init__(self, title, maker, cluster, group, line, gens, aliases=(), exclude=(),
                 must=None):
        self.title, self.maker, self.cluster, self.group = title, maker, cluster, group
        self.line, self.gens, self.aliases = line, gens, list(aliases)
        self.exclude, self.must = tuple(exclude), must


GM_TWINS = ("gmc", "sierra", "yukon", "denali")

FAMILIES = [
    # ---- pony cars ---------------------------------------------------------------------
    F("Ford Mustang", "Ford", "pony car", "an American pony car", "Ford Mustang", [
        G("gen1", (1965, 1973), 1965, "Ford Mustang (first generation)", cats=["Ford Mustang I"]),
        G("gen2", (1974, 1978), 1976, "Ford Mustang (second generation)", cats=["Ford Mustang II"]),
        G("gen3", (1979, 1993), 1985, "Ford Mustang (third generation)",
          cats=["Ford Mustang (1979-1986)", "Ford Mustang (1987-1993)"]),
        G("gen4", (1994, 2004), 1999, "Ford Mustang (fourth generation)", cats=["Ford Mustang IV"]),
        G("gen5", (2005, 2014), 2005, "Ford Mustang (fifth generation)",
          cats=["Ford Mustang V (2005-2009)", "Ford Mustang (2010-2014)"]),
        G("gen6", (2015, 2023), 2018, "Ford Mustang (sixth generation)", cats=["Ford Mustang VI"]),
        G("gen7", (2024, NOW), 2025, "Ford Mustang (seventh generation)", cats=["Ford Mustang VII"]),
    ], exclude=("mach-e", "mach e", "saleen", "shelby", "steeda", "roush")),
    F("Chevrolet Camaro", "Chevrolet", "pony car", "an American pony car", "Chevrolet Camaro", [
        G("gen1", (1967, 1969), 1969, "Chevrolet Camaro (first generation)", cats=["Chevrolet Camaro (1967–1969)"]),
        G("gen2", (1970, 1981), 1977, "Chevrolet Camaro (second generation)", cats=["Chevrolet Camaro (1970–1981)"]),
        G("gen3", (1982, 1992), 1989, "Chevrolet Camaro (third generation)", cats=["Chevrolet Camaro (1982–1992)"]),
        G("gen4", (1993, 2002), 1998, "Chevrolet Camaro (fourth generation)", cats=["Chevrolet Camaro (1993–2002)"]),
        G("gen5", (2010, 2015), 2010, "Chevrolet Camaro (fifth generation)", cats=["Chevrolet Camaro (2010–2015)"]),
        G("gen6", (2016, 2024), 2019, "Chevrolet Camaro (sixth generation)", cats=["Chevrolet Camaro (2016–2024)"]),
    ], exclude=("bumblebee", "transformers")),
    F("Pontiac Firebird", "Pontiac", "pony car", "an American pony car", "Pontiac Firebird", [
        G("gen1", (1967, 1969), 1968, sec="First generation", cats=["Pontiac Firebird (1st generation)"]),
        G("gen2", (1970, 1981), 1977, "Pontiac Firebird (second generation)", cats=["Pontiac Firebird (2nd generation)"]),
        G("gen3", (1982, 1992), 1988, "Pontiac Firebird (third generation)", cats=["Pontiac Firebird (3rd generation)"]),
        G("gen4", (1993, 2002), 1998, sec="Fourth generation", cats=["Pontiac Firebird (4th generation)"]),
    ], exclude=("knight rider", "kitt")),
    F("Dodge Challenger", "Dodge", "pony car", "an American pony car", "Dodge Challenger", [
        G("gen1", (1970, 1974), 1970, "Dodge Challenger (1970)", cats=["Dodge Challenger (E-body)"]),
        G("gen3", (2008, 2023), 2015, "Dodge Challenger (2008)", cats=["Dodge Challenger (LC)"]),
    ]),
    F("Plymouth Barracuda", "Plymouth", "pony car", "an American pony car", "Plymouth Barracuda", [
        G("gen1", (1964, 1966), 1965, sec="First generation", cats=["Plymouth Barracuda (1964-1966)"]),
        G("gen2", (1967, 1969), 1968, sec="Second generation", cats=["Plymouth Barracuda (1967-1969)"]),
        G("gen3", (1970, 1974), 1970, sec="Third generation", cats=["Plymouth Barracuda (E-body)"]),
    ]),
    # ---- muscle cars -------------------------------------------------------------------
    F("Dodge Charger", "Dodge", "muscle car", "an American muscle car", "Dodge Charger", [
        G("gen1", (1966, 1967), 1966, "Dodge Charger (1966)", sec="First generation",
          cats=["Dodge Charger (B-body; 1966-1967)"]),
        G("gen2", (1968, 1970), 1969, "Dodge Charger (1966)", sec="Second generation",
          cats=["Dodge Charger (B-body; 1968-1970)"]),
        G("gen3", (1971, 1974), 1972, "Dodge Charger (1966)", sec="Third generation",
          cats=["Dodge Charger (B-body; 1971-1974)"]),
        G("gen5", (1982, 1987), 1986, "Dodge Charger (1981)", cats=["Dodge Charger (L-body)"]),
        G("gen6", (2006, 2010), 2006, "Dodge Charger (2006)", cats=["Dodge Charger (2005)"]),
        G("gen7", (2011, 2023), 2015, "Dodge Charger (2006)", cats=["Dodge Charger (LD)"]),
        G("gen8", (2024, NOW), 2025, "Dodge Charger (2024)", cats=["Dodge Charger (2024)"]),
    ], exclude=("general lee", "daytona", "superbird", "dukes")),
    F("Pontiac GTO", "Pontiac", "muscle car", "an American muscle car", "Pontiac GTO", [
        G("gen1", (1964, 1967), 1966, sec="First generation", cats=["Pontiac GTO (A-body)"], strict=True),
        G("gen2", (1968, 1972), 1969, sec="Second generation", cats=["Pontiac GTO (A-body)"], strict=True),
        G("gen5", (2004, 2006), 2004, sec="Fifth generation", cats=["Pontiac GTO (2004)"]),
    ]),
    F("Chevrolet Chevelle", "Chevrolet", "muscle car", "an American muscle car", "Chevrolet Chevelle", [
        G("gen1", (1964, 1967), 1966, sec="First generation", cats=["Chevrolet Chevelle (1st generation)"]),
        G("gen2", (1968, 1972), 1970, sec="Second generation", cats=["Chevrolet Chevelle (2nd generation)"]),
        G("gen3", (1973, 1977), 1975, sec="Third generation", cats=["Chevrolet Chevelle (3rd generation)"]),
    ], exclude=("wagon", "el camino")),
    F("Plymouth Road Runner", "Plymouth", "muscle car", "an American muscle car", "Plymouth Road Runner", [
        G("gen1", (1968, 1970), 1969, sec="First generation", cats=["Plymouth Road Runner (B-body)"], strict=True),
        G("gen2", (1971, 1974), 1972, sec="Second generation", cats=["Plymouth Road Runner (B-body)"], strict=True),
    ], exclude=("superbird",)),
    # ---- sports cars -------------------------------------------------------------------
    F("Chevrolet Corvette", "Chevrolet", "sports car", "an American sports car", "Chevrolet Corvette", [
        G("c1", (1953, 1962), 1957, "Chevrolet Corvette (C1)", cats=["Chevrolet Corvette C1"]),
        G("c2", (1963, 1967), 1963, "Chevrolet Corvette (C2)", cats=["Chevrolet Corvette C2"]),
        G("c3", (1968, 1982), 1978, "Chevrolet Corvette (C3)", cats=["Chevrolet Corvette C3"]),
        G("c4", (1984, 1996), 1990, "Chevrolet Corvette (C4)", cats=["Chevrolet Corvette C4"]),
        G("c5", (1997, 2004), 1999, "Chevrolet Corvette (C5)", cats=["Chevrolet Corvette C5"]),
        G("c6", (2005, 2013), 2008, "Chevrolet Corvette (C6)", cats=["Chevrolet Corvette C6"]),
        G("c7", (2014, 2019), 2016, "Chevrolet Corvette (C7)", cats=["Chevrolet Corvette C7"]),
        G("c8", (2020, NOW), 2020, "Chevrolet Corvette (C8)", cats=["Chevrolet Corvette C8"]),
    ], exclude=("callaway", "mako", "manta ray", "speed racer", "c5-r", "c6.r", "c7.r", "c8.r",
                "gt3", "gt2", "gt1")),
    F("Porsche 911", "Porsche", "sports car", "a German sports car", "Porsche 911", [
        G("original", (1964, 1973), 1965, "Porsche 911 (classic)", cats=["Porsche 911 classic"],
          ok="The classic-911 article covers 1964–1989 in one infobox; its own text dates the "
             "original series 1964–1973 and the G-series 1974–1989."),
        G("g-series", (1974, 1989), 1985, "Porsche 911 (classic)", cats=["Porsche 911 G-series"],
          ok="Same classic-911 article (1964–1989); the G-series is its 1974–1989 second half."),
        G("964", (1989, 1994), 1991, "Porsche 911 (964)", cats=["Porsche 964"]),
        G("993", (1994, 1998), 1996, "Porsche 911 (993)", cats=["Porsche 993"]),
        G("996", (1997, 2004), 2001, "Porsche 911 (996)", cats=["Porsche 996"]),
        G("997", (2004, 2012), 2005, "Porsche 911 (997)", cats=["Porsche 997"]),
        G("991", (2011, 2019), 2015, "Porsche 991", cats=["Porsche 991"]),
        G("992", (2019, NOW), 2025, "Porsche 911 (992)", cats=["Porsche 992"]),
    ], exclude=("912", "930 turbo", "gt3", "gt2", "rsr", "safari", "dakar", "singer", "ruf")),
    F("Nissan Z-car", "Nissan", "sports car", "a Japanese sports car", "Nissan Z-car", [
        G("s30", (1969, 1978), 1972, "Nissan Fairlady Z (S30)",
          cats=["Datsun 240Z", "Nissan Fairlady Z (S30)", "Datsun 280Z"], maker=["Datsun", "Nissan"]),
        G("s130", (1978, 1983), 1980, "Nissan Fairlady Z (S130)", cats=["Nissan Fairlady Z (S130)"],
          maker=["Datsun", "Nissan"]),
        G("z31", (1983, 1989), 1986, "Nissan 300ZX", sec="Z31", cats=["Nissan 300ZX (Z31)"]),
        G("z32", (1989, 2000), 1992, "Nissan 300ZX", sec="Z32", cats=["Nissan 300ZX (Z32)"]),
        G("z33", (2003, 2009), 2005, "Nissan 350Z", cats=["Nissan 350Z"]),
        G("z34", (2009, 2020), 2012, "Nissan 370Z", cats=["Nissan 370Z"]),
        G("rz34", (2023, NOW), 2023, "Nissan Z (RZ34)", cats=["Nissan Z (RZ34)"]),
    ], aliases=["Datsun 240Z", "Nissan 300ZX", "Nissan 350Z", "Nissan 370Z"]),
    F("Toyota Supra", "Toyota", "sports car", "a Japanese sports car", "Toyota Supra", [
        G("a40", (1979, 1981), 1979, sec="First generation", cats=["Toyota Supra (A40/A50)"]),
        G("a60", (1982, 1986), 1984, sec="Second generation", cats=["Toyota Supra (A60)"]),
        G("a70", (1986, 1993), 1989, sec="Third generation", cats=["Toyota Supra (A70)"]),
        G("a80", (1993, 2002), 1999, sec="Fourth generation", cats=["Toyota Supra (A80)"]),
        G("a90", (2020, NOW), 2020, "Toyota GR Supra", cats=["Toyota GR Supra"]),
    ], exclude=("fast and furious", "fast & furious")),
    F("Dodge Viper", "Dodge", "sports car", "an American sports car", "Dodge Viper", [
        G("sr2", (1996, 2002), 1997, "Dodge Viper (SR II)", cats=["Dodge Viper (SR II)"]),
        G("zb1", (2003, 2006), 2004, "Dodge Viper (ZB I)", cats=["Dodge Viper (ZB I)"]),
        G("vx1", (2013, 2017), 2017, "Dodge Viper (VX I)", cats=["Dodge Viper (VX I)"]),
    ], exclude=("gts-r", "acr-x")),
    F("Ford GT", "Ford", "sports car", "an American supercar", "Ford GT", [
        G("gen1", (2005, 2006), 2005, sec="First generation", cats=["Ford GT (1st generation)"]),
        G("gen2", (2017, 2022), 2017, sec="Second generation", cats=["Ford GT (2nd generation)"]),
    ], exclude=("gt40", "le mans", "mk iv", "mkiv", "gte")),
    F("Jaguar E-Type", "Jaguar", "sports car", "a British sports car", "Jaguar E-Type", [
        G("e-type", (1961, 1974), 1963, "Jaguar E-Type", cats=["Jaguar E-Type"]),
    ], exclude=("lightweight", "low drag", "eagle", "e-type zero")),
    F("Porsche 356", "Porsche", "sports car", "a German sports car", "Porsche 356", [
        G("356", (1948, 1965), 1958, "Porsche 356", cats=["Quality images of Porsche 356", "Porsche 356 coupes"]),
    ], exclude=("speedster replica", "outlaw", "550")),
    # ---- roadsters ---------------------------------------------------------------------
    F("Mercedes-Benz SL", "Mercedes-Benz", "convertible roadster", "a German roadster",
      "Mercedes-Benz SL-Class", [
          G("w198", (1954, 1963), 1955, "Mercedes-Benz 300 SL", sec="W198",
            cats=["Mercedes-Benz 300 SL", "Mercedes-Benz W198"]),
          G("w113", (1963, 1971), 1967, "Mercedes-Benz W113", sec="W113", cats=["Mercedes-Benz W113"]),
          G("r107", (1971, 1989), 1975, "Mercedes-Benz R107 and C107", sec="R107",
            cats=["Mercedes-Benz R107 SL"], exclude=("slc", "c107", "c 107")),
          G("r129", (1989, 2001), 1995, "Mercedes-Benz SL-Class (R129)", sec="R129", cats=["Mercedes-Benz R129"]),
          G("r230", (2001, 2011), 2005, "Mercedes-Benz SL-Class (R230)", sec="R230", cats=["Mercedes-Benz R230"]),
          G("r231", (2012, 2020), 2015, "Mercedes-Benz SL-Class (R231)", sec="R231", cats=["Mercedes-Benz R231"]),
          G("r232", (2022, NOW), 2025, "Mercedes-Benz SL (R232)", sec="R232", cats=["Mercedes-AMG R232"]),
      ], exclude=("w194", "slr", "sls", "190 sl", "190sl", "w121", "carrera panamericana")),
    F("MG MGB", "MG", "convertible roadster", "a British roadster", "MG MGB", [
        G("mgb", (1962, 1980), 1970, "MG MGB", cats=["MG B Roadster"]),
    ]),
    F("Triumph Spitfire", "Triumph", "convertible roadster", "a British roadster", "Triumph Spitfire", [
        G("spitfire", (1962, 1980), 1970, "Triumph Spitfire", cats=["Triumph Spitfire"]),
    ]),
    F("Austin-Healey 3000", "Austin-Healey", "convertible roadster", "a British roadster",
      "Austin-Healey 3000", [
          G("3000", (1959, 1967), 1962, "Austin-Healey 3000", cats=["Austin-Healey 3000"]),
      ]),
    F("Alfa Romeo Spider", "Alfa Romeo", "convertible roadster", "an Italian roadster",
      "Alfa Romeo Spider", [
          G("spider", (1966, 1993), 1967, "Alfa Romeo Spider", cats=["Alfa Romeo Spider"]),
      ]),
    F("Mazda MX-5 Miata", "Mazda", "convertible roadster", "a Japanese roadster", "Mazda MX-5", [
        G("na", (1989, 1997), 1990, "Mazda MX-5 (NA)", cats=["Mazda MX-5 (NA)"]),
        G("nb", (1998, 2005), 2001, "Mazda MX-5 (NB)", cats=["Mazda MX-5 (NB)"]),
        G("nc", (2006, 2015), 2008, "Mazda MX-5 (NC)", cats=["Mazda MX-5 (NC)"]),
        G("nd", (2016, NOW), 2016, "Mazda MX-5 (ND)", cats=["Mazda MX-5 (ND)"]),
    ], aliases=["Mazda MX-5", "Mazda Miata"], exclude=("cup", "spec miata")),
    F("Porsche Boxster", "Porsche", "convertible roadster", "a German roadster",
      "Porsche Boxster and Cayman", [
          G("986", (1996, 2004), 1997, "Porsche 986", cats=["Porsche 986"]),
          G("981", (2012, 2016), 2013, "Porsche 981", cats=["Porsche 981"]),
          G("982", (2016, 2025), 2018, "Porsche 982", cats=["Porsche 982"]),
      ], exclude=("cayman",), must="boxster"),
    # ---- luxury cars -------------------------------------------------------------------
    F("Ford Thunderbird", "Ford", "luxury car", "an American personal luxury car", "Ford Thunderbird", [
        G("gen1", (1955, 1957), 1957, "Ford Thunderbird (first generation)", cats=["Ford Thunderbird (first generation)"]),
        G("gen2", (1958, 1960), 1959, "Ford Thunderbird (second generation)", cats=["Ford Thunderbird (second generation)"]),
        G("gen3", (1961, 1963), 1962, "Ford Thunderbird (third generation)", cats=["Ford Thunderbird (third generation)"]),
        G("gen4", (1964, 1966), 1965, "Ford Thunderbird (fourth generation)", cats=["Ford Thunderbird (fourth generation)"]),
        G("gen5", (1967, 1971), 1967, "Ford Thunderbird (fifth generation)", cats=["Ford Thunderbird (fifth generation)"]),
        G("gen6", (1972, 1976), 1974, "Ford Thunderbird (sixth generation)", cats=["Ford Thunderbird (sixth generation)"]),
        G("gen7", (1977, 1979), 1977, "Ford Thunderbird (seventh generation)", cats=["Ford Thunderbird (seventh generation)"]),
        G("gen9", (1983, 1988), 1985, "Ford Thunderbird (ninth generation)", cats=["Ford Thunderbird (ninth generation)"]),
        G("gen10", (1989, 1997), 1997, "Ford Thunderbird (tenth generation)", cats=["Ford Thunderbird (tenth generation)"]),
        G("gen11", (2002, 2005), 2002, "Ford Thunderbird (eleventh generation)", cats=["Ford Thunderbird (eleventh generation)"]),
    ], exclude=("nascar",)),
    F("Cadillac Eldorado", "Cadillac", "luxury car", "an American luxury car", "Cadillac Eldorado", [
        G("gen1", (1953, 1953), 1953, sec="First generation", cats=["Cadillac Eldorado (1st generation)"], strict=True),
        G("gen2", (1954, 1956), 1955, sec="Second generation", cats=["Cadillac Eldorado (2nd generation)"], strict=True),
        G("gen4", (1959, 1960), 1959, sec="Fourth generation", cats=["Cadillac Eldorado (3rd generation)"], strict=True),
        G("gen8", (1967, 1970), 1967, sec="Eighth generation", cats=["Cadillac Eldorado (8th generation)"], strict=True),
        G("gen9", (1971, 1978), 1976, sec="Ninth generation", cats=["Cadillac Eldorado (9th generation)"], strict=True),
        G("gen10", (1979, 1985), 1980, sec="Tenth generation", cats=["Cadillac Eldorado (10th generation)"]),
        G("gen11", (1986, 1991), 1988, sec="Eleventh generation", cats=["Cadillac Eldorado (11th generation)"]),
        G("gen12", (1992, 2002), 1996, sec="Twelfth generation", cats=["Cadillac Eldorado (12th generation)"]),
    ], aliases=["Cadillac Eldorado Biarritz"]),
    F("Lincoln Continental", "Lincoln", "luxury car", "an American luxury car", "Lincoln Continental", [
        G("gen1", (1940, 1948), 1941, sec="First generation", cats=["Lincoln Continental (first generation)"]),
        G("gen3", (1958, 1960), 1958, sec="Third generation", cats=["Lincoln Continental (third generation)"]),
        G("gen4", (1961, 1969), 1961, sec="Fourth generation", cats=["Lincoln Continental (fourth generation)"]),
        G("gen5", (1970, 1979), 1977, sec="Fifth generation", cats=["Lincoln Continental (fifth generation)"]),
        G("gen7", (1982, 1987), 1982, sec="Seventh generation", cats=["Lincoln Continental (seventh generation)"]),
        G("gen8", (1988, 1994), 1990, sec="Eighth generation", cats=["Lincoln Continental (eighth generation)"]),
        G("gen9", (1995, 2002), 2002, sec="Ninth generation", cats=["Lincoln Continental (ninth generation)"]),
        G("gen10", (2017, 2020), 2017, sec="Tenth generation", cats=["Lincoln Continental (tenth generation)"]),
    ], exclude=("mark ii", "mark iii", "mark iv", "mark v", "town car", "kennedy", "x-100", "sx-100")),
    F("Buick Riviera", "Buick", "luxury car", "an American personal luxury car", "Buick Riviera", [
        G("gen1", (1963, 1965), 1963, sec="First generation", cats=["Buick Riviera (E-body; 1963-1965)"]),
        G("gen3", (1971, 1973), 1971, sec="Third generation", cats=["Buick Riviera (E-body; 1971-1973)"]),
        G("gen6", (1979, 1985), 1983, sec="Sixth generation", cats=["Buick Riviera (E-body FWD)"], strict=True),
        G("gen8", (1995, 1999), 1995, sec="Eighth generation", cats=["Buick Riviera (G-body)"], strict=True),
    ]),
    # The S-Class name began in 1972. Wikipedia lists the Ponton and the Fintail as its
    # predecessors, and they were once in this line — which let a round ask "which one is a
    # 1955 Mercedes S-Class?" about a car that was never called one. They are lines of their
    # own now, asked about by the names people knew them by.
    F("Mercedes Ponton", "Mercedes-Benz", "luxury car", "a German luxury car", "Mercedes-Benz W180", [
        G("w180", (1954, 1959), 1955, "Mercedes-Benz W180", sec="W180", cats=["Mercedes-Benz W180"]),
    ]),
    F("Mercedes Fintail", "Mercedes-Benz", "luxury car", "a German luxury car", "Mercedes-Benz W111", [
        G("w111", (1959, 1968), 1962, "Mercedes-Benz W111", sec="Fintail", cats=["Mercedes-Benz W111"]),
    ]),
    F("Mercedes-Benz S-Class", "Mercedes-Benz", "luxury car", "a German luxury car", "Mercedes-Benz S-Class", [
        G("w116", (1972, 1980), 1975, "Mercedes-Benz W116", cats=["Mercedes-Benz W116"]),
        G("w126", (1979, 1991), 1985, "Mercedes-Benz W126", cats=["Mercedes-Benz W126"]),
        G("w140", (1991, 1998), 1995, "Mercedes-Benz W140", cats=["Mercedes-Benz W140"]),
        G("w220", (1998, 2005), 2000, "Mercedes-Benz S-Class (W220)", cats=["Mercedes-Benz W220"]),
        G("w221", (2005, 2013), 2007, "Mercedes-Benz S-Class (W221)", cats=["Mercedes-Benz W221"]),
        G("w222", (2013, 2020), 2015, "Mercedes-Benz S-Class (W222)", cats=["Mercedes-Benz W222"]),
        G("w223", (2020, NOW), 2021, "Mercedes-Benz S-Class (W223)", sec="Seventh generation",
          cats=["Mercedes-Benz W223"]),
    ], exclude=("pullman", "guard", "c126", "c140", "c215", "c216", "c217", "a217", "coupe", "coupé",
                "cabriolet", "brabus", "maybach")),
    F("Rolls-Royce Phantom", "Rolls-Royce", "luxury car", "a British luxury car", "Rolls-Royce Phantom", [
        G("i", (1925, 1931), 1927, "Rolls-Royce Phantom I", cats=["Rolls-Royce Phantom I"], cluster="vintage car"),
        G("ii", (1929, 1935), 1932, "Rolls-Royce Phantom II", cats=["Rolls-Royce Phantom II"], cluster="vintage car"),
        G("iii", (1936, 1939), 1937, "Rolls-Royce Phantom III", cats=["Rolls-Royce Phantom III"], cluster="vintage car"),
        G("v", (1959, 1968), 1962, "Rolls-Royce Phantom V", cats=["Rolls-Royce Phantom V"]),
        G("vi", (1968, 1990), 1982, "Rolls-Royce Phantom VI", cats=["Rolls-Royce Phantom VI"]),
        G("vii", (2003, 2017), 2005, "Rolls-Royce Phantom VII", cats=["Rolls-Royce Phantom VII"]),
        G("viii", (2017, NOW), 2020, "Rolls-Royce Phantom VIII", cats=["Rolls-Royce Phantom VIII"]),
    ], exclude=("drophead", "coupé", "coupe")),
    F("Jaguar XJ", "Jaguar", "luxury car", "a British luxury car", "Jaguar XJ", [
        G("series1", (1968, 1973), 1970, sec="Series I", cats=["Jaguar XJ6 (Series I)", "Jaguar XJ Series I"]),
        G("series3", (1979, 1992), 1985, sec="Series III", cats=["Jaguar XJ Series III", "Jaguar XJ6 (Series III)"]),
        G("xj40", (1986, 1994), 1990, "Jaguar XJ (XJ40)", cats=["Jaguar XJ40"]),
        G("x300", (1994, 1997), 1995, "Jaguar XJ (X300)", cats=["Jaguar XJ (X300)"]),
        G("x308", (1997, 2003), 2000, "Jaguar XJ (X308)", cats=["Jaguar XJ (X308)"]),
        G("x350", (2003, 2009), 2005, "Jaguar XJ (X350)", cats=["Jaguar XJ (X350)"]),
        G("x351", (2010, 2019), 2012, "Jaguar XJ (X351)", cats=["Jaguar XJ (X351)"]),
    ], exclude=("xjs", "xj-s", "xjc", "xj-c", "xj220", "xj13", "spider", "daimler")),
    F("BMW 7 Series", "BMW", "luxury car", "a German luxury car", "BMW 7 Series", [
        G("e23", (1977, 1986), 1980, "BMW 7 Series (E23)", cats=["BMW E23"]),
        G("e32", (1987, 1994), 1990, "BMW 7 Series (E32)", cats=["BMW E32"]),
        G("e38", (1995, 2001), 2000, "BMW 7 Series (E38)", cats=["BMW E38"]),
        G("e65", (2002, 2008), 2003, "BMW 7 Series (E65)", cats=["BMW E65", "BMW E66"]),
        G("f01", (2008, 2015), 2010, "BMW 7 Series (F01)", cats=["BMW F01", "BMW F02"]),
        G("g11", (2016, 2022), 2020, "BMW 7 Series (G11)", cats=["BMW G11", "BMW G12"]),
        G("g70", (2023, NOW), 2023, "BMW 7 Series (G70)", cats=["BMW G70"]),
    ], exclude=("alpina", "protection", "schnitzer")),
    F("Lexus LS", "Lexus", "luxury car", "a Japanese luxury car", "Lexus LS", [
        G("xf10", (1990, 1994), 1990, sec="First generation", cats=["Lexus LS (XF10)"]),
        G("xf40", (2007, 2017), 2010, "Lexus LS (XF40)", cats=["Lexus LS (XF40)"]),
        G("xf50", (2018, NOW), 2018, sec="Fifth generation", cats=["Lexus LS (XF50)"]),
    ]),
    F("Lincoln Town Car", "Lincoln", "luxury car", "an American luxury car", "Lincoln Town Car", [
        G("gen1", (1981, 1989), 1985, sec="First generation", cats=["Lincoln Town Car (1981)"]),
        G("gen2", (1990, 1997), 1992, sec="Second generation", cats=["Lincoln Town Car (1990)"]),
        G("gen3", (1998, 2011), 2005, sec="Third generation", cats=["Lincoln Town Car (2003)", "Lincoln Town Car (1998)"]),
    ], exclude=("hearse", "stretch", "limo", "funeral")),
    F("Mercedes-Benz E-Class", "Mercedes-Benz", "luxury car", "a German executive car", "Mercedes-Benz E-Class", [
        G("w124", (1985, 1995), 1990, "Mercedes-Benz W124", cats=["Mercedes-Benz W124"]),
        G("w210", (1996, 2002), 2000, "Mercedes-Benz E-Class (W210)", cats=["Mercedes-Benz W210"]),
        G("w211", (2003, 2009), 2005, "Mercedes-Benz E-Class (W211)", cats=["Mercedes-Benz W211"]),
        G("w212", (2009, 2016), 2012, "Mercedes-Benz E-Class (W212)", cats=["Mercedes-Benz W212"]),
        G("w213", (2017, 2023), 2018, "Mercedes-Benz E-Class (W213)", cats=["Mercedes-Benz W213"]),
        G("w214", (2024, NOW), 2024, "Mercedes-Benz E-Class (W214)", cats=["Mercedes-Benz W214"]),
    ], exclude=("estate", "t-modell", "wagon", "coupe", "coupé", "cabrio", "s124", "s210", "s211",
                "s212", "s213", "s214", "c124", "c207", "c238", "a207", "a238", "brabus", "amg")),
    # ---- full-size American cars --------------------------------------------------------
    F("Chevrolet Impala", "Chevrolet", "full-size car", "an American full-size car", "Chevrolet Impala", [
        G("gen1", (1958, 1958), 1958, sec="First generation", cats=["1958 Chevrolet Bel Air Impala"]),
        G("gen2", (1959, 1960), 1959, sec="Second generation", cats=["Chevrolet Impala (1959–1960)"]),
        G("gen3", (1961, 1964), 1962, sec="Third generation", cats=["Chevrolet Impala (1961–1964)"]),
        G("gen4", (1965, 1970), 1967, "Chevrolet Impala (fourth generation)", cats=["Chevrolet Impala (1965–1970)"]),
        G("gen5", (1971, 1976), 1973, "Chevrolet Impala (fifth generation)", cats=["Chevrolet Impala (1971–1976)"]),
        G("gen6", (1977, 1985), 1978, sec="Sixth generation", cats=["Chevrolet Impala (1977–1985)"]),
        G("gen7", (1994, 1996), 1995, sec="Seventh generation", cats=["Chevrolet Impala SS"], strict=True),
        G("gen8", (2000, 2005), 2000, sec="Eighth generation", cats=["Chevrolet Impala (2000–2005)"]),
        G("gen9", (2006, 2013), 2008, sec="Ninth generation", cats=["Chevrolet Impala (2006–2016)"]),
        G("gen10", (2014, 2020), 2020, sec="Tenth generation", cats=["Chevrolet Impala (2014–2020)"]),
    ], exclude=("lowrider", "wagon", "nascar")),
    F("Chevrolet Bel Air", "Chevrolet", "full-size car", "an American full-size car", "Chevrolet Bel Air", [
        G("gen1", (1950, 1954), 1953, sec="First generation", cats=["Chevrolet Bel Air (1950–1954)"]),
        G("gen2", (1955, 1957), 1957, sec="Second generation", cats=["Chevrolet Bel Air (1955–1957)"]),
        G("gen5", (1961, 1964), 1962, sec="Fifth generation", cats=["Chevrolet Bel Air (1961–1964)"]),
        G("gen6", (1965, 1970), 1966, sec="Sixth generation", cats=["Chevrolet Bel Air (1965–1970)"]),
    ], exclude=("nomad", "wagon", "impala", "lowrider")),
    F("Ford Galaxie", "Ford", "full-size car", "an American full-size car", "Ford Galaxie", [
        G("gen1", (1959, 1959), 1959, sec="First generation", cats=["1959 Ford Galaxie"]),
        G("gen2", (1960, 1964), 1963, sec="Second generation", cats=[]),
        G("gen3", (1965, 1968), 1966, sec="Third generation", cats=[]),
        G("gen4", (1969, 1974), 1970, sec="Fourth generation", cats=[]),
    ], exclude=("australia", "brazil", "landau", "ltd")),
    F("Plymouth Fury", "Plymouth", "full-size car", "an American full-size car", "Plymouth Fury", [
        G("gen1", (1959, 1959), 1959, sec="First generation", cats=["1959 Plymouth Fury"]),
        G("gen3", (1962, 1964), 1963, sec="Third generation", cats=["Plymouth Fury (B-body)"], strict=True),
        G("gen4", (1965, 1968), 1966, sec="Fourth generation", cats=["Plymouth Fury (C-body)"], strict=True),
        G("gen5", (1969, 1973), 1970, sec="Fifth generation", cats=["Plymouth Fury (C-body)"], strict=True),
    ], exclude=("christine", "police", "gran fury")),
    F("Chevrolet Caprice", "Chevrolet", "full-size car", "an American full-size car", "Chevrolet Caprice", [
        G("gen1", (1966, 1970), 1966, sec="First generation", cats=["Chevrolet Caprice (1966–1970)", "1965 Chevrolet Caprice"]),
        G("gen3", (1977, 1990), 1985, sec="Third generation", cats=["Chevrolet Caprice (1977–1990)"]),
        G("gen4", (1991, 1996), 1994, sec="Fourth generation", cats=["Chevrolet Caprice (1991–1996)"]),
    ], exclude=("wagon", "lowrider", "donk", "9c1", "ppv")),
    F("Ford Crown Victoria", "Ford", "full-size car", "an American full-size car", "Ford Crown Victoria", [
        G("gen1", (1992, 1997), 1995, sec="First generation", cats=["Ford Crown Victoria (1992)"]),
        G("gen2", (1998, 2012), 2005, sec="Second generation", cats=["Ford Crown Victoria (1998)"]),
    ], exclude=("interceptor", "cvpi", "sheriff", "patrol")),
    # ---- pickups -----------------------------------------------------------------------
    F("Ford F-Series", "Ford", "pickup truck", "an American pickup truck", "Ford F-Series", [
        G("gen1", (1948, 1952), 1950, "Ford F-Series (first generation)", cats=["Ford F-Series (1948)"]),
        G("gen2", (1953, 1956), 1956, "Ford F-Series (second generation)", cats=["Ford F-Series (1953)"]),
        G("gen3", (1957, 1960), 1959, "Ford F-Series (third generation)", cats=["Ford F-Series (1957)"]),
        G("gen4", (1961, 1966), 1965, "Ford F-Series (fourth generation)", cats=["Ford F-Series (1961)"]),
        G("gen5", (1967, 1972), 1970, "Ford F-Series (fifth generation)", cats=["Ford F-Series (1967)"]),
        G("gen6", (1973, 1979), 1977, "Ford F-Series (sixth generation)", cats=["Ford F-Series (1973)"]),
        G("gen7", (1980, 1986), 1985, "Ford F-Series (seventh generation)", cats=["Ford F-Series (1980)"]),
        G("gen8", (1987, 1991), 1990, "Ford F-Series (eighth generation)", cats=["Ford F-Series (1987)"]),
        G("gen9", (1992, 1997), 1995, "Ford F-Series (ninth generation)", cats=["Ford F-Series (1992)"]),
        G("gen10", (1997, 2004), 2000, "Ford F-Series (tenth generation)", cats=["Ford F-Series (1997)"]),
        G("gen11", (2004, 2008), 2006, "Ford F-Series (eleventh generation)", cats=["Ford F-Series (2004)"]),
        G("gen12", (2009, 2014), 2010, "Ford F-Series (twelfth generation)", cats=["Ford F-Series (2009)"]),
        G("gen13", (2015, 2020), 2017, "Ford F-Series (thirteenth generation)", cats=["Ford F-Series (2015)", "Ford F-Series (2017)"]),
        G("gen14", (2021, NOW), 2023, "Ford F-Series (fourteenth generation)", cats=["Ford F-Series (2021)", "Ford F-Series (2023)"]),
    ], aliases=["Ford F-100", "Ford F-150"],
      exclude=("tow", "wrecker", "bus", "camper", "camping", "dump", "flatbed", "medium",
               "super duty", "f-350", "f-450", "f-550", "f-650", "f-750", "raptor", "lightning",
               "ranger", "monster", "lifted", "rail")),
    F("Chevrolet C/K", "Chevrolet", "pickup truck", "an American pickup truck", "Chevrolet C/K", [
        G("gen1", (1960, 1966), 1962, "Chevrolet C/K (first generation)", cats=["Chevrolet C/K (1960)"]),
        G("gen2", (1967, 1972), 1970, "Chevrolet C/K (second generation)", cats=["Chevrolet C/K (1967)"]),
        G("gen3", (1973, 1991), 1982, "Chevrolet C/K (third generation)", cats=["Chevrolet C/K (1973)", "Chevrolet C/K (1981)"]),
        G("gen4", (1988, 2000), 1995, "Chevrolet C/K (fourth generation)", cats=["Chevrolet C/K (1988)"]),
    ], aliases=["Chevrolet C-10", "Chevrolet C10"],
      exclude=GM_TWINS + ("blazer", "suburban", "jimmy", "tow", "dump", "lifted", "lowrider")),
    F("Chevrolet Silverado", "Chevrolet", "pickup truck", "an American pickup truck", "Chevrolet Silverado", [
        G("gen1", (1999, 2006), 2002, "Chevrolet Silverado (first generation)", cats=["Chevrolet Silverado (GMT800/GMT880)"]),
        G("gen2", (2007, 2013), 2010, "Chevrolet Silverado (second generation)", cats=["Chevrolet Silverado (GMT901/GMT911)"]),
        G("gen3", (2014, 2018), 2016, sec="Third generation", cats=["Chevrolet Silverado (GMTK2XX)"]),
        G("gen4", (2019, NOW), 2022, sec="Fourth generation", cats=["Chevrolet Silverado (GMTT1XX)"]),
    ], exclude=GM_TWINS + ("chassis cab", "silverado ev", "tow", "lifted", "police", "medium duty")),
    F("Dodge Ram", "Dodge", "pickup truck", "an American pickup truck", "Ram pickup", [
        G("gen1", (1981, 1993), 1985, sec="First generation", cats=["Dodge D/W Ram"]),
        G("gen2", (1994, 2002), 1996, sec="Second generation", cats=["Dodge BR/BE Ram"]),
        G("gen3", (2002, 2008), 2005, sec="Third generation", cats=["Dodge DR/DH Ram"]),
        G("gen4", (2009, 2018), 2012, "Ram 1500 (DS)", cats=["Ram 1500 (DS)"], maker=["Ram", "Dodge"],
          ok="Wikipedia gives 2009–2024 because the old truck stayed on sale as the 'Ram 1500 "
             "Classic' beside its successor; the generation proper ran 2009–2018."),
        G("gen5", (2019, NOW), 2025, "Ram 1500 (DT)", cats=["Ram 1500 (DT)"], maker=["Ram"]),
    ], aliases=["Ram 1500", "Dodge Ram 1500"],
      exclude=("ram 50", "rampage", "ramcharger", "ram van", "trx", "rev", "chassis", "tow",
               "lifted", "power wagon")),
    F("Toyota Hilux", "Toyota", "pickup truck", "a Japanese pickup truck", "Toyota Hilux", [
        G("gen1", (1968, 1972), 1970, sec="First generation", cats=["Toyota HiLux (N10)"]),
        G("gen2", (1972, 1978), 1975, sec="Second generation", cats=["Toyota HiLux (N20)"]),
        G("gen3", (1978, 1983), 1980, sec="Third generation", cats=["Toyota HiLux (N30/N40)"]),
        G("gen4", (1983, 1988), 1985, sec="Fourth generation", cats=["Toyota HiLux (N50/N60/N70)"],
          ok="Infobox production is a list by market; the fourth generation's model years are 1984–1988."),
        G("gen5", (1988, 1997), 1990, sec="Fifth generation", cats=["Toyota HiLux (N80/N90/N100/N110)"]),
        G("gen6", (1997, 2006), 2000, sec="Sixth generation", cats=["Toyota HiLux (N140/N150/N160/N170)"]),
        G("gen7", (2004, 2015), 2010, sec="Seventh generation", cats=["Toyota HiLux (AN10/AN20/AN30)"]),
        G("gen8", (2015, 2025), 2018, sec="Eighth generation", cats=["Toyota HiLux (AN120/AN130)"],
          ok="Eighth generation 'May 2015 – present' until the ninth (2025) replaced it."),
    ], aliases=["Toyota HiLux"], exclude=("military", "technical", "surf", "sw4", "4runner",
                                          "camper", "camping", "top gear")),
    F("Toyota Tacoma", "Toyota", "pickup truck", "a Japanese pickup truck", "Toyota Tacoma", [
        G("gen1", (1995, 2004), 1996, sec="First generation", cats=["Toyota Tacoma (N140/N150/N160/N170)"]),
        G("gen2", (2005, 2015), 2010, sec="Second generation", cats=["Toyota Tacoma (N220/N240/N250/N260/N270)"]),
        G("gen3", (2016, 2023), 2016, sec="Third generation", cats=["Toyota Tacoma (N300)"]),
        G("gen4", (2024, NOW), 2024, sec="Fourth generation", cats=["Toyota Tacoma (N400)"]),
    ], exclude=("lifted",)),
    F("Chevrolet El Camino", "Chevrolet", "pickup truck", "an American car-based pickup", "Chevrolet El Camino", [
        G("gen1", (1959, 1960), 1959, sec="First generation", cats=["Chevrolet El Camino (Full-size)"]),
        G("gen3", (1968, 1972), 1970, sec="Third generation", cats=["Chevrolet El Camino (3rd generation)"]),
        G("gen5", (1978, 1987), 1980, sec="Fifth generation", cats=["Chevrolet El Camino (A/G-body)"]),
    ], exclude=("gmc", "sprint", "caballero", "south africa")),
    # ---- SUVs --------------------------------------------------------------------------
    F("Chevrolet Suburban", "Chevrolet", "SUV", "an American SUV", "Chevrolet Suburban", [
        G("gen1", (1935, 1940), 1937, sec="First generation", cats=["Chevrolet Carryall-Suburban (1935–1940)"]),
        G("gen3", (1947, 1955), 1950, sec="Third generation", cats=["Chevrolet Suburban (Advance-Design)"]),
        G("gen4", (1955, 1959), 1957, sec="Fourth generation", cats=["Chevrolet Suburban (Task-Force)"]),
        G("gen5", (1960, 1966), 1963, sec="Fifth generation", cats=["Chevrolet Suburban (1960-1966 C/K)"]),
        G("gen6", (1967, 1972), 1970, sec="Sixth generation", cats=["Chevrolet Suburban (1967-1972)"]),
        G("gen7", (1973, 1991), 1980, sec="Seventh generation", cats=["Chevrolet Suburban (1973-1980)", "Chevrolet Suburban (1981-1991)"]),
        G("gen8", (1992, 1999), 1995, "Chevrolet Suburban (eighth generation)", cats=["Chevrolet Suburban (GMT410)"]),
        G("gen9", (2000, 2006), 2003, sec="Ninth generation", cats=["Chevrolet Suburban (GMT830)"]),
        G("gen10", (2007, 2014), 2010, sec="Tenth generation", cats=["Chevrolet Suburban (GMT931)"]),
        G("gen11", (2015, 2020), 2017, sec="Eleventh generation", cats=["Chevrolet Suburban (GMTK2YC)"]),
        G("gen12", (2021, NOW), 2023, sec="Twelfth generation", cats=["Chevrolet Suburban (GMTT1YC)"]),
    ], exclude=GM_TWINS + ("police", "secret service", "ambulance", "fire", "lifted")),
    F("Toyota Land Cruiser", "Toyota", "SUV", "a Japanese four-wheel drive", "Toyota Land Cruiser", [
        G("j20", (1955, 1960), 1955, sec="J20", cats=["Toyota Land Cruiser (J20)"], cluster="off-roader"),
        G("j40", (1960, 1984), 1965, "Toyota Land Cruiser (J40)", cats=["Toyota Land Cruiser (J40)"],
          cluster="off-roader",
          ok="Infobox production is a list by market; Wikipedia's J40 section dates the series 1960–1984."),
        G("j55", (1967, 1980), 1975, sec="J50", cats=["Toyota Land Cruiser (J55)"], cluster="off-roader"),
        G("j60", (1980, 1992), 1985, sec="J60", cats=["Toyota Land Cruiser (J60)"]),
        G("j80", (1990, 1998), 1995, sec="J80", cats=["Toyota Land Cruiser (J80)"],
          ok="Infobox production is a list by market; the J80 was built 1990–1997/98."),
        G("j100", (1998, 2007), 2005, sec="J100", cats=["Toyota Land Cruiser (J100)"]),
        G("j200", (2008, 2021), 2015, sec="J200", cats=["Toyota Land Cruiser (J200)"]),
        G("j300", (2021, NOW), 2023, sec="J300", cats=["Toyota Land Cruiser (J300)"]),
    ], exclude=("prado", "j70", "j90", "j120", "j150", "lexus", "camper", "military", "technical",
                "ambulance")),
    F("Range Rover", "Land Rover", "SUV", "a British luxury SUV", "Range Rover", [
        G("classic", (1970, 1996), 1975, "Range Rover Classic", cats=["Range Rover Classic"]),
        G("p38a", (1994, 2002), 1996, "Range Rover (P38A)", cats=["Land Rover Range Rover (2nd generation)"]),
        G("l322", (2002, 2012), 2005, "Range Rover (L322)", cats=["Land Rover Range Rover (3rd generation)"]),
        G("l405", (2013, 2021), 2015, "Range Rover (L405)", cats=["Land Rover Range Rover (4th generation)"]),
        G("l460", (2022, NOW), 2025, "Range Rover (L460)", cats=["Land Rover Range Rover (5th generation)"]),
    ], exclude=("sport", "evoque", "velar", "police", "ambulance", "rally", "6x6", "stretch")),
    F("Jeep Cherokee", "Jeep", "SUV", "an American SUV", "Jeep Cherokee", [
        G("sj", (1974, 1983), 1975, "Jeep Cherokee (SJ)", cats=["Jeep Cherokee (SJ)"]),
        G("xj", (1984, 2001), 1995, "Jeep Cherokee (XJ)", cats=["Jeep Cherokee (XJ)"]),
        G("kl", (2014, 2023), 2015, "Jeep Cherokee (KL)", cats=["Jeep Cherokee (KL)"]),
    ], exclude=("grand cherokee", "wagoneer", "liberty", "lifted")),
    F("Ford Bronco", "Ford", "off-roader", "an American four-wheel drive", "Ford Bronco", [
        G("gen1", (1966, 1977), 1966, sec="First generation", cats=["Ford Bronco (1st generation)"]),
        G("gen2", (1978, 1979), 1978, sec="Second generation", cats=["Ford Bronco (2nd generation)"]),
        G("gen3", (1980, 1986), 1986, sec="Third generation", cats=["Ford Bronco (3rd generation)"]),
        G("gen4", (1987, 1991), 1989, sec="Fourth generation", cats=["Ford Bronco (4th generation)"]),
        G("gen5", (1992, 1996), 1995, sec="Fifth generation", cats=["Ford Bronco (5th generation)"]),
        G("gen6", (2021, NOW), 2021, sec="Sixth generation", cats=["Ford Bronco (6th generation)"]),
    ], exclude=("bronco sport", "bronco ii", "bronco new energy", "lifted", "police")),
    F("Toyota 4Runner", "Toyota", "SUV", "a Japanese SUV", "Toyota 4Runner", [
        G("gen1", (1984, 1989), 1985, sec="First generation", cats=["Toyota 4Runner (N60)"]),
        G("gen2", (1990, 1995), 1992, sec="Second generation", cats=["Toyota 4Runner (N120/N130)"]),
        G("gen3", (1996, 2002), 1998, sec="Third generation", cats=["Toyota 4Runner (N180)"]),
        G("gen4", (2003, 2009), 2005, sec="Fourth generation", cats=["Toyota 4Runner (N210)"]),
        G("gen5", (2010, 2024), 2015, sec="Fifth generation", cats=["Toyota 4Runner (N280)"]),
        G("gen6", (2025, NOW), 2025, sec="Sixth generation", cats=["Toyota 4Runner (N500)"]),
    ], exclude=("hilux surf", "lifted")),
    F("Ford Explorer", "Ford", "SUV", "an American SUV", "Ford Explorer", [
        G("gen1", (1991, 1994), 1991, sec="First generation", cats=["Ford Explorer (first generation)"]),
        G("gen2", (1995, 2001), 1998, sec="Second generation", cats=["Ford Explorer (second generation)"]),
        G("gen3", (2002, 2005), 2003, sec="Third generation", cats=["Ford Explorer (third generation)"]),
        G("gen5", (2011, 2019), 2011, sec="Fifth generation", cats=["Ford Explorer (fifth generation)"]),
        G("gen6", (2020, NOW), 2020, sec="Sixth generation", cats=["Ford Explorer (sixth generation)"]),
    ], exclude=("police", "interceptor", "sport trac", "explorer ev", "sheriff", "patrol")),
    F("Jeep Grand Cherokee", "Jeep", "SUV", "an American SUV", "Jeep Grand Cherokee", [
        G("zj", (1993, 1998), 1993, "Jeep Grand Cherokee (ZJ)", cats=["Jeep Grand Cherokee (ZJ)"]),
        G("wj", (1999, 2004), 2000, "Jeep Grand Cherokee (WJ)", cats=["Jeep Grand Cherokee (WJ)"]),
        G("wk", (2005, 2010), 2006, "Jeep Grand Cherokee (WK)", cats=["Jeep Grand Cherokee (WK)"]),
        G("wk2", (2011, 2022), 2014, "Jeep Grand Cherokee (WK2)", cats=["Jeep Grand Cherokee (WK2)"]),
        G("wl", (2022, NOW), 2022, sec="Fifth generation", cats=["Jeep Grand Cherokee (WL)"]),
    ], exclude=("police", "srt8", "trackhawk")),
    F("Chevrolet Tahoe", "Chevrolet", "SUV", "an American SUV", "Chevrolet Tahoe", [
        G("gen1", (1995, 2000), 1996, sec="First generation", cats=["Chevrolet Tahoe (GMT420)"],
          ok="The infobox mixes the GMC Yukon (from 1992) with the Tahoe, which went on sale for 1995."),
        G("gen2", (2000, 2006), 2003, sec="Second generation", cats=["Chevrolet Tahoe (GMT820)"]),
        G("gen3", (2007, 2014), 2010, sec="Third generation", cats=["Chevrolet Tahoe (GMT921)"]),
        G("gen4", (2015, 2020), 2016, sec="Fourth generation", cats=["Chevrolet Tahoe (GMTK2UC)"]),
        G("gen5", (2021, NOW), 2021, sec="Fifth generation", cats=["Chevrolet Tahoe (GMTT1UC)"]),
    ], exclude=GM_TWINS + ("police", "ppv", "sheriff", "patrol", "fire", "ems", "ambulance")),
    F("Cadillac Escalade", "Cadillac", "SUV", "an American luxury SUV", "Cadillac Escalade", [
        G("gen1", (1999, 2000), 1999, sec="First generation", cats=["Cadillac Escalade (GMT435)"]),
        G("gen2", (2002, 2006), 2003, sec="Second generation", cats=["Cadillac Escalade (GMT820)"]),
        G("gen3", (2007, 2014), 2010, sec="Third generation", cats=["Cadillac Escalade (GMT926)"]),
        G("gen4", (2015, 2020), 2017, sec="Fourth generation", cats=["Cadillac Escalade (GMTK2UL)"]),
        G("gen5", (2021, NOW), 2021, sec="Fifth generation", cats=["Cadillac Escalade (GMTT1UL)"]),
    ], exclude=("ext", "escalade iq", "stretch", "limo")),
    # ---- off-roaders -------------------------------------------------------------------
    F("Jeep Wrangler", "Jeep", "off-roader", "an American four-wheel drive", "Jeep Wrangler", [
        G("yj", (1987, 1995), 1990, "Jeep Wrangler (YJ)", cats=["Jeep Wrangler (YJ)"]),
        G("tj", (1997, 2006), 2000, "Jeep Wrangler (TJ)", cats=["Jeep Wrangler (TJ)"]),
        G("jk", (2007, 2018), 2010, "Jeep Wrangler (JK)", cats=["Jeep Wrangler (JK)"]),
        G("jl", (2018, NOW), 2020, "Jeep Wrangler (JL)", cats=["Jeep Wrangler (JL)"]),
    ], exclude=("popemobile", "lifted", "rock crawl", "military", "gladiator")),
    F("Jeep CJ", "Jeep", "off-roader", "an American four-wheel drive", "Jeep CJ", [
        G("cj-2a", (1945, 1949), 1946, sec="CJ-2A", cats=["Jeep CJ-2A"], maker=["Willys"]),
        G("cj-3b", (1953, 1968), 1966, sec="CJ-3B", cats=["Jeep CJ-3B"], maker=["Willys"]),
        G("cj-5", (1955, 1983), 1970, sec="CJ-5", cats=["Jeep CJ-5"]),
        G("cj-7", (1976, 1986), 1986, sec="CJ-7", cats=["Jeep CJ-7"]),
    ], exclude=("mitsubishi", "military", "m38", "lifted", "mahindra", "hotchkiss")),
    F("Willys MB", "Willys", "off-roader", "a wartime American jeep", "Willys MB", [
        G("mb", (1941, 1945), 1943, "Willys MB", cats=["Willys MB / Ford GPW in museums", "Willys MB / Ford GPW"],
          ok="The Willys MB infobox gives no dates; its article dates production 1941–1945."),
    ], exclude=("ambulance", "rail", "sas", "hotchkiss", "mitsubishi", "replica", "during world war",
                "indonesian revolution")),
    F("Mercedes-Benz G-Class", "Mercedes-Benz", "off-roader", "a German four-wheel drive", "Mercedes-Benz G-Class", [
        G("w460", (1979, 1991), 1980, sec="W460", cats=["Mercedes-Benz W460"]),
        G("w463", (1991, 2018), 2000, sec="W463 (1990", cats=["Mercedes-Benz W463"]),
    ], exclude=("6x6", "4x4²", "4x4 squared", "military", "pickup", "brabus", "w461", "w462",
                "popemobile", "puch", "peugeot", "landaulet")),
    F("Land Rover Series", "Land Rover", "off-roader", "a British four-wheel drive", "Land Rover Series", [
        G("series1", (1948, 1958), 1950, sec="Series I", cats=["Land Rover Series I"]),
        G("series2", (1958, 1971), 1970, sec="Series IIA", cats=["Land Rover Series II/IIA"],
          ok="Series II (1958–1961) and IIA (1961–1971) share one Commons category and one look."),
        G("series3", (1971, 1985), 1980, sec="Series III", cats=["Land Rover Series III"]),
    ], exclude=("military", "forward control", "ambulance", "fire", "santana", "pink panther",
                "wolf", "lightweight")),
    F("Land Rover Defender", "Land Rover", "off-roader", "a British four-wheel drive", "Land Rover Defender", [
        G("classic", (1990, 2016), 2000, sec="Defender", cats=["Land Rover Defender (L316)", "Land Rover Defender (L315)"],
          ok="Infobox production is a list; the classic Defender name ran 1990–2016."),
        G("l663", (2020, NOW), 2020, "Land Rover Defender (L663)", cats=["Land Rover Defender (L663)"]),
    ], exclude=("military", "wolf", "ambulance", "fire", "police", "camel trophy", "6x6", "pickup")),
    # ---- compact cars ------------------------------------------------------------------
    F("Honda Civic", "Honda", "compact car", "a Japanese compact car", "Honda Civic", [
        G("gen1", (1973, 1979), 1975, "Honda Civic (first generation)", cats=["Honda Civic (1972)"]),
        G("gen3", (1984, 1987), 1985, "Honda Civic (third generation)", cats=["Honda Civic (1983)"]),
        G("gen4", (1988, 1991), 1990, "Honda Civic (fourth generation)", cats=["Honda Civic (1987)"]),
        G("gen5", (1992, 1995), 1995, "Honda Civic (fifth generation)", cats=["Honda Civic (1991)"]),
        G("gen7", (2001, 2005), 2003, "Honda Civic (seventh generation)", cats=["Honda Civic (2000)"]),
        G("gen8", (2006, 2011), 2008, "Honda Civic (eighth generation)", cats=["Honda Civic (2005)"],
          ok="Infobox production 2005–2012 spans markets; the US model years are 2006–2011."),
        G("gen9", (2012, 2015), 2015, "Honda Civic (ninth generation)", cats=["Honda Civic (2011)"],
          ok="Infobox production 2011–2017 spans markets; the US model years are 2012–2015."),
        G("gen10", (2016, 2021), 2017, "Honda Civic (tenth generation)", cats=["Honda Civic (2015)"]),
        G("gen11", (2022, NOW), 2023, "Honda Civic (eleventh generation)", cats=["Honda Civic (2021)"]),
    ], exclude=("type r", "tuning", "tuned", "shuttle", "wagon", "crx", "del sol", "hybrid", "gx",
                "mules", "btcc", "tcr", "wtcc")),
    F("Volkswagen Golf", "Volkswagen", "compact car", "a German compact car", "Volkswagen Golf", [
        G("mk1", (1974, 1983), 1976, "Volkswagen Golf Mk1", cats=["Volkswagen Golf I"]),
        G("mk2", (1983, 1992), 1985, "Volkswagen Golf Mk2", cats=["Volkswagen Golf II"]),
        G("mk3", (1991, 1998), 1996, "Volkswagen Golf Mk3", cats=["Volkswagen Golf III"]),
        G("mk4", (1997, 2006), 2000, "Volkswagen Golf Mk4", cats=["Volkswagen Golf IV"]),
        G("mk5", (2003, 2009), 2005, "Volkswagen Golf Mk5", cats=["Volkswagen Golf V"]),
        G("mk6", (2008, 2013), 2010, "Volkswagen Golf Mk6", cats=["Volkswagen Golf VI"]),
        G("mk7", (2012, 2020), 2016, "Volkswagen Golf Mk7", cats=["Volkswagen Golf VII"]),
        G("mk8", (2019, NOW), 2020, "Volkswagen Golf Mk8", cats=["Volkswagen Golf VIII"]),
    ], aliases=["Volkswagen Rabbit"],
      exclude=("variant", "golf plus", "sportsvan", "cabrio", "jetta", "caddy", "country",
               "citystromer", "e-golf", "tuning", "rallye", "estate", "wagon", "alltrack")),
    F("Toyota Corolla", "Toyota", "compact car", "a Japanese compact car", "Toyota Corolla", [
        G("e10", (1966, 1970), 1968, "Toyota Corolla (E10)", cats=["Toyota Corolla (E10)"]),
        G("e30", (1974, 1981), 1975, "Toyota Corolla (E30)", cats=["Toyota Corolla (E30)"]),
        G("e70", (1979, 1983), 1980, "Toyota Corolla (E70)", cats=["Toyota Corolla (E70)"]),
        G("e80", (1983, 1987), 1985, "Toyota Corolla (E80)", cats=["Toyota Corolla (E80)"]),
        G("e90", (1988, 1992), 1988, "Toyota Corolla (E90)", cats=["Toyota Corolla (E90)"]),
        G("e110", (1995, 2002), 1998, "Toyota Corolla (E110)", cats=["Toyota Corolla (E110)"]),
        G("e120", (2003, 2008), 2008, "Toyota Corolla (E120)", cats=["Toyota Corolla (E120)"]),
        G("e170", (2014, 2019), 2015, "Toyota Corolla (E170)", cats=["Toyota Corolla (E170)"]),
        G("e210", (2019, NOW), 2020, "Toyota Corolla (E210)", cats=["Toyota Corolla (E210)"]),
    ], exclude=("levin", "trueno", "ae86", "spacio", "verso", "sprinter", "corolla cross", "fielder", "axio", "rumion",
                "wagon", "van", "touring", "rally", "wrc", "taxi", "police")),
    F("Mini", "Mini", "compact car", "a British small car", "Mini", [
        G("classic", (1959, 2000), 1965, "Mini", cats=["Austin Mini", "Austin Mini Cooper"], maker=["Austin", "Morris", "Mini"],
          ok="The classic Mini's infobox gives production 1959–2000 in its Mark sections."),
        G("r50", (2001, 2006), 2003, "Mini Hatch", sec="First generation", cats=["Mini Hatch (first generation)"]),
        G("r56", (2006, 2013), 2008, "Mini Hatch", sec="Second generation", cats=["Mini Hatch (R56)"]),
        G("f56", (2014, 2024), 2023, "Mini Hatch", sec="Third generation", cats=["Mini Hatch (third generation)"]),
    ], exclude=("moke", "clubman", "countryman", "paceman", "traveller", "countryman", "van",
                "pickup", "pick-up", "roadster", "coupe", "convertible", "cabrio", "italian job",
                "union jack", "mr bean", "wildgoose")),
    F("Fiat 500", "Fiat", "compact car", "an Italian small car", "Fiat 500", [
        G("topolino", (1936, 1955), 1937, 'Fiat 500 "Topolino"', cats=['Fiat 500 "Topolino"']),
        G("nuova", (1957, 1975), 1960, "Fiat 500", cats=["Fiat 500 (1957-1975)"]),
        G("312", (2007, 2024), 2010, "Fiat 500 (2007)", cats=["Fiat 500 (2007–2015)", "North American Fiat 500 (2007)"]),
    ], exclude=("abarth", "giardiniera", "simca", "furgone", "500c", "500l", "500x", "steyr",
                "jolly", "art car", "tuning", "people with", "mille miglia", "crash")),
    F("Volkswagen Beetle", "Volkswagen", "compact car", "a German small car", "Volkswagen Beetle", [
        G("type1", (1938, 2003), 1965, "Volkswagen Beetle", cats=["Volkswagen Type 1"],
          ok="The original Beetle was built from 1938 until the last one left Puebla in 2003."),
        G("new", (1998, 2010), 2000, "Volkswagen New Beetle", cats=["Volkswagen New Beetle"]),
        G("a5", (2012, 2019), 2013, "Volkswagen Beetle (A5)", cats=["Volkswagen Beetle (A5)"]),
    ], aliases=["Volkswagen Type 1", "Volkswagen Käfer"],
      exclude=("cabrio", "convertible", "baja", "dune", "buggy", "hot rod", "rat", "herbie", "kubel",
               "kübel", "schwimm", "karmann", "thing", "type 181", "brazil", "art car")),
    F("Ford Fiesta", "Ford", "compact car", "a small car", "Ford Fiesta", [
        G("mk1", (1976, 1983), 1978, "Ford Fiesta (first generation)", cats=["Ford Fiesta MK1"]),
        G("mk4", (1995, 2002), 1998, "Ford Fiesta (fourth generation)", cats=["Ford Fiesta MK4"]),
        G("mk6", (2008, 2017), 2011, "Ford Fiesta (sixth generation)", cats=["Ford Fiesta MK6"],
          ok="Infobox production is a list by market; Wikipedia's Fiesta article dates this generation 2008–2019 worldwide, 2008–2017 in Europe."),
        G("mk7", (2017, 2023), 2018, "Ford Fiesta (seventh generation)", cats=["Ford Fiesta MK7"]),
    ], exclude=("van", "courier", "rally", "wrc", "st", "sedan", "brazil", "active", "damaged")),
    F("Chevrolet Nova", "Chevrolet", "compact car", "an American compact car", "Chevrolet Nova", [
        G("gen1", (1962, 1965), 1963, sec="First generation", cats=["Chevrolet Chevy II Nova", "Chevrolet Nova"], strict=True),
        G("gen3", (1968, 1974), 1970, sec="Third generation", cats=["Chevrolet Nova (X-body)", "Chevrolet Nova"], strict=True),
        G("gen4", (1975, 1979), 1976, sec="Fourth generation", cats=["Chevrolet Nova (X-body)", "Chevrolet Nova"], strict=True),
    ], aliases=["Chevrolet Chevy II", "Chevrolet Chevy II Nova"], exclude=("s-body", "drag", "pro street")),
    # ---- family sedans -----------------------------------------------------------------
    F("Toyota Camry", "Toyota", "family sedan", "a Japanese family sedan", "Toyota Camry", [
        G("v10", (1983, 1986), 1983, sec="V10", cats=["Toyota Camry (V10)"]),
        G("xv10", (1992, 1996), 1993, "Toyota Camry (XV10)", cats=["Toyota Camry (XV10)"]),
        G("xv20", (1997, 2001), 1999, "Toyota Camry (XV20)", cats=["Toyota Camry (XV20)"]),
        G("xv30", (2002, 2006), 2003, "Toyota Camry (XV30)", cats=["Toyota Camry (XV30)"]),
        G("xv40", (2007, 2011), 2009, "Toyota Camry (XV40)", cats=["Toyota Camry (XV40)"]),
        G("xv50", (2012, 2017), 2013, "Toyota Camry (XV50)", cats=["Toyota Camry (XV50)"]),
        G("xv70", (2018, 2024), 2020, "Toyota Camry (XV70)", cats=["Toyota Camry (XV70)"]),
        G("xv80", (2025, NOW), 2025, "Toyota Camry (XV80)", cats=["Toyota Camry (XV80)"]),
    ], exclude=("taxi", "police", "nascar", "solara", "wagon", "aurion", "vista", "daihatsu", "altise")),
    F("Honda Accord", "Honda", "family sedan", "a Japanese family sedan", "Honda Accord", [
        G("gen1", (1976, 1981), 1978, sec="First generation", cats=["Honda Accord (1976)"]),
        G("gen3", (1986, 1989), 1987, sec="Third generation", cats=["Honda Accord (1985)"]),
        G("gen4", (1990, 1993), 1991, sec="Fourth generation", cats=["Honda Accord (1989)"]),
        G("gen6", (1998, 2002), 1998, "Honda Accord (sixth generation)", cats=["Honda Accord (1997)"],
          ok="Infobox production September 1997 – 2002: the 1998–2002 model years."),
        G("gen7", (2003, 2007), 2005, "Honda Accord (North America seventh generation)", cats=["Honda Accord (2002)"]),
        G("gen8", (2008, 2012), 2010, "Honda Accord (North America eighth generation)", cats=["Honda Accord (2007)"]),
        G("gen10", (2018, 2022), 2018, sec="Tenth generation", cats=["Honda Accord (2017)"],
          ok="Infobox production September 2017 – December 2022 (North America): model years 2018–2022."),
        G("gen11", (2023, NOW), 2023, sec="Eleventh generation", cats=["Honda Accord (2022)"]),
    ], exclude=("wagon", "aerodeck", "euro", "type r", "btcc", "jtcc", "inspire", "vigor", "crosstour",
                "china", "tourer", "estate")),
    F("Chevrolet Malibu", "Chevrolet", "family sedan", "an American family sedan", "Chevrolet Malibu", [
        G("gen4", (1978, 1983), 1980, sec="Fourth generation", cats=["Chevrolet Malibu (A/G-body)"]),
        G("gen5", (1997, 2003), 2000, sec="Fifth generation", cats=["Chevrolet Malibu (N-body)"]),
        G("gen7", (2008, 2012), 2010, sec="Seventh generation", cats=["Chevrolet Malibu (2008-2011)"]),
        G("gen9", (2016, 2025), 2020, sec="Ninth generation", cats=["Chevrolet Malibu (E2XX)"]),
    ], exclude=("maxx", "wagon", "police", "nascar", "chevelle", "classic")),
    F("Ford Taurus", "Ford", "family sedan", "an American family sedan", "Ford Taurus", [
        G("gen1", (1986, 1991), 1986, "Ford Taurus (first generation)", cats=["Ford Taurus (first generation)"]),
        G("gen3", (1996, 1999), 1997, "Ford Taurus (third generation)", cats=["Ford Taurus (1995–1999)"]),
        G("gen4", (2000, 2007), 2003, "Ford Taurus (fourth generation)", cats=["Ford Taurus (1999–2007)"]),
        G("gen6", (2010, 2019), 2013, "Ford Taurus (sixth generation)", cats=["Ford Taurus (sixth generation)"]),
    ], exclude=("police", "interceptor", "wagon", "station wagon", "taurus x", "china", "nascar",
                "sheriff", "patrol", "mules")),
    F("BMW 3 Series", "BMW", "family sedan", "a German sports sedan", "BMW 3 Series", [
        G("e21", (1975, 1983), 1977, "BMW 3 Series (E21)", cats=["BMW E21"]),
        G("e30", (1982, 1994), 1987, "BMW 3 Series (E30)", cats=["BMW E30"]),
        G("e36", (1990, 2000), 1997, "BMW 3 Series (E36)", cats=["BMW E36"]),
        G("e46", (1998, 2006), 2002, "BMW 3 Series (E46)", cats=["BMW E46"]),
        G("e90", (2005, 2013), 2007, "BMW 3 Series (E90)", cats=["BMW E90"]),
        G("f30", (2012, 2018), 2017, "BMW 3 Series (F30)", cats=["BMW F30"]),
        G("g20", (2019, NOW), 2020, "BMW 3 Series (G20)", cats=["BMW G20"]),
    ], exclude=("touring", "compact", "alpina", "m3", "dtm", "btcc", "wtcc", "baur", "convertible",
                "cabrio", "e91", "e92", "e93", "f31", "f34", "g21", "tuning", "drift")),
    # ---- vans --------------------------------------------------------------------------
    F("Volkswagen Bus", "Volkswagen", "van", "a German van", "Volkswagen Type 2", [
        G("t1", (1950, 1967), 1960, "Volkswagen Type 2", sec="T1", cats=["Volkswagen T1"],
          ok="The T1 section's infobox lists production by country; the T1 was built in Germany 1950–1967."),
        G("t2", (1967, 1979), 1972, "Volkswagen Type 2", sec="T2", cats=["Volkswagen T2"],
          ok="German T2 production ran 1967–1979; Brazil kept building it until 2013."),
        G("t3", (1979, 1992), 1985, "Volkswagen Type 2 (T3)", cats=["Volkswagen T3"],
          ok="German T3 production ended in 1992; South Africa continued to 2002."),
    ], aliases=["Volkswagen Type 2", "Volkswagen Transporter", "Volkswagen Microbus"],
      exclude=("pickup", "pick-up", "doka", "pritsche", "food", "fire", "police", "ambulance",
               "custom", "hot rod", "rat", "lowrider", "plattenwagen", "kombi brazil", "brazil",
               "syncro 16")),
    F("Dodge Caravan", "Dodge", "van", "an American minivan", "Dodge Caravan", [
        G("gen1", (1984, 1990), 1985, "Chrysler minivans (S)", sec="First generation", cats=["Dodge Caravan (S)"]),
        G("gen2", (1991, 1995), 1993, sec="Second generation", cats=["Dodge Caravan (AS)"]),
        G("gen3", (1996, 2000), 1997, "Chrysler minivans (NS)", cats=["Dodge Caravan (NS)"]),
        G("gen5", (2008, 2020), 2010, "Chrysler minivans (RT)", cats=["Dodge Grand Caravan (RT)"]),
    ], aliases=["Dodge Grand Caravan"], exclude=("plymouth", "chrysler", "voyager", "town & country",
                                                 "town and country", "taxi", "routan", "c/v", "mini ram")),
    F("Ford Econoline", "Ford", "van", "an American van", "Ford E-Series", [
        G("gen1", (1961, 1967), 1963, sec="First generation", cats=["Ford Econoline (1961)"]),
        G("gen2", (1968, 1974), 1970, sec="Second generation", cats=["Ford Econoline (1968)"]),
        G("gen3", (1975, 1991), 1985, sec="Third generation", cats=["Ford Econoline (1975)"]),
        G("gen4", (1992, 2014), 2005, sec="Fourth generation", cats=["Ford Econoline (1992)", "Ford E-Series (2008-2015)"],
          ok="Passenger and cargo vans 1992–2014; the cutaway chassis is still built."),
    ], aliases=["Ford E-Series"], exclude=("bus", "ambulance", "camper", "camping", "cutaway", "rv",
                                            "motorhome", "pickup", "shuttle", "box truck", "u-haul")),
    F("Toyota Sienna", "Toyota", "van", "a Japanese minivan", "Toyota Sienna", [
        G("xl10", (1998, 2003), 1998, sec="First generation", cats=["Toyota Sienna (XL10)"]),
        G("xl30", (2011, 2020), 2015, sec="Third generation", cats=["Toyota Sienna (XL30)"]),
        G("xl40", (2021, NOW), 2021, sec="Fourth generation", cats=["Toyota Sienna (XL40)"]),
    ], exclude=("taxi", "police", "mobility")),
    # ---- vintage -----------------------------------------------------------------------
    F("Ford Model T", "Ford", "vintage car", "an early American car", "Ford Model T", [
        G("t", (1908, 1927), 1915, "Ford Model T", cats=["Ford Model T (1913–1914)", "Ford Model T (1915–1916)",
                                                          "Ford Model T (1917–1922)", "Ford Model T"]),
    ], exclude=("replica", "monument", "models", "golden", "speedster", "hot rod", "truck", "tt",
                "fire", "snowmobile", "depot hack")),
    F("Ford Model A", "Ford", "vintage car", "an early American car", "Ford Model A (1927–1931)", [
        G("a", (1928, 1932), 1930, "Ford Model A (1927–1931)", cats=["Ford Model A (1928–1931)"],
          ok="Model years 1928–1931 in the US; Ford kept building it until March 1932."),
    ], exclude=("hot rod", "rat", "replica", "pickup", "delivery", "1903", "ac", "gaz", "modified",
                "ramblin")),
    F("Cord 810", "Cord", "vintage car", "an American classic car", "Cord 810/812", [
        G("810", (1936, 1937), 1937, "Cord 810/812", cats=["Cord 812", "Cord 810"]),
    ], aliases=["Cord 812"], exclude=("replica", "8/10", "sportsman")),
]

# MARK: - Filters

# Looked at on a contact sheet and turned down: bonnet up, a crowd, a camper, a show truck,
# a rusted shell, a dark crop. SigLIP passes these; a person would not.
SKIP_FILES = {
    "Chevrolet Corvette Sting Ray Coupé (C2, 1963) (53769227255).jpg",
    "2017 Bois d'Arc Spring Car Show 29 (2011 Chevrolet Corvette).jpg",
    "Dodge Viper 1999 RT10 DownLNose LakeMirrorClassic 17Oct09 (14413962179).jpg",
    "Mercedes-Benz Pagonda (14293012840).jpg",
    "Mercedes - Flickr - dave 7.jpg",
    "Mercedes-Benz E 300 e (W214, 2024) (54854514180).jpg",
    "1962 Chevrolet Bel Air (28593926046).jpg",
    "1963 Plymouth Fury (8067501605).jpg",
    "1966 Plymouth Sport Fury (6901562286).jpg",
    "1970 Plymouth Sport Fury - Flickr - denizen24.jpg",
    "1995 Ford Crown Victoria (EN53).jpg",
    "1955 Ford F100 Pickup (3804238574).jpg",
    "1977 Ford Truck (4283696902).jpg",
    "1966 Chevrolet C10 - 03.jpg",
    "Toyota Tacoma 1999 on Chumstick Mountain Chelan County Washington in 2011.jpg",
    "Toyota Tacoma Back to the Future Show Truck NAIAS 2016.jpg",
    "2005 & 2008 Toyota Land Cruiser 100 & 200 (51146036495).jpg",
    "Toyota Land Cruiser 300 4x4 VXR 2021 (6).jpg",
    "Ford Bronco (3336097414).jpg",
    "2022 Jeep Grand Cherokee L.jpg",
    "Honda Civic TI (2011) (32431941232).jpg",
    "1970 Toyota Corolla 1200cc.jpg",
    "2003-2007 Toyota Corolla Spacio 1.png",
    "1937 Fiat Topolino (32460081631).jpg",
    "2018 Honda Accord Touring 2.0t.jpg",
    "1953 Volkswagen Type 2 T1 Van (8371456274).jpg",
    "Ford E-Super Duty V10 1997 (44592155835).jpg",
    "Cord 812 1937 Beverly HeadOn Lake Mirror Cassic 16Oct2010 (14690587970).jpg",
    "1963 Plymouth Sport Fury, rear left side, DQ Littleton Car Show 2026-08-02.jpg",
    "1966 Plymouth Fury III sedan at 2015 MD-MVA show 3of4.jpg",
    "View of a 1955 Ford F100 pick-up in the Hedingham Castle Classic and Vintage Car Show - geograph.org.uk - 6242478.jpg",
    "1979 Ford truck (6030507845).jpg",
    "1963 Plymouth Sport Fury, front right side, DQ Littleton Car Show 2026-08-02.jpg",
    "1954 Ford Pickup (4768664725).jpg",
}

BAD_TITLE = ("interior", "engine", "dashboard", "badge", "emblem", "logo", "wheel", "toy",
             "model kit", "diecast", "die-cast", "scale model", "lego", "concept", "prototype",
             "race", "racing", "rally", "crash", "wreck", "rust", "junkyard", "police", "taxi",
             "limousine conversion", "drawing", "advert", "brochure", "museum display sign",
             "nascar", "drag", "dragster", "advertisement", "wrecked", "crashed", "rusty",
             "rusted", "junk", "scrapyard", "salvage", "rear", "heck", "rearview")
# Words in a subcategory's name that mean the files in it are not a clean road car.
BAD_SUBCAT = ("interior", "engine", "detail", "logo", "badge", "emblem", "wheel", "model car",
              "models", "toy", "diecast", "lego", "competition", "racing", "race", "rally",
              "motorsport", "police", "taxi", "ambulance", "hearse", "fire", "limousine", "stretch",
              "concept", "prototype", "modified", "custom", "tuning", "hot rod", "replica",
              "art car", "crash", "wreck", "accident", "damaged", "abandoned", "rust", "junk",
              "drawing", "advert", "brochure", "assembly", "production line", "factory",
              "body shell", "chassis", "people with", "by country", "military", "army",
              "development mule", "camping", "camper", "bus", "tow truck", "road-rail",
              "food truck", "drift", "lowrider", "monster", "kit car", "clones", "dashboard",
              "steering", "seat", "trunk", "boot", "headlight", "tail light", "taillight", "grille",
              "hubcap", "rims", "patent", "manual", "poster", "stamp", "film", "movie", "museum sign")
GOOD = ["a photograph of a whole car parked outdoors", "a photograph of a car"]
BAD = ["a photograph of a car interior or dashboard", "a close-up of a car engine",
       "a close-up of a car badge or wheel", "a toy car or a scale model",
       "a racing car on a track", "a drawing, an advertisement or a page of text",
       "a crowded car show with many cars"]
RANK = ["a clean photograph of one whole car seen from the front three-quarter view, parked "
        "outdoors on a sunny day"]
BITMAP = (".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff")
YEAR = re.compile(r"(?<!\d)(19[0-9]{2}|20[0-2][0-9])(?!\d)")



# What the question calls a line — the name people say, not Wikipedia's. "Chevrolet C/K"
# is an article title; anybody who owned one called it a C10. Ids keep the original name
# so a rename never orphans anything.
SPOKEN = {
    "Chevrolet C/K": "Chevrolet C10",
    "Nissan Z-car": "Nissan Z (Datsun Z)",
    "Mazda MX-5 Miata": "Mazda Miata",
    "Mini": "Mini Cooper",
    "MG MGB": "MGB",
    "Land Rover Series": "classic Land Rover",
    "Willys MB": "Willys Jeep",
    "Ford Econoline": "Ford Econoline van",
    "Volkswagen Golf": "Volkswagen Golf (Rabbit)",
    "Mercedes-Benz E-Class": "Mercedes E-Class",
    "Mercedes-Benz G-Class": "Mercedes G-Class",
    "Mercedes-Benz S-Class": "Mercedes S-Class",
    "Mercedes-Benz SL": "Mercedes SL",
    "Ford Galaxie": "Ford Galaxie 500"
}


def spoken(title):
    return SPOKEN.get(title, title)

def words(text):
    return " " + re.sub(r"[^a-z0-9äöüé&²/+.\-]+", " ", text.lower()) + " "


def norm(text):
    return " ".join(re.sub(r"[^0-9a-zäöüéèß²]+", " ", text.lower()).split())


def has_word(text, word):
    """A whole word or phrase, plurals allowed: "race" matches "races" but not "terrace", and
    "toy" does not match "Toyota". Punctuation is ignored on both sides, so "mach-e" matches
    "Mach E" and "F-350" matches "f 350"."""
    pattern = r"(?<![0-9a-z])" + re.escape(norm(word)) + r"(?:s|es)?(?![0-9a-z])"
    return re.search(pattern, norm(text)) is not None


def title_problem(name, fam, gen):
    lower = name.lower()
    stem = lower.rsplit(".", 1)[0]
    for word in BAD_TITLE:
        if has_word(stem, word):
            return "title"
    for word in fam.exclude + gen.exclude:
        if has_word(stem, word):
            return "excluded"
    must = gen.must or fam.must
    if must and must not in stem:
        return "excluded"
    return None


def years_in(text):
    return [int(y) for y in YEAR.findall(text)]


# MARK: - Caches

def cache_path(name):
    return os.path.join(CACHE, f"cars-{name}.json")


def load_cache(name):
    try:
        return json.load(open(cache_path(name)))
    except Exception:
        return {}


def save_cache(name, data):
    os.makedirs(CACHE, exist_ok=True)
    tmp = cache_path(name) + ".tmp"
    with open(tmp, "w") as handle:
        json.dump(data, handle, ensure_ascii=False)
    os.replace(tmp, cache_path(name))


# MARK: - Wikipedia: infoboxes and intros

def wikitexts(titles, cache):
    want = [t for t in dict.fromkeys(titles) if t not in cache]
    for start in range(0, len(want), 20):
        batch = want[start:start + 20]
        data = q.fetch_json("https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode({
            "action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main",
            "titles": "|".join(batch), "redirects": 1, "format": "json", "formatversion": 2}))
        time.sleep(0.5)
        if not data:
            continue
        norm = {r["from"]: r["to"] for r in data["query"].get("normalized", [])}
        red = {r["from"]: r["to"] for r in data["query"].get("redirects", [])}
        pages = {p["title"]: p for p in data["query"]["pages"]}
        for title in batch:
            resolved = red.get(norm.get(title, title), norm.get(title, title))
            page = pages.get(resolved)
            if page and "revisions" in page:
                cache[title] = {"resolved": resolved,
                                "text": page["revisions"][0]["slots"]["main"]["content"]}
    return cache


def matching_close(text, start):
    depth, i = 0, start
    while i < len(text):
        if text.startswith("{{", i):
            depth += 1
            i += 2
        elif text.startswith("}}", i):
            depth -= 1
            i += 2
            if depth == 0:
                return i
        else:
            i += 1
    return len(text)


def params(box):
    """Top-level |name=value pairs of a template, braces and links respected."""
    out, depth, square, current = {}, 0, 0, []
    body = box[2:-2]
    parts = []
    i = 0
    while i < len(body):
        two = body[i:i + 2]
        if two == "{{":
            depth += 1; current.append(two); i += 2; continue
        if two == "}}":
            depth -= 1; current.append(two); i += 2; continue
        if two == "[[":
            square += 1; current.append(two); i += 2; continue
        if two == "]]":
            square -= 1; current.append(two); i += 2; continue
        if body[i] == "|" and depth == 0 and square == 0:
            parts.append("".join(current)); current = []; i += 1; continue
        current.append(body[i]); i += 1
    parts.append("".join(current))
    for part in parts[1:]:
        if "=" in part:
            key, value = part.split("=", 1)
            out[key.strip().lower()] = value
    return out


def infoboxes(text):
    heads = [(m.start(), m.group(1).strip()) for m in re.finditer(r"\n=+\s*(.*?)\s*=+\s*\n", text)]
    boxes = []
    for m in re.finditer(r"\{\{\s*Infobox automobile", text, re.I):
        end = matching_close(text, m.start())
        p = params(text[m.start():end])
        section = [h for pos, h in heads if pos < m.start()]
        boxes.append({"section": section[-1] if section else "",
                      "name": p.get("name", ""),
                      "model_years": p.get("model_years", ""),
                      "production": p.get("production", "")})
    return boxes


def clean(value):
    value = re.sub(r"<ref[^>]*/>", "", value)
    value = re.sub(r"<ref.*?</ref>", "", value, flags=re.S)
    value = re.sub(r"<!--.*?-->", "", value, flags=re.S)
    value = re.sub(r"\{\{(?:sfn|cn|citation needed|efn)[^}]*\}\}", "", value, flags=re.I)
    return value


def ranges(value):
    """(starts, ends) of every year range in an infobox field."""
    text = clean(value).replace("&ndash;", "–").replace("&mdash;", "–")
    text = re.sub(r"\s*(?:–|—|−|-|‒|to)\s*", "–", text)
    starts, ends = set(), set()
    for m in re.finditer(r"(?<!\d)(\d{4})(?:–(?:[A-Za-z]+\s+)?(?:\d{1,2}\s*,?\s*)?(\d{4}|present))?",
                         text, re.I):
        a = int(m.group(1))
        if not 1880 <= a <= NOW:
            continue
        b = m.group(2)
        b = NOW if b and b.lower() == "present" else int(b) if b else a
        starts.add(a)
        ends.add(b)
    return starts, ends


def check_years(gen, fam, texts):
    """Whether Wikipedia's infobox agrees with gen.years, and the evidence."""
    boxes = []
    if gen.art and gen.art in texts:
        art_boxes = infoboxes(texts[gen.art]["text"])
        if gen.sec:
            art_boxes = [b for b in art_boxes
                         if gen.sec.lower() in (b["section"] + " " + b["name"]).lower()] or (
                art_boxes[:1] if gen.art != fam.line else [])
        else:
            art_boxes = art_boxes[:1]
        boxes += art_boxes
    if gen.sec and fam.line in texts and fam.line != gen.art:
        boxes += [b for b in infoboxes(texts[fam.line]["text"])
                  if gen.sec.lower() in (b["section"] + " " + b["name"]).lower()]
    if not gen.art and not gen.sec and fam.line in texts:
        boxes += infoboxes(texts[fam.line]["text"])[:1]
    y0, y1 = gen.years
    evidence = []
    for box in boxes:
        for field in ("model_years", "production"):
            starts, ends = ranges(box[field])
            if not starts:
                continue
            evidence.append(f"{field}: {sorted(starts)}–{sorted(ends)}")
            end_ok = any(abs(e - y1) <= 1 for e in ends) or (y1 >= NOW - 1 and NOW in ends)
            if any(abs(s - y0) <= 1 for s in starts) and end_ok:
                return True, "; ".join(evidence[-1:])
    return False, "; ".join(evidence) or "no infobox years found"


# MARK: - Wikidata

def wikidata_for_titles(titles):
    """{enwiki title: {"id", "sitelinks", "P373", "start", "end"}}."""
    out = {}
    titles = list(dict.fromkeys(titles))
    for start in range(0, len(titles), 50):
        batch = titles[start:start + 50]
        data = q.fetch_json("https://www.wikidata.org/w/api.php?" + urllib.parse.urlencode({
            "action": "wbgetentities", "sites": "enwiki", "titles": "|".join(batch),
            "props": "sitelinks|claims", "format": "json"}))
        time.sleep(0.5)
        if not data:
            continue
        for qid, entity in (data.get("entities") or {}).items():
            if not qid.startswith("Q"):
                continue
            title = ((entity.get("sitelinks") or {}).get("enwiki") or {}).get("title")
            cats = q.claim_values(entity, "P373")
            out[title] = {"id": qid, "sitelinks": q.sitelink_count(entity),
                          "P373": cats[0] if cats else None,
                          "start": q.claim_year(entity, "P2031") or q.claim_year(entity, "P571"),
                          "end": q.claim_year(entity, "P2032") or q.claim_year(entity, "P730")}
    return out


def wikidata_for_commons_cats(cats):
    """{commons category: qid} for items whose Commons category is exactly that."""
    out = {}
    cats = [c for c in dict.fromkeys(cats) if c]
    for start in range(0, len(cats), 60):
        batch = cats[start:start + 60]
        values = " ".join(json.dumps(c) for c in batch)
        rows = q.sparql(f"SELECT ?item ?cc WHERE {{ VALUES ?cc {{ {values} }} ?item wdt:P373 ?cc }}")
        time.sleep(1.0)
        for row in rows or []:
            out.setdefault(row["cc"], q.qid(row["item"]))
    return out


# MARK: - Commons

def api(params_):
    data = q.fetch_json("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(
        {**params_, "format": "json", "formatversion": 2}))
    time.sleep(0.6)
    return data


def category_redirect(cat):
    data = api({"action": "query", "titles": "Category:" + cat, "prop": "revisions",
                "rvprop": "content", "rvslots": "main"})
    try:
        text = data["query"]["pages"][0]["revisions"][0]["slots"]["main"]["content"]
    except Exception:
        return None
    m = re.search(r"\{\{\s*(?:Category redirect|Cat redirect|Seecat|Category move)\s*\|\s*"
                  r"(?:Category:)?([^}|]+)", text, re.I)
    return m.group(1).strip() if m else None


def members(cat, mcache):
    """(files, subcats) directly in a category, following soft redirects. Cached."""
    if cat in mcache:
        return mcache[cat]
    files, subcats, cont = [], [], {}
    for _ in range(3):
        data = api({"action": "query", "list": "categorymembers", "cmtitle": "Category:" + cat,
                    "cmtype": "file|subcat", "cmlimit": 500, **cont})
        if data is None:
            return None          # refused: do not cache, a rerun will ask again
        for m in data.get("query", {}).get("categorymembers", []):
            if m["ns"] == 14:
                subcats.append(m["title"].removeprefix("Category:"))
            elif m["ns"] == 6:
                files.append(m["title"].removeprefix("File:"))
        if "continue" in data and len(files) < 600:
            cont = data["continue"]
        else:
            break
    if not files and not subcats:
        target = category_redirect(cat)
        if target and target != cat:
            result = members(target, mcache)
            mcache[cat] = result
            return result
    mcache[cat] = [files, subcats]
    return mcache[cat]


def existing_categories(names, ecache):
    want = [n for n in dict.fromkeys(names) if n not in ecache]
    for start in range(0, len(want), 50):
        batch = want[start:start + 50]
        data = api({"action": "query", "titles": "|".join("Category:" + n for n in batch),
                    "prop": "categoryinfo"})
        if not data:
            continue
        norm = {r["from"]: r["to"] for r in data["query"].get("normalized", [])}
        pages = {p["title"]: p for p in data["query"]["pages"]}
        for name in batch:
            t = "Category:" + name
            page = pages.get(norm.get(t, t), {})
            info = page.get("categoryinfo") or {}
            ecache[name] = bool(info.get("files") or info.get("subcats")) and not page.get("missing")
    return [n for n in names if ecache.get(n)]


def subcat_ok(name, gen, fam):
    lower = name.lower()
    for word in BAD_SUBCAT:
        if has_word(lower, word):
            return False
    for word in fam.exclude + gen.exclude:
        if has_word(lower, word):
            return False
    ys = [y for y in years_in(name) if 1900 <= y <= NOW]
    if ys and not any(gen.years[0] - 1 <= y <= gen.years[1] + 1 for y in ys):
        return False       # a category for another generation's years
    return True


def year_cat_names(fam, gen):
    names = [fam.title] + fam.aliases
    out = []
    for y in range(gen.years[0], min(gen.years[1], NOW) + 1):
        for n in names:
            out.append(f"{y} {n}")
    return out


def candidates_for(fam, gen, mcache, ecache, extra_cats):
    """Ordered candidate file names, each with the tier it came from (0 = askYear category,
    1 = another year category in range, 2 = the generation's categories)."""
    y0, y1 = gen.years
    tiers = {}
    year_cats = existing_categories(year_cat_names(fam, gen), ecache)
    year_cats.sort(key=lambda c: (abs(years_in(c)[0] - gen.ask), c))
    budget = 18
    for cat in year_cats[:5]:
        result = members(cat, mcache)
        budget -= 1
        if not result:
            continue
        tier = 0 if years_in(cat)[0] == gen.ask else 1
        for f in result[0]:
            tiers.setdefault(f, (tier, cat))
        for sub in result[1][:4]:
            if subcat_ok(sub, gen, fam) and budget > 0:
                r2 = members(sub, mcache)
                budget -= 1
                for f in (r2 or [[]])[0]:
                    tiers.setdefault(f, (tier, sub))
    queue = [(c, 0) for c in (gen.cats or extra_cats)]
    seen = set(year_cats)
    while queue and budget > 0 and len(tiers) < 160:
        cat, depth = queue.pop(0)
        if cat in seen:
            continue
        seen.add(cat)
        result = members(cat, mcache)
        budget -= 1
        if not result:
            continue
        files, subcats = result
        ys = years_in(cat)
        cat_in_range = any(y0 - 1 <= y <= y1 + 1 for y in ys)
        for f in files:
            tiers.setdefault(f, (2 if not (gen.strict and cat_in_range) else 1, cat))
        if depth < 2:
            for sub in subcats:
                if subcat_ok(sub, gen, fam):
                    queue.append((sub, depth + 1))
    return tiers


def stable_order(name, salt):
    return hashlib.sha1((salt + name).encode()).hexdigest()


# MARK: - Build

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--per-gen", type=int, default=12, help="candidates scored per generation")
    parser.add_argument("--only", help="family title to (re)build alone, for debugging")
    parser.add_argument("--years-only", action="store_true", help="check years against Wikipedia and stop")
    args = parser.parse_args()

    families = [f for f in FAMILIES if not args.only or f.title == args.only]
    gens = [(fam, gen) for fam in families for gen in fam.gens]
    print(f"{len(families)} model lines, {len(gens)} generations")
    rejects = Counter()
    notes = []

    # --- Wikipedia text, years -------------------------------------------------------
    texts = load_cache("wikitext")
    titles = [f.line for f in families] + [g.art for _, g in gens if g.art]
    wikitexts(titles, texts)
    save_cache("wikitext", texts)
    years_ok = {}
    for fam, gen in gens:
        good, evidence = check_years(gen, fam, texts)
        if not good and gen.ok:
            notes.append(f"years {fam.title} {gen.slug} {gen.years}: accepted by note — {gen.ok} "
                         f"[infobox: {evidence}]")
            good = True
        elif not good:
            notes.append(f"years {fam.title} {gen.slug} {gen.years}: NOT CONFIRMED [{evidence}]")
        years_ok[(fam.title, gen.slug)] = good
        if not (gen.years[0] <= gen.ask <= gen.years[1] and gen.ask <= 2025):
            years_ok[(fam.title, gen.slug)] = False
            notes.append(f"askYear {fam.title} {gen.slug}: {gen.ask} outside {gen.years}")

    if args.years_only:
        for n in notes:
            print("   " + n)
        print(f"{sum(years_ok.values())} of {len(years_ok)} generations confirmed")
        return

    # --- Wikidata ----------------------------------------------------------------------
    wd = load_cache("wikidata")
    want = [t for t in titles if t in texts and texts[t]["resolved"] not in wd]
    if want:
        found = wikidata_for_titles([texts[t]["resolved"] for t in want])
        wd.update(found)
        save_cache("wikidata", wd)
    def item(title):
        return wd.get(texts.get(title, {}).get("resolved", title)) if title else None
    catmap = load_cache("catqid")
    allcats = [c for _, g in gens for c in g.cats]
    missing = [c for c in allcats if c not in catmap]
    if missing:
        found = wikidata_for_commons_cats(missing)
        for c in missing:
            catmap[c] = found.get(c)
        save_cache("catqid", catmap)

    # --- Facts -------------------------------------------------------------------------
    facts = load_cache("facts")
    fact_titles = sorted({texts[t]["resolved"] for t in titles if t in texts} - set(facts))
    if fact_titles:
        import add_descriptions as ad
        got = ad.intros(fact_titles)
        for t in fact_titles:
            facts[t] = got.get(t)
        save_cache("facts", facts)

    # --- Commons candidates --------------------------------------------------------------
    mcache = load_cache("members")
    ecache = load_cache("catexists")
    crawl = load_cache("crawl")
    for n, (fam, gen) in enumerate(gens):
        key = f"{fam.title}|{gen.slug}"
        if key in crawl:
            continue
        extra = []
        if not gen.cats:
            it = item(gen.art) if gen.art and gen.art != fam.line else None
            if it and it.get("P373"):
                extra = [it["P373"]]
        tiers = candidates_for(fam, gen, mcache, ecache, extra)
        crawl[key] = {f: list(t) for f, t in tiers.items()}
        print(f"[{n + 1}/{len(gens)}] {fam.title} {gen.slug}: {len(tiers)} files", flush=True)
        if n % 5 == 0:
            save_cache("members", mcache); save_cache("catexists", ecache); save_cache("crawl", crawl)
    save_cache("members", mcache); save_cache("catexists", ecache); save_cache("crawl", crawl)

    # --- Pre-filter by title, then fetch file info -----------------------------------------
    shortlist = {}
    for fam, gen in gens:
        key = f"{fam.title}|{gen.slug}"
        tiers = crawl.get(key, {})
        keep = []
        for name, (tier, cat) in tiers.items():
            if not name.lower().endswith(BITMAP):
                continue
            problem = title_problem(name, fam, gen)
            if problem:
                rejects[f"2. file title ({problem})"] += 1
                continue
            ys = [y for y in years_in(name.rsplit(".", 1)[0]) if 1900 <= y <= NOW]
            in_range = any(gen.years[0] - 1 <= y <= gen.years[1] + 1 for y in ys)
            if gen.strict and tier == 2 and not in_range:
                rejects["2. strict: no year inside the generation"] += 1
                continue
            # A title that names only model years before this generation began is another car.
            if ys and not in_range and max(ys) < gen.years[0] - 1:
                rejects["2. title names another generation's year"] += 1
                continue
            bonus = 0 if in_range else 1
            keep.append(((tier, bonus, stable_order(name, key)), name))
        keep.sort()
        shortlist[key] = [name for _, name in keep[:45]]

    info = load_cache("info")
    want = sorted({n for names in shortlist.values() for n in names if n not in info})
    print(f"file info for {len(want)} files", flush=True)
    for start in range(0, len(want), 200):
        batch = want[start:start + 200]
        got = q.commons_files(batch, width=1280)
        for n in batch:
            if n in got:
                info[n] = got[n]
        save_cache("info", info)

    # --- Download and embed ----------------------------------------------------------------
    import numpy as np
    vec_path = os.path.join(CACHE, "cars-vectors.npz")
    vectors = {}
    if os.path.exists(vec_path):
        loaded = np.load(vec_path)
        vectors = {k: loaded[k] for k in loaded.files}
    siglip = q.Siglip()
    good_text, bad_text, rank_text = siglip.text(GOOD), siglip.text(BAD), siglip.text(RANK)

    def thumb(url):
        return re.sub(r"/\d+px-", "/500px-", url) if "/thumb/" in url else url

    def vkey(name):
        return hashlib.sha1(name.encode()).hexdigest()

    pool = {}
    for n, (fam, gen) in enumerate(gens):
        key = f"{fam.title}|{gen.slug}"
        usable = []
        for name in shortlist[key]:
            meta = info.get(name)
            if not meta:
                continue
            if not q.usable_photo(meta):
                rejects["1. licence / size / format"] += 1
                continue
            usable.append(name)
            if len(usable) >= args.per_gen:
                break
        new = [nm for nm in usable if vkey(nm) not in vectors]
        for name in new:
            path = q.download(thumb(info[name]["url"]))
            if not path:
                rejects["1. not downloadable"] += 1
                continue
            got = siglip.images([path])
            if path in got:
                vectors[vkey(name)] = got[path]
        scored = []
        for name in usable:
            if name in SKIP_FILES:
                rejects["7. turned down by eye"] += 1
                continue
            v = vectors.get(vkey(name))
            if v is None:
                continue
            g, b, r = float((good_text @ v).max()), float((bad_text @ v).max()), float((rank_text @ v).max())
            if g <= b:
                rejects["3. SigLIP prefers a bad description"] += 1
                continue
            tier = crawl[key][name][0]
            scored.append((round(r + 0.5 * (g - b) + (0.004 if tier == 0 else 0), 5), name))
        scored.sort(reverse=True)
        pool[key] = [name for _, name in scored]
        if new:
            print(f"[{n + 1}/{len(gens)}] {fam.title} {gen.slug}: {len(usable)} usable, "
                  f"{len(scored)} pass SigLIP", flush=True)
            np.savez(vec_path, **vectors)
    np.savez(vec_path, **vectors)

    # --- Choose, de-duplicate ----------------------------------------------------------------
    choice, used = {}, set()
    for fam, gen in gens:
        key = f"{fam.title}|{gen.slug}"
        for name in pool.get(key, []):
            if name not in used:
                choice[key] = name
                used.add(name)
                break
    for _ in range(4):
        chosen = {k: vectors[vkey(v)] for k, v in choice.items()}
        drop = q.near_duplicates(chosen, threshold=0.94)
        if not drop:
            break
        for key in drop:
            rejects["4. near-duplicate of another item"] += 1
            used.discard(choice[key])
            nxt = [n for n in pool[key] if n not in used and n != choice[key]]
            bad = choice.pop(key)
            pool[key] = [n for n in pool[key] if n != bad]
            if nxt:
                choice[key] = nxt[0]
                used.add(nxt[0])

    # --- Items ------------------------------------------------------------------------------
    items, dropped = [], []
    qid_use = Counter()
    for fam, gen in gens:
        if gen.art and gen.art != fam.line and item(gen.art):
            qid_use[item(gen.art)["id"]] += 1
    for fam, gen in gens:
        key = f"{fam.title}|{gen.slug}"
        if key not in choice:
            dropped.append(f"{fam.title} {gen.slug}: no photograph passed")
            continue
        if not years_ok[(fam.title, gen.slug)]:
            rejects["6. years not confirmed"] += 1
            dropped.append(f"{fam.title} {gen.slug}: years not confirmed")
            continue
        fact_title = None
        for t in (gen.art, fam.line):
            if t and t in texts and facts.get(texts[t]["resolved"]):
                fact_title = texts[t]["resolved"]
                break
        if not fact_title:
            rejects["5. no fact"] += 1
            dropped.append(f"{fam.title} {gen.slug}: no fact")
            continue
        # subjectID: the generation's own item when it has one to itself.
        subject = None
        own = item(gen.art) if gen.art and gen.art != fam.line else None
        if own and qid_use[own["id"]] == 1:
            subject = own["id"]
        if not subject:
            for c in gen.cats:
                if catmap.get(c):
                    subject = catmap[c]
                    break
        fam_slug = re.sub(r"[^a-z0-9]+", "-", fam.title.lower()).strip("-")
        if not subject or subject in {i["subjectID"] for i in items}:
            subject = f"{fam_slug}-{gen.slug}"
        line_item = item(fam.line) or {}
        meta = info[choice[key]]
        items.append({
            "id": f"cars-{fam_slug}-{gen.slug}",
            "subjectID": subject,
            "title": spoken(fam.title),
            "objectTags": [],
            "remoteURL": meta["url"],
            "year": gen.ask,
            "month": 6,
            "credit": meta["credit"] or "Wikimedia Commons contributor",
            "source": "Wikimedia Commons",
            "sourceURL": meta["sourceURL"],
            "license": meta["license"],
            "licenseURL": meta["licenseURL"],
            "isResizedCopy": True,
            "knownBy": line_item.get("sitelinks", 0),
            "creator": None,
            "creatorDied": None,
            "group": fam.group,
            "latitude": None,
            "longitude": None,
            "fact": facts[fact_title],
            "factSource": "https://en.wikipedia.org/wiki/" + urllib.parse.quote(fact_title.replace(" ", "_")),
            "facts": {"maker": gen.maker or [fam.maker]},
            "cluster": gen.cluster or fam.cluster,
            "family": spoken(fam.title),
            "years": [gen.years[0], min(gen.years[1], NOW)],
            "askYear": gen.ask,
        })

    report(items, rejects, notes, dropped, choice)
    if args.dry_run or args.only:
        print("\n(dry run — nothing written)")
        return
    q.write_pack(PACK, META, items, force=args.force)


def generation_support(gens):
    """Largest set of a family's items whose askYears are pairwise ≥20 apart and whose year
    ranges do not overlap."""
    gens = sorted(gens, key=lambda i: i["askYear"])
    best = []

    def fits(chosen, cand):
        return all(abs(cand["askYear"] - c["askYear"]) >= 20 and
                   (cand["years"][0] > c["years"][1] or cand["years"][1] < c["years"][0])
                   for c in chosen)

    def search(start, chosen):
        nonlocal best
        if len(chosen) > len(best):
            best = list(chosen)
        for i in range(start, len(gens)):
            if fits(chosen, gens[i]):
                search(i + 1, chosen + [gens[i]])
    search(0, [])
    return best


def report(items, rejects, notes, dropped, choice):
    print(f"\n=== {len(items)} items, {len({i['family'] for i in items})} model lines ===")
    by_family = defaultdict(list)
    for i in items:
        by_family[i["family"]].append(i)
    support = {f: generation_support(v) for f, v in by_family.items()}
    four = sorted(f for f, s in support.items() if len(s) >= 4)
    three = sorted(f for f, s in support.items() if len(s) == 3)
    print(f"generation rounds: {len(four)} lines support 4 — " +
          ", ".join(f"{f} {[i['askYear'] for i in support[f]]}" for f in four))
    print(f"                   {len(three)} lines support only 3 — " + ", ".join(three))
    clusters = defaultdict(set)
    sizes = Counter()
    for i in items:
        clusters[i["cluster"]].add(i["family"])
        sizes[i["cluster"]] += 1
    print("clusters (items / lines):")
    for c in sorted(clusters, key=lambda c: -sizes[c]):
        print(f"   {c:22} {sizes[c]:4} / {len(clusters[c])}" + ("" if len(clusters[c]) >= 4 else "   <4 lines"))
    print(f"named-round clusters with ≥4 lines: {sum(1 for c in clusters if len(clusters[c]) >= 4)} of {len(clusters)}")
    print("rejections:")
    for k, v in sorted(rejects.items()):
        print(f"   {k}: {v}")
    print("notes:")
    for n in notes:
        print("   " + n)
    print("dropped:")
    for d in dropped:
        print("   " + d)
    summary = {"items": len(items), "four": four, "three": three,
               "clusters": {c: [sizes[c], sorted(clusters[c])] for c in clusters},
               "rejects": rejects, "notes": notes, "dropped": dropped,
               "choices": {i["id"]: [i["title"], i["years"], i["askYear"], i["cluster"],
                                     i["sourceURL"].rsplit("File:", 1)[-1]] for i in items}}
    save_cache("report", summary)


if __name__ == "__main__":
    main()
