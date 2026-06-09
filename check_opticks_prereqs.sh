#!/usr/bin/env bash
# check_opticks_prereqs.sh
#
# Verificador incremental para Opticks en AlmaLinux 9.
# No instala ni modifica nada y no requiere sudo.

set -u

ok()       { printf '[OK]       %s\n' "$*"; }
warn()     { printf '[AVISO]    %s\n' "$*"; }
miss()     { printf '[FALTA]    %s\n' "$*"; }
critical() { printf '[CRITICO]  %s\n' "$*"; }
section()  { printf '\n===== %s =====\n' "$*"; }

has() { command -v "$1" >/dev/null 2>&1; }
rpm_has() { rpm -q "$1" >/dev/null 2>&1; }

version_ge() {
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

missing_rpms=()
critical_items=()
missing_items=()
tmpdir=""

cleanup() {
    [[ -n "$tmpdir" && -d "$tmpdir" ]] && rm -rf "$tmpdir"
}
trap cleanup EXIT

section "GPU NVIDIA y controlador"

if has lspci; then
    nvidia_pci="$(lspci | grep -Ei 'VGA|3D|Display' | grep -i NVIDIA || true)"
    if [[ -n "$nvidia_pci" ]]; then
        ok "GPU NVIDIA detectada por PCI"
        sed 's/^/           /' <<< "$nvidia_pci"
    else
        warn "lspci no muestra una GPU NVIDIA"
    fi
else
    warn "lspci no está disponible"
fi

if has nvidia-smi && nvidia-smi >/dev/null 2>&1; then
    ok "nvidia-smi funciona"
    nvidia-smi \
      --query-gpu=index,name,driver_version,memory.total \
      --format=csv,noheader 2>/dev/null |
      sed 's/^/           /' || nvidia-smi -L

    compute_cap="$(
        nvidia-smi --query-gpu=compute_cap \
          --format=csv,noheader 2>/dev/null | head -n 1 || true
    )"

    if [[ -n "$compute_cap" ]]; then
        ok "Compute capability: $compute_cap"
        echo "           OPTICKS_COMPUTE_CAPABILITY=${compute_cap/.}"
    else
        warn "Este nvidia-smi no reporta compute capability"
        echo "           Después se puede obtener compilando CUDA deviceQuery."
    fi
else
    critical "nvidia-smi no existe o no puede comunicarse con el driver"
    critical_items+=("GPU/controlador NVIDIA operativo")
fi

if compgen -G '/dev/nvidia*' >/dev/null; then
    ok "Dispositivos /dev/nvidia* visibles"
else
    warn "No se ven dispositivos /dev/nvidia*"
fi

section "CUDA Toolkit"

cuda_prefix=""

for candidate in \
    "${CUDA_HOME-}" \
    "${CUDA_PATH-}" \
    "${OPTICKS_CUDA_PREFIX-}" \
    /usr/local/cuda \
    /opt/cuda \
    "$HOME/opt/cuda"
do
    [[ -n "$candidate" && -d "$candidate" ]] || continue
    if [[ -x "$candidate/bin/nvcc" || -r "$candidate/include/cuda.h" ]]; then
        cuda_prefix="$candidate"
        break
    fi
done

if has nvcc; then
    ok "nvcc: $(command -v nvcc)"
    nvcc --version | tail -n 2 | sed 's/^/           /'

    tmpdir="$(mktemp -d)"
    cat > "$tmpdir/test.cu" <<'EOF'
#include <cuda_runtime.h>
int main() { return 0; }
EOF

    if nvcc -std=c++17 -c "$tmpdir/test.cu" \
        -o "$tmpdir/test.o" >/dev/null 2>&1; then
        ok "nvcc compila CUDA+C++17 con el GCC actual"
    else
        critical "nvcc existe, pero falló una compilación CUDA+C++17"
        critical_items+=("Compatibilidad nvcc–GCC")
    fi

    rm -rf "$tmpdir"
    tmpdir=""
else
    critical "nvcc no está en PATH"
    critical_items+=("CUDA Toolkit")
fi

if [[ -n "$cuda_prefix" ]]; then
    ok "CUDA prefix probable: $cuda_prefix"
    [[ -r "$cuda_prefix/include/cuda.h" ]] \
        && ok "cuda.h presente" \
        || miss "Falta $cuda_prefix/include/cuda.h"

    [[ -d "$cuda_prefix/include/thrust" ]] \
        && ok "Thrust presente" \
        || warn "No se encontró Thrust bajo el prefijo CUDA"
else
    warn "No se detectó un prefijo CUDA en rutas habituales"
fi

section "NVIDIA OptiX SDK"

optix_prefix=""

for candidate in \
    "${OPTICKS_OPTIX_PREFIX-}" \
    "${OPTIX_ROOT-}" \
    /usr/local/optix \
    /opt/optix \
    "$HOME/opt/optix" \
    "$HOME/opt/NVIDIA-OptiX-SDK"
do
    [[ -n "$candidate" && -r "$candidate/include/optix.h" ]] || continue
    optix_prefix="$candidate"
    break
done

if [[ -z "$optix_prefix" ]]; then
    optix_header="$(
        find /usr/local /opt "$HOME/.local" "$HOME/opt" \
          -maxdepth 7 -type f -name optix.h -print -quit 2>/dev/null || true
    )"
    if [[ -n "$optix_header" ]]; then
        optix_prefix="$(dirname "$(dirname "$optix_header")")"
    fi
fi

if [[ -n "$optix_prefix" ]]; then
    ok "OptiX prefix: $optix_prefix"

    optix_integer="$(
        awk '/^[[:space:]]*#define[[:space:]]+OPTIX_VERSION[[:space:]]+[0-9]+/ {
            print $3
            exit
        }' "$optix_prefix/include/optix.h"
    )"

    if [[ -n "$optix_integer" ]]; then
        major=$((optix_integer / 10000))
        minor=$(((optix_integer / 100) % 100))
        patch=$((optix_integer % 100))
        ok "OptiX ${major}.${minor}.${patch} (OPTIX_VERSION=$optix_integer)"

        if (( optix_integer < 70000 )); then
            critical "Opticks actual requiere OptiX 7 o posterior"
            critical_items+=("OptiX >= 7")
        fi
    else
        warn "No se pudo leer OPTIX_VERSION desde optix.h"
    fi

    for header in optix.h optix_stubs.h optix_function_table_definition.h; do
        [[ -r "$optix_prefix/include/$header" ]] \
            && ok "$header" \
            || miss "$header"
    done
else
    critical "No se encontró el SDK de OptiX"
    echo "           El SDK puede extraerse bajo \$HOME/opt; no requiere instalar el driver."
    critical_items+=("NVIDIA OptiX SDK")
fi

section "Geant4, CLHEP, Xerces-C y Boost"

if has geant4-config; then
    ok "Geant4 $(geant4-config --version 2>/dev/null || echo '?')"
    echo "           Prefix: $(geant4-config --prefix 2>/dev/null || echo '?')"
else
    miss "Geant4 todavía no está instalado o cargado"
    missing_items+=("Geant4")
fi

clhep_found=0
if has clhep-config; then
    clhep_found=1
    ok "clhep-config: $(command -v clhep-config)"
fi
if has pkg-config && pkg-config --exists clhep 2>/dev/null; then
    clhep_found=1
    ok "CLHEP $(pkg-config --modversion clhep)"
fi
if [[ -r /usr/include/CLHEP/Random/Random.h ]]; then
    clhep_found=1
    ok "CLHEP headers presentes"
fi
if (( clhep_found == 0 )); then
    miss "CLHEP de desarrollo"
    missing_items+=("CLHEP")
fi

xerces_found=0
if has pkg-config && pkg-config --exists xerces-c 2>/dev/null; then
    xerces_found=1
    ok "Xerces-C $(pkg-config --modversion xerces-c)"
fi
if [[ -r /usr/include/xercesc/util/XercesVersion.hpp ]]; then
    xerces_found=1
    ok "Xerces-C headers presentes"
fi
if (( xerces_found == 0 )); then
    miss "Xerces-C de desarrollo"
    missing_items+=("Xerces-C")
fi

if [[ -r /usr/include/boost/version.hpp ]]; then
    boost_version="$(
        awk '/^#define BOOST_LIB_VERSION/ {
            gsub(/"/,"",$3)
            print $3
            exit
        }' /usr/include/boost/version.hpp
    )"
    ok "Boost ${boost_version:-versión desconocida}"
else
    miss "Boost de desarrollo"
    missing_items+=("Boost")
fi

section "CMake, GCC y Python"

if has cmake; then
    cmake_version="$(cmake --version | awk 'NR==1 {print $3}')"
    if version_ge "$cmake_version" 3.18; then
        ok "CMake $cmake_version"
    else
        critical "CMake $cmake_version es menor que 3.18"
        critical_items+=("CMake >= 3.18")
    fi
else
    critical "CMake no está disponible"
    critical_items+=("CMake")
fi

if has g++; then
    gcc_version="$(g++ -dumpfullversion -dumpversion)"
    ok "G++ $gcc_version"
    if printf 'int main(){}\n' |
       g++ -std=c++17 -x c++ -fsyntax-only - >/dev/null 2>&1; then
        ok "C++17 funciona"
    else
        critical "Falló la prueba C++17"
        critical_items+=("Compilador C++17")
    fi
else
    critical "g++ no está disponible"
    critical_items+=("g++")
fi

if has python3; then
    py_version="$(python3 -c 'import platform; print(platform.python_version())')"
    ok "Python $py_version"

    py_include="$(
        python3 -c 'import sysconfig; print(sysconfig.get_paths().get("include",""))'
    )"
    if [[ -r "$py_include/Python.h" ]]; then
        ok "Python.h presente"
    else
        miss "Python.h; probablemente falta python3-devel"
        missing_items+=("python3-devel")
    fi

    if python3 -m nanobind --cmake_dir >/dev/null 2>&1; then
        ok "nanobind disponible"
    else
        warn "nanobind no está instalado; algunos bindings Python no se construirán"
    fi
else
    critical "python3 no está disponible"
    critical_items+=("Python >= 3.8")
fi

section "Paquetes RPM"

rpms=(
    python3-devel
    python3-pip
    pkgconf-pkg-config
    zip
    unzip
    boost-devel
    clhep-devel
    xerces-c-devel
)

if has rpm; then
    for package in "${rpms[@]}"; do
        if rpm_has "$package"; then
            ok "$package"
        else
            miss "$package"
            missing_rpms+=("$package")
        fi
    done
fi

section "Resumen"

if (( ${#critical_items[@]} == 0 )); then
    ok "El stack NVIDIA no presenta bloqueos evidentes"
else
    critical "Bloqueos para Opticks:"
    printf '           - %s\n' "${critical_items[@]}"
fi

if (( ${#missing_items[@]} > 0 )); then
    echo
    miss "Dependencias de software todavía ausentes:"
    printf '           - %s\n' "${missing_items[@]}"
fi

if (( ${#missing_rpms[@]} > 0 )); then
    echo
    echo "Paquetes que podría instalar el administrador:"
    printf '  sudo dnf install'
    printf ' %q' "${missing_rpms[@]}"
    printf '\n'
fi

cat <<'EOF'

Para instalar Geant4 pensando en Opticks, usa:

  -DGEANT4_INSTALL_DATA=ON
  -DGEANT4_BUILD_MULTITHREADED=ON
  -DGEANT4_USE_GDML=ON
  -DGEANT4_USE_SYSTEM_CLHEP=ON
  -DGEANT4_USE_SYSTEM_EXPAT=ON
  -DGEANT4_USE_SYSTEM_ZLIB=ON
  -DGEANT4_USE_QT=OFF
  -DGEANT4_USE_OPENGL_X11=OFF
  -DGEANT4_USE_RAYTRACER_X11=OFF

La simulación GPU headless no necesita una sesión gráfica. Sin embargo,
opticks-full puede intentar compilar componentes de visualización del árbol
completo, aunque luego no los uses.

EOF
