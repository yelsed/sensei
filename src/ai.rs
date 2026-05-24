use ollama_rs::{
    generation::completion::request::GenerationRequest, Ollama,
};

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
