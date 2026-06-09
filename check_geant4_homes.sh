#!/usr/bin/env bash
# check_geant4_homes.sh
# Busca SOLO instalaciones de Geant4 en:
#   /home/rrios
#   /home/sndecs
#   /home/tdship
# No modifica ningún archivo.

set -u

HOMES=(
    /home/rrios
    /home/sndecs
    /home/tdship
)

found=0

echo "Buscando Geant4 en los HOME indicados..."
echo

for home_dir in "${HOMES[@]}"; do
    echo "===== $home_dir ====="

    if [[ ! -d "$home_dir" ]]; then
        echo "[AVISO] El directorio no existe."
        echo
        continue
    fi

    mapfile -t matches < <(
        sudo find "$home_dir" -xdev -maxdepth 10 \
            \( -type f -o -type l \) \
            \( -name geant4-config \
               -o -name geant4.sh \
               -o -name Geant4Config.cmake \) \
            -print 2>/dev/null |
        sort
    )

    if (( ${#matches[@]} == 0 )); then
        echo "[NO] No se encontraron archivos característicos de Geant4."
        echo
        continue
    fi

    found=1
    printf '%s\n' "${matches[@]}"

    for path in "${matches[@]}"; do
        if [[ "$(basename "$path")" == "geant4-config" ]]; then
            version="$(sudo "$path" --version 2>/dev/null || true)"
            prefix="$(sudo "$path" --prefix 2>/dev/null || true)"

            [[ -n "$version" ]] && echo "  Versión: $version"
            [[ -n "$prefix" ]]  && echo "  Prefix:  $prefix"
        fi
    done

    echo
done

if (( found )); then
    echo "[OK] Se encontraron archivos de una instalación de Geant4."
    exit 0
else
    echo "[NO] No se encontró Geant4 en /home/rrios, /home/sndecs ni /home/tdship."
    exit 1
fi
