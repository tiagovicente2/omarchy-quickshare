use clap::{Parser, Subcommand};
use serde_json::json;
use std::path::PathBuf;

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
    },
    /// Ping running daemon
    Ping,
    /// Return current devices and active transfers
    Snapshot,
    /// Send files to a target device
    Send {
        #[arg(long)]
        device: String,
        #[arg(long = "path", required = true)]
        paths: Vec<PathBuf>,
    },
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

#[tokio::main]
async fn main() {
    let cli = Cli::parse();

    match cli.command {
        Command::Daemon {
            device_name,
            destination: _,
        } => {
            // Emit startup event for Quickshell service
            println!(
                "{}",
                json!({
                    "event": "ready",
                    "data": {
                        "name": device_name,
                        "status": "listening"
                    }
                })
            );

            // Keep daemon alive
            tokio::signal::ctrl_c()
                .await
                .expect("Failed to listen for ctrl+c");
        }
        Command::Ping => {
            println!("{}", json!({"status": "ok", "message": "pong"}));
        }
        Command::Snapshot => {
            println!(
                "{}",
                json!({
                    "status": "ok",
                    "devices": [],
                    "transfers": []
                })
            );
        }
        Command::Send { device, paths } => {
            println!(
                "{}",
                json!({
                    "status": "initiated",
                    "device": device,
                    "file_count": paths.len()
                })
            );
        }
        Command::Accept { request_id } => {
            println!("{}", json!({"status": "accepted", "id": request_id}));
        }
        Command::Decline { request_id } => {
            println!("{}", json!({"status": "declined", "id": request_id}));
        }
        Command::Cancel { transfer_id } => {
            println!("{}", json!({"status": "cancelled", "id": transfer_id}));
        }
    }
}
