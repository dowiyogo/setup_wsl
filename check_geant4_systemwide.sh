#!/usr/bin/env bash
# check_geant4_systemwide.sh
# Busca Geant4 en ubicaciones compartidas habituales.
# No modifica ningún archivo.

set -u

SEARCH_DIRS=(
    /opt
    /usr/local
    /usr
    /cvmfs
    /software
    /apps
)

echo "===== PATH actual ====="

if command -v geant4-config >/dev/null 2>&1; then
    echo "[OK] geant4-config: $(command -v geant4-config)"
    echo "     versión: $(geant4-config --version 2>/dev/null)"
    echo "     prefix:  $(geant4-config --prefix 2>/dev/null)"
else
    echo "[NO] geant4-config no está en PATH"
fi

echo
echo "===== Paquetes RPM ====="

rpm -qa | grep -Ei '(^|-)geant4([.-]|$)' || echo "[NO] No hay RPM de Geant4"

echo
echo "===== Environment Modules ====="

if [[ -r /etc/profile.d/modules.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/modules.sh >/dev/null 2>&1 || true
fi

if type module >/dev/null 2>&1; then
    module -t avail 2>&1 |
        grep -Ei 'geant4|g4' ||
        echo "[NO] No aparecen módulos Geant4"
else
    echo "[NO] El comando module no está disponible"
fi

echo
echo "===== Búsqueda en ubicaciones compartidas ====="

existing_dirs=()
for dir in "${SEARCH_DIRS[@]}"; do
    [[ -d "$dir" ]] && existing_dirs+=("$dir")
done

if (( ${#existing_dirs[@]} == 0 )); then
    echo "[NO] Ninguna ruta de búsqueda existe"
    exit 1
fi

mapfile -t found < <(
    sudo find "${existing_dirs[@]}" -xdev -maxdepth 9 \
        \( -type f -o -type l \) \
        \( -name geant4-config \
           -o -name geant4.sh \
           -o -name Geant4Config.cmake \
           -o -name G4Version.hh \
           -o -name 'libG4run.so*' \) \
        -print 2>/dev/null |
    sort -u
)

if (( ${#found[@]} == 0 )); then
    echo "[NO] No se encontraron archivos característicos de Geant4"
    exit 1
fi

printf '%s\n' "${found[@]}"

echo
echo "===== Instalaciones verificables ====="

verified=0

for path in "${found[@]}"; do
    if [[ "$(basename "$path")" == "geant4-config" ]]; then
        version="$(sudo "$path" --version 2>/dev/null || true)"
        prefix="$(sudo "$path" --prefix 2>/dev/null || true)"

        if [[ -n "$version" ]]; then
            echo "[OK] $path"
            echo "     versión: $version"
            [[ -n "$prefix" ]] && echo "     prefix:  $prefix"
            verified=1
        fi
    fi
done

echo

if (( verified )); then
    echo "[OK] Se confirmó al menos una instalación de Geant4."
else
    echo "[AVISO] Hay archivos de Geant4, pero no se encontró un geant4-config ejecutable."
fi
