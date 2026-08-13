import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'services/config_service.dart';
import 'services/daemon_manager.dart';
import 'services/tailscale_service.dart';
import 'tray/tray_controller.dart';
import 'ui/settings_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final configService = ConfigService();
  final daemonManager = DaemonManager();
  final tailscaleService = TailscaleService();

  windowManager.setTitle('Tailscale Tray');
  windowManager.setSize(const Size(500, 600));
  windowManager.setMinimumSize(const Size(400, 300));

  late final TrayController tray;
  tray = TrayController(
    configService: configService,
    tailscaleService: tailscaleService,
    onSettings: () async {
      await windowManager.show();
      await windowManager.focus();
    },
    onAccountSelected: (account) async {
      final cfg = await configService.load();
      await configService.save(cfg.copyWith(activeAccountId: account.id));
      await tray.refresh();
    },
    onQuit: () async {
      tray.dispose();
      await windowManager.destroy();
      exit(0);
    },
  );
  await tray.initialize();

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SettingsWindow(
      configService: configService,
      daemonManager: daemonManager,
      tailscaleService: tailscaleService,
    ),
  ));
}
