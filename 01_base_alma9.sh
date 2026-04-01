#!/bin/sh
set -eu

# AlmaLinux 9 / EL9 base bootstrap for WSL2
# - build tools
# - terminal utilities
# - Python scientific basics
# - Jupyter
# - gnuplot / grace / ImageMagick
# - gdb / valgrind
#
# Does NOT install:
# - office suites
# - web browsers
# - IDEs/editors beyond minimal console tools

if [ "$(id -u)" -ne 0 ]; then
    echo "Este script debe ejecutarse como root."
    echo "Usa: sudo sh $0"
    exit 1
fi

if [ -r /etc/os-release ]; then
    . /etc/os-release
    echo "Detectado: ${PRETTY_NAME:-desconocido}"
    case "${ID:-}" in
        almalinux|rhel|rocky|centos) : ;;
        *)
            echo "Advertencia: este script fue pensado para AlmaLinux 9 / EL9."
            ;;
    esac
    case "${VERSION_ID:-}" in
        9* ) : ;;
        * )
            echo "Advertencia: VERSION_ID=${VERSION_ID:-?}. Este script fue pensado para EL9."
            ;;
    esac
fi

echo "==> Actualizando sistema"
dnf -y update

echo "==> Instalando plugins de DNF"
dnf -y install dnf-plugins-core epel-release

echo "==> Habilitando CRB y refrescando metadatos"
crb enable || dnf config-manager --set-enabled crb || true
dnf makecache

echo "==> Instalando grupo Development Tools"
dnf -y groupinstall "Development Tools"

echo "==> Instalando utilidades base"
dnf -y install \
    which file \
    git git-lfs \
    curl wget rsync \
    tar unzip zip xz bzip2 \
    patch diffutils findutils \
    less vim-enhanced nano tmux screen \
    tree htop time \
    ca-certificates gnupg2 \
    openssh-clients \
    hostname procps-ng \
    lsof strace \
    man-db man-pages

echo "==> Instalando herramientas de build adicionales"
dnf -y install \
    cmake cmake-gui \
    ninja-build \
    pkgconf pkgconf-pkg-config \
    gcc gcc-c++ gcc-gfortran \
    make automake autoconf libtool \
    flex bison \
    byacc \
    m4 \
    redhat-rpm-config \
    environment-modules

echo "==> Instalando depuración y análisis"
dnf -y install \
    gdb valgrind elfutils elfutils-devel elfutils-libelf-devel

echo "==> Instalando Python base y stack científico"
dnf -y install \
    python3 python3-pip python3-setuptools python3-wheel python3-devel \
    python3-virtualenv \
    python3-ipython \
    python3-numpy \
    python3-scipy \
    python3-matplotlib

echo "==> Instalando Jupyter Notebook"
dnf -y install jupyter-notebook || true

# Fallback por si el paquete no quedara disponible en la distro/repos activos
if ! command -v jupyter-notebook >/dev/null 2>&1 && ! command -v jupyter >/dev/null 2>&1; then
    echo "==> No apareció jupyter desde RPM; instalando fallback en /opt/jupyter-venv"
    python3 -m venv /opt/jupyter-venv
    /opt/jupyter-venv/bin/pip install --upgrade pip
    /opt/jupyter-venv/bin/pip install notebook jupyterlab ipykernel
    ln -sf /opt/jupyter-venv/bin/jupyter /usr/local/bin/jupyter
    if [ -x /opt/jupyter-venv/bin/jupyter-notebook ]; then
        ln -sf /opt/jupyter-venv/bin/jupyter-notebook /usr/local/bin/jupyter-notebook
    fi
fi

echo "==> Instalando utilidades científicas extra"
dnf -y install \
    gnuplot \
    grace \
    ImageMagick || true

echo "==> Limpieza de caché DNF"
dnf clean all

echo
echo "Instalación base terminada."
echo
echo "Pruebas rápidas sugeridas:"
echo "  gcc --version"
echo "  g++ --version"
echo "  cmake --version"
echo "  python3 --version"
echo "  gdb --version"
echo "  valgrind --version"
echo "  gnuplot --version || true"
echo "  grace -version || true"
echo "  magick -version || convert -version || true"
echo "  jupyter --version || jupyter-notebook --version || true"
echo
echo "Para cargar modules en shells futuras, normalmente basta con:"
echo "  source /etc/profile.d/modules.sh"
