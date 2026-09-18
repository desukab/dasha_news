/// What the automated newsroom is doing, and where it gave up.
///
/// The health numbers are the server's own counts, fetched on entry. A failed
/// article can be sent back through the desk from here; the retry runs on the
/// server, and the result -- including its errors -- is reported back rather
/// than swallowed.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dasha_editor/core/api_client.dart';
import 'package:dasha_editor/models/story.dart';
import 'package:dasha_editor/state/session_state.dart';
import 'package:dasha_editor/ui/widgets.dart';

class PipelinePage extends StatefulWidget {
  const PipelinePage({super.key, this.onRetried});

  final VoidCallback? onRetried;

  @override
  State<PipelinePage> createState() => _PipelinePageState();
}

class _PipelinePageState extends State<PipelinePage> {
  Future<PipelineFailures>? _failures;
  PipelineHealth? _health;

  @override
  void initState() {
    super.initState();
    _failures = _fetch();
  }

  Future<PipelineFailures> _fetch() {
    return context.read<SessionState>().client.pipelineFailures();
  }

  Future<void> _refresh() async {
    final client = context.read<SessionState>().client;
    final health = await client.pipelineHealth();
    final failures = await client.pipelineFailures();
    if (mounted) {
      setState(() {
        _health = health;
        _failures = Future.value(failures);
      });
    }
    widget.onRetried?.call();
  }

  Future<void> _retry(FailedArticle article) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await context.read<SessionState>().client.retryArticle(article.id);
      final errors = (result['errors'] as List?) ?? const [];
      if (errors.isEmpty) {
        messenger.showSnackBar(SnackBar(
          content: Text('Article reprocessed: ${result['status']}'),
          behavior: SnackBarBehavior.floating));
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text('Retry failed again: ${errors.join("; ")}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8)));
      }
      await _refresh();
    } on EditorApiException catch (exc) {
      messenger.showSnackBar(SnackBar(
        content: Text('Retry refused: ${exc.message}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        children: [
          if (_health != null) _healthCard(_health!),
          FutureBuilder<PipelineFailures>(
            future: _failures,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              if (snapshot.hasError) {
                final message = snapshot.error is EditorApiException
                    ? (snapshot.error as EditorApiException).message
                    : 'Could not load the pipeline state.';
                // Reading pipeline failures needs editor privileges; a
                // reader-role account is told that plainly.
                return QueueMessage(
                  icon: Icons.lock_outline,
                  title: 'Not available',
                  detail: message,
                );
              }
              final failures = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _failuresCard(failures),
                  if (failures.jobs.isNotEmpty) _jobsCard(failures.jobs),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _healthCard(PipelineHealth health) {
    final rows = [
      ('Articles the pipeline gave up on', health.articlesFailed, health.articlesFailed > 0),
      ('Jobs stuck', health.jobsStuck, health.jobsStuck > 0),
      ('Stories needing review', health.storiesNeedingReview,
          health.storiesNeedingReview > 0),
      ('Stories held by an editor', health.storiesEditorLocked, false),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Automated newsroom', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (health.needsAttention)
                  const StatusChip('needs attention', color: Color(0xFFB3261E))
                else
                  const StatusChip('healthy', color: Color(0xFF1E6B4F)),
              ],
            ),
            const SizedBox(height: 10),
            for (final (label, count, alert) in rows) ...[
              _countRow(label, count, alert),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _countRow(String label, int count, bool alert) {
    return Row(
      children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        Text('$count',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: alert ? const Color(0xFFB3261E) : null,
                fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _failuresCard(PipelineFailures failures) {
    if (failures.articles.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Color(0xFF1E6B4F), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('No article has been given up on.',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Failed articles · ${failures.total}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final article in failures.articles) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(article.title ?? article.url,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium),
                          const SizedBox(height: 4),
                          if (article.reason != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(article.reason!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFFB3261E))),
                            ),
                          Text(article.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey, fontSize: 11.5)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _retry(article),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _jobsCard(List<FailedJob> jobs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Failed jobs', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final job in jobs) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${job.kind} · ${job.attempts} attempt(s)',
                        style: Theme.of(context).textTheme.bodyMedium),
                    if (job.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(job.error!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: const Color(0xFFB3261E))),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }
}
