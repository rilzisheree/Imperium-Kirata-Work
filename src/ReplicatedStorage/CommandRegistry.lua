local CommandRegistry = {}

CommandRegistry.COMMANDS = {
        sm = {
                description = "Broadcast a server message to all players",
                args        = { "message" },
                permission  = "Admin",
        },
        im = {
                description = "Send a message to a player or all players",
                args        = { "player|all", "message" },
                permission  = "Moderator",
        },
        anxiety = {
                description = "Trigger a panic visual on a player or all players (level 1–5)",
                args        = { "player|all", "level" },
                permission  = "Admin",
        },
        blind = {
                description = "Block a player's vision (optional fade 1–120s)",
                args        = { "player|all", "[duration]" },
                permission  = "Admin",
        },
        unblind = {
                description = "Remove the blind effect from a player",
                args        = { "player|all" },
                permission  = "Admin",
        },
        createcorpse = {
                description = "Spawn a static corpse at a player's location (optional lifetime in seconds)",
                args        = { "player|all", "[lifetime]" },
                permission  = "Admin",
        },
        re = {
                description = "Refresh a player's character in place (same position, orientation, and health)",
                args        = { "player|all" },
                permission  = "Admin",
        },
        respawn = {
                description = "Respawn a player's character at the world's default spawn location",
                args        = { "player|all" },
                permission  = "Admin",
        },
        help = {
                description = "Send a help request message to online admins",
                args        = { "message" },
                permission  = "Everyone",
        },
        helpui = {
                description = "Toggle whether help request notifications are shown to you",
                args        = {},
                permission  = "Admin",
        },
        notif = {
                description = "Send a custom notification to a player or all players",
                args        = { "player|all", "message" },
                permission  = "Admin",
        },
        weather = {
                description = "Open the Weather Control panel",
                args        = {},
                permission  = "Admin",
        },
        countdown = {
                description = "Start a visible countdown for all players",
                args        = { "seconds" },
                permission  = "Admin",
        },
        stopcountdown = {
                description = "Stop the current countdown for all players",
                args        = {},
                permission  = "Admin",
        },
        language = {
                description = "Open the language selection menu",
                args        = {},
                permission  = "Everyone",
        },
        accesslanguage = {
                description = "Grant a player access to a language",
                args        = { "player|all", "language" },
                permission  = "Admin",
        },
        setworldspawn = {
                description = "Set the world spawn to your current position",
                args        = {},
                permission  = "Admin",
        },
        shutdown = {
                description = "Gracefully shut down the server",
                args        = { "[message]" },
                permission  = "Owner",
        },
        watch = {
                description = "Spectate a player's point of view",
                args        = { "player" },
                permission  = "Admin",
        },
        unwatch = {
                description = "Stop spectating and restore your normal camera",
                args        = {},
                permission  = "Admin",
        },
        invis = {
                description = "Make a player's character invisible",
                args        = { "player|all" },
                permission  = "Admin",
        },
        uninvis = {
                description = "Restore a player's character visibility",
                args        = { "player|all" },
                permission  = "Admin",
        },
        fly = {
                description = "Enable flight for a player or all players (E to toggle, LeftAlt to boost)",
                args        = { "player|all", "[speed]" },
                permission  = "Admin",
        },
        unfly = {
                description = "Disable flight for a player or all players",
                args        = { "player|all" },
                permission  = "Admin",
        },
        to = {
                description = "Teleport yourself to a player",
                args        = { "player" },
                permission  = "Admin",
        },
        tp = {
                description = "Teleport a player (or all players) to another player",
                args        = { "player|all", "player" },
                permission  = "Admin",
        },
        bring = {
                description = "Teleport a player or players to your current position",
                args        = { "player|all" },
                permission  = "Admin",
        },
        setwaypoint = {
                description = "Place a waypoint at your position for a player or all players",
                args        = { "player|all", "[title]" },
                permission  = "Admin",
        },
        clearwaypoints = {
                description = "Remove any active waypoint for a player or all players",
                args        = { "player|all" },
                permission  = "Admin",
        },
        music = {
                description = "Open the Music Control panel, or play an audio ID for all players",
                args        = { "[id]" },
                permission  = "Admin",
        },
        heal = {
                description = "Restore a player's health (fully, or by a specific amount)",
                args        = { "player|all", "[amount]" },
                permission  = "Admin",
        },
        damage = {
                description = "Remove a specific amount of health from a player",
                args        = { "player|all", "amount" },
                permission  = "Admin",
        },
        kick = {
                description = "Remove a player from the server with an optional reason",
                args        = { "player|all", "[reason]" },
                permission  = "Admin",
        },
        esp = {
                description = "Toggle an ESP overlay showing health, team, distance, and location for a player",
                args        = { "player|all" },
                permission  = "Admin",
        },
        place = {
                description = "Teleport a player or all players to a Roblox Place ID",
                args        = { "player|all", "placeId" },
                permission  = "Admin",
        },
        privateserver = {
                description = "Open the Private Server management menu to reserve and populate a server",
                args        = {},
                permission  = "Admin",
        },
        freeze = {
                description = "Freeze a player in place, preventing all movement",
                args        = { "player|all" },
                permission  = "Admin",
        },
        unfreeze = {
                description = "Unfreeze a player and restore their movement",
                args        = { "player|all" },
                permission  = "Admin",
        },
        serverbring = {
                description = "Bring a player from another server of this experience into this server",
                args        = { "player|all" },
                permission  = "Admin",
        },
        serverjoin = {
                description = "Teleport yourself to the server that the specified player is currently in",
                args        = { "player" },
                permission  = "Admin",
        },
        staffmode = {
                description = "Toggle Staff Mode, enabling or disabling access to staff-only commands for this session",
                args        = {},
                permission  = "Admin",
        },
}

return CommandRegistry
