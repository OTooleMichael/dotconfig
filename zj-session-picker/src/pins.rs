use std::fs;
use std::path::PathBuf;

pub fn default_pins_path() -> PathBuf {
    PathBuf::from("/Users/michaelotoole/.config/zj-session-picker/pins.json")
}

pub fn load(path: &PathBuf) -> Vec<String> {
    fs::read_to_string(path)
        .ok()
        .and_then(|s| parse_json_string_array(&s))
        .unwrap_or_default()
}

pub fn save(path: &PathBuf, pins: &[String]) {
    let json = format!(
        "[{}]",
        pins.iter()
            .map(|p| format!("\"{}\"", p.replace('"', "\\\"")))
            .collect::<Vec<_>>()
            .join(",")
    );
    let _ = fs::write(path, json);
}

fn parse_json_string_array(s: &str) -> Option<Vec<String>> {
    let s = s.trim();
    if !s.starts_with('[') || !s.ends_with(']') {
        return None;
    }
    let inner = &s[1..s.len() - 1];
    if inner.trim().is_empty() {
        return Some(vec![]);
    }
    inner
        .split(',')
        .map(|item| {
            let item = item.trim();
            if item.starts_with('"') && item.ends_with('"') {
                Some(item[1..item.len() - 1].replace("\\\"", "\""))
            } else {
                None
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    #[test]
    fn round_trips_pins() {
        let mut f = NamedTempFile::new().unwrap();
        let path = f.path().to_path_buf();
        let pins = vec!["main".to_string(), "work".to_string()];
        save(&path, &pins);
        let loaded = load(&path);
        assert_eq!(loaded, pins);
    }

    #[test]
    fn empty_array() {
        assert_eq!(parse_json_string_array("[]"), Some(vec![]));
    }

    #[test]
    fn malformed_returns_none() {
        assert_eq!(parse_json_string_array("not json"), None);
    }

    #[test]
    fn handles_missing_file() {
        let path = PathBuf::from("/tmp/zj-session-picker-nonexistent-test.json");
        assert_eq!(load(&path), vec![] as Vec<String>);
    }
}
