-- Quick preflight: is the binary installed, is Ollama up, what models exist.

local M = {}

function M.run(config)
  local lines = { "Sensei health", "" }
  local bin = config.binary

  -- 1. binary on PATH
  if vim.fn.executable(bin) == 1 then
    lines[#lines + 1] = "✓ binary '" .. bin .. "' found on PATH"
  else
    lines[#lines + 1] = "✗ binary '" .. bin .. "' NOT found"
    lines[#lines + 1] = "    fix: cargo install --path . (in the sensei repo)"
  end

  -- 2. Ollama reachable + models
  local body = ""
  if vim.fn.executable("curl") == 1 then
    local out = vim.fn.systemlist({ "curl", "-s", "-m", "2", "http://localhost:11434/api/tags" })
    if vim.v.shell_error == 0 then
      body = table.concat(out, "\n")
    end
  end

  if body:find("models") then
    lines[#lines + 1] = "✓ Ollama reachable at localhost:11434"

    local models = {}
    for name in body:gmatch('"name"%s*:%s*"([^"]+)"') do
      models[#models + 1] = name
    end
    if #models > 0 then
      lines[#lines + 1] = "    models: " .. table.concat(models, ", ")
    else
      lines[#lines + 1] = "    no models pulled yet — fix: ollama pull phi3"
    end
  else
    lines[#lines + 1] = "✗ Ollama not reachable on localhost:11434"
    lines[#lines + 1] = "    fix: start it with `ollama serve`, then `ollama pull phi3`"
  end

  -- 3. config scaffolding hint
  lines[#lines + 1] = ""
  lines[#lines + 1] = "tip: run `sensei init` to scaffold config + my_stack.md"

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Sensei" })
end

return M
