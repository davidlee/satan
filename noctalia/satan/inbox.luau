--!nonstrict
-- Bar widget: SATAN inbox unread count, asked of Emacs every few seconds;
-- while unread, it blinks to the accent colour on a 2 s cycle.
-- Click opens the inbox. `noctalia msg plugin davidlee/satan:inbox all refresh`
-- forces a poll.
local inbox = require("./lib/inbox.luau")

-- One tick per blink phase; Emacs is polled every POLL_TICKS ticks.
local TICK_MS = 1000
local POLL_TICKS = 10

local ticks = 0
local count = nil -- last polled count; nil while unknown
local inFlight = false

local function render()
  local view = inbox.view(count, ticks % 2 == 1)
  barWidget.setVisible(view.visible)
  barWidget.setGlyph(view.glyph)
  barWidget.setText(view.text)
  barWidget.setTooltip(view.tooltip)
  barWidget.setGlyphColor(view.color)
  barWidget.setColor(view.color)
end

local function refresh()
  if inFlight then
    return
  end
  inFlight = noctalia.runAsync(inbox.query, function(result)
    inFlight = false
    count = inbox.count(result)
    render()
  end)
  if not inFlight then
    count = nil
    render()
  end
end

noctalia.setUpdateInterval(TICK_MS)

function update()
  if ticks % POLL_TICKS == 0 then
    refresh()
  end
  render()
  ticks += 1
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
