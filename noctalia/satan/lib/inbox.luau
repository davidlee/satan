--!nonstrict
-- Pure core of the inbox widget: emacsclient result -> count -> presentation.
-- The count itself is owned by Emacs (`satan-inbox-unread-count').
local M = {}

M.query = { "emacsclient", "--eval", "(satan-inbox-unread-count)" }
M.windows = { "umbriel", "windows", "--json" }

-- Title of the dedicated inbox frame: how `open' recognises it.
M.frameTitle = "SATAN inbox"

-- Compositor-spawned so the new frame receives an activation token and focus.
-- `umbriel msg spawn` runs its argument through a shell, hence one string.
local spawnFrame = `emacsclient -c -n -F '((name . "{M.frameTitle}"))' -e '(satan-inbox)'`

-- Argv steps, run in order: if `windows` (decoded `umbriel windows --json`)
-- has the inbox frame, show the inbox in it (its buffer may have changed) and
-- focus it; else spawn it.
function M.open(windows)
  for _, w in windows or {} do
    if w.title == M.frameTitle then
      return {
        { "emacsclient", "--eval", `(satan-inbox-show-in-frame "{M.frameTitle}")` },
        { "umbriel", "msg", `window-focus:{w.id}` },
      }
    end
  end
  return { { "umbriel", "msg", "spawn", spawnFrame } }
end

-- Unread count from a `noctalia.runAsync` result, or nil when Emacs is
-- unreachable or answers with anything but a non-negative integer.
function M.count(result)
  if result.exitCode ~= 0 then
    return nil
  end
  local digits = string.match(result.stdout, "^%s*(%d+)%s*$")
  return digits and tonumber(digits)
end

-- Bar presentation for a count. Hidden at zero; visible-but-dim when the
-- count is unknown, so a broken query is noticed instead of passing for zero.
function M.view(n)
  if n == nil then
    return { visible = true, glyph = "inbox-off", text = "", tooltip = "SATAN inbox: unavailable" }
  end
  return { visible = n > 0, glyph = "inbox", text = tostring(n), tooltip = `SATAN inbox: {n} unread` }
end

return M
