use colored::Colorize;

const BOX_WIDTH: usize = 52;

pub fn print_tip(topic: &str, content: &str) {
    let label = format!("  💡 {}", topic.to_uppercase());
    let top = format!("╭{}╮", "─".repeat(BOX_WIDTH));
    let bottom = format!("╰{}╯", "─".repeat(BOX_WIDTH));
    let empty = format!("│{}│", " ".repeat(BOX_WIDTH));

    println!("{}", top.bright_cyan());
    println!("{}", format!("│{:<width$}│", label, width = BOX_WIDTH).bright_cyan());
    println!("{}", empty.bright_cyan());

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
