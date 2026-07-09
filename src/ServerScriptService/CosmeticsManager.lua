local DataStoreService = game:GetService("DataStoreService")
local HttpService       = game:GetService("HttpService")
local InsertService     = game:GetService("InsertService")

local CosmeticsManager = {}

local DS_KEY_PREFIX = "player_"
local ds = DataStoreService:GetDataStore("PlayerCosmetics_v1")

-- In-memory cache keyed by userId (number).
-- shirt/pants store template URLs (rbxassetid://...) so onCharacterAdded can
-- apply them instantly without an InsertService round-trip on every respawn.
-- Legacy DataStore values that are plain numeric strings (catalog IDs) are
-- resolved once on first use and then upgraded to template URLs automatically.
local playerData = {}

-- Catalog ID → resolved template URL, so InsertService is only called once per
-- unique clothing asset per server lifetime.
local shirtTemplateCache = {}  -- [catalogIdStr] = "rbxassetid://..."
local pantsTemplateCache = {}  -- [catalogIdStr] = "rbxassetid://..."

-- Catalog ID → unparented Accessory/Hat clone, reused across respawns.
local accessoryTemplateCache = {}  -- [catalogIdStr] = Instance

local function defaultData()
	return { accessories = {}, shirt = nil, pants = nil }
end

local function loadData(userId: number)
	local ok, result = pcall(function()
		return ds:GetAsync(DS_KEY_PREFIX .. userId)
	end)
	if ok and type(result) == "string" then
		local decOk, decoded = pcall(HttpService.JSONDecode, HttpService, result)
		if decOk and type(decoded) == "table" then
			local clean = defaultData()
			if type(decoded.accessories) == "table" then
				for id, v in pairs(decoded.accessories) do
					if v and type(id) == "string" and id:match("^%d+$") then
						clean.accessories[id] = true
					end
				end
			end
			-- Accept both legacy numeric catalog IDs and new template URL strings.
			if type(decoded.shirt) == "string" then
				local v = decoded.shirt
				if v:match("^%d+$") or v:match("^rbxassetid://") then
					clean.shirt = v
				end
			end
			if type(decoded.pants) == "string" then
				local v = decoded.pants
				if v:match("^%d+$") or v:match("^rbxassetid://") then
					clean.pants = v
				end
			end
			return clean
		end
	end
	return defaultData()
end

local function saveData(userId: number, data)
	pcall(function()
		ds:SetAsync(DS_KEY_PREFIX .. userId, HttpService:JSONEncode(data))
	end)
end

local function getData(userId: number)
	if not playerData[userId] then
		playerData[userId] = defaultData()
	end
	return playerData[userId]
end

function CosmeticsManager.onPlayerAdded(player: Player)
	playerData[player.UserId] = loadData(player.UserId)
end

function CosmeticsManager.onPlayerRemoving(player: Player)
	playerData[player.UserId] = nil
end

local function loadAssetModel(assetId: number): (Model?, string?)
	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not result then
		return nil, "Failed to load asset " .. tostring(assetId) .. "."
	end
	return result, nil
end

local function findAccessoryIn(model: Instance): Instance?
	for _, inst in model:GetDescendants() do
		if inst:IsA("Accessory") or inst:IsA("Hat") then
			return inst
		end
	end
	return nil
end

-- Returns a reusable (unparented) Accessory/Hat template for the given catalog
-- asset ID, validating that it is actually a hair/accessory. Caches on success.
local function getAccessoryTemplate(assetId: number): (Instance?, string?)
	local idStr = tostring(assetId)
	if accessoryTemplateCache[idStr] then
		return accessoryTemplateCache[idStr], nil
	end

	local model, err = loadAssetModel(assetId)
	if not model then
		return nil, err
	end

	local accessory = findAccessoryIn(model)
	if not accessory then
		model:Destroy()
		return nil, "Asset " .. idStr .. " is not a hair/accessory asset."
	end

	accessory.Parent = nil
	model:Destroy()
	accessoryTemplateCache[idStr] = accessory
	return accessory, nil
end

-- Loads a clothing catalog asset via InsertService and extracts the actual
-- ShirtTemplate / PantsTemplate URL from the clothing instance inside it.
-- The catalog asset ID differs from the texture template ID, so we must resolve
-- it before use. Negatives are not cached so a transient load failure can be
-- retried without restarting the server.
local function resolveClothingTemplate(
	assetId: number,
	className: string,
	cache: { [string]: string }
): (string?, string?)
	local idStr = tostring(assetId)
	if cache[idStr] then
		return cache[idStr], nil
	end

	local model, err = loadAssetModel(assetId)
	if not model then
		return nil, err
	end

	local item
	for _, inst in model:GetDescendants() do
		if inst:IsA(className) then
			item = inst
			break
		end
	end

	if not item then
		model:Destroy()
		return nil, "Asset " .. idStr .. " is not a " .. className .. " asset."
	end

	local templateUrl = if className == "Shirt"
		then (item :: Shirt).ShirtTemplate
		else (item :: Pants).PantsTemplate

	model:Destroy()

	if not templateUrl or templateUrl == "" then
		return nil, "Asset " .. idStr .. " returned an empty template URL."
	end

	cache[idStr] = templateUrl
	return templateUrl, nil
end

local function removeAccessoryInstance(character: Model, idStr: string)
	for _, inst in character:GetChildren() do
		if (inst:IsA("Accessory") or inst:IsA("Hat"))
			and inst:GetAttribute("CosmeticAssetId") == idStr
		then
			inst:Destroy()
		end
	end
end

local function equipAccessory(character: Model, template: Instance, idStr: string): (boolean, string?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "Character has no Humanoid."
	end
	removeAccessoryInstance(character, idStr)
	local clone = template:Clone()
	clone:SetAttribute("CosmeticAssetId", idStr)
	local addOk, addErr = pcall(function()
		humanoid:AddAccessory(clone :: Accessory)
	end)
	if not addOk then
		clone:Destroy()
		return false, "Failed to equip accessory: " .. tostring(addErr)
	end
	return true, nil
end

local function applyShirtToCharacter(character: Model, templateUrl: string)
	local shirt = character:FindFirstChildOfClass("Shirt")
	if not shirt then
		shirt = Instance.new("Shirt")
		shirt.Parent = character
	end
	shirt.ShirtTemplate = templateUrl
end

local function applyPantsToCharacter(character: Model, templateUrl: string)
	local pants = character:FindFirstChildOfClass("Pants")
	if not pants then
		pants = Instance.new("Pants")
		pants.Parent = character
	end
	pants.PantsTemplate = templateUrl
end

-- sethair <target> <assetId> <permanent>
function CosmeticsManager.setHair(player: Player, assetId: number, permanent: boolean): (boolean, string)
	local template, err = getAccessoryTemplate(assetId)
	if not template then
		return false, err or "Invalid asset ID."
	end

	local idStr = tostring(assetId)
	local character = player.Character
	if character then
		local equipOk, equipErr = equipAccessory(character, template, idStr)
		if not equipOk then
			return false, equipErr or "Failed to equip accessory."
		end
	end

	local data = getData(player.UserId)
	if permanent then
		data.accessories[idStr] = true
	else
		data.accessories[idStr] = nil
	end
	task.spawn(saveData, player.UserId, data)

	return true, character and "equipped" or "saved (no character loaded)"
end

-- setshirt <target> <assetId> <permanent>
-- Resolves the catalog asset to its actual ShirtTemplate URL and stores that
-- URL directly so onCharacterAdded can apply it without an InsertService call.
function CosmeticsManager.setShirt(player: Player, assetId: number, permanent: boolean): (boolean, string)
	local templateUrl, err = resolveClothingTemplate(assetId, "Shirt", shirtTemplateCache)
	if not templateUrl then
		return false, err or "Invalid asset ID."
	end

	local character = player.Character
	if character then
		applyShirtToCharacter(character, templateUrl)
	end

	local data = getData(player.UserId)
	data.shirt = permanent and templateUrl or nil
	task.spawn(saveData, player.UserId, data)

	return true, character and "applied" or "saved (no character loaded)"
end

-- setpants <target> <assetId> <permanent>
-- Resolves the catalog asset to its actual PantsTemplate URL and stores that
-- URL directly so onCharacterAdded can apply it without an InsertService call.
function CosmeticsManager.setPants(player: Player, assetId: number, permanent: boolean): (boolean, string)
	local templateUrl, err = resolveClothingTemplate(assetId, "Pants", pantsTemplateCache)
	if not templateUrl then
		return false, err or "Invalid asset ID."
	end

	local character = player.Character
	if character then
		applyPantsToCharacter(character, templateUrl)
	end

	local data = getData(player.UserId)
	data.pants = permanent and templateUrl or nil
	task.spawn(saveData, player.UserId, data)

	return true, character and "applied" or "saved (no character loaded)"
end

-- removehat <target>: clears every saved accessory and strips them from
-- the current character immediately. Temporary accessories are untouched.
function CosmeticsManager.removePermanentAccessories(player: Player): boolean
	local data = getData(player.UserId)

	local hadAny = false
	for idStr in pairs(data.accessories) do
		hadAny = true
		local character = player.Character
		if character then
			removeAccessoryInstance(character, idStr)
		end
	end

	if not hadAny then
		return false
	end

	data.accessories = {}
	task.spawn(saveData, player.UserId, data)
	return true
end

-- clearhats <target>: removes every accessory currently on the character
-- (temporary or permanent) without touching the saved permanent data, so
-- permanent accessories return automatically on the next respawn.
function CosmeticsManager.clearCurrentAccessories(player: Player): number
	local character = player.Character
	if not character then
		return 0
	end

	local removed = 0
	for _, inst in character:GetChildren() do
		if inst:IsA("Accessory") or inst:IsA("Hat") then
			inst:Destroy()
			removed += 1
		end
	end
	return removed
end

-- Re-applies every permanently saved cosmetic to a freshly spawned character.
-- Shirt/pants template URLs are applied directly (no InsertService yield) so
-- they win the race against Roblox's default character appearance loading.
-- Legacy DataStore entries that still contain numeric catalog IDs are resolved
-- once via InsertService and then upgraded in memory for subsequent respawns.
function CosmeticsManager.onCharacterAdded(player: Player, character: Model)
	local data = playerData[player.UserId]
	if not data then return end

	local function applyClothing(
		field: string,
		className: string,
		cache: { [string]: string },
		applyFn: (Model, string) -> ()
	)
		local stored = (data :: any)[field]
		if not stored then return end

		if stored:match("^rbxassetid://") then
			-- Already a resolved template URL — apply immediately, no yield.
			applyFn(character, stored)
		else
			-- Legacy catalog ID: resolve once and upgrade the stored value.
			local assetId = tonumber(stored)
			if not assetId then return end
			local templateUrl, err = resolveClothingTemplate(assetId, className, cache)
			if templateUrl then
				applyFn(character, templateUrl)
				-- Upgrade in memory so the next respawn is instant.
				;(data :: any)[field] = templateUrl
				task.spawn(saveData, player.UserId, data)
			else
				warn("[CosmeticsManager] failed to reapply " .. field .. " " .. stored .. ": " .. tostring(err))
			end
		end
	end

	applyClothing("shirt", "Shirt", shirtTemplateCache, applyShirtToCharacter)
	applyClothing("pants", "Pants", pantsTemplateCache, applyPantsToCharacter)

	for idStr in pairs(data.accessories) do
		local assetId = tonumber(idStr)
		if assetId then
			local template, err = getAccessoryTemplate(assetId)
			if template then
				equipAccessory(character, template, idStr)
			else
				warn("[CosmeticsManager] failed to reapply accessory " .. idStr .. ": " .. tostring(err))
			end
		end
	end
end

return CosmeticsManager
