---
name: Roblox TextBox key-replay on focus
description: Why a hotkey used to open a chat/command TextBox can appear typed inside it, and the two valid approaches.
---

When a hotkey (e.g. `/` to open chat) programmatically calls `TextBox:CaptureFocus()` from an input handler, the key can appear typed into the box even if the handler returns `Enum.ContextActionResult.Sink`.

**Why:** if the box gains focus while the physical key is still held down (i.e. focus is captured on `Enum.UserInputState.Begin`), Roblox replays that still-held keystroke into the newly-focused TextBox. Sinking the action does not prevent this replay — it's a focus-timing issue, not an input-propagation issue.

**How to apply (two options):**

Option A — Capture on release (`End`). Eliminates replay entirely but introduces a perceived delay: chat doesn't open until the user lifts the key. Avoid when instant response matters.

Option B — Capture on press (`Begin`) + strip the stray character reactively. This is the preferred approach for user-facing open-chat hotkeys. In the `TextBox.Focused` handler, clear the text if it equals the hotkey character, and `task.defer` a second check to catch the frame-later replay. Both cleanups together handle all timing cases. The user perceives instant opening; any stray `/` is invisible.

The chat bar in this project uses Option B.
