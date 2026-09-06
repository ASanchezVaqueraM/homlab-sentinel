# Red de Acceso Remoto Seguro (VPN & DNS)

Esta carpeta contiene las plantillas para la infraestructura de acceso remoto cifrado al homelab.

## 1. Túnel Principal: WireGuard + DuckDNS
* **Cifrado:** ChaCha20-Poly1305 / Curve25519.
* **Resolución dinámica:** DuckDNS actualiza la IP pública dinámica del router ante cambios de WAN.
* **DNS Privado:** Todo el tráfico VPN resuelve consultas a través de la instancia local de Pi-hole (`10.6.0.1:53`), asegurando navegación sin rastreadores ni publicidad.

## 2. Red de Respaldo: Tailscale Mesh
Para garantizar acceso ante incidencias en la apertura de puertos del router, CG-NAT o cortafuegos restrictivos en redes públicas:
* Despliegue de nodo Tailscale en la Raspberry Pi con reenvío de subred local:
  ```bash
  sudo tailscale up --advertise-routes=192.168.1.0/24 --accept-dns=false
