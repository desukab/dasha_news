/// The editor app's root. Two states only: holding a session, or not.
///
/// There is no anonymous view of anything -- unlike the reader app, every
/// screen here is behind the session, and the session decides the landing
/// screen. A restore that finds a dead token clears it and shows login rather
/// than retrying a credential the server has already refused.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dasha_editor/state/session_state.dart';
import 'package:dasha_editor/state/workqueue_state.dart';
import 'package:dasha_editor/ui/accounts_page.dart';
import 'package:dasha_editor/ui/login_page.dart';
import 'package:dasha_editor/ui/theme.dart';
import 'package:dasha_editor/ui/workqueue_page.dart';

class DashaEditorApp extends StatelessWidget {
  const DashaEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dasha Editor',
      debugShowCheckedModeBanner: false,
      theme: editorTheme(Brightness.light),
      darkTheme: editorTheme(Brightness.dark),
      home: const _Gate(),
    );
  }
}

class _Gate extends StatefulWidget {
  const _Gate();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionState>().restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionState>(
      builder: (context, session, _) {
        if (session.loading) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        if (!session.isAuthenticated) {
          return const LoginPage();
        }
        return MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => WorkQueueState(session.client)..refresh(),
            ),
          ],
          child: const _Shell(),
        );
      },
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _index = 0;

  static const _screens = [
    WorkQueuePage(),
    AccountsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final isAdmin = session.isAdmin;
    final screens = isAdmin ? _screens : [_screens.first];
    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.view_list_outlined),
            selectedIcon: Icon(Icons.view_list),
            label: 'Queue',
          ),
          if (isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Accounts',
            ),
        ],
      ),
    );
  }
}
