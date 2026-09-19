import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'state/app_state.dart';
import 'ui/router.dart';

/// The widget tree above the router.
///
/// Theme and locale are driven entirely by [AppState], so a reader changing
/// language on the Profile screen re-skins the whole app without a restart.
class DashaApp extends StatelessWidget {
  const DashaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return MaterialApp(
      // The task switcher carries the paper's name in the language the reader
      // is reading in — the launcher icon beside it already does.
      title: app.strings.appName,
      onGenerateTitle: (context) =>
          context.read<AppState>().strings.appName,
      debugShowCheckedModeBanner: false,
      themeMode: app.themeModeValue,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      onGenerateRoute: DashaRouter.onGenerateRoute,
      initialRoute: DashaRouter.splash,
    );
  }
}
