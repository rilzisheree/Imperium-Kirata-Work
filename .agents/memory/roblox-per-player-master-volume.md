---
name: Roblox per-player master volume
description: How independent per-player volume control was implemented without touching every individual Sound instance.
---

To scale all game audio (music, ambience, notifications, etc.) per-player without
server-side changes affecting other clients, route every `Sound` instance through a
single client-created `SoundGroup` (assigned locally via a `LocalScript`, e.g. hooking
`game.DescendantAdded`) and scale `SoundGroup.Volume` instead of touching each Sound's
own `.Volume`. Property changes made by a LocalScript to replicated instances are local
to that client only — they never sync to the server or other players.

**Why:** Sounds in this codebase are created from many different places (server-side
weather ambience, client-side music/notification pops/heartbeat SFX) with hardcoded
`.Volume` values. Touching every call site would be invasive and error-prone; a single
client-side SoundGroup interception point is DRY and automatically covers future sounds.

**How to apply:** Any future "personal audio preference" feature (e.g. mute categories)
should extend the same SoundGroup interception pattern rather than editing individual
Sound-creation sites.
