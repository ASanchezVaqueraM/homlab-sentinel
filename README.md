# Homelab Sentinel: Arquitectura de Acceso Remoto Seguro, Monitorización y Hardening

## 1. Resumen Ejecutivo y Alcance

Este proyecto documenta el diseño, despliegue e implementación de un nodo perimetral doméstico basado en **Raspberry Pi 4B**, concebido como servidor de acceso remoto seguro, filtrado DNS, monitorización activa y bastionado de servicios.

El objetivo central es permitir la administración desatendida y segura del entorno local desde redes externas hostiles, garantizando:
* **Acceso cifrado punto a punto:** Túnel principal WireGuard respaldado por DuckDNS para IPs dinámicas, con topología de respaldo mediante malla Tailscale (inmunidad a CG-NAT y puertos bloqueados).
* **Filtrado DNS y privacidad perimetral:** Integración local con Pi-hole para el bloqueo de telemetría y publicidad en todos los clientes tunelizados.
* **Bastionado de autenticación:** Acceso administrativo mediante claves asimétricas `Ed25519`, desactivación total de contraseñas y defensa activa reactiva con Fail2ban.
* **Telemetría y observabilidad:** Alertas push en tiempo real hacia Telegram para accesos, intentos de intrusión y rearranques, complementado con sondas activas en Uptime Kuma mediante Docker.

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
## 3. Matriz de Componentes y Stack Tecnológico

| Capa | Componente | Función Técnica | Justificación |
| :--- | :--- | :--- | :--- |
| Acceso Remoto | **WireGuard** | Túnel VPN de capa 3 | Cifrado ChaCha20-Poly1305, mínimo consumo de CPU en SoC ARM y latencia negligible. |
| Redundancia | **Tailscale** | VPN mesh de emergencia | Conectividad segura mediante NAT Traversal (DERP) si la IP dinámica o el reenvío de puertos falla. |
| Resolución Dinámica | **DuckDNS** | Sincronización DDNS | Mapeo continuo de la dirección WAN dinámica del ISP hacia el endpoint WireGuard. |
| Filtrado DNS | **Pi-hole** | DNS Sinkhole perimetral | Resolución local (127.0.0.1:53) con bloqueo de telemetría y dominios de rastreo para los clientes VPN. |
| Acceso de Gestión | **OpenSSH** | Consola administrativa | Claves asimétricas Ed25519 exclusivas, eliminación de vector por fuerza bruta (PasswordAuthentication no). |
| Defensa Activa | **Fail2ban** | Detección y bloqueo IPS | Monitorización de fallos de autenticación con aislamiento dinámico de IPs atacantes vía Netfilter/iptables. |
| Event Watcher | **Bash Daemon** | Vigilancia proactiva | Análisis en flujo continuo (journalctl -u ssh -f) de accesos fallidos antes del umbral de baneo. |
| Monitorización | **Uptime Kuma** | Observabilidad de nodos | Despliegue contenerizado en Docker; sondeo ICMP/DNS de hosts internos y canal WAN con webhook nativo a Telegram |

---

## 4. Implementación Técnica Paso a Paso

### 4.1. Hardening Criptográfico SSH (Claves Ed25519)

Se descarta el uso tradicional de contraseñas para erradicar ataques de fuerza bruta y diccionarios automatizados:

1. **Generación de pares de claves asimétricas en clientes:**
   ```bash
   ssh-keygen -t ed25519 -C "alvaro-dispositivo"
   
2. **Despliegue de la clave pública en el servidor (`~/.ssh/authorized_keys`):**
   ```bash
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... alvaro-dispositivo" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```
3. **Bloqueo en `/etc/ssh/sshd_config`:**
   ```ini
   PubkeyAuthentication yes
   PasswordAuthentication no
   PermitEmptyPasswords no
   X11Forwarding no
   ```
4. **Reinicio seguro tras comprobación de sintaxis:**
   ```bash
   sudo sshd -t && sudo systemctl restart ssh
   ```

---

### 4.2. Conector Central de Notificaciones (`telegram-notify`)

Script modular en `/usr/local/bin/telegram-notify` con permisos `755`:

```bash
#!/bin/bash
TOKEN="<TELEGRAM_BOT_TOKEN>"
CHAT_ID="<TELEGRAM_CHAT_ID>"
MENSAJE="$1"

if [ -n "$MENSAJE" ]; then
  curl -s -X POST "[https://api.telegram.org/bot$](https://api.telegram.org/bot$){TOKEN}/sendMessage" \
       -d "chat_id=${CHAT_ID}" \
       -d "text=${MENSAJE}" \
       -d "parse_mode=HTML" > /dev/null
fi
```

---

### 4.3. Notificación de Sesiones SSH Exitosas

Ubicado en `/etc/profile.d/ssh-telegram-alert.sh` para interceptar toda sesión interactiva abierta:

```bash
if [ -n "$SSH_CLIENT" ]; then
  IP=$(echo "$SSH_CLIENT" | awk '{print $1}')
  FECHA=$(date '+%d/%m/%Y %H:%M:%S')
  /usr/local/bin/telegram-notify "🚨 <b>Acceso SSH Detectado</b>%0AUsuario: <code>$USER</code>%0AIP origen: <code>$IP</code>\%0AFecha:$FECHA"
fi
```

---

### 4.4. Centinela de Intentos de Acceso Fallidos (`ssh-failed-watcher`)

Servicio en streaming para interceptar contraseñas incorrectas o usuarios inexistentes en tiempo real:

* **Script ejecutable (`/usr/local/bin/ssh-failed-watcher.sh`):**
  ```bash
  #!/bin/bash
  journalctl -u ssh -f -n 0 | while read -r line; do
    if echo "$line" | grep -E -q "Failed password|Invalid user"; then
      IP=$(echo "$line" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1)
      USER_TRY=$(echo "$line" | sed -n -e 's/.*Invalid user \([^ ]*\).*/\1/p' -e 's/.*Failed password for \([^ ]*\).*/\1/p')
      FECHA=$(date '+%d/%m/%Y %H:%M:%S')

      /usr/local/bin/telegram-notify "⚠️ <b>Intento SSH Fallido</b>%0AUsuario probado: <code>${USER_TRY:-desconocido}</code>%0AIP origen: <code>$IP</code>\%0AFecha:$FECHA"
    fi
  done

---

### 4.5. Alerta de Rearranque del Sistema (Cortes de Luz / Reboots)

Unidad Systemd de tipo oneshot (/etc/systemd/system/telegram-boot.service) disparada tras confirmar enlace de red:
Ini, TOML
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

---

### 4.6. Integración de Fail2ban con Telegram

1. **Acción de bloqueo (`/etc/fail2ban/action.d/telegram.conf`):**
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

### 4.7. Monitorización Continua con Uptime Kuma en Docker

Despliegue contenerizado y persistente:

```bash
docker run -d \
  --name uptime-kuma \
  --restart always \
  -p 3001:3001 \
  -v uptime-kuma:/app/data \
  louislam/uptime-kuma:1
```

* **Sondas configuradas:**
  * **PC Sobremesa:** Monitor ICMP Ping cada 60 s hacia la IP interna de la LAN.
  * **DNS / Pi-hole:** Sonda DNS hacia `127.0.0.1:53` verificando resolución de dominios en tiempo y forma.
  * **Internet Gateway / WAN:** Monitor ICMP Ping hacia `1.1.1.1` para detección de caídas de fibra o corte de ISP.
* **Canal de alerta:** Webhook nativo a la API de Telegram con el mismo bot y chat ID.

---

## 5. Pruebas de Validación y Verificación

| Escenario de Prueba | Acción Ejecutada | Resultado Esperado en Telegram | Estado |
| :--- | :--- | :--- | :---: |
| **Inicio de Sesión Autorizado** | Conexión SSH con clave Ed25519 desde Mac/PC | Mensaje con usuario, IP origen y timestamp exacto | ✅ Superado |
| **Ataque / Error de Contraseña** | `ssh baduser@<ip_servidor>` con credenciales erróneas | Alerta instantánea reflejando usuario probado e IP | ✅ Superado |
| **Fuerza Bruta Persistente** | 5 intentos erróneos consecutivos | Notificación de ban de Fail2ban + IP aislada en iptables | ✅ Superado |
| **Reinicio / Corte Eléctrico** | Ejecución de `sudo reboot` | Mensaje de arranque en cuanto la red sincroniza | ✅ Superado |
| **Caída de Host / Servicio** | Apagado de equipo sobremesa o desconexión DNS | Notificación Push de caída emitida por Uptime Kuma | ✅ Superado |

---

## 6. Consideraciones de Seguridad y Buenas Prácticas

1. **Gestión de Secretos:** El archivo `/usr/local/bin/telegram-notify` contiene el token del bot; debe pertenecer a `root:root` con permisos `700` o `750` para evitar lecturas por usuarios sin privilegios.
2. **Rotación y Auditoría de Claves:** Para dar de baja un cliente comprometido o extraviado, basta con eliminar su línea en `~/.ssh/authorized_keys`.
3. **Huella Criptográfica:** Cada clave pública autorizada puede ser verificada mediante su huella digital ejecutando:
   ```bash
   ssh-keygen -l -f ~/.ssh/authorized_keys
   ```

---

## 7. Licencia y Autoría

* **Autor:** Proyecto Personal de Seguridad y Administración de Sistemas
* **Licencia:** MIT License
