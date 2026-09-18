"""Telangana geographic hierarchy used by the Location Engine.

Structure:  State -> District -> Mandal -> Town / Locality

The district list reflects the 33 districts formed after the 2016 and 2023
reorganisations. `LOCATOR` maps aliases (English spellings, common Telugu
transliterations, old district names, assembly constituency names) to the
canonical district so that messy source text resolves reliably.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

STATE = "Telangana"
CAPITAL = "Hyderabad"

# The 33 districts, grouped by the state's official revenue-division regions.
DISTRICTS: Dict[str, List[str]] = {
    "hyderabad": ["Hyderabad"],
    "medchal_malkajgiri": ["Medchal-Malkajgiri"],
    "rangareddy": ["Rangareddy"],
    "vikarabad": ["Vikarabad"],
    "sangareddy": ["Sangareddy"],
    "medak": ["Medak"],
    "siddipet": ["Siddipet"],
    "yadadri_bhuvanagiri": ["Yadadri Bhuvanagiri"],
    "nalgonda": ["Nalgonda"],
    "suryapet": ["Suryapet"],
    "jangaon": ["Jangaon"],
    "warangal": ["Warangal Rural", "Warangal Urban", "Hanamkonda"],
    "mahabubabad": ["Mahabubabad"],
    "mulugu": ["Mulugu"],
    "jayashankar_bhupalapally": ["Jayashankar Bhupalapally"],
    "khammam": ["Khammam"],
    "bhadradri_kothagudem": ["Bhadradri Kothagudem"],
    "nagarkurnool": ["Nagarkurnool"],
    "wanaparthy": ["Wanaparthy"],
    "naryana": ["Narayanpet"],
    "mahbubnagar": ["Mahbubnagar"],
    "jogulamba_gadwal": ["Jogulamba Gadwal"],
    "nizamabad": ["Nizamabad"],
    "kamareddy": ["Kamareddy"],
    "adilabad": ["Adilabad"],
    "komaram_bheem_asifabad": ["Komaram Bheem Asifabad"],
    "nirmal": ["Nirmal"],
    "mancherial": ["Mancherial"],
    "karimnagar": ["Karimnagar"],
    "rajanna_sircilla": ["Rajanna Sircilla"],
    "peddapalli": ["Peddapalli"],
    "jagtial": ["Jagtial"],
    "bhadradri": ["Bhadradri Kothagudem"],
}

# Flat canonical district set (bhadradri de-duplicated against the region key).
ALL_DISTRICTS: List[str] = sorted({d for group in DISTRICTS.values() for d in group})

# Major mandals / towns per district. Non-exhaustive but covers the population
# centres that dominate local news, which is what the Location Engine needs.
MANDALS: Dict[str, List[str]] = {
    "Hyderabad": [
        "Abids", "Ameerpet", "Asifnagar", "Bahadurpura", "Bandlaguda",
        "Charminar", "Golconda", "Himayatnagar", "Khairatabad", "Kukatpally",
        "Madhapur", "Malakpet", "Manikonda", "Nampally", "Qutubullapur",
        "Rajendranagar", "Secunderabad", "Serilingampally", "Shaikpet",
        "Thirumalagiri", "Trimulgherry", "Vanasthalipuram", "Musheerabad",
        "Amberpet", "Karwan", "Yakutpura", "Chandrayangutta",
    ],
    "Medchal-Malkajgiri": [
        "Medchal", "Malkajgiri", "Keesara", "Bachupally", "Nizampet",
        "Dundigal", "Shamirpet", "Uppal", "Kapra", "Alwal",
    ],
    "Rangareddy": [
        "Rangareddy", "Saroornagar", "Balapur", "Ibrahimpatnam", "Maheswaram",
        "Shadnagar", "Chevella", "Moinabad", "Shankarpalle", "Kandukur",
    ],
    "Warangal Urban": ["Warangal", "Hanamkonda", "Kazipet", "Hasanparthy", "Wardhannapet"],
    "Warangal Rural": ["Narsampet", "Parkal", "Jangaon", "Cherial", "Rayaparthy"],
    "Hanamkonda": ["Hanamkonda", "Kazipet", "Warangal"],
    "Karimnagar": ["Karimnagar", "Huzurabad", "Jagtial", "Sircilla", "Manakondur"],
    "Khammam": ["Khammam", "Kothagudem", "Palwancha", "Sattupally", "Madhira", "Wyra"],
    "Nizamabad": ["Nizamabad", "Armoor", "Bodhan", "Kamareddy", "Banswada"],
    "Mahbubnagar": ["Mahbubnagar", "Gadwal", "Narayanpet", "Wanaparthy", "Kollapur"],
    "Nalgonda": ["Nalgonda", "Miryalaguda", "Suryapet", "Bhongir", "Mothe"],
    "Adilabad": ["Adilabad", "Nirmal", "Mancherial", "Utnoor", "Asifabad"],
    "Medak": ["Medak", "Sangareddy", "Siddipet", "Narayankhed", "Zaheerabad"],
    "Siddipet": ["Siddipet", "Gajwel", "Husnabad", "Dubbak", "Cherial"],
}

# Assembly constituencies -> district, for source text that names a seat rather
# than a district (very common in Telugu political coverage).
CONSTITUENCIES: Dict[str, str] = {
    "Gajwel": "Siddipet", "Sircilla": "Rajanna Sircilla", "Korutla": "Jagtial",
    "Karimnagar": "Karimnagar", "Mancherial": "Mancherial", "Nirmal": "Nirmal",
    "Asifabad": "Komaram Bheem Asifabad", "Boath": "Adilabad",
    "Mudhole": "Nizamabad", "Bodhan": "Nizamabad", "Armoor": "Nizamabad",
    "Kamareddy": "Kamareddy", "Nizamabad Urban": "Nizamabad",
    "Medak": "Medak", "Narayankhed": "Medak", "Sangareddy": "Sangareddy",
    "Andole": "Sangareddy", "Patancheru": "Sangareddy", "Medchal": "Medchal-Malkajgiri",
    "Malkajgiri": "Medchal-Malkajgiri", "Quthbullapur": "Medchal-Malkajgiri",
    "Uppal": "Medchal-Malkajgiri", "Ibrahimpatnam": "Rangareddy",
    "Maheswaram": "Rangareddy", "Rajendranagar": "Rangareddy",
    "Serilingampally": "Rangareddy", "Musheerabad": "Hyderabad",
    "Amberpet": "Hyderabad", "Khairatabad": "Hyderabad", "Secunderabad": "Hyderabad",
    "Malakpet": "Hyderabad", "Karwan": "Hyderabad", "Charminar": "Hyderabad",
    "Chandrayangutta": "Hyderabad", "Bahadurpura": "Hyderabad", "Nampally": "Hyderabad",
    "Yakutpura": "Hyderabad", "Goshamahal": "Hyderabad",
    "Huzurnagar": "Nalgonda", "Kodad": "Nalgonda", "Nagarjuna Sagar": "Nalgonda",
    "Devarakonda": "Nalgonda", "Miryalaguda": "Nalgonda",
    "Suryapet": "Suryapet", "Thungathurthy": "Suryapet",
    "Bhongir": "Yadadri Bhuvanagiri", "Alair": "Yadadri Bhuvanagiri",
    "Jangaon": "Jangaon", "Ghanpur": "Jangaon", "Palakurthi": "Jangaon",
    "Narsampet": "Warangal Rural", "Parkal": "Warangal Rural",
    "Warangal East": "Warangal Urban", "Warangal West": "Warangal Urban",
    "Shadnagar": "Rangareddy", "Kollapur": "Mahbubnagar",
    "Kalwakurthy": "Mahbubnagar", "Achampet": "Nagarkurnool",
    "Nagarkurnool": "Nagarkurnool", "Kollam": "Nagarkurnool",
    "Gadwal": "Jogulamba Gadwal", "Alampur": "Jogulamba Gadwal",
    "Narayanpet": "Narayanpet", "Makthal": "Narayanpet",
    "Mahbubnagar": "Mahbubnagar", "Devarkadra": "Mahbubnagar",
    "Wanaparthy": "Wanaparthy", "Pangal": "Wanaparthy",
    "Kothagudem": "Bhadradri Kothagudem", "Aswaraopeta": "Bhadradri Kothagudem",
    "Sattupally": "Khammam", "Madhira": "Khammam", "Palair": "Khammam",
    "Wyra": "Khammam", "Khammam": "Khammam",
    "Mulugu": "Mulugu", "Eturnagaram": "Mulugu",
    "Pinapaka": "Bhadradri Kothagudem", "Bhadrachalam": "Bhadradri Kothagudem",
    "Manthani": "Peddapalli", "Peddapalli": "Peddapalli", "Ramagundam": "Peddapalli",
    "Choppadandi": "Karimnagar", "Vemulawada": "Rajanna Sircilla",
    "Huzurabad": "Karimnagar", "Jagtial": "Jagtial",
}

# Aliases -> canonical district. Includes pre-2016 district names, which are
# still common in copy from agencies that never updated their style guides.
ALIASES: Dict[str, str] = {
    # Pre-2016 composite districts
    "Warangal District": "Warangal Urban",
    "Khammam District": "Khammam",
    "Nalgonda District": "Nalgonda",
    "Mahbubnagar District": "Mahbubnagar",
    "Medak District": "Medak",
    "Adilabad District": "Adilabad",
    "Karimnagar District": "Karimnagar",
    "Nizamabad District": "Nizamabad",
    "Rangareddy District": "Rangareddy",
    # Common transliterations / abbreviations
    "Hyd": "Hyderabad", "Hyd.": "Hyderabad", "Secunderabad": "Hyderabad",
    "Sec-bad": "Hyderabad", "Cyberabad": "Hyderabad",
    "Warangal": "Warangal Urban", "Warangal City": "Warangal Urban",
    "Rural": "Warangal Rural", "Kothagudem": "Bhadradri Kothagudem",
    "Bhadradri": "Bhadradri Kothagudem", "Asifabad": "Komaram Bheem Asifabad",
    "K B Asifabad": "Komaram Bheem Asifabad", "KB Asifabad": "Komaram Bheem Asifabad",
    "Bupalpally": "Jayashankar Bhupalapally", "Bhupalpalle": "Jayashankar Bhupalapally",
    "Gadwal": "Jogulamba Gadwal", "Jogulamba": "Jogulamba Gadwal",
    "Sircilla": "Rajanna Sircilla", "Rajanna": "Rajanna Sircilla",
    "Bhongiri": "Yadadri Bhuvanagiri", "Yadadri": "Yadadri Bhuvanagiri",
    "Nagarkurnole": "Nagarkurnool", "Nagar Kurnool": "Nagarkurnool",
    "Mahaboobnagar": "Mahbubnagar", "Mahabubnagar": "Mahbubnagar",
    "Mehboobnagar": "Mahbubnagar", "Palamoor": "Mahbubnagar",
    "Nizamabad Urban": "Nizamabad", "Nizamabad Rural": "Nizamabad",
    "Kamareddy": "Kamareddy", "Kamareddi": "Kamareddy",
    "Manchiryala": "Mancherial", "Mancherial": "Mancherial",
    "Jagityal": "Jagtial", "Jagitial": "Jagtial",
    "Adilabad": "Adilabad", "Adhilabad": "Adilabad",
    "Vikarabad": "Vikarabad", "Tandur": "Vikarabad",
    "Sangareddy": "Sangareddy", "Sangareddi": "Sangareddy",
    "Medchal": "Medchal-Malkajgiri", "Malkajgiri": "Medchal-Malkajgiri",
    "RR Dist": "Rangareddy", "R R District": "Rangareddy",
    "Mulugu": "Mulugu", "Mahabubabad": "Mahabubabad",
    "Bayyaram": "Mahabubabad", "Dornakal": "Mahabubabad",
    "Narayanpet": "Narayanpet", "Narayanapet": "Narayanpet",
    "Suryapet": "Suryapet", "Suryapeta": "Suryapet",
    "Jangaon": "Jangaon", "Jangoan": "Jangaon",
    "Peddapalli": "Peddapalli", "Peddapally": "Peddapalli",
    "Ramagundam": "Peddapalli", "Godavarikhani": "Peddapalli",
    "Huzurabad": "Karimnagar", "Karimnagar": "Karimnagar",
    "Khammam Urban": "Khammam", "Khammam Rural": "Khammam",
    "Palwancha": "Bhadradri Kothagudem", "Paloncha": "Bhadradri Kothagudem",
    "Yellandu": "Bhadradri Kothagudem", "Manuguru": "Bhadradri Kothagudem",

    # Telugu-script district names. A Telangana-first product must resolve
    # Telugu copy, not only transliterated English.
    "హైదరాబాద్": "Hyderabad",
    "హైదరాబాదు": "Hyderabad",
    "మెద్చల్ మల్కాజ్‌గిరి": "Medchal-Malkajgiri",
    "మల్కాజ్‌గిరి": "Medchal-Malkajgiri",
    "రంగారెడ్డి": "Rangareddy",
    "వికారాబాద్": "Vikarabad",
    "సంగారెడ్డి": "Sangareddy",
    "మేడ్చల్": "Medchal",
    "సిద్దిపేట": "Siddipet",
    "యాదాద్రి భువనగిరి": "Yadadri Bhuvanagiri",
    "భువనగిరి": "Yadadri Bhuvanagiri",
    "నల్గొండ": "Nalgonda",
    "సూర్యాపేట": "Suryapet",
    "జనగామ": "Jangaon",
    "వరంగల్": "Warangal Urban",
    "వరంగల్ నగరం": "Warangal Urban",
    "హనుమకొండ": "Hanamkonda",
    "మహబూబాబాద్": "Mahabubabad",
    "ములుగు": "Mulugu",
    "జయశంకర్ భూపాలపల్లి": "Jayashankar Bhupalapally",
    "ఖమ్మం": "Khammam",
    "భద్రాద్రి కొత్తగూడెం": "Bhadradri Kothagudem",
    "కొత్తగూడెం": "Bhadradri Kothagudem",
    "నాగర్‌కర్నూల్": "Nagarkurnool",
    "వనపర్తి": "Wanaparthy",
    "నారాయణపేట": "Narayanpet",
    "మహబూబ్‌నగర్": "Mahbubnagar",
    "మహబూబ్ నగర్": "Mahbubnagar",
    "పాలమూరు": "Mahbubnagar",
    "జోగులాంబ గద్వాల": "Jogulamba Gadwal",
    "గద్వాల": "Jogulamba Gadwal",
    "నిజామాబాద్": "Nizamabad",
    "కామారెడ్డి": "Kamareddy",
    "ఆదిలాబాద్": "Adilabad",
    "కొమారం భీం ఆసిఫాబాద్": "Komaram Bheem Asifabad",
    "ఆసిఫాబాద్": "Komaram Bheem Asifabad",
    "నిర్మల్": "Nirmal",
    "మంచిర్యాల": "Mancherial",
    "మంచిర్యాల్": "Mancherial",
    "కరీంనగర్": "Karimnagar",
    "రాజన్న సిరిసిల్ల": "Rajanna Sircilla",
    "సిరిసిల్ల": "Rajanna Sircilla",
    "పెద్దపల్లి": "Peddapalli",
    "జగిత్యాల": "Jagtial",
    "సికింద్రాబాద్": "Hyderabad",
    "సికింద్రాబాదు": "Hyderabad",
}

# Assembly constituencies resolve through the same lookup as aliases.
for _seat, _district in CONSTITUENCIES.items():
    ALIASES.setdefault(_seat, _district)

# The plain English district names. These were missing from the hand-written
# alias table, which meant English copy naming a district directly ("...in
# Hyderabad") resolved to state-level news while the Telugu and abbreviated
# spellings worked. Derived from DISTRICTS so the canonical name can never
# drift from the district list.
for _district in ALL_DISTRICTS:
    ALIASES.setdefault(_district, _district)

HYDERABAD_LOCALITIES: List[str] = MANDALS["Hyderabad"]


@dataclass
class GeoMatch:
    """Result of resolving location mentions in a piece of text."""

    state: Optional[str] = None
    district: Optional[str] = None
    mandal: Optional[str] = None
    locality: Optional[str] = None
    matched_terms: List[str] = field(default_factory=list)

    @property
    def is_state_level(self) -> bool:
        return self.district is None and self.state is not None

    @property
    def is_district_level(self) -> bool:
        return self.district is not None and self.mandal is None

    def as_path(self) -> Tuple[str, ...]:
        parts = [p for p in (self.state, self.district, self.mandal, self.locality) if p]
        return tuple(parts)

    def to_dict(self) -> Dict[str, Optional[str]]:
        return {
            "state": self.state,
            "district": self.district,
            "mandal": self.mandal,
            "locality": self.locality,
        }


def _district_index() -> Dict[str, str]:
    index: Dict[str, str] = {}
    for district in ALL_DISTRICTS:
        index[district.lower()] = district
        # Allow "Warangal Urban" to also match bare "Warangal Urban".
        for token in district.lower().replace("-", " ").split():
            if len(token) > 3:
                index.setdefault(token, district)
    return index


_DISTRICT_INDEX = _district_index()
_MANDAL_INDEX = {m.lower(): d for d, ms in MANDALS.items() for m in ms}


def resolve_location(text: Optional[str]) -> GeoMatch:
    """Resolve free text to the deepest place in the hierarchy it supports.

    Purely deterministic: longest-match-first scanning, with locality matches
    preferred over district matches (a locality implies its district). This is
    deliberately conservative -- if nothing is recognised the story is filed as
    state-level Telangana news rather than being forced into a wrong district.
    """
    if not text:
        return GeoMatch()
    lowered = " " + _normalize(text) + " "

    matched: List[str] = []
    state: Optional[str] = None
    district: Optional[str] = None
    mandal: Optional[str] = None
    locality: Optional[str] = None

    # National / international context is tracked separately from the Telangana
    # hierarchy; callers use it to pick the world/national section.
    nation_terms = ["india", "delhi", "new delhi", "centre", "central government",
                    "union government", "parliament", "supreme court", "lok sabha"]
    world_terms = ["usa", "united states", "us ", "uk", "britain", "china", "russia",
                   "pakistan", "israel", "gaza", "ukraine", "united nations",
                   "world bank", "imf", "global", "international"]

    # --- longest-first matching over aliases and constituencies -----------
    # NOTE: the loop variable must not be named `district` -- it would clobber
    # this function's own `district` accumulator and silently resolve every
    # story to whichever alias happens to be last in the mapping.
    alias_hits: List[Tuple[str, str, int]] = []
    for alias, alias_district in ALIASES.items():
        needle = " " + _normalize(alias) + " "
        pos = lowered.find(needle)
        if pos >= 0:
            alias_hits.append((alias, alias_district, len(alias)))
    alias_hits.sort(key=lambda item: item[2], reverse=True)

    consumed_spans: List[Tuple[int, int]] = []

    def _overlaps(start: int, end: int) -> bool:
        return any(not (end <= s or start >= e) for s, e in consumed_spans)

    for alias, alias_district, _length in alias_hits:
        needle = " " + _normalize(alias) + " "
        pos = lowered.find(needle)
        while pos >= 0:
            start, end = pos, pos + len(needle)
            if not _overlaps(start, end):
                consumed_spans.append((start, end))
                matched.append(alias)
                district = _prefer_more_specific(district, alias_district)
                break
            pos = lowered.find(needle, pos + 1)

    # --- mandals / localities ---------------------------------------------
    for mandal_name, mandal_district in sorted(_MANDAL_INDEX.items(), key=lambda kv: len(kv[0]), reverse=True):
        needle = " " + mandal_name + " "
        pos = lowered.find(needle)
        while pos >= 0:
            start, end = pos, pos + len(needle)
            if not _overlaps(start, end):
                consumed_spans.append((start, end))
                matched.append(mandal_name)
                if district is None:
                    district = mandal_district
                mandal = mandal_name
                if district == mandal_district:
                    locality = mandal_name
                break
            pos = lowered.find(needle, pos + 1)

    if any(term in lowered for term in nation_terms):
        state = "India"
    if any(term in lowered for term in world_terms):
        state = "World"

    if district is not None or state in (None, "Telangana"):
        state = state or "Telangana"

    # A national/world story with no Telangana angle should not be filed
    # under Telangana just because it was published from Hyderabad.
    if state in ("India", "World") and district is None:
        return GeoMatch(state=state, matched_terms=matched)

    return GeoMatch(
        state="Telangana" if district else state,
        district=district,
        mandal=mandal,
        locality=locality,
        matched_terms=sorted(set(matched)),
    )


def _prefer_more_specific(current: Optional[str], candidate: str) -> str:
    if current is None:
        return candidate
    if candidate == current:
        return candidate
    # Composite-district members (Warangal Urban/Rural) are more specific than
    # the composite name, so prefer them.
    composite_members = {"Warangal Urban", "Warangal Rural", "Hanamkonda"}
    if candidate in composite_members:
        return candidate
    return current


def _normalize(text: str) -> str:
    """Lowercase and de-punctuate, keeping non-Latin scripts intact.

    Combining marks (Telugu vowel signs, anusvara) are NOT `str.isalnum()`, so
    filtering on `isalnum()` alone would turn 'హైదరాబాద్' into 'హ దర బ ద'. Whole
    non-Latin script blocks are treated as alphabetic here.
    """
    out = []
    prev_space = False
    for ch in text.lower():
        if _is_alphabetic(ch):
            out.append(ch)
            prev_space = False
        elif ch in ".'’-":
            out.append(ch)
            prev_space = False
        else:
            if not prev_space:
                out.append(" ")
                prev_space = True
    return "".join(out).strip()


def _is_alphabetic(char: str) -> bool:
    if char.isalnum():
        return True
    # Latin-adjacent letters already pass above; this covers Indic combining
    # marks (Mn/Mc) and signs, which Python does not consider alphanumeric.
    code = ord(char)
    return (
        0x0900 <= code <= 0x097F   # Devanagari
        or 0x0980 <= code <= 0x09FF  # Bengali/Assamese
        or 0x0C00 <= code <= 0x0C7F  # Telugu
        or 0x0D00 <= code <= 0x0D7F  # Kannada/Malayalam
        or 0x0B80 <= code <= 0x0BFF  # Tamil
    )


def district_for(locality_or_district: str) -> Optional[str]:
    """Public helper: any place name -> its canonical district (or None)."""
    if not locality_or_district:
        return None
    key = _normalize(locality_or_district)
    if key in _DISTRICT_INDEX:
        return _DISTRICT_INDEX[key]
    if key in _MANDAL_INDEX:
        return _MANDAL_INDEX[key]
    if key in {k.lower(): v for k, v in ALIASES.items()}:
        return ALIASES[_unnormalize_alias(key)]
    return None


def _unnormalize_alias(key: str) -> str:
    for alias in ALIASES:
        if _normalize(alias) == key:
            return alias
    raise KeyError(key)
