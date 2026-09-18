# Dasha News — $0 Software/AI Operating Constraint

## Hard rule

Dasha must not require a paid API, subscription, credit card, or usage-based AI service to run the core newsroom.

Azure hosting is treated as existing infrastructure for this project; do not add new paid cloud services without an explicit owner decision.

## Preferred stack

- Python/FastAPI backend already present
- SQLite as zero-config fallback
- PostgreSQL only when an existing/free deployment is available
- RSS/Atom/public HTML acquisition
- Scrapling where useful and permitted
- BeautifulSoup/lxml/feedparser or existing equivalents
- local deterministic/heuristic NLP where sufficient
- local Ollama only if the VM can run it acceptably
- free/open models already available locally
- espeak or another installed offline TTS path
- FFmpeg if available
- Flutter Android app
- GitHub for source control

## AI provider policy

The existing provider abstraction may remain, but paid providers must be optional.

If no external AI credentials exist:
- the system must still boot;
- ingestion must still work;
- deterministic extraction/deduplication/classification must still work;
- the app must still display news;
- publishing must not depend on a paid model.

If local AI is too expensive for the VM's CPU/RAM, gracefully fall back to deterministic methods.

## No fake capabilities

Never claim:
- a source was fetched when it was not;
- an image is licensed when its provenance is unknown;
- AI verification happened when no verifier ran;
- a model was used when it was unavailable;
- an APK was tested when it was not built/tested.

## Autonomous operations

The scheduler should:
- run continuously;
- retry failed sources;
- avoid duplicate work;
- maintain health metrics;
- keep processing after individual failures;
- expose useful logs;
- avoid requiring an interactive terminal.

The final production process must be suitable for tmux/systemd/supervisor-style persistent execution on the Azure VM.

## Resource discipline

The agent must benchmark CPU, RAM, disk, network, and processing latency. Prefer a simpler reliable pipeline over a heavyweight stack that makes the VM unstable.

## Cost audit

Before final release, produce a machine-readable and human-readable cost audit:
- required services
- optional services
- whether each is free
- whether a credit card is required
- whether a quota can silently create charges
- local fallback

The release gate fails if the core system requires a paid API.
