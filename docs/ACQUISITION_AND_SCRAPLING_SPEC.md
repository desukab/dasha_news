# Dasha News — Zero-Cost Acquisition & Scrapling Specification

## Goal

Maximize useful Telangana coverage using free and legitimately accessible sources. Quality and resilience matter more than raw scrape count.

## Acquisition priority

1. RSS/Atom/JSON feeds
2. Official public APIs/endpoints that are genuinely free without a paid plan
3. Government/public institutional pages
4. Legitimately accessible public HTML
5. Scrapling for sources where its extraction capabilities materially improve quality and where automated access is permitted
6. Other free local/public datasets

Never make a paid API a required dependency.

## Source registry

Each source should record:
- stable id
- publisher name
- domain
- region
- district coverage
- category
- language
- access method
- feed URL
- article URL pattern
- robots/terms notes
- crawl frequency
- rate limit
- enabled
- priority
- parser
- image policy
- license/usage notes
- last success/failure
- extraction quality metrics

## Telangana coverage

Build broad coverage across Hyderabad and all currently recognized Telangana districts. Do not hard-code an obsolete district list without verifying current official naming/structure.

Prioritize:
- Telangana government departments
- police and emergency/public-safety sources
- courts and official notices
- GHMC/local bodies
- transport/metro/rail/RTC
- education/recruitment
- health/public alerts
- weather/disaster sources
- agriculture
- local business
- Telugu media
- English India media
- district/local publishers
- entertainment/sports sources

## Scrapling rules

Scrapling is an acquisition/extraction component, not a bypass mechanism.

Allowed:
- public pages accessible without authentication
- normal rendering needed to obtain content that the source intentionally exposes publicly
- respectful rate limits
- source-specific parsers
- extraction from pages where automated access is permitted

Forbidden:
- bypassing paywalls
- bypassing CAPTCHA
- defeating bot protection
- credential/session theft
- evading explicit access controls
- scraping private accounts
- ignoring contractual restrictions

If Scrapling does not materially improve a source or quality metric, do not force it into the path.

## Quality metrics

Measure per source:
- fetch success
- extraction success
- usable article rate
- duplicate rate
- canonical URL accuracy
- publication date accuracy
- district classification accuracy
- language/script detection accuracy
- source diversity
- median/p95 latency
- retry/failure rate
- image availability
- provenance completeness

## Free-first failure strategy

If an external source fails:
- retry with backoff;
- use RSS if available;
- use another permitted source;
- keep the story cluster alive from existing evidence;
- mark stale/unavailable sources;
- never block the whole newsroom.

## Real-world validation

The autonomous agent must test a representative set of public Telangana sources, record results, and build source adapters only from evidence. Do not claim coverage merely because a domain was added to a config file.
