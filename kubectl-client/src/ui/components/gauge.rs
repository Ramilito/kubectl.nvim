//! Reusable gauge widget factory.

use ratatui::{
    style::{Color, Style},
    widgets::Gauge,
};

use crate::ui::colors;

/// Predefined gauge color schemes.
#[derive(Clone, Copy)]
pub enum GaugeStyle {
    Cpu,
    Memory,
    Custom(Color),
}

impl GaugeStyle {
    fn color(self) -> Color {
        match self {
            GaugeStyle::Cpu => colors::INFO,
            GaugeStyle::Memory => colors::WARNING,
            GaugeStyle::Custom(c) => c,
        }
    }
}

/// Creates a styled gauge widget with consistent appearance.
///
/// # Arguments
/// * `label` - Label prefix (e.g., "CPU", "MEM")
/// * `percent` - Value as percentage (0.0 - 100.0)
/// * `style` - Color scheme to use
///
/// # Example
/// ```ignore
/// let gauge = make_gauge("CPU", 75.5, GaugeStyle::Cpu);
/// ```
pub fn make_gauge(label: &str, percent: f64, style: GaugeStyle) -> Gauge<'static> {
    Gauge::default()
        .gauge_style(Style::default().fg(style.color()).bg(colors::GRAY_BG))
        .label(format!("{label}: {}", percent.round() as u16))
        .use_unicode(true)
        .percent(percent.clamp(0.0, 100.0) as u16)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_gauge_style_colors() {
        assert_eq!(GaugeStyle::Cpu.color(), colors::INFO);
        assert_eq!(GaugeStyle::Memory.color(), colors::WARNING);
        assert_eq!(GaugeStyle::Custom(Color::Red).color(), Color::Red);
    }
}
