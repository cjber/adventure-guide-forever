# Report window

`/agf report` gives a player one block of text to paste into a bug report. They don't need a `/reload` or a
saved-variables file. This page describes the pattern so the other Forever addons can port it
(cjber/adventure-guide-forever#156).

## What the player sees

A stock `PortraitFrameTemplate` window with the addon icon as its portrait. It has a one-line hint ("The text is
selected. Press Ctrl+C..."), and below that an `InsetFrameTemplate` holding a `ScrollFrameTemplate` with a multi-line
edit box. The edit box has focus and all of its text is selected when the window opens, so Ctrl+C copies the lot.
Typing puts the text back and selects it again, so the box is effectively read-only. Escape or the close button hides
the window: the frame is named `<addon>Report` and listed in `UISpecialFrames` (an addon-owned frame, so no taint), so
Escape works whether or not the box has focus. The frame is made on the first `/agf report` and reused after that, so it costs nothing at
login. It is movable and clamped to the screen.

## What the text holds

At most 2,000 characters, one Discord or forum message, in this order:

1. `AdventureGuideForever 0.13.0 | WoW 1.60.1 (70374) 16001 | enUS`: addon version, game version, build, interface,
   locale.
2. `Character: level 18 Orc SHAMAN, Horde`: no name or realm.
3. `Place: map 1413 (The Barrens) 52.0, 30.0`.
4. The addon's own lines. For AGF these are QuestieDB's state and version, the guide's settings, the journey, the stop
   the tracker shows (title, kind, key, map, coordinates, radius, reason and detail), each of its quests by ID with
   `Model.Why`'s lines (`+` met, `-` unmet), and the next two stops' titles.
5. `Errors (n):`: what `ns.core.SafeCall` caught, newest first, as `- [label] xCount message` with up to four stack lines.
   `Errors: none caught` otherwise.
6. `Other addons (n): A 1.0, B 2.1 and 40 more`: the loaded addons and their versions, sorted, trimmed to the room
   left.

Each section has its own cap so one long section can't push another out: the addon's own lines stop at 1,000
characters and the errors at 600, and the addon list takes what room is left. Every cut lands on a UTF-8 character
boundary and ends in "...". When the text is still too long, the end is cut. Field labels stay English in every locale; names, step titles and
Why lines are in the client's language. The window title and hint go through `ns.L`. The stop line reads `Stop:` for
the stop being guided to and `Route head:` for step 1 when nothing is being guided.

## Files

ForeverCore owns the window and the error journal; an addon supplies only its own lines.

| ForeverCore module | Role |
| --- | --- |
| `Core/SafeCall.lua` | `ns.core.SafeCall(label, fn, ...)`, `ns.core.RecordError(label, message, stack)`, `ns.core.CaughtErrors()` |
| `UI/Report.lua` | the window, the shared header, errors and addon list: `ns.core.Report.Text(lines)`, `ns.core.Report.Show(text)` |
| `Core/Report.lua` in the addon | `ns.ReportLines()`: the addon's own lines as a string list, passed to `ForeverCore.Register` |

The slash handler runs `ns.ReportLines` through `ns.core.SafeCall` and shows `ns.core.Report.Text(lines)`, with one
"Report lines failed" line in their place when they error, so the header and the caught errors still reach the player.

## SafeCall

`ns.core.SafeCall(label, fn, ...)` returns what `pcall(fn, ...)` would, nils included. On a failure it:

- keeps the error under `label` (the innermost SafeCall's, when they nest) with a stack cut to four lines that name a
  `.lua` file (`debugstack`, else `debug.traceback`). A repeat of the same label and message raises the count and
  moves to the end, and only the last five are kept. A long message is cut on a UTF-8 character boundary;
- passes the message to `geterrorhandler()` from inside xpcall's message handler, before the stack unwinds, so BugSack
  and the default error frame capture the stack and locals where the error happened. Nothing is swallowed.

Wrap the places where an error would otherwise be lost or would stop other work: callbacks you run for other code
(listener lists), event handlers and the slash command. AGF wraps the route listeners (one failing listener no longer
stops the rest), `Core/State.lua`'s event handler and the slash command. A coroutine's error never reaches an
`xpcall`, so record it with `ns.core.RecordError(label, message, debug.traceback(co))` before re-raising, as AGF's sliced
rebuild does.

## Porting checklist

- Require ForeverCore and register once with `ForeverCore.Register(addonName, { title = ..., lines = ... })`. Add the
  `REPORT_TITLE` and `HELP_REPORT` strings.
- Write `ns.ReportLines()` (SPF: the journey and ride trace; Legacy and SkillUp: the audit lines).
- Add the slash command and its help line, and the `types/` fields.
- Specs: core's own `tests/api_spec.lua` and `tests/report_spec.lua` cover the window, the journal and SafeCall; an
  addon's specs cover only its own lines.

## Issue link

The in-game issue composer selects a pre-filled GitHub issue URL for copying into a browser; the WoW client cannot open a browser or submit an HTTP request. The `report.md` template lets GitHub use the URL body because issue forms ignore `body` prefills. When porting this window, read the repository from `X-Website` metadata and include the matching markdown template.

The system report also includes the two newest current-session Lua errors and their first trace line when BugGrabber is installed (BugSack uses BugGrabber for its error history). Without it, the client’s ScriptErrors window does not expose a readable history to addons; the composer does not replace the game’s error handler. Error locals are never copied.
