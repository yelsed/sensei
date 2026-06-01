use serde_json::Map;
use std::fs;
use std::path::PathBuf;

/// One detected dependency, source-agnostic so future sources (project deps,
/// VS Code extensions, ...) slot in without changing call sites.
pub struct DetectedItem {
    pub name: String,
    pub kind: ItemKind,
    pub detail: Option<String>,
}

pub enum ItemKind {
    NvimPlugin,
    // future: ProjectDep, VscodeExt, ...
}

impl ItemKind {
    fn label(&self) -> &'static str {
        match self {
            ItemKind::NvimPlugin => "Neovim plugins",
        }
    }
}

/// Extensibility seam: each detection source reports what it can find. A source
/// never errors — a missing or unreadable input yields an empty Vec.
pub trait StackSource {
    /// Source identifier — part of the extensibility seam, surfaced once more
    /// than one source exists (diagnostics / per-source toggles).
    #[allow(dead_code)]
    fn name(&self) -> &'static str;
    fn detect(&self) -> Vec<DetectedItem>;
}

/// Reads `~/.config/nvim/lazy-lock.json` — the lazy.nvim lockfile, a JSON object
/// keyed by plugin name. The keys are all the context the summarizer needs.
pub struct NvimLazySource;

impl StackSource for NvimLazySource {
    fn name(&self) -> &'static str {
        "nvim-lazy"
    }

    fn detect(&self) -> Vec<DetectedItem> {
        let Ok(contents) = fs::read_to_string(lazy_lock_path()) else {
            return Vec::new();
        };
        let Ok(map) = serde_json::from_str::<Map<String, serde_json::Value>>(&contents) else {
            return Vec::new();
        };
        map.into_iter()
            .map(|(name, _)| DetectedItem {
                name,
                kind: ItemKind::NvimPlugin,
                detail: None,
            })
            .collect()
    }
}

/// Path to the lazy.nvim lockfile, with `~` expansion.
pub fn lazy_lock_path() -> PathBuf {
    PathBuf::from(shellexpand::tilde("~/.config/nvim/lazy-lock.json").as_ref())
}

/// Run every known detection source and concatenate their results. Today only
/// `NvimLazySource`; add to the list to extend.
pub fn detect_all() -> Vec<DetectedItem> {
    let sources: Vec<Box<dyn StackSource>> = vec![Box::new(NvimLazySource)];
    sources.iter().flat_map(|s| s.detect()).collect()
}

/// Render the raw detected items into the plain-text block fed to Ollama — and
/// used verbatim as the offline fallback body written to disk.
pub fn render_raw(items: &[DetectedItem]) -> String {
    if items.is_empty() {
        return String::new();
    }
    // Group by kind label so the block reads cleanly when sources are mixed.
    let label = items[0].kind.label();
    let mut out = format!("Detected {label}:\n");
    for item in items {
        match &item.detail {
            Some(d) => out.push_str(&format!("- {} ({d})\n", item.name)),
            None => out.push_str(&format!("- {}\n", item.name)),
        }
    }
    out
}
