use crate::RUNTIME;
use crossterm::{
    event::{Event, KeyCode, KeyEvent, KeyModifiers, MouseEventKind},
    terminal::{disable_raw_mode, enable_raw_mode},
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
};
use tokio::{
    sync::mpsc,
    time::{self, Duration},
};

use crate::ui::{
    overview_ui::{self, OverviewState},
    top_ui::{self, InputMode, TopViewState},
};

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
    tx_in: mpsc::UnboundedSender<Vec<u8>>, // stdin  (Neo → UI)
    rx_out: Mutex<mpsc::UnboundedReceiver<Vec<u8>>>, // stdout (UI  → Neo)
    open: Arc<AtomicBool>,
    cols: Arc<AtomicU16>,
    rows: Arc<AtomicU16>,
}

impl Session {
    pub fn new(view_name: String) -> LuaResult<Self> {
        /* shared flags / size */
        let open = Arc::new(AtomicBool::new(true));
        let cols = Arc::new(AtomicU16::new(80));
        let rows = Arc::new(AtomicU16::new(24));

        /* channels ----------------------------------------------------------- */
        let (tx_in, rx_in) = mpsc::unbounded_channel::<Vec<u8>>();
        let (tx_out, rx_out) = mpsc::unbounded_channel::<Vec<u8>>();

        /* spawn UI task ------------------------------------------------------ */
        let rt = RUNTIME.get_or_init(|| tokio::runtime::Runtime::new().unwrap());
        let ui_open = open.clone();
        let ui_cols = cols.clone();
        let ui_rows = rows.clone();
        rt.spawn(run_ui(view_name, rx_in, tx_out, ui_open, ui_cols, ui_rows));

        Ok(Self {
            tx_in,
            rx_out: Mutex::new(rx_out),
            open,
            cols,
            rows,
        })
    }

    /* ── Lua‑visible helpers ─────────────────────────────────────────────── */
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

trait View: Send {
    fn on_event(&mut self, ev: &Event) -> bool;
    fn draw(&mut self, f: &mut Frame, area: Rect);
}

macro_rules! scroll_nav {
    ($state:expr, $key:expr) => {
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
    };
}

fn bytes_to_event(b: &[u8]) -> Option<Event> {
    use KeyCode::*;
    use KeyModifiers as M;
    macro_rules! key {
        ($code:expr) => {
            Event::Key(KeyEvent::new($code, M::NONE))
        };
    }
    match b {
        b"\x1B[A" => Some(key!(Up)),
        b"\x1B[B" => Some(key!(Down)),
        b"\x1B[C" => Some(key!(Right)),
        b"\x1B[D" => Some(key!(Left)),
        b"\x1B[5~" => Some(key!(PageUp)),
        b"\x1B[6~" => Some(key!(PageDown)),
        b"\x1B[Z" => Some(key!(BackTab)),
        b"\t" => Some(key!(Tab)),
        b"\x7F" => Some(key!(Backspace)),
        [c @ 0x20..=0x7e] => Some(key!(Char(*c as char))),
        _ => None,
    }
}

#[derive(Default)]
struct OverviewView {
    state: OverviewState,
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
    fn draw(&mut self, f: &mut Frame, area: Rect) {
        overview_ui::draw(f, area, &mut self.state);
    }
}

#[derive(Default)]
struct TopView {
    state: TopViewState,
}

impl View for TopView {
    fn on_event(&mut self, ev: &Event) -> bool {
        match ev {
            Event::Key(k) => {
                /* 1 — filter prompt eats its own keys */
                self.state.handle_key(*k);
                let is_filter_key = matches!(
                    k.code,
                    KeyCode::Char('/') | KeyCode::Esc | KeyCode::Enter | KeyCode::Backspace
                );
                if is_filter_key || self.state.input_mode == InputMode::Filtering {
                    return true;
                }
                /* 2 — generic nav */
                match k.code {
                    KeyCode::Tab => {
                        self.state.next_tab();
                        true
                    }
                    KeyCode::Char('e') => {
                        self.state.expand_all();
                        true
                    }
                    KeyCode::Char('E') => {
                        self.state.collapse_all();
                        true
                    }
                    // Namespace selection (Pods tab only)
                    KeyCode::Char('j') | KeyCode::Down => {
                        if self.state.is_pods_tab() {
                            self.state.select_next_ns();
                        } else {
                            self.state.scroll_down();
                        }
                        true
                    }
                    KeyCode::Char('k') | KeyCode::Up => {
                        if self.state.is_pods_tab() {
                            self.state.select_prev_ns();
                        } else {
                            self.state.scroll_up();
                        }
                        true
                    }
                    // Toggle selected namespace
                    KeyCode::Enter | KeyCode::Char(' ') => {
                        if self.state.is_pods_tab() {
                            self.state.toggle_selected_ns();
                            true
                        } else {
                            false
                        }
                    }
                    // Page scroll still works normally
                    KeyCode::PageDown => {
                        self.state.scroll_page_down();
                        true
                    }
                    KeyCode::PageUp => {
                        self.state.scroll_page_up();
                        true
                    }
                    _ => false,
                }
            }
            Event::Mouse(m) => match m.kind {
                MouseEventKind::ScrollDown => {
                    if self.state.is_pods_tab() {
                        self.state.select_next_ns();
                    } else {
                        self.state.scroll_down();
                    }
                    true
                }
                MouseEventKind::ScrollUp => {
                    if self.state.is_pods_tab() {
                        self.state.select_prev_ns();
                    } else {
                        self.state.scroll_up();
                    }
                    true
                }
                _ => false,
            },
            _ => false,
        }
    }
    fn draw(&mut self, f: &mut Frame, area: Rect) {
        top_ui::draw(f, area, &mut self.state);
    }
}

fn make_view(name: &str) -> Box<dyn View> {
    match name.to_ascii_lowercase().as_str() {
        "top" | "top_ui" => Box::new(TopView::default()),
        "overview" | "overview_ui" => Box::new(OverviewView::default()),
        _other => Box::new(OverviewView::default()),
    }
}

async fn run_ui(
    view_name: String,
    mut rx_in: mpsc::UnboundedReceiver<Vec<u8>>,
    tx_out: mpsc::UnboundedSender<Vec<u8>>,
    open: Arc<AtomicBool>,
    cols: Arc<AtomicU16>,
    rows: Arc<AtomicU16>,
) {
    enable_raw_mode().ok();
    let backend = CrosstermBackend::new(NvWriter(tx_out));
    let initial_w = cols.load(Ordering::Acquire);
    let initial_h = rows.load(Ordering::Acquire);
    let mut term = Terminal::with_options(
        backend,
        TerminalOptions {
            viewport: Viewport::Fixed(Rect::new(0, 0, initial_w, initial_h)),
        },
    )
    .expect("terminal");

    let mut view = make_view(&view_name);
    let mut tick = time::interval(Duration::from_millis(2_000));

    loop {
        tokio::select! {
            /* ── a) input from Neovim ─────────────────────────────────── */
            Some(bytes) = rx_in.recv() => {
                if let Some(ev) = bytes_to_event(&bytes) {
                    if matches!(ev, Event::Key(KeyEvent{code:KeyCode::Char('q'),..})) {
                        open.store(false, Ordering::Release);
                        break;
                    }
                    if view.on_event(&ev) { draw(&mut term, &mut *view); }
                }
            }

            /* ── b) periodic tick ─────────────────────────────────────── */
            _ = tick.tick() => {
                draw(&mut term, &mut *view);
            }

            /* ── c) cooperative yield allows resize updates ───────────── */
            else => {
                let w = cols.load(Ordering::Acquire);
                let h = rows.load(Ordering::Acquire);
                term.resize(Rect::new(0,0,w,h)).ok();
            }
        }
    }

    disable_raw_mode().ok();
}

fn draw(term: &mut Terminal<CrosstermBackend<NvWriter>>, view: &mut dyn View) {
    let _ = term.draw(|f| {
        let area = f.area();
        view.draw(f, area);
    });
}
