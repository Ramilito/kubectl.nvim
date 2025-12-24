//! Event parsing and handling utilities.
//!
//! Provides byte-to-event conversion and shared scroll handling logic.

use crossterm::event::{Event, KeyCode, KeyEvent, KeyModifiers};

/// Parsed message from Neovim
pub enum ParsedMessage {
    /// Regular input event
    Event(Event),
    /// Cursor line sync from Neovim (0-indexed)
    CursorLine(u16),
}

/// Parse bytes that might be a cursor sync message or regular input.
pub fn parse_message(bytes: &[u8]) -> Option<ParsedMessage> {
    // Check for cursor sync message: \x00CURSOR:<line>\x00
    // Using NUL bytes as delimiters since they won't appear in normal input
    if bytes.starts_with(b"\x00CURSOR:") {
        let content = &bytes[8..]; // Skip "\x00CURSOR:"
        if let Some(end_pos) = content.iter().position(|&b| b == 0x00) {
            let line_str = std::str::from_utf8(&content[..end_pos]).ok()?;
            let line: u16 = line_str.parse().ok()?;
            tracing::debug!("Parsed cursor line: {}", line);
            return Some(ParsedMessage::CursorLine(line));
        }
        tracing::debug!("Failed to parse cursor message: {:?}", bytes);
    }

    // Otherwise try to parse as regular input
    bytes_to_event(bytes).map(ParsedMessage::Event)
}

/// Converts raw bytes from Neovim into crossterm Events.
///
/// Handles ANSI escape sequences for special keys.
pub fn bytes_to_event(bytes: &[u8]) -> Option<Event> {
    use KeyCode::*;
    use KeyModifiers as M;

    macro_rules! key {
        ($code:expr) => {
            Event::Key(KeyEvent::new($code, M::NONE))
        };
    }

    match bytes {
        // Arrow keys
        b"\x1B[A" => Some(key!(Up)),
        b"\x1B[B" => Some(key!(Down)),
        b"\x1B[C" => Some(key!(Right)),
        b"\x1B[D" => Some(key!(Left)),
        // Page navigation
        b"\x1B[5~" => Some(key!(PageUp)),
        b"\x1B[6~" => Some(key!(PageDown)),
        // Tab variants
        b"\x1B[Z" => Some(key!(BackTab)),
        b"\t" => Some(key!(Tab)),
        // Editing
        b"\x7F" => Some(key!(Backspace)),
        b"\r" | b"\n" => Some(key!(Enter)),
        b"\x1B" => Some(key!(Esc)),
        // Printable ASCII characters
        [c @ 0x20..=0x7e] => Some(key!(Char(*c as char))),
        _ => None,
    }
}

/// Trait for types that support scrolling.
///
/// Provides a unified interface for scroll operations across different views.
pub trait Scrollable {
    fn scroll_down(&mut self);
    fn scroll_up(&mut self);
    fn scroll_page_down(&mut self);
    fn scroll_page_up(&mut self);
}

/// Handles scroll navigation keys for any Scrollable type.
///
/// Returns `true` if the key was handled, `false` otherwise.
pub fn handle_scroll_key<S: Scrollable>(state: &mut S, key: KeyCode) -> bool {
    match key {
        KeyCode::Down | KeyCode::Char('j') => {
            state.scroll_down();
            true
        }
        KeyCode::Up | KeyCode::Char('k') => {
            state.scroll_up();
            true
        }
        KeyCode::PageDown => {
            state.scroll_page_down();
            true
        }
        KeyCode::PageUp => {
            state.scroll_page_up();
            true
        }
        _ => false,
    }
}

/// Checks if the event is a quit command.
pub fn is_quit_event(event: &Event) -> bool {
    matches!(
        event,
        Event::Key(KeyEvent {
            code: KeyCode::Char('q'),
            ..
        })
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bytes_to_event_arrows() {
        assert!(matches!(
            bytes_to_event(b"\x1B[A"),
            Some(Event::Key(KeyEvent {
                code: KeyCode::Up,
                ..
            }))
        ));
        assert!(matches!(
            bytes_to_event(b"\x1B[B"),
            Some(Event::Key(KeyEvent {
                code: KeyCode::Down,
                ..
            }))
        ));
    }

    #[test]
    fn test_bytes_to_event_chars() {
        assert!(matches!(
            bytes_to_event(b"a"),
            Some(Event::Key(KeyEvent {
                code: KeyCode::Char('a'),
                ..
            }))
        ));
        assert!(matches!(
            bytes_to_event(b"/"),
            Some(Event::Key(KeyEvent {
                code: KeyCode::Char('/'),
                ..
            }))
        ));
    }

    #[test]
    fn test_is_quit_event() {
        let quit = Event::Key(KeyEvent::new(KeyCode::Char('q'), KeyModifiers::NONE));
        assert!(is_quit_event(&quit));

        let not_quit = Event::Key(KeyEvent::new(KeyCode::Char('a'), KeyModifiers::NONE));
        assert!(!is_quit_event(&not_quit));
    }

    struct MockScrollable {
        down_count: usize,
        up_count: usize,
    }

    impl Scrollable for MockScrollable {
        fn scroll_down(&mut self) {
            self.down_count += 1;
        }
        fn scroll_up(&mut self) {
            self.up_count += 1;
        }
        fn scroll_page_down(&mut self) {
            self.down_count += 10;
        }
        fn scroll_page_up(&mut self) {
            self.up_count += 10;
        }
    }

    #[test]
    fn test_handle_scroll_key() {
        let mut state = MockScrollable {
            down_count: 0,
            up_count: 0,
        };

        assert!(handle_scroll_key(&mut state, KeyCode::Down));
        assert_eq!(state.down_count, 1);

        assert!(handle_scroll_key(&mut state, KeyCode::Char('j')));
        assert_eq!(state.down_count, 2);

        assert!(handle_scroll_key(&mut state, KeyCode::Up));
        assert_eq!(state.up_count, 1);

        assert!(!handle_scroll_key(&mut state, KeyCode::Char('x')));
    }
}
