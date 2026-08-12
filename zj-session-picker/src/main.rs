mod drawable;
mod pins;
mod renderer;
mod state;

use std::collections::BTreeMap;
use zellij_tile::prelude::*;

use state::{Effect, KeyInput, State};

struct Plugin {
    state: State,
}

impl Default for Plugin {
    fn default() -> Self {
        Self { state: State::default() }
    }
}

register_plugin!(Plugin);

impl ZellijPlugin for Plugin {
    fn load(&mut self, _config: BTreeMap<String, String>) {
        self.state.load_pins();
        subscribe(&[
            EventType::Key,
            EventType::Timer,
            EventType::SessionUpdate,
            EventType::PermissionRequestResult,
        ]);
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
        ]);
        set_timeout(0.1);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::Timer(_) => true,

            Event::PermissionRequestResult(PermissionStatus::Granted) => {
                if let Ok(snapshot) = get_session_list() {
                    let live = snapshot.live_sessions.iter().map(|s| s.name.clone()).collect();
                    let current = snapshot
                        .live_sessions
                        .iter()
                        .find(|s| s.is_current_session)
                        .map(|s| s.name.clone())
                        .unwrap_or_default();
                    self.state.apply_sessions(live, current);
                }
                true
            }

            Event::SessionUpdate(infos, _) => {
                let live = infos.iter().map(|s| s.name.clone()).collect();
                let current = infos
                    .iter()
                    .find(|s| s.is_current_session)
                    .map(|s| s.name.clone())
                    .unwrap_or_default();
                self.state.apply_deletion(live, current);
                false
            }

            Event::Key(key) => {
                let input = zellij_key_to_input(key);
                match self.state.apply_key(input) {
                    Effect::Render => true,
                    Effect::Jump(name) => {
                        if name != self.state.current {
                            switch_session(Some(&name));
                        }
                        close_self();
                        false
                    }
                    Effect::Close => {
                        close_self();
                        false
                    }
                    Effect::Nothing => false,
                }
            }

            _ => false,
        }
    }

    fn render(&mut self, rows: usize, cols: usize) {
        let drawable = self.state.drawable(cols, rows);
        let output = renderer::render(&drawable);
        print!("{}", output);
    }
}

fn zellij_key_to_input(key: KeyWithModifier) -> KeyInput {
    let ctrl = key.key_modifiers.contains(&KeyModifier::Ctrl);
    match key.bare_key {
        BareKey::Esc => KeyInput::esc(),
        BareKey::Enter => KeyInput::enter(),
        BareKey::Char(c) => KeyInput { bare: c, ctrl },
        _ => KeyInput { bare: '\0', ctrl: false },
    }
}
