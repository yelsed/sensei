use ollama_rs::{
    generation::chat::{request::ChatMessageRequest, ChatMessage},
    generation::completion::request::GenerationRequest,
    Ollama,
};
use serde::Deserialize;

/// One turn in a chat transcript. Deserialized from the JSON the editor sends
/// over stdin to `sensei chat`.
#[derive(Deserialize)]
pub struct ChatMsg {
    pub role: String,
    pub content: String,
}

/// Editor context for a context-aware tip. Any field may be empty.
#[derive(Default)]
pub struct EditorContext<'a> {
    pub lang: Option<&'a str>,
    pub mode: Option<&'a str>,
    pub line: Option<&'a str>,
}

impl EditorContext<'_> {
    pub fn is_empty(&self) -> bool {
        self.lang.is_none() && self.mode.is_none() && self.line.is_none()
    }
}

pub async fn generate_tip(
    model: &str,
    stack_context: &str,
    topic: Option<&str>,
    question: Option<&str>,
    code: Option<&str>,
    lang: Option<&str>,
    file_context: Option<&str>,
) -> Result<String, String> {
    let ollama = Ollama::default();

    let prompt = build_prompt(stack_context, topic, question, code, lang, file_context);

    let request = GenerationRequest::new(model.to_string(), prompt);

    match ollama.generate(request).await {
        Ok(response) => Ok(response.response.trim().to_string()),
        Err(e) => Err(e.to_string()),
    }
}

/// Context-aware tip: suggest a Neovim motion/command relevant to what the
/// developer is editing right now.
pub async fn context_tip(
    model: &str,
    stack_context: &str,
    ctx: &EditorContext<'_>,
) -> Result<String, String> {
    let ollama = Ollama::default();
    let prompt = build_context_tip_prompt(stack_context, ctx);
    let request = GenerationRequest::new(model.to_string(), prompt);

    match ollama.generate(request).await {
        Ok(response) => Ok(response.response.trim().to_string()),
        Err(e) => Err(e.to_string()),
    }
}

/// Multi-turn chat. The transcript is stateless: the editor owns the history and
/// sends the full message list each turn. We prepend a mentor system prompt.
pub async fn chat(
    model: &str,
    stack_context: &str,
    messages: &[ChatMsg],
) -> Result<String, String> {
    let ollama = Ollama::default();

    let mut chat_messages = Vec::with_capacity(messages.len() + 1);
    chat_messages.push(ChatMessage::system(format!(
        "You are a concise, friendly coding mentor helping a developer learn (especially Neovim). \
         Give practical, specific answers with concrete commands or keystrokes. \
         Keep replies short unless asked to go deep. The developer's stack:\n{stack_context}"
    )));
    for m in messages {
        let cm = match m.role.as_str() {
            "assistant" => ChatMessage::assistant(m.content.clone()),
            "system" => ChatMessage::system(m.content.clone()),
            _ => ChatMessage::user(m.content.clone()),
        };
        chat_messages.push(cm);
    }

    let request = ChatMessageRequest::new(model.to_string(), chat_messages);

    match ollama.send_chat_messages(request).await {
        Ok(response) => Ok(response.message.content.trim().to_string()),
        Err(e) => Err(e.to_string()),
    }
}

/// Summarize a raw detected-dependency list (e.g. Neovim plugins) into a short,
/// clean markdown stack description. Used by `sensei stack` to populate
/// `detected_stack.md`. Returns Err with the Ollama error string if unreachable.
pub async fn summarize_stack(model: &str, raw_plugin_list: &str) -> Result<String, String> {
    let ollama = Ollama::default();
    let prompt = format!(
        "You are a concise technical writer. Below is a raw list of a developer's \
         Neovim plugins. Write a short, clean markdown description of their stack and \
         tooling: group related plugins, name the key technologies, and infer the editor \
         workflow (e.g. completion, LSP, fuzzy finding). Do not list every plugin verbatim \
         — summarize. Output markdown only, no preamble.\n\n{raw_plugin_list}"
    );
    let request = GenerationRequest::new(model.to_string(), prompt);

    match ollama.generate(request).await {
        Ok(response) => Ok(response.response.trim().to_string()),
        Err(e) => Err(e.to_string()),
    }
}

fn build_prompt(
    stack: &str,
    topic: Option<&str>,
    question: Option<&str>,
    code: Option<&str>,
    lang: Option<&str>,
    file_context: Option<&str>,
) -> String {
    if let Some(q) = question {
        return format!(
            "You are a concise coding mentor. The developer's stack:\n{stack}\n\nAnswer this in 2-3 sentences max, be direct and practical:\n{q}"
        );
    }

    if let Some(c) = code {
        let lang_line = lang.map(|l| format!("File language: {l}\n\n")).unwrap_or_default();
        let ctx_section = file_context
            .map(|ctx| format!("Surrounding file context:\n```\n{ctx}\n```\n\n"))
            .unwrap_or_default();
        return format!(
            "You are a concise coding mentor. The developer's stack:\n{stack}\n\n{lang_line}{ctx_section}Explain the following code in 2-3 sentences. Focus on what it does and any important concept to learn:\n```\n{c}\n```"
        );
    }

    let topic_str = topic.unwrap_or("general programming");
    format!(
        "You are a concise coding mentor. The developer's stack:\n{stack}\n\nGive ONE short, actionable tip about {topic_str} that would help this developer improve. Max 2 sentences. Be specific and practical."
    )
}

fn build_context_tip_prompt(stack: &str, ctx: &EditorContext<'_>) -> String {
    let lang = ctx.lang.filter(|l| !l.is_empty()).unwrap_or("a file");
    let mode = match ctx.mode.unwrap_or("") {
        m if m.starts_with('i') => "insert",
        m if m.starts_with('v') || m.starts_with('V') => "visual",
        m if m.starts_with('n') => "normal",
        _ => "normal",
    };
    let line_section = ctx
        .line
        .filter(|l| !l.trim().is_empty())
        .map(|l| format!("The current line is:\n```\n{l}\n```\n\n"))
        .unwrap_or_default();

    format!(
        "You are a concise Neovim mentor. The developer's stack:\n{stack}\n\n\
         The developer is editing {lang} in {mode} mode. {line_section}\
         Suggest ONE concrete Neovim motion or command that would be genuinely useful right now. \
         Show the exact keystrokes, then one short sentence on what it does. Max 2 sentences total. \
         Prefer something a beginner might not know yet."
    )
}
