/// Build-time configuration for the Dasha News client.
///
/// The newsroom base URL is the single piece of deployment information the app
/// needs, and it is a *build* fact: where the backend is, and that it is not a
/// developer's laptop. It is supplied at compile time and can still be
/// overridden at runtime from the Profile screen.
library;

/// The newsroom origin this build was compiled to talk to.
///
/// Pass it on the build command line:
///
///     flutter build apk --release \
///       --dart-define=DASHA_API_BASE=https://news.dasha.example
///
/// Empty when no define was passed, which is the case [defaultBaseUrl]
/// resolves.
const String buildTimeBaseUrl = String.fromEnvironment(
  'DASHA_API_BASE',
  defaultValue: '',
);

/// True in a `--release` build. Used to decide whether the emulator-only
/// fallback is even eligible, so it can never ship to a real phone.
bool get isReleaseBuild => const bool.fromEnvironment('dart.vm.product');

/// The newsroom origin a build uses before the reader overrides it in
/// Profile → Server.
///
/// Order of preference: a value the reader already set (handled by
/// [AppState], which reads this only when nothing is stored), then a value
/// baked in at build time, then — debug builds only — the Android emulator's
/// alias for the host's own loopback, so a developer running the newsroom on
/// this machine reads a live feed with no configuration at all.
///
/// A release build with no `DASHA_API_BASE` has no backend. Rather than
/// silently point every phone at an address no device can route to, it falls
/// back to a loopback URL the reader will immediately recognise as wrong in
/// Profile → Server, which is where they fix it.
String get defaultBaseUrl {
  if (buildTimeBaseUrl.isNotEmpty) return buildTimeBaseUrl;
  return isReleaseBuild ? unresolvedBaseUrl : 'http://10.0.2.2:8000';
}

/// The placeholder used when neither a build-time value nor a stored reader
/// preference exists and the build is a release. Prefixed so it is obvious in
/// the Server field that it is not a real address.
const String unresolvedBaseUrl = 'http://localhost:8000';

/// True when [value] is the build's unresolved placeholder rather than a real
/// newsroom address.
bool isUnresolved(String value) => value.trim() == unresolvedBaseUrl;

/// Key under which the overridden base URL is persisted.
const String baseUrlKey = 'dasha.base_url';

/// Keys for reader preferences.
const String localeKey = 'dasha.locale';
const String themeModeKey = 'dasha.theme_mode';
const String breakingAlertsKey = 'dasha.breaking_alerts';
const String dailyDigestKey = 'dasha.daily_digest';
const String deviceIdKey = 'dasha.device_id';
const String onboardingDoneKey = 'dasha.onboarding_done';
const String homeSectionKey = 'dasha.home_section';
const String homeDistrictKey = 'dasha.home_district';

/// The three publication languages, in the order the app offers them.
const List<String> supportedLocales = ['te', 'ten', 'en'];

/// Request timeouts. The newsroom is slow on a cold start (it may be sweeping
/// feeds), so read timeout is generous.
const Duration connectTimeout = Duration(seconds: 10);
const Duration readTimeout = Duration(seconds: 30);

/// How many stories are requested per page.
const int defaultPageSize = 20;
