local CommandRegistry = {}

CommandRegistry.COMMANDS = {
	sm = {
		description = "broadcast a server message to all players",
		args = { "message" },
	},
	im = {
		description = "send a private message to a player or everyone",
		args = { "player|all", "message" },
	},
	anxiety = {
		description = "trigger panic visuals on a player (level 1-5)",
		args = { "player|all", "level" },
	},
	blind = {
		description = "block a player's vision, optional fade duration 1-120s",
		args = { "player|all", "[duration]" },
	},
	unblind = {
		description = "remove blind effect from a player",
		args = { "player|all" },
	},
	concussion = {
		description = "apply a concussion effect (screen blur, tinnitus, dizziness, slowed movement) to a player, optional duration in seconds (default 15)",
		args = { "player|all", "[duration]" },
	},
	createcorpse = {
		description = "spawn a corpse at a player's location, optional lifetime in seconds",
		args = { "player|all", "[lifetime]" },
	},
	re = {
		description = "refresh a player's character in place (keeps position, orientation, health)",
		args = { "player|all" },
	},
	respawn = {
		description = "respawn a player at the world spawn",
		args = { "player|all" },
	},
	help = {
		description = "send a help request to online admins",
		args = { "message" },
	},
	helpui = {
		description = "toggle help request notifications for yourself",
		args = {},
	},
	notif = {
		description = "send a notification to a player or everyone",
		args = { "player|all", "message" },
	},
	weather = {
		description = "open the weather control panel",
		args = {},
	},
	countdown = {
		description = "start a visible countdown for all players",
		args = { "seconds" },
	},
	stopcountdown = {
		description = "stop the current countdown",
		args = {},
	},
	language = {
		description = "open the language selection menu",
		args = {},
	},
	accesslanguage = {
		description = "grant a player access to a language",
		args = { "player|all", "language" },
	},
	setworldspawn = {
		description = "set the world spawn to your current position",
		args = {},
	},
	shutdown = {
		description = "gracefully shut down the server",
		args = { "[message]" },
	},
	watch = {
		description = "spectate a player's point of view",
		args = { "player" },
	},
	unwatch = {
		description = "stop spectating and restore your camera",
		args = {},
	},
	invis = {
		description = "make a player invisible",
		args = { "player|all" },
	},
	uninvis = {
		description = "restore a player's visibility",
		args = { "player|all" },
	},
	fly = {
		description = "enable flight for a player (E to toggle, LeftAlt to boost)",
		args = { "player|all", "[speed]" },
	},
	unfly = {
		description = "disable flight for a player",
		args = { "player|all" },
	},
	to = {
		description = "teleport yourself to a player",
		args = { "player" },
	},
	tp = {
		description = "teleport a player (or everyone) to another player",
		args = { "player|all", "player" },
	},
	bring = {
		description = "teleport a player to your position",
		args = { "player|all" },
	},
	setwaypoint = {
		description = "place a waypoint at your position for a player",
		args = { "player|all", "[title]" },
	},
	clearwaypoints = {
		description = "remove active waypoints for a player",
		args = { "player|all" },
	},
	music = {
		description = "open the music panel, or play an audio ID for everyone",
		args = { "[id]" },
	},
	heal = {
		description = "restore a player's health, fully or by an amount",
		args = { "player|all", "[amount]" },
	},
	damage = {
		description = "deal a set amount of damage to a player",
		args = { "player|all", "amount" },
	},
	kick = {
		description = "kick a player with an optional reason",
		args = { "player|all", "[reason]" },
	},
	esp = {
		description = "toggle ESP overlay showing health, team, distance for a player",
		args = { "player|all" },
	},
	place = {
		description = "teleport a player to a roblox place by ID",
		args = { "player|all", "placeId" },
	},
	privateserver = {
		description = "open the private server management menu",
		args = {},
	},
	freeze = {
		description = "freeze a player in place",
		args = { "player|all" },
	},
	unfreeze = {
		description = "unfreeze a player",
		args = { "player|all" },
	},
	serverbring = {
		description = "pull a player from another server into this one",
		args = { "player|all" },
	},
	serverjoin = {
		description = "join the server that a player is currently in",
		args = { "player" },
	},
	staffmode = {
		description = "toggle staff mode on/off for this session",
		args = {},
	},
	filter = {
		description = "toggle the chat filter on or off for a player",
		args = { "player|all", "on/off" },
	},
	volume = {
		description = "set your personal game volume (0-100)",
		args = { "0-100" },
	},
	heartbeat = {
		description = "apply an intense heartbeat/stress effect to a player, optional duration in seconds (default 15)",
		args = { "player|all", "[duration]" },
	},
}

return CommandRegistry
