import 'dart:io';

class Account {
  final String id;
  final String label;
  final int port;
  final String? authkey;
  final String? tailnet;

  Account({
    required this.id,
    required this.label,
    required this.port,
    this.authkey,
    this.tailnet,
  });

  bool get hasAuthkey => authkey != null && authkey!.isNotEmpty;

  String get socketPath => '/run/tailscale/tailscaled-$id.sock';
  String get stateDir => '${Platform.environment['HOME']}/.local/share/tailscale/$id';

  Account copyWith({
    String? id,
    String? label,
    int? port,
    String? authkey,
    String? tailnet,
  }) {
    return Account(
      id: id ?? this.id,
      label: label ?? this.label,
      port: port ?? this.port,
      authkey: authkey ?? this.authkey,
      tailnet: tailnet ?? this.tailnet,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'port': port,
        if (authkey != null) 'authkey': authkey,
        if (tailnet != null) 'tailnet': tailnet,
      };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String,
        label: json['label'] as String,
        port: json['port'] as int,
        authkey: json['authkey'] as String?,
        tailnet: json['tailnet'] as String?,
      );
}

class AccountConfig {
  final List<Account> accounts;
  final String? activeAccountId;

  AccountConfig({required this.accounts, this.activeAccountId});

  AccountConfig copyWith({List<Account>? accounts, String? activeAccountId}) =>
      AccountConfig(
        accounts: accounts ?? this.accounts,
        activeAccountId: activeAccountId ?? this.activeAccountId,
      );
}
