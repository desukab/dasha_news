library;

import 'api_client.dart';
import 'app_strings.dart';

/// The reader-facing message for a failed request.
///
/// [ApiException.message] is a developer string in English — the transport
/// layer has no language, and its wording ('the request could not be sent') is
/// not something to put in front of a Telugu reader whose newsroom happens to
/// be unreachable. This maps a failure to a localised sentence instead, so the
/// raw message stays in the crash log where it is useful and off the screen
/// where it is not.
String errorMessage(AppStrings strings, ApiException? error) {
  if (error == null) return strings.errorGeneric;
  // An unreachable or slow newsroom is by far the common case, and it is the
  // one the reader can do something about: pull to retry, or check the server
  // in Profile. A refused or malformed request is the generic message, since
  // no detail we could phrase would help.
  if (error.isOffline || error.kind == ApiFailure.network) {
    return strings.errorOffline;
  }
  return strings.errorGeneric;
}
