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
  bool get isTailscale => name.startsWith('tailscale') || name == 'tailscale0';

  String get displayName {
    if (isTailscale) return '🔒 $name';
    return name;
  }
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
