library;

/// The newsroom emits absolute media URLs from its own `public_base_url`,
/// which is `http://localhost:8000` on the machine it runs on. A phone reading
/// that URL tries to play a file from itself, so nothing is heard.
///
/// The fix is not to correct the newsroom's guess about where it is — a quick
/// tunnel's hostname changes on every restart, so no value is stable — but to
/// treat a loopback origin as the newsroom naming *its own* machine rather
/// than the reader's. Media is served from the same origin as the API, and the
/// app already knows that origin from the build or from Profile → Server.
const Set<String> _loopbackHosts = {
  'localhost',
  '127.0.0.1',
  '[::1]',
  '::1',
  // The Android emulator's alias for the developer's host loopback.
  '10.0.2.2',
};

/// True when [uri] names the machine it was written on rather than the reader's.
bool isLoopback(Uri uri) => _loopbackHosts.contains(uri.host.toLowerCase());

/// [raw] with its origin replaced by [baseUrl]'s when it names a loopback host.
///
/// Relative URLs — the other shape a misconfigured `public_base_url` produces —
/// are resolved against [baseUrl] as well. A URL that is already public is
/// returned untouched, so a CDN or a source site's own image host is honoured.
String? resolveMediaUrl(String? raw, String baseUrl) {
  if (raw == null || raw.isEmpty) return null;
  final parsed = Uri.tryParse(raw);
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
    // Not an absolute URL: treat it as a path on the newsroom.
    final origin = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return raw.startsWith('/') ? '$origin$raw' : '$origin/$raw';
  }
  if (!isLoopback(parsed)) return raw;
  final origin = Uri.tryParse(baseUrl);
  if (origin == null || !origin.hasScheme || origin.host.isEmpty) return raw;
  // An empty query still serialises a trailing '?', so it is only carried
  // when there is something to carry.
  return origin
      .replace(
        path: parsed.path,
        queryParameters:
            parsed.queryParameters.isEmpty ? null : parsed.queryParameters,
      )
      .toString();
}
