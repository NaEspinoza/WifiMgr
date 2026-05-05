# wifimgr 📡

> Gestor interactivo de configuración WiFi para Linux — TUI basado en terminal.

```
 ██╗    ██╗██╗███████╗██╗███╗   ███╗ ██████╗ ██████╗
 ██║    ██║██║██╔════╝██║████╗ ████║██╔════╝ ██╔══██╗
 ██║ █╗ ██║██║█████╗  ██║██╔████╔██║██║  ███╗██████╔╝
 ██║███╗██║██║██╔══╝  ██║██║╚██╔╝██║██║   ██║██╔══██╗
 ╚███╔███╔╝██║██║     ██║██║ ╚═╝ ██║╚██████╔╝██║  ██║
  ╚══╝╚══╝ ╚═╝╚═╝     ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝
```

**Autor:** Nazareno Espinoza  
**Licencia:** MIT  
**Compatibilidad:** Cualquier distribución Linux — sin importar distro ni hardware

---

## ¿Qué es wifimgr?

`wifimgr` es un script Bash con interfaz TUI (Text User Interface) interactiva que permite gestionar por completo la configuración de conexiones WiFi en Linux desde la terminal, sin necesidad de recordar comandos ni editar archivos de configuración manualmente.

Opera sobre backends estándar (`nmcli`, `iproute2`, `iw`) y se adapta automáticamente al entorno disponible, funcionando tanto en sistemas con NetworkManager como en instalaciones mínimas.

---

## Características

| Módulo | Descripción |
|--------|-------------|
| 📊 Estado de interfaz | IP, MAC, gateway, DNS, SSID activo, nivel de señal, driver y MTU en una sola pantalla |
| 🌐 Configuración IP | Cambio entre DHCP automático e IP estática (con prefijo CIDR, gateway y DNS) |
| 🔀 Gestión de MAC | Generación aleatoria (preservando OUI del fabricante), MAC completamente aleatoria, manual o restauración de la MAC de hardware |
| 📡 Escaneo de redes | Lista de redes disponibles con SSID, señal, canal y tipo de seguridad |
| 🔗 Conexión a redes | Conexión asistida con soporte de perfiles guardados y redes abiertas o protegidas |
| ✂️ Desconexión | Desconexión limpia de la red activa |
| 🔍 Configuración DNS | Presets para Cloudflare, Google, Quad9, AdGuard, OpenDNS o DNS personalizado |
| 📏 Control de MTU | Presets para Ethernet estándar, PPPoE, VPN, Jumbo frames, o valor libre |
| 🛡️ Modo Monitor | Toggle entre modo managed y monitor (útil para auditoría y análisis de paquetes) |
| 🏓 Test de conectividad | Ping al gateway, servidor DNS, internet o un host personalizado |
| 💾 Perfiles guardados | Visualizar, eliminar y exportar perfiles WiFi de NetworkManager |
| 🔄 Reinicio de red | Reinicio de interfaz, NetworkManager o ambos |
| ℹ️ Info del sistema | Detección de herramientas instaladas, kernel, distro y módulos WiFi cargados |

---

## Requisitos

### Dependencias mínimas (presentes en cualquier Linux)

```
bash >= 4.0
ip       (paquete: iproute2)
awk
grep
```

### TUI — una de las dos (normalmente ya instalada)

```
whiptail   →  Debian/Ubuntu: apt install whiptail
              Arch:          pacman -S libnewt
              RHEL/Fedora:   dnf install newt

dialog     →  apt/dnf/pacman install dialog  (fallback automático)
```

### Opcionales (amplían funcionalidad)

| Herramienta | Función adicional que habilita |
|-------------|-------------------------------|
| `nmcli` + NetworkManager | Gestión de perfiles, conexión asistida, DNS persistente |
| `iw` | Modo monitor, escaneo avanzado, información de señal |
| `ethtool` | Lectura de la MAC original de hardware |
| `macchanger` | Fallback para cambio de MAC en kernels restrictivos |
| `dhclient` / `dhcpcd` | Solicitud DHCP sin NetworkManager |
| `airmon-ng` | Limpieza de procesos antes de activar modo monitor |

---

## Instalación

```bash
# Clonar o descargar el script
git clone https://github.com/nazareno-espinoza/wifimgr
cd wifimgr

# Dar permisos de ejecución
chmod +x wifimgr.sh

# Ejecutar (se recomienda root para todas las funciones)
sudo ./wifimgr.sh
```

O directamente sin clonar:

```bash
curl -O https://raw.githubusercontent.com/nazareno-espinoza/wifimgr/main/wifimgr.sh
chmod +x wifimgr.sh
sudo ./wifimgr.sh
```

---

## Uso

### Ejecución básica

```bash
sudo ./wifimgr.sh
```

> Ejecutar como root garantiza acceso completo a todas las funciones (cambio de MAC, modo monitor, configuración de IP, etc.).  
> Sin root, algunas operaciones solicitarán `sudo` de forma puntual.

### Navegación en el TUI

```
Flechas ↑↓     Moverse entre opciones
Enter          Seleccionar / Confirmar
Tab            Alternar entre botones (OK / Cancel)
Escape         Volver al menú anterior
```

---

## Ejemplos de uso frecuente

### Cambiar a IP estática

1. Ejecutar `sudo ./wifimgr.sh`
2. Seleccionar **2 — Cambiar dirección IP**
3. Elegir interfaz WiFi
4. Seleccionar **IP estática**
5. Ingresar: IP, prefijo CIDR (ej. `24`), gateway y DNS
6. Confirmar — se aplica inmediatamente (persiste si usa NetworkManager)

### Randomizar la MAC antes de conectarse

1. Seleccionar **3 — Cambiar dirección MAC**
2. Elegir interfaz
3. Seleccionar **MAC completamente aleatoria**
4. Confirmar

> El script asegura que el bit de unicast esté correctamente configurado (bit 0 del primer octeto = 0).

### Activar modo monitor para auditoría

1. Seleccionar **9 — Modo Monitor / Managed**
2. Elegir interfaz
3. Seleccionar **Cambiar a modo Monitor**
4. El script detiene procesos interferentes automáticamente (`airmon-ng check kill` si está disponible)

### Cambiar DNS a Cloudflare

1. Seleccionar **7 — Configurar DNS**
2. Elegir **Cloudflare — 1.1.1.1 / 1.0.0.1**
3. Seleccionar interfaz — se aplica en NetworkManager o en `/etc/resolv.conf`

---

## Compatibilidad de distribuciones

| Distribución | Estado |
|-------------|--------|
| Debian / Ubuntu / Mint | ✅ Completa |
| Arch Linux / Manjaro | ✅ Completa |
| Fedora / RHEL / CentOS | ✅ Completa |
| openSUSE | ✅ Completa |
| Alpine Linux | ✅ Funcional (sin NM, usa iproute2) |
| Kali Linux / Parrot | ✅ Completa + modo monitor |
| Raspbian / Raspberry Pi OS | ✅ Completa |
| Sistemas embebidos (BusyBox) | ⚠️ Parcial (requiere bash y whiptail) |

---

## Arquitectura del script

```
wifimgr.sh
├── Detección de TUI backend        (whiptail → dialog)
├── Helpers TUI                     (tui_msg, tui_menu, tui_input, ...)
├── Detección de interfaces         (iw dev / sysfs /sys/class/net)
├── Detección de backend de red     (nmcli disponible + NM activo)
│
├── Módulos de función
│   ├── show_status()
│   ├── change_ip()
│   ├── change_mac()
│   ├── scan_networks()
│   ├── connect_network()
│   ├── disconnect_network()
│   ├── configure_dns()
│   ├── change_mtu()
│   ├── toggle_monitor_mode()
│   ├── test_connectivity()
│   ├── manage_profiles()
│   ├── restart_network()
│   └── system_info()
│
└── main_menu()                     (bucle principal TUI)
```

**Lógica de fallback por función:**

```
Cambio de IP  →  nmcli con modify  →  ip addr add  →  error informativo
Cambio de MAC →  ip link set addr  →  macchanger   →  error informativo
DNS           →  nmcli con modify  →  /etc/resolv.conf directo
Escaneo       →  nmcli dev wifi    →  iw dev scan
```

---

## Notas de seguridad

- El cambio de MAC es temporal y se revierte al reiniciar, a menos que se configure persistencia en NetworkManager.
- El modo monitor puede desconectar la interfaz de la red activa.
- Las contraseñas WiFi ingresadas se pasan directamente a `nmcli` y no se almacenan en el script.
- En sistemas con `/etc/resolv.conf` gestionado por `systemd-resolved` o `resolvconf`, los cambios de DNS manuales pueden ser sobreescritos. Se recomienda usar la opción vía nmcli.

---

## Solución de problemas

**"No se encontraron interfaces WiFi"**  
→ Verificar que el driver esté cargado: `lsmod | grep -E 'mac80211|iwl|ath|rtl'`  
→ Verificar: `ip link show`

**"No se pudo cambiar la MAC"**  
→ Instalar macchanger: `apt install macchanger`  
→ Algunos drivers no permiten cambio de MAC con la interfaz activa — el script baja y sube la interfaz automáticamente.

**"Esta función requiere NetworkManager"**  
→ Instalar: `apt install network-manager` / `pacman -S networkmanager`  
→ Activar: `sudo systemctl enable --now NetworkManager`

**TUI no se muestra correctamente**  
→ Verificar tamaño de terminal (mínimo 80×24 recomendado)  
→ Instalar whiptail: `apt install whiptail`

---

## Contribuciones

Las contribuciones son bienvenidas. Para reportar un bug o proponer una mejora, abrir un issue en el repositorio indicando:

- Distribución y versión del kernel
- Salida de `bash --version`
- Herramientas disponibles (ejecutar opción 13 del menú)
- Descripción del comportamiento observado vs esperado

---

## Licencia

MIT License — libre para uso, modificación y distribución con atribución.

---

<div align="center">

Desarrollado por **Nazareno Espinoza**

*"La terminal es la interfaz más honesta que existe."*

</div>
