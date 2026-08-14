import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'models/config_service.dart';
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

  // Auto-start de la cuenta activa al abrir la app (evita tener que hacer
  // click ▶ cada vez que reiniciás la PC). Si la sesión quedó válida en
  // state, tailscaled reanuda sin pedir login. Fire-and-forget.
  _autoStartActive(configService, daemonManager);

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SettingsWindow(
      configService: configService,
      daemonManager: daemonManager,
      tailscaleService: tailscaleService,
    ),
  ));
}

Future<void> _autoStartActive(
  ConfigService configService,
  DaemonManager daemonManager,
) async {
  try {
    final cfg = await configService.load();
    if (cfg.activeAccountId == null) return;
    final account = cfg.accounts.firstWhere(
      (a) => a.id == cfg.activeAccountId,
      orElse: () => Account(id: '', label: '', port: 0),
    );
    if (account.id.isEmpty) return;

    // Si ya está corriendo, no hacer nada
    final socket = File(account.socketPath);
    if (await socket.exists()) return;

    // Si no hay PIN configurado, no podemos escalar privilegios
    if (!await daemonManager.auth.hasPin()) return;

    // Iniciar silenciosamente. Si la sesión está en state, Tailscale reanuda.
    // Si no, generate AuthURL y el usuario verá el diálogo de login.
    await daemonManager.startAccount(account);
  } catch (_) {
    // Auto-start es best-effort, no rompemos nada si falla
  }
}
