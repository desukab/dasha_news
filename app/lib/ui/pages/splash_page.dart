import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../router.dart';
import '../widgets/masthead.dart';

/// The first frame: nothing to read until the state has loaded its
/// preferences, so this screen shows the masthead instead of an empty frame.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _rise;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    // The nameplate arrives already lit and settles where it sits: a fade with
    // a small rise, not a bounce, because a paper's masthead is a fixed thing.
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
    );
    _rise = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.75, curve: Curves.easeOutCubic),
    ));
    _controller.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _route() async {
    final app = context.read<AppState>();
    await app.init();
    if (!mounted) return;

    final onboardingDone = app.storage.onboardingDone;
    if (!onboardingDone) {
      await Navigator.pushReplacementNamed(context, DashaRouter.onboarding);
      return;
    }
    await Navigator.pushReplacementNamed(context, DashaRouter.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFB3261E), Color(0xFF7F1212)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _opacity,
                  child: SlideTransition(
                    position: _rise,
                    child: const DashaMasthead(size: MastheadSize.splash),
                  ),
                ),
                const SizedBox(height: 26),
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.2,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppStrings.of(context, 'te').tagline,
                  style: const TextStyle(
                    color: mastheadPaper,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
