# tailscale_tray

Monitor de múltiples cuentas Tailscale en la bandeja del sistema (Linux).

Reemplaza el alias `tail <nombre>` de bash con una GUI que muestra el estado
de cada identidad (Tailscale daemon independiente con socket y puerto propio),
permite activar/apagar cuentas y agregar nuevas (con authkey o login por
navegador).

## Stack

- Flutter 3.44 (Linux desktop)
- `tray_manager` 0.5.3 (StatusNotifierItem / D-Bus)
- `window_manager` 0.5.2
- `pkexec` para escalar privilegios (polkit gráfico)

## Estructura

```
lib/
  main.dart                   init window + tray + run app
  models/config_service.dart  Account, AccountConfig
  services/
    config_service.dart       JSON en ~/.config/tailscale-tray/ (chmod 600)
    daemon_manager.dart       pkexec start/stop por cuenta
    tailscale_service.dart    probe socket → IP/status
  tray/tray_controller.dart   icono + menú dinámico (refresh 10s)
  ui/settings_window.dart     lista + agregar + activar
assets/tray_icon.png          icono T azul 64x64
scripts/fix-tray-manager.sh   patch durable para pub-cache
```

## Compilar

```bash
flutter pub get
~/Projects/tailscale_tray/scripts/fix-tray-manager.sh   # solo la primera vez / tras upgrade
flutter build linux --release
```

## Instalar

```bash
mkdir -p ~/.local/share/tailscale-tray
cp -r build/linux/x64/release/bundle/* ~/.local/share/tailscale-tray/
ln -sf ~/.local/share/tailscale-tray/tailscale_tray ~/.local/bin/tailscale-tray
```

## Autoarranque

```bash
cp tailscale-tray.desktop ~/.config/autostart/
```

## Configuración

`~/.config/tailscale-tray/accounts.json` (chmod 600):

```json
{
  "accounts": [
    {"id": "ara",   "label": "Ara",     "port": 41641, "authkey": "tskey-..."},
    {"id": "bits",  "label": "Bits",    "port": 41642}
  ],
  "activeAccountId": "ara"
}
```

`authkey` es opcional. Si está vacío, al hacer Start se corre `tailscale up`
sin authkey, se captura la URL de `https://login.tailscale.com/...` del log y
se abre con `xdg-open`.

## Cada cuenta usa:

- `tailscaled --socket=/run/tailscale/tailscaled-<id>.sock --tun=<id> --port=<port>`
- `~/.local/share/tailscale/<id>/` para el estado
- Auth por `--authkey` o por URL de navegador

## Notas

- El paquete del sistema `tailscale` debe estar instalado (provee `tailscale`
  y `tailscaled` en `/usr/{bin,sbin}`).
- El patch en `scripts/fix-tray-manager.sh` silencia un `-Wdeprecated-declarations`
  del ayatana appindicator. Reaplicar tras `flutter pub upgrade`.
- `pkexec` levanta un diálogo polkit cada vez que iniciás/parás una cuenta.
