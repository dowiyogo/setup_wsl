#!/usr/bin/env bash
# check_hep_alma9.sh
# Verifica ROOT, Geant4 y dependencias para compilar Geant4 headless.
# No instala ni modifica nada. No requiere sudo.

set -u

ok()   { printf '[OK]    %s\n' "$*"; }
warn() { printf '[AVISO] %s\n' "$*"; }
miss() { printf '[FALTA] %s\n' "$*"; }
section() { printf '\n===== %s =====\n' "$*"; }

has() { command -v "$1" >/dev/null 2>&1; }

version_ge() {
    # Verdadero si $1 >= $2.
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

show_command() {
    local command_name="$1"
    shift
    if has "$command_name"; then
        ok "$command_name: $(command -v "$command_name")"
        "$command_name" "$@" 2>&1 | head -n 1 | sed 's/^/        /' || true
    else
        miss "$command_name no está en PATH"
    fi
}

section "Sistema"

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "Sistema: ${PRETTY_NAME:-desconocido}"
    if [[ "${ID:-}" =~ ^(almalinux|rhel|rocky|centos)$ ]] &&
       [[ "${VERSION_ID:-}" == 9* ]]; then
        ok "Distribución EL9 compatible"
    else
        warn "Este script fue preparado para AlmaLinux/RHEL/Rocky 9"
    fi
fi

echo "Arquitectura: $(uname -m)"
echo "CPU:          $(getconf _NPROCESSORS_ONLN 2>/dev/null || echo '?') núcleos"
echo "HOME:         $HOME"
df -h "$HOME" | awk 'NR==2 {print "Disco HOME:   "$4" libres de "$2}'

if [[ -w /opt ]]; then
    ok "/opt es escribible"
else
    warn "/opt no es escribible; conviene instalar Geant4 en \$HOME/opt"
fi

if has sudo; then
    warn "sudo existe, pero este script no lo utiliza"
else
    warn "sudo no está disponible; cualquier paquete faltante debe instalarlo el administrador"
fi

section "ROOT"

root_found=0

if has root; then
    root_found=1
    ok "root: $(command -v root)"
else
    miss "root"
fi

if has root-config; then
    root_found=1
    ok "root-config: $(command -v root-config)"
    echo "Versión: $(root-config --version 2>/dev/null || echo '?')"
    echo "Prefix:  $(root-config --prefix 2>/dev/null || echo '?')"
    echo "C++:     $(root-config --cxx 2>/dev/null || echo '?')"
else
    warn "root-config no está en PATH"
fi

if (( root_found )); then
    ok "ROOT ya está instalado; no hace falta reinstalarlo para instalar Geant4"
fi

section "Geant4"

geant4_found=0

if has geant4-config; then
    geant4_found=1
    ok "geant4-config: $(command -v geant4-config)"
    echo "Versión: $(geant4-config --version 2>/dev/null || echo '?')"
    echo "Prefix:  $(geant4-config --prefix 2>/dev/null || echo '?')"
else
    warn "geant4-config no está en PATH"
fi

for variable in Geant4_DIR G4INSTALL GEANT4_DATA_DIR G4EXAMPLES G4LEDATA; do
    value="${!variable-}"
    if [[ -n "$value" ]]; then
        geant4_found=1
        echo "$variable=$value"
    fi
done

# Busca instalaciones cuyo entorno quizá no se haya cargado.
for base in /usr/local /opt "$HOME/.local" "$HOME/opt"; do
    [[ -d "$base" ]] || continue
    while IFS= read -r file; do
        geant4_found=1
        echo "Encontrado fuera de PATH: $file"
    done < <(
        find "$base" -maxdepth 7 -type f \
          \( -name geant4-config -o -name geant4.sh -o -name Geant4Config.cmake \) \
          -print 2>/dev/null | head -n 20
    )
done

if has rpm; then
    rpm -qa | grep -Ei '^geant4' | sed 's/^/RPM instalado: /' || true
fi

if (( geant4_found == 0 )); then
    miss "No se detectó Geant4"
fi

section "Compilador y herramientas"

show_command gcc --version
show_command g++ --version
show_command cmake --version
show_command make --version
show_command git --version
show_command curl --version
show_command tar --version

if has g++; then
    gcc_version="$(g++ -dumpfullversion -dumpversion 2>/dev/null || true)"
    if [[ -n "$gcc_version" ]] && version_ge "$gcc_version" 11; then
        ok "GCC $gcc_version satisface el mínimo GCC 11"
    else
        miss "Se requiere GCC 11 o superior; detectado: ${gcc_version:-desconocido}"
    fi

    if printf 'int main(){}\n' |
       g++ -std=c++17 -x c++ -fsyntax-only - >/dev/null 2>&1; then
        ok "El compilador acepta C++17"
    else
        miss "El compilador no pudo compilar una prueba C++17"
    fi
fi

if has cmake; then
    cmake_version="$(cmake --version | awk 'NR==1 {print $3}')"
    if version_ge "$cmake_version" 3.16; then
        ok "CMake $cmake_version satisface el mínimo 3.16"
    else
        miss "Se requiere CMake 3.16 o superior; detectado: $cmake_version"
    fi
fi

section "Paquetes AlmaLinux 9"

# Paquetes prácticos para descargar y compilar Geant4 sin Qt, X11 ni OpenGL.
required_packages=(
    gcc
    gcc-c++
    make
    cmake
    git
    curl
    tar
    gzip
    expat-devel
)

# zlib puede ser interna; xerces-c solo se necesita para GDML.
optional_packages=(
    zlib-devel
    xerces-c-devel
    ninja-build
    wget
    bzip2
    xz
)

missing_required=()
missing_optional=()

if has rpm; then
    echo "Requeridos para esta instalación headless:"
    for package in "${required_packages[@]}"; do
        if rpm -q "$package" >/dev/null 2>&1; then
            ok "$package"
        else
            miss "$package"
            missing_required+=("$package")
        fi
    done

    echo
    echo "Opcionales:"
    for package in "${optional_packages[@]}"; do
        if rpm -q "$package" >/dev/null 2>&1; then
            ok "$package"
        else
            warn "$package"
            missing_optional+=("$package")
        fi
    done
else
    warn "rpm no está disponible; no se pudieron verificar los nombres de paquetes"
fi

section "Resumen"

if (( ${#missing_required[@]} > 0 )); then
    echo "Paquetes mínimos faltantes:"
    printf '  %s\n' "${missing_required[@]}"
    echo
    echo "Comando que podría ejecutar el administrador:"
    printf '  sudo dnf install'
    printf ' %q' "${missing_required[@]}"
    printf '\n'
elif has rpm; then
    ok "No faltan paquetes mínimos de la lista verificada"
fi

if [[ " ${missing_optional[*]-} " == *" xerces-c-devel "* ]]; then
    echo
    echo "Para usar archivos GDML, pedir además:"
    echo "  sudo dnf install xerces-c-devel"
fi

cat <<'EOF'

No necesitas Qt, X11, OpenGL ni RayTracer para simulaciones por terminal.

Opciones CMake recomendadas:

  -DGEANT4_INSTALL_DATA=ON
  -DGEANT4_BUILD_MULTITHREADED=ON
  -DGEANT4_USE_QT=OFF
  -DGEANT4_USE_OPENGL_X11=OFF
  -DGEANT4_USE_RAYTRACER_X11=OFF

Para GDML:
  -DGEANT4_USE_GDML=ON       # requiere xerces-c-devel

Sin GDML:
  -DGEANT4_USE_GDML=OFF

EOF
