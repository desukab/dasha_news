/// Build-time configuration for the Dasha Editor client.
///
/// The editor app is a private internal tool: it holds a newsroom session
/// token and nothing else. It is *never* shipped with credentials of any
/// kind -- a fresh install shows the login screen, full stop -- and the
/// newsroom address is the only piece of deployment information it keeps.
library;

/// The newsroom origin this build was compiled to talk to.
///
/// Supplied at build time, because a release must not point at a developer's
/// laptop:
///
///     flutter build apk --release \
///       --dart-define=DASHA_API_BASE=https://newsroom.example
///
/// A reader of the override below can still type their own address from
/// Login → Server, and that wins.
const String buildTimeBaseUrl = String.fromEnvironment(
  'DASHA_API_BASE',
  defaultValue: '',
);

/// True in a `--release` build, so the emulator alias can be ruled out of a
/// build that ships to a real phone.
bool get isReleaseBuild => const bool.fromEnvironment('dart.vm.product');

/// Default newsroom origin.
///
/// With a build-time value, that value is it. Without one, only a debug build
/// may use `10.0.2.2` — the Android emulator's alias for the host's own
/// loopback, which reaches a newsroom on the developer's own machine and
/// nothing else. A release with no define has no backend, so it falls back to
/// an explicit placeholder that is visibly wrong in Login → Server rather
/// than an address no phone can route to.
String get defaultBaseUrl {
  if (buildTimeBaseUrl.isNotEmpty) return buildTimeBaseUrl;
  return isReleaseBuild ? unresolvedBaseUrl : 'http://10.0.2.2:8000';
}

/// The placeholder used when nothing is configured and the build is a
/// release. Prefixed so the desk sees at a glance that it is not a real
/// newsroom address.
const String unresolvedBaseUrl = 'http://localhost:8000';

/// True when [value] is the unresolved placeholder.
bool isUnresolved(String value) => value.trim() == unresolvedBaseUrl;

/// Key under which the overridden base URL is persisted.
const String baseUrlKey = 'dasha_editor.base_url';

/// Key under which the session token is persisted.
///
/// The token is a signed, expiry-bound credential the newsroom issued; it is
/// stored here only so a re-opened app does not force a re-login, and it is
/// cleared on logout. It never becomes part of the app binary.
const String tokenKey = 'dasha_editor.token';

/// Request timeouts. A sweep over a slow feed can take a while, and the
/// pipeline retry endpoint processes an article synchronously.
const Duration connectTimeout = Duration(seconds: 10);
const Duration readTimeout = Duration(seconds: 45);

/// Page size for the workqueue.
const int defaultPageSize = 25;

/// The three publication languages, in the order the desk writes them.
const List<String> supportedLocales = ['te', 'ten', 'en'];

/// Editorial statuses the desk can filter the queue by.
const List<String> editorialStatuses = [
  'draft',
  'editor_review',
  'approved',
  'published',
  'corrected',
  'unpublished',
  'archived',
  'held',
  'auto_published',
  'developing',
  'breaking',
  'killed',
];

/// Evidence labels a fact can carry, most certain first.
const List<String> evidenceLevels = [
  'fact',
  'official',
  'claim',
  'allegation',
  'disputed',
  'unverified',
];
