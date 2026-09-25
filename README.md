# Omarchy Quick Share

Android Quick Share (formerly Nearby Share) integration for Omarchy. Discovers nearby Android devices, receives incoming transfers, and sends files directly from the Omarchy status bar without running an external GUI.

## Features

- **Status Bar Widget:** Live device discovery, active transfer indicator, and popup controls in the Omarchy bar.
- **Headless Daemon:** Background controller managing Bluetooth Low Energy (BLE) advertisements and local Wi-Fi transfers.
- **Transfers:** Accept or decline incoming files with PIN/SAS verification, or share files directly to nearby devices.
- **Notifications:** Native desktop alerts for incoming connection requests and transfer completions.

## Install

```bash
omarchy plugin add https://github.com/tiagovicente2/omarchy-quickshare.git --enable --yes
```

To enable the bar widget manually if needed:

```bash
omarchy plugin enable omarchy-quickshare --section right
```

## Documentation

Detailed technical documentation is maintained in the [`docs/`](docs/) directory:

- [Architecture & System Design](docs/architecture.md) — How the headless Rust controller, Unix socket RPC, and Quickshell QML interact.
- [Backend Evaluation & Protocols](docs/backend-evaluation.md) — Comparison of `rquickshare`, `packet`, and `google/nearby`, plus network and BLE details.
- [Development Guide](docs/development.md) — Prerequisites, build instructions, and testing.

## License

MIT
