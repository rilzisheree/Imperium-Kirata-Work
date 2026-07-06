--[[
	LanguageManager.lua
	ModuleScript — ServerScriptService

	Manages per-player language state:
	  • DataStore persistence for granted languages
	  • In-memory selected language per session
	  • Translation via MyMemory API (free, no key) with result caching

	Requires: ReplicatedStorage/LanguageData
	Required by: LanguageServer.server.lua, CommandServer.server.lua,
	             ChatServer.server.lua
--]]

local DataStoreService  = game:GetService("DataStoreService")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LanguageData = require(ReplicatedStorage:WaitForChild("LanguageData"))

local LanguageManager = {}

local DS_KEY_PREFIX = "player_"
local ds = DataStoreService:GetDataStore("PlayerLanguages_v1")

-- In-memory tables keyed by userId (number)
local playerGrants   = {}   -- [userId] = { "Korean", "Japanese", ... }
local playerSelected = {}   -- [userId] = "Korean" | nil  (nil = English / none)

-- Translation cache: [isoCode .. "|" .. text] = translatedText
-- Lives for the server's lifetime; identical messages in the same language hit the cache.
local translationCache = {}

-- ── DataStore helpers ──────────────────────────────────────────────────────────

local function loadGrants(userId: number): { string }
	local ok, result = pcall(function()
		return ds:GetAsync(DS_KEY_PREFIX .. userId)
	end)
	if ok and type(result) == "string" then
		local decOk, decoded = pcall(HttpService.JSONDecode, HttpService, result)
		if decOk and type(decoded) == "table" then
			-- Re-validate each entry against LanguageData so bad/old data is silently dropped
			local clean = {}
			for _, v in ipairs(decoded) do
				if type(v) == "string" and LanguageData.BY_NAME[v:lower()] then
					table.insert(clean, LanguageData.BY_NAME[v:lower()].name)
				end
			end
			return clean
		end
	end
	return {}
end

local function saveGrants(userId: number, grants: { string })
	pcall(function()
		ds:SetAsync(DS_KEY_PREFIX .. userId, HttpService:JSONEncode(grants))
	end)
end

-- ── Player lifecycle ───────────────────────────────────────────────────────────

-- Must be called (and awaited) before getGrants is reliable for this player.
-- Yields while the DataStore load is in flight.
function LanguageManager.onPlayerAdded(player: Player)
	local grants = loadGrants(player.UserId)
	playerGrants[player.UserId]   = grants
	playerSelected[player.UserId] = nil
end

function LanguageManager.onPlayerRemoving(player: Player)
	playerGrants[player.UserId]   = nil
	playerSelected[player.UserId] = nil
end

-- ── Getters / setters ──────────────────────────────────────────────────────────

function LanguageManager.getGrants(userId: number): { string }
	return playerGrants[userId] or {}
end

function LanguageManager.getSelected(userId: number): string?
	return playerSelected[userId]
end

function LanguageManager.setSelected(userId: number, langName: string?)
	playerSelected[userId] = langName
end

-- Attempts to grant `langName` to `userId`.
-- Returns (true, canonicalName) on success.
-- Returns (false, "already_granted") if they already have it — caller
--   may surface this differently from a validation error.
-- Returns (false, errorMsg) for validation failures.
function LanguageManager.grantLanguage(userId: number, langName: string): (boolean, string)
	local lower = langName:lower()
	if lower == "english" then
		return false, "English is available to all players by default."
	end
	local lang = LanguageData.BY_NAME[lower]
	if not lang then
		return false, 'Unknown language "' .. langName .. '".'
	end

	local grants = playerGrants[userId] or {}
	for _, g in ipairs(grants) do
		if g:lower() == lower then
			return false, "already_granted"
		end
	end

	local newGrants = table.clone(grants)
	table.insert(newGrants, lang.name)
	playerGrants[userId] = newGrants
	task.spawn(saveGrants, userId, newGrants)   -- save async; don't block the caller
	return true, lang.name
end

-- ── Translation ────────────────────────────────────────────────────────────────

-- Translates `text` from English into the language identified by `isoCode`.
-- Yields while the HTTP request is in flight.
-- Returns the translated string, or `text` unchanged as a graceful fallback
-- if the request fails or returns an empty result.
function LanguageManager.translate(text: string, isoCode: string): string
	local cacheKey = isoCode .. "|" .. text
	if translationCache[cacheKey] then
		return translationCache[cacheKey]
	end

	local ok, result = pcall(function()
		local url = "https://api.mymemory.translated.net/get?q="
			.. HttpService:UrlEncode(text)
			.. "&langpair=en%7C" .. isoCode
		local resp = HttpService:RequestAsync({ Url = url, Method = "GET" })
		if not resp.Success then
			error("HTTP " .. tostring(resp.StatusCode))
		end
		local data = HttpService:JSONDecode(resp.Body)
		if data
			and data.responseData
			and type(data.responseData.translatedText) == "string"
			and data.responseData.translatedText ~= ""
		then
			return data.responseData.translatedText
		end
		error("empty translation response")
	end)

	if ok and type(result) == "string" and result ~= "" then
		translationCache[cacheKey] = result
		return result
	end

	warn("[LanguageManager] Translation failed for lang=" .. isoCode
		.. ": " .. tostring(result) .. " — falling back to original text")
	return text
end

return LanguageManager
