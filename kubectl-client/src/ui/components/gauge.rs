//! Reusable gauge widget factory.

use ratatui::{
    style::{palette::tailwind, Color, Style},
    widgets::Gauge,
};

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
            GaugeStyle::Cpu => tailwind::GREEN.c500,
            GaugeStyle::Memory => tailwind::ORANGE.c400,
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
        .gauge_style(Style::default().fg(style.color()).bg(tailwind::GRAY.c800))
        .label(format!("{label}: {}", percent.round() as u16))
        .use_unicode(true)
        .percent(percent.clamp(0.0, 100.0) as u16)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_gauge_style_colors() {
        assert_eq!(GaugeStyle::Cpu.color(), tailwind::GREEN.c500);
        assert_eq!(GaugeStyle::Memory.color(), tailwind::ORANGE.c400);
        assert_eq!(GaugeStyle::Custom(Color::Red).color(), Color::Red);
    }
}
