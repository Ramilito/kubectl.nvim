//! UI module for the kubectl dashboard.
//!
//! This module provides a ratatui-based UI for displaying Kubernetes cluster
//! metrics and information. It renders to native Neovim buffers via a custom
//! backend that outputs structured data (lines + extmarks).
//!
//! ## Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                         session.rs                              │
//! │  BufferSession (Lua FFI) ─── run_buffer_ui ─── NeovimBackend   │
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
//! - `session` - BufferSession management and Lua FFI bindings
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

// Re-export main session type for FFI registration
pub use session::BufferSession;
