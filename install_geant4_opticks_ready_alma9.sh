#!/usr/bin/env bash
# install_geant4_opticks_ready_alma9.sh
#
# Instala Geant4 11.4.0 en $HOME para AlmaLinux 9.
# Deja Geant4 preparado para una futura integración con Opticks:
#   - GDML + Xerces-C
#   - CLHEP externo
#   - multithreading
#   - datasets y ejemplos
#   - bibliotecas compartidas
#   - sin Qt, OpenGL ni X11
#
# NO instala CUDA, OptiX ni Opticks.
# NO modifica ROOT.
#
# Uso:
#   chmod +x install_geant4_opticks_ready_alma9.sh
#   ./install_geant4_opticks_ready_alma9.sh
#
# Opciones:
#   --install-rpms   instala con sudo los RPM faltantes
#   --clean          reconstruye desde cero
#   --add-bashrc     añade el entorno a ~/.bashrc
#
# Variables opcionales:
#   G4_VERSION=11.4.0
#   JOBS=12
#   BUILD_TYPE=Release
#
set -Eeuo pipefail

G4_VERSION="${G4_VERSION:-11.4.0}"
BUILD_TYPE="${BUILD_TYPE:-Release}"

OPT_ROOT="${OPT_ROOT:-$HOME/opt}"
SRC_ROOT="${SRC_ROOT:-$HOME/src}"
BUILD_ROOT="${BUILD_ROOT:-$HOME/build}"

G4_TAG="v${G4_VERSION}"
G4_URL="${G4_URL:-https://github.com/Geant4/geant4/archive/refs/tags/${G4_TAG}.tar.gz}"

G4_ARCHIVE="$SRC_ROOT/geant4-${G4_TAG}.tar.gz"
G4_SOURCE="$SRC_ROOT/geant4-${G4_TAG}"
G4_BUILD="$BUILD_ROOT/geant4-${G4_TAG}"
G4_INSTALL="$OPT_ROOT/geant4-${G4_VERSION}"
G4_LINK="$OPT_ROOT/geant4"
ENV_FILE="$OPT_ROOT/hep_env.sh"

CPU_COUNT="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
JOBS="${JOBS:-$CPU_COUNT}"
(( JOBS > 12 )) && JOBS=12

INSTALL_RPMS=0
CLEAN=0
ADD_BASHRC=0

while (( $# > 0 )); do
    case "$1" in
        --install-rpms) INSTALL_RPMS=1 ;;
        --clean)        CLEAN=1 ;;
        --add-bashrc)   ADD_BASHRC=1 ;;
        -h|--help)
            sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Opción desconocida: $1" >&2
            exit 1
            ;;
    esac
    shift
done

log()  { printf '\n==> %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -ne 0 ]] ||
    fail "No ejecutes este script como root; debe instalar en tu HOME."

mkdir -p "$OPT_ROOT" "$SRC_ROOT" "$BUILD_ROOT"

# ----------------------------------------------------------------------
# Sistema
# ----------------------------------------------------------------------

log "Verificando AlmaLinux/EL9"

source /etc/os-release

[[ "${ID:-}" =~ ^(almalinux|rhel|rocky|centos)$ ]] ||
    fail "Este script fue preparado para AlmaLinux/RHEL/Rocky."

[[ "${VERSION_ID:-}" == 9* ]] ||
    fail "Este script fue preparado para EL9."

[[ "$(uname -m)" == "x86_64" ]] ||
    fail "Arquitectura no soportada: $(uname -m)"

echo "Sistema:      ${PRETTY_NAME:-desconocido}"
echo "Usuario:      $(id -un)"
echo "CPU:          $CPU_COUNT"
echo "Compilación:  $JOBS procesos"
echo "Instalación:  $G4_INSTALL"

# ----------------------------------------------------------------------
# RPM
# ----------------------------------------------------------------------

log "Verificando dependencias"

# CLHEP, Xerces-C y Python de desarrollo se dejan listos para Opticks.
PACKAGES=(
    gcc
    gcc-c++
    make
    cmake
    git
    curl
    wget
    tar
    gzip
    bzip2
    xz
    unzip
    zip
    patch
    pkgconf-pkg-config
    expat-devel
    zlib-devel
    xerces-c-devel
    clhep-devel
    boost-devel
    python3
    python3-devel
    python3-pip
)

missing=()

for pkg in "${PACKAGES[@]}"; do
    if rpm -q "$pkg" >/dev/null 2>&1; then
        ok "$pkg"
    else
        echo "[FALTA] $pkg"
        missing+=("$pkg")
    fi
done

if (( ${#missing[@]} > 0 )); then
    if (( INSTALL_RPMS == 0 )) && [[ -t 0 ]]; then
        echo
        read -r -p "¿Instalar los RPM faltantes con sudo? [s/N] " answer
        case "${answer,,}" in
            s|si|sí|y|yes) INSTALL_RPMS=1 ;;
        esac
    fi

    if (( INSTALL_RPMS )); then
        command -v sudo >/dev/null ||
            fail "sudo no está disponible."

        sudo dnf -y install "${missing[@]}" || {
            echo
            echo "Uno o más paquetes no están en los repositorios habilitados."
            echo "Pide al administrador habilitar CRB/EPEL, por ejemplo:"
            echo
            echo "  sudo dnf install dnf-plugins-core epel-release"
            echo "  sudo dnf config-manager --set-enabled crb"
            echo "  sudo dnf install clhep-devel xerces-c-devel python3-devel"
            exit 1
        }
    else
        echo
        echo "Ejecuta nuevamente:"
        echo
        echo "  $0 --install-rpms"
        exit 1
    fi
fi

for pkg in "${PACKAGES[@]}"; do
    rpm -q "$pkg" >/dev/null ||
        fail "El paquete $pkg sigue ausente."
done

# ----------------------------------------------------------------------
# Toolchain
# ----------------------------------------------------------------------

log "Verificando compilador"

gcc_version="$(g++ -dumpfullversion -dumpversion)"
cmake_version="$(cmake --version | awk 'NR==1 {print $3}')"

echo "G++:   $gcc_version"
echo "CMake: $cmake_version"

version_ge() {
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

version_ge "$gcc_version" 11 ||
    fail "Se requiere GCC 11 o superior."

version_ge "$cmake_version" 3.16 ||
    fail "Se requiere CMake 3.16 o superior."

printf 'int main(){}\n' |
    g++ -std=c++17 -x c++ -fsyntax-only - >/dev/null ||
    fail "El compilador no acepta C++17."

# ----------------------------------------------------------------------
# ROOT
# ----------------------------------------------------------------------

log "Verificando ROOT existente"

if command -v root-config >/dev/null 2>&1; then
    echo "ROOT version: $(root-config --version)"
    echo "ROOT prefix:  $(root-config --prefix)"
    ok "ROOT no será modificado"
else
    echo "[AVISO] ROOT no está en PATH; esto no impide compilar Geant4."
fi

# ----------------------------------------------------------------------
# CLHEP y Xerces-C
# ----------------------------------------------------------------------

log "Localizando CLHEP y Xerces-C"

CLHEP_CONFIG="$(
    rpm -ql clhep-devel 2>/dev/null |
        grep '/CLHEPConfig.cmake$' |
        head -n 1 || true
)"

[[ -n "$CLHEP_CONFIG" ]] ||
    fail "No se encontró CLHEPConfig.cmake pese a tener clhep-devel."

CLHEP_DIR="$(dirname "$CLHEP_CONFIG")"

pkg-config --exists xerces-c ||
    fail "pkg-config no encuentra Xerces-C."

echo "CLHEP:    $CLHEP_CONFIG"
echo "Xerces-C: $(pkg-config --modversion xerces-c)"

# ----------------------------------------------------------------------
# Limpiar
# ----------------------------------------------------------------------

if (( CLEAN )); then
    log "Limpiando build e instalación anteriores"
    rm -rf "$G4_BUILD" "$G4_INSTALL"
    [[ -L "$G4_LINK" ]] && rm -f "$G4_LINK"
fi

# ----------------------------------------------------------------------
# Descargar y extraer
# ----------------------------------------------------------------------

log "Preparando código fuente Geant4 $G4_VERSION"

if [[ ! -f "$G4_ARCHIVE" ]]; then
    curl -L --fail --retry 4 \
        -o "${G4_ARCHIVE}.part" "$G4_URL"
    mv "${G4_ARCHIVE}.part" "$G4_ARCHIVE"
else
    ok "Se reutiliza $G4_ARCHIVE"
fi

tar -tzf "$G4_ARCHIVE" >/dev/null ||
    fail "El archivo descargado no es válido."

if [[ ! -d "$G4_SOURCE" ]]; then
    tmp="$SRC_ROOT/.g4-extract-$$"
    rm -rf "$tmp"
    mkdir -p "$tmp"

    tar -xzf "$G4_ARCHIVE" -C "$tmp"

    extracted="$(
        find "$tmp" -mindepth 1 -maxdepth 1 -type d -print -quit
    )"

    [[ -n "$extracted" ]] ||
        fail "No se encontró el directorio extraído."

    mv "$extracted" "$G4_SOURCE"
    rm -rf "$tmp"
fi

[[ -f "$G4_SOURCE/CMakeLists.txt" ]] ||
    fail "La fuente de Geant4 está incompleta."

# ----------------------------------------------------------------------
# Configurar
# ----------------------------------------------------------------------

log "Configurando Geant4"

mkdir -p "$G4_BUILD"

cmake \
    -S "$G4_SOURCE" \
    -B "$G4_BUILD" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_INSTALL_PREFIX="$G4_INSTALL" \
    -DCMAKE_CXX_STANDARD=17 \
    -DBUILD_SHARED_LIBS=ON \
    -DGEANT4_INSTALL_DATA=ON \
    -DGEANT4_INSTALL_DATA_TIMEOUT=3000 \
    -DGEANT4_INSTALL_EXAMPLES=ON \
    -DGEANT4_BUILD_MULTITHREADED=ON \
    -DGEANT4_USE_GDML=ON \
    -DGEANT4_USE_SYSTEM_CLHEP=ON \
    -DCLHEP_DIR="$CLHEP_DIR" \
    -DGEANT4_USE_SYSTEM_EXPAT=ON \
    -DGEANT4_USE_SYSTEM_ZLIB=ON \
    -DGEANT4_USE_QT=OFF \
    -DGEANT4_USE_OPENGL_X11=OFF \
    -DGEANT4_USE_RAYTRACER_X11=OFF

CACHE="$G4_BUILD/CMakeCache.txt"

grep -qx 'GEANT4_USE_GDML:BOOL=ON' "$CACHE" ||
    fail "GDML no quedó activado."

grep -qx 'GEANT4_USE_SYSTEM_CLHEP:BOOL=ON' "$CACHE" ||
    fail "CLHEP externo no quedó activado."

grep -qx 'GEANT4_BUILD_MULTITHREADED:BOOL=ON' "$CACHE" ||
    fail "Multithreading no quedó activado."

# ----------------------------------------------------------------------
# Compilar e instalar
# ----------------------------------------------------------------------

log "Compilando Geant4"

cmake --build "$G4_BUILD" --parallel "$JOBS"

log "Instalando Geant4"

cmake --install "$G4_BUILD"

[[ -f "$G4_INSTALL/bin/geant4.sh" ]] ||
    fail "No se encontró geant4.sh tras instalar."

[[ -x "$G4_INSTALL/bin/geant4-config" ]] ||
    fail "No se encontró geant4-config tras instalar."

ln -sfn "$G4_INSTALL" "$G4_LINK"

# ----------------------------------------------------------------------
# Entorno
# ----------------------------------------------------------------------

log "Creando entorno"

G4_CONFIG="$(
    find "$G4_INSTALL" -type f -name Geant4Config.cmake -print -quit
)"

[[ -n "$G4_CONFIG" ]] ||
    fail "No se encontró Geant4Config.cmake."

G4_CMAKE_DIR="$(dirname "$G4_CONFIG")"

COMPUTE_CAPABILITY="$(
    nvidia-smi --query-gpu=compute_cap \
        --format=csv,noheader 2>/dev/null |
        head -n 1 |
        tr -d ' .' || true
)"

cat > "$ENV_FILE" <<EOF
#!/usr/bin/env bash
# Entorno local de Geant4.

export HEP_PREFIX="$OPT_ROOT"
export Geant4_DIR="$G4_CMAKE_DIR"

if [[ -f "$G4_LINK/bin/geant4.sh" ]]; then
    source "$G4_LINK/bin/geant4.sh"
fi

export CMAKE_PREFIX_PATH="$G4_LINK\${CMAKE_PREFIX_PATH:+:\$CMAKE_PREFIX_PATH}"
EOF

if [[ -n "$COMPUTE_CAPABILITY" ]]; then
    cat >> "$ENV_FILE" <<EOF

# Detectado para una futura instalación de Opticks.
export OPTICKS_COMPUTE_CAPABILITY="$COMPUTE_CAPABILITY"
EOF
fi

cat >> "$ENV_FILE" <<'EOF'

# Añadir solo cuando CUDA, OptiX y Opticks sean instalados:
# export OPTICKS_CUDA_PREFIX="$HOME/opt/cuda"
# export OPTICKS_OPTIX_PREFIX="$HOME/opt/optix"
# export OPTICKS_PREFIX="$HOME/opt/opticks"
EOF

chmod 755 "$ENV_FILE"

if (( ADD_BASHRC )); then
    line="source \"$ENV_FILE\""
    grep -Fqx "$line" "$HOME/.bashrc" 2>/dev/null ||
        printf '\n%s\n' "$line" >> "$HOME/.bashrc"
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

# ----------------------------------------------------------------------
# Prueba de integración
# ----------------------------------------------------------------------

log "Probando Geant4 + GDML + CLHEP + Xerces-C"

TEST_SRC="$BUILD_ROOT/g4-check-src"
TEST_BUILD="$BUILD_ROOT/g4-check-build"

rm -rf "$TEST_SRC" "$TEST_BUILD"
mkdir -p "$TEST_SRC"

cat > "$TEST_SRC/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(CheckG4 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Geant4 REQUIRED)
find_package(CLHEP REQUIRED CONFIG)
find_package(XercesC REQUIRED)

include(${Geant4_USE_FILE})

add_executable(check_g4 check_g4.cc)

target_link_libraries(check_g4
    PRIVATE
        ${Geant4_LIBRARIES}
        CLHEP::CLHEP
        XercesC::XercesC
)
EOF

cat > "$TEST_SRC/check_g4.cc" <<'EOF'
#include "G4Version.hh"
#include "G4GDMLParser.hh"
#include "CLHEP/Random/Random.h"
#include <xercesc/util/XercesVersion.hpp>
#include <iostream>

int main()
{
    G4GDMLParser parser;

    std::cout << "Geant4: " << G4Version << '\n';
    std::cout << "CLHEP seed: "
              << CLHEP::HepRandom::getTheSeed() << '\n';
    std::cout << "Xerces-C: "
              << XERCES_VERSION_MAJOR << '.'
              << XERCES_VERSION_MINOR << '.'
              << XERCES_VERSION_REVISION << '\n';

    return 0;
}
EOF

cmake \
    -S "$TEST_SRC" \
    -B "$TEST_BUILD" \
    -DGeant4_DIR="$G4_CMAKE_DIR" \
    -DCLHEP_DIR="$CLHEP_DIR"

cmake --build "$TEST_BUILD" --parallel "$JOBS"
"$TEST_BUILD/check_g4"

# ----------------------------------------------------------------------
# Resumen
# ----------------------------------------------------------------------

log "Instalación completada"

echo "Geant4:          $G4_INSTALL"
echo "Enlace estable:  $G4_LINK"
echo "Entorno:         $ENV_FILE"
echo "CMake config:    $G4_CONFIG"
echo
echo "Versión:"
"$G4_INSTALL/bin/geant4-config" --version
echo
echo "Para usarlo ahora:"
echo
echo "  source \"$ENV_FILE\""
echo
echo "CUDA, OptiX y Opticks no fueron instalados."
echo "Geant4 quedó preparado con GDML, CLHEP externo y multithreading."
