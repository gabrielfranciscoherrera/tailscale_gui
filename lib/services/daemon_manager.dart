import 'dart:io';

import '../models/config_service.dart';
import 'auth_service.dart';

class StartResult {
  final bool ok;
  final String? loginUrl;
  final String? error;
  final String? stderr;
  final bool waitingForLogin;
  final bool needsPin;

  StartResult.ok({this.loginUrl, this.waitingForLogin = false})
      : ok = true,
        error = null,
        stderr = null,
        needsPin = false;

  StartResult.fail(this.error, {this.stderr, this.needsPin = false})
      : ok = false,
        loginUrl = null,
        waitingForLogin = false;
}

class DaemonManager {
  final AuthService auth;
  DaemonManager({AuthService? auth}) : auth = auth ?? AuthService();

  /// Ejecuta el script con sudo usando el PIN guardado.
  /// Devuelve el exit code y stderr para diagnóstico.
  Future<({int exitCode, String stderr})> _runPrivileged(String script) async {
    final result = await auth.runPrivileged(script);
    return (exitCode: result.exitCode, stderr: result.stderr.toString());
  }
  /// Asegura que tailscaled está corriendo. No llama a `tailscale up`.
  /// Usado por [getLoginUrl] para poder pedir la URL sin haber hecho Start.
  Future<({int exitCode, String stderr})> ensureDaemon(Account account) async {
    final stateDir = account.stateDir;
    await Directory(stateDir).create(recursive: true);
    final user = Platform.environment['USER'] ?? 'root';
    final pidFile = '$stateDir/tailscaled.pid';
    final logFile = '$stateDir/tailscaled.log';

    final cmd = '''
mkdir -p "$stateDir"
chown $user:$user "$stateDir"

# Matar instancia anterior via PID file (evita pkill que se mata a sí mismo)
if [ -f "$pidFile" ]; then
  oldpid=\$(cat "$pidFile" 2>/dev/null)
  if [ -n "\$oldpid" ] && kill -0 "\$oldpid" 2>/dev/null; then
    kill "\$oldpid" 2>/dev/null || true
    sleep 1
    kill -9 "\$oldpid" 2>/dev/null || true
  fi
  rm -f "$pidFile"
fi

# Verificar que el socket no esté colgado
[ -S "${account.socketPath}" ] && rm -f "${account.socketPath}"

# Iniciar tailscaled y guardar PID
/usr/sbin/tailscaled \\
  --state="$stateDir/tailscaled.state" \\
  --socket=${account.socketPath} \\
  --statedir="$stateDir" \\
  --tun=${account.id} \\
  --port=${account.port} \\
  > "$logFile" 2>&1 &
disown
echo \$! > "$pidFile"
chown $user:$user "$pidFile" 2>/dev/null || true

# Esperar a que el socket aparezca (max 5s)
for i in 1 2 3 4 5; do
  [ -S "${account.socketPath}" ] && exit 0
  sleep 1
done

echo "tailscaled no creó el socket en 5s. Log:" >&2
tail -20 "$logFile" >&2 2>/dev/null
exit 1
''';
    return _runPrivileged(cmd);
  }

  Future<StartResult> startAccount(Account account) async {
    if (!await auth.hasPin()) {
      return StartResult.fail(
        'No hay PIN configurado. Abrí Configuración para ingresarlo.',
        needsPin: true,
      );
    }

    final stateDir = account.stateDir;
    final r1 = await ensureDaemon(account);
    if (r1.exitCode != 0) {
      final log = await _tailLog('$stateDir/tailscaled.log', 15);
      final needsPin = r1.exitCode == 2;
      return StartResult.fail(
        needsPin
            ? 'PIN incorrecto. Volvé a ingresarlo en Configuración.'
            : 'tailscaled no quedó listo (exit ${r1.exitCode})',
        stderr: [
          if (r1.stderr.isNotEmpty) r1.stderr,
          if (log.isNotEmpty) log,
        ].join('\n'),
        needsPin: needsPin,
      );
    }

    final tailnetFlag = account.tailnet != null ? ' --operator=${account.tailnet}' : '';

    if (account.hasAuthkey) {
      final upCmd = '''
/usr/bin/tailscale --socket=${account.socketPath} up \\
  --authkey=${account.authkey} \\
  --hostname=${account.id}$tailnetFlag \\
  --accept-routes 2>&1
exit 0
''';
      final r2 = await _runPrivileged(upCmd);
      if (r2.exitCode != 0) {
        final needsPin = r2.exitCode == 2;
        return StartResult.fail(
          needsPin
              ? 'PIN incorrecto. Volvé a ingresarlo en Configuración.'
              : 'tailscale up falló (exit ${r2.exitCode})',
          stderr: r2.stderr.isEmpty ? null : r2.stderr,
          needsPin: needsPin,
        );
      }
      return StartResult.ok();
    } else {
      // Sin authkey: lanza tailscale up en background. Devuelve inmediatamente
      // con `waitingForLogin=true` para que la UI muestre un diálogo que va
      // a buscar la URL al log y a refrescarse solo.
      final r3 = await _launchUpInBackground(account, stateDir, tailnetFlag);
      if (r3.exitCode != 0) {
        return StartResult.fail(
          r3.exitCode == 2
              ? 'PIN incorrecto. Volvé a ingresarlo en Configuración.'
              : 'No se pudo lanzar tailscale up',
          stderr: r3.stderr.isEmpty ? null : r3.stderr,
          needsPin: r3.exitCode == 2,
        );
      }
      return StartResult.ok(waitingForLogin: true);
    }
  }

  /// Lanza `tailscale up` en background. La URL aparece en el log al instante.
  Future<({int exitCode, String stderr})> _launchUpInBackground(
    Account account,
    String stateDir,
    String tailnetFlag,
  ) async {
    final upScript = '''
: > "$stateDir/tailscaled.up.log"
/usr/bin/tailscale --socket=${account.socketPath} up \\
  --hostname=${account.id}$tailnetFlag \\
  --accept-routes > "$stateDir/tailscaled.up.log" 2>&1 &
echo \$! > "$stateDir/tailscaled.up.pid"
exit 0
''';
    return _runPrivileged(upScript);
  }

  /// Lee la URL de login del log si ya fue generada. Útil para polling de UI.
  Future<String?> getLoginUrl(Account account) async {
    final logFile = File('${account.stateDir}/tailscaled.up.log');
    if (!await logFile.exists()) return null;
    final content = await logFile.readAsString();
    return RegExp(r'https://login\.tailscale\.com/\S+').firstMatch(content)?.group(0);
  }

  Future<void> openInBrowser(String url) async {
    try {
      await Process.run('xdg-open', [url]);
    } catch (_) {
      // ignore: avoid_print
      print('Abri manualmente: $url');
    }
  }

  Future<int> stopAccount(Account account) async {
    final stateDir = account.stateDir;
    final pidFile = '$stateDir/tailscaled.pid';
    final cmd = '''
sock="${account.socketPath}"
[ -S "\$sock" ] && /usr/bin/tailscale --socket="\$sock" logout 2>/dev/null || true
if [ -f "$pidFile" ]; then
  pid=\$(cat "$pidFile" 2>/dev/null)
  if [ -n "\$pid" ] && kill -0 "\$pid" 2>/dev/null; then
    kill "\$pid" 2>/dev/null || true
    sleep 1
    kill -9 "\$pid" 2>/dev/null || true
  fi
  rm -f "$pidFile"
fi
[ -S "\$sock" ] && rm -f "\$sock"
exit 0
''';
    return (await _runPrivileged(cmd)).exitCode;
  }

  Future<int> stopAll(List<Account> accounts) async {
    final cmds = accounts.map((a) {
      final stateDir = a.stateDir;
      final pidFile = '$stateDir/tailscaled.pid';
      return '''
sock="${a.socketPath}"
[ -S "\$sock" ] && /usr/bin/tailscale --socket="\$sock" logout 2>/dev/null || true
if [ -f "$pidFile" ]; then
  pid=\$(cat "$pidFile" 2>/dev/null)
  if [ -n "\$pid" ] && kill -0 "\$pid" 2>/dev/null; then
    kill "\$pid" 2>/dev/null || true
  fi
  rm -f "$pidFile"
fi
[ -S "\$sock" ] && rm -f "\$sock"
''';
    }).join('\n');
    return (await _runPrivileged('$cmds\nexit 0\n')).exitCode;
  }

  Future<String> _tailLog(String path, int lines) async {
    try {
      final f = File(path);
      if (!await f.exists()) return '';
      final content = await f.readAsString();
      final all = content.split('\n');
      return all.length > lines ? all.sublist(all.length - lines).join('\n') : content;
    } catch (_) {
      return '';
    }
  }
}
