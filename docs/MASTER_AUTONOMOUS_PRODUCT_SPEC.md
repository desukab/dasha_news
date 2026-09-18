# Dasha News — Autonomous Product Specification

## Mission

Build a zero-paid-API, Telangana-first short-news platform for Telugu, Tenglish, and English. The system must continuously discover permitted public news sources, extract and reconcile facts, produce original short-form stories, attach valid media, publish to the mobile app, and keep operating without a human newsroom staff.

Primary success condition:

> A normal user can install Dasha, open it, immediately see fresh Telangana-relevant short news, understand the source/evidence, follow stories, receive useful updates, and return daily — while the backend runs unattended on a modest Azure VM.

## Non-negotiable constraints

1. **Zero paid APIs.** Do not require OpenAI, Anthropic, Gemini, Groq, Together, paid search, paid news APIs, paid image APIs, or paid TTS APIs.
2. Prefer free RSS/Atom, official public feeds, legitimate public webpages, public government sources, public court/government notices, and other permitted sources.
3. Scrapling may be integrated where it materially improves permitted acquisition. It must never be used to bypass paywalls, CAPTCHAs, authentication, robots restrictions, rate limits, or anti-bot controls.
4. The app must work in **Telugu, Tenglish, and English**. Telugu and Tenglish are first-class, not afterthoughts.
5. No secrets in source control.
6. No copying or republishing full third-party articles.
7. Every story must preserve source attribution and provenance.
8. Images must have a recorded provenance/usage basis. Do not silently download random copyrighted images from social media or news sites.
9. Normal engineering decisions are autonomous. Do not stop to ask the owner for permission unless an external credential, legal authorization, paid service, irreversible destructive action, or genuinely unknowable product decision is required.
10. If one source, provider, model, parser, or service fails, continue with other available paths.

## Product shape

Dasha should feel like a fast Telangana short-news app, not a newspaper website.

Core feeds:
- Breaking
- Trending
- Hyderabad
- Districts
- Politics
- Crime & accidents
- Government/civic
- Jobs & education
- Business
- Cinema & entertainment
- Sports
- Technology
- Health
- Weather/disasters
- India
- World
- Telangana-interest stories

Core interaction:
- swipe/scroll short cards
- headline + 2–5 sentence summary
- source and publication/update time
- evidence/status badge
- location/category
- image/media
- save/share
- audio where available
- related story cluster
- source link
- correction/update history

## Autonomous newsroom

Discovery → acquisition → normalization → extraction → canonicalization → dedupe → story clustering → fact extraction → source comparison → evidence classification → editorial generation → language variants → media selection → risk gates → publication → monitoring → updates/corrections.

Generated prose is never the source of truth. Structured facts and source evidence are.

## Retention without sacrificing trust

Optimize for useful engagement:
- fast first screen
- highly local recommendations
- strong factual headlines
- trending signals
- breaking notifications
- story updates instead of duplicate articles
- Telugu/Tenglish language preference
- district/location preference
- audio
- shorts
- saved stories
- reading history
- lightweight personalization
- graceful offline cache

Do not optimize retention through fabricated urgency, fake quotes, fake images, impersonation, or knowingly misleading headlines.

## Completion gate

The work is not complete because tests pass. It is complete when the agent has:
- demonstrated the automated pipeline end-to-end;
- demonstrated real permitted public-source ingestion;
- demonstrated Telangana classification;
- demonstrated Telugu/Tenglish/English rendering;
- demonstrated duplicate clustering;
- demonstrated evidence/conflict handling;
- demonstrated valid image provenance;
- demonstrated autonomous scheduled operation;
- demonstrated app/backend integration;
- demonstrated failure recovery;
- produced a release APK;
- documented exactly what remains external configuration.

If a capability cannot be legitimately automated for $0, implement the best zero-cost fallback and document it instead of introducing a paid dependency.
