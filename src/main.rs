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
    /// Show a tip. With editor context flags, asks Ollama for a relevant one.
    Tip {
        /// Filter by topic
        #[arg(short, long)]
        topic: Option<String>,
        /// Filetype of the buffer (e.g. rust, lua) — enables a context-aware tip
        #[arg(long)]
        lang: Option<String>,
        /// Current editor mode (n, i, v) — enables a context-aware tip
        #[arg(long)]
        mode: Option<String>,
        /// Current line text — enables a context-aware tip
        #[arg(long)]
        line: Option<String>,
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
    /// Multi-turn chat. Reads a JSON messages array from stdin, prints the reply.
    Chat {
        /// Override Ollama model
        #[arg(short, long)]
        model: Option<String>,
    },
    /// List available tip topics
    Topics,
    /// Scaffold ~/.config/sensei/{config.toml, my_stack.md} if missing.
    Init,
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

    let default = Command::Tip {
        topic: None,
        lang: None,
        mode: None,
        line: None,
    };

    match cli.command.unwrap_or(default) {
        Command::Tip { topic, lang, mode, line } => {
            let ctx = ai::EditorContext {
                lang: lang.as_deref(),
                mode: mode.as_deref(),
                line: line.as_deref(),
            };

            // With editor context, try an Ollama-generated context-aware tip;
            // fall back to a static tip if Ollama is unreachable.
            let mut shown = false;
            if !ctx.is_empty() {
                let model = &config.model;
                let stack = load_stack(&config).unwrap_or_else(|| "General developer".to_string());
                match ai::context_tip(model, &stack, &ctx).await {
                    Ok(response) => {
                        display::print_tip("VIM TIP", &response);
                        shown = true;
                    }
                    Err(e) => {
                        eprintln!("Ollama unavailable ({e}), falling back to static tip.");
                    }
                }
            }

            if !shown {
                let topic_ref = topic.as_deref();
                match get_tip(&tips, topic_ref) {
                    Some(t) => display::print_tip(&t.topic, &t.tip),
                    None => {
                        eprintln!("No tips found{}", topic.map(|t| format!(" for topic '{t}'")).unwrap_or_default());
                        std::process::exit(1);
                    }
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

        Command::Chat { model } => {
            let model = model.as_deref().unwrap_or(&config.model);
            let stack = load_stack(&config).unwrap_or_else(|| "General developer".to_string());

            let input = match std::io::read_to_string(std::io::stdin()) {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("Failed to read stdin: {e}");
                    std::process::exit(1);
                }
            };

            let messages: Vec<ai::ChatMsg> = match serde_json::from_str(&input) {
                Ok(m) => m,
                Err(e) => {
                    eprintln!("Invalid chat JSON on stdin: {e}");
                    std::process::exit(1);
                }
            };

            match ai::chat(model, &stack, &messages).await {
                Ok(response) => println!("{response}"),
                Err(e) => {
                    eprintln!("Ollama unavailable ({e}).");
                    std::process::exit(1);
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

        Command::Init => {
            println!("{}", display::BANNER);
            println!();
            for (path, status) in config::init_files() {
                println!("{}: {}", path.display(), status);
            }
            println!("\nNext: edit your stack file, then run `ollama pull {}`.", config.model);
        }
    }
}
