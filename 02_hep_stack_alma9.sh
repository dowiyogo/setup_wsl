#!/bin/sh
set -eu

# ============================================================
# 02_hep_stack_alma9.sh
# AlmaLinux 9 / WSL2
# Instala:
#   - dependencias HEP/científicas
#   - ROOT (binario oficial)
#   - Geant4 11.4.0 desde fuente
#   - datasets Geant4
#   - script de entorno /opt/hep/setup.sh
#
# Ejecutar como root:
#   sudo sh 02_hep_stack_alma9.sh
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
    echo "Este script debe ejecutarse como root."
    echo "Usa: sudo sh $0"
    exit 1
fi

# ----------------------------
# Variables editables
# ----------------------------
PREFIX="/opt/hep"
SRC_DIR="${PREFIX}/src"
BUILD_DIR="${PREFIX}/build"

G4_VERSION="11.4.0"
G4_TAG="v${G4_VERSION}"
G4_URL="https://github.com/Geant4/geant4/archive/refs/tags/${G4_TAG}.tar.gz"

# Ajusta esto si luego descubres la versión exacta de ROOT en la VM
ROOT_VERSION="6.36.10"
ROOT_PLATFORM="almalinux9.7-x86_64-gcc11.5"
ROOT_ARCHIVE="root_v${ROOT_VERSION}.Linux-${ROOT_PLATFORM}.tar.gz"
ROOT_URL="https://root.cern/download/${ROOT_ARCHIVE}"

# Opciones Geant4
G4_INSTALL_EXAMPLES="ON"
G4_INSTALL_DATA="ON"
G4_USE_GDML="ON"
G4_USE_QT="ON"
G4_USE_OPENGL_X11="ON"
G4_USE_RAYTRACER_X11="ON"
G4_BUILD_MULTITHREADED="ON"
G4_USE_SYSTEM_EXPAT="ON"
G4_USE_SYSTEM_ZLIB="ON"

# Núcleos para compilar
NPROC="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
[ -n "${NPROC}" ] || NPROC=2

# ----------------------------
# Funciones auxiliares
# ----------------------------
install_if_available() {
    PKG="$1"
    if rpm -q "$PKG" >/dev/null 2>&1; then
        echo "==> Ya instalado: $PKG"
        return 0
    fi
    if dnf -q list --available "$PKG" >/dev/null 2>&1; then
        echo "==> Instalando opcional: $PKG"
        dnf -y install "$PKG"
    else
        echo "==> Aviso: paquete opcional no disponible en repos: $PKG"
    fi
}

download_file() {
    URL="$1"
    OUT="$2"

    rm -f "$OUT"

    if command -v curl >/dev/null 2>&1; then
        curl -L --fail --retry 3 -o "$OUT" "$URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$OUT" "$URL"
    else
        echo "Ni curl ni wget están disponibles."
        exit 1
    fi
}

# ----------------------------
# Comprobación de SO
# ----------------------------
if [ -r /etc/os-release ]; then
    . /etc/os-release
    echo "Detectado: ${PRETTY_NAME:-desconocido}"
    case "${ID:-}" in
        almalinux|rhel|rocky|centos) : ;;
        *)
            echo "Advertencia: este script fue pensado para AlmaLinux/RHEL 9."
            ;;
    esac
fi

# ----------------------------
# Repositorios
# ----------------------------
echo "==> Preparando repositorios"
dnf -y install epel-release dnf-plugins-core
crb enable || dnf config-manager --set-enabled crb || true
dnf makecache

# ----------------------------
# Dependencias base HEP / ROOT / Geant4
# ----------------------------
echo "==> Instalando dependencias requeridas"
dnf -y install \
    gcc gcc-c++ gcc-gfortran \
    make cmake ninja-build binutils \
    git curl wget tar gzip bzip2 xz unzip patch \
    python3 python3-devel python3-pip python3-numpy \
    openssl-devel \
    expat-devel zlib-devel \
    xerces-c-devel \
    boost-devel \
    libX11-devel libXpm-devel libXft-devel libXext-devel libXt-devel libXmu-devel \
    mesa-libGL-devel mesa-libGLU-devel \
    readline-devel libuuid-devel libxml2-devel \
    qt6-qtbase-devel

echo "==> Instalando dependencias opcionales útiles"
install_if_available freeglut-devel
install_if_available glew-devel
install_if_available ftgl-devel
install_if_available cfitsio-devel
install_if_available graphviz-devel
install_if_available fftw-devel
install_if_available gsl-devel
install_if_available xrootd-client-devel
install_if_available xrootd-libs-devel
install_if_available pcre-devel

# ----------------------------
# Directorios
# ----------------------------
echo "==> Creando directorios de instalación"
mkdir -p "$PREFIX" "$SRC_DIR" "$BUILD_DIR"

# ----------------------------
# Instalar ROOT (binario oficial)
# ----------------------------
echo "==> Instalando ROOT ${ROOT_VERSION}"
cd "$SRC_DIR"

ROOT_TARBALL="${SRC_DIR}/${ROOT_ARCHIVE}"
ROOT_TMP="${BUILD_DIR}/root-extract"

download_file "$ROOT_URL" "$ROOT_TARBALL"

rm -rf "$ROOT_TMP" "${PREFIX}/root-${ROOT_VERSION}" "${PREFIX}/root"
mkdir -p "$ROOT_TMP"

tar -xzf "$ROOT_TARBALL" -C "$ROOT_TMP"

if [ ! -d "${ROOT_TMP}/root" ]; then
    echo "No se encontró el directorio 'root' tras descomprimir ${ROOT_ARCHIVE}"
    exit 1
fi

mv "${ROOT_TMP}/root" "${PREFIX}/root-${ROOT_VERSION}"
ln -sfn "${PREFIX}/root-${ROOT_VERSION}" "${PREFIX}/root"

if [ ! -f "${PREFIX}/root/bin/thisroot.sh" ]; then
    echo "No se encontró thisroot.sh después de instalar ROOT."
    exit 1
fi

# ----------------------------
# Instalar Geant4 desde fuente
# ----------------------------
echo "==> Descargando Geant4 ${G4_VERSION}"
cd "$SRC_DIR"

G4_TARBALL="${SRC_DIR}/geant4-${G4_TAG}.tar.gz"
download_file "$G4_URL" "$G4_TARBALL"

# Detectar nombre real del directorio dentro del tarball
G4_EXTRACTED_DIR="$(tar -tzf "$G4_TARBALL" | head -1 | cut -d/ -f1)"
if [ -z "$G4_EXTRACTED_DIR" ]; then
    echo "No se pudo detectar el directorio contenido en el tarball de Geant4."
    exit 1
fi

rm -rf "${SRC_DIR}/${G4_EXTRACTED_DIR}" \
       "${SRC_DIR}/geant4-v${G4_VERSION}" \
       "${BUILD_DIR}/geant4-v${G4_VERSION}" \
       "${PREFIX}/geant4-${G4_VERSION}" \
       "${PREFIX}/geant4"

tar -xzf "$G4_TARBALL" -C "$SRC_DIR"

if [ ! -d "${SRC_DIR}/${G4_EXTRACTED_DIR}" ]; then
    echo "No se encontró el directorio fuente extraído de Geant4."
    exit 1
fi

mv "${SRC_DIR}/${G4_EXTRACTED_DIR}" "${SRC_DIR}/geant4-v${G4_VERSION}"

G4_SRC="${SRC_DIR}/geant4-v${G4_VERSION}"
G4_BUILD="${BUILD_DIR}/geant4-v${G4_VERSION}"
G4_INSTALL="${PREFIX}/geant4-${G4_VERSION}"

mkdir -p "$G4_BUILD"

echo "==> Configurando Geant4"
cmake -S "$G4_SRC" -B "$G4_BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$G4_INSTALL" \
    -DGEANT4_INSTALL_DATA="${G4_INSTALL_DATA}" \
    -DGEANT4_INSTALL_EXAMPLES="${G4_INSTALL_EXAMPLES}" \
    -DGEANT4_BUILD_MULTITHREADED="${G4_BUILD_MULTITHREADED}" \
    -DGEANT4_USE_SYSTEM_EXPAT="${G4_USE_SYSTEM_EXPAT}" \
    -DGEANT4_USE_SYSTEM_ZLIB="${G4_USE_SYSTEM_ZLIB}" \
    -DGEANT4_USE_GDML="${G4_USE_GDML}" \
    -DGEANT4_USE_QT="${G4_USE_QT}" \
    -DGEANT4_USE_OPENGL_X11="${G4_USE_OPENGL_X11}" \
    -DGEANT4_USE_RAYTRACER_X11="${G4_USE_RAYTRACER_X11}"

echo "==> Compilando Geant4 con ${NPROC} hilos"
cmake --build "$G4_BUILD" -j"$NPROC"

echo "==> Instalando Geant4"
cmake --install "$G4_BUILD"

ln -sfn "$G4_INSTALL" "${PREFIX}/geant4"

if [ ! -f "${PREFIX}/geant4/bin/geant4.sh" ]; then
    echo "No se encontró geant4.sh después de instalar Geant4."
    exit 1
fi

# ----------------------------
# Script de entorno común
# ----------------------------
echo "==> Creando script de entorno ${PREFIX}/setup.sh"
cat > "${PREFIX}/setup.sh" <<'EOF'
#!/bin/sh

HEP_PREFIX="/opt/hep"

if [ -f "${HEP_PREFIX}/root/bin/thisroot.sh" ]; then
    . "${HEP_PREFIX}/root/bin/thisroot.sh"
fi

if [ -f "${HEP_PREFIX}/geant4/bin/geant4.sh" ]; then
    . "${HEP_PREFIX}/geant4/bin/geant4.sh"
fi

export HEP_PREFIX
EOF

chmod 755 "${PREFIX}/setup.sh"

# ----------------------------
# Limpieza
# ----------------------------
dnf clean all

# ----------------------------
# Resumen
# ----------------------------
echo
echo "=============================================="
echo " Instalación terminada"
echo "=============================================="
echo "ROOT     : ${PREFIX}/root"
echo "Geant4   : ${PREFIX}/geant4"
echo "Setup    : source ${PREFIX}/setup.sh"
echo
echo "Pruebas sugeridas:"
echo "  source ${PREFIX}/setup.sh"
echo "  root -l -q"
echo "  geant4-config --version"
echo "  echo \$GEANT4_DATA_DIR"
echo
echo "Ejemplo B1:"
echo "  source ${PREFIX}/setup.sh"
echo "  mkdir -p \$HOME/buildB1 && cd \$HOME/buildB1"
echo "  cmake \$G4EXAMPLES/basic/B1"
echo "  make -j${NPROC}"
echo "  ./exampleB1"
echo
echo "Si quieres que quede permanente en bash:"
echo "  echo 'source ${PREFIX}/setup.sh' >> ~/.bashrc"
