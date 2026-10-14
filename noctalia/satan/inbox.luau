--!nonstrict
-- Bar widget: SATAN inbox unread count, asked of Emacs every few seconds.
-- Click opens the inbox. `noctalia msg plugin davidlee/satan:inbox all refresh`
-- forces a poll.
local inbox = require("./lib/inbox.luau")

local inFlight = false

local function render(view)
  barWidget.setVisible(view.visible)
  barWidget.setGlyph(view.glyph)
  barWidget.setText(view.text)
  barWidget.setTooltip(view.tooltip)
end

local function refresh()
  if inFlight then
    return
  end
  inFlight = noctalia.runAsync(inbox.query, function(result)
    inFlight = false
    render(inbox.view(inbox.count(result)))
  end)
  if not inFlight then
    render(inbox.view(nil))
  end
end

noctalia.setUpdateInterval(10000)

function update()
  refresh()
end

-- Run argv steps in sequence, each after the previous exits.
local function runSteps(steps, i)
  i = i or 1
  if steps[i] then
    noctalia.runAsync(steps[i], function()
      runSteps(steps, i + 1)
    end)
  end
end

function onClick()
  noctalia.runAsync(inbox.windows, function(result)
    runSteps(inbox.open(noctalia.json.decode(result.stdout)))
  end)
end

function onIpc(event)
  if event == "refresh" then
    refresh()
  end
end
