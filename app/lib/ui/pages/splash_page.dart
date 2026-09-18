import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../router.dart';

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
                const _Masthead(),
                const SizedBox(height: 24),
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

/// The brand lockup used on the splash and onboarding screens.
class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'డ',
              style: TextStyle(
                fontSize: 52,
                height: 1.15,
                color: AppTheme.breaking,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'దశ న్యూస్',
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'DASHA NEWS',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 3.2,
          ),
        ),
      ],
    );
  }
}
