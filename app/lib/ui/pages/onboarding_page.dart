import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../router.dart';
import '../widgets/masthead.dart';

/// First-run orientation: language, then district, then in.
///
/// Language is asked first and alone, because the rest of the flow is
/// meaningless if the reader cannot read it.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _step = 0;
  String? _district;

  static const int _steps = 3;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final strings = app.strings;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(strings),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _stepBody(app, strings),
              ),
            ),
            _footer(app, strings),
          ],
        ),
      ),
    );
  }

  Widget _header(AppStrings strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Row(
        children: [
          const DashaMonogram(extent: 38),
          const SizedBox(width: 12),
          Text(strings.appName,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const Spacer(),
          if (_step < _steps - 1)
            TextButton(
              onPressed: _finish,
              child: Text(strings.skip),
            ),
        ],
      ),
    );
  }

  Widget _stepBody(AppState app, AppStrings strings) {
    switch (_step) {
      case 0:
        return _LanguageStep(strings: strings, selected: app.locale);
      case 1:
        return _DistrictStep(
          strings: strings,
          districts: app.districts,
          selected: _district,
          onSelected: (value) => setState(() => _district = value),
        );
      default:
        return _SummaryStep(
          strings: strings,
          locale: app.locale,
          district: _district,
        );
    }
  }

  Widget _footer(AppState app, AppStrings strings) {
    final isLast = _step == _steps - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (int i = 0; i < _steps; i++) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= _step
                          ? SemanticColour.breaking.badge
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (i < _steps - 1) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: SemanticColour.breaking.badge,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => _next(app),
              child: Text(
                isLast ? strings.getStarted : strings.next,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _next(AppState app) async {
    if (_step < _steps - 1) {
      setState(() => _step++);
      return;
    }
    await _finish();
  }

  Future<void> _finish() async {
    final app = context.read<AppState>();
    if (_district != null && _district!.isNotEmpty) {
      await app.storage.setString(homeDistrictKey, _district!);
    }
    // Onboarding is a local fact, not something the newsroom has to confirm:
    // persist it and go. The device sync is best-effort and is never awaited
    // here, so an offline first run does not hang on a 50-second timeout
    // waiting for a POST that cannot succeed.
    await app.storage.completeOnboarding();
    if (!mounted) return;
    unawaited(app.syncDevice());
    await Navigator.pushReplacementNamed(context, DashaRouter.home);
  }
}

class _LanguageStep extends StatelessWidget {
  const _LanguageStep({required this.strings, required this.selected});

  final AppStrings strings;
  final String selected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          strings.onboardingTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
        ),
        const SizedBox(height: 12),
        Text(
          strings.onboardingBody,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.55,
              ),
        ),
        const SizedBox(height: 24),
        Text(
          strings.chooseLanguage,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        for (final code in supportedLocales)
          _LanguageTile(
            code: code,
            selected: code == selected,
            onTap: () => context.read<AppState>().setLocale(code),
          ),
      ],
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.code,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected
                ? SemanticColour.breaking.inkOf(context).withValues(alpha: 0.08)
                : Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? SemanticColour.breaking.inkOf(context)
                  : Colors.transparent,
              width: selected ? 1.6 : 0,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.nameOf(code),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _sample(code),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected
                    ? SemanticColour.breaking.inkOf(context)
                    : Theme.of(context).colorScheme.outline,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sample(String code) {
    switch (code) {
      case 'te':
        return 'తెలుగు లిపిలో వార్తలు';
      case 'ten':
        return 'Tenglish lo vaarthalu';
      default:
        return 'News in English';
    }
  }
}

class _DistrictStep extends StatelessWidget {
  const _DistrictStep({
    required this.strings,
    required this.districts,
    required this.selected,
    required this.onSelected,
  });

  final AppStrings strings;
  final List<String> districts;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          strings.chooseDistrict,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          strings.district,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _districtChip(context, strings.allDistricts, null),
            for (final name in districts)
              _districtChip(context, name, name),
          ],
        ),
      ],
    );
  }

  Widget _districtChip(BuildContext context, String label, String? value) {
    final isSelected = selected == value || (selected == null && value == null);
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(value ?? ''),
    );
  }
}

class _SummaryStep extends StatelessWidget {
  const _SummaryStep({
    required this.strings,
    required this.locale,
    required this.district,
  });

  final AppStrings strings;
  final String locale;
  final String? district;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Icon(Icons.check_circle_rounded,
              size: 48, color: SemanticColour.fact.inkOf(context)),
          const SizedBox(height: 16),
          Text(
            strings.getStarted,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          _row(context, strings.language, AppStrings.nameOf(locale)),
          if (district != null && district!.isNotEmpty)
            _row(context, strings.district, district!),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              strings.originalVsSummary,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(key,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
          const Spacer(),
          Text(value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
        ],
      ),
    );
  }
}
