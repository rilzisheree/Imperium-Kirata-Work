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
}

return CommandRegistry
