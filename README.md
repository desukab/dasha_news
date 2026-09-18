# Dasha News

A Telangana-first, AI-native digital newspaper — Telugu, Tenglish and
English — with a Flutter reader app and a FastAPI newsroom that stores
news as structured facts rather than prose.

## What is here

```
app/         Flutter reader app (Android)
backend/     FastAPI newsroom: ingest, NLP, evidence scoring, media
```

### Editorial model

Every story is a cluster of source reports resolved into **structured
facts**, each carrying an evidence level from a fixed taxonomy:

`fact` · `official` · `claim` · `allegation` · `disputed` · `unverified`

The app never softens these levels — an allegation reaches the reader
labelled as an allegation. Derived signals shown on every card:

- **corroboration** — two or more independent outlets reported it;
- **conflict** — sources materially disagree (for example differing
  casualty figures), which is surfaced, never averaged away;
- **correction** — the story was amended after publication, with its
  version and update history attached.

External news content is untrusted input throughout: it is sanitised on
ingest, and original article text is never reproduced in full — Dasha
publishes its own original summaries.

## Newsroom backend

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp ../.env.example .env          # then edit: database URL, AI provider
uvicorn newsroom.api.main:app --reload --port 8000
```

The API surface includes `/v1/feed`, `/v1/breaking`, `/v1/developing`,
`/v1/story/{id}`, `/v1/search`, `/v1/sections`, `/v1/districts`,
`/v1/bookmarks`, `/v1/history`, `/v1/submissions` (the reader tip line)
and an admin console under `/admin`.

AI assistance (drafting, summarising, evidence tagging) goes through a
provider abstraction in `backend/newsroom/ai/provider.py`; any
OpenAI-compatible endpoint or local Ollama instance works, and **no paid
API is required** — the application runs without one.

```bash
pytest                            # 151 tests
```

## Reader app

```bash
cd app
flutter pub get
flutter analyze                   # 0 issues
flutter test
flutter build apk --release       # build/app/outputs/flutter-apk/...
```

The app is offline-tolerant: the last successfully fetched page is kept
on disk and shown when the network is down, so a reader on a patchy
connection sees yesterday's news instead of a spinner. Screens: Home,
Explore (sections and districts), Breaking, Audio (read-aloud edition),
Saved, Profile, Shorts (vertical poster cards), story detail, search and
the tip line.

Language handling is the part most likely to silently break: Telugu
vowel signs are excluded by generic word-boundary logic, so the newsroom
and the app both use script-aware boundaries
(`backend/newsroom/nlp/telugu.py`, `app/lib/core/format.dart`), and the
app picks a script-aware line height by inspecting the rendered string
rather than trusting the language setting.

## Configuration

`.env.example` lists every variable the newsroom reads; no secret is
committed. The app points at `http://10.0.2.2:8000` by default (the
emulator's alias for the host loopback) and the base URL is editable in
Profile for readers who host their own instance.

## Licences

Third-party components are documented in
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md). No GPL/AGPL code is
linked into the app or the newsroom.
