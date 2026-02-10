# Guardian Hub Stack

Complete Docker Compose stack for Guardian Hub - a Raspberry Pi-based network appliance providing network-wide ad blocking, VPN access, DNS privacy, and unified web management.

## Overview

Guardian Hub transforms a Raspberry Pi into a powerful network appliance that provides:

- **Network-wide ad blocking** via Pi-hole
- **Encrypted DNS** via Cloudflared (DNS-over-HTTPS)
- **Remote VPN access** via WireGuard with web UI
- **Reverse proxy** via Nginx Proxy Manager with custom domains
- **Unified dashboard** via Homepage
- **Configuration interface** via Guardian Hub Config UI

## Hardware Requirements

### Recommended
- **Raspberry Pi 5** (4GB or 8GB RAM)
- 64GB microSD card (Class 10 or better)
- Official Raspberry Pi power supply
- Ethernet connection (recommended for stability)

### Minimum
- **Raspberry Pi 4** (4GB RAM minimum)
- 32GB microSD card
- Stable 5V/3A power supply

## Software Requirements

- **OS:** Raspberry Pi OS Lite (64-bit) or Ubuntu Server 22.04+ ARM64
- **Docker:** 24.0+
- **Docker Compose:** 2.0+

### Services Included

| Service | Purpose | Access |
|---------|---------|--------|
| **Pi-hole** | Network-wide ad blocking | http://pihole.guardian.home/admin |
| **Cloudflared** | DNS-over-HTTPS encryption | Background service |
| **WireGuard Easy** | VPN server with web UI | http://wireguard.guardian.home |
| **Nginx Proxy Manager** | Reverse proxy & SSL | http://npm.guardian.home |
| **Homepage** | Unified dashboard | http://homepage.guardian.home |
| **Config UI** | Configuration manager | http://config.guardian.home |

## Architecture
```
┌─────────────────────────────────────────────┐
│          Guardian Hub (Raspberry Pi)        │
├─────────────────────────────────────────────┤
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │   Nginx Proxy Manager (Port 80)      │  │
│  │   Reverse proxy for *.guardian.home  │  │
│  └──────────────────────────────────────┘  │
│                     │                       │
│  ┌──────────────────┴──────────────────┐   │
│  │                                      │   │
│  ▼                  ▼                   ▼   │
│ Config UI      Pi-hole          WireGuard  │
│ :8888          :8053            :51821      │
│                                             │
│           Cloudflared (DNS-over-HTTPS)      │
│                                             │
│           Homepage Dashboard                │
│                                             │
└─────────────────────────────────────────────┘
```

## License

GNU General Public License v3.0 - See [LICENSE](LICENSE)

## Author

Jon Quass - [@jquass](https://github.com/jquass)

## Related Projects

- [GuardianHub](https://github.com/jquass/GuardianHub) - Web-based configuration UI (required)

## Acknowledgments

Built with:
- [Pi-hole](https://pi-hole.net/) - Network-wide ad blocking
- [WireGuard Easy](https://github.com/wg-easy/wg-easy) - WireGuard with web UI
- [Cloudflared](https://github.com/cloudflare/cloudflared) - DNS-over-HTTPS
- [Nginx Proxy Manager](https://nginxproxymanager.com/) - Reverse proxy
- [Homepage](https://gethomepage.dev/) - Application dashboard
