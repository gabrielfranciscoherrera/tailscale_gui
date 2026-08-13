import 'dart:io';

enum AccountStatus { online, offline, starting, error }

class AccountInfo {
  final String id;
  final AccountStatus status;
  final String? ipv4;
  final String? hostname;
  final String? error;

  AccountInfo({
    required this.id,
    required this.status,
    this.ipv4,
    this.hostname,
    this.error,
  });

  String get displayStatus {
    switch (status) {
      case AccountStatus.online:
        return ipv4 ?? 'online';
      case AccountStatus.offline:
        return 'offline';
      case AccountStatus.starting:
        return 'starting...';
      case AccountStatus.error:
        return 'error: ${error ?? "unknown"}';
    }
  }
}

class TailscaleService {
  Future<AccountInfo> probe(String accountId, String socketPath) async {
    final socket = File(socketPath);
    if (!await socket.exists()) {
      return AccountInfo(id: accountId, status: AccountStatus.offline);
    }

    try {
      final result = await Process.run(
        'tailscale',
        ['--socket=$socketPath', 'status', '--json'],
      ).timeout(const Duration(seconds: 3), onTimeout: () {
        return ProcessResult(0, -1, '', 'timeout');
      });

      if (result.exitCode != 0) {
        return AccountInfo(
          id: accountId,
          status: AccountStatus.error,
          error: result.stderr.toString().trim(),
        );
      }

      final stdout = result.stdout.toString();
      final json = _parseSimple(stdout);

      final ipv4 = json['IPv4'] as String?;
      final hostname = json['Hostname'] as String?;

      return AccountInfo(
        id: accountId,
        status: AccountStatus.online,
        ipv4: ipv4,
        hostname: hostname,
      );
    } catch (e) {
      return AccountInfo(
        id: accountId,
        status: AccountStatus.error,
        error: e.toString(),
      );
    }
  }

  Map<String, dynamic> _parseSimple(String stdout) {
    final lines = stdout.split('\n');
    final result = <String, dynamic>{};
    for (final line in lines) {
      final match = RegExp(r'"([^"]+)":\s*"([^"]+)"').firstMatch(line);
      if (match != null) {
        result[match.group(1)!] = match.group(2)!;
      }
    }
    return result;
  }
}
