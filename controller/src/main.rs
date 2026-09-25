use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use rqs_lib::channel::{ChannelAction, ChannelDirection, ChannelMessage};
use rqs_lib::{EndpointInfo, State, Visibility};
use rqs_lib::RQS;
use serde::{Deserialize, Serialize};
use serde_json::json;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{broadcast, Mutex};

const DEFAULT_SOCKET_NAME: &str = "omarchy-quickshare.sock";

fn get_socket_path(custom: Option<PathBuf>) -> PathBuf {
    if let Some(path) = custom {
        return path;
    }
    if let Ok(runtime_dir) = std::env::var("XDG_RUNTIME_DIR") {
        return Path::new(&runtime_dir).join(DEFAULT_SOCKET_NAME);
    }
    Path::new("/tmp").join(DEFAULT_SOCKET_NAME)
}

#[derive(Parser)]
#[command(
    name = "quickshare-controller",
    version,
    about = "Headless Quick Share controller for Omarchy"
)]
struct Cli {
    #[arg(long, global = true, value_name = "PATH")]
    socket: Option<PathBuf>,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Start the background Quick Share receiver daemon
    Daemon {
        #[arg(long, default_value = "Omarchy PC")]
        device_name: String,

        #[arg(long, value_name = "PATH")]
        destination: Option<PathBuf>,

        #[arg(long)]
        port: Option<u32>,
    },
    /// Ping running daemon
    Ping,
    /// Return current devices and active transfers
    Snapshot,
    /// Accept incoming transfer
    Accept {
        #[arg(long)]
        request_id: String,
    },
    /// Decline incoming transfer
    Decline {
        #[arg(long)]
        request_id: String,
    },
    /// Cancel active transfer
    Cancel {
        #[arg(long)]
        transfer_id: String,
    },
}

#[derive(Debug, Serialize, Deserialize)]
struct SocketRequest {
    action: String,
    #[serde(default)]
    id: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct SocketResponse {
    status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<serde_json::Value>,
}

#[derive(Debug, Default, Clone, Serialize)]
struct DaemonState {
    devices: HashMap<String, EndpointInfo>,
    active_incoming: Option<IncomingPrompt>,
    transfers: HashMap<String, TransferProgress>,
}

#[derive(Debug, Clone, Serialize)]
struct IncomingPrompt {
    id: String,
    pin: Option<String>,
    device: Option<String>,
    files: Option<Vec<String>>,
    total_bytes: u64,
}

#[derive(Debug, Clone, Serialize)]
struct TransferProgress {
    id: String,
    state: String,
    transferred: u64,
    total: u64,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let socket_path = get_socket_path(cli.socket);

    match cli.command {
        Command::Daemon {
            device_name: _,
            destination,
            port,
        } => {
            run_daemon(socket_path, destination, port).await?;
        }
        Command::Ping => {
            let resp = send_socket_command(&socket_path, &SocketRequest {
                action: "ping".into(),
                id: None,
            })
            .await?;
            println!("{}", serde_json::to_string(&resp)?);
        }
        Command::Snapshot => {
            let resp = send_socket_command(&socket_path, &SocketRequest {
                action: "snapshot".into(),
                id: None,
            })
            .await?;
            println!("{}", serde_json::to_string(&resp)?);
        }
        Command::Accept { request_id } => {
            let resp = send_socket_command(&socket_path, &SocketRequest {
                action: "accept".into(),
                id: Some(request_id),
            })
            .await?;
            println!("{}", serde_json::to_string(&resp)?);
        }
        Command::Decline { request_id } => {
            let resp = send_socket_command(&socket_path, &SocketRequest {
                action: "decline".into(),
                id: Some(request_id),
            })
            .await?;
            println!("{}", serde_json::to_string(&resp)?);
        }
        Command::Cancel { transfer_id } => {
            let resp = send_socket_command(&socket_path, &SocketRequest {
                action: "cancel".into(),
                id: Some(transfer_id),
            })
            .await?;
            println!("{}", serde_json::to_string(&resp)?);
        }
    }

    Ok(())
}

async fn run_daemon(
    socket_path: PathBuf,
    destination: Option<PathBuf>,
    port: Option<u32>,
) -> Result<()> {
    let download_dir = destination.unwrap_or_else(|| {
        directories::UserDirs::new()
            .and_then(|u| u.download_dir().map(|p| p.to_path_buf()))
            .unwrap_or_else(|| PathBuf::from(std::env::var("HOME").unwrap_or_default()).join("Downloads"))
    });

    let mut rqs = RQS::new(Visibility::Visible, port, Some(download_dir));
    let (_send_channel, _ble_rx) = rqs.run().await.context("Failed to start RQS network service")?;

    let (discovery_tx, mut discovery_rx) = broadcast::channel::<EndpointInfo>(32);
    let _ = rqs.discovery(discovery_tx);

    let state = Arc::new(Mutex::new(DaemonState::default()));

    // Clean up any stale socket file
    if socket_path.exists() {
        let _ = std::fs::remove_file(&socket_path);
    }

    let listener = UnixListener::bind(&socket_path)
        .with_context(|| format!("Failed to bind unix socket at {:?}", socket_path))?;

    // Announce ready event to Quickshell service over stdout
    println!(
        "{}",
        json!({
            "event": "ready",
            "data": {
                "status": "listening",
                "socket": socket_path.to_string_lossy(),
            }
        })
    );

    let msg_sender = rqs.message_sender.clone();
    let mut msg_rx = rqs.message_sender.subscribe();

    // 1. Task: handle incoming protocol events from rqs_lib
    let state_proto = state.clone();
    tokio::spawn(async move {
        while let Ok(msg) = msg_rx.recv().await {
            let mut s = state_proto.lock().await;

            if let Some(state_variant) = &msg.state {
                match state_variant {
                    State::WaitingForUserConsent => {
                        let prompt = IncomingPrompt {
                            id: msg.id.clone(),
                            pin: msg.meta.as_ref().and_then(|m| m.pin_code.clone()),
                            device: msg.meta.as_ref().and_then(|m| m.source.as_ref().map(|d| d.name.clone())),
                            files: msg.meta.as_ref().and_then(|m| m.files.clone()),
                            total_bytes: msg.meta.as_ref().map(|m| m.total_bytes).unwrap_or(0),
                        };
                        s.active_incoming = Some(prompt.clone());
                        println!(
                            "{}",
                            json!({
                                "event": "incoming",
                                "data": prompt
                            })
                        );
                    }
                    State::ReceivingFiles => {
                        let total = msg.meta.as_ref().map(|m| m.total_bytes).unwrap_or(0);
                        let ack = msg.meta.as_ref().map(|m| m.ack_bytes).unwrap_or(0);
                        let progress = TransferProgress {
                            id: msg.id.clone(),
                            state: "transferring".into(),
                            transferred: ack,
                            total,
                        };
                        s.transfers.insert(msg.id.clone(), progress.clone());
                        println!(
                            "{}",
                            json!({
                                "event": "progress",
                                "data": progress
                            })
                        );
                    }
                    State::Finished => {
                        s.active_incoming = None;
                        s.transfers.remove(&msg.id);
                        println!(
                            "{}",
                            json!({
                                "event": "transfers",
                                "data": []
                            })
                        );
                    }
                    State::Rejected | State::Cancelled | State::Disconnected => {
                        s.active_incoming = None;
                        s.transfers.remove(&msg.id);
                        println!(
                            "{}",
                            json!({
                                "event": "transfers",
                                "data": []
                            })
                        );
                    }
                    _ => {}
                }
            }
        }
    });

    // 2. Task: handle mDNS / BLE discovery endpoints
    let state_disc = state.clone();
    tokio::spawn(async move {
        while let Ok(endpoint) = discovery_rx.recv().await {
            let mut s = state_disc.lock().await;
            if endpoint.present.unwrap_or(true) {
                s.devices.insert(endpoint.id.clone(), endpoint);
            } else {
                s.devices.remove(&endpoint.id);
            }

            let device_list: Vec<&EndpointInfo> = s.devices.values().collect();
            println!(
                "{}",
                json!({
                    "event": "devices",
                    "data": device_list
                })
            );
        }
    });

    // 3. Main loop: accept Unix socket RPC connections
    let state_rpc = state.clone();
    loop {
        tokio::select! {
            accept_res = listener.accept() => {
                match accept_res {
                    Ok((stream, _)) => {
                        let state_clone = state_rpc.clone();
                        let sender_clone = msg_sender.clone();
                        tokio::spawn(async move {
                            if let Err(e) = handle_socket_client(stream, state_clone, sender_clone).await {
                                eprintln!("Error handling socket client: {}", e);
                            }
                        });
                    }
                    Err(e) => {
                        eprintln!("Socket accept error: {}", e);
                        tokio::time::sleep(Duration::from_millis(50)).await;
                    }
                }
            }
            _ = tokio::signal::ctrl_c() => {
                eprintln!("Shutting down Quick Share daemon...");
                break;
            }
        }
    }

    let _ = std::fs::remove_file(&socket_path);
    rqs.stop().await;

    Ok(())
}

async fn handle_socket_client(
    stream: UnixStream,
    state: Arc<Mutex<DaemonState>>,
    msg_sender: broadcast::Sender<ChannelMessage>,
) -> Result<()> {
    let (reader, mut writer) = stream.into_split();
    let mut lines = BufReader::new(reader).lines();

    while let Some(line) = lines.next_line().await? {
        if line.trim().is_empty() {
            continue;
        }

        let req: SocketRequest = match serde_json::from_str(&line) {
            Ok(r) => r,
            Err(e) => {
                let err_resp = SocketResponse {
                    status: "error".into(),
                    message: Some(format!("Invalid request JSON: {}", e)),
                    data: None,
                };
                writer.write_all(serde_json::to_string(&err_resp)?.as_bytes()).await?;
                writer.write_all(b"\n").await?;
                continue;
            }
        };

        let response = match req.action.as_str() {
            "ping" => SocketResponse {
                status: "ok".into(),
                message: Some("pong".into()),
                data: None,
            },
            "snapshot" => {
                let s = state.lock().await;
                SocketResponse {
                    status: "ok".into(),
                    message: None,
                    data: Some(serde_json::to_value(&*s)?),
                }
            }
            "accept" => {
                if let Some(id) = req.id {
                    let msg = ChannelMessage {
                        id: id.clone(),
                        direction: ChannelDirection::FrontToLib,
                        action: Some(ChannelAction::AcceptTransfer),
                        rtype: None,
                        state: None,
                        meta: None,
                    };
                    let _ = msg_sender.send(msg);
                    SocketResponse {
                        status: "accepted".into(),
                        message: Some(format!("Accepted transfer {}", id)),
                        data: None,
                    }
                } else {
                    SocketResponse {
                        status: "error".into(),
                        message: Some("Missing transfer id".into()),
                        data: None,
                    }
                }
            }
            "decline" => {
                if let Some(id) = req.id {
                    let msg = ChannelMessage {
                        id: id.clone(),
                        direction: ChannelDirection::FrontToLib,
                        action: Some(ChannelAction::RejectTransfer),
                        rtype: None,
                        state: None,
                        meta: None,
                    };
                    let _ = msg_sender.send(msg);
                    SocketResponse {
                        status: "declined".into(),
                        message: Some(format!("Declined transfer {}", id)),
                        data: None,
                    }
                } else {
                    SocketResponse {
                        status: "error".into(),
                        message: Some("Missing transfer id".into()),
                        data: None,
                    }
                }
            }
            "cancel" => {
                if let Some(id) = req.id {
                    let msg = ChannelMessage {
                        id: id.clone(),
                        direction: ChannelDirection::FrontToLib,
                        action: Some(ChannelAction::CancelTransfer),
                        rtype: None,
                        state: None,
                        meta: None,
                    };
                    let _ = msg_sender.send(msg);
                    SocketResponse {
                        status: "cancelled".into(),
                        message: Some(format!("Cancelled transfer {}", id)),
                        data: None,
                    }
                } else {
                    SocketResponse {
                        status: "error".into(),
                        message: Some("Missing transfer id".into()),
                        data: None,
                    }
                }
            }
            other => SocketResponse {
                status: "error".into(),
                message: Some(format!("Unknown action: {}", other)),
                data: None,
            },
        };

        writer.write_all(serde_json::to_string(&response)?.as_bytes()).await?;
        writer.write_all(b"\n").await?;
    }

    Ok(())
}

async fn send_socket_command(socket_path: &Path, req: &SocketRequest) -> Result<SocketResponse> {
    let stream = UnixStream::connect(socket_path)
        .await
        .with_context(|| format!("Daemon not running or socket not accessible at {:?}", socket_path))?;

    let (reader, mut writer) = stream.into_split();
    let req_json = serde_json::to_string(req)?;
    writer.write_all(req_json.as_bytes()).await?;
    writer.write_all(b"\n").await?;

    let mut lines = BufReader::new(reader).lines();
    if let Some(line) = lines.next_line().await? {
        let resp: SocketResponse = serde_json::from_str(&line)?;
        Ok(resp)
    } else {
        anyhow::bail!("No response from Quick Share daemon")
    }
}
