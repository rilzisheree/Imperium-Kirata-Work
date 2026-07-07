# Imperium — Roblox Game Project

A Roblox game project using **Rojo** for file-sync workflow. Built with Luau.

## Project Structure

```
src/
  ReplicatedStorage/
    ChatRemotes.lua        — RemoteEvents for the proximity chat system
    CommandRegistry.lua    — Command definitions, permissions, and arg parsing
    CommandRemotes.lua     — RemoteEvents for the command system
  ServerScriptService/
    Main.server.lua        — Server entry point
    ChatServer.server.lua  — Proximity chat: filters, range checks, log buffer
    CommandServer.server.lua — Handles sm, im, anxiety commands server-side
  StarterPlayerScripts/
    ChatClient.client.lua  — Custom chat bubbles UI + input bar (press / to chat)
    CommandBar.client.lua  — Command bar UI (press ; or ' to open)
    CommandEffects.client.lua — Visual effects for sm/im commands
default.project.json       — Rojo project definition
aftman.toml                — Aftman toolchain config (Rojo 7.7.0-rc.1)
```

## Systems

### Custom Chat
- Proximity-based: only players within 60 studs see your message
- Press `/` or `Enter` to open the input bar
- Styled chat bubbles appear above character heads
- Replaces default Roblox chat entirely

### Command Bar
- Press `;` or `'` to open the command bar
- Tab/Up/Down for autocomplete
- Commands: `sm`, `im`, `anxiety`, `heal`, `damage`, `kick`, `esp`, `place`, `privateserver`, `serverbring`, `serverjoin`, `freeze`, `unfreeze`
- Permission tiers: Helper → Moderator → Admin → Owner

## Setup (local development)
1. Install [Aftman](https://github.com/LPGhatguy/aftman): `aftman install`
2. Start Rojo: `rojo serve`
3. Connect from Roblox Studio via the Rojo plugin

## User Preferences
