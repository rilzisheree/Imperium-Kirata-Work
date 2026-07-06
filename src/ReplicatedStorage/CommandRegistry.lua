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
}

return CommandRegistry
