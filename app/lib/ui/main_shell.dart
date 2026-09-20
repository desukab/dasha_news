import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_strings.dart';
import '../state/app_state.dart';
import '../state/audio_controller.dart';
import 'audio_bar.dart';
import 'pages/audio_page.dart';
import 'pages/breaking_page.dart';
import 'pages/explore_page.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'pages/saved_page.dart';
import 'router.dart';

/// The bottom-navigation shell.
///
/// Tabs are held in an [IndexedStack] so that each page's scroll position and
/// loaded pages survive a tab switch; a reader moving between Home and
/// Breaking should never see a loading spinner for something they already
/// had. Tapping the current tab again scrolls it back to the top.
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialRoute = DashaRouter.home});

  final String initialRoute;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _index;
  final List<GlobalKey<TabPageState>> _tabKeys = [];

  @override
  void initState() {
    super.initState();
    _index = _resolveIndex(widget.initialRoute);
  }

  int _resolveIndex(String route) {
    final strings = context.read<AppState>().strings;
    final tabs = DashaRouter.tabs(strings);
    final match = tabs.indexWhere((tab) => tab.route == route);
    return match < 0 ? 0 : match;
  }

  void _onDestinationSelected(int index) {
    if (index == _index) {
      _tabKeys[index].currentState?.jumpToTop();
      return;
    }
    // A selection, not a command: the softest of the three impact levels, so
    // the tab change is felt in the thumb that made it rather than heard.
    HapticFeedback.selectionClick();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final audio = context.watch<AudioController>();
    final tabs = DashaRouter.tabs(app.strings);

    final pages = <Widget>[
      HomePage(key: _tabKey(0)),
      ExplorePage(key: _tabKey(1)),
      BreakingPage(key: _tabKey(2)),
      AudioPage(key: _tabKey(3)),
      SavedPage(key: _tabKey(4)),
      ProfilePage(key: _tabKey(5)),
    ];

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(index: _index, children: pages),
          ),
          if (audio.nowPlaying != null) const AudioBar(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
        destinations: [
          for (final tab in tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.activeIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }

  GlobalKey<TabPageState> _tabKey(int index) {
    while (_tabKeys.length <= index) {
      _tabKeys.add(GlobalKey<TabPageState>());
    }
    return _tabKeys[index];
  }
}

/// Mixin the shell uses for the "tap the current tab to go to the top" gesture.
abstract class TabPageState<T extends StatefulWidget> extends State<T> {
  void jumpToTop();
}

/// A Scaffold preset for tab pages: brand-titled app bar with the language
/// switch always one tap away, on every screen.
class TabScaffold extends StatelessWidget {
  const TabScaffold({
    super.key,
    required this.title,
    this.titleWidget,
    this.actions,
    required this.body,
    this.bottom,
    this.showFab = true,
  });

  final String title;

  /// Draws in place of the text title. Used by the front page, which carries
  /// its own masthead and so shows the nameplate in the chrome.
  final Widget? titleWidget;

  final List<Widget>? actions;
  final Widget body;
  final PreferredSizeWidget? bottom;

  /// Whether the submit-a-tip button floats over the page. It does on every
  /// page but the stream: there it would sit on the share action every story
  /// screen carries, so the stream puts the tip line at its end instead.
  final bool showFab;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: titleWidget ??
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
        centerTitle: false,
        actions: actions ?? [const LanguageButton()],
        bottom: bottom,
      ),
      body: body,
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: () =>
                  Navigator.pushNamed(context, DashaRouter.submitTip),
              icon: const Icon(Icons.campaign_outlined),
              label: Text(app.strings.submitTip),
            )
          : null,
    );
  }
}

/// The language switch, available from the app bar of every tab.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return PopupMenuButton<String>(
      tooltip: app.strings.language,
      icon: const Icon(Icons.language_rounded),
      onSelected: app.setLocale,
      itemBuilder: (context) => [
        for (final code in AppStrings.pickerChoices)
          PopupMenuItem<String>(
            value: code,
            child: Row(
              children: [
                if (code == app.locale)
                  Icon(Icons.check_rounded,
                      color: Theme.of(context).colorScheme.primary, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text(AppStrings.nameOf(code)),
              ],
            ),
          ),
      ],
    );
  }
}
