local DataStoreService = game:GetService("DataStoreService")
local HttpService       = game:GetService("HttpService")
local InsertService     = game:GetService("InsertService")

local CosmeticsManager = {}

local DS_KEY_PREFIX = "player_"
local ds = DataStoreService:GetDataStore("PlayerCosmetics_v1")

-- In-memory cache keyed by userId.
-- shirt/pants store resolved template URLs so onCharacterAdded never needs an
-- InsertService call on respawn. Legacy DataStore entries with plain numeric
-- catalog IDs are upgraded automatically on first use.
local playerData = {}

local shirtTemplateCache = {}  -- [catalogIdStr] = "rbxassetid://..."
local pantsTemplateCache = {}  -- [catalogIdStr] = "rbxassetid://..."
local accessoryTemplateCache = {}  -- [catalogIdStr] = unparented Accessory/Hat

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
			-- Accept catalog IDs (digits only) and any URL format (rbxassetid://, http://, etc.)
			if type(decoded.shirt) == "string" and #decoded.shirt > 0 then
				clean.shirt = decoded.shirt
			end
			if type(decoded.pants) == "string" and #decoded.pants > 0 then
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

-- Resolves a clothing catalog asset to its actual ShirtTemplate/PantsTemplate
-- URL. The catalog ID differs from the texture template ID, so we must load
-- the asset and read the property. Negatives are not cached.
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

-- Applies a template URL to a Shirt or Pants instance and locks the property
-- against Roblox's async HumanoidDescription loading for `duration` seconds.
-- Roblox's loader modifies ShirtTemplate/PantsTemplate in-place on the existing
-- instance rather than creating new ones, so ChildAdded alone is not enough —
-- we use GetPropertyChangedSignal to immediately restore our value if it changes,
-- then release the lock once loading is guaranteed to have settled.
local function applyAndLock(
	character: Model,
	className: string,
	propName: string,
	templateUrl: string,
	duration: number
)
	local protected = true
	task.delay(duration, function()
		protected = false
	end)

	local function lockInst(inst: Instance)
		(inst :: any)[propName] = templateUrl
		inst:GetPropertyChangedSignal(propName):Connect(function()
			if protected and (inst :: any)[propName] ~= templateUrl then
				(inst :: any)[propName] = templateUrl
			end
		end)
	end

	-- Apply to the existing instance, or create one if absent.
	local existing = character:FindFirstChildOfClass(className)
	if existing then
		lockInst(existing)
	else
		local newInst = Instance.new(className)
		newInst.Parent = character
		lockInst(newInst)
	end

	-- Handle the case where Roblox's loader creates a brand-new instance
	-- (destroys the old one and parents a fresh one) during the lock window.
	character.ChildAdded:Connect(function(child)
		if protected and child:IsA(className) then
			lockInst(child)
		end
	end)
end

local function applyShirtToCharacter(character: Model, templateUrl: string)
	applyAndLock(character, "Shirt", "ShirtTemplate", templateUrl, 5)
end

local function applyPantsToCharacter(character: Model, templateUrl: string)
	applyAndLock(character, "Pants", "PantsTemplate", templateUrl, 5)
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
	data.shirt = permanent and templateUrl or nil
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
-- without touching the saved permanent data.
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
<<<<<<< HEAD
-- Shirt/pants template URLs are applied directly (no InsertService yield) so
-- they win the race against Roblox's default character appearance loading.
-- Legacy DataStore entries that still contain numeric catalog IDs are resolved
-- once via InsertService and then upgraded in memory for subsequent respawns.
=======
--
-- Problem: Roblox's CharacterAdded fires before HumanoidDescription is fully
-- applied. The appearance loader then modifies ShirtTemplate/PantsTemplate
-- in-place on the existing Shirt/Pants instances, overwriting any templates
-- we set immediately in CharacterAdded. ChildAdded alone doesn't help because
-- no new instances are created — only properties change.
--
-- Solution: resolve shirt/pants URLs first (synchronous for stored URLs, one
-- InsertService yield for legacy catalog IDs), then call applyAndLock which:
--   1. Sets the template immediately on the existing or newly-created instance.
--   2. Installs a GetPropertyChangedSignal listener that restores our value the
--      instant Roblox's loader overwrites it.
--   3. Installs a ChildAdded listener in case Roblox does replace the instance.
--   4. Releases all locks after 5 seconds (well past appearance-load completion).
>>>>>>> f1d561a5387f862b5bbfc6659e297c707fe20ac6
function CosmeticsManager.onCharacterAdded(player: Player, character: Model)
	local data = playerData[player.UserId]
	if not data then return end

<<<<<<< HEAD
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
=======
	-- Resolve shirt URL. If stored value is a plain number it's a legacy catalog
	-- ID that needs InsertService resolution; anything else is a template URL.
	local shirtUrl: string? = nil
	if data.shirt then
		if data.shirt:match("^%d+$") then
			local assetId = tonumber(data.shirt)
			if assetId then
				local url, resolveErr = resolveClothingTemplate(assetId, "Shirt", shirtTemplateCache)
				if url then
					shirtUrl = url
					data.shirt = url  -- upgrade so future respawns skip this yield
					task.spawn(saveData, player.UserId, data)
				else
					warn("[CosmeticsManager] failed to reapply shirt " .. data.shirt .. ": " .. tostring(resolveErr))
				end
>>>>>>> f1d561a5387f862b5bbfc6659e297c707fe20ac6
			end
		else
			shirtUrl = data.shirt  -- already a template URL
		end
	end

<<<<<<< HEAD
	applyClothing("shirt", "Shirt", shirtTemplateCache, applyShirtToCharacter)
	applyClothing("pants", "Pants", pantsTemplateCache, applyPantsToCharacter)
=======
	-- Resolve pants URL (same logic).
	local pantsUrl: string? = nil
	if data.pants then
		if data.pants:match("^%d+$") then
			local assetId = tonumber(data.pants)
			if assetId then
				local url, resolveErr = resolveClothingTemplate(assetId, "Pants", pantsTemplateCache)
				if url then
					pantsUrl = url
					data.pants = url
					task.spawn(saveData, player.UserId, data)
				else
					warn("[CosmeticsManager] failed to reapply pants " .. data.pants .. ": " .. tostring(resolveErr))
				end
			end
		else
			pantsUrl = data.pants
		end
	end

	if not character.Parent then return end

	if shirtUrl then applyShirtToCharacter(character, shirtUrl) end
	if pantsUrl then applyPantsToCharacter(character, pantsUrl) end
>>>>>>> f1d561a5387f862b5bbfc6659e297c707fe20ac6

	for idStr in pairs(data.accessories) do
		local assetId = tonumber(idStr)
		if assetId then
			local template, accessoryErr = getAccessoryTemplate(assetId)
			if template then
				equipAccessory(character, template, idStr)
			else
				warn("[CosmeticsManager] failed to reapply accessory " .. idStr .. ": " .. tostring(accessoryErr))
			end
		end
	end
end

return CosmeticsManager
