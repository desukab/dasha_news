import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/error_message.dart';
import '../main_shell.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';

/// The reader's tip line.
///
/// Everything submitted here lands in the newsroom as *unverified* and is
/// never auto-published; the app says so plainly, because a reader who tells
/// us something is trusting us with it.
class SubmitTipPage extends StatefulWidget {
  const SubmitTipPage({super.key});

  @override
  State<SubmitTipPage> createState() => _SubmitTipPageState();
}

class _SubmitTipPageState extends State<SubmitTipPage> {
  final _body = TextEditingController();
  final _location = TextEditingController();
  final _contact = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sending = false;

  @override
  void dispose() {
    _body.dispose();
    _location.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final app = context.read<AppState>();
    setState(() => _sending = true);
    try {
      await app.api.submitTip(
        deviceId: app.storage.deviceId,
        body: _body.text.trim(),
        locationText: _location.text.trim().isEmpty
            ? null
            : _location.text.trim(),
        contact: _contact.text.trim().isEmpty ? null : _contact.text.trim(),
      );
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(app.strings.tipSubmitted)),
      );
      Navigator.pop(context);
    } on ApiException catch (exc) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage(app.strings, exc))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final strings = app.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.submitTip,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: const [LanguageButton()],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SemanticColour.breaking.inkOf(context)
                    .withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined,
                      size: 18, color: SemanticColour.breaking.inkOf(context)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      strings.holdNote,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.5,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _field(
              controller: _body,
              label: strings.tipBody,
              hint: strings.tipBodyHint,
              maxLines: 7,
              validator: (value) {
                if (value == null || value.trim().length < 10) {
                  return strings.tipTooShort;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _field(
              controller: _location,
              label: strings.tipLocation,
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            _field(
              controller: _contact,
              label: strings.tipContact,
              maxLines: 1,
            ),
            const SizedBox(height: 24),
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
                onPressed: _sending ? null : _submit,
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        strings.submitTip,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: maxLines > 1,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
