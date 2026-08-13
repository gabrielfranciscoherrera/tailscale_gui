import 'dart:convert';
import 'dart:io';

import '../models/config_service.dart';

class ConfigService {
  static const _configFile = 'accounts.json';

  Future<File> _getConfigFile() async {
    final configDir = Directory('${Platform.environment['HOME']}/.config/tailscale_gui');
    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
    }
    return File('${configDir.path}/$_configFile');
  }

  Future<AccountConfig> load() async {
    final file = await _getConfigFile();
    if (!await file.exists()) {
      return AccountConfig(accounts: []);
    }
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final accounts = (json['accounts'] as List)
          .cast<Map<String, dynamic>>()
          .map(Account.fromJson)
          .toList();
      return AccountConfig(
        accounts: accounts,
        activeAccountId: json['activeAccountId'] as String?,
      );
    } catch (_) {
      return AccountConfig(accounts: []);
    }
  }

  Future<void> save(AccountConfig config) async {
    final file = await _getConfigFile();
    final data = {
      'accounts': config.accounts.map((a) => a.toJson()).toList(),
      'activeAccountId': config.activeAccountId,
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    await Process.run('chmod', ['600', file.path]);
  }
}
