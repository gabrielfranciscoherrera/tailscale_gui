import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import '../models/config_service.dart';
import '../services/auth_service.dart';
import '../services/config_service.dart';
import '../services/daemon_manager.dart';
import '../services/network_service.dart';
import '../services/tailscale_service.dart';
import 'auth_dialog.dart';

class SettingsWindow extends StatefulWidget {
  final ConfigService configService;
  final DaemonManager daemonManager;
  final TailscaleService tailscaleService;

  const SettingsWindow({
    super.key,
    required this.configService,
    required this.daemonManager,
    required this.tailscaleService,
  });

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  AccountConfig _config = AccountConfig(accounts: []);
  bool _loading = true;
  bool _hasPin = false;
  final Map<String, AccountInfo> _infos = {};
  List<NetworkInterface> _interfaces = [];
  bool _ifCollapsed = false;
  final _auth = AuthService();
  final _network = NetworkService();

  @override
  void initState() {
    super.initState();
    _reload();
    _checkPin();
  }

  Future<void> _checkPin() async {
    final has = await _auth.hasPin();
    if (mounted) setState(() => _hasPin = has);
  }

  Widget _buildInterfacesPanel() {
    // Mostrar interfaces con IP en 100.64/10 (Tailscale userspace-networking).
    // Si están UP perfecto; si están UNKNOWN también (userspace tun suele quedar así).
    final visible = _interfaces.where((i) => i.isTailscale);
    if (visible.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock, size: 16, color: Colors.indigo.shade700),
              const SizedBox(width: 6),
              Text('Tailscale activo',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900)),
              const Spacer(),
              IconButton(
                icon: Icon(
                    _ifCollapsed ? Icons.expand_more : Icons.expand_less,
                    size: 18),
                onPressed: () =>
                    setState(() => _ifCollapsed = !_ifCollapsed),
                tooltip: _ifCollapsed ? 'Expandir' : 'Colapsar',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (!_ifCollapsed)
            ...visible.map((iface) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 140,
                        child: Text(
                          iface.name,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.indigo.shade800,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 2,
                          children: iface.addresses
                              .where((a) => a.isIpv4 || a.isIpv6)
                              .map((a) => GestureDetector(
                                    onTap: () {
                                      Clipboard.setData(
                                          ClipboardData(text: a.address));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(
                                                  'IP copiada: ${a.address}'),
                                              duration: const Duration(
                                                  seconds: 1)));
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: a.isIpv4
                                            ? Colors.indigo.shade100
                                            : Colors.grey.shade200,
                                        borderRadius:
                                            BorderRadius.circular(4),
                                        border: Border.all(
                                            color: a.isIpv4
                                                ? Colors.indigo.shade300
                                                : Colors.grey.shade400,
                                            width: 0.5),
                                      ),
                                      child: Text(
                                        a.address,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontFamily: 'monospace',
                                          color: a.isIpv4
                                              ? Colors.indigo.shade900
                                              : Colors.grey.shade700,
                                          fontWeight: a.isIpv4
                                              ? FontWeight.w500
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Future<void> _openAuthDialog() async {
    await showDialog(
      context: context,
      builder: (_) => const AuthSettingsDialog(),
    );
    await _checkPin();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final cfg = await widget.configService.load();
    final infos = <String, AccountInfo>{};
    for (final acc in cfg.accounts) {
      infos[acc.id] = await widget.tailscaleService.probe(acc.id, acc.socketPath);
    }
    final ifaces = await _network.listInterfaces();
    setState(() {
      _config = cfg;
      _infos.clear();
      _infos.addAll(infos);
      _interfaces = ifaces;
      _loading = false;
    });
  }

  Future<void> _addAccount() async {
    final result = await showDialog<Account>(
      context: context,
      builder: (_) => const _AddAccountDialog(),
    );
    if (result != null) {
      final accounts = [..._config.accounts, result];
      final newCfg = _config.copyWith(accounts: accounts);
      await widget.configService.save(newCfg);
      _reload();
    }
  }

  Future<void> _removeAccount(Account acc) async {
    await widget.daemonManager.stopAccount(acc);
    final accounts = _config.accounts.where((a) => a.id != acc.id).toList();
    final newCfg = _config.copyWith(
      accounts: accounts,
      activeAccountId:
          _config.activeAccountId == acc.id ? null : _config.activeAccountId,
    );
    await widget.configService.save(newCfg);
    _reload();
  }

  Future<void> _setActive(Account acc) async {
    final newCfg = _config.copyWith(activeAccountId: acc.id);
    await widget.configService.save(newCfg);
    final result = await widget.daemonManager.startAccount(acc);
    _showStartResult(acc, result);
    _reload();
  }

  Future<void> _startAccount(Account acc) async {
    final result = await widget.daemonManager.startAccount(acc);
    if (result.needsPin) {
      await _openAuthDialog();
      _reload();
      return;
    }
    if (!acc.hasAuthkey && result.ok) {
      await _showLoginDialog(acc);
    } else {
      _showStartResult(acc, result);
    }
    _reload();
  }

  /// Diálogo persistente que muestra la URL de login apenas aparece en el log,
  /// con botones Copy / Open in browser. Polling hasta que la cuenta queda online.
  Future<void> _showLoginDialog(Account acc) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return _LoginDialog(account: acc, daemon: widget.daemonManager);
      },
    );
  }

  void _showStartResult(Account acc, StartResult result) {
    if (!mounted) return;
    if (!result.ok) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Error: ${acc.label}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.error ?? 'desconocido'),
                if (result.stderr != null && result.stderr!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Log de tailscaled:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      result.stderr!,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 10),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (result.needsPin)
              FilledButton.icon(
                icon: const Icon(Icons.key, size: 16),
                label: const Text('Configurar PIN'),
                onPressed: () async {
                  Navigator.pop(context);
                  await _openAuthDialog();
                  _reload();
                },
              )
            else
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
          ],
        ),
      );
    }
  }

  Future<void> _stopAccount(Account acc) async {
    await widget.daemonManager.stopAccount(acc);
    _reload();
  }

  Future<void> _stopAll() async {
    await widget.daemonManager.stopAll(_config.accounts);
    _reload();
  }

  Future<void> _getLoginUrl(Account acc) async {
    final result = await widget.daemonManager.startAccount(acc);
    if (result.needsPin) {
      await _openAuthDialog();
      _reload();
      return;
    }
    if (!result.ok) {
      _showStartResult(acc, result);
      return;
    }
    await _showLoginDialog(acc);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tailscale Tray'),
        actions: [
          IconButton(
            icon: Icon(
              _hasPin ? Icons.key : Icons.key_off,
              color: _hasPin ? Colors.green : Colors.orange,
            ),
            onPressed: _openAuthDialog,
            tooltip: _hasPin ? 'PIN configurado' : 'Configurar PIN',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addAccount,
            tooltip: 'Add account',
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined),
            onPressed: _stopAll,
            tooltip: 'Stop all',
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_hasPin)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Configurá tu PIN de sudo para iniciar/parar cuentas',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: _openAuthDialog,
                    child: const Text('Configurar'),
                  ),
                ],
              ),
            ),
          if (_interfaces.isNotEmpty) _buildInterfacesPanel(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _config.accounts.isEmpty
                    ? const Center(
                        child: Text(
                          'No accounts configured.\nClick + to add one.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                  itemCount: _config.accounts.length,
                  itemBuilder: (ctx, i) {
                    final acc = _config.accounts[i];
                    final info = _infos[acc.id];
                    final isActive = _config.activeAccountId == acc.id;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: Icon(
                          isActive ? Icons.check_circle : Icons.circle_outlined,
                          color: isActive ? Colors.green : Colors.grey,
                        ),
                        title: Row(
                          children: [
                            Text(acc.label,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            if (info?.ipv4 != null && info!.ipv4!.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  Clipboard.setData(
                                      ClipboardData(text: info.ipv4!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('IP copiada: ${info.ipv4}'),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color: Colors.green.shade300, width: 0.5),
                                  ),
                                  child: Text(
                                    info.ipv4!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: Colors.green.shade900,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (info?.status == AccountStatus.online)
                              Text(
                                'tun=${acc.id}  •  port=${acc.port}',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey.shade600),
                              )
                            else
                              Text(info?.displayStatus ?? 'unknown'),
                            if (!acc.hasAuthkey && info?.status != AccountStatus.online)
                              TextButton.icon(
                                icon: const Icon(Icons.link, size: 16),
                                label: const Text('Get login URL',
                                    style: TextStyle(fontSize: 11)),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                                  minimumSize: const Size(0, 28),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => _getLoginUrl(acc),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_arrow),
                              tooltip: 'Start',
                              onPressed: () => _startAccount(acc),
                            ),
                            IconButton(
                              icon: const Icon(Icons.stop),
                              tooltip: 'Stop',
                              onPressed: () => _stopAccount(acc),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Remove',
                              onPressed: () => _removeAccount(acc),
                            ),
                          ],
                        ),
                        onTap: () => _setActive(acc),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

class _AddAccountDialog extends StatefulWidget {
  const _AddAccountDialog();

  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _id = TextEditingController();
  final _label = TextEditingController();
  final _authkey = TextEditingController();
  final _port = TextEditingController(text: '41650');

  @override
  void dispose() {
    _id.dispose();
    _label.dispose();
    _authkey.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Tailscale account'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _id,
              decoration: const InputDecoration(labelText: 'ID (e.g. ara)'),
            ),
            TextField(
              controller: _label,
              decoration:
                  const InputDecoration(labelText: 'Label (e.g. My Account 1)'),
            ),
            TextField(
              controller: _port,
              decoration: const InputDecoration(labelText: 'Port (e.g. 41650)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _authkey,
              decoration: const InputDecoration(
                labelText: 'Auth key (opcional)',
                helperText: 'Vacío = login por navegador',
              ),
              obscureText: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_id.text.isEmpty) return;
            Navigator.pop(
              context,
              Account(
                id: _id.text.trim(),
                label: _label.text.trim().isEmpty
                    ? _id.text.trim()
                    : _label.text.trim(),
                port: int.tryParse(_port.text.trim()) ?? 41650,
                authkey: _authkey.text.trim().isEmpty
                    ? null
                    : _authkey.text.trim(),
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _LoginDialog extends StatefulWidget {
  final Account account;
  final DaemonManager daemon;

  const _LoginDialog({required this.account, required this.daemon});

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  String? _url;
  bool _checking = true;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  Future<void> _poll() async {
    // Hasta 30s esperando que aparezca la URL
    for (var i = 0; i < 60 && mounted; i++) {
      final url = await widget.daemon.getLoginUrl(widget.account);
      if (url != null) {
        setState(() {
          _url = url;
          _checking = false;
        });
        await widget.daemon.openInBrowser(url);
        break;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (mounted && _checking) {
      setState(() => _checking = false);
    }
    // Luego polling del estado de la cuenta
    while (mounted && !_connected) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      final socket = File(widget.account.socketPath);
      if (await socket.exists()) {
        final res = await Process.run('tailscale',
            ['--socket=${widget.account.socketPath}', 'status', '--json']);
        if (res.stdout.toString().contains('"BackendState":"Running"')) {
          setState(() => _connected = true);
          await Future.delayed(const Duration(milliseconds: 1500));
          if (mounted) Navigator.of(context).pop();
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Login: ${widget.account.label}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_connected)
            const Row(children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Expanded(child: Text('¡Conectado! Cerrando...')),
            ])
          else if (_checking && _url == null) ...[
            const Row(children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(child: Text('Pidiéndole URL a Tailscale...')),
            ]),
          ] else if (_url != null) ...[
            const Text('Abrimos el navegador. Si no se abrió, usá una de estas opciones:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(_url!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.hourglass_empty, size: 14, color: Colors.blueGrey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Esperando autorización en el navegador...',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ),
            ]),
          ] else
            const Text('No se pudo obtener la URL. Probá de nuevo.'),
        ],
      ),
      actions: [
        if (_url != null) ...[
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _url!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('URL copiada'), duration: Duration(seconds: 1)),
              );
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_browser, size: 16),
            label: const Text('Open'),
            onPressed: () => widget.daemon.openInBrowser(_url!),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
