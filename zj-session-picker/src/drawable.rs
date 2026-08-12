#[derive(Debug, Clone, PartialEq)]
pub enum Slot {
    Pinned(usize),
    Unpinned(char),
}

#[derive(Debug, Clone, PartialEq)]
pub struct SessionRow {
    pub slot: Slot,
    pub name: String,
    pub is_current: bool,
    pub has_cursor: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum DrawMode {
    Select,
    Edit,
}

#[derive(Debug, Clone)]
pub struct Drawable {
    pub rows: Vec<DrawRow>,
    pub mode: DrawMode,
    pub loaded: bool,
    pub cols: usize,
    pub total_rows: usize,
}

#[derive(Debug, Clone, PartialEq)]
pub enum DrawRow {
    Session(SessionRow),
    Divider,
}
