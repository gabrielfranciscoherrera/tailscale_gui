import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class AuthSettingsDialog extends StatefulWidget {
  const AuthSettingsDialog({super.key});

  @override
  State<AuthSettingsDialog> createState() => _AuthSettingsDialogState();
}

class _AuthSettingsDialogState extends State<AuthSettingsDialog> {
  final _auth = AuthService();
  final _pinController = TextEditingController();
  bool _obscure = true;
  bool _hasPin = false;
  bool _testing = false;
  String? _status;
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final has = await _auth.hasPin();
    setState(() {
      _hasPin = has;
      if (!has) {
        _pinController.clear();
        _status = null;
      }
    });
  }

  Future<void> _testAndSave() async {
    final pin = _pinController.text;
    if (pin.isEmpty) {
      setState(() {
        _status = 'Ingresá un PIN';
        _statusOk = false;
      });
      return;
    }
    setState(() {
      _testing = true;
      _status = 'Probando con sudo...';
      _statusOk = false;
    });

    final result = await _auth.testPinDetailed(pin);
    if (result.ok) {
      await _auth.savePin(pin);
      setState(() {
        _hasPin = true;
        _testing = false;
        _status = '✓ PIN guardado y validado correctamente';
        _statusOk = true;
        _pinController.clear();
      });
    } else {
      setState(() {
        _testing = false;
        _status = '✗ ${result.error ?? "Falló"}';
        _statusOk = false;
      });
    }
  }

  Future<void> _clear() async {
    await _auth.clearPin();
    setState(() {
      _hasPin = false;
      _status = 'PIN borrado';
      _statusOk = true;
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Autenticación'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                _hasPin ? Icons.check_circle : Icons.warning_amber,
                color: _hasPin ? Colors.green : Colors.orange,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _hasPin
                      ? 'PIN configurado. Las acciones privilegiadas usan este PIN en lugar del diálogo polkit.'
                      : 'No hay PIN configurado. La app no puede iniciar/paroar tailscaled hasta que ingreses uno.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: _hasPin ? 'Nuevo PIN (sudo)' : 'Tu PIN de sudo',
                helperText: 'Es tu contraseña de root/sudo. Se guarda en ~/.config/tailscale-tray/auth.json con permisos 0600.',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _testAndSave(),
            ),
            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(
                _status!,
                style: TextStyle(
                  fontSize: 12,
                  color: _statusOk ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_hasPin)
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text('Borrar PIN', style: TextStyle(color: Colors.red)),
            onPressed: _clear,
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        FilledButton.icon(
          icon: _testing
              ? const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save, size: 16),
          label: const Text('Guardar y probar'),
          onPressed: _testing ? null : _testAndSave,
        ),
      ],
    );
  }
}
