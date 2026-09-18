# Dasha News — Autonomous Agent Release Gate

## Operating instruction

Claude/Atria is the implementation agent. It must work autonomously through the repository and continue until the release gate is satisfied.

Do not ask for permission for:
- normal architecture choices
- file creation/deletion when clearly required
- dependency installation
- refactoring
- adding tests
- fixing ordinary failures
- choosing between equivalent free implementations
- committing/pushing completed work

Ask only when necessary for:
- secret credentials
- paid services
- legal authorization not already available
- irreversible destructive actions with meaningful data loss
- an external decision that cannot reasonably be inferred

If blocked, document the blocker and continue all independent work.

## Mission phases

### Phase 1 — Audit
- inspect main branch;
- inspect all worktrees/branches if accessible;
- understand existing backend and Flutter app;
- identify dead code and duplicate systems;
- establish baseline tests/builds.

### Phase 2 — Product completion
Implement the product described in the other docs. Preserve good existing work.

### Phase 3 — Acquisition
Build broad Telangana coverage using free sources and selective Scrapling integration.

### Phase 4 — Newsroom
Verify discovery → facts → clustering → evidence → editorial → language → media → publish → update.

### Phase 5 — Mobile
Make the app fast, attractive, readable in Telugu/Tenglish/English, offline-tolerant, and retention-oriented.

### Phase 6 — Security
Attack:
- SSRF
- malicious source HTML
- prompt injection through source text
- unsafe URLs
- path traversal
- XSS
- oversized feeds/media
- duplicate floods
- rate abuse
- admin authentication
- secret leakage
- poisoned/malicious source content

### Phase 7 — Adversarial QA
Create fixtures for:
- contradictory reports
- fake quotes
- copied articles
- Telugu Unicode edge cases
- Tenglish spelling variation
- district ambiguity
- duplicate stories
- stale stories
- image provenance gaps
- source outages
- malformed RSS
- redirects/SSRF
- sudden high-volume breaking-news floods

### Phase 8 — Real validation
Where legitimately possible:
- ingest real public sources;
- run the scheduled pipeline;
- generate real story records;
- verify source attribution;
- verify media provenance;
- build the Android APK;
- test backend/app integration.

Do not bypass access controls to increase the test count.

### Phase 9 — Cost and release audit
Prove:
- no paid API is required;
- no secret is committed;
- no hidden paid dependency is required;
- core newsroom works with zero external AI credentials;
- image/media fallback works;
- persistent operation works on the Azure VM.

### Phase 10 — Final delivery
Produce:
- release APK;
- final Git SHA;
- test results;
- coverage/source registry summary;
- known limitations;
- exact Azure run commands;
- exact environment variables;
- cost audit;
- architecture summary;
- rollback instructions.

## Completion rule

Do not stop after a partial implementation because the existing code "looks good."

Continue until:
1. the app is usable;
2. the newsroom is autonomous;
3. free acquisition is real;
4. Telangana coverage is broad;
5. Telugu/Tenglish/English work;
6. images have provenance;
7. failures recover;
8. security tests pass;
9. Android release build is produced;
10. documentation matches reality.

If a requirement cannot be completed legitimately for $0, implement the best zero-cost fallback and document it. Do not add a paid service to make the checklist look complete.
