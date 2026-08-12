use crate::drawable::{DrawMode, DrawRow, Drawable, Slot};

pub fn render(d: &Drawable) -> String {
    let mut out = String::new();

    let mode_label = match d.mode {
        DrawMode::Select => "select",
        DrawMode::Edit => " edit ",
    };

    let title = format!(" Sessions [{}]", mode_label);
    let padding = d.cols.saturating_sub(title.len());
    out.push_str(&format!("{}{}\n", title, " ".repeat(padding)));
    out.push_str(&format!("{}\n", "─".repeat(d.cols)));

    if !d.loaded {
        out.push_str("  waiting for permissions...\n");
        return out;
    }

    let mut content_lines: usize = 0;

    for row in &d.rows {
        match row {
            DrawRow::Divider => {
                out.push_str(&format!("{}\n", "─".repeat(d.cols)));
                content_lines += 1;
            }
            DrawRow::Session(sr) => {
                let cursor_ch = if sr.has_cursor { "▶" } else { " " };
                let cur_ch = if sr.is_current { "*" } else { " " };
                let key_ch = match sr.slot {
                    Slot::Pinned(n) => format!("{}", n),
                    Slot::Unpinned(c) => format!("{}", c),
                };
                out.push_str(&format!(
                    "{} [{}] {} {}\n",
                    cursor_ch, key_ch, cur_ch, sr.name
                ));
                content_lines += 1;
            }
        }
    }

    if d.rows.is_empty() {
        out.push_str("  (no sessions)\n");
        content_lines += 1;
    }

    // Pad to push footer to bottom
    let used = 2 + content_lines + 2; // header + content + footer
    for _ in used..d.total_rows {
        out.push('\n');
    }

    out.push_str(&format!("{}\n", "─".repeat(d.cols)));
    let footer = match d.mode {
        DrawMode::Select => " 1-9 pinned  a-z others  ^e edit  Esc close",
        DrawMode::Edit => " j/k nav  Enter jump  m pin  1-9 slot  u unpin  ^j/k reorder  Esc back",
    };
    out.push_str(footer);

    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::drawable::{DrawMode, DrawRow, Drawable, SessionRow, Slot};

    fn simple_drawable(sessions: Vec<(&str, bool)>, mode: DrawMode) -> Drawable {
        let rows = sessions
            .into_iter()
            .enumerate()
            .map(|(i, (name, is_current))| {
                DrawRow::Session(SessionRow {
                    slot: Slot::Pinned(i + 1),
                    name: name.to_string(),
                    is_current,
                    has_cursor: false,
                })
            })
            .collect();
        Drawable { rows, mode, loaded: true, cols: 40, total_rows: 10 }
    }

    #[test]
    fn renders_session_names() {
        let d = simple_drawable(vec![("main", true), ("work", false)], DrawMode::Select);
        let out = render(&d);
        assert!(out.contains("main"));
        assert!(out.contains("work"));
    }

    #[test]
    fn marks_current_session() {
        let d = simple_drawable(vec![("main", true), ("work", false)], DrawMode::Select);
        let out = render(&d);
        // current gets * marker
        assert!(out.contains("* main"));
        assert!(out.contains("  work"));
    }

    #[test]
    fn shows_slot_numbers() {
        let d = simple_drawable(vec![("main", false), ("work", false)], DrawMode::Select);
        let out = render(&d);
        assert!(out.contains("[1]"));
        assert!(out.contains("[2]"));
    }

    #[test]
    fn shows_mode_label() {
        let d_select = simple_drawable(vec![], DrawMode::Select);
        assert!(render(&d_select).contains("select"));

        let d_edit = simple_drawable(vec![], DrawMode::Edit);
        assert!(render(&d_edit).contains("edit"));
    }

    #[test]
    fn shows_loading_message_when_not_loaded() {
        let d = Drawable {
            rows: vec![],
            mode: DrawMode::Select,
            loaded: false,
            cols: 40,
            total_rows: 10,
        };
        assert!(render(&d).contains("waiting for permissions"));
    }

    #[test]
    fn cursor_shown_in_edit_mode() {
        let d = Drawable {
            rows: vec![DrawRow::Session(SessionRow {
                slot: Slot::Pinned(1),
                name: "main".into(),
                is_current: false,
                has_cursor: true,
            })],
            mode: DrawMode::Edit,
            loaded: true,
            cols: 40,
            total_rows: 10,
        };
        assert!(render(&d).contains("▶"));
    }

    #[test]
    fn divider_rendered() {
        let d = Drawable {
            rows: vec![
                DrawRow::Session(SessionRow {
                    slot: Slot::Pinned(1),
                    name: "pinned".into(),
                    is_current: false,
                    has_cursor: false,
                }),
                DrawRow::Divider,
                DrawRow::Session(SessionRow {
                    slot: Slot::Unpinned('a'),
                    name: "free".into(),
                    is_current: false,
                    has_cursor: false,
                }),
            ],
            mode: DrawMode::Select,
            loaded: true,
            cols: 40,
            total_rows: 15,
        };
        let out = render(&d);
        assert!(out.contains("[1]"));
        assert!(out.contains("[a]"));
        // two divider lines (header + middle)
        assert_eq!(out.matches("─".repeat(40).as_str()).count(), 3); // header + divider + footer
    }
}
