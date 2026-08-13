import 'dart:async';

import 'package:tray_manager/tray_manager.dart';

import '../models/config_service.dart' as model;
import '../services/config_service.dart';
import '../services/tailscale_service.dart';

typedef OnSettingsRequested = void Function();
typedef OnAccountSelected = void Function(model.Account account);

class TrayController with TrayListener {
  final ConfigService configService;
  final TailscaleService tailscaleService;
  final OnSettingsRequested onSettings;
  final OnAccountSelected onAccountSelected;
  final void Function() onQuit;

  Timer? _refreshTimer;

  TrayController({
    required this.configService,
    required this.tailscaleService,
    required this.onSettings,
    required this.onAccountSelected,
    required this.onQuit,
  });

  Future<void> initialize() async {
    try {
      await trayManager.setIcon('assets/tray_icon.png');
    } catch (e) {
      _log('setIcon failed', e);
    }
    try {
      await trayManager.setToolTip('Tailscale Tray');
    } catch (e) {
      _log('setToolTip failed (not implemented on Linux)', e);
    }
    trayManager.addListener(this);
    await refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
  }

  void _log(String msg, Object e) {
    // ignore: avoid_print
    print('[TrayController] $msg: $e');
  }

  Future<void> refresh() async {
    final config = await configService.load();
    final accounts = config.accounts;

    final menuItems = <MenuItem>[];

    if (accounts.isEmpty) {
      menuItems.add(MenuItem(label: 'No accounts configured', disabled: true));
    } else {
      for (final acc in accounts) {
        final info = await tailscaleService.probe(acc.id, acc.socketPath);
        final marker = config.activeAccountId == acc.id ? '● ' : '○ ';
        final statusText = info.displayStatus;
        menuItems.add(MenuItem(
          label: '$marker${acc.label}  ($statusText)',
          onClick: (_) => onAccountSelected(acc),
        ));
      }
    }

    menuItems.add(MenuItem.separator());
    menuItems.add(MenuItem(label: 'Settings...', onClick: (_) => onSettings()));
    menuItems.add(MenuItem.separator());
    menuItems.add(MenuItem(label: 'Quit', onClick: (_) => onQuit()));

    final activeLabel = accounts.isEmpty
        ? 'Tailscale: not configured'
        : 'Tailscale: ${_findActive(config)?.label ?? "—"}';
    try {
      await trayManager.setContextMenu(Menu(items: menuItems));
    } catch (e) {
      _log('setContextMenu failed', e);
    }
    try {
      await trayManager.setToolTip(activeLabel);
    } catch (e) {
      // setToolTip no implementado en Linux por tray_manager 0.5.x
    }
  }

  model.Account? _findActive(model.AccountConfig c) {
    if (c.activeAccountId == null) return null;
    for (final a in c.accounts) {
      if (a.id == c.activeAccountId) return a;
    }
    return null;
  }

  @override
  void onTrayIconMouseDown() {
    onSettings();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  void dispose() {
    _refreshTimer?.cancel();
    trayManager.removeListener(this);
  }
}
