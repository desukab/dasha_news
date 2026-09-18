/// Newsroom accounts. Administrator-only, and the app says so.
///
/// The list itself is refused by the server for a non-admin account, so this
/// page shows the 403 rather than a guessed-at empty list: the desk needs to
/// know the account lacks the privilege, not that nobody works here.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dasha_editor/core/api_client.dart';
import 'package:dasha_editor/models/story.dart';
import 'package:dasha_editor/state/session_state.dart';
import 'package:dasha_editor/ui/theme.dart';
import 'package:dasha_editor/ui/widgets.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  Future<List<NewsroomUser>>? _load;

  @override
  void initState() {
    super.initState();
    _load = context.read<SessionState>().client.users();
  }

  Future<void> _refresh() async {
    setState(() => _load = context.read<SessionState>().client.users());
    await _load;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<NewsroomUser>>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          if (snapshot.hasError) {
            final message = snapshot.error is EditorApiException
                ? (snapshot.error as EditorApiException).message
                : 'Could not load accounts.';
            return QueueMessage(
              icon: Icons.lock_outline,
              title: 'Administrator privileges required',
              detail: message,
              action: TextButton(onPressed: _refresh, child: const Text('Retry')),
            );
          }
          final users = snapshot.data!;
          final isAdmin = session.isAdmin;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    isAdmin
                        ? '${users.length} account(s). Demoting or suspending takes effect on the next request.'
                        : 'Your account can view this list but cannot change it.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: users.length + (isAdmin ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == users.length) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: FilledButton.icon(
                          onPressed: _invite,
                          icon: const Icon(Icons.person_add_outlined, size: 18),
                          label: const Text('Invite an editor'),
                        ),
                      );
                    }
                    return _accountRow(users[index], isAdmin);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _accountRow(NewsroomUser user, bool canManage) {
    final color = statusColor(user.isActive ? user.role : 'suspended');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.email, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      StatusChip(user.role, color: color),
                      if (!user.isActive) const StatusChip('suspended', color: Color(0xFFB3261E)),
                      if (user.id == context.read<SessionState>().user?.id)
                        const StatusChip('you', color: Colors.grey),
                    ],
                  ),
                ],
              ),
            ),
            if (canManage) _roleMenu(user),
          ],
        ),
      ),
    );
  }

  Widget _roleMenu(NewsroomUser user) {
    return PopupMenuButton<String>(
      tooltip: 'Change role or status',
      icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
      onSelected: (value) => _change(user, value),
      itemBuilder: (context) => [
        for (final role in const ['admin', 'editor', 'user'])
          PopupMenuItem(value: 'role:$role', child: Text('Set role: $role')),
        PopupMenuItem(
          value: user.isActive ? 'deactivate' : 'activate',
          child: Text(user.isActive ? 'Suspend the account' : 'Reinstate the account'),
        ),
      ],
    );
  }

  Future<void> _change(NewsroomUser user, String command) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (command.startsWith('role:')) {
        await context.read<SessionState>().client.updateUser(user.id, role: command.substring(5));
      } else {
        await context.read<SessionState>()
            .client.updateUser(user.id, isActive: command == 'activate');
      }
      messenger.showSnackBar(SnackBar(
          content: Text('${user.email} updated.'), behavior: SnackBarBehavior.floating));
      await _refresh();
    } on EditorApiException catch (exc) {
      messenger.showSnackBar(SnackBar(
        content: Text('Change refused: ${exc.message}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ));
    }
  }

  void _invite() {
    final email = TextEditingController();
    final password = TextEditingController();
    final name = TextEditingController();
    String role = 'editor';
    showDialog(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) => AlertDialog(
          title: const Text('Invite an editor'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Display name (optional)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Initial password', helperText: 'At least 12 characters.'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'editor', child: Text('editor — can write and publish')),
                  DropdownMenuItem(value: 'admin', child: Text('admin — also manages accounts')),
                  DropdownMenuItem(value: 'user', child: Text('user — read-only')),
                ],
                onChanged: (value) => setState(() => role = value ?? 'editor'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialog).pop();
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await context.read<SessionState>().client.createUser(
                        email: email.text,
                        password: password.text,
                        role: role,
                        displayName: name.text.trim().isEmpty ? null : name.text.trim(),
                      );
                  messenger.showSnackBar(SnackBar(
                      content: Text('${email.text.trim()} invited.'),
                      behavior: SnackBarBehavior.floating));
                  await _refresh();
                } on EditorApiException catch (exc) {
                  messenger.showSnackBar(SnackBar(
                    content: Text('Invite refused: ${exc.message}'),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 6),
                  ));
                }
              },
              child: const Text('Invite'),
            ),
          ],
        ),
      ),
    );
  }
}
