use std::path::PathBuf;

use crate::drawable::{DrawMode, DrawRow, Drawable, SessionRow, Slot};
use crate::pins;

#[derive(Default, PartialEq, Clone, Debug)]
pub enum Mode {
    #[default]
    Select,
    Edit,
}

#[derive(Debug, PartialEq)]
pub enum Effect {
    Render,
    Jump(String),
    Close,
    Nothing,
}

#[derive(Default, Clone)]
pub struct KeyInput {
    pub bare: char,
    pub ctrl: bool,
}

impl KeyInput {
    pub fn plain(c: char) -> Self {
        Self { bare: c, ctrl: false }
    }
    pub fn ctrl(c: char) -> Self {
        Self { bare: c, ctrl: true }
    }
    pub fn esc() -> Self {
        Self { bare: '\x1b', ctrl: false }
    }
    pub fn enter() -> Self {
        Self { bare: '\n', ctrl: false }
    }
}

pub struct State {
    pub pinned: Vec<String>,
    pub live: Vec<String>,
    pub current: String,
    pub mode: Mode,
    pub cursor: usize,
    pub loaded: bool,
    pub pins_path: PathBuf,
}

impl Default for State {
    fn default() -> Self {
        Self {
            pinned: vec![],
            live: vec![],
            current: String::new(),
            mode: Mode::default(),
            cursor: 0,
            loaded: false,
            pins_path: pins::default_pins_path(),
        }
    }
}

impl State {
    pub fn with_pins_path(path: PathBuf) -> Self {
        Self { pins_path: path, ..Default::default() }
    }

    pub fn load_pins(&mut self) {
        self.pinned = pins::load(&self.pins_path);
    }

    pub fn apply_sessions(&mut self, live: Vec<String>, current: String) {
        self.live = live;
        self.live.sort();
        self.current = current;
        // Drop dead pins
        let live = self.live.clone();
        self.pinned.retain(|p| live.contains(p));
        self.save_pins();
        self.loaded = true;
        self.clamp_cursor();
    }

    pub fn apply_deletion(&mut self, live: Vec<String>, current: String) {
        let deleted = self.live.iter().any(|n| !live.contains(n));
        if deleted {
            self.apply_sessions(live, current);
        }
    }

    pub fn apply_key(&mut self, key: KeyInput) -> Effect {
        match self.mode {
            Mode::Select => self.select_key(key),
            Mode::Edit => self.edit_key(key),
        }
    }

    pub fn drawable(&self, cols: usize, total_rows: usize) -> Drawable {
        let unpinned = self.unpinned();
        let has_both = !self.pinned.is_empty() && !unpinned.is_empty();
        let mut rows = vec![];

        for (i, name) in self.pinned.iter().enumerate() {
            rows.push(DrawRow::Session(SessionRow {
                slot: Slot::Pinned(i + 1),
                name: name.clone(),
                is_current: *name == self.current,
                has_cursor: self.mode == Mode::Edit && self.cursor_index() == i,
            }));
        }

        if has_both {
            rows.push(DrawRow::Divider);
        }

        let pinned_len = self.pinned.len();
        for (i, name) in unpinned.iter().enumerate() {
            let letter = (b'a' + i as u8) as char;
            let display_idx = pinned_len + if has_both { 1 } else { 0 } + i;
            rows.push(DrawRow::Session(SessionRow {
                slot: Slot::Unpinned(letter),
                name: name.clone(),
                is_current: *name == self.current,
                has_cursor: self.mode == Mode::Edit && self.cursor_index() == pinned_len + i,
            }));
            let _ = display_idx;
        }

        Drawable {
            rows,
            mode: match self.mode {
                Mode::Select => DrawMode::Select,
                Mode::Edit => DrawMode::Edit,
            },
            loaded: self.loaded,
            cols,
            total_rows,
        }
    }

    // ── private ──────────────────────────────────────────────────────────────

    fn unpinned(&self) -> Vec<String> {
        self.live.iter().filter(|s| !self.pinned.contains(s)).cloned().collect()
    }

    fn session_count(&self) -> usize {
        self.pinned.len() + self.unpinned().len()
    }

    fn cursor_index(&self) -> usize {
        self.cursor
    }

    fn clamp_cursor(&mut self) {
        let len = self.session_count();
        if len == 0 {
            self.cursor = 0;
        } else if self.cursor >= len {
            self.cursor = len - 1;
        }
    }

    fn save_pins(&self) {
        pins::save(&self.pins_path, &self.pinned);
    }

    fn name_at_cursor(&self) -> Option<String> {
        let mut all: Vec<String> = self.pinned.clone();
        all.extend(self.unpinned());
        all.get(self.cursor).cloned()
    }

    fn pin_append(&mut self, name: &str) {
        if !self.pinned.contains(&name.to_string()) {
            self.pinned.push(name.to_string());
            self.save_pins();
        }
    }

    fn pin_to_slot(&mut self, name: &str, slot: usize) {
        self.pinned.retain(|p| p != name);
        let idx = (slot - 1).min(self.pinned.len());
        self.pinned.insert(idx, name.to_string());
        self.save_pins();
    }

    fn unpin(&mut self, name: &str) {
        self.pinned.retain(|p| p != name);
        self.save_pins();
        self.clamp_cursor();
    }

    fn move_cursor_pin_down(&mut self) {
        if self.cursor + 1 < self.pinned.len() {
            self.pinned.swap(self.cursor, self.cursor + 1);
            self.cursor += 1;
            self.save_pins();
        }
    }

    fn move_cursor_pin_up(&mut self) {
        if self.cursor > 0 && self.cursor < self.pinned.len() {
            self.pinned.swap(self.cursor, self.cursor - 1);
            self.cursor -= 1;
            self.save_pins();
        }
    }

    fn select_key(&mut self, key: KeyInput) -> Effect {
        if key.bare == '\x1b' {
            return Effect::Close;
        }
        if key.ctrl && key.bare == 'e' {
            self.mode = Mode::Edit;
            return Effect::Render;
        }
        if !key.ctrl {
            if key.bare.is_ascii_digit() {
                let slot = key.bare.to_digit(10).unwrap() as usize;
                let idx = if slot == 0 { 9 } else { slot - 1 };
                if let Some(name) = self.pinned.get(idx) {
                    return Effect::Jump(name.clone());
                }
            }
            if key.bare.is_ascii_lowercase() {
                let unpinned = self.unpinned();
                let idx = (key.bare as u8 - b'a') as usize;
                if let Some(name) = unpinned.get(idx) {
                    return Effect::Jump(name.clone());
                }
            }
        }
        Effect::Nothing
    }

    fn edit_key(&mut self, key: KeyInput) -> Effect {
        if key.bare == '\x1b' {
            self.mode = Mode::Select;
            return Effect::Render;
        }
        if key.bare == '\n' {
            if let Some(name) = self.name_at_cursor() {
                return Effect::Jump(name);
            }
        }
        if !key.ctrl {
            match key.bare {
                'j' => {
                    let len = self.session_count();
                    if self.cursor + 1 < len { self.cursor += 1; }
                    return Effect::Render;
                }
                'k' => {
                    if self.cursor > 0 { self.cursor -= 1; }
                    return Effect::Render;
                }
                'm' => {
                    if let Some(name) = self.name_at_cursor() {
                        self.pin_append(&name);
                    }
                    return Effect::Render;
                }
                'u' => {
                    if let Some(name) = self.name_at_cursor() {
                        self.unpin(&name);
                    }
                    return Effect::Render;
                }
                c if c.is_ascii_digit() => {
                    let slot = c.to_digit(10).unwrap() as usize;
                    if slot > 0 {
                        if let Some(name) = self.name_at_cursor() {
                            self.pin_to_slot(&name, slot);
                        }
                    }
                    return Effect::Render;
                }
                _ => {}
            }
        }
        if key.ctrl {
            match key.bare {
                'j' => { self.move_cursor_pin_down(); return Effect::Render; }
                'k' => { self.move_cursor_pin_up(); return Effect::Render; }
                _ => {}
            }
        }
        Effect::Nothing
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    fn state_with_sessions(pinned: Vec<&str>, live: Vec<&str>, current: &str) -> State {
        let f = NamedTempFile::new().unwrap();
        let mut s = State::with_pins_path(f.path().to_path_buf());
        s.pinned = pinned.iter().map(|x| x.to_string()).collect();
        s.live = live.iter().map(|x| x.to_string()).collect();
        s.current = current.to_string();
        s.loaded = true;
        s
    }

    #[test]
    fn esc_in_select_closes() {
        let mut s = state_with_sessions(vec![], vec!["main"], "main");
        assert_eq!(s.apply_key(KeyInput::esc()), Effect::Close);
    }

    #[test]
    fn digit_jumps_to_pinned() {
        let mut s = state_with_sessions(vec!["main", "work"], vec!["main", "work"], "work");
        assert_eq!(s.apply_key(KeyInput::plain('1')), Effect::Jump("main".into()));
        assert_eq!(s.apply_key(KeyInput::plain('2')), Effect::Jump("work".into()));
    }

    #[test]
    fn letter_jumps_to_unpinned() {
        let mut s = state_with_sessions(vec![], vec!["alpha", "beta"], "alpha");
        assert_eq!(s.apply_key(KeyInput::plain('a')), Effect::Jump("alpha".into()));
        assert_eq!(s.apply_key(KeyInput::plain('b')), Effect::Jump("beta".into()));
    }

    #[test]
    fn ctrl_e_enters_edit() {
        let mut s = state_with_sessions(vec![], vec!["main"], "main");
        assert_eq!(s.apply_key(KeyInput::ctrl('e')), Effect::Render);
        assert_eq!(s.mode, Mode::Edit);
    }

    #[test]
    fn esc_in_edit_returns_to_select() {
        let mut s = state_with_sessions(vec![], vec!["main"], "main");
        s.mode = Mode::Edit;
        s.apply_key(KeyInput::esc());
        assert_eq!(s.mode, Mode::Select);
    }

    #[test]
    fn j_k_moves_cursor() {
        let mut s = state_with_sessions(vec!["a", "b", "c"], vec!["a", "b", "c"], "a");
        s.mode = Mode::Edit;
        s.apply_key(KeyInput::plain('j'));
        assert_eq!(s.cursor, 1);
        s.apply_key(KeyInput::plain('j'));
        assert_eq!(s.cursor, 2);
        s.apply_key(KeyInput::plain('k'));
        assert_eq!(s.cursor, 1);
    }

    #[test]
    fn cursor_clamps_at_bounds() {
        let mut s = state_with_sessions(vec!["a", "b"], vec!["a", "b"], "a");
        s.mode = Mode::Edit;
        s.apply_key(KeyInput::plain('k')); // already at 0
        assert_eq!(s.cursor, 0);
        s.apply_key(KeyInput::plain('j'));
        s.apply_key(KeyInput::plain('j'));
        s.apply_key(KeyInput::plain('j')); // past end
        assert_eq!(s.cursor, 1);
    }

    #[test]
    fn m_pins_unpinned_session() {
        let mut s = state_with_sessions(vec![], vec!["main"], "main");
        s.mode = Mode::Edit;
        s.apply_key(KeyInput::plain('m'));
        assert_eq!(s.pinned, vec!["main"]);
    }

    #[test]
    fn u_unpins_pinned_session() {
        let mut s = state_with_sessions(vec!["main"], vec!["main"], "main");
        s.mode = Mode::Edit;
        s.apply_key(KeyInput::plain('u'));
        assert!(s.pinned.is_empty());
    }

    #[test]
    fn pin_to_slot_reorders() {
        let mut s = state_with_sessions(vec!["a", "b", "c"], vec!["a", "b", "c"], "a");
        s.mode = Mode::Edit;
        s.cursor = 2; // on "c"
        s.apply_key(KeyInput::plain('1'));
        assert_eq!(s.pinned[0], "c");
    }

    #[test]
    fn ctrl_j_k_reorders_pins() {
        let mut s = state_with_sessions(vec!["a", "b", "c"], vec!["a", "b", "c"], "a");
        s.mode = Mode::Edit;
        s.cursor = 0;
        s.apply_key(KeyInput::ctrl('j'));
        assert_eq!(s.pinned, vec!["b", "a", "c"]);
        assert_eq!(s.cursor, 1);
    }

    #[test]
    fn apply_sessions_drops_dead_pins() {
        let mut s = state_with_sessions(vec!["gone", "main"], vec!["gone", "main"], "main");
        s.apply_sessions(vec!["main".into()], "main".into());
        assert_eq!(s.pinned, vec!["main"]);
    }

    #[test]
    fn drawable_marks_current() {
        let s = state_with_sessions(vec!["main", "work"], vec!["main", "work"], "work");
        let d = s.drawable(80, 24);
        let work_row = d.rows.iter().find_map(|r| {
            if let crate::drawable::DrawRow::Session(sr) = r {
                if sr.name == "work" { return Some(sr.clone()); }
            }
            None
        });
        assert!(work_row.unwrap().is_current);
    }

    #[test]
    fn drawable_has_divider_when_both() {
        let s = state_with_sessions(vec!["pinned"], vec!["pinned", "free"], "pinned");
        let d = s.drawable(80, 24);
        assert!(d.rows.contains(&crate::drawable::DrawRow::Divider));
    }
}
