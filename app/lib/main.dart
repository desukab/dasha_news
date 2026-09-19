import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/storage.dart';
import 'state/app_state.dart';
import 'state/audio_controller.dart';
import 'state/history_recorder.dart';

/// Reads the persistent layer before the first frame, so that [AppState] is
/// initialised exactly once and no screen ever sees a half-ready store.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The front page formats its date line with an explicit en_IN locale, and
  // intl will not serve an explicit locale until its symbol data has been
  // loaded — DateFormat throws LocaleDataException otherwise. That throw lands
  // inside the list's item builder, where a release build swallows it into a
  // blank ErrorWidget, so this runs before the first frame is ever drawn.
  await initializeDateFormatting('en_IN');

  final prefs = await SharedPreferences.getInstance();
  final cacheDir = await getTemporaryDirectory();
  final storage = Storage(prefs, cacheDir);

  final appState = AppState(storage: storage);
  await appState.init();

  runApp(
    AppProviders(
      appState: appState,
      audio: AudioController(appState),
      history: HistoryRecorder(appState),
      child: const DashaApp(),
    ),
  );
}

/// Provided at the root so every descendant shares one state instance.
class AppProviders extends StatelessWidget {
  const AppProviders({
    super.key,
    required this.appState,
    required this.audio,
    required this.history,
    required this.child,
  });

  final AppState appState;
  final AudioController audio;
  final HistoryRecorder history;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<AudioController>.value(value: audio),
        Provider<HistoryRecorder>.value(value: history),
      ],
      child: child,
    );
  }
}
