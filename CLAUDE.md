# sensei

Clippy-style tech stack learning assistant. Ambient tips + interactive Q&A injected into Neovim, VS Code, and Zed. Local Ollama backend — no cloud API.

## Build

```bash
cargo build           # dev build
cargo build --release # release build
cargo install --path . # install `sensei` to PATH
```

Binary lands at `target/debug/sensei` or `target/release/sensei`.

## Test the binary

```bash
./target/debug/sensei tip
./target/debug/sensei tip --topic vim
./target/debug/sensei topics
./target/debug/sensei ask "how do I center a line in vim?"   # requires Ollama running
./target/debug/sensei explain "const { data } = useFetch('/api/user')"
```

## Project structure

```
src/
  main.rs       # clap CLI wiring — all subcommands defined here
  config.rs     # loads ~/.config/sensei/config.toml and my_stack.md
  tip.rs        # loads tips/default.json, random selection, topic filter
  display.rs    # ANSI box renderer (colored crate)
  ai.rs         # Ollama integration via ollama-rs

tips/
  default.json  # bundled tips — included at compile time via include_str!()
                # topics: vim, nuxt, docker, git, zsh

nvim/sensei.nvim/
  lua/sensei/
    init.lua      # setup(), merges user config with defaults
    window.lua    # nvim_open_win floating window, strips ANSI, auto-dismiss
    commands.lua  # keymaps (<leader>st/se/sa), VimEnter autocmd, user commands
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
- **Ollama fallback**: if Ollama is unreachable, `explain` and `ask` print a warning and fall back to a random static tip. Never hard-fail.
- **ANSI stripping**: the binary outputs colored ANSI boxes for the terminal. The Nvim plugin and VS Code extension both strip ANSI codes before rendering in their own UI.
- **`my_stack.md` as AI context**: loaded from `~/.config/sensei/my_stack.md` (or path in config.toml) and passed as the system prompt to Ollama. Richer file = better tips.
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

Install via lazy.nvim with `dir = "path/to/nvim/sensei.nvim"`. Call `require("sensei").setup({})`. The binary must be on PATH.

Keymaps: `<leader>st` tip · `<leader>se` explain line/selection · `<leader>sa` ask

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
