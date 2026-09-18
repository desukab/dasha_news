import 'package:flutter/material.dart';

import '../core/app_strings.dart';

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
    final strings = AppStrings.of(context, 'te');
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeCap: StrokeCap.round),
          const SizedBox(height: 16),
          Text(
            label ?? strings.loading,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
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
