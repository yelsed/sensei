mod ai;
mod config;
mod display;
mod tip;

use clap::{Parser, Subcommand};
use config::{load_config, load_stack};
use std::path::PathBuf;
use tip::{get_tip, list_topics, load_tips};

#[derive(Parser)]
#[command(name = "sensei", about = "Your personal tech stack learning assistant")]
struct Cli {
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Subcommand)]
enum Command {
    /// Show a random tip (default)
    Tip {
        /// Filter by topic
        #[arg(short, long)]
        topic: Option<String>,
    },
    /// Explain a line of code or a concept
    Explain {
        /// Code or text to explain
        input: String,
        /// File language (e.g. typescript, rust)
        #[arg(long)]
        lang: Option<String>,
        /// Surrounding file context
        #[arg(long)]
        context: Option<String>,
    },
    /// Ask a question about your tech stack
    Ask {
        /// Your question
        question: String,
        /// Override Ollama model
        #[arg(short, long)]
        model: Option<String>,
    },
    /// List available tip topics
    Topics,
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();
    let config = load_config();

    let tips_path = config
        .tips_file
        .as_deref()
        .map(|p| PathBuf::from(shellexpand::tilde(p).as_ref()))
        .unwrap_or_else(|| config::config_dir().join("tips.json"));

    let tips = load_tips(&tips_path);

    match cli.command.unwrap_or(Command::Tip { topic: None }) {
        Command::Tip { topic } => {
            let topic_ref = topic.as_deref();
            match get_tip(&tips, topic_ref) {
                Some(t) => display::print_tip(&t.topic, &t.tip),
                None => {
                    eprintln!("No tips found{}", topic.map(|t| format!(" for topic '{t}'")).unwrap_or_default());
                    std::process::exit(1);
                }
            }
        }

        Command::Explain { input, lang, context } => {
            let model = &config.model;
            let stack = load_stack(&config).unwrap_or_else(|| "General developer".to_string());

            match ai::generate_tip(model, &stack, None, None, Some(&input), lang.as_deref(), context.as_deref()).await {
                Ok(response) => display::print_tip("EXPLAIN", &response),
                Err(e) => {
                    eprintln!("Ollama unavailable ({e}), falling back to static tip.");
                    if let Some(t) = get_tip(&tips, None) {
                        display::print_tip(&t.topic, &t.tip);
                    }
                }
            }
        }

        Command::Ask { question, model } => {
            let model = model.as_deref().unwrap_or(&config.model);
            let stack = load_stack(&config).unwrap_or_else(|| "General developer".to_string());

            match ai::generate_tip(model, &stack, None, Some(&question), None, None, None).await {
                Ok(response) => display::print_tip("SENSEI", &response),
                Err(e) => {
                    eprintln!("Ollama unavailable ({e}), falling back to static tip.");
                    if let Some(t) = get_tip(&tips, None) {
                        display::print_tip(&t.topic, &t.tip);
                    }
                }
            }
        }

        Command::Topics => {
            let topics = list_topics(&tips);
            println!("Available topics:");
            for t in topics {
                println!("  {t}");
            }
        }
    }
}
