/// Build-time configuration for the Dasha News client.
///
/// The newsroom base URL is the single piece of deployment information the app
/// needs. It defaults to the emulator-to-host mapping so that a developer
/// running the FastAPI backend on this machine can read a live feed without
/// configuration, and it can be overridden at runtime from the Profile screen.
library;

/// Default newsroom origin.
///
/// `10.0.2.2` is the Android emulator's alias for the host's own loopback
/// interface, so a backend on `http://127.0.0.1:8000` is reachable as this.
/// On a physical device the value must be an address the phone can route to;
/// it is editable in Profile → Server.
const String defaultBaseUrl = 'http://10.0.2.2:8000';

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
