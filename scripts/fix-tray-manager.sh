#!/usr/bin/env bash
# =============================================================================
# fix-tray-manager.sh — reaplica el patch a tray_manager en pub-cache
# =============================================================================
# Por qué: tray_manager 0.5.x usa `app_indicator_new()` que está deprecada en
# libayatana-appindicator3-0.1 desde Ubuntu 24.04+. El plugin se compila con
# `-Werror` y falla con:
#   error: 'app_indicator_new' is deprecated [-Werror,-Wdeprecated-declarations]
#
# Este script envuelve la llamada con `#pragma GCC diagnostic ignored
# "-Wdeprecated-declarations"`. Hay que correrlo cada vez que se haga
# `flutter pub upgrade` o se cambie la versión de tray_manager.
#
# USO: ./scripts/fix-tray-manager.sh
# =============================================================================

set -euo pipefail

PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
TARGET_DIR="$PUB_CACHE/hosted/pub.dev/tray_manager-0.5.3/linux"
FILE="$TARGET_DIR/tray_manager_plugin.cc"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: no se encontró $FILE"
  echo "Asegurate de haber corrido 'flutter pub get' al menos una vez."
  exit 1
fi

if grep -q 'pragma GCC diagnostic ignored "-Wdeprecated-declarations"' "$FILE"; then
  echo "✓ Patch ya aplicado en $FILE"
  exit 0
fi

echo "Aplicando patch a $FILE ..."

python3 - "$FILE" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text()
old = '''  if (!indicator) {
    indicator = app_indicator_new(id, icon_path,
                                  APP_INDICATOR_CATEGORY_APPLICATION_STATUS);

    app_indicator_set_menu(indicator, GTK_MENU(menu));'''
new = '''  if (!indicator) {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    indicator = app_indicator_new(id, icon_path,
                                  APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
#pragma GCC diagnostic pop

    app_indicator_set_menu(indicator, GTK_MENU(menu));'''
if old not in src:
    print("ERROR: no se encontró el bloque a parchear (¿versión distinta?)")
    sys.exit(1)
p.write_text(src.replace(old, new))
print("ok")
PYEOF

echo "✓ Patch aplicado. Rebuild con 'flutter build linux'."
