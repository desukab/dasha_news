import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import 'app_state.dart';

/// Reading-history bookkeeping. Fire and forget by design: losing a reading
/// second is inconsequential, and a failed write must never interrupt the
/// reader.
class HistoryRecorder {
  HistoryRecorder(this.appState);

  final AppState appState;
  final Map<int, Stopwatch> _watches = {};

  /// Starts the clock for a story, stopping the clock on any other story the
  /// reader had open.
  void start(int storyId) {
    for (final entry in _watches.entries) {
      if (entry.key != storyId) {
        entry.value.stop();
      }
    }
    _watches[storyId]?.stop();
    final watch = Stopwatch()..start();
    _watches[storyId] = watch;
  }

  /// Records the elapsed time, optionally marking the story as finished.
  Future<void> stop(int storyId, {bool completed = false}) async {
    final watch = _watches.remove(storyId);
    watch?.stop();
    final seconds = watch?.elapsed.inSeconds ?? 0;
    try {
      await appState.api.recordHistory(
        deviceId: appState.storage.deviceId,
        storyId: storyId,
        readSeconds: seconds,
        completed: completed,
      );
    } on ApiException {
      // Best effort.
    }
  }

  /// Forgets every open story, e.g. when the reader resets their identity.
  @nonVirtual
  void reset() {
    for (final watch in _watches.values) {
      watch.stop();
    }
    _watches.clear();
  }
}
