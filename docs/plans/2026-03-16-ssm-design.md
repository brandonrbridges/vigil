# Vigil — Server Monitor

## Overview

A native macOS app (Tahoe / macOS 26) with liquid glass UI for monitoring and managing multiple Hetzner servers. Connect via SSH, view real-time metrics, manage Docker containers, browse files over SFTP, and drop into a terminal — all from one window.

## Platform & Tech Stack

- **Platform:** macOS 26 (Tahoe) — SwiftUI with liquid glass materials
- **Language:** Swift 6, strict concurrency
- **SSH/SFTP:** Citadel (built on SwiftNIO SSH)
- **Terminal:** SwiftTerm (embedded terminal emulator)
- **Charts:** Swift Charts (Apple)
- **Storage:** macOS Keychain (credentials) + local JSON (server configs)
- **Minimum deployment:** macOS 26

## Architecture

### Three Layers

1. **Connection Layer** — manages SSH/SFTP sessions via Citadel. One persistent connection per active server, multiplexed for metrics polling, terminal sessions, and file transfers. Credentials stored in macOS Keychain, server metadata in `~/Library/Application Support/Vigil/servers.json`.

2. **Monitoring Layer** — polls each server on 5–10 second intervals. Executes remote commands over SSH and parses output into Swift models. Each server has its own polling actor to avoid blocking.

3. **UI Layer** — SwiftUI with liquid glass. Sidebar for server list, tabbed main area per server.

### Data Flow

```
User adds server
  → Citadel authenticates (password or SSH key)
  → Persistent connection established
  → Polling actor starts collecting metrics
  → @Observable models updated
  → SwiftUI views react
```

## Welcome Screen & Server Management

### First Launch

Centered liquid glass card with:
- **Server IP** text field (with port, defaulting to 22)
- **Username** text field (defaulting to `root`)
- **Authentication method** — segmented control: Password | SSH Key
  - Password: secure text field
  - SSH Key: file picker, auto-detects keys in `~/.ssh/`
- **Nickname** — optional friendly name (e.g. "Production API")
- **Connect** button — tests the connection before saving

### Subsequent Launches

Sidebar shows saved servers with:
- Nickname + IP
- Status indicator (green/red dot, checked on launch)
- Right-click to edit or remove

"Add Server" button at the bottom opens the same form as a sheet.

### SSH Key Auto-Detection

1. Scan `~/.ssh/` for private keys (`id_ed25519`, `id_rsa`, `id_ecdsa`)
2. Filter out `.pub` files
3. Auto-select if only one found, dropdown if multiple

## App Layout

```
+------------------+--------------------------------------------+
|                  | [ Dashboard | Docker | Terminal | Files ]   |
|  Server List     |                                            |
|                  |                                            |
|  > Prod API      |        Active Tab Content                  |
|    Staging DB    |                                            |
|    Dev Box       |                                            |
|                  |                                            |
|  [+ Add Server]  |                                            |
+------------------+--------------------------------------------+
```

## Tab Details

### Dashboard

Liquid glass cards in a responsive grid:

| Card | Data Source | Display |
|------|-----------|---------|
| CPU | `top -bn1` | Gauge + percentage |
| Memory | `free -m` | Bar chart (used/cached/free) |
| Disk | `df -h` | Usage bars per mount |
| Network | `ip -s link` | Sparkline charts (in/out bandwidth) |
| Services | `systemctl list-units --type=service` | List with status badges |
| System Info | `uname -a`, `uptime` | Hostname, OS, kernel, load averages |

Polling interval: 5–10 seconds (configurable per server).

### Docker

Split view:

- **Left panel:** Container list
  - Name, image, status, CPU/memory usage
  - Color-coded status (running/stopped/exited)
- **Right panel:** Selected container detail
  - Streaming log tail
  - Environment variables
  - Port mappings
  - Restart policy

**Controls:** Start, Stop, Restart buttons per container.

**Data sources:**
- `docker ps --format json`
- `docker stats --no-stream --format json`
- `docker logs --tail 100 -f`

**Future:** Drag-and-drop a folder with `docker-compose.yml` → SFTP upload → `docker compose up -d`.

### Terminal

SwiftTerm embedded view providing a full interactive SSH session. Supports multiple terminal instances as sub-tabs within the Terminal tab.

### Files

SFTP file browser via Citadel:
- Tree view (left) + file list (right)
- Drag-and-drop upload/download
- Operations: rename, delete, mkdir, edit text files in a sheet

## Dependencies

| Package | Purpose | Source |
|---------|---------|--------|
| Citadel | SSH + SFTP | Swift Package Manager |
| SwiftTerm | Terminal emulator | Swift Package Manager |
| Swift Charts | Metric visualizations | Apple framework |
| SwiftNIO | Async networking (via Citadel) | Swift Package Manager |

## Security & Privacy

- **100% local** — no telemetry, no analytics, no cloud services, no phone-home
- Passwords and key passphrases stored in macOS Keychain
- Private keys referenced by path, never copied
- App Sandbox with network client entitlement
- Only network traffic is SSH/SFTP to user-specified servers
- **Open source** — MIT licensed

## Phases

### Phase 1 — Foundation
- Xcode project setup (macOS 26, SwiftUI)
- Connection layer (Citadel SSH auth)
- Server management (add/edit/remove, Keychain storage)
- Welcome screen + sidebar

### Phase 2 — Dashboard
- Polling actor per server
- Metric parsing (CPU, memory, disk, network, services)
- Dashboard cards with liquid glass styling
- Swift Charts integration

### Phase 3 — Docker
- Container list + status
- Container detail (logs, env, ports)
- Start/stop/restart controls

### Phase 4 — Terminal & Files
- SwiftTerm integration
- Multi-tab terminal sessions
- SFTP browser with drag-and-drop

### Phase 5 — Polish
- Connection resilience (auto-reconnect)
- Error handling UX
- Drag-and-drop compose deployment
- Settings (polling interval, themes)
