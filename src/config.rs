use dirs::home_dir;
use serde::Deserialize;
use std::fs;
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
