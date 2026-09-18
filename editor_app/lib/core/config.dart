/// Build-time configuration for the Dasha Editor client.
///
/// The editor app is a private internal tool: it holds a newsroom session
/// token and nothing else. It is *never* shipped with credentials of any
/// kind -- a fresh install shows the login screen, full stop -- and the
/// newsroom address is the only piece of deployment information it keeps.
library;

/// Default newsroom origin.
///
/// `10.0.2.2` is the Android emulator's alias for the host's own loopback
/// interface, so a backend on `http://127.0.0.1:8000` is reachable as this.
/// On a physical device the value must be an address the phone can route to;
/// it is editable from Login → Server.
const String defaultBaseUrl = 'http://10.0.2.2:8000';

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
