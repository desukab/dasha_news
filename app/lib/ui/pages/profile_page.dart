import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../main_shell.dart';
import '../router.dart';
import '../widgets/masthead.dart';

/// Reader preferences and app information.
///
/// Everything here is the reader's own choice and is applied immediately:
/// language and theme re-skin the app without a restart, and the server
/// address is editable so a reader can point the app at their own newsroom.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends TabPageState<ProfilePage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _version = '${info.version} (${info.buildNumber})');
  }

  @override
  void jumpToTop() {}

  void _changeLanguage(AppState app) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(app.strings.chooseLanguage,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            RadioGroup<String>(
              groupValue: app.locale,
              onChanged: (value) {
                if (value != null) {
                  app.setLocale(value);
                }
                Navigator.pop(context);
              },
              child: Column(
                children: [
                  for (final code in supportedLocales)
                    RadioListTile<String>(
                      value: code,
                      title: Text(AppStrings.nameOf(code)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _changeServer(AppState app) async {
    final controller = TextEditingController(text: app.baseUrl);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(app.strings.server),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: app.strings.serverHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(app.strings.ok),
          ),
        ],
      ),
    );
    final value = controller.text.trim();
    controller.dispose();
    if (value.isEmpty || value == app.baseUrl || !mounted) return;
    await app.setBaseUrl(value);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final strings = app.strings;
    final theme = Theme.of(context);
    return TabScaffold(
      title: app.strings.profile,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _identityCard(app, theme),
          const SizedBox(height: 16),
          _sectionHeader(strings.language),
          _languageTile(app, theme, strings),
          const SizedBox(height: 16),
          _sectionHeader(strings.theme),
          _themeRow(app, theme, strings),
          const SizedBox(height: 16),
          _sectionHeader(strings.settings),
          _switchTile(
            theme: theme,
            icon: Icons.notifications_active_rounded,
            title: strings.breakingAlerts,
            value: app.breakingAlerts,
            onChanged: app.setBreakingAlerts,
          ),
          _switchTile(
            theme: theme,
            icon: Icons.newspaper_rounded,
            title: strings.dailyDigest,
            value: app.dailyDigest,
            onChanged: app.setDailyDigest,
          ),
          _actionTile(
            theme: theme,
            icon: Icons.dns_rounded,
            title: strings.server,
            subtitle: app.baseUrl,
            onTap: () => _changeServer(app),
          ),
          _actionTile(
            theme: theme,
            icon: Icons.cached_rounded,
            title: strings.clearCache,
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              await app.clearCache();
              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(content: Text(strings.cacheCleared)),
              );
            },
          ),
          _actionTile(
            theme: theme,
            icon: Icons.campaign_outlined,
            title: strings.submitTip,
            onTap: () =>
                Navigator.pushNamed(context, DashaRouter.submitTip),
          ),
          _actionTile(
            theme: theme,
            icon: Icons.refresh_rounded,
            title: strings.retry,
            subtitle: app.online ? '' : strings.offline,
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              await app.refreshCatalogues();
              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(content: Text(strings.cacheCleared)),
              );
            },
          ),
          _actionTile(
            theme: theme,
            icon: Icons.no_accounts_outlined,
            title: strings.resetIdentity,
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              await app.resetIdentity();
              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(content: Text(strings.identityReset)),
              );
            },
          ),
          const SizedBox(height: 24),
          _sectionHeader(strings.about),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const DashaMonogram(extent: 34),
                    const SizedBox(width: 10),
                    Text(strings.appName,
                        style: theme.textTheme.titleMedium),
                    const Spacer(),
                    if (_version.isNotEmpty)
                      Text(_version,
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  strings.aboutBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.55,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  strings.originalVsSummary,
                  style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              letterSpacing: 0.9,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  Widget _identityCard(AppState app, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB3261E), Color(0xFF7F1212)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                app.strings.profile,
                style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: mastheadChip,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  app.online ? app.strings.online : app.strings.offline,
                  style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            app.storage.deviceId,
            style: theme.textTheme.bodySmall?.copyWith(
                  color: mastheadPaper,
                  fontFamily: 'monospace',
                ),
          ),
        ],
      ),
    );
  }

  Widget _languageTile(AppState app, ThemeData theme, AppStrings strings) {
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.language_rounded),
        title: Text(strings.language),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppStrings.nameOf(app.locale),
                style: theme.textTheme.titleSmall),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
        onTap: () => _changeLanguage(app),
      ),
    );
  }

  Widget _themeRow(AppState app, ThemeData theme, AppStrings strings) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final mode in const ['system', 'light', 'dark'])
            Expanded(
              child: GestureDetector(
                onTap: () => app.setThemeMode(mode),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: app.themeMode == mode
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    mode == 'system'
                        ? strings.system
                        : mode == 'light'
                            ? strings.light
                            : strings.dark,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                          color: app.themeMode == mode
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: app.themeMode == mode
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _switchTile({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile(
          secondary: Icon(icon),
          title: Text(title),
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _actionTile({
    required ThemeData theme,
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle != null && subtitle.isNotEmpty
            ? Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall)
            : null,
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      ),
    );
  }
}
