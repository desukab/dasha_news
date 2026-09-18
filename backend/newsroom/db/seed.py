"""Zero-config source seed.

These are real, publicly advertised feeds and pages of Telugu and national
outlets, used as *configuration* (the list is editable at runtime from the
editor console), never as bundled content. The pipeline fetches them live when
it runs; no article text is shipped with this repository.

Feeds are the intended machine interface for news sites and linking to them is
standard aggregator practice, but the resulting articles remain the copyright
of their publishers. The newsroom therefore never republishes raw article text:
it extracts facts, clusters stories, and generates its own short summaries that
link back to the originating outlet.

Every entry below was verified live against the real acquisition path (robots
included) before it was added. The list is deliberately short for that reason:
a dead source costs a sweep a fetch round trip and contributes nothing but
noise to the failure counters. Publishers retire feeds without notice, so the
editor console's per-source ``fetch_error_count`` is what surfaces the next one
to go -- re-verify before adding a source back.
"""

from __future__ import annotations

import logging

from sqlalchemy import select

from newsroom.db.engine import db_scope
from newsroom.db.models import Source

logger = logging.getLogger(__name__)

SEED_SOURCES: list[dict[str, object]] = [
    # ---- Telangana press -----------------------------------------------------
    # The state's highest-volume feed, and the only one that files stories from
    # the districts rather than the capital. Trust is set below the national
    # press: the title is government-owned, so its copy is treated as official
    # positioning first and corroborated reporting second.
    {"name": "Telangana Today", "site": "https://telanganatoday.com",
     "site_slug": "telangana-today", "kind": "rss",
     "feed": "https://telanganatoday.com/feed", "lang": "te", "trust": 0.65},
    {"name": "V6 Velugu", "site": "https://v6velugu.com", "site_slug": "v6velugu",
     "kind": "rss", "feed": "https://v6velugu.com/feed", "lang": "te", "trust": 0.7},
    {"name": "Mirchi9", "site": "https://www.mirchi9.com", "site_slug": "mirchi9",
     "kind": "rss", "feed": "https://www.mirchi9.com/feed", "lang": "te", "trust": 0.6},
    {"name": "The Siasat Daily", "site": "https://www.siasat.com", "site_slug": "siasat",
     "kind": "rss", "feed": "https://www.siasat.com/feed", "lang": "en", "trust": 0.75},
    {"name": "Telangana Tribune", "site": "https://telanganatribune.com",
     "site_slug": "telangana-tribune", "kind": "rss",
     "feed": "https://telanganatribune.com/feed", "lang": "en", "trust": 0.6},
    # ---- National press (Telangana desks first) ------------------------------
    # The Hindu files separate Telangana and Hyderabad feeds, which is what lets
    # the location engine see state and city stories as distinct from national
    # ones rather than bucketing them all as "India".
    {"name": "The Hindu – Telangana", "site": "https://www.thehindu.com",
     "site_slug": "the-hindu-telangana", "kind": "rss",
     "feed": "https://www.thehindu.com/news/national/telangana/feeder/default.rss",
     "lang": "en", "trust": 0.9},
    {"name": "The Hindu – Hyderabad", "site": "https://www.thehindu.com",
     "site_slug": "the-hindu-hyderabad", "kind": "rss",
     "feed": "https://www.thehindu.com/news/cities/Hyderabad/feeder/default.rss",
     "lang": "en", "trust": 0.9},
    {"name": "The Hindu – National", "site": "https://www.thehindu.com",
     "site_slug": "the-hindu-national", "kind": "rss",
     "feed": "https://www.thehindu.com/news/national/feeder/default.rss",
     "lang": "en", "trust": 0.9},
    {"name": "Hindustan Times – India", "site": "https://www.hindustantimes.com",
     "site_slug": "hindustan-times", "kind": "rss",
     "feed": "https://www.hindustantimes.com/feeds/rss/india-news/rssfeed.xml",
     "lang": "en", "trust": 0.8},
    # ---- Government (primary sources, not reporting) -------------------------
    # Press releases are what a government *says*, which is exactly the
    # OFFICIAL_STATEMENT evidence level. High trust as a record of a statement,
    # not as an account of what happened.
    {"name": "Telangana Government – Press Releases", "site": "https://www.telangana.gov.in",
     "site_slug": "tg-gov-press-releases", "kind": "html",
     "feed": "https://www.telangana.gov.in/press-releases", "lang": "en", "trust": 0.8},
    {"name": "Office of the Chief Minister, Telangana", "site": "https://cm.telangana.gov.in",
     "site_slug": "tg-cm-office", "kind": "html",
     "feed": "https://cm.telangana.gov.in/", "lang": "te", "trust": 0.8},
]

# Outlets whose channels carry genuine breaking-news flags. Used by the
# breaking detector to trust `<category>breaking</category>` style markers.
BREAKING_CAPABLE = {
    "the-hindu-telangana", "the-hindu-hyderabad", "the-hindu-national",
    "hindustan-times", "siasat",
}


def seed_sources(force: bool = False) -> int:
    """Idempotently create seed sources. Returns the number created.

    Also retires seed sources that no longer ship with the list. Only our own
    ``seed:`` guids are ever touched this way -- a source an editor added by
    hand is left alone even when its feed has gone quiet, because that is a
    person's deliberate choice and not ours to undo.
    """
    created = 0
    with db_scope() as session:
        existing_guids = {row[0] for row in session.execute(select(Source.guid)).all()}
        shipped = set()
        for entry in SEED_SOURCES:
            guid = f"seed:{entry['site_slug']}"
            shipped.add(guid)
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
                    kind=str(entry.get("kind") or "rss"),
                    language=str(entry["lang"]),
                    trust_score=float(entry["trust"]),
                    default_section=entry.get("section"),
                    is_enabled=True,
                    is_breaking_capable=entry["site_slug"] in BREAKING_CAPABLE,
                )
            )
            created += 1

        retired = sorted(guid for guid in existing_guids
                         if guid.startswith("seed:") and guid not in shipped)
        for guid in retired:
            session.execute(
                Source.__table__.update()
                .where(Source.guid == guid, Source.is_enabled.is_(True))
                .values(is_enabled=False)
            )
        if retired:
            logger.info("Retired %d seed source(s) no longer shipped: %s",
                        len(retired), ", ".join(retired))
    if created:
        logger.info("Seeded %d sources", created)
    return created
