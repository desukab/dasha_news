/// The login screen, and the only place credentials are ever typed.
///
/// The app ships with no credentials of any kind: no admin key, no seed
/// account, no fallback. A fresh install stops here until a newsroom account
/// is entered. The newsroom URL is editable from the same screen because the
/// editor app must follow the newsroom to a new server by configuration
/// alone.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dasha_editor/state/session_state.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _server = TextEditingController();
  bool _showServer = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    // Seed the field once, from the persisted address -- not on every build,
    // which would fight the user's typing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = context.read<SessionState>();
      if (mounted && _server.text.isEmpty) {
        _server.text = session.baseUrl;
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _signIn(SessionState session) async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      _localError('Email and password are both required');
      return;
    }
    FocusScope.of(context).unfocus();
    await session.login(email: email, password: password);
  }

  void _localError(String message) {
    // Shown without involving the state, because it is a client-side gap.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionState>(
      builder: (context, session, _) {
        if (session.error != null && !session.loading) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _localError(session.error!));
        }
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.edit_note, size: 48, color: Color(0xFFB3261E)),
                      const SizedBox(height: 12),
                      Text('Dasha Editor',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                      const SizedBox(height: 6),
                      Text('Newsroom sign-in. This app holds no credentials of its own.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.alternate_email, size: 20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => _signIn(session),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                size: 20),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: session.loading ? null : () => _signIn(session),
                        child: session.loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Sign in'),
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: () => setState(() => _showServer = !_showServer),
                        icon: const Icon(Icons.dns_outlined, size: 18),
                        label: Text(_showServer ? 'Hide server address' : 'Newsroom server'),
                      ),
                      if (_showServer) ...[
                        TextField(
                          controller: _server,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Newsroom base URL',
                            hintText: 'http://10.0.2.2:8000',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () async {
                              await session.setBaseUrl(_server.text);
                              _localError('Newsroom address saved');
                            },
                            child: const Text('Save address'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
