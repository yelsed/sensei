# sensei

Clippy-style tech stack learning assistant. Ambient tips + interactive Q&A injected into Neovim, VS Code, and Zed. Local Ollama backend — no cloud API.

## Build

```bash
cargo build           # dev build
cargo build --release # release build
cargo install --path . # install `sensei` to PATH
```

Binary lands at `target/debug/sensei` or `target/release/sensei`.

## Getting started (cold start)

```bash
cargo install --path .          # put `sensei` on PATH
sensei init                     # scaffold ~/.config/sensei/{config.toml,my_stack.md}
$EDITOR ~/.config/sensei/my_stack.md   # describe your stack — richer = better answers
ollama serve & ollama pull phi3 # local model the AI features use
nvim                            # <leader>st tip · <leader>sa chat · <leader>sh health
```

## Test the binary

```bash
./target/debug/sensei tip
./target/debug/sensei tip --topic vim
./target/debug/sensei tip --lang rust --mode n --line "fn main() {}"  # context-aware (AI; falls back to static if Ollama down)
./target/debug/sensei topics
./target/debug/sensei init                                     # scaffold config + my_stack.md (never overwrites)
./target/debug/sensei stack                                    # detect nvim plugins, AI-summarize into detected_stack.md (cached; no-op if unchanged)
./target/debug/sensei stack --force                            # regenerate even if lazy-lock.json unchanged
./target/debug/sensei ask "how do I center a line in vim?"     # requires Ollama running
./target/debug/sensei explain "const { data } = useFetch('/api/user')"
echo '[{"role":"user","content":"how do I delete a word in vim?"}]' | ./target/debug/sensei chat  # multi-turn; reads JSON transcript on stdin
```

## Project structure

```
src/
  main.rs       # clap CLI wiring — all subcommands defined here
  config.rs     # loads config.toml + my_stack.md; load_combined_stack merges my_stack.md + detected_stack.md; content-hash cache helpers
  detect.rs     # reads ~/.config/nvim/lazy-lock.json into a raw plugin list (StackSource trait — extensible to other sources)
  tip.rs        # loads tips/default.json, random selection, topic filter
  display.rs    # ANSI box renderer (colored crate)
  ai.rs         # Ollama integration via ollama-rs: generate_tip, context_tip, chat, summarize_stack

tips/
  default.json  # bundled tips — included at compile time via include_str!()
                # topics: vim, nuxt, docker, git, zsh

nvim/sensei.nvim/
  lua/sensei/
    init.lua      # setup(), merges user config with defaults
    window.lua    # floating window for tip/explain/ask, strips ANSI, auto-dismiss; show_tip passes editor context
    chat.lua      # persistent scrollable chat buffer, async jobstart, owns conversation history
    health.lua    # :SenseiHealth — checks binary on PATH + Ollama reachable + models
    commands.lua  # keymaps (<leader>st/se/sa/sh), VimEnter autocmd, user commands
  plugin/sensei.lua  # guard against double-load

vscode/
  src/extension.ts   # TypeScript extension, calls binary via child_process
  package.json       # commands: sensei.tip / .explain / .ask

zed/
  src/lib.rs         # Rust/WASM extension stub
  extension.toml     # extension metadata
  Cargo.toml         # separate crate, target: wasm32-wasip2
```

## Key design decisions

- **Tips bundled at compile time** via `include_str!("../tips/default.json")` in `tip.rs`. User can override with `~/.config/sensei/tips.json`.
- **Ollama fallback**: if Ollama is unreachable, `explain`, `ask`, and context-aware `tip` print a warning and fall back to a random static tip. Never hard-fail. Exception: `chat` exits non-zero with a stderr message (a chat needs a real reply, not a tip).
- **Context-aware tips**: `tip` with `--lang/--mode/--line` asks Ollama for a Neovim motion relevant to the current buffer. Nvim sends these on `<leader>st`. Plain `tip` (and the VimEnter ambient tip) stays static/offline so startup is instant.
- **Stateless chat**: the binary holds no session. The editor owns the conversation history and sends the full `[{role,content}]` transcript as JSON on stdin to `sensei chat` each turn; the binary prepends a mentor system prompt (+ `my_stack.md`) and returns the reply. Nvim runs this async via `jobstart` so the editor never freezes.
- **ANSI stripping**: the binary outputs colored ANSI boxes for the terminal. The Nvim plugin and VS Code extension both strip ANSI codes before rendering in their own UI.
- **`my_stack.md` as AI context**: `config::load_combined_stack` merges the hand-written `~/.config/sensei/my_stack.md` (or path in config.toml) with the AI-generated `detected_stack.md`, and passes the result as the system prompt to Ollama. Richer file = better tips.
- **Detected stack (`sensei stack`)**: `detect.rs` reads `~/.config/nvim/lazy-lock.json` (plugin names) and `ai::summarize_stack` has Ollama write a concise prose description into `~/.config/sensei/detected_stack.md` — kept **separate** from the hand-written `my_stack.md` so regeneration never clobbers manual notes. A content hash of `lazy-lock.json` is cached in `detected_stack.hash`; `sensei stack` no-ops when unchanged (`--force` overrides). Regeneration is **explicit-only** — the AI query paths just read the cached file via `load_combined_stack`, so they never call Ollama twice or block the editor. If Ollama is down, `sensei stack` prints a note and writes the raw plugin list as fallback (never hard-fails). Detection is extensible via the `StackSource` trait (future: project deps, VS Code extensions).
- **Zed limitation**: Zed extensions cannot place floating windows inline with code. Zed removed slash commands from the extension API (use MCP servers for AI panel integration instead). The Zed extension is currently a minimal stub.

## Adding tips

Edit `tips/default.json` (rebuilds into the binary) or add to `~/.config/sensei/tips.json` (runtime override, no rebuild needed):

```json
{ "topic": "vim", "tip": "Your tip here.", "tags": ["editing"] }
```

## Config

`~/.config/sensei/config.toml`:

```toml
model = "phi3"
stack_file = "~/.config/sensei/my_stack.md"
tips_file = "~/.config/sensei/tips.json"
```

## Neovim plugin

Install via lazy.nvim with `dir = "path/to/nvim/sensei.nvim"`. Call `require("sensei").setup({})`. The binary must be on PATH (`cargo install --path .`).

Keymaps:
- `<leader>st` — context-aware tip (uses current filetype/mode/line)
- `<leader>se` — explain current line / visual selection
- `<leader>sa` — open the chat buffer (follow-up Q&A; `i`/`a`/`<CR>` to ask, `q`/`<Esc>` to close)
- `<leader>sh` — health check

Commands: `:SenseiTip [topic]` · `:SenseiAsk <q>` (one-shot) · `:SenseiChat` · `:SenseiChatReset` · `:SenseiExplain <text>` · `:SenseiHealth`

First time? Run `:SenseiHealth` to confirm the binary and Ollama are wired up.

## VS Code extension

```bash
cd vscode && npm install && npm run compile
```

Load via `F5` in VS Code (Extension Development Host) or install from VSIX.

## Zed extension

```bash
cd zed && cargo build --target wasm32-wasip2 --release
```

Install via Zed's extension panel (`zed: extensions` → Install Dev Extension).
