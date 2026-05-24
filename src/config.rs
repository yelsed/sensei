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
