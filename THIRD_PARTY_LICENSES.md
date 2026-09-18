# Third-party software in Dasha News

Everything below is used under the terms of its own licence, which is
reproduced or linked rather than paraphrased. Nothing here has been
modified. Dasha News' own code is proprietary.

Licence key: **MIT** = MIT (and Modern MIT / ISC-family, which are
functionally the same terms); **BSD-3** = BSD 3-Clause; **Apache-2.0**;
**MPL** = Mozilla Public License 2.0 (weak copyleft, applies to the
file level only); **LGPL** = GNU Lesser General Public License.

## Android application (`app/`)

| Package | Licence | Purpose |
| --- | --- | --- |
| flutter (framework, widgets, material) | BSD-3 | UI framework and Material components |
| provider | BSD-3 | Application state and dependency injection |
| http | BSD-3 | Newsroom transport |
| shared_preferences | BSD-3 | Reader preferences |
| cached_network_image | MIT | Poster image loading, caching and placeholders |
| url_launcher | BSD-3 | Open the originating outlet's report |
| intl | BSD-3 | Date and number formatting (`en_IN`) |
| connectivity_plus | BSD-3 | Online / offline detection for cache fallback |
| just_audio | MIT | Read-aloud audio playback |
| package_info_plus | BSD-3 | Version reporting in Profile |
| path_provider | BSD-3 | Cache directory location |
| share_plus | BSD-3 | System share sheet for story links |
| flutter_lints | BSD-3 | Static analysis rules |
| flutter_launcher_icons | MIT | Launcher icon generation |
| dart (core, async, convert, io, collection) | BSD-3 | Language core libraries |

Transitive dependencies are resolved by the pub solver at build time and
carry the same family of licences (BSD-3 / MIT); the resolved set is
written to `app/pubspec.lock`.

### Fonts and artwork

- The launcher glyph is drawn from **Noto Sans Telugu**, licence
  **SIL Open Font License 1.1** (`assets/images/icon*.png`, rendered to a
  raster for the launcher so no font file is redistributed).
- Material Symbols icons are redistributed under the Apache-2.0 terms of
  the Flutter framework.

## Newsroom backend (`backend/`)

| Package | Licence | Purpose |
| --- | --- | --- |
| fastapi | MIT | HTTP API |
| uvicorn | BSD-3 | ASGI server |
| pydantic | MIT | Request and response validation |
| pydantic-settings | MIT | Configuration from environment |
| sqlalchemy | MIT | Database layer |
| greenlet | MIT | Coroutine support used by SQLAlchemy |
| httpx | BSD-3 | Fetching source feeds |
| feedparser | BSD-2 | RSS / Atom parsing |
| beautifulsoup4 | MIT | HTML extraction from source pages |
| lxml | BSD-3 | XML/HTML parsing back end |
| nh3 | MIT | HTML sanitisation (MIT-ammonia successor) |
| apscheduler | MIT | Scheduled ingest and pipeline jobs |
| Pillow | MIT-CMU | Image poster processing |
| python-multipart | Apache-2.0 | Multipart form handling |
| sse-starlette | BSD-3 | Server-sent events for breaking alerts |
| pytest | MIT | Test runner |
| pytest-asyncio | Apache-2.0 | Async test support |
| pytest-cov | MIT | Coverage reporting |

### Tooling (not distributed in the app)

| Tool | Licence | Purpose |
| --- | --- | --- |
| Flutter / Dart SDK | BSD-3 | Build toolchain |
| Android SDK, Gradle, AGP | Apache-2.0 | Android build |
| OpenJDK 17 | GPL-2.0 with Classpath Exception | Java toolchain for the build |
| FFmpeg (when used) | LGPL-2.1 | Audio/segment transcoding, invoked as a separate process |

## Policy notes

- **No GPL/AGPL component is linked into the application or the
  newsroom.** The only GPL-family item in the toolchain is OpenJDK, which
  is used at build time only and is governed by the Classpath Exception;
  it does not reach the APK.
- FFmpeg, when the newsroom transcodes media, is invoked as an external
  process rather than linked, which keeps the LGPL boundary intact. It is
  an optional dependency and the basic application does not require it.
- **No paid or proprietary API is required.** Local AI providers (Ollama
  and any OpenAI-compatible endpoint) sit behind a provider abstraction
  in `backend/newsroom/ai/`, and the application ships without any
  hard-coded AI vendor.
- External news content is treated as untrusted input throughout: it is
  sanitised with `nh3`, stored as structured facts with an evidence level
  rather than as prose, and original article text is never reproduced in
  full.
