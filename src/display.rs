use colored::Colorize;
use std::io::{IsTerminal, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

const BOX_WIDTH: usize = 52;

/// A braille spinner animated on stderr while a slow Ollama call runs. Stops and
/// clears its line when dropped. No-op when stderr is not a TTY (e.g. the editor
/// drives the binary via jobstart) so it never pollutes captured output.
pub struct Spinner {
    done: Arc<AtomicBool>,
    handle: Option<thread::JoinHandle<()>>,
}

impl Spinner {
    pub fn start(msg: &str) -> Self {
        let done = Arc::new(AtomicBool::new(false));
        if !std::io::stderr().is_terminal() {
            return Spinner { done, handle: None };
        }
        let flag = done.clone();
        let msg = msg.to_string();
        let handle = thread::spawn(move || {
            let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
            let mut i = 0;
            while !flag.load(Ordering::Relaxed) {
                eprint!("\r{} {} ", frames[i % frames.len()].bright_cyan(), msg);
                let _ = std::io::stderr().flush();
                i += 1;
                thread::sleep(Duration::from_millis(80));
            }
            // Clear the spinner line so the result box renders cleanly.
            eprint!("\r\x1b[2K");
            let _ = std::io::stderr().flush();
        });
        Spinner {
            done,
            handle: Some(handle),
        }
    }
}

impl Drop for Spinner {
    fn drop(&mut self) {
        self.done.store(true, Ordering::Relaxed);
        if let Some(h) = self.handle.take() {
            let _ = h.join();
        }
    }
}

pub const BANNER: &str = r#"╔═══════════════════════════════╗
║    a mentor in your shell     ║
╟───────────────────────────────╢
║  ____ ____ _  _ ____ ____ _   ║
║  [__  |___ |\ | [__  |___ |   ║
║  ___] |___ | \| ___] |___ |   ║
║                               ║
╚═══════════════════════════════╝"#;

pub fn print_tip(topic: &str, content: &str) {
    print_tip_inner(topic, None, content);
}

/// Same box as `print_tip`, but with a yellow offline notice rendered inside it.
/// Used when an AI command falls back to a static tip because Ollama is unreachable.
pub fn print_tip_offline(topic: &str, content: &str) {
    print_tip_inner(
        topic,
        Some("⚠  Ollama offline — showing a static tip · run :SenseiHealth or `ollama serve`"),
        content,
    );
}

fn print_tip_inner(topic: &str, notice: Option<&str>, content: &str) {
    let label = format!("  💡 {}", topic.to_uppercase());
    let top = format!("╭{}╮", "─".repeat(BOX_WIDTH));
    let bottom = format!("╰{}╯", "─".repeat(BOX_WIDTH));
    let empty = format!("│{}│", " ".repeat(BOX_WIDTH));

    println!("{}", top.bright_cyan());
    println!("{}", format!("│{:<width$}│", label, width = BOX_WIDTH).bright_cyan());
    println!("{}", empty.bright_cyan());

    if let Some(notice) = notice {
        for line in wrap(notice, BOX_WIDTH - 4) {
            // Pad the plain text first (so width is correct), then color: border cyan, text yellow.
            let inner = format!("{:<width$}", line, width = BOX_WIDTH - 4);
            println!("{}{}{}", "│  ".bright_cyan(), inner.yellow(), "  │".bright_cyan());
        }
        println!("{}", empty.bright_cyan());
    }

    for line in wrap(content, BOX_WIDTH - 4) {
        let padded = format!("│  {:<width$}  │", line, width = BOX_WIDTH - 4);
        println!("{}", padded.bright_cyan());
    }

    println!("{}", empty.bright_cyan());
    println!("{}", bottom.bright_cyan());
}

fn wrap(text: &str, width: usize) -> Vec<String> {
    let mut lines = Vec::new();
    let mut current = String::new();

    for word in text.split_whitespace() {
        if current.is_empty() {
            current = word.to_string();
        } else if current.len() + 1 + word.len() <= width {
            current.push(' ');
            current.push_str(word);
        } else {
            lines.push(current.clone());
            current = word.to_string();
        }
    }
    if !current.is_empty() {
        lines.push(current);
    }
    lines
}
