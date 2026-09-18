/// Writing a story by hand, in any or all of the three languages.
///
/// A manual story is locked from the moment it is created, because the
/// pipeline has no source articles to regenerate it from and therefore
/// nothing it is allowed to overwrite. That is a server-side rule; this form
/// only submits the words.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dasha_editor/core/api_client.dart';
import 'package:dasha_editor/core/config.dart';
import 'package:dasha_editor/models/story.dart';
import 'package:dasha_editor/state/session_state.dart';

class StoryEditPage extends StatefulWidget {
  const StoryEditPage({super.key, this.story});

  /// Present means: edit an existing story's wording. Absent means: compose.
  final StoryDetail? story;

  @override
  State<StoryEditPage> createState() => _StoryEditPageState();
}

class _StoryEditPageState extends State<StoryEditPage> {
  late final Map<String, TextEditingController> _headline;
  late final Map<String, TextEditingController> _body;
  final _section = TextEditingController(text: 'general');
  final _district = TextEditingController();
  String _status = 'draft';
  bool _saving = false;
  bool get _isEditing => widget.story != null;

  static const _labels = {
    'te': 'తెలుగు (Telugu)',
    'ten': 'Tenglish',
    'en': 'English',
  };

  @override
  void initState() {
    super.initState();
    final story = widget.story;
    _headline = {
      for (final locale in supportedLocales)
        locale: TextEditingController(text: story?.headlineIn(locale) ?? ''),
    };
    _body = {
      for (final locale in supportedLocales)
        locale: TextEditingController(text: story?.bodyIn(locale) ?? ''),
    };
    if (story != null) {
      _section.text = story.section;
      _district.text = story.district ?? '';
      _status = _isUnpublishedState(story.status) ? story.status : story.status;
    }
  }

  bool _isUnpublishedState(String status) =>
      status == 'draft' || status == 'editor_review' || status == 'approved';

  @override
  void dispose() {
    for (final controller in [..._headline.values, ..._body.values, _section, _district]) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> _fields() {
    return {
      for (final locale in supportedLocales)
        'headline_$locale': _headline[locale]!.text.trim(),
      for (final locale in supportedLocales)
        'body_$locale': _body[locale]!.text.trim(),
      'section': _section.text.trim().isEmpty ? 'general' : _section.text.trim(),
      if (_district.text.trim().isNotEmpty) 'district': _district.text.trim(),
      if (_isEditing) 'status': _status,
    };
  }

  bool get _hasAnyHeadline =>
      supportedLocales.any((l) => _headline[l]!.text.trim().isNotEmpty);

  Future<void> _save() async {
    if (!_hasAnyHeadline) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('A headline in at least one language is required.'),
          behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final client = context.read<SessionState>().client;
      if (_isEditing) {
        await client.updateStory(widget.story!.id, _fields());
        messenger.showSnackBar(const SnackBar(
            content: Text('Saved. The story is held against regeneration.'),
            behavior: SnackBarBehavior.floating));
      } else {
        await client.createStory({..._fields(), 'status': _status});
        messenger.showSnackBar(const SnackBar(
            content: Text('Story created.'), behavior: SnackBarBehavior.floating));
      }
      if (mounted) Navigator.of(context).pop(true);
    } on EditorApiException catch (exc) {
      messenger.showSnackBar(SnackBar(
        content: Text('Save refused: ${exc.message}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit story #${widget.story!.id}' : 'Write a story'),
        actions: [
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          for (final locale in supportedLocales) ...[
            _section_(
              title: _labels[locale]!,
              headline: _headline[locale]!,
              body: _body[locale]!,
            ),
            const SizedBox(height: 20),
          ],
          const Divider(),
          const SizedBox(height: 12),
          TextField(
            controller: _section,
            decoration: const InputDecoration(
              labelText: 'Section',
              helperText: 'politics, business, general …',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _district,
            decoration: const InputDecoration(
              labelText: 'District (optional)',
              helperText: 'Hyderabad, Warangal, Nizamabad …',
            ),
          ),
          const SizedBox(height: 10),
          if (!_isEditing || _isUnpublishedState(widget.story!.status))
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'draft', child: Text('draft — not yet published')),
                DropdownMenuItem(value: 'editor_review', child: Text('editor review')),
                DropdownMenuItem(value: 'approved', child: Text('approved')),
                DropdownMenuItem(value: 'published', child: Text('published')),
              ],
              onChanged: (value) => setState(() => _status = value ?? 'draft'),
            ),
          const SizedBox(height: 20),
          if (_isEditing)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline, size: 18, color: Color(0xFF8A6D1F)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Saving holds this story against automated regeneration. '
                        'Its wording is now an editorial decision.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _section_({
    required String title,
    required TextEditingController headline,
    required TextEditingController body,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: headline,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Headline'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: body,
          minLines: 4,
          maxLines: 10,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Body',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}
