import 'package:flutter/material.dart';

import '../core/app_strings.dart';
import '../models/story.dart';
import 'pages/audio_page.dart';
import 'pages/breaking_page.dart';
import 'pages/explore_page.dart';
import 'pages/home_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/profile_page.dart';
import 'pages/saved_page.dart';
import 'pages/search_page.dart';
import 'pages/shorts_page.dart';
import 'pages/splash_page.dart';
import 'pages/story_detail_page.dart';
import 'pages/submit_tip_page.dart';

/// Named routes. Typed arguments are used rather than untyped `arguments`,
/// so a refactor that renames a field breaks at compile time, not at runtime.
class DashaRouter {
  const DashaRouter._();

  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String home = '/home';
  static const String explore = '/explore';
  static const String breaking = '/breaking';
  static const String shorts = '/shorts';
  static const String audio = '/audio';
  static const String search = '/search';
  static const String saved = '/saved';
  static const String profile = '/profile';
  static const String submitTip = '/submit-tip';

  /// Story detail takes either an id (cheaper, fetches the detail) or a full
  /// card (renders instantly while the detail loads).
  static const String story = '/story';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return _fade(const SplashPage(), settings);
      case onboarding:
        return MaterialPageRoute(builder: (_) => const OnboardingPage());
      case home:
        return _noTransition(const HomePage(), settings);
      case explore:
        return _noTransition(const ExplorePage(), settings);
      case breaking:
        return _noTransition(const BreakingPage(), settings);
      case shorts:
        return _noTransition(const ShortsPage(), settings);
      case audio:
        return _noTransition(const AudioPage(), settings);
      case search:
        return MaterialPageRoute(builder: (_) => const SearchPage());
      case saved:
        return _noTransition(const SavedPage(), settings);
      case profile:
        return _noTransition(const ProfilePage(), settings);
      case submitTip:
        return MaterialPageRoute(builder: (_) => const SubmitTipPage());
      case story:
        final args = settings.arguments;
        if (args is StoryDetailArgs) {
          return MaterialPageRoute<void>(
            builder: (_) => StoryDetailPage(args: args),
            settings: settings,
          );
        }
        return _errorRoute(settings);
      default:
        return _errorRoute(settings);
    }
  }

  /// Tab destinations, shared by the shell and by anything that needs to jump
  /// to a specific tab.
  static List<DashaTab> tabs(AppStrings strings) {
    return [
      DashaTab(route: home, icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: strings.home),
      DashaTab(route: explore, icon: Icons.explore_outlined, activeIcon: Icons.explore_rounded, label: strings.explore),
      DashaTab(route: breaking, icon: Icons.bolt_outlined, activeIcon: Icons.bolt_rounded, label: strings.breaking),
      DashaTab(route: audio, icon: Icons.headphones_outlined, activeIcon: Icons.headphones_rounded, label: strings.audio),
      DashaTab(route: saved, icon: Icons.bookmark_border_outlined, activeIcon: Icons.bookmark_rounded, label: strings.saved),
      DashaTab(route: profile, icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: strings.profile),
    ];
  }

  static Route<dynamic> _noTransition(Widget child, RouteSettings settings) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => child,
      settings: settings,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  static Route<dynamic> _fade(Widget child, RouteSettings settings) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => child,
      settings: settings,
      transitionDuration: const Duration(milliseconds: 250),
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  static Route<dynamic> _errorRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Page not found')),
      ),
      settings: settings,
    );
  }
}

class DashaTab {
  const DashaTab({
    required this.route,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final String route;
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Arguments for the story detail page.
class StoryDetailArgs {
  const StoryDetailArgs({this.id, this.story, this.slug});

  /// The story id. Required unless [story] is supplied.
  final int? id;

  /// A card already loaded in a list, shown immediately.
  final Story? story;

  /// A slug, used when opening from a deep link or a shared URL.
  final String? slug;

  int get resolvedId => story?.id ?? id ?? 0;

  bool get isValid => story != null || (id != null && id! > 0) || (slug?.isNotEmpty ?? false);
}
