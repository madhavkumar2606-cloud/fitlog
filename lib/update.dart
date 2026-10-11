import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Version info baked in by the GitHub build (empty when run from VS Code).
class AppInfo {
  static const version = String.fromEnvironment('APP_VERSION');
  static const repo = 'madhavkumar2606-cloud/fitlog';
  static const releasesUrl = 'https://github.com/$repo/releases/latest';
  static const downloadUrl = 'https://github.com/$repo/releases/latest/download/FitLog.apk';

  static String get label => version.isEmpty ? 'development build' : 'v$version';
}

class UpdateInfo {
  final String latest;
  final bool required;
  const UpdateInfo(this.latest, this.required);
}

List<int>? _parts(String v) {
  final m = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(v);
  if (m == null) return null;
  return [int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!)];
}

/// True if [latest] (e.g. "v2.3.0") is newer than [current] (e.g. "2.2.0").
bool isNewerVersion(String latest, String current) {
  final a = _parts(latest);
  final b = _parts(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

class Updater {
  static bool _promptedThisRun = false;

  /// Asks GitHub for the newest release. Returns null if this app is up to date.
  /// Put "#required" in a release's description on GitHub to make that update mandatory.
  static Future<UpdateInfo?> check() async {
    if (AppInfo.version.isEmpty) return null;
    final res = await http
        .get(
          Uri.parse('https://api.github.com/repos/${AppInfo.repo}/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'FitLog-app'},
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (data['tag_name'] as String?) ?? '';
    if (!isNewerVersion(tag, AppInfo.version)) return null;
    final body = ((data['body'] as String?) ?? '').toLowerCase();
    return UpdateInfo(tag.startsWith('v') ? tag.substring(1) : tag, body.contains('#required'));
  }

  static Future<void> download() async {
    await launchUrl(Uri.parse(AppInfo.downloadUrl), mode: LaunchMode.externalApplication);
  }

  /// Shows an "update available" dialog at most once per app launch, and lets people
  /// snooze a normal update for a day.
  static Future<void> promptIfNeeded(BuildContext context) async {
    if (_promptedThisRun) return;
    _promptedThisRun = true;
    UpdateInfo? found;
    try {
      found = await check();
    } catch (_) {
      return; // Offline or GitHub unreachable: try again next launch.
    }
    if (found == null) return;
    final info = found;
    final prefs = await SharedPreferences.getInstance();
    final key = 'update_snoozed_${info.latest}';
    final snoozed = DateTime.tryParse(prefs.getString(key) ?? '');
    if (!info.required && snoozed != null && DateTime.now().difference(snoozed).inHours < 24) return;
    if (!context.mounted) return;
    await showUpdateDialog(context, info, onLater: () => prefs.setString(key, DateTime.now().toIso8601String()));
  }

  static Future<void> showUpdateDialog(BuildContext context, UpdateInfo info, {VoidCallback? onLater}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !info.required,
      builder: (ctx) => PopScope(
        canPop: !info.required,
        child: AlertDialog(
          icon: const Icon(Icons.system_update, size: 36),
          title: Text('Update available: v${info.latest}'),
          content: Text(
            '${info.required ? 'This update is needed to keep using FitLog. ' : ''}'
            'Download it, then tap Install. It installs over your current app and keeps all your data.\n\n'
            'You have ${AppInfo.label}.',
          ),
          actions: [
            if (!info.required)
              TextButton(
                onPressed: () {
                  onLater?.call();
                  Navigator.pop(ctx);
                },
                child: const Text('Later'),
              ),
            FilledButton(
              onPressed: () async {
                await download();
                if (!info.required && ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Download'),
            ),
          ],
        ),
      ),
    );
  }
}
