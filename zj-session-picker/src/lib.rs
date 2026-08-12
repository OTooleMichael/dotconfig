use std::collections::BTreeMap;
use zellij_tile::prelude::*;

#[no_mangle]
pub extern "C" fn _start() {}

#[derive(Default)]
struct State;

register_plugin!(State);

impl ZellijPlugin for State {
    fn load(&mut self, _config: BTreeMap<String, String>) {
        subscribe(&[EventType::Key, EventType::ModeUpdate]);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::Key(key) if key.bare_key == BareKey::Esc => {
                close_self();
                false
            }
            // ModeUpdate fires on load — return true to trigger first render
            Event::ModeUpdate(_) => true,
            _ => false,
        }
    }

    fn render(&mut self, _rows: usize, _cols: usize) {
        print!("\u{1b}[1;1HHello from plugin! Press Esc to close.");
    }
}
