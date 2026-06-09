#!/usr/bin/env bash
# check_geant4_t0minidaq.sh
# Solo verifica si Geant4 está instalado o configurado en el usuario t0minidaq.
# No modifica ningún archivo.

set -u

USER_TO_CHECK="t0minidaq"

ok()   { printf '[OK]    %s\n' "$*"; }
info() { printf '[INFO]  %s\n' "$*"; }
warn() { printf '[AVISO] %s\n' "$*"; }

command -v sudo >/dev/null 2>&1 || {
    echo "[ERROR] sudo no está disponible."
    exit 1
}

entry="$(getent passwd "$USER_TO_CHECK")"
if [[ -z "$entry" ]]; then
    echo "[ERROR] El usuario $USER_TO_CHECK no existe."
    exit 1
fi

home_dir="$(cut -d: -f6 <<< "$entry")"
shell="$(cut -d: -f7 <<< "$entry")"

info "Usuario: $USER_TO_CHECK"
info "HOME:    $home_dir"
info "Shell:   $shell"

echo
echo "===== Entorno del usuario ====="

sudo -iu "$USER_TO_CHECK" bash -lc '
    for f in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile" "$HOME/.bashrc"; do
        [[ -r "$f" ]] && source "$f" >/dev/null 2>&1 || true
    done

    if command -v geant4-config >/dev/null 2>&1; then
        echo "[OK]    geant4-config: $(command -v geant4-config)"
        echo "[OK]    versión: $(geant4-config --version 2>/dev/null)"
        echo "[OK]    prefix:  $(geant4-config --prefix 2>/dev/null)"
    else
        echo "[AVISO] geant4-config no aparece en PATH"
    fi

    for var in Geant4_DIR G4INSTALL GEANT4_DATA_DIR G4EXAMPLES G4LEDATA; do
        value="${!var-}"
        [[ -n "$value" ]] && echo "[INFO]  $var=$value"
    done
'

echo
echo "===== Archivos dentro de $home_dir ====="

mapfile -t found < <(
    sudo find "$home_dir" -xdev -maxdepth 9 \
        \( -type f -o -type l \) \
        \( -name geant4-config \
           -o -name geant4.sh \
           -o -name Geant4Config.cmake \) \
        -print 2>/dev/null |
    sort
)

if (( ${#found[@]} == 0 )); then
    warn "No se encontraron archivos característicos de Geant4 en el HOME."
    exit 1
fi

printf '%s\n' "${found[@]}"

echo
echo "===== Versiones encontradas ====="

verified=0

for path in "${found[@]}"; do
    case "$(basename "$path")" in
        geant4-config)
            version="$(sudo -u "$USER_TO_CHECK" "$path" --version 2>/dev/null || true)"
            prefix="$(sudo -u "$USER_TO_CHECK" "$path" --prefix 2>/dev/null || true)"

            if [[ -n "$version" ]]; then
                ok "$path"
                echo "        versión: $version"
                [[ -n "$prefix" ]] && echo "        prefix:  $prefix"
                verified=1
            fi
            ;;

        Geant4Config.cmake)
            version="$(
                sudo grep -E \
                    'set[[:space:]]*\([[:space:]]*Geant4_VERSION' \
                    "$path" 2>/dev/null |
                head -n 1 || true
            )"

            if [[ -n "$version" ]]; then
                ok "$path"
                echo "        $version"
                verified=1
            fi
            ;;
    esac
done

echo

if (( verified )); then
    ok "Geant4 está instalado dentro del entorno de $USER_TO_CHECK."
    echo "Para usar esa instalación desde rrios habrá que cargar su geant4.sh"
    echo "o añadir su prefijo a CMAKE_PREFIX_PATH, siempre que los permisos lo permitan."
    exit 0
else
    warn "Hay archivos relacionados con Geant4, pero no se pudo confirmar la versión."
    exit 2
fi
