local CommandRegistry = {}

CommandRegistry.COMMANDS = {
	sm = {
		description = "Broadcast a server message to all players",
		args        = { "message" },
		permission  = "Admin",
	},
	im = {
		description = "Send a message to one specific player",
		args        = { "player", "message" },
		permission  = "Moderator",
	},
	anxiety = {
		description = "Trigger a panic visual on a player (level 1–5)",
		args        = { "player", "level" },
		permission  = "Admin",
	},
}

return CommandRegistry
