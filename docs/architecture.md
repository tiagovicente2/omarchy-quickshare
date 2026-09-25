# Architecture & System Design

Omarchy Quick Share integrates the Android Quick Share protocol into Omarchy's Wayland desktop environment (Quickshell + Hyprland).

```
┌────────────────────────────────────────────────────────┐
│                   Omarchy Desktop                      │
│                                                        │
│  ┌─────────────────────────┐  ┌──────────────────────┐ │
│  │ widget/QuickShareBar.qml │  │ service/Receiver.qml │ │
│  │ (Status bar icon + UI)  │  │ (Process supervisor) │ │
│  └────────────┬────────────┘  └──────────┬───────────┘ │
│               │   Quickshell QML Runtime │             │
│               └─────────────┬────────────┘             │
│                             │ JSON-RPC (Unix Socket)   │
└─────────────────────────────┼──────────────────────────┘
                              ▼
        $XDG_RUNTIME_DIR/omarchy-quickshare.sock
                              ▲
┌─────────────────────────────┼──────────────────────────┐
│                             │                          │
│               ┌─────────────┴────────────┐             │
│               │ bin/quickshare-controller│             │
│               │ (Rust Headless Daemon)   │             │
│               └──────┬────────────┬──────┘             │
│                      │            │                    │
│        BLE (BlueZ)   │            │ Wi-Fi / mDNS       │
│        Discovery     │            │ TCP File Transfer  │
│                      ▼            ▼                    │
│            ┌─────────────────────────────┐             │
│            │   Android Phone (Nearby)    │             │
│            └─────────────────────────────┘             │
└────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Headless Controller (`controller/` & `bin/quickshare-controller`)
- Written in Rust.
- Operates as a daemon in the user session without any GTK, Qt, or WebKit GUI dependencies.
- Handles:
  - **Discovery:** Advertises machine presence over Bluetooth Low Energy (BLE) via Linux BlueZ D-Bus and registers an mDNS-SD service on local Wi-Fi.
  - **Handshake & Encryption:** Performs UKEY2 cryptographic key exchange and TLS handshake to establish a secure channel. Generates the 4-digit verification PIN / SAS token.
  - **Transfer Engine:** Receives payload streams, saves files to `~/Downloads` (or configured directory), and streams files when sending.
- Exposes a private Unix domain socket at `$XDG_RUNTIME_DIR/omarchy-quickshare.sock` using newline-delimited JSON-RPC.

### 2. Service Supervisor (`service/Receiver.qml`)
- Mounted by `omarchy-shell` on startup (`kind: "service"`).
- Spawns and supervises `quickshare-controller`.
- Maintains socket connection and dispatches events:
  - `device_found` / `device_lost`
  - `incoming_request` (with device name, payload count/size, and verification PIN)
  - `transfer_progress` (bytes transferred, rate, ETA)
  - `transfer_completed` / `transfer_failed`
- Triggers desktop notifications for incoming requests and transfer results.

### 3. Bar Widget (`widget/QuickShareBar.qml`)
- Status bar item loaded in Hyprland (`kind: "bar-widget"`).
- Displays symbolic icon indicating state:
  - **Idle:** subtle presence icon.
  - **Active:** badge showing available nearby devices or progress ring during active transfers.
- Clicking opens a popover panel with:
  - Nearby device list with one-click share buttons.
  - "Send Files..." picker (invoking desktop file chooser).
  - Incoming request card showing sender device name, PIN, and "Accept" / "Decline" buttons.
  - Active transfer progress bars with cancellation controls.

## IPC Protocol (Socket RPC)

Communication between the QML shell and the Rust daemon uses JSON-RPC over the local Unix domain socket.

### Commands (QML → Daemon)

| Method | Parameters | Description |
|---|---|---|
| `ping` | `{}` | Heartbeat check |
| `snapshot` | `{}` | Query current state (status, devices, transfers) |
| `send_files` | `{"device": "<id>", "paths": ["/path/1", ...]}` | Send files to a discovered device |
| `accept` | `{"request_id": "<id>"}` | Accept an incoming transfer |
| `decline` | `{"request_id": "<id>"}` | Reject an incoming transfer |
| `cancel` | `{"transfer_id": "<id>"}` | Cancel an ongoing transfer |
| `set_visible` | `{"visible": true/false}` | Toggle receiver discoverability |

### Events (Daemon → QML)

| Event | Payload |
|---|---|
| `device_discovered` | `{"id": "...", "name": "Pixel 9", "type": "phone"}` |
| `incoming_request` | `{"id": "...", "device": "Pixel 9", "pin": "8412", "files": [{"name": "photo.jpg", "size": 3145728}]}` |
| `progress` | `{"transfer_id": "...", "transferred": 1048576, "total": 3145728, "rate_bps": 2097152}` |
| `finished` | `{"transfer_id": "...", "status": "completed", "files": ["/home/user/Downloads/photo.jpg"]}` |
