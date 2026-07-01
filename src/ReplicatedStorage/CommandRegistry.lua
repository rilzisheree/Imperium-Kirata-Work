--[[
	CommandRegistry.lua
	ModuleScript — ReplicatedStorage
--]]

local CommandRegistry = {}

CommandRegistry.COMMANDS = {

	sm = {
		description = "Broadcast a server message to all players",
		args        = { "message" },
		permission  = "Admin",
		aliases     = {},
	},

	im = {
		description = "Send an individual message to a specific player",
		args        = { "player", "message" },
		permission  = "Moderator",
		aliases     = {},
	},

	anxiety = {
		description = "Trigger a panic attack visual effect on a player (level 1–5)",
		args        = { "player", "level" },
		permission  = "Admin",
		aliases     = {},
	},

}

--[[
	CommandRegistry.parseArgs(raw)
	Splits a raw string into tokens, respecting "quoted strings".
--]]
function CommandRegistry.parseArgs(raw: string): { string }
	local tokens = {}
	local i = 1
	local len = #raw
	while i <= len do
		-- skip whitespace
		while i <= len and raw:sub(i, i):match("%s") do i += 1 end
		if i > len then break end

		if raw:sub(i, i) == '"' then
			-- quoted token
			i += 1
			local start = i
			while i <= len and raw:sub(i, i) ~= '"' do i += 1 end
			table.insert(tokens, raw:sub(start, i - 1))
			i += 1
		else
			-- unquoted token
			local start = i
			while i <= len and not raw:sub(i, i):match("%s") do i += 1 end
			table.insert(tokens, raw:sub(start, i - 1))
		end
	end
	return tokens
end

--[[
	CommandRegistry.getMatches(query)
	Returns a list of commands whose name starts with `query`.
	Each entry: { name: string, description: string, args: {string}, permission: string }
--]]
function CommandRegistry.getMatches(query: string): { { name: string, description: string, args: { string }, permission: string } }
	local q = query:lower()
	local results = {}
	for name, def in CommandRegistry.COMMANDS do
		if name:sub(1, #q) == q then
			table.insert(results, {
				name        = name,
				description = def.description,
				args        = def.args,
				permission  = def.permission,
			})
		end
	end
	table.sort(results, function(a, b) return a.name < b.name end)
	return results
end

return CommandRegistry
