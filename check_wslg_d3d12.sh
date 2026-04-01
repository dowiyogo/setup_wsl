#!/bin/sh
set -u

line() {
    printf '%s\n' "------------------------------------------------------------"
}

say() {
    printf '%s\n' "$*"
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

check_path() {
    p="$1"
    if [ -e "$p" ]; then
        echo "OK   $p"
    else
        echo "MISS $p"
    fi
}

find_matches() {
    base="$1"
    pat="$2"
    if [ -d "$base" ]; then
        find "$base" -maxdepth 3 -iname "$pat" 2>/dev/null
    fi
}

line
say "Chequeo de backend d3d12 / WSLg en AlmaLinux"
line

say "Kernel: $(uname -r 2>/dev/null || echo desconocido)"
if [ -r /etc/os-release ]; then
    . /etc/os-release
    say "Distro: ${PRETTY_NAME:-desconocida}"
fi

say "DISPLAY         : ${DISPLAY:-<vacío>}"
say "WAYLAND_DISPLAY : ${WAYLAND_DISPLAY:-<vacío>}"
say "LD_LIBRARY_PATH : ${LD_LIBRARY_PATH:-<vacío>}"

line
say "Rutas clave de WSLg"
line
check_path /mnt/wslg
check_path /usr/lib/wsl/lib
check_path /usr/lib/wsl/drivers

line
say "Contenido de /usr/lib/wsl/lib"
line
if [ -d /usr/lib/wsl/lib ]; then
    ls -1 /usr/lib/wsl/lib 2>/dev/null || true
else
    say "No existe /usr/lib/wsl/lib"
fi

line
say "Búsqueda de bibliotecas/archivos relacionados con d3d12"
line
FOUND_ANY=0

for d in /usr/lib64 /usr/lib /usr/lib64/dri /usr/lib/dri /usr/lib/wsl/lib; do
    if [ -d "$d" ]; then
        OUT="$(find "$d" -maxdepth 3 \( -iname '*d3d12*' -o -iname '*dxcore*' -o -iname '*dzn*' \) 2>/dev/null || true)"
        if [ -n "$OUT" ]; then
            FOUND_ANY=1
            printf '%s\n' "$OUT"
        fi
    fi
done

if [ "$FOUND_ANY" -eq 0 ]; then
    say "No se encontraron archivos con d3d12/dxcore/dzn en rutas típicas."
fi

line
say "Drivers DRI presentes"
line
DRI_FOUND=0
for d in /usr/lib64/dri /usr/lib/dri; do
    if [ -d "$d" ]; then
        DRI_FOUND=1
        say "Directorio: $d"
        ls -1 "$d" 2>/dev/null | grep -Ei 'swrast|zink|d3d12|kms|virtio|radeonsi|iris|crocus' || true
    fi
done
if [ "$DRI_FOUND" -eq 0 ]; then
    say "No existen directorios DRI típicos."
fi

line
say "Comprobación de glxinfo / eglinfo"
line
if have_cmd glxinfo; then
    glxinfo -B 2>/dev/null | sed -n '1,20p'
else
    say "glxinfo no está instalado."
fi

if [ -x /usr/lib64/mesa/eglinfo ]; then
    /usr/lib64/mesa/eglinfo 2>/dev/null | grep -i -E 'EGL vendor|string|driver name|d3d12|swrast' | head -20 || true
elif have_cmd eglinfo; then
    eglinfo 2>/dev/null | grep -i -E 'EGL vendor|string|driver name|d3d12|swrast' | head -20 || true
else
    say "eglinfo no está instalado."
fi

line
say "Diagnóstico rápido"
line

SOFT=0
if have_cmd glxinfo; then
    if glxinfo -B 2>/dev/null | grep -Eiq 'llvmpipe|softpipe|swrast'; then
        SOFT=1
    fi
fi

if [ "$FOUND_ANY" -eq 0 ]; then
    say "No aparecen rastros claros del backend d3d12 en las rutas típicas."
    say "Eso sugiere que AlmaLinux podría no estar resolviendo/cargando el backend acelerado de WSLg."
elif [ "$SOFT" -eq 1 ]; then
    say "Sí hay piezas de WSLg visibles, pero OpenGL sigue cayendo en software."
    say "Eso sugiere problema de integración/carga de Mesa, no sólo ausencia de archivos."
else
    say "Hay archivos relacionados con d3d12 y no se detectó software rendering de forma obvia."
    say "Revisa igual la salida completa de glxinfo -B."
fi

line
say "Sugerencia"
line
say "Pégame la salida completa de este script y te digo si el problema es:"
say "1) falta de backend/archivos,"
say "2) problema de carga de bibliotecas,"
say "3) o que AlmaLinux simplemente no está enganchando WSLg acelerado."
