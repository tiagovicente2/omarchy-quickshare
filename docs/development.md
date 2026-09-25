# Development Guide

This guide covers building the Omarchy Quick Share plugin and controller from source.

## Prerequisites

- **Rust toolchain:** `rustc` and `cargo` 1.80+ (`rustup default stable`)
- **System packages (Arch / Omarchy):**
  - `bluez`, `bluez-utils` (Bluetooth stack)
  - `avahi` (mDNS network resolution)
  - `openssl`
  - `pkg-config`
  - `qmllint` (for validating QML files)
- **Omarchy Shell:** `omarchy-shell` and Quickshell runtime

Install build dependencies on Arch/Omarchy:

```bash
omarchy pkg add bluez bluez-utils avahi openssl pkg-config
```

Ensure BlueZ and Avahi are running:

```bash
sudo systemctl enable --now bluetooth avahi-daemon
```

---

## Directory Structure

```
omarchy-quickshare/
├── manifest.json              # Plugin manifest
├── README.md                  # Quick start & overview
├── docs/                      # Technical documentation
│   ├── architecture.md
│   ├── backend-evaluation.md
│   └── development.md
├── bin/
│   └── quickshare-controller  # Launcher script / executable wrapper
├── service/
│   └── Receiver.qml           # Background service supervisor
├── widget/
│   └── QuickShareBar.qml      # Status bar widget and popover
├── assets/
│   └── quickshare-symbolic.svg
└── controller/                # Rust backend daemon
    ├── Cargo.toml
    └── src/
        └── main.rs
```

---

## Building the Controller

Navigate to the `controller` directory:

```bash
cd controller
cargo build --release
```

Copy or symlink the compiled binary:

```bash
cp target/release/quickshare-controller ../bin/quickshare-controller
```

---

## Validating the Plugin

Run the Omarchy plugin validator:

```bash
omarchy plugin validate .
```

Verify QML syntax with `qmllint`:

```bash
qmllint -I /usr/share/omarchy/shell service/Receiver.qml widget/QuickShareBar.qml
```

---

## Local Testing

1. Link the plugin into your Omarchy plugins directory:
   ```bash
   ln -s "$(pwd)" ~/.config/omarchy/plugins/omarchy-quickshare
   ```
2. Rescan plugins or restart the shell:
   ```bash
   omarchy-shell shell rescanPlugins
   # or: omarchy restart shell
   ```
3. Check daemon logs and socket:
   ```bash
   ls -la "$XDG_RUNTIME_DIR/omarchy-quickshare.sock"
   ```
