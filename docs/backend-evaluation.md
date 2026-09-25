# Backend Evaluation & Protocol Analysis

This document details the evaluation of upstream Quick Share implementations for use as the Omarchy Quick Share backend.

## Comparison Summary

| Implementation | Language | Architecture | Suitability |
|---|---|---|---|
| **[Martichou/rquickshare](https://github.com/Martichou/rquickshare)** | Rust | Multi-crate workspace (`core_lib` + Tauri app) | **Primary Choice:** `core_lib` is decoupled, pure Rust, handles BLE + mDNS + UKEY2, and compiles to a standalone headless binary. |
| **[nozwock/packet](https://github.com/nozwock/packet)** | Rust | GTK4 / Libadwaita desktop app | **Alternative:** High quality Linux client, but networking logic is deeply tied to the GTK4 event loop and UI widgets. |
| **[google/nearby](https://github.com/google/nearby)** | C++ | Bazel monorepo, internal Google frameworks | **Not Suitable:** Heavy C++ dependencies, lack of Linux desktop D-Bus/socket interfaces, and tied to Google Play Services / Chromium code. |

---

## Detailed Evaluation

### 1. Martichou/rquickshare (Recommended)

- **Crate Layout:**
  - `core_lib`: Pure Rust implementation containing mDNS discovery, BlueZ BLE advertising, UKEY2 key negotiation, TLS session setup, and stream file transfer.
  - `app`: Frontend packaging (Tauri).
- **Advantages:**
  - Can import or vendor `core_lib` directly in `controller/Cargo.toml`.
  - Built-in BlueZ D-Bus integration for Bluetooth discovery.
  - Native Linux mDNS handling via `mdns-sd`.
  - Small compiled size (~10MB standalone binary, zero GUI dependencies).
- **Implementation Path:**
  - Build `controller/` around `rquickshare::core_lib`.
  - Wrap its event channel in a Tokio-based Unix domain socket server speaking JSON-RPC.

### 2. nozwock/packet

- **Advantages:**
  - Specifically designed for Linux Quick Share interoperability.
  - Handles recent Android Quick Share protocol quirks well.
- **Drawbacks:**
  - UI-coupled design. The GTK4 and Libadwaita bindings run on the main thread, making extraction as a headless library require upstream refactoring.

### 3. google/nearby

- **Advantages:**
  - Official protocol reference maintained by Google.
- **Drawbacks:**
  - Requires Bazel build system.
  - Lacks standard Linux session service packaging.
  - Upstream pull requests adding Linux desktop support have historically stalled.

---

## Protocol Breakdown

### Discovery Phase
1. **Bluetooth Low Energy (BLE):**
   - The receiver broadcasts an advertising packet with Google Nearby Share Service UUID (`0xFEF3`).
   - The advertisement payload includes device visibility flags and endpoint salt.
   - When an Android user taps "Quick Share", the phone scans for `0xFEF3` beacons to identify eligible targets.
2. **Wi-Fi mDNS-SD:**
   - Both devices advertise `_FC9F5ED42C8A._tcp` on the local network (port 5353).
   - Contains endpoint attributes: device name, device type (PC, phone), and service port.

### Connection & Authentication Phase
1. **TCP Connection:** The initiator opens a TCP socket to the target IP and port announced via mDNS.
2. **UKEY2 Handshake:**
   - Initiator and target exchange UKEY2 client/server init packets.
   - Diffie-Hellman key exchange derives a shared secret.
   - A short authentication string (SAS) is computed to produce the 4-digit verification PIN displayed on both screens.
3. **TLS Upgrade:** The connection upgrades to TLS using ephemeral self-signed certificates verified against the derived UKEY2 secret.

### Payload Transfer Phase
1. **Introduction Frame:** Initiator sends metadata describing files (filename, size, MIME type).
2. **User Consent:** The receiver prompts the user (via the Omarchy status bar panel).
3. **Data Streaming:** Upon acceptance, file chunks are streamed over the encrypted TCP channel.
4. **Completion:** Disconnect frame verifies file hashes and signals finished transfer.

---

## Network & Firewall Requirements

To receive transfers reliably:
- **UDP Port 5353:** Multicast DNS (mDNS) for local discovery.
- **Dynamic TCP Ports (or configured range, e.g. 52380–52390):** Incoming transfer stream.
- **BlueZ D-Bus:** Daemon must have permissions to interact with `org.bluez` for BLE advertising.
