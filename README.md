# Instalar AlmaLinux 9 en Windows 11 con PowerShell

## Opción recomendada

Abre **PowerShell como Administrador** y ejecuta:

```powershell
wsl --install --no-distribution
````

Reinicia Windows, y luego ejecuta:

```powershell
wsl --update
wsl --list --online
wsl --install AlmaLinux-9
```

Para iniciarlo por primera vez:

```powershell
wsl -d AlmaLinux-9
```

Microsoft indica que `wsl --install` permite instalar WSL y también distribuciones específicas usando `wsl --install <DistributionName>`, y que los nombres válidos se pueden ver con `wsl --list --online`. AlmaLinux documenta que **AlmaLinux OS 9** está disponible tanto en Microsoft Store como en la CLI de WSL. ([Microsoft Learn][1])

---

## Comandos útiles después de instalar

Ver estado de WSL:

```powershell
wsl --status
```

Ver distribuciones instaladas:

```powershell
wsl --list --verbose
```

Poner AlmaLinux 9 como distribución por defecto:

```powershell
wsl --set-default AlmaLinux-9
```

Asegurar que use WSL 2:

```powershell
wsl --set-version AlmaLinux-9 2
```

Cerrar todas las instancias de WSL:

```powershell
wsl --shutdown
```

Actualizar WSL:

```powershell
wsl --update
```

Estos comandos forman parte de los comandos básicos actuales de WSL, y Microsoft también recomienda `wsl --update` y `wsl --shutdown` para mantener o reiniciar el entorno. ([Microsoft Learn][1])

---

## Si `wsl --install` no funciona

En algunos equipos conviene habilitar WSL manualmente desde PowerShell **como Administrador**:

```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

Luego reinicia Windows y ejecuta:

```powershell
wsl --update
wsl --install AlmaLinux-9
```

Microsoft mantiene estos pasos manuales como alternativa para instalaciones donde el método directo no funciona. ([Microsoft Learn][2])

---

## Resumen corto

Si quieres sólo lo esencial, usa esto:

```powershell
wsl --install --no-distribution
```

Reinicia, y después:

```powershell
wsl --update
wsl --install AlmaLinux-9
wsl -d AlmaLinux-9
```

[1]: https://learn.microsoft.com/es-es/windows/wsl/basic-commands?utm_source=chatgpt.com "Comandos básicos para WSL"
[2]: https://learn.microsoft.com/en-us/windows/wsl/install-manual?utm_source=chatgpt.com "Manual installation steps for older versions of WSL"



# Mesa 3D acelerado en AlmaLinux 9 sobre WSL2/WSLg

Este documento resume los pasos que funcionaron para habilitar aceleración 3D real en **AlmaLinux 9** corriendo en **WSL2**, usando **WSLg** y el backend **D3D12** de Mesa.

## Problema observado

Al ejecutar:

```bash
glxinfo -B
````

la salida mostraba renderizado por software:

* `OpenGL renderer string: llvmpipe ...`
* `Accelerated: no`

Eso indicaba que WSLg estaba funcionando, pero **sin aceleración por GPU**.

## Causa

La pila Mesa disponible en AlmaLinux 9 no traía el backend `d3d12` operativo para WSLg, por lo que OpenGL/EGL caían en `llvmpipe`/`swrast`.

## Solución

Se compiló **Mesa 24.0.5** manualmente, habilitando explícitamente el driver Gallium `d3d12`.

---

## 1. Instalar dependencias de compilación

Primero, habilitar repositorios necesarios:

```bash
sudo dnf install epel-release dnf-plugins-core -y
sudo dnf config-manager --set-enabled crb
sudo dnf makecache
```

Luego instalar dependencias:

```bash
sudo dnf install -y \
  gcc gcc-c++ meson ninja-build cmake pkgconf-pkg-config \
  python3-mako python3-pyyaml python3-ply \
  libX11-devel libXext-devel libXfixes-devel libdrm-devel \
  libxcb-devel libxshmfence-devel libXrandr-devel \
  wayland-devel wayland-protocols-devel \
  expat-devel zlib-devel elfutils-libelf-devel \
  libglvnd-devel llvm-devel clang-devel \
  bison flex git
```

---

## 2. Descargar Mesa 24.0.5

```bash
cd /usr/local/src
sudo git clone --branch mesa-24.0.5 https://gitlab.freedesktop.org/mesa/mesa.git
cd mesa
```

---

## 3. Configurar la compilación

Se usó `meson` con los drivers mínimos necesarios y habilitando `d3d12`:

```bash
sudo meson setup build \
  --prefix=/usr/local \
  -Dbuildtype=release \
  -Dplatforms=x11,wayland \
  -Dgallium-drivers=swrast,d3d12 \
  -Dvulkan-drivers= \
  -Dllvm=enabled
```

---

## 4. Compilar e instalar

```bash
sudo ninja -C build
sudo ninja -C build install
```

Esto instala la nueva Mesa en `/usr/local`, sin sobrescribir directamente la del sistema.

---

## 5. Ajustar variables de entorno

Para que WSLg use la Mesa recién compilada, se agregaron estas variables al entorno.

### Opción recomendada: sólo en WSL

Agregar esto a `~/.bashrc`:

```bash
if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib:/usr/lib/wsl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
  export GALLIUM_DRIVER=d3d12
fi
```

Luego recargar:

```bash
source ~/.bashrc
```

### Nota sobre `LD_LIBRARY_PATH`

La forma:

```bash
/usr/lib/wsl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
```

es intencional.

* Si `LD_LIBRARY_PATH` está vacío, queda sólo `/usr/lib/wsl/lib`
* Si ya tenía contenido, agrega `:$LD_LIBRARY_PATH`

Así se evita dejar dos puntos seguidos o un `:` sobrante.

---

## 6. Verificación

Ejecutar:

```bash
glxinfo -B
```

La salida correcta ahora debería verse parecida a:

```text
Vendor: Microsoft Corporation
Device: D3D12 (AMD Radeon(TM) Graphics)
Accelerated: yes
```

En el caso validado, la salida fue:

```text
Vendor: Microsoft Corporation
Device: D3D12 (AMD Radeon(TM) Graphics)
Accelerated: yes
OpenGL renderer string: D3D12 (AMD Radeon(TM) Graphics)
```

Eso confirma que WSLg ya está usando aceleración real por GPU.

---

## 7. Observaciones

* El problema no estaba en Windows ni en el driver AMD, sino en la pila Mesa de AlmaLinux 9.
* Compilar Mesa con `-Dgallium-drivers=swrast,d3d12` fue la clave.
* Instalar en `/usr/local` permite mantener separado lo compilado manualmente de los paquetes del sistema.
* Esta solución es especialmente útil en distros WSL donde la Mesa empaquetada no trae soporte `d3d12` funcional.

---

## 8. Comandos útiles de diagnóstico

### Ver OpenGL

```bash
glxinfo -B
```

### Ver qué `LD_LIBRARY_PATH` quedó activo

```bash
echo $LD_LIBRARY_PATH
```

### Verificar bibliotecas WSLg

```bash
ls /usr/lib/wsl/lib
```

### Buscar rastros de D3D12

```bash
find /usr/lib64 /usr/lib /usr/lib/wsl/lib -iname '*d3d12*' 2>/dev/null
```

---

## 9. Resultado final

Con esta configuración, **AlmaLinux 9 en WSL2** pasó de:

* `llvmpipe`
* `Accelerated: no`

a:

* `D3D12 (AMD Radeon(TM) Graphics)`
* `Accelerated: yes`

lo que deja el entorno mucho más apto para aplicaciones con OpenGL, Qt y visualización científica.

````

Y si quieres crearlo directo desde la terminal, usa esto:

```bash
cat > README_mesa_3D_pulido.md <<'EOF'
# Mesa 3D acelerado en AlmaLinux 9 sobre WSL2/WSLg

Este documento resume los pasos que funcionaron para habilitar aceleración 3D real en **AlmaLinux 9** corriendo en **WSL2**, usando **WSLg** y el backend **D3D12** de Mesa.

## Problema observado

Al ejecutar:

```bash
glxinfo -B
````

la salida mostraba renderizado por software:

* `OpenGL renderer string: llvmpipe ...`
* `Accelerated: no`

Eso indicaba que WSLg estaba funcionando, pero **sin aceleración por GPU**.

## Causa

La pila Mesa disponible en AlmaLinux 9 no traía el backend `d3d12` operativo para WSLg, por lo que OpenGL/EGL caían en `llvmpipe`/`swrast`.

## Solución

Se compiló **Mesa 24.0.5** manualmente, habilitando explícitamente el driver Gallium `d3d12`.

---

## 1. Instalar dependencias de compilación

Primero, habilitar repositorios necesarios:

```bash
sudo dnf install epel-release dnf-plugins-core -y
sudo dnf config-manager --set-enabled crb
sudo dnf makecache
```

Luego instalar dependencias:

```bash
sudo dnf install -y \
  gcc gcc-c++ meson ninja-build cmake pkgconf-pkg-config \
  python3-mako python3-pyyaml python3-ply \
  libX11-devel libXext-devel libXfixes-devel libdrm-devel \
  libxcb-devel libxshmfence-devel libXrandr-devel \
  wayland-devel wayland-protocols-devel \
  expat-devel zlib-devel elfutils-libelf-devel \
  libglvnd-devel llvm-devel clang-devel \
  bison flex git
```

---

## 2. Descargar Mesa 24.0.5

```bash
cd /usr/local/src
sudo git clone --branch mesa-24.0.5 https://gitlab.freedesktop.org/mesa/mesa.git
cd mesa
```

---

## 3. Configurar la compilación

Se usó `meson` con los drivers mínimos necesarios y habilitando `d3d12`:

```bash
sudo meson setup build \
  --prefix=/usr/local \
  -Dbuildtype=release \
  -Dplatforms=x11,wayland \
  -Dgallium-drivers=swrast,d3d12 \
  -Dvulkan-drivers= \
  -Dllvm=enabled
```

---

## 4. Compilar e instalar

```bash
sudo ninja -C build
sudo ninja -C build install
```

Esto instala la nueva Mesa en `/usr/local`, sin sobrescribir directamente la del sistema.

---

## 5. Ajustar variables de entorno

Para que WSLg use la Mesa recién compilada, se agregaron estas variables al entorno.

### Opción recomendada: sólo en WSL

Agregar esto a `~/.bashrc`:

```bash
if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib:/usr/lib/wsl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
  export GALLIUM_DRIVER=d3d12
fi
```

Luego recargar:

```bash
source ~/.bashrc
```

### Nota sobre `LD_LIBRARY_PATH`

La forma:

```bash
/usr/lib/wsl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
```

es intencional.

* Si `LD_LIBRARY_PATH` está vacío, queda sólo `/usr/lib/wsl/lib`
* Si ya tenía contenido, agrega `:$LD_LIBRARY_PATH`

Así se evita dejar dos puntos seguidos o un `:` sobrante.

---

## 6. Verificación

Ejecutar:

```bash
glxinfo -B
```

La salida correcta ahora debería verse parecida a:

```text
Vendor: Microsoft Corporation
Device: D3D12 (AMD Radeon(TM) Graphics)
Accelerated: yes
```

En el caso validado, la salida fue:

```text
Vendor: Microsoft Corporation
Device: D3D12 (AMD Radeon(TM) Graphics)
Accelerated: yes
OpenGL renderer string: D3D12 (AMD Radeon(TM) Graphics)
```

Eso confirma que WSLg ya está usando aceleración real por GPU.

---

## 7. Observaciones

* El problema no estaba en Windows ni en el driver AMD, sino en la pila Mesa de AlmaLinux 9.
* Compilar Mesa con `-Dgallium-drivers=swrast,d3d12` fue la clave.
* Instalar en `/usr/local` permite mantener separado lo compilado manualmente de los paquetes del sistema.
* Esta solución es especialmente útil en distros WSL donde la Mesa empaquetada no trae soporte `d3d12` funcional.

---

## 8. Comandos útiles de diagnóstico

### Ver OpenGL

```bash
glxinfo -B
```

### Ver qué `LD_LIBRARY_PATH` quedó activo

```bash
echo $LD_LIBRARY_PATH
```

### Verificar bibliotecas WSLg

```bash
ls /usr/lib/wsl/lib
```

### Buscar rastros de D3D12

```bash
find /usr/lib64 /usr/lib /usr/lib/wsl/lib -iname '*d3d12*' 2>/dev/null
```

---

## 9. Resultado final

Con esta configuración, **AlmaLinux 9 en WSL2** pasó de:

* `llvmpipe`
* `Accelerated: no`

a:

* `D3D12 (AMD Radeon(TM) Graphics)`
* `Accelerated: yes`

lo que deja el entorno mucho más apto para aplicaciones con OpenGL, Qt y visualización científica.
