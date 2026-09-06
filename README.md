# 🛡️ Homelab Sentinel: Arquitectura de Acceso Remoto Seguro, Monitorización y Hardening

*Nodo perimetral doméstico basado en **Raspberry Pi 4B** concebido para la administración desatendida y segura desde redes externas hostiles, incorporando túneles VPN redundantes, filtrado DNS, bastionado de claves asimétricas y un pipeline centinela de alertas push en tiempo real a Telegram.*


## 📋 Tabla de Contenidos

- [1. Resumen Ejecutivo y Alcance](#1-resumen-ejecutivo-y-alcance)
- [2. Arquitectura del Sistema](#2-arquitectura-del-sistema)
- [3. Matriz de Componentes y Stack Tecnológico](#3-matriz-de-componentes-y-stack-tecnológico)
- [4. Implementación Técnica Paso a Paso](#4-implementación-técnica-paso-a-paso)
  - [4.1 Acceso Remoto Seguro y Redundancia (WireGuard + Tailscale)](#41-acceso-remoto-seguro-y-redundancia-wireguard--tailscale)
  - [4.2 Bastionado Criptográfico SSH (Claves Ed25519)](#42-bastionado-criptográfico-ssh-claves-ed25519)
  - [4.3 Pipeline de Alertas y Scripting (Telegram Integration)](#43-pipeline-de-alertas-y-scripting-telegram-integration)
  - [4.4 Integración de Fail2ban con Telegram](#44-integración-de-fail2ban-con-telegram)
  - [4.5 Monitorización Contenerizada con Docker Compose](#45-monitorización-contenerizada-con-docker-compose)
- [5. Pruebas de Validación y Verificación](#5-pruebas-de-validación-y-verificación)
- [6. Consideraciones de Seguridad y Buenas Prácticas](#6-consideraciones-de-seguridad-y-buenas-prácticas)
- [7. Licencia](#7-licencia)

---

## 1. Resumen Ejecutivo y Alcance

Este proyecto documenta el diseño, despliegue e implementación de un nodo perimetral doméstico basado en **Raspberry Pi 4B**, concebido como servidor de acceso remoto seguro, filtrado DNS, monitorización activa y bastionado de servicios.

El objetivo central es permitir la administración desatendida y segura del entorno local desde redes externas hostiles, garantizando:

**Acceso cifrado punto a punto:** Túnel principal WireGuard respaldado por DuckDNS para IPs dinámicas, con topología de respaldo mediante malla Tailscale (inmunidad a CG-NAT y puertos bloqueados).
**Filtrado DNS y privacidad perimetral:** Integración local con Pi-hole para el bloqueo de telemetría y publicidad en todos los clientes tunelizados.
**Bastionado de autenticación:** Acceso administrativo mediante claves asimétricas `Ed25519`, desactivación total de contraseñas y defensa activa reactiva con Fail2ban.
**Telemetría y observabilidad:** Alertas push en tiempo real hacia Telegram para accesos, intentos de intrusión y rearranques, complementado con sondas activas en Uptime Kuma mediante Docker.

---

## 2. Arquitectura del Sistema

```text
       ┌─────────────────────────────────────────────────────────────┐
       │                    Dispositivos Cliente                     │
       │        (Mac Air / PC Sobremesa / Dispositivos Móviles)      │
       └──────────────────────────────┬──────────────────────────────┘
                                      │
              ┌───────────────────────┴───────────────────────┐
              │                                               │
              ▼ (Túnel Principal UDP)                         ▼ (Malla Respaldo / CG-NAT)
       ┌──────────────┐                               ┌──────────────┐
       │  WireGuard   │                               │  Tailscale   │
       │ (w/ DuckDNS) │                               │  (Mesh Peer) │
       └──────┬───────┘                               └───────┬──────┘
              │                                               │
              └───────────────────────┬───────────────────────┘
                                      │ Enlace Cifrado Local
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Raspberry Pi 4B                                │
│                                                                             │
│  ┌───────────────────────┐  ┌──────────────────────┐  ┌──────────────────┐  │
│  │   ssh-failed-watcher  │  │   ssh-login-alert    │  │   systemd boot   │  │
│  │    (journalctl log)   │  │  (/etc/profile.d)    │  │  (systemd unit)  │  │
│  └───────────┬───────────┘  └──────────┬───────────┘  └─────────┬────────┘  │
│              │                         │                        │           │
│              └──────────────────┬──────┴────────────────────────┘           │
│                                 │                                           │
│  ┌───────────────────────┐      ▼                                           │
│  │  Fail2ban Intrusion   │──▶ telegram-notify ──┐                           │
│  │  (iptables jail/ban)  │    (/usr/local/bin)  │                           │
│  └───────────────────────┘                      │                           │
│                                                 │                           │
│  ┌───────────────────────────────────────────┐  │                           │
│  │  Servicios Base & Contenedores Docker     │  │                           │
│  │  - Pi-hole: Filtrado DNS local (puerto 53)│  │                           │
│  │  - Uptime Kuma: Sondas ICMP / DNS         │──┼───────────────────────────┼──┐
│  └───────────────────────────────────────────┘  │                           │  │
└─────────────────────────────────────────────────┼───────────────────────────┘  │
                                                  │                              │
                                                  │ HTTPS POST API               │
                                                  ▼                              ▼
                                       ┌─────────────────────────────────────────┐
                                       │         Telegram Bot API / Chat         │
                                       │          Notificaciones Push            │
                                       └─────────────────────────────────────────┘
```

---

## 3. Matriz de Componentes y Stack Tecnológico

| Capa | Componente | Función Técnica | Justificación |
| :--- | :--- | :--- | :--- |
| **Acceso Remoto** | `WireGuard` | Túnel VPN de capa 3 | Cifrado ChaCha20-Poly1305, mínimo consumo de CPU en SoC ARM y latencia negligible. |
| **Redundancia** | `Tailscale` | VPN mesh de emergencia | Conectividad segura mediante NAT Traversal (DERP) si la IP dinámica o el reenvío de puertos falla. |
| **Resolución Dinámica** | `DuckDNS` | Sincronización DDNS | Mapeo continuo de la dirección WAN dinámica del ISP hacia el endpoint WireGuard. |
| **Filtrado DNS** | `Pi-hole` | DNS Sinkhole perimetral | Resolución local (`127.0.0.1:53`) con bloqueo de telemetría y dominios de rastreo para los clientes VPN. |
| **Acceso de Gestión** | `OpenSSH` | Consola administrativa | Claves asimétricas `Ed25519` exclusivas, eliminación de vector por fuerza bruta (`PasswordAuthentication no`). |
| **Defensa Activa** | `Fail2ban` | Detección y bloqueo IPS | Monitorización de fallos de autenticación con aislamiento dinámico de IPs atacantes vía Netfilter/iptables. |
| **Event Watcher** | `Bash Daemon` | Vigilancia proactiva | Análisis en flujo continuo (`journalctl -u ssh -f`) de accesos fallidos antes del umbral de baneo. |
| **Monitorización** | `Uptime Kuma` | Observabilidad de nodos | Despliegue contenerizado en Docker; sondeo ICMP/DNS de hosts internos y canal WAN con webhook nativo a Telegram. |

---

## 4. Implementación Técnica Paso a Paso

### 4.1 Acceso Remoto Seguro y Redundancia (WireGuard + Tailscale)

1. **Configuración del Servidor WireGuard (`/etc/wireguard/wg0.conf`):**

   ```ini
   [Interface]
   Address = 10.6.0.1/24
   ListenPort = 51820
   PrivateKey = <SERVER_PRIVATE_KEY>
   PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
   PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

   [Peer]
   PublicKey = <CLIENT_PUBLIC_KEY>
   AllowedIPs = 10.6.0.2/32
   ```

2. **Perfil del Cliente (`client.conf`):**

   ```ini
   [Interface]
   PrivateKey = <CLIENT_PRIVATE_KEY>
   Address = 10.6.0.2/24
   DNS = 10.6.0.1

   [Peer]
   PublicKey = <SERVER_PUBLIC_KEY>
   Endpoint = tu-subdominio.duckdns.org:51820
   AllowedIPs = 0.0.0.0/0, ::/0
   PersistentKeepalive = 25
   ```

3. **Nodo de Respaldo Tailscale:**

   ```bash
   sudo tailscale up --advertise-routes=192.168.1.0/24 --accept-dns=false
   ```

---

### 4.2 Bastionado Criptográfico SSH (Claves Ed25519)

1. **Generación del par de claves en el cliente:**

   ```bash
   ssh-keygen -t ed25519 -C "admin-nodo"
   ```

2. **Despliegue de la clave pública en `~/.ssh/authorized_keys`:**

   ```bash
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... admin-nodo" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

3. **Hardening en `/etc/ssh/sshd_config`:**

   ```ini
   PubkeyAuthentication yes
   PasswordAuthentication no
   PermitEmptyPasswords no
   X11Forwarding no
   ```

4. **Validación de sintaxis y reinicio del servicio:**

   ```bash
   sudo sshd -t && sudo systemctl restart ssh
   ```

---

### 4.3 Pipeline de Alertas y Scripting (Telegram Integration)

> [!NOTE]
> Todas las notificaciones del sistema convergen en un script emisor modular que interactúa directamente con la Bot API de Telegram mediante peticiones HTTPS POST.

#### 1. Conector Principal Telegram (`/usr/local/bin/telegram-notify`)

```bash
#!/bin/bash
TOKEN="<TELEGRAM_BOT_TOKEN>"
CHAT_ID="<TELEGRAM_CHAT_ID>"
MENSAJE="$1"

if [ -n "$MENSAJE" ]; then
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "text=${MENSAJE}" \
    -d "parse_mode=HTML" > /dev/null
fi
```

*Asignación de permisos de ejecución:*
```bash
sudo chmod +x /usr/local/bin/telegram-notify
```

#### 2. Alerta de Inicio de Sesión Interactivo (`/etc/profile.d/ssh-telegram-alert.sh`)

Ubicado en la ruta de inicio de perfil global para interceptar cualquier sesión SSH interactiva iniciada:

```bash
if [ -n "$SSH_CLIENT" ]; then
  IP=$(echo "$SSH_CLIENT" | awk '{print $1}')
  FECHA=$(date '+%d/%m/%Y %H:%M:%S')
  /usr/local/bin/telegram-notify "🚨 <b>Acceso SSH Detectado</b>%0AUsuario: <code>$USER</code>%0AIP origen: <code>$IP</code>%0AFecha: $FECHA"
fi
```

#### 3. Centinela de Intentos Fallidos (`/usr/local/bin/ssh-failed-watcher.sh`)

Daemon ejecutado en streaming continuo para detectar contraseñas incorrectas o intentos de usuarios inexistentes en tiempo real:

```bash
#!/bin/bash
journalctl -u ssh -f -n 0 | while read -r line; do
  if echo "$line" | grep -E -q "Failed password|Invalid user"; then
    IP=$(echo "$line" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1)
    USER_TRY=$(echo "$line" | sed -n -e 's/.*Invalid user \([^ ]*\).*/\1/p' -e 's/.*Failed password for \([^ ]*\).*/\1/p')
    FECHA=$(date '+%d/%m/%Y %H:%M:%S')

    /usr/local/bin/telegram-notify "⚠️ <b>Intento SSH Fallido</b>%0AUsuario probado: <code>${USER_TRY:-desconocido}</code>%0AIP origen: <code>$IP</code>%0AFecha: $FECHA"
  fi
done
```

#### 4. Notificación de Rearme / Reboot (`/etc/systemd/system/telegram-boot.service`)

Unidad Systemd de tipo `oneshot` disparada tras confirmar el enlace de red operativo:

```ini
[Unit]
Description=Notificación de Arranque de Sistema por Telegram
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/telegram-notify "🟢 <b>Raspberry Pi Operativa</b>%0AEl sistema ha completado el arranque y la red está en línea."

[Install]
WantedBy=multi-user.target
```

*Habilitar el servicio systemd:*
```bash
sudo systemctl daemon-reload
sudo systemctl enable telegram-boot.service
```

---

### 4.4 Integración de Fail2ban con Telegram

1. **Acción de baneo personalizada (`/etc/fail2ban/action.d/telegram.conf`):**

   ```ini
   [Definition]
   actionban = /usr/local/bin/telegram-notify "⛔ <b>Fail2ban: IP Bloqueada</b>%0ASe ha baneado la IP: <code><ip></code> tras reiterados intentos fallidos contra <b><name></b>."
   ```

2. **Jail SSH en `/etc/fail2ban/jail.local`:**

   ```ini
   [DEFAULT]
   bantime  = 1h
   findtime = 10m
   maxretry = 5

   [sshd]
   enabled = true
   port    = ssh
   logpath = %(sshd_log)s
   backend = %(syslog_backend)s
   action  = %(action_)s
             telegram
   ```

---

### 4.5 Monitorización Contenerizada con Docker Compose

Despliegue declarativo de **Uptime Kuma** para observabilidad del nodo y red interna:

```yaml
version: '3.8'

services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: always
    ports:
      - "3001:3001"
    volumes:
      - uptime-kuma-data:/app/data
    security_opt:
      - no-new-privileges:true

volumes:
  uptime-kuma-data:
    name: uptime-kuma-data
```

#### Sondas de Monitorización Configuradas:
**PC Sobremesa / LAN:** Monitor ICMP Ping periódico hacia la IP interna de la LAN.
**DNS / Pi-hole:** Sonda de resolución DNS hacia `127.0.0.1:53` verificando respuesta ante peticiones de dominio.
**Gateway WAN:** Sonda ICMP hacia `1.1.1.1` para alertar caídas del ISP o cortes de fibra.
**Canal de Alerta:** Webhook nativo configurado hacia Telegram Bot API.

---

## 5. Pruebas de Validación y Verificación

| Vector de Prueba | Acción Ejecutada | Resultado Obtenido | Estado |
| :--- | :--- | :--- | :---: |
| **Acceso Remoto WireGuard** | Conexión externa mediante cliente WireGuard vía DuckDNS | Túnel levantado, IP remota asignada y tráfico DNS filtrado por Pi-hole | ✅ Superado |
| **Fallback Redundante** | Corte deliberado del puerto 51820 del router | Conexión inmediata mediante Tailscale a través de la ruta anunciada | ✅ Superado |
| **Autenticación SSH Válida** | Login SSH utilizando llave criptográfica `Ed25519` | Notificación instantánea en Telegram con IP de origen y marca temporal | ✅ Superado |
| **Intento de Intrusión SSH** | Conexión fallida forzada con credenciales erróneas | Alerta proactiva en Telegram reportando usuario e IP atacante | ✅ Superado |
| **Ataque de Fuerza Bruta** | Ráfaga de 5 intentos fallidos superando umbral | Baneo por Fail2ban, corte en iptables y notificación push | ✅ Superado |
| **Corte de Corriente / Reboot** | Ejecución de reinicio del sistema (`sudo reboot`) | Mensaje en Telegram notificando disponibilidad tras enlace de red | ✅ Superado |
| **Degradación de Servicios** | Caída inducida de host o fallo de resolución DNS | Notificación Push de servicio caído emitida por Uptime Kuma | ✅ Superado |

---

## 6. Consideraciones de Seguridad y Buenas Prácticas

> [!IMPORTANT]
> **Gestión de Secretos y Permisos**
> Los tokens de API y claves privadas deben residir exclusivamente en el host local. El script `/usr/local/bin/telegram-notify` almacena el token del bot y debe pertenecer a `root:root` con permisos restringidos:
> ```bash
> sudo chown root:root /usr/local/bin/telegram-notify
> sudo chmod 700 /usr/local/bin/telegram-notify
> ```

> [!TIP]
> **Aislamiento de Perfiles VPN**
> Los perfiles de cliente WireGuard deben configurarse con claves asimétricas únicas por dispositivo, evitando el reuso de pares criptográficos para facilitar la revocación individual en caso de pérdida de un terminal.

> [!NOTE]
> **Auditoría de Claves Autorizadas SSH**
> Cada clave pública autorizada puede ser auditada y verificada mediante su huella digital ejecutando:
> ```bash
> ssh-keygen -l -f ~/.ssh/authorized_keys
> ```

---

## 7. Licencia

Distribuido bajo la **Licencia MIT**. Consulta el archivo `LICENSE` para obtener más información.
