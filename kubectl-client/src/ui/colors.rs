//! Kubectl highlight colors.
//!
//! These RGB values must match `lua/kubectl/actions/highlight.lua`.
//! All dashboard UI components should use these constants for consistent theming.

use ratatui::style::Color;

pub const INFO: Color = Color::Rgb(0x60, 0x8B, 0x4E);      // #608B4E - green
pub const WARNING: Color = Color::Rgb(0xD1, 0x9A, 0x66);   // #D19A66 - orange
pub const ERROR: Color = Color::Rgb(0xD1, 0x69, 0x69);     // #D16969 - red
pub const DEBUG: Color = Color::Rgb(0xDC, 0xDC, 0xAA);     // #DCDCAA - yellow
pub const HEADER: Color = Color::Rgb(0x56, 0x9C, 0xD6);    // #569CD6 - blue
pub const SUCCESS: Color = Color::Rgb(0x4E, 0xC9, 0xB0);   // #4EC9B0 - cyan
pub const PENDING: Color = Color::Rgb(0xC5, 0x86, 0xC0);   // #C586C0 - purple
pub const GRAY: Color = Color::Rgb(0x66, 0x66, 0x66);      // #666666 - dark gray
pub const GRAY_BG: Color = Color::Rgb(0x3E, 0x44, 0x51);   // #3E4451 - background gray
