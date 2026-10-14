--!nonstrict
-- Run: luau noctalia/satan/test/inbox_test.luau
-- The luau CLI resolves require without the `.luau` extension Noctalia demands.
local inbox = require("../lib/inbox")

local failures = 0

local function check(name, got, want)
  if got ~= want then
    failures += 1
    print(`FAIL {name}: got {tostring(got)}, want {tostring(want)}`)
  end
end

local function ok(stdout)
  return { exitCode = 0, stdout = stdout }
end

-- count: emacsclient result -> unread count, or nil when unavailable
check("count plain", inbox.count(ok("28\n")), 28)
check("count zero", inbox.count(ok("0\n")), 0)
check("count nil reply", inbox.count(ok("nil\n")), nil)
check("count error text", inbox.count(ok("*ERROR*: void-function\n")), nil)
check("count empty", inbox.count(ok("")), nil)
check("count failed exit", inbox.count({ exitCode = 1, stdout = "28\n" }), nil)

-- view: count -> widget presentation
local unread = inbox.view(3)
check("unread visible", unread.visible, true)
check("unread glyph", unread.glyph, "inbox")
check("unread text", unread.text, "3")
check("unread tooltip", unread.tooltip, "SATAN inbox: 3 unread")

check("empty hidden", inbox.view(0).visible, false)

local down = inbox.view(nil)
check("down visible", down.visible, true)
check("down glyph", down.glyph, "inbox-off")
check("down text", down.text, "")
check("down tooltip", down.tooltip, "SATAN inbox: unavailable")

-- open: compositor window list -> argv steps that show the inbox in its
-- dedicated frame and focus it, spawning the frame when absent
local inboxFrame = { id = "abc", title = inbox.frameTitle }
local other = { id = "xyz", title = "notes.org - GNU Emacs" }

local focus = inbox.open({ other, inboxFrame })
check("open existing: two steps", #focus, 2)
check("open existing: shows inbox first", focus[1][3], `(satan-inbox-show-in-frame "{inbox.frameTitle}")`)
check("open existing: then focuses", focus[2][3], "window-focus:abc")

local spawn = inbox.open({ other })
check("open absent: one step", #spawn, 1)
check("open absent: spawns", spawn[1][3], "spawn")
check("open absent: names frame", string.find(spawn[1][4], `(name . "{inbox.frameTitle}")`, 1, true) ~= nil, true)
check("open with no list: spawns", inbox.open(nil)[1][3], "spawn")

if failures > 0 then
  error(`{failures} failure(s)`)
end
print("inbox_test: ok")
