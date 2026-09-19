import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
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

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
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
                const DashaMasthead(size: MastheadSize.splash),
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
                    color: Colors.white70,
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
