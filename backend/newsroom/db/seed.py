"""Zero-config source seed.

These are real, publicly advertised RSS feeds of Telugu and national outlets,
used as *configuration* (the list is editable at runtime from the admin
console), never as bundled content. The pipeline fetches them live when it
runs; no article text is shipped with this repository.

Feeds are the intended machine interface for news sites and linking to them is
standard aggregator practice, but the resulting articles remain the copyright
of their publishers. The newsroom therefore never republishes raw article text:
it extracts facts, clusters stories, and generates its own short summaries that
link back to the originating outlet.
"""

from __future__ import annotations

import logging

from sqlalchemy import select

from newsroom.db.engine import db_scope
from newsroom.db.models import Source

logger = logging.getLogger(__name__)

SEED_SOURCES: list[dict[str, object]] = [
    # ---- Telugu dailies -----------------------------------------------------
    {"name": "ఈనాడు – తెలంగాణ", "site": "https://www.eenadu.net", "site_slug": "eenadu",
     "feed": "https://www.eenadu.net/rss/general/topnews.xml", "lang": "te", "trust": 0.75},
    {"name": "సాక్షి – తెలంగాణ", "site": "https://www.sakshi.com", "site_slug": "sakshi",
     "feed": "https://www.sakshi.com/rss/telangana", "lang": "te", "trust": 0.7},
    {"name": "ఆంధ్రజ్యోతి – తెలంగాణ", "site": "https://www.andhrajyothy.com", "site_slug": "andhrajyothy",
     "feed": "https://www.andhrajyothy.com/rss/telangana", "lang": "te", "trust": 0.7},
    {"name": "నమస్తే తెలంగాణ", "site": "https://www.namasthetelangaana.com", "site_slug": "namaste-telangana",
     "feed": "https://www.namasthetelangaana.com/RssFeed.aspx?catid=6", "lang": "te", "trust": 0.7},
    {"name": "ప్రజాశక్తి", "site": "https://www.prajasakti.com", "site_slug": "prajasakti",
     "feed": "https://www.prajasakti.com/rss/telangana", "lang": "te", "trust": 0.65},
    {"name": "తెలంగాణ టుడే", "site": "https://telanganatoday.com", "site_slug": "telangana-today",
     "feed": "https://telanganatoday.com/feed", "lang": "te", "trust": 0.7},
    # ---- National (English) -------------------------------------------------
    {"name": "The Hindu – National", "site": "https://www.thehindu.com", "site_slug": "the-hindu",
     "feed": "https://www.thehindu.com/news/national/feeder/default.rss", "lang": "en", "trust": 0.9},
    {"name": "Indian Express", "site": "https://indianexpress.com", "site_slug": "indian-express",
     "feed": "https://indianexpress.com/feed", "lang": "en", "trust": 0.85},
    {"name": "Hindustan Times", "site": "https://www.hindustantimes.com", "site_slug": "hindustan-times",
     "feed": "https://www.hindustantimes.com/feeds/rss/india-news/rssfeed.xml", "lang": "en", "trust": 0.8},
    # ---- Verticals ----------------------------------------------------------
    {"name": "Cricbuzz", "site": "https://www.cricbuzz.com", "site_slug": "cricbuzz",
     "feed": "https://www.cricbuzz.com/rss/cricket-news.xml", "lang": "en", "trust": 0.8,
     "section": "sports"},
    {"name": "Moneycontrol – Markets", "site": "https://www.moneycontrol.com", "site_slug": "moneycontrol",
     "feed": "https://www.moneycontrol.com/rss/markets.xml", "lang": "en", "trust": 0.8,
     "section": "markets"},
    {"name": "ఈనాడు – క్రీడలు", "site": "https://www.eenadu.net", "site_slug": "eenadu-sports",
     "feed": "https://www.eenadu.net/rss/sports", "lang": "te", "trust": 0.75, "section": "sports"},
    {"name": "ఈనాడు – సినిమా", "site": "https://www.eenadu.net", "site_slug": "eenadu-cinema",
     "feed": "https://www.eenadu.net/rss/cinema", "lang": "te", "trust": 0.7, "section": "cinema"},
]

# Outlets whose RSS channels carry genuine breaking-news flags. Used by the
# breaking detector to trust `<category>breaking</category>` style markers.
BREAKING_CAPABLE = {"the-hindu", "indian-express", "hindustan-times", "eenadu", "sakshi"}


def seed_sources(force: bool = False) -> int:
    """Idempotently create seed sources. Returns the number created."""
    created = 0
    with db_scope() as session:
        existing_guids = {row[0] for row in session.execute(select(Source.guid)).all()}
        for entry in SEED_SOURCES:
            guid = f"seed:{entry['site_slug']}"
            if guid in existing_guids:
                if force:
                    session.execute(
                        Source.__table__.update()
                        .where(Source.guid == guid)
                        .values(
                            name=entry["name"], site_url=entry["site"],
                            feed_url=entry["feed"], language=entry["lang"],
                            trust_score=entry["trust"],
                            default_section=entry.get("section"),
                            is_enabled=True,
                        )
                    )
                continue
            session.add(
                Source(
                    guid=guid,
                    name=str(entry["name"]),
                    site_url=str(entry["site"]),
                    feed_url=str(entry["feed"]),
                    kind="rss",
                    language=str(entry["lang"]),
                    trust_score=float(entry["trust"]),
                    default_section=entry.get("section"),
                    is_enabled=True,
                    is_breaking_capable=entry["site_slug"] in BREAKING_CAPABLE,
                )
            )
            created += 1
    if created:
        logger.info("Seeded %d sources", created)
    return created
