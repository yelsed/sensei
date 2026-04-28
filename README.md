# sensei

A Clippy-style learning assistant for your personal tech stack. Shows ambient tips and answers questions about Vim, Nuxt, Docker, Git, and Zsh — injected into the tools you already use.

Powered by a local Ollama LLM. No cloud API, no token costs.

---

## What was built

### Rust binary (`src/`)

The core of sensei. A single cross-platform binary that handles tip selection and AI queries.

```
sensei tip                        # random tip from curated list
sensei tip --topic vim            # tip filtered by topic
sensei explain "<code or text>"   # explain via Ollama
sensei ask "<question>"           # ask a question via Ollama
sensei topics                     # list available topics
```

If Ollama is not running, `explain` and `ask` fall back to a random static tip with a warning.

**Topics included:** vim, nuxt, docker, git, zsh (35 curated tips)

### Neovim plugin (`nvim/sensei.nvim/`)

The primary UX. Shows tips in a floating window centered on screen.

| Trigger | Action |
|---|---|
| `VimEnter` | Ambient tip, auto-dismisses after 8s |
| `<leader>st` | Show a random tip |
| `<leader>se` (normal) | Explain current line |
| `<leader>se` (visual) | Explain selected code |
| `<leader>sa` | Ask a question (input prompt) |
| `<Esc>` or cursor move | Close the floating window |

User commands: `:SenseiTip [topic]`, `:SenseiAsk <question>`, `:SenseiExplain <text>`

### VS Code extension (`vscode/`)

TypeScript extension that calls the `sensei` binary as a child process.

| Trigger | Action |
|---|---|
| Startup | Ambient tip as info notification |
| `Ctrl+Shift+T` | Show a tip |
| `Ctrl+Shift+E` | Explain selection or current line (WebviewPanel) |
| `Ctrl+Shift+A` | Ask a question (input box → WebviewPanel) |

Configure the binary path via `sensei.binaryPath` in VS Code settings if `sensei` is not on your PATH.

### Zed extension (`zed/`)

Rust/WASM extension. Registers slash commands in Zed's AI assistant panel.

| Command | Action |
|---|---|
| `/sensei-tip [topic]` | Insert a random tip |
| `/sensei-explain <code>` | Explain code or a concept |
| `/sensei-ask <question>` | Answer a question |

Note: Zed's extension API does not support floating windows next to code lines. This is the best available integration given that constraint.

---

## Project structure

```
sensei/
├── src/
│   ├── main.rs          # CLI entry point (clap)
│   ├── tip.rs           # Tip loading and random selection
│   ├── ai.rs            # Ollama integration
│   ├── display.rs       # ANSI styled box renderer
│   └── config.rs        # Config loading from ~/.config/sensei/
├── tips/
│   └── default.json     # 35 curated tips (bundled into binary)
├── nvim/
│   └── sensei.nvim/
│       ├── lua/sensei/
│       │   ├── init.lua       # Setup and config
│       │   ├── window.lua     # Floating window logic
│       │   └── commands.lua   # Keymaps and autocmds
│       └── plugin/sensei.lua  # Plugin entry point
├── vscode/
│   ├── src/extension.ts  # VS Code extension
│   └── package.json
├── zed/
│   ├── src/lib.rs        # Zed WASM extension
│   └── extension.toml
├── Cargo.toml
└── my_stack.md           # Your tech stack context (edit this)
```

---

## Configuration

### `~/.config/sensei/config.toml`

```toml
model = "phi3"                              # Ollama model to use
stack_file = "~/.config/sensei/my_stack.md"
tips_file = "~/.config/sensei/tips.json"   # optional: override bundled tips
```

### `my_stack.md`

This file is the AI's context. The more specific you are, the better the tips.

```markdown
## My Tech Stack
- Editor: Neovim
- Frontend: Nuxt 3 / Vue 3
- Containers: Docker
- Shell: Zsh

## My Learning Goals
- Get faster with Vim motions
- Understand Nuxt composables deeply

## My Environment
- OS: Linux / macOS
- Terminal: foot / WezTerm
```

---

## Next steps

### 1. Install the binary

```bash
cargo install --path .
```

Verify it works:

```bash
sensei tip
sensei tip --topic vim
```

### 2. Set up your stack context

```bash
mkdir -p ~/.config/sensei
cp my_stack.md ~/.config/sensei/my_stack.md
```

Edit `~/.config/sensei/my_stack.md` with your actual stack and learning goals.

### 3. (Optional) Configure Ollama

Install [Ollama](https://ollama.com) and pull a model:

```bash
ollama pull phi3
# or a larger model:
ollama pull llama3.2
```

Test AI mode:

```bash
sensei ask "what is the difference between useAsyncData and useFetch in Nuxt?"
```

Override the model in `~/.config/sensei/config.toml` if needed.

### 4. Wire up Neovim

Add to your lazy.nvim config:

```lua
{
  dir = "~/Projects/clippy-assistant/nvim/sensei.nvim",
  config = function()
    require("sensei").setup({
      binary = "sensei",         -- must be on PATH
      auto_tip = true,           -- show tip on VimEnter
      dismiss_timeout = 8000,    -- ms before auto-close
      keymaps = {
        tip     = "<leader>st",
        explain = "<leader>se",
        ask     = "<leader>sa",
      },
    })
  end,
}
```

Once published to GitHub, replace `dir` with `"yourusername/sensei.nvim"`.

### 5. Wire up VS Code

```bash
cd vscode
npm install
npm run compile
```

Then install the extension in VS Code:

```
Extensions panel → ... → Install from VSIX
```

Or during development, open the `vscode/` folder in VS Code and press `F5` to launch an Extension Development Host.

### 6. Wire up Zed

```bash
cd zed
cargo build --target wasm32-wasi --release
```

Then install via Zed's extension panel or copy the built extension to Zed's extensions directory. Use `/sensei-tip`, `/sensei-explain`, `/sensei-ask` in the AI assistant panel.

### 7. Add your own tips

Edit `~/.config/sensei/tips.json` (create it if it doesn't exist — it overrides the bundled list):

```json
[
  { "topic": "vim", "tip": "Your custom tip here.", "tags": ["editing"] }
]
```

---

## Ideas for later

- Shell hook: add `sensei tip` to `.zshrc` for a tip on each new terminal session
- Claude Code hook: fire a tip on Claude Code session start via a `PostToolUse` hook
- GitHub release with pre-built binaries for macOS and Linux
- Publish `sensei.nvim` to GitHub so lazy.nvim can install it directly
- Add more topics: TypeScript, Tailwind, SQL, Rust
# sensai
