use dirs::home_dir;
use serde::Deserialize;
use std::fs;
use std::hash::{Hash, Hasher};
use std::path::PathBuf;

#[derive(Deserialize)]
pub struct Config {
    #[serde(default = "default_model")]
    pub model: String,
    pub stack_file: Option<String>,
    pub tips_file: Option<String>,
}

fn default_model() -> String {
    "phi3".to_string()
}

impl Default for Config {
    fn default() -> Self {
        Config {
            model: default_model(),
            stack_file: None,
            tips_file: None,
        }
    }
}

pub fn config_dir() -> PathBuf {
    home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".config")
        .join("sensei")
}

pub fn load_config() -> Config {
    let config_path = config_dir().join("config.toml");
    if let Ok(content) = fs::read_to_string(&config_path) {
        toml::from_str(&content).unwrap_or_default()
    } else {
        Config::default()
    }
}

pub fn stack_file_path(config: &Config) -> PathBuf {
    if let Some(path) = &config.stack_file {
        PathBuf::from(shellexpand::tilde(path).as_ref())
    } else {
        config_dir().join("my_stack.md")
    }
}

pub fn load_stack(config: &Config) -> Option<String> {
    let path = stack_file_path(config);
    fs::read_to_string(&path).ok()
}

/// AI-generated stack description, written by `sensei stack`. Kept separate from
/// the hand-written `my_stack.md` so regeneration never clobbers manual notes.
pub fn detected_stack_path() -> PathBuf {
    config_dir().join("detected_stack.md")
}

/// Cache sidecar: holds the content hash of the lazy-lock.json that produced the
/// current `detected_stack.md`, so `sensei stack` can no-op when nothing changed.
pub fn detected_hash_path() -> PathBuf {
    config_dir().join("detected_stack.hash")
}

/// Stable hash of a string. Used to detect lazy-lock.json content changes.
/// Content hash, not mtime — lazy.nvim rewrites the lockfile on every sync even
/// when its contents are identical.
pub fn content_hash(s: &str) -> String {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    s.hash(&mut hasher);
    format!("{:x}", hasher.finish())
}

pub fn read_cached_hash() -> Option<String> {
    fs::read_to_string(detected_hash_path())
        .ok()
        .map(|s| s.trim().to_string())
}

/// Effective AI context = hand-written `my_stack.md` + AI-detected stack,
/// combined. Either may be absent; returns None only if both are missing. This
/// only reads the cached `detected_stack.md` — no detection, no Ollama — so the
/// AI query paths stay fast and never block the editor.
pub fn load_combined_stack(config: &Config) -> Option<String> {
    let mine = load_stack(config);
    let detected = fs::read_to_string(detected_stack_path())
        .ok()
        .filter(|s| !s.trim().is_empty());
    match (mine, detected) {
        (Some(m), Some(d)) => Some(format!("{m}\n\n## Detected tooling\n\n{d}")),
        (Some(m), None) => Some(m),
        (None, Some(d)) => Some(format!("## Detected tooling\n\n{d}")),
        (None, None) => None,
    }
}

const STARTER_CONFIG: &str = r#"# sensei config
model = "phi3"
stack_file = "~/.config/sensei/my_stack.md"
tips_file = "~/.config/sensei/tips.json"
"#;

const STARTER_STACK: &str = r#"# My stack

Fill this in — the richer it is, the better sensei's tips and answers.

## Editor
- Neovim (learning the motions)

## Languages
-

## Tools
-

## What I want to get better at
- Neovim motions and shortcuts
"#;

/// Scaffold `config.toml` and `my_stack.md` in the config dir. Never overwrites
/// an existing file. Returns the status of each path so the caller can report it.
pub fn init_files() -> Vec<(PathBuf, &'static str)> {
    let dir = config_dir();
    let _ = fs::create_dir_all(&dir);

    let mut report = Vec::new();

    for (path, contents) in [
        (dir.join("config.toml"), STARTER_CONFIG),
        (dir.join("my_stack.md"), STARTER_STACK),
    ] {
        if path.exists() {
            report.push((path, "already present"));
        } else {
            match fs::write(&path, contents) {
                Ok(_) => report.push((path, "created")),
                Err(_) => report.push((path, "failed to write")),
            }
        }
    }

    report
}
