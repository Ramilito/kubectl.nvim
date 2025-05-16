use std::{
    fs::File,
    os::unix::io::{FromRawFd, IntoRawFd, RawFd},
    sync::{Arc, Mutex},
    thread,
    time::Duration,
};

use k8s_metrics::{
    v1beta1::{self as metricsv1},
    QuantityExt,
};
use kube::api;
use mlua::{prelude::*, Lua};
use nix::pty::openpty;
use ratatui::{
    backend::CrosstermBackend,
    layout::Rect,
    style::{Color, Modifier, Style},
    widgets::{Block, Borders, Paragraph},
    Terminal,
};
use tokio::runtime::Runtime;
use tracing::info;

use crate::{CLIENT_INSTANCE, RUNTIME};

#[derive(Clone, Debug)]
struct NodeStat {
    name: String,
    cpu: String,
    memory: String,
}
type SharedStats = Arc<Mutex<Vec<NodeStat>>>;

#[tracing::instrument]
pub fn start_dashboard(_lua: &Lua, (w, _h): (u16, u16)) -> LuaResult<i32> {
    let pty = openpty(None, None).map_err(|e| LuaError::ExternalError(Arc::new(e)))?;
    let master_fd: RawFd = pty.master.into_raw_fd();
    let slave_fd: RawFd = pty.slave.into_raw_fd();

    // Shared stats vec -------------------------------------------
    let stats: SharedStats = Arc::new(Mutex::new(Vec::new()));

    {
        let stats = stats.clone();
        thread::spawn(move || loop {
            let rt =
                RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

            let client_guard = CLIENT_INSTANCE
                .lock()
                .map_err(|_| {
                    LuaError::RuntimeError("Failed to acquire lock on client instance".into())
                })
                .unwrap();
            let client = client_guard
                .as_ref()
                .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))
                .unwrap()
                .clone();

            let res = rt.block_on(async {
                let lp = api::ListParams::default();
                api::Api::<metricsv1::NodeMetrics>::all(client.clone())
                    .list(&lp)
                    .await
                    .map(|list| list.items)
            });

            match res {
                Ok(dynamic_vec) => {
                    let mut out = Vec::new();

                    for obj in dynamic_vec {
                        let name = obj.metadata.name.unwrap();
                        let cpu = obj.usage.cpu.to_f64().unwrap().to_string();
                        let memory = obj.usage.memory.to_memory().unwrap().to_string();
                        out.push(NodeStat { name, cpu, memory });
                    }

                    *stats.lock().unwrap() = out;
                }

                Err(e) => {
                    tracing::warn!("metrics fetch error: {e}");
                }
            }

            thread::sleep(Duration::from_secs(5));
        });
    }

    // 4. spawn Ratatui draw loop on the slave side ------------------
    let inner_w = w.saturating_sub(2).max(1);
    {
        let stats = stats.clone();
        thread::spawn(move || {
            // SAFETY: we own `slave_fd`
            let file = unsafe { File::from_raw_fd(slave_fd) };
            let backend = CrosstermBackend::new(file);
            let mut term = Terminal::new(backend).unwrap();

            loop {
                let snapshot = stats.lock().unwrap().clone();
                let _ = term.draw(|f| {
                    let size = f.area();

                    let frame = Block::default()
                        .title(" Node usage (live) ")
                        .borders(Borders::ALL)
                        .border_style(
                            Style::default()
                                .fg(Color::Cyan)
                                .add_modifier(Modifier::BOLD),
                        );
                    f.render_widget(frame, size);

                    for (i, ns) in snapshot.iter().enumerate() {
                        let text = format!("{}  CPU:{}  MEM:{}", ns.name, ns.cpu, ns.memory);
                        let line = Paragraph::new(text);
                        let area = Rect {
                            x: size.x + 1,
                            y: size.y + 1 + i as u16,
                            width: inner_w,
                            height: 1,
                        };
                        f.render_widget(line, area);
                    }
                });

                thread::sleep(Duration::from_millis(200));
            }
        });
    }

    // 5. return master FD to Lua (for nvim_chan_send pump)
    Ok(master_fd)
}
