/// Small shared pieces the pages compose from.
library;

import 'package:flutter/material.dart';

/// An empty or refused state, shown the same way everywhere.
///
/// Used for a queue that would not load, and for a 403 -- the desk needs to
/// see that the account lacks the privilege, not a silently empty list.
class QueueMessage extends StatelessWidget {
  const QueueMessage({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: Colors.grey),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(detail!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// A flat coloured tag: status, origin, evidence level.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
    );
  }
}
