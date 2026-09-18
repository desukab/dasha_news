"""Editorial section taxonomy.

Sections are the product's navigation surface. Each one carries:
  * a stable slug (used in URLs and the API),
  * display names in Telugu, Tenglish and English,
  * keyword seeds the classifier uses when no LLM is configured,
  * flags telling the newsroom how to treat the section (sensitivity, whether
    it belongs to the Telangana local desk, the priority used for ordering).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List


@dataclass(frozen=True)
class Section:
    slug: str
    te: str
    ten: str          # Tenglish: Telugu in Latin script
    en: str
    keywords: List[str] = field(default_factory=list)
    priority: int = 50        # higher = earlier in navigation
    telangana_local: bool = False
    sensitive: bool = False   # always held for human review when True


SECTIONS: List[Section] = [
    Section("breaking", "బ్రేకింగ్", "Breaking", "Breaking News",
            keywords=["breaking", "urgent", "flash", "just in", "బ్రేకింగ్"],
            priority=100),
    Section("developing", "కొనసాగుతున్న", "Developing", "Developing Stories",
            keywords=["developing", "live updates", "కొనసాగుతున్న", "తాజా"],
            priority=99),
    Section("telangana", "తెలంగాణ", "Telangana", "Telangana",
            keywords=["telangana", "kcr", "ktr", "revanth", "prasanthi", "తెలంగాణ",
                      "హైదరాబాద్", "ముఖ్యమంత్రి", "ప్రభుత్వం"],
            priority=98, telangana_local=True),
    Section("hyderabad", "హైదరాబాద్", "Hyderabad", "Hyderabad",
            keywords=["hyderabad", "ghmc", "secunderabad", "cyberabad", "హైదరాబాద్",
                      "సికింద్రాబాద్", "జిహెచ్ఎంసి"],
            priority=97, telangana_local=True),
    Section("districts", "జిల్లాలు", "Jillalu", "Districts",
            keywords=["district", "mandal", "village", "జిల్లా", "మండలం", "గ్రామం"],
            priority=96, telangana_local=True),
    Section("national", "జాతీయం", "Jatheeyam", "National",
            keywords=["national", "india", "delhi", "parliament", "modi", "bjp",
                      "congress", "centre", "జాతీయ", "కేంద్రం", "పార్లమెంట్"],
            priority=95),
    Section("world", "అంతర్జాతీయం", "Antharjatheeyam", "World",
            keywords=["world", "global", "international", "united states", "china",
                      "russia", "ukraine", "gaza", "israel", "ప్రపంచం", "అంతర్జాతీయం"],
            priority=94),
    Section("politics", "రాజకీయాలు", "Rajakeeyalu", "Politics",
            keywords=["politics", "election", "bypass", "assembly", "mla", "mp",
                      "party", "campaign", "రాజకీయాలు", "ఎన్నికలు", "పార్టీ"],
            priority=93),
    Section("elections", "ఎన్నికలు", "Eennikalu", "Elections",
            keywords=["election", "elections", "ec", "polling", "vote", "campaign",
                      "ఎన్నికలు", "ఓటింగ్", "పోలింగ్"],
            priority=92),
    Section("government", "ప్రభుత్వం", "Prabhutvam", "Government",
            keywords=["government", "ministry", "scheme", "policy", "official",
                      "notification", "ప్రభుత్వం", "పథకం", "ఉత్తర్వు"],
            priority=91),
    Section("crime", "నేరాలు", "Nerelu", "Crime",
            keywords=["crime", "murder", "theft", "robbery", "assault", "arrest",
                      "police", "fir", "నేరం", "హత్య", "దోపిడీ", "పోలీసులు"],
            priority=90, sensitive=True),
    Section("courts", "న్యాయవ్యవస్థ", "Nyayavyavastha", "Courts",
            keywords=["court", "high court", "supreme court", "judge", "verdict",
                      "bail", "hearing", "కోర్టు", "న్యాయమూర్తి", "తీర్పు"],
            priority=89, sensitive=True),
    Section("accidents", "ప్రమాదాలు", "Pramadalu", "Accidents",
            keywords=["accident", "crash", "collision", "fire", "drown", "ప్రమాదం",
                      "దుర్ఘటన", "అగ్నిప్రమాదం"],
            priority=88, sensitive=True),
    Section("education", "విద్య", "Vidya", "Education",
            keywords=["education", "school", "college", "exam", "results", "university",
                      "tcet", "eamcet", "విద్య", "పాఠశాల", "కళాశాల", "పరీక్ష"],
            priority=87),
    Section("jobs", "ఉద్యోగాలు", "Udyogalu", "Jobs",
            keywords=["job", "jobs", "recruitment", "vacancy", "tspsc", "upsc", "ssc",
                      "notification", "ఉద్యోగం", "నియామకం", "ఖాళీ"],
            priority=86),
    Section("business", "వ్యాపారం", "Vyaparalu", "Business",
            keywords=["business", "economy", "industry", "startup", "trade", "tax",
                      "వ్యాపారం", "ఆర్థికం", "పరిశ్రమ"],
            priority=85),
    Section("markets", "మార్కెట్లు", "Markets", "Markets",
            keywords=["market", "markets", "sensex", "nifty", "share", "stock", "gold",
                      "petrol", "diesel", "షేర్", "మార్కెట్", "బంగారం"],
            priority=84),
    Section("technology", "సాంకేతికత", "Tech", "Technology",
            keywords=["technology", "tech", "ai", "software", "app", "internet",
                      "smartphone", "టెక్నాలజీ", "సాఫ్ట్‌వేర్", "ఆర్టిఫిషియల్ ఇంటెలిజెన్స్"],
            priority=83),
    Section("science", "శాస్త్రం", "Shastram", "Science",
            keywords=["science", "space", "isro", "research", "study", "శాస్త్రం",
                      "అంతరిక్షం", "పరిశోధన"],
            priority=82),
    Section("sports", "క్రీడలు", "Kreelalu", "Sports",
            keywords=["sports", "cricket", "football", "badminton", "olympic", "match",
                      "batsman", "wicket", "క్రీడలు", "క్రికెట్", "మ్యాచ్"],
            priority=81),
    Section("cinema", "సినిమా", "Cinema", "Cinema",
            keywords=["cinema", "movie", "film", "actor", "actress", "director",
                      "tollywood", "bollywood", "సినిమా", "చిత్రం", "నటుడు",
                      "నటి", "టాలీవుడ్"],
            priority=80),
    Section("entertainment", "వినోదం", "Vinodam", "Entertainment",
            keywords=["entertainment", "tv", "ott", "music", "concert", "festival",
                      "వినోదం", "వినోదం", "సంగీతం", "ఓటీటీ"],
            priority=79),
    Section("health", "ఆరోగ్యం", "Aarogyam", "Health",
            keywords=["health", "hospital", "doctor", "disease", "vaccine", "medical",
                      "ఆరోగ్యం", "ఆసుపత్రి", "వైద్యుడు", "వ్యాధి"],
            priority=78),
    Section("weather", "వాతావరణం", "VatavarANam", "Weather",
            keywords=["weather", "rain", "monsoon", "temperature", "heatwave", "cyclone",
                      "forecast", "వాతావరణం", "వర్షం", "ఉష్ణోగ్రత"],
            priority=77),
    Section("agriculture", "వ్యవసాయం", "Vyavasayam", "Agriculture",
            keywords=["agriculture", "farmer", "crop", "irrigation", "soil", "kharif",
                      "rabi", "వ్యవసాయం", "రైతు", "పంట", "నీటిపారుదల"],
            priority=76),
    Section("infrastructure", "మౌలిక సదుపాయాలు", "Infra", "Infrastructure",
            keywords=["infrastructure", "metro", "road", "bridge", "flyover", "airport",
                      "construction", "మెట్రో", "రోడ్డు", "వంతెన", "నిర్మాణం"],
            priority=75),
    Section("civic", "పౌర సమస్యలు", "Civic", "Civic Issues",
            keywords=["civic", "water", "sewage", "garbage", "power cut", "traffic",
                      "తాగునీరు", "చెత్త", "ట్రాఫిక్", "కరెంటు"],
            priority=74, telangana_local=True),
    Section("explainers", "విశ్లేషణ", "Vishleshana", "Explainers",
            keywords=["explainer", "analysis", "why it matters", "context",
                      "విశ్లేషణ", "వ్యాఖ్యానం", "నేపథ్యం"],
            priority=73),
    Section("unverified", "నిర్ధారణ లేదు", "Unverified", "Unverified Reports",
            keywords=["unverified", "rumour", "claim", "yet to confirm",
                      "నిర్ధారణ లేదు", "పుకారు"],
            priority=40, sensitive=True),
]

BY_SLUG: Dict[str, Section] = {s.slug: s for s in SECTIONS}

# Sections surfaced as the app's primary tabs / chips. Everything else is
# reachable through Explore and Search.
PRIMARY_SLUGS: List[str] = [
    "breaking", "developing", "telangana", "hyderabad", "districts",
    "national", "politics", "crime", "sports", "cinema", "business",
    "technology", "education", "jobs", "health",
]

ALL_SLUGS: List[str] = [s.slug for s in SECTIONS]


def section_for_slug(slug: str) -> Section:
    return BY_SLUG[slug]


def is_sensitive(slug: str) -> bool:
    section = BY_SLUG.get(slug)
    return bool(section and section.sensitive)
