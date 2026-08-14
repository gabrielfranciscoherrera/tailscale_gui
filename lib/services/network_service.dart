import 'dart:convert';
import 'dart:io';

class NetworkInterface {
  final String name;
  final String? mac;
  final String state; // UP, DOWN, UNKNOWN
  final List<NetworkAddress> addresses;

  NetworkInterface({
    required this.name,
    this.mac,
    required this.state,
    required this.addresses,
  });

  bool get isUp => state == 'UP';
  bool get isLoopback => name == 'lo';

  /// Heurística: una interface es de Tailscale si su nombre empieza con
  /// `tailscale` o si tiene alguna IP en el rango CGNAT 100.64.0.0/10
  /// (donde Tailscale asigna IPs en userspace-networking mode).
  bool get isTailscale {
    if (name.startsWith('tailscale') || name == 'tailscale0') return true;
    for (final a in addresses) {
      if (a.isIpv4 && _isInCgnatRange(a.address)) return true;
    }
    return false;
  }

  static bool _isInCgnatRange(String ip) {
    // Tailscale usa el rango CGNAT 100.64.0.0/10 (RFC 6598)
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    if (first == null || second == null) return false;
    if (first != 100) return false;
    // 100.64/10 cubre 100.64.0.0 a 100.127.255.255
    return second >= 64 && second <= 127;
  }

  String get displayName => '🔒 $name';
}

class NetworkAddress {
  final String family; // inet, inet6
  final String address;
  final int prefix;

  NetworkAddress({required this.family, required this.address, required this.prefix});

  bool get isIpv4 => family == 'inet';
  bool get isIpv6 => family == 'inet6';

  String get display {
    return '$address/$prefix';
  }
}

class NetworkService {
  /// Lee `ip -j addr show` y devuelve todas las interfaces con sus IPs.
  Future<List<NetworkInterface>> listInterfaces() async {
    try {
      final res = await Process.run('ip', ['-j', 'addr', 'show']);
      if (res.exitCode != 0) return [];

      final json = jsonDecode(res.stdout.toString()) as List;
      return json
          .cast<Map<String, dynamic>>()
          .map(_parseInterface)
          .toList()
        ..sort((a, b) {
          // tailscale primero, luego up, luego down
          if (a.isTailscale != b.isTailscale) return a.isTailscale ? -1 : 1;
          if (a.isUp != b.isUp) return a.isUp ? -1 : 1;
          return a.name.compareTo(b.name);
        });
    } catch (_) {
      return [];
    }
  }

  NetworkInterface _parseInterface(Map<String, dynamic> data) {
    final addrs = <NetworkAddress>[];
    for (final a in (data['addr_info'] as List? ?? []).cast<Map<String, dynamic>>()) {
      addrs.add(NetworkAddress(
        family: a['family'] as String? ?? '?',
        address: a['local'] as String? ?? '',
        prefix: a['prefixlen'] as int? ?? 0,
      ));
    }
    return NetworkInterface(
      name: data['ifname'] as String? ?? '?',
      mac: data['address'] as String?,
      state: data['operstate'] as String? ?? 'UNKNOWN',
      addresses: addrs,
    );
  }
}
