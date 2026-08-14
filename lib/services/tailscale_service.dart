import 'dart:convert';
import 'dart:io';

enum AccountStatus { online, offline, starting, needsLogin, error }

class AccountInfo {
  final String id;
  final AccountStatus status;
  final String? ipv4;
  final String? hostname;
  final String? backendState;
  final String? authUrl;
  final String? error;

  AccountInfo({
    required this.id,
    required this.status,
    this.ipv4,
    this.hostname,
    this.backendState,
    this.authUrl,
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
      case AccountStatus.needsLogin:
        return authUrl != null ? 'login pendiente' : 'needs login';
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
      final result = await Process.run('tailscale', [
        '--socket=$socketPath',
        'status',
        '--json',
      ]).timeout(const Duration(seconds: 3), onTimeout: () {
        return ProcessResult(0, -1, '', 'timeout');
      });

      if (result.exitCode != 0) {
        return AccountInfo(
          id: accountId,
          status: AccountStatus.error,
          error: result.stderr.toString().trim(),
        );
      }

      final Map<String, dynamic> json;
      try {
        json = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
      } catch (e) {
        return AccountInfo(
          id: accountId,
          status: AccountStatus.error,
          error: 'JSON parse error: $e',
        );
      }

      final backendState = json['BackendState'] as String?;
      final authUrl = json['AuthURL'] as String?;
      final hostname = (json['Self'] as Map?)?['HostName'] as String?;

      // Self.TailscaleIPs puede ser null o un array de strings
      String? ipv4;
      final selfIps = (json['Self'] as Map?)?['TailscaleIPs'];
      if (selfIps is List && selfIps.isNotEmpty) {
        ipv4 = selfIps.first as String?;
      }

      // Mapear BackendState → status
      switch (backendState) {
        case 'Running':
          return AccountInfo(
            id: accountId,
            status: AccountStatus.online,
            ipv4: ipv4,
            hostname: hostname,
            backendState: backendState,
          );
        case 'NeedsLogin':
          return AccountInfo(
            id: accountId,
            status: AccountStatus.needsLogin,
            authUrl: authUrl,
            backendState: backendState,
          );
        case 'Starting':
        case 'Waiting':
          return AccountInfo(
            id: accountId,
            status: AccountStatus.starting,
            backendState: backendState,
          );
        case 'NoState':
        case 'Stopped':
        case null:
        default:
          return AccountInfo(
            id: accountId,
            status: AccountStatus.offline,
            backendState: backendState,
          );
      }
    } catch (e) {
      return AccountInfo(
        id: accountId,
        status: AccountStatus.error,
        error: e.toString(),
      );
    }
  }
}
