import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dasha_editor/state/session_state.dart';
import 'package:dasha_editor/ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => SessionState(),
      child: const DashaEditorApp(),
    ),
  );
}
