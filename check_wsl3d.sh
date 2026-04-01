#!/bin/sh
# check_wsl3d.sh
# Diagnóstico simple de aceleración 3D en WSL2 / WSLg
#
# Exit codes:
#   0 = aceleración detectada
#   1 = sin aceleración (software rendering)
#   2 = inconcluso / faltan herramientas

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

find_exec() {
    for x in "$@"; do
        if [ -n "$x" ] && [ -x "$x" ]; then
            printf '%s\n' "$x"
            return 0
        fi
        if have_cmd "$x"; then
            command -v "$x"
            return 0
        fi
    done
    return 1
}

contains_soft_renderer() {
    printf '%s\n' "$1" | grep -Eiq 'llvmpipe|softpipe|swrast'
}

contains_hw_hint() {
    printf '%s\n' "$1" | grep -Eiq 'd3d12|nvidia|amd|radeon|intel|iris|crocus'
}

print_install_hint() {
    say "Herramientas faltantes para diagnosticar mejor:"
    if have_cmd dnf; then
        say "  sudo dnf install mesa-demos vulkan-tools -y"
    elif have_cmd apt-get; then
        say "  sudo apt update && sudo apt install mesa-utils mesa-utils-extra vulkan-tools -y"
    elif have_cmd zypper; then
        say "  sudo zypper install Mesa-demo-x vulkan-tools"
    else
        say "  Instala glxinfo / eglinfo / vulkaninfo con el gestor de paquetes de tu distro."
    fi
}

RESULT="inconclusive"
DETAILS=""

line
say "Chequeo de aceleración 3D en WSL"
line

# 1) Entorno general
WSL_DETECTED="no"
if grep -qi microsoft /proc/version 2>/dev/null || \
   grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
    WSL_DETECTED="yes"
fi

say "WSL detectado           : $WSL_DETECTED"
say "Kernel                  : $(uname -r 2>/dev/null || echo desconocido)"
if [ -r /etc/os-release ]; then
    . /etc/os-release
    say "Distribución            : ${PRETTY_NAME:-desconocida}"
fi

say "DISPLAY                 : ${DISPLAY:-<vacío>}"
say "WAYLAND_DISPLAY         : ${WAYLAND_DISPLAY:-<vacío>}"
say "XDG_SESSION_TYPE        : ${XDG_SESSION_TYPE:-<vacío>}"

if [ -d /mnt/wslg ]; then
    say "/mnt/wslg               : presente"
else
    say "/mnt/wslg               : ausente"
fi

# 2) Buscar herramientas
GLXINFO="$(find_exec glxinfo /usr/lib64/mesa/glxinfo 2>/dev/null || true)"
EGLINFO="$(find_exec eglinfo /usr/lib64/mesa/eglinfo 2>/dev/null || true)"
VULKANINFO="$(find_exec vulkaninfo 2>/dev/null || true)"

line
say "Herramientas detectadas"
line
say "glxinfo                 : ${GLXINFO:-no encontrado}"
say "eglinfo                 : ${EGLINFO:-no encontrado}"
say "vulkaninfo              : ${VULKANINFO:-no encontrado}"

GLX_STATE="unknown"
EGL_STATE="unknown"
VK_STATE="unknown"

# 3) GLX / OpenGL
if [ -n "${GLXINFO:-}" ]; then
    line
    say "GLX / OpenGL"
    line

    GLX_OUT="$("$GLXINFO" -B 2>/dev/null || true)"

    if [ -n "$GLX_OUT" ]; then
        DIRECT="$(printf '%s\n' "$GLX_OUT" | sed -n 's/^direct rendering: //p' | head -n1)"
        ACCEL="$(printf '%s\n' "$GLX_OUT" | sed -n 's/^[[:space:]]*Accelerated: //p' | head -n1)"
        GL_VENDOR="$(printf '%s\n' "$GLX_OUT" | sed -n 's/^OpenGL vendor string: //p' | head -n1)"
        GL_RENDERER="$(printf '%s\n' "$GLX_OUT" | sed -n 's/^OpenGL renderer string: //p' | head -n1)"
        GL_VERSION="$(printf '%s\n' "$GLX_OUT" | sed -n 's/^OpenGL version string: //p' | head -n1)"
        DEV_LINE="$(printf '%s\n' "$GLX_OUT" | sed -n 's/^[[:space:]]*Device: //p' | head -n1)"

        say "direct rendering       : ${DIRECT:-desconocido}"
        say "Accelerated            : ${ACCEL:-desconocido}"
        say "OpenGL vendor          : ${GL_VENDOR:-desconocido}"
        say "OpenGL renderer        : ${GL_RENDERER:-desconocido}"
        say "OpenGL version         : ${GL_VERSION:-desconocido}"
        [ -n "$DEV_LINE" ] && say "Renderer device        : $DEV_LINE"

        GLX_TEXT="$GL_VENDOR $GL_RENDERER $DEV_LINE $ACCEL"

        if contains_soft_renderer "$GLX_TEXT"; then
            GLX_STATE="software"
        elif [ "${ACCEL:-}" = "yes" ] || contains_hw_hint "$GLX_TEXT"; then
            GLX_STATE="accelerated"
        else
            GLX_STATE="unknown"
        fi
    else
        say "No se pudo obtener salida de glxinfo -B"
    fi
fi

# 4) EGL
if [ -n "${EGLINFO:-}" ]; then
    line
    say "EGL"
    line

    EGL_OUT="$("$EGLINFO" 2>/dev/null || true)"

    if [ -n "$EGL_OUT" ]; then
        EGL_VENDOR="$(printf '%s\n' "$EGL_OUT" | sed -n 's/^EGL vendor string: //p' | head -n1)"
        EGL_CLIENT_APIS="$(printf '%s\n' "$EGL_OUT" | sed -n 's/^EGL client APIs: //p' | head -n1)"
        EGL_ANY_D3D12="$(printf '%s\n' "$EGL_OUT" | grep -i 'd3d12' | head -n1 || true)"
        EGL_ANY_LLVM="$(printf '%s\n' "$EGL_OUT" | grep -Ei 'llvmpipe|softpipe|swrast' | head -n1 || true)"

        say "EGL vendor             : ${EGL_VENDOR:-desconocido}"
        say "EGL client APIs        : ${EGL_CLIENT_APIS:-desconocido}"
        [ -n "$EGL_ANY_D3D12" ] && say "EGL hint               : $EGL_ANY_D3D12"
        [ -n "$EGL_ANY_LLVM" ] && say "EGL hint               : $EGL_ANY_LLVM"

        EGL_TEXT="$EGL_VENDOR $EGL_CLIENT_APIS $EGL_ANY_D3D12 $EGL_ANY_LLVM"

        if contains_soft_renderer "$EGL_TEXT"; then
            EGL_STATE="software"
        elif contains_hw_hint "$EGL_TEXT"; then
            EGL_STATE="accelerated"
        else
            EGL_STATE="unknown"
        fi
    else
        say "No se pudo obtener salida de eglinfo"
    fi
fi

# 5) Vulkan
if [ -n "${VULKANINFO:-}" ]; then
    line
    say "Vulkan"
    line

    VK_OUT="$("$VULKANINFO" --summary 2>/dev/null || "$VULKANINFO" 2>/dev/null || true)"

    if [ -n "$VK_OUT" ]; then
        VK_DEVICE_LINE="$(printf '%s\n' "$VK_OUT" | grep -Ei 'deviceName|GPU id|device[[:space:]]*=' | head -n1 || true)"
        VK_DRIVER_LINE="$(printf '%s\n' "$VK_OUT" | grep -Ei 'driverName|driverInfo' | head -n1 || true)"
        VK_LLVM_LINE="$(printf '%s\n' "$VK_OUT" | grep -Ei 'llvmpipe|softpipe|lavapipe|swrast' | head -n1 || true)"
        VK_D3D12_LINE="$(printf '%s\n' "$VK_OUT" | grep -Ei 'd3d12|nvidia|amd|intel|radeon' | head -n1 || true)"

        [ -n "$VK_DEVICE_LINE" ] && say "Vulkan device          : $VK_DEVICE_LINE"
        [ -n "$VK_DRIVER_LINE" ] && say "Vulkan driver          : $VK_DRIVER_LINE"
        [ -n "$VK_LLVM_LINE" ] && say "Vulkan hint            : $VK_LLVM_LINE"
        [ -n "$VK_D3D12_LINE" ] && say "Vulkan hint            : $VK_D3D12_LINE"

        VK_TEXT="$VK_DEVICE_LINE $VK_DRIVER_LINE $VK_LLVM_LINE $VK_D3D12_LINE"

        if printf '%s\n' "$VK_TEXT" | grep -Eiq 'lavapipe|llvmpipe|softpipe|swrast'; then
            VK_STATE="software"
        elif contains_hw_hint "$VK_TEXT"; then
            VK_STATE="accelerated"
        else
            VK_STATE="unknown"
        fi
    else
        say "No se pudo obtener salida de vulkaninfo"
    fi
fi

# 6) Diagnóstico final
line
say "Resumen"
line
say "Estado GLX             : $GLX_STATE"
say "Estado EGL             : $EGL_STATE"
say "Estado Vulkan          : $VK_STATE"

TOOLS_FOUND=0
[ -n "${GLXINFO:-}" ] && TOOLS_FOUND=1
[ -n "${EGLINFO:-}" ] && TOOLS_FOUND=1
[ -n "${VULKANINFO:-}" ] && TOOLS_FOUND=1

if [ "$TOOLS_FOUND" -eq 0 ]; then
    RESULT="inconclusive"
    DETAILS="No hay herramientas de diagnóstico instaladas."
elif [ "$GLX_STATE" = "accelerated" ] || [ "$EGL_STATE" = "accelerated" ] || [ "$VK_STATE" = "accelerated" ]; then
    RESULT="accelerated"
    DETAILS="Se detectaron indicios de aceleración por GPU."
elif [ "$GLX_STATE" = "software" ] || [ "$EGL_STATE" = "software" ] || [ "$VK_STATE" = "software" ]; then
    RESULT="software"
    DETAILS="Se detectó renderizado por software."
else
    RESULT="inconclusive"
    DETAILS="No hubo evidencia clara ni de GPU ni de software."
fi

say "Diagnóstico final      : $RESULT"
say "Detalle                : $DETAILS"

line
case "$RESULT" in
    accelerated)
        say "Conclusión: WSLg parece estar usando aceleración 3D."
        exit 0
        ;;
    software)
        say "Conclusión: WSLg está renderizando por software."
        say "Pistas típicas: renderer = llvmpipe / lavapipe / swrast."
        say "En Windows revisa:"
        say "  1) wsl --update"
        say "  2) wsl --shutdown"
        say "  3) driver GPU actualizado (AMD/NVIDIA/Intel)"
        exit 1
        ;;
    *)
        say "Conclusión: chequeo inconcluso."
        print_install_hint
        exit 2
        ;;
esac
