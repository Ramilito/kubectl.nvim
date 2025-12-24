//! Reusable UI components.
//!
//! This module provides shared widgets and rendering utilities
//! that can be used across different views.

mod gauge;
mod header;
mod help_overlay;

pub use gauge::{make_gauge, GaugeStyle};
pub use header::draw_header;
pub use help_overlay::{draw_help_overlay, overview_help_items, top_view_help_items};
