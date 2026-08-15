import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:asmr_hub/l10n/app_localizations.dart';
import 'package:asmr_hub/services/audio_source_manager.dart';
import '../sources/base/base_source.dart';
import '../providers/auth_provider.dart';
import 'import_sources_page.dart';

class SourceManagementPage extends StatefulWidget {
  const SourceManagementPage({super.key});

  @override
  State<SourceManagementPage> createState() => _SourceManagementPageState();
}

class _SourceManagementPageState extends State<SourceManagementPage> {
  final AudioSourceManager _sourceManager = AudioSourceManager();
  bool _importing = false;

  Future<void> _importFromAccounts() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ImportSourcesPage()),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sourceManager
        .getSources()
        .where((s) => s.requiresAuth)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.sourceAccountManagementTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context)!.importFromAccounts,
            onPressed: _importing ? null : _importFromAccounts,
            icon: _importing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_outlined),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: sources.length,
        itemBuilder: (context, index) {
          final source = sources[index];
          if (source is! BaseAudioSource) {
            return const SizedBox.shrink(); // Skip non-base sources (like Local)
          }

          return Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                ListTile(
                  leading:
                      source.auth.isLoggedIn &&
                          source.auth.currentUser?.avatarUrl != null
                      ? CircleAvatar(
                          radius: 20,
                          backgroundImage: NetworkImage(
                            source.auth.currentUser!.avatarUrl!,
                          ),
                          onBackgroundImageError: (_, _) {},
                        )
                      : Icon(source.icon, size: 40),
                  title: Text(
                    source.sourceTypeId == 'local'
                        ? AppLocalizations.of(context)!.sourceLocal
                        : source.sourceName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    source.auth.isLoggedIn
                        ? AppLocalizations.of(context)!.loggedIn(
                            source.auth.currentUser?.name ?? 'Unknown',
                          )
                        : AppLocalizations.of(context)!.notLoggedIn,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: source.auth.isLoggedIn
                      ? IconButton(
                          icon: const Icon(Icons.logout),
                          onPressed: () async {
                            await context.read<AuthProvider>().logout(
                              source.sourceTypeId,
                            );
                            setState(() {});
                          },
                        )
                      : null,
                ),
                if (!source.auth.isLoggedIn)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if ((Platform.isAndroid || Platform.isIOS) &&
                            source.auth.supportsWebLogin)
                          ElevatedButton.icon(
                            onPressed: () async {
                              await source.auth.loginWithWeb(context);
                              if (source.auth.isLoggedIn &&
                                  source.auth.currentUser != null &&
                                  context.mounted) {
                                await context
                                    .read<AuthProvider>()
                                    .onLoginSuccess(
                                      source.sourceTypeId,
                                      source.auth.currentUser!,
                                    );
                              }
                              setState(() {});
                            },
                            icon: const Icon(Icons.web),
                            label: Text(
                              AppLocalizations.of(context)!.webLogin,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                        if (source.auth.supportsQrCodeLogin)
                          ElevatedButton.icon(
                            onPressed: () async {
                              await source.auth.loginWithQrCode(context);
                              if (source.auth.isLoggedIn &&
                                  source.auth.currentUser != null &&
                                  context.mounted) {
                                await context
                                    .read<AuthProvider>()
                                    .onLoginSuccess(
                                      source.sourceTypeId,
                                      source.auth.currentUser!,
                                    );
                              }
                              setState(() {});
                            },
                            icon: const Icon(Icons.qr_code),
                            label: Text(
                              AppLocalizations.of(context)!.scanQrCodeLogin,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                        if (source.auth.supportsCredentialsLogin)
                          ElevatedButton.icon(
                            onPressed: () =>
                                _showCredentialsLoginDialog(context, source),
                            icon: const Icon(Icons.key),
                            label: Text(
                              AppLocalizations.of(context)!.accountLogin,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                        if (source.auth.supportsCookieLogin)
                          ElevatedButton.icon(
                            onPressed: () =>
                                _showCookieLoginDialog(context, source),
                            icon: const Icon(Icons.cookie),
                            label: Text(
                              AppLocalizations.of(context)!.cookieLogin,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCredentialsLoginDialog(
    BuildContext context,
    BaseAudioSource source,
  ) {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.accountLoginTitle(source.sourceName),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.username,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.password,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty &&
                  passwordController.text.isNotEmpty) {
                String? error;
                try {
                  await source.auth.loginWithCredentials(
                    nameController.text,
                    passwordController.text,
                  );
                } catch (e) {
                  error = 'Login failed: $e';
                }
                if (error != null && context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error)));
                  return;
                }
                if (source.auth.isLoggedIn &&
                    source.auth.currentUser != null &&
                    context.mounted) {
                  await context.read<AuthProvider>().onLoginSuccess(
                    source.sourceTypeId,
                    source.auth.currentUser!,
                  );
                }
                if (context.mounted) {
                  Navigator.pop(context);
                }
                if (mounted) {
                  setState(() {});
                }
              }
            },
            child: Text(
              AppLocalizations.of(context)!.login,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }

  void _showCookieLoginDialog(BuildContext context, BaseAudioSource source) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.cookieLoginTitle(source.sourceName),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.enterCookieHint,
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                String? error;
                try {
                  await source.auth.loginWithCookie(controller.text);
                } catch (e) {
                  error = 'Login failed: $e';
                }
                if (error != null && context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error)));
                  return;
                }
                if (source.auth.isLoggedIn &&
                    source.auth.currentUser != null &&
                    context.mounted) {
                  await context.read<AuthProvider>().onLoginSuccess(
                    source.sourceTypeId,
                    source.auth.currentUser!,
                  );
                }
                if (context.mounted) {
                  Navigator.pop(context);
                }
                if (mounted) {
                  setState(() {});
                }
              }
            },
            child: Text(
              AppLocalizations.of(context)!.login,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}
