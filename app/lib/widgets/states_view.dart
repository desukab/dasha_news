import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_strings.dart';
import '../state/app_state.dart';

/// The three states a list screen can be in, drawn the same way everywhere.
///
/// Consistency here matters more than beauty: a reader who sees the same
/// retry button in the same place on every screen learns that retrying is
/// always available.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: FrontPageSkeleton(label: label),
    );
  }
}

/// A loading state drawn in the shape of the page that is about to replace it.
///
/// A bare spinner tells the reader nothing about how long the wait is or what
/// is coming; blocks laid out as a lead story over three briefs do. The pulse
/// is a single colour tween on Flutter's own animation controller, so it costs
/// no new dependency.
class FrontPageSkeleton extends StatefulWidget {
  const FrontPageSkeleton({super.key, this.label});

  final String? label;

  @override
  State<FrontPageSkeleton> createState() => _FrontPageSkeletonState();
}

class _FrontPageSkeletonState extends State<FrontPageSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Color?> _tween;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _tween = ColorTween(
      begin: Colors.transparent,
      end: Colors.black.withValues(alpha: 0.06),
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context, context.watch<AppState>().locale);
    return AnimatedBuilder(
      animation: _tween,
      builder: (context, child) => _Shade(colour: _tween.value, child: child!),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _block(context, height: 190, radius: 12),
            const SizedBox(height: 14),
            _line(context, widthFactor: 0.94, height: 18),
            const SizedBox(height: 9),
            _line(context, widthFactor: 0.72, height: 18),
            const SizedBox(height: 12),
            _line(context, widthFactor: 0.34, height: 11),
            const SizedBox(height: 26),
            for (int i = 0; i < 3; i++) ...[
              _line(context, widthFactor: 0.3, height: 10),
              const SizedBox(height: 8),
              _line(context, widthFactor: 0.96, height: 14),
              const SizedBox(height: 7),
              _line(context, widthFactor: 0.62, height: 14),
              const SizedBox(height: 22),
            ],
            if (widget.label != null)
              Center(
                child: Text(
                  widget.label!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              )
            else
              Center(child: _SpinnerlessWait(strings: strings)),
          ],
        ),
      ),
    );
  }

  Widget _block(BuildContext context,
      {required double height, required double radius}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _line(BuildContext context,
      {required double widthFactor, required double height}) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

/// Tints the whole skeleton with the pulse, without rebuilding the blocks.
class _Shade extends StatelessWidget {
  const _Shade({required this.colour, required this.child});

  final Color? colour;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: colour ?? Colors.transparent, child: child);
  }
}

/// A quiet "loading" caption, so the skeleton is labelled without a spinner.
class _SpinnerlessWait extends StatelessWidget {
  const _SpinnerlessWait({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Text(
      strings.loading,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.4,
          ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.hint,
    this.icon = Icons.article_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? hint;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.offlineHint = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool offlineHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context, 'te');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              offlineHint ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
              size: 52,
              color: offlineHint
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              offlineHint ? strings.offline : strings.errorGeneric,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              offlineHint ? strings.offlineHint : message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(strings.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A sliver variant, for screens that mix a header with a scrolling list.
class SliverLoading extends StatelessWidget {
  const SliverLoading({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: LoadingView(label: label),
    );
  }
}

class SliverEmpty extends StatelessWidget {
  const SliverEmpty({
    super.key,
    required this.title,
    this.hint,
    this.icon = Icons.article_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? hint;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: EmptyState(
        title: title,
        hint: hint,
        icon: icon,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    );
  }
}

class SliverError extends StatelessWidget {
  const SliverError({
    super.key,
    required this.message,
    this.onRetry,
    this.offlineHint = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool offlineHint;

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: ErrorState(
        message: message,
        onRetry: onRetry,
        offlineHint: offlineHint,
      ),
    );
  }
}
