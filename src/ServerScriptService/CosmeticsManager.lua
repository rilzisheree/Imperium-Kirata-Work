local DataStoreService = game:GetService("DataStoreService")
local HttpService       = game:GetService("HttpService")
local InsertService     = game:GetService("InsertService")

local CosmeticsManager = {}

local DS_KEY_PREFIX = "player_"
local ds = DataStoreService:GetDataStore("PlayerCosmetics_v1")

-- In-memory cache keyed by userId (number).
-- { accessories = { [assetIdString] = true, ... }, shirt = assetIdString?, pants = assetIdString? }
local playerData = {}

-- Caches so repeated sethair/respawns don't hit InsertService every time.
-- Accessory cache holds the unparented Instance; clothing caches hold the
-- resolved template URL because the catalog asset ID ≠ the texture template ID.
local accessoryTemplateCache = {}  -- [assetIdStr] = Accessory/Hat instance
local shirtTemplateCache     = {}  -- [assetIdStr] = ShirtTemplate URL string
local pantsTemplateCache     = {}  -- [assetIdStr] = PantsTemplate URL string

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
			if type(decoded.shirt) == "string" and decoded.shirt:match("^%d+$") then
				clean.shirt = decoded.shirt
			end
			if type(decoded.pants) == "string" and decoded.pants:match("^%d+$") then
				clean.pants = decoded.pants
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

-- Returns a reusable (unparented) Accessory/Hat template for the given asset ID,
-- validating that the asset is actually a hair/accessory. Caches on success.
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

-- Loads the catalog asset and extracts the actual ShirtTemplate/PantsTemplate URL
-- from the clothing instance inside it. The catalog asset ID is not the same as the
-- template texture ID, so building rbxassetid://<catalogId> directly produces a
-- broken texture. Caches the resolved URL on success; negative results are not
-- cached so a transient load failure doesn't permanently brand a valid asset.
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
	data.shirt = permanent and tostring(assetId) or nil
	task.spawn(saveData, player.UserId, data)

	return true, character and "applied" or "saved (no character loaded)"
end

-- setpants <target> <assetId> <permanent>
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
	data.pants = permanent and tostring(assetId) or nil
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
-- Called from CharacterAdded so cosmetics persist across respawns and rejoins.
function CosmeticsManager.onCharacterAdded(player: Player, character: Model)
	local data = playerData[player.UserId]
	if not data then return end

	if data.shirt then
		local assetId = tonumber(data.shirt)
		if assetId then
			local templateUrl, err = resolveClothingTemplate(assetId, "Shirt", shirtTemplateCache)
			if templateUrl then
				applyShirtToCharacter(character, templateUrl)
			else
				warn("[CosmeticsManager] failed to reapply shirt " .. data.shirt .. ": " .. tostring(err))
			end
		end
	end

	if data.pants then
		local assetId = tonumber(data.pants)
		if assetId then
			local templateUrl, err = resolveClothingTemplate(assetId, "Pants", pantsTemplateCache)
			if templateUrl then
				applyPantsToCharacter(character, templateUrl)
			else
				warn("[CosmeticsManager] failed to reapply pants " .. data.pants .. ": " .. tostring(err))
			end
		end
	end

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
