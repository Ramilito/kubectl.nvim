use crate::{with_client, RUNTIME};
use crossterm::{
    event::{Event, KeyCode, KeyEvent, MouseEventKind},
    terminal::enable_raw_mode,
};
use mlua::{prelude::*, UserData, UserDataMethods};
use ratatui::{
    backend::CrosstermBackend, layout::Rect, Frame, Terminal, TerminalOptions, Viewport,
};
use std::{
    io::{Result as IoResult, Write},
    sync::{
        atomic::{AtomicBool, AtomicU16, Ordering},
        Arc, Mutex,
    },
    time::Instant,
};
use tokio::{
    sync::mpsc,
    time::{sleep, Duration},
};

use crate::{
    metrics::nodes::{spawn_node_collector, NodeStat, SharedNodeStats},
    ui::{
        overview_ui::{self, OverviewState},
        top_ui::{self, TopViewState},
    },
};

use super::top_ui::InputMode;

struct NvWriter(mpsc::UnboundedSender<Vec<u8>>);

impl Write for NvWriter {
    fn write(&mut self, buf: &[u8]) -> IoResult<usize> {
        let _ = self.0.send(buf.to_vec());
        Ok(buf.len())
    }
    fn flush(&mut self) -> IoResult<()> {
        Ok(())
    }
}

pub struct Session {
    tx_in: mpsc::UnboundedSender<Vec<u8>>,
    rx_out: Mutex<mpsc::UnboundedReceiver<Vec<u8>>>,
    open: Arc<AtomicBool>,
    cols: Arc<AtomicU16>,
    rows: Arc<AtomicU16>,
}

impl Session {
    pub fn new(view_name: String) -> LuaResult<Self> {
        let rt = RUNTIME.get_or_init(|| tokio::runtime::Runtime::new().unwrap());
        let open = Arc::new(AtomicBool::new(true));
        let cols = Arc::new(AtomicU16::new(80));
        let rows = Arc::new(AtomicU16::new(24));
        let node_stats: SharedNodeStats = Arc::new(Mutex::new(Vec::new()));
        let ui_node_stats = node_stats.clone();
        let _ = with_client(move |client| async move {
            spawn_node_collector(node_stats.clone(), client.clone());
            Ok(())
        });

        let (tx_in, rx_in) = mpsc::unbounded_channel::<Vec<u8>>();
        let (tx_out, rx_out) = mpsc::unbounded_channel::<Vec<u8>>();

        {
            let open = open.clone();
            let ui_cols = cols.clone();
            let ui_rows = rows.clone();
            rt.spawn(async move {
                run_ui(
                    ui_node_stats,
                    view_name,
                    rx_in,
                    tx_out,
                    open,
                    ui_cols,
                    ui_rows,
                )
                .await
            });
        }

        Ok(Self {
            tx_in,
            rx_out: Mutex::new(rx_out),
            open,
            cols,
            rows,
        })
    }

    fn read_chunk(&self) -> Option<String> {
        self.rx_out
            .lock()
            .unwrap()
            .try_recv()
            .ok()
            .map(|v| String::from_utf8_lossy(&v).into_owned())
    }
    fn write(&self, s: &str) {
        let _ = self.tx_in.send(s.as_bytes().to_vec());
    }
    fn is_open(&self) -> bool {
        self.open.load(Ordering::Acquire)
    }
    fn resize(&self, w: u16, h: u16) {
        self.cols.store(w, Ordering::Release);
        self.rows.store(h, Ordering::Release);
    }
}

impl UserData for Session {
    fn add_methods<M: UserDataMethods<Self>>(m: &mut M) {
        m.add_method("read_chunk", |_, this, ()| Ok(this.read_chunk()));
        m.add_method("write", |_, this, s: String| {
            this.write(&s);
            Ok(())
        });
        m.add_method("open", |_, this, ()| Ok(this.is_open()));
        m.add_method("resize", |_, this, (w, h): (u16, u16)| {
            this.resize(w, h);
            Ok(())
        });
    }
}

/* ─────────────────────────── View trait & concrete views ─────────────────────────── */

trait View {
    fn on_event(&mut self, ev: &Event) -> bool;
    fn draw(&mut self, f: &mut Frame, area: Rect, nodes: &[NodeStat]);
}

/* ------------------------------ Overview view ------------------------------ */

macro_rules! scroll_nav {
    ($state:expr, $key:expr) => {{
        match $key {
            KeyCode::Down | KeyCode::Char('j') => {
                $state.scroll_down();
                true
            }
            KeyCode::Up | KeyCode::Char('k') => {
                $state.scroll_up();
                true
            }
            KeyCode::PageDown => {
                $state.scroll_page_down();
                true
            }
            KeyCode::PageUp => {
                $state.scroll_page_up();
                true
            }
            _ => false,
        }
    }};
}

struct OverviewView {
    state: OverviewState,
}
impl OverviewView {
    fn new() -> Self {
        Self {
            state: OverviewState::default(),
        }
    }
}
impl View for OverviewView {
    fn on_event(&mut self, ev: &Event) -> bool {
        match ev {
            Event::Key(k) => match k.code {
                KeyCode::Tab => {
                    self.state.focus_next();
                    true
                }
                KeyCode::BackTab => {
                    self.state.focus_prev();
                    true
                }
                other => scroll_nav!(self.state, other),
            },
            Event::Mouse(m) => match m.kind {
                MouseEventKind::ScrollDown => {
                    self.state.scroll_down();
                    true
                }
                MouseEventKind::ScrollUp => {
                    self.state.scroll_up();
                    true
                }
                _ => false,
            },
            _ => false,
        }
    }

    fn draw(&mut self, f: &mut Frame, area: Rect, nodes: &[NodeStat]) {
        overview_ui::draw(f, nodes, area, &mut self.state);
    }
}

/* -------------------------------- Top view -------------------------------- */

struct TopView {
    state: TopViewState,
}
impl TopView {
    fn new() -> Self {
        Self {
            state: TopViewState::default(),
        }
    }
}
impl View for TopView {
    fn on_event(&mut self, ev: &Event) -> bool {
        match ev {
            Event::Key(k) => {
                /* 1 ▸ Let the view-state consume filter keys first */
                self.state.handle_key(*k);

                /* Did the key touch the filter prompt? – always redraw */
                let filter_keys = matches!(
                    k.code,
                    KeyCode::Char('/') | KeyCode::Esc | KeyCode::Enter | KeyCode::Backspace
                );
                if filter_keys || self.state.input_mode == InputMode::Filtering {
                    return true;
                }

                /* 2 ▸ Normal keys (tab / scrolling) */
                match k.code {
                    KeyCode::Tab => {
                        self.state.next_tab();
                        true
                    }
                    other => scroll_nav!(self.state, other),
                }
            }
            Event::Mouse(m) => match m.kind {
                MouseEventKind::ScrollDown => {
                    self.state.scroll_down();
                    true
                }
                MouseEventKind::ScrollUp => {
                    self.state.scroll_up();
                    true
                }
                _ => false,
            },
            _ => false,
        }
    }

    fn draw(&mut self, f: &mut Frame, area: Rect, nodes: &[NodeStat]) {
        top_ui::draw(f, area, &mut self.state, nodes);
    }
}

fn bytes_to_event(b: &[u8]) -> Option<Event> {
    match b {
        b"\x1B[A" => Some(Event::Key(KeyCode::Up.into())),
        b"\x1B[B" => Some(Event::Key(KeyCode::Down.into())),
        b"\x1B[C" => Some(Event::Key(KeyCode::Right.into())),
        b"\x1B[D" => Some(Event::Key(KeyCode::Left.into())),
        b"\x1B[5~" => Some(Event::Key(KeyCode::PageUp.into())),
        b"\x1B[6~" => Some(Event::Key(KeyCode::PageDown.into())),
        b"\x7F" => Some(Event::Key(KeyCode::Backspace.into())),
        b"\t" => Some(Event::Key(KeyCode::Tab.into())),
        b"\x1B[Z" => Some(Event::Key(KeyCode::BackTab.into())),
        [c] if *c >= 0x20 && *c <= 0x7e => Some(Event::Key(KeyCode::Char(*c as char).into())),
        _ => None,
    }
}

#[tracing::instrument]
async fn run_ui(
    node_stats: SharedNodeStats,
    view_name: String,
    mut rx_in: mpsc::UnboundedReceiver<Vec<u8>>,
    tx_out: mpsc::UnboundedSender<Vec<u8>>,
    open: Arc<AtomicBool>,
    cols: Arc<AtomicU16>,
    rows: Arc<AtomicU16>,
) {
    let w = cols.load(Ordering::Acquire);
    let h = rows.load(Ordering::Acquire);
    let backend = CrosstermBackend::new(NvWriter(tx_out));
    let options = TerminalOptions {
        viewport: Viewport::Fixed(Rect::new(0, 0, w, h)),
    };
    let mut term = Terminal::with_options(backend, options).expect("terminal");

    enable_raw_mode().ok();

    let mut active_view: Box<dyn View + Send> = match view_name.to_ascii_lowercase().as_str() {
        "overview" | "overview_ui" => Box::new(OverviewView::new()),
        "top" | "top_ui" => Box::new(TopView::new()),
        _other => Box::new(OverviewView::new()),
    };

    /* 3 ▸ tick / event loop -------------------------------------------------- */
    const TICK_MS: u64 = 2_000;
    let mut last_tick = Instant::now() - Duration::from_millis(TICK_MS);

    loop {
        /* — a. Handle every input chunk Neovim sent us — */
        while let Ok(bytes) = rx_in.try_recv() {
            if let Some(ev) = bytes_to_event(&bytes) {
                /* global quit key */
                if matches!(
                    ev,
                    Event::Key(KeyEvent {
                        code: KeyCode::Char('q'),
                        ..
                    })
                ) {
                    open.store(false, Ordering::Release);
                    return;
                }

                /* delegate to the active view */
                if active_view.on_event(&ev) {
                    let nodes = node_stats.lock().unwrap().clone();
                    let _ = term.draw(|f| {
                        let area = f.area();
                        active_view.draw(f, area, &nodes);
                    });
                    last_tick = Instant::now();
                }
            }
        }

        /* — b. Periodic redraw (“tick”) — */
        if last_tick.elapsed() >= Duration::from_millis(TICK_MS) {
            let nodes = node_stats.lock().unwrap().clone();
            let _ = term.draw(|f| {
                let area = f.area();
                active_view.draw(f, area, &nodes);
            });
            last_tick = Instant::now();
        }

        /* — c. keep frame‑rate smooth — */
        sleep(Duration::from_millis(30)).await;
    }
}
