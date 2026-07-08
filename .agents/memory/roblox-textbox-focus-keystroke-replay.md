---
name: Roblox TextBox key-replay on focus
description: Why a hotkey used to open a chat/command TextBox can appear typed inside it, and the fix.
---

When a hotkey (e.g. `/` to open chat) programmatically calls `TextBox:CaptureFocus()` from an input handler, the key can appear typed into the box even if the handler returns `Enum.ContextActionResult.Sink`.

**Why:** if the box gains focus while the physical key is still held down (i.e. focus is captured on `Enum.UserInputState.Begin`), Roblox replays that still-held keystroke into the newly-focused TextBox. Sinking the action does not prevent this replay — it's a focus-timing issue, not an input-propagation issue.

**How to apply:** capture focus on key release (`Enum.UserInputState.End`) instead of key press (`Begin`), still sinking `Begin` so the key doesn't fall through to other bindings while held. Capturing after release means the key is no longer "down" so there's nothing left to replay. Only fall back to reactively stripping the character on `TextBox.Focused` if release-based capture isn't feasible.
