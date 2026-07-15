local CommandRegistry = {}

CommandRegistry.COMMANDS = {
	sm = {
		description = "broadcast a server message to all players",
		args = { "message" },
		permission = "Admin",
	},
	im = {
		description = "send a private message to a player or everyone",
		args = { "player|all", "message" },
		permission = "Moderator",
	},
	anxiety = {
		description = "trigger panic visuals on a player (level 1-5)",
		args = { "player|all", "level" },
		permission = "Admin",
	},
	blind = {
		description = "block a player's vision, optional fade duration 1-120s",
		args = { "player|all", "[duration]" },
		permission = "Admin",
	},
	unblind = {
		description = "remove blind effect from a player",
		args = { "player|all" },
		permission = "Admin",
	},
	concussion = {
		description = "apply a concussion effect (screen blur, tinnitus, dizziness, slowed movement) to a player, optional duration in seconds (default 15)",
		args = { "player|all", "[duration]" },
		permission = "Admin",
	},
	createcorpse = {
		description = "spawn a corpse at a player's location, optional lifetime in seconds",
		args = { "player|all", "[lifetime]" },
		permission = "Admin",
	},
	re = {
		description = "refresh a player's character in place (keeps position, orientation, health)",
		args = { "player|all" },
		permission = "Admin",
	},
	respawn = {
		description = "respawn a player at the world spawn",
		args = { "player|all" },
		permission = "Admin",
	},
	help = {
		description = "send a help request to online admins",
		args = { "message" },
		permission = "Everyone",
	},
	helpui = {
		description = "toggle help request notifications for yourself",
		args = {},
		permission = "Admin",
	},
	notif = {
		description = "send a notification to a player or everyone",
		args = { "player|all", "message" },
		permission = "Admin",
	},
	weather = {
		description = "open the weather control panel",
		args = {},
		permission = "Admin",
	},
	countdown = {
		description = "start a visible countdown for all players",
		args = { "seconds" },
		permission = "Admin",
	},
	stopcountdown = {
		description = "stop the current countdown",
		args = {},
		permission = "Admin",
	},
	language = {
		description = "open the language selection menu",
		args = {},
		permission = "Everyone",
	},
	accesslanguage = {
		description = "grant a player access to a language",
		args = { "player|all", "language" },
		permission = "Admin",
	},
	setworldspawn = {
		description = "set the world spawn to your current position",
		args = {},
		permission = "Admin",
	},
	shutdown = {
		description = "gracefully shut down the server",
		args = { "[message]" },
		permission = "Owner",
	},
	watch = {
		description = "spectate a player's point of view",
		args = { "player" },
		permission = "Admin",
	},
	unwatch = {
		description = "stop spectating and restore your camera",
		args = {},
		permission = "Admin",
	},
	invis = {
		description = "make a player invisible",
		args = { "player|all" },
		permission = "Admin",
	},
	uninvis = {
		description = "restore a player's visibility",
		args = { "player|all" },
		permission = "Admin",
	},
	fly = {
		description = "enable flight for a player (E to toggle, LeftAlt to boost)",
		args = { "player|all", "[speed]" },
		permission = "Admin",
	},
	unfly = {
		description = "disable flight for a player",
		args = { "player|all" },
		permission = "Admin",
	},
	to = {
		description = "teleport yourself to a player",
		args = { "player" },
		permission = "Admin",
	},
	tp = {
		description = "teleport a player (or everyone) to another player",
		args = { "player|all", "player" },
		permission = "Admin",
	},
	bring = {
		description = "teleport a player to your position",
		args = { "player|all" },
		permission = "Admin",
	},
	setwaypoint = {
		description = "place a waypoint at your position for a player",
		args = { "player|all", "[title]" },
		permission = "Admin",
	},
	clearwaypoints = {
		description = "remove active waypoints for a player",
		args = { "player|all" },
		permission = "Admin",
	},
	music = {
		description = "open the music panel, or play an audio ID for everyone",
		args = { "[id]" },
		permission = "Admin",
	},
	heal = {
		description = "restore a player's health, fully or by an amount",
		args = { "player|all", "[amount]" },
		permission = "Admin",
	},
	damage = {
		description = "deal a set amount of damage to a player",
		args = { "player|all", "amount" },
		permission = "Admin",
	},
	kick = {
		description = "kick a player with an optional reason",
		args = { "player|all", "[reason]" },
		permission = "Admin",
	},
	esp = {
		description = "toggle ESP overlay showing health, team, distance for a player",
		args = { "player|all" },
		permission = "Admin",
	},
	place = {
		description = "teleport a player to a roblox place by ID",
		args = { "player|all", "placeId" },
		permission = "Admin",
	},
	privateserver = {
		description = "open the private server management menu",
		args = {},
		permission = "Admin",
	},
	freeze = {
		description = "freeze a player in place",
		args = { "player|all" },
		permission = "Admin",
	},
	unfreeze = {
		description = "unfreeze a player",
		args = { "player|all" },
		permission = "Admin",
	},
	serverbring = {
		description = "pull a player from another server into this one",
		args = { "player|all" },
		permission = "Admin",
	},
	serverjoin = {
		description = "join the server that a player is currently in",
		args = { "player" },
		permission = "Admin",
	},
	staffmode = {
		description = "toggle staff mode on/off for this session",
		args = {},
		permission = "Admin",
	},
	filter = {
		description = "toggle the chat filter on or off for a player",
		args = { "player|all", "on/off" },
		permission = "Admin",
	},
	volume = {
		description = "set your personal game volume (0-100)",
		args = { "0-100" },
		permission = "Everyone",
	},
}

return CommandRegistry
