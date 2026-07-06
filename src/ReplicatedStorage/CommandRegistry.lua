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
		description = "Block a player's vision with a black overlay",
		args        = { "player|all" },
		permission  = "Admin",
	},
	unblind = {
		description = "Remove the blind effect from a player",
		args        = { "player|all" },
		permission  = "Admin",
	},
}

return CommandRegistry
