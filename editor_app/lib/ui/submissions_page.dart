/// The reader-tip queue: leads the desk confirms by hand.
///
/// A tip here is not a story and this page never forgets it. The list shows
/// what the submitter sent and where they say they are; the detail view shows
/// the whole text, exactly as received, with the contact details a follow-up
/// needs. Triage moves a label; the only way a tip becomes a story is the
/// desk reading it, confirming it, and writing the draft.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dasha_editor/core/api_client.dart';
import 'package:dasha_editor/core/freshness.dart';
import 'package:dasha_editor/models/story.dart';
import 'package:dasha_editor/state/session_state.dart';
import 'package:dasha_editor/state/submissions_state.dart';
import 'package:dasha_editor/ui/story_detail_page.dart';
import 'package:dasha_editor/ui/theme.dart';
import 'package:dasha_editor/ui/widgets.dart';

/// The tab the desk sees, with the count of tips nobody has looked at yet.
class SubmissionsTab extends StatelessWidget {
  const SubmissionsTab({super.key, required this.newCount});

  final int newCount;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Text('Reader tips'),
      if (newCount > 0) ...[
        const SizedBox(width: 7),
        Badge(
          backgroundColor: const Color(0xFFB3261E),
          label: Text('$newCount'),
        ),
      ],
    ]);
  }
}

class SubmissionsPage extends StatefulWidget {
  const SubmissionsPage({super.key, this.state});

  /// Test seam: a state wired to a recording transport. Production leaves it
  /// null and the page builds its own against the signed session.
  final SubmissionsState? state;

  @override
  State<SubmissionsPage> createState() => _SubmissionsPageState();
}

class _SubmissionsPageState extends State<SubmissionsPage> {
  SubmissionsState? _owned;
  bool _loaded = false;
  bool _refreshScheduled = false;

  /// The injected state wins when a test supplies one; otherwise the page
  /// builds its own against the signed session. Both are resolved here rather
  /// than in initState, because the session sits above the navigator.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.state == null) {
      _owned ??= SubmissionsState(context.read<SessionState>().client);
    }
    _loaded = true;
    if (!_refreshScheduled && _state.items.isEmpty && !_state.loading) {
      _refreshScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _state.refresh();
      });
    }
  }

  SubmissionsState get _state => widget.state ?? _owned!;

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        return Column(
          children: [
            _filterBar(),
            Expanded(child: _body()),
          ],
        );
      },
    );
  }

  Widget _filterBar() {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: SubmissionFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final filter = SubmissionFilter.values[index];
          final selected = _state.filter == filter;
          return FilterChip(
            label: Text(filter.label),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => _state.selectFilter(filter),
          );
        },
      ),
    );
  }

  Widget _body() {
    if (_state.loading && _state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_state.error != null && _state.items.isEmpty) {
      // A refused request is shown, not swapped for an empty list: an empty
      // queue and a queue the account cannot read look identical otherwise.
      return QueueMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not reach the newsroom',
        detail: _state.error!,
        action: TextButton(
            onPressed: _state.refresh, child: const Text('Retry')),
      );
    }
    if (_state.items.isEmpty) {
      return QueueMessage(
        icon: Icons.check_circle_outline,
        title: _state.filter == SubmissionFilter.newTips
            ? 'No tip is waiting on the desk.'
            : 'Nothing here with that status.',
      );
    }
    return RefreshIndicator(
      onRefresh: _state.refresh,
      child: ListView.separated(
        itemCount: _state.items.length + (_state.canLoadMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index >= _state.items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: TextButton(
                  onPressed: _state.loadMore,
                  child: const Text('Load more'),
                ),
              ),
            );
          }
          return _SubmissionRow(
            submission: _state.items[index],
            onTap: () => _open(_state.items[index]),
          );
        },
      ),
    );
  }

  Future<void> _open(SubmissionView submission) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubmissionDetailPage(
          submission: submission,
          state: _state,
        ),
      ),
    );
    if (mounted) _state.refresh();
  }
}

class _SubmissionRow extends StatelessWidget {
  const _SubmissionRow({required this.submission, required this.onTap});

  final SubmissionView submission;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    submission.headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    [
                      relativeTime(submission.createdAt),
                      if (submission.locationText != null)
                        submission.locationText,
                      if (submission.isConverted)
                        'story #${submission.storyId}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      StatusChip(submission.status,
                          color: submissionStatusColor(submission.status)),
                      // Contact details travel with a tip so the desk can
                      // follow up; they are never the tip itself.
                      if (submission.contact != null)
                        StatusChip('contact: ${submission.contact}',
                            color: const Color(0xFF6B6470)),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }
}

/// One tip, opened: the whole text as it arrived, and the desk's decisions.
class SubmissionDetailPage extends StatefulWidget {
  const SubmissionDetailPage({super.key, required this.submission, this.state});

  final SubmissionView submission;
  final SubmissionsState? state;

  @override
  State<SubmissionDetailPage> createState() => _SubmissionDetailPageState();
}

class _SubmissionDetailPageState extends State<SubmissionDetailPage> {
  late SubmissionView _submission;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _submission = widget.submission;
  }

  Future<void> _triage(String status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated =
          await context.read<SessionState>().client.triageSubmission(
                _submission.id,
                status: status,
              );
      if (mounted) setState(() => _submission = updated);
      // Keep the queue's badge honest without a full refetch.
      await widget.state?.triage(_submission.id, status: status);
    } on EditorApiException catch (exc) {
      _report(exc);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Turn a verified tip into a draft the desk then writes and publishes.
  /// Never a publish: the newsroom records the tip as one unverified claim
  /// and hands back a draft for the editor to actually report out.
  Future<void> _convert() async {
    if (_busy || _submission.isConverted) return;
    final client = context.read<SessionState>().client;
    final fields = await _showConvertDialog();
    if (fields == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final story = await client.submissionToStory(
            _submission.id,
            headlineTe: fields.headline,
            section: fields.section,
            district: fields.district,
          );
      await widget.state?.refresh();
      if (!mounted) return;
      // The tip is now a draft; the desk's next move is to write it, so that
      // is where the flow lands.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StoryDetailPage(storyId: story.id, story: story),
        ),
      );
    } on EditorApiException catch (exc) {
      _report(exc);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_ConvertFields?> _showConvertDialog() {
    final headline = TextEditingController();
    final section = TextEditingController();
    final district = TextEditingController(
      text: _submission.locationText ?? '',
    );
    return showDialog<_ConvertFields>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create a draft story'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'The tip becomes an unverified claim attributed to the '
              'submitter. The draft is yours to report out and publish.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: headline,
              decoration: const InputDecoration(
                labelText: 'Headline (optional)',
                hintText: 'Left blank, the tip’s own first line is used',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: section,
              decoration: const InputDecoration(labelText: 'Section (optional)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: district,
              decoration: const InputDecoration(labelText: 'District (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _ConvertFields(
                headline: headline.text.trim(),
                section: section.text.trim(),
                district: district.text.trim(),
              ),
            ),
            child: const Text('Create draft'),
          ),
        ],
      ),
    );
  }

  void _report(EditorApiException exc) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(exc.message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Tip #${_submission.id}')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  StatusChip(_submission.status,
                      color: submissionStatusColor(_submission.status)),
                  if (_submission.isConverted)
                    const StatusChip('converted', color: Color(0xFF1E6B4F)),
                  if (_submission.category != null)
                    StatusChip(_submission.category!,
                        color: const Color(0xFF6B6470)),
                ],
              ),
              const SizedBox(height: 10),
              // The submitter's own summary of what they saw, kept exactly as
              // written: a correction here would destroy the record the desk
              // is verifying against.
              SelectableText(
                _submission.headline,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              const _SectionLabel('What the reader sent'),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: SelectableText(
                  _submission.body,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 16),
              _detailRow('Received', relativeTime(_submission.createdAt)),
              if (_submission.locationText != null)
                _detailRow('Where', _submission.locationText!),
              if (_submission.contact != null)
                _detailRow('Contact', _submission.contact!),
              if (_submission.mediaPath != null)
                _detailRow('Media', _submission.mediaPath!),
              if (_submission.triageNote != null) ...[
                const SizedBox(height: 14),
                const _SectionLabel('Desk note'),
                const SizedBox(height: 6),
                SelectableText(
                  _submission.triageNote!,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 16),
              const _SectionLabel('Triage'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: submissionStatuses
                    .map((status) => FilterChip(
                          label: Text(status),
                          selected: _submission.status == status,
                          showCheckmark: false,
                          onSelected: _busy
                              ? null
                              : (_) {
                                  if (status != _submission.status) {
                                    _triage(status);
                                  }
                                },
                        ))
                    .toList(),
              ),
            ],
          ),
          if (_busy)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 3),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            // A tip that already became a story is not converted twice; the
            // newsroom would refuse with 409, so the control says so.
            onPressed: _busy || _submission.isConverted ? null : _convert,
            icon: const Icon(Icons.article_outlined, size: 19),
            label: Text(_submission.isConverted
                ? 'Already story #${_submission.storyId}'
                : 'Create draft story'),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.grey,
            letterSpacing: 0.6,
          ),
    );
  }
}

class _ConvertFields {
  const _ConvertFields({this.headline, this.section, this.district});

  final String? headline;
  final String? section;
  final String? district;
}
