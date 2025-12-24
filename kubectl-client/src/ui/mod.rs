//! UI module for the kubectl dashboard.
//!
//! This module provides a terminal UI for displaying Kubernetes cluster metrics
//! and information. It's designed to work with Neovim via the Lua FFI.
//!
//! ## Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                         session.rs                              │
//! │  Session (Lua FFI) ─── run_ui ─── Terminal<CrosstermBackend>   │
//! └───────────────────────────────┬─────────────────────────────────┘
//!                                 │
//!                                 ▼
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                          views/                                  │
//! │  View trait ─── TopView ─── OverviewView                        │
//! │       │              │              │                            │
//! │       │       TopViewState    OverviewState                      │
//! └───────┼──────────────────────────────────────────────────────────┘
//!         │
//!         ▼
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                       components/                                │
//! │  Gauge ─── HelpOverlay ─── Header                               │
//! └─────────────────────────────────────────────────────────────────┘
//! ```
//!
//! ## Modules
//!
//! - `session` - Session management and Lua FFI bindings
//! - `views` - View trait and implementations (Top, Overview)
//! - `components` - Reusable UI widgets (Gauge, HelpOverlay, Header)
//! - `events` - Event parsing and scroll handling
//! - `layout` - Layout calculation utilities
//! - `neovim_backend` - Custom backend for native Neovim buffer rendering

pub mod components;
pub mod events;
pub mod layout;
pub mod neovim_backend;
pub mod session;
pub mod views;

// Re-export main session types for FFI registration
pub use session::{BufferSession, Session};
