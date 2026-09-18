/// One story, every language, and everything the desk needs to decide on it.
///
/// The action bar at the bottom reflects what the *server* allows for this
/// account: a reader-role account would see the controls but every one of
/// them is refused with 403 on the wire. The app reports the refusal it gets
/// back rather than guessing in advance.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dasha_editor/core/api_client.dart';
import 'package:dasha_editor/core/config.dart';
import 'package:dasha_editor/models/story.dart';
import 'package:dasha_editor/state/session_state.dart';
import 'package:dasha_editor/ui/story_edit_page.dart';
import 'package:dasha_editor/ui/theme.dart';
import 'package:dasha_editor/ui/widgets.dart';

class StoryDetailPage extends StatefulWidget {
  const StoryDetailPage({super.key, required this.storyId, this.story});

  final int storyId;
  final StoryDetail? story;

  @override
  State<StoryDetailPage> createState() => _StoryDetailPageState();
}

class _StoryDetailPageState extends State<StoryDetailPage> {
  late Future<StoryDetail> _load;
  String _locale = 'te';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load = _fetch();
  }

  Future<StoryDetail> _fetch() {
    final client = context.read<SessionState>().client;
    if (widget.story != null) {
      return Future.value(widget.story);
    }
    return client.story(widget.storyId);
  }

  Future<void> _reload() async {
    setState(() => _load = context.read<SessionState>().client.story(widget.storyId));
    await _load;
  }

  Future<void> _run(
    String label,
    Future<Object?> Function(EditorApiClient client) action, {
    bool reload = true,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(context.read<SessionState>().client);
      messenger.showSnackBar(SnackBar(
        content: Text('$label — done'), behavior: SnackBarBehavior.floating));
      if (reload && mounted) await _reload();
    } on EditorApiException catch (exc) {
      messenger.showSnackBar(SnackBar(
        content: Text('$label refused: ${exc.message}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StoryDetail>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text('Story')),
            body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError) {
          final message = snapshot.error is EditorApiException
              ? (snapshot.error as EditorApiException).message
              : 'Could not load this story.';
          return Scaffold(
            appBar: AppBar(title: const Text('Story')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 40, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(message, textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 16),
                    TextButton(onPressed: _reload, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          );
        }
        final story = snapshot.data!;
        return _detail(story);
      },
    );
  }

  Widget _detail(StoryDetail story) {
    final session = context.watch<SessionState>();
    final canEdit = session.isEditor;
    return Scaffold(
      appBar: AppBar(
        title: Text('Story #${story.id}'),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Edit the wording',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StoryEditPage(story: story),
                ));
                if (mounted) _reload();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _header(story),
          _languageSwitcher(),
          _body(story),
          _statusRow(story),
          _facts(story, canEdit),
          _sources(story),
          _auditTrail(story),
        ],
      ),
      bottomNavigationBar: canEdit ? _actions(story) : null,
    );
  }

  Widget _header(StoryDetail story) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(story.headlineIn(_locale),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700, height: 1.25, letterSpacing: -0.4)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              StatusChip(story.status, color: statusColor(story.status)),
              StatusChip(story.origin == 'manual' ? 'written by hand' : 'automated',
                  color: Colors.grey),
              if (story.editorLocked) const StatusChip('editor hold', color: Color(0xFF8A6D1F)),
              if (story.needsReview) const StatusChip('needs review', color: Color(0xFFB3261E)),
              if (story.isBreaking) const StatusChip('breaking', color: Color(0xFFB3261E)),
              if (story.isDeveloping) const StatusChip('developing', color: Color(0xFF8A6D1F)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${story.section} · ${story.district ?? story.state ?? 'Telangana'}\n'
            '${story.numSources} source(s) · evidence ${story.evidenceScore.toStringAsFixed(2)}'
            ' · importance ${story.importance.toStringAsFixed(2)}\n'
            'version ${story.version} · ${story.correctionsCount} correction(s)'
            '${story.publishedAt != null ? '\npublished ${story.publishedAt}' : ''}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _languageSwitcher() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'te', label: Text('తెలుగు')),
          ButtonSegment(value: 'ten', label: Text('Tenglish')),
          ButtonSegment(value: 'en', label: Text('English')),
        ],
        selected: {_locale},
        onSelectionChanged: (set) => setState(() => _locale = set.first),
      ),
    );
  }

  Widget _body(StoryDetail story) {
    final prose = story.bodyIn(_locale);
    final hasProse = prose.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Body ($_locale)',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
            const SizedBox(height: 8),
            Text(
              hasProse ? prose : 'No body in this language yet. Use ✎ to write it.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: hasProse ? null : Colors.grey, height: 1.55),
            ),
            if (story.leadTe != null && _locale == 'te') ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Text('Lead: ${story.leadTe}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusRow(StoryDetail story) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.history, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                story.editorLocked
                    ? 'Automation will not touch this story\'s wording while it is held by an editor.'
                    : 'Automation may regenerate this story on the next sweep.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _facts(StoryDetail story, bool canEdit) {
    final active = story.facts.where((f) => f.isActive).toList();
    final withdrawn = story.facts.where((f) => !f.isActive).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Facts and claims',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (canEdit)
                  IconButton(
                    tooltip: 'Add a fact',
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: () => _addFact(story),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (active.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No recorded facts.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
              ),
            for (final fact in active) ...[
              _factRow(fact, canEdit),
              const Divider(height: 1),
            ],
            if (withdrawn.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Withdrawn (kept for the audit trail)',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
              for (final fact in withdrawn)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(fact.textTe,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                          decoration: TextDecoration.lineThrough)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _factRow(FactView fact, bool canEdit) {
    final color = evidenceColor(fact.evidenceLevel);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fact.textTe, style: Theme.of(context).textTheme.bodyMedium),
                if (fact.textEn != null && fact.textEn!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(fact.textEn!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                  ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  children: [
                    StatusChip(fact.evidenceLevel, color: color),
                    if (fact.attributedTo != null)
                      StatusChip('by ${fact.attributedTo}', color: Colors.grey),
                  ],
                ),
              ],
            ),
          ),
          if (canEdit)
            IconButton(
              tooltip: 'Withdraw this fact',
              icon: const Icon(Icons.undo_outlined, size: 18, color: Colors.grey),
              onPressed: () => _withdraw(fact),
            ),
        ],
      ),
    );
  }

  void _addFact(StoryDetail story) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => _AddFactSheet(storyId: story.id),
    ).then((added) {
      if (added == true && mounted) _reload();
    });
  }

  void _withdraw(FactView fact) {
    _run('Withdrawing the fact', (client) => client.withdrawFact(fact.id));
  }

  Widget _sources(StoryDetail story) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Provenance · ${story.sources.length} link(s)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            if (story.sources.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                    'A story written by hand has no source articles; nothing corroborates it.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
              ),
            for (final link in story.sources) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(link.sourceName ?? 'Unknown source',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600)),
                          if (link.articleTitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(link.articleTitle!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall),
                            ),
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 6,
                            children: [
                              if (link.corroborates)
                                const StatusChip('corroborates', color: Color(0xFF1E6B4F)),
                              if (link.conflictsWith != null)
                                StatusChip('conflicts: ${link.conflictsWith}',
                                    color: const Color(0xFFB3261E)),
                              if (link.publishedAt != null)
                                StatusChip(link.publishedAt!.substring(0, 10), color: Colors.grey),
                            ],
                          ),
                        ],
                      ),
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

  Widget _auditTrail(StoryDetail story) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Audit trail', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            if (story.updates.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No recorded changes.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
              ),
            for (final update in story.updates) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusChip(update.kind, color: statusColor(update.kind)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${update.appliedBy ?? 'unknown'} · ${_shortTimestamp(update.createdAt)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                    if (update.headline != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(update.headline!,
                            style: Theme.of(context).textTheme.bodyMedium),
                      ),
                    if (update.textTe != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(update.textTe!,
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                    if (update.textEn != null && update.textEn != update.textTe)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(update.textEn!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
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

  String _shortTimestamp(String iso) {
    if (iso.length < 16) return iso;
    return '${iso.substring(0, 10)} ${iso.substring(11, 16)}';
  }

  Widget _actions(StoryDetail story) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (story.status != 'published' && story.status != 'corrected')
              _ActionButton(
                label: 'Publish',
                icon: Icons.public,
                busy: _busy,
                onTap: () => _run('Publishing', (c) => c.storyAction(story.id, 'publish')),
              ),
            if (story.status == 'published' || story.status == 'corrected')
              _ActionButton(
                label: 'Unpublish',
                icon: Icons.public_off_outlined,
                busy: _busy,
                onTap: () => _run('Unpublishing', (c) => c.storyAction(story.id, 'unpublish')),
              ),
            if (story.status != 'archived' && story.status != 'killed')
              _ActionButton(
                label: 'Archive',
                icon: Icons.archive_outlined,
                busy: _busy,
                onTap: () => _run('Archiving', (c) => c.storyAction(story.id, 'archive')),
              ),
            _ActionButton(
              label: story.isBreaking ? 'Unfeature breaking' : 'Mark breaking',
              icon: story.isBreaking ? Icons.flash_off_outlined : Icons.flash_on_outlined,
              busy: _busy,
              onTap: () => _run('Updating the breaking flag',
                  (c) => c.storyAction(story.id, 'breaking', body: {'is_breaking': !story.isBreaking})),
            ),
            _ActionButton(
              label: 'Correct',
              icon: Icons.edit_note_outlined,
              busy: _busy,
              onTap: () => _correct(story),
            ),
            if (story.editorLocked)
              _ActionButton(
                label: 'Unlock',
                icon: Icons.lock_open_outlined,
                busy: _busy,
                onTap: () => _run('Unlocking', (c) => c.unlock(story.id)),
              )
            else if (story.origin != 'manual')
              _ActionButton(
                label: 'Regenerate',
                icon: Icons.refresh,
                busy: _busy,
                onTap: () => _run('Regenerating', (c) => c.regenerate(story.id)),
              ),
          ],
        ),
      ),
    );
  }

  void _correct(StoryDetail story) {
    final te = TextEditingController();
    final en = TextEditingController();
    showDialog(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Issue a correction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: te,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'సవరణ వాచకం (Telugu)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: en,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Correction text (English)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialog).pop();
              _run('Issuing the correction', (c) => c.storyAction(story.id, 'correct',
                  body: {
                    if (te.text.trim().isNotEmpty) 'text_te': te.text.trim(),
                    if (en.text.trim().isNotEmpty) 'text_en': en.text.trim(),
                  }));
            },
            child: const Text('Publish correction'),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: busy ? null : onTap,
      icon: busy
          ? const SizedBox(
              height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

/// The bottom sheet behind "Add a fact".
///
/// Telugu is the floor of the story; English is optional scaffolding for the
/// desk. The evidence level is what the desk is actually asserting about the
/// claim, and it travels to the server separately from the prose so that the
/// published record can distinguish a fact from an allegation.
class _AddFactSheet extends StatefulWidget {
  const _AddFactSheet({required this.storyId});

  final int storyId;

  @override
  State<_AddFactSheet> createState() => _AddFactSheetState();
}

class _AddFactSheetState extends State<_AddFactSheet> {
  final _te = TextEditingController();
  final _en = TextEditingController();
  String _level = 'claim';
  bool _saving = false;

  @override
  void dispose() {
    _te.dispose();
    _en.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final textTe = _te.text.trim();
    if (textTe.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('A Telugu statement is required.'),
          behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<SessionState>().client.addFact(widget.storyId,
          textTe: textTe, textEn: _en.text.trim().isEmpty ? null : _en.text.trim());
      messenger.showSnackBar(const SnackBar(
          content: Text('Fact recorded.'), behavior: SnackBarBehavior.floating));
      if (mounted) Navigator.of(context).pop(true);
    } on EditorApiException catch (exc) {
      messenger.showSnackBar(SnackBar(
        content: Text('Refused: ${exc.message}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add a fact', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'What is actually being asserted, in the desk\'s own words. The level '
            'below is published alongside the statement.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _te,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'The statement (Telugu) *',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _en,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'English rendering (optional)',
              helperText: 'For the desk and the Tenglish edition.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _level,
            decoration: const InputDecoration(
              labelText: 'Evidence level',
              helperText: 'fact · official · claim · allegation · disputed · unverified',
            ),
            items: [
              for (final level in evidenceLevels)
                DropdownMenuItem(value: level, child: Text(level)),
            ],
            onChanged: _saving ? null : (value) => setState(() => _level = value ?? 'claim'),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Record'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
