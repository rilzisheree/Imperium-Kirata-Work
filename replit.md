# Imperium

## Overview
Imperium is a Roblox game project built with Lua and synced to Roblox Studio using [Rojo](https://rojo.space/). This is not a traditional web app — there is no browser-based frontend or backend server in the usual sense. Instead, Rojo runs a live-sync server that a Roblox Studio plugin connects to, streaming file changes from this codebase directly into Roblox Studio.

## Project Structure
- `default.project.json` — Rojo project definition mapping Lua files to the Roblox DataModel (ReplicatedStorage, ServerScriptService, StarterPlayerScripts, etc.)
- `src/ReplicatedStorage/` — Shared modules (chat remotes, command registry, language data, markdown parser)
- `src/ServerScriptService/` — Server-side scripts (chat server, command server, corpse factory, language/weather servers, main entry point)
- `src/StarterPlayerScripts/` — Client-side LocalScripts (chat UI, command bar, effects, menus, etc.)
- `aftman.toml` — Toolchain manager config pinning the Rojo version
- `rojo` — Prebuilt Rojo binary used to serve the project
- `sourcemap.json` — Generated Rojo sourcemap

## Development Workflow
The `Rojo Serve` workflow runs:
```
./rojo serve default.project.json --address 0.0.0.0 --port 8000
```
This exposes a live-sync HTTP server on port 8000. To connect from Roblox Studio:
1. Install the [Rojo Studio plugin](https://rojo.space/docs/v7/getting-started/installation/#roblox-studio-plugin).
2. In Studio, open the Rojo plugin and click "Connect", using this Repl's public dev URL and port 8000 (or use the workflow's forwarded address shown in Replit).
3. File changes made in this codebase will sync live into the open Studio place.

There is no browser-viewable game UI — the served page is Rojo's status/info page, not the game itself. The actual game only runs inside Roblox Studio or the Roblox client.

## User Preferences
None recorded yet.
