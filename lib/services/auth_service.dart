import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Maneja el PIN de root (sudo password) del usuario.
///
/// El PIN se guarda plano en `~/.config/tailscale_gui/auth.json` con
/// permisos 0600. No es ideal en seguridad pero es lo que pidió el usuario
/// para evitar el diálogo polkit cada vez.
class PinTestResult {
  final bool ok;
  final String? error;
  PinTestResult.ok() : ok = true, error = null;
  PinTestResult.fail(this.error) : ok = false;
}

class AuthService {
  static const _authFile = 'auth.json';

  Future<File> _getFile() async {
    final dir = Directory(
        '${Platform.environment['HOME']}/.config/tailscale_gui');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$_authFile');
  }

  Future<String?> loadPin() async {
    final f = await _getFile();
    if (!await f.exists()) return null;
    try {
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return data['pin'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasPin() async => (await loadPin()) != null;

  Future<void> savePin(String pin) async {
    final f = await _getFile();
    await f.writeAsString(jsonEncode({'pin': pin}));
    await Process.run('chmod', ['600', f.path]);
  }

  Future<void> clearPin() async {
    final f = await _getFile();
    if (await f.exists()) await f.delete();
  }

  /// Testea el PIN contra sudo. Devuelve [PinTestResult] con estado
  /// detallado (ok, mensaje de error, etc).
  ///
  /// Usa [Process.start] (no [Process.run]) para poder escribir el PIN en
  /// stdin. Con [Process.run] stdin se cierra antes que sudo pueda leerlo.
  Future<PinTestResult> testPinDetailed(String pin) async {
    // Primero verificar que sudo existe
    final whichRes = await Process.run('which', ['sudo']);
    if (whichRes.exitCode != 0) {
      return PinTestResult.fail(
        'sudo no está instalado. Instalalo con: sudo apt install sudo',
      );
    }

    try {
      final proc = await Process.start(
        'sudo',
        ['-S', '-k', 'true'],
        runInShell: true,
      );
      proc.stdin.writeln(pin);
      await proc.stdin.close();

      final stderr = await proc.stderr.transform(utf8.decoder).join();
      final exitCode = await proc.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          proc.kill();
          return -1;
        },
      );

      if (exitCode == 0) {
        return PinTestResult.ok();
      }

      if (stderr.contains('not in the sudoers file') ||
          stderr.contains('not allowed')) {
        return PinTestResult.fail(
          'Tu usuario no tiene permisos sudo. Agregalo al grupo sudo.',
        );
      }
      if (stderr.contains('Sorry, try again') ||
          stderr.contains('incorrect password')) {
        return PinTestResult.fail('PIN incorrecto. Verificá tu contraseña de sudo.');
      }
      if (stderr.contains('Authentication required')) {
        return PinTestResult.fail(
          'sudo requirió auth adicional (¿polkit?). Cerrá otros diálogos sudo.',
        );
      }
      if (exitCode == -1) {
        return PinTestResult.fail('sudo no respondió en 5s. Timeout.');
      }
      return PinTestResult.fail(
        'Falló (exit $exitCode). ${stderr.trim().isEmpty ? "" : stderr.trim()}',
      );
    } catch (e) {
      return PinTestResult.fail('Error ejecutando sudo: $e');
    }
  }

  /// Wrapper que devuelve solo bool (compat).
  Future<bool> testPin(String pin) async =>
      (await testPinDetailed(pin)).ok;

  /// Ejecuta un script con sudo usando el PIN guardado.
  /// Si no hay PIN guardado, devuelve -1 (la UI debe usar pkexec como fallback).
  /// Si el PIN es incorrecto, devuelve 1 y borra el PIN guardado.
  Future<ProcessResult> runPrivileged(String script) async {
    final pin = await loadPin();
    if (pin == null) {
      return ProcessResult(0, -1, '',
          'No hay PIN guardado. Configurá uno o usá pkexec.');
    }

    final proc = await Process.start(
      'sudo',
      ['-S', '-k', 'bash', '-c', script],
      runInShell: true,
    );

    // Mandar el PIN a stdin y cerrarlo
    proc.stdin.writeln(pin);
    await proc.stdin.close();

    final stdout = await proc.stdout.transform(utf8.decoder).join();
    final stderr = await proc.stderr.transform(utf8.decoder).join();
    final exitCode = await proc.exitCode;

    if (exitCode != 0 && (stderr.contains('Sorry, try again') ||
        stderr.toLowerCase().contains('incorrect password'))) {
      // PIN incorrecto: invalidar y reportar
      await clearPin();
      return ProcessResult(0, 2, stdout,
          'PIN incorrecto. Se borró de la configuración. Volvé a ingresarlo.');
    }

    return ProcessResult(proc.pid, exitCode, stdout, stderr);
  }
}
