local DataStoreService = game:GetService("DataStoreService")
local InsertService    = game:GetService("InsertService")

local CosmeticsManager = {}

-- DataStore -- resolved lazily on first use so no DataStore call ever runs at
-- module load time.  Studio without API access or any init error degrades to
-- a nil store; all call sites already guard with `if not ds`.
local ds = nil
local dsResolved = false

local function getDs()
	if dsResolved then return ds end
	dsResolved = true
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("PlayerCosmetics_v1")
	end)
	if ok then
		ds = result
		print("[CosmeticsManager] DataStore handle acquired.")
	else
		warn("[CosmeticsManager] Failed to acquire DataStore handle: " .. tostring(result))
	end
	return ds
end

local DS_KEY_PREFIX = "player_"

-- In-memory state keyed by userId:
--   accessories = { ["assetId"] = true, ... }   (permanent hair/accessories)
--   shirt       = "assetId" | nil               (permanent shirt asset id)
--   pants       = "assetId" | nil               (permanent pants asset id)
local permanentData = {}  -- [userId] = { accessories, shirt, pants }
local dataLoaded    = {}  -- [userId] = true when the DataStore load has finished

-- ---------------------------------------------------------------------------
-- DataStore helpers
-- ---------------------------------------------------------------------------

local function emptyData()
	return { accessories = {}, shirt = nil, pants = nil }
end

local function loadData(userId: number)
	local store = getDs()
	if not store then
		warn(("[CosmeticsManager] loadData(%d): DataStore unavailable -- returning empty data. " ..
			"Enable Studio API access under Game Settings > Security if testing in Studio."):format(userId))
		return emptyData()
	end

	local ok, result = pcall(function()
		return store:GetAsync(DS_KEY_PREFIX .. userId)
	end)
	if not ok then
		warn(("[CosmeticsManager] loadData(%d): GetAsync failed: %s"):format(userId, tostring(result)))
		return emptyData()
	end

	if type(result) ~= "table" then
		if result == nil then
			print(("[CosmeticsManager] loadData(%d): no saved data (first join or data was cleared)."):format(userId))
		else
			warn(("[CosmeticsManager] loadData(%d): unexpected saved type '%s' -- using empty data."):format(
				userId, type(result)))
		end
		return emptyData()
	end

	local clean = emptyData()

	if type(result.accessories) == "table" then
		for _, id in ipairs(result.accessories) do
			if type(id) == "string" or type(id) == "number" then
				clean.accessories[tostring(id)] = true
			end
		end
	end
	if type(result.shirt) == "string" or type(result.shirt) == "number" then
		clean.shirt = tostring(result.shirt)
	end
	if type(result.pants) == "string" or type(result.pants) == "number" then
		clean.pants = tostring(result.pants)
	end

	local accCount = 0
	for _ in pairs(clean.accessories) do accCount += 1 end
	print(("[CosmeticsManager] loadData(%d): loaded -- %d accessory(ies), shirt=%s, pants=%s"):format(
		userId, accCount, tostring(clean.shirt), tostring(clean.pants)))
	return clean
end

local function saveData(userId: number, data)
	local store = getDs()
	if not store then
		warn(("[CosmeticsManager] saveData(%d): DataStore unavailable -- save skipped."):format(userId))
		return
	end

	local accessoriesList = {}
	for id in pairs(data.accessories) do
		table.insert(accessoriesList, id)
	end
	local payload = {
		accessories = accessoriesList,
		shirt       = data.shirt,
		pants       = data.pants,
	}

	local ok, err = pcall(function()
		store:SetAsync(DS_KEY_PREFIX .. userId, payload)
	end)
	if not ok then
		warn(("[CosmeticsManager] saveData(%d): SetAsync FAILED -- data was NOT persisted: %s"):format(
			userId, tostring(err)))
	else
		print(("[CosmeticsManager] saveData(%d): saved -- %d accessory(ies), shirt=%s, pants=%s"):format(
			userId, #accessoriesList, tostring(data.shirt), tostring(data.pants)))
	end
end

-- ---------------------------------------------------------------------------
-- Asset loading helpers (all yield -- must be called inside task.spawn or
-- a coroutine, never at module top level)
-- ---------------------------------------------------------------------------

-- Load an Accessory from Roblox's asset catalogue.
-- Returns (true, Accessory) on success, (false, errorMsg) on failure.
local function loadAccessory(assetId: number): (boolean, any)
	local ok, model = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok then
		local msg = "Failed to load asset " .. assetId .. ": " .. tostring(model)
		warn("[CosmeticsManager] loadAccessory: " .. msg)
		return false, msg
	end
	local accessory = model:FindFirstChildOfClass("Accessory")
	if not accessory then
		model:Destroy()
		local msg = "Asset " .. assetId .. " is not an Accessory."
		warn("[CosmeticsManager] loadAccessory: " .. msg)
		return false, msg
	end
	accessory.Parent = nil
	model:Destroy()
	return true, accessory
end

-- Load a clothing asset and extract the real template ID.
-- className must be "Shirt" or "Pants".
-- Returns (true, templateId) or (false, errorMsg).
local function resolveClothingTemplate(assetId: number, className: string): (boolean, string)
	local ok, model = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok then
		local msg = "Failed to load asset " .. assetId .. ": " .. tostring(model)
		warn("[CosmeticsManager] resolveClothingTemplate: " .. msg)
		return false, msg
	end
	local item = model:FindFirstChildOfClass(className)
	if not item then
		model:Destroy()
		local msg = "Asset " .. assetId .. " does not contain a " .. className .. "."
		warn("[CosmeticsManager] resolveClothingTemplate: " .. msg)
		return false, msg
	end
	local rawTemplate: string = (className == "Shirt") and item.ShirtTemplate or item.PantsTemplate
	model:Destroy()
	-- Extract the numeric ID embedded in "rbxassetid://XXXXX"
	local numericId = tostring(rawTemplate):match("%d+") or tostring(assetId)
	return true, numericId
end

-- ---------------------------------------------------------------------------
-- Character application helpers
-- ---------------------------------------------------------------------------

local function applyShirt(character: Model, templateId: string)
	local shirt = character:FindFirstChildOfClass("Shirt")
	if not shirt then
		shirt = Instance.new("Shirt")
		shirt.Parent = character
	end
	shirt.ShirtTemplate = "rbxassetid://" .. templateId
end

local function applyPants(character: Model, templateId: string)
	local pants = character:FindFirstChildOfClass("Pants")
	if not pants then
		pants = Instance.new("Pants")
		pants.Parent = character
	end
	pants.PantsTemplate = "rbxassetid://" .. templateId
end

-- Add an Accessory to a character via Humanoid:AddAccessory, marking it with
-- an attribute so removehat can later distinguish it from temporary accessories.
local function attachAccessory(character: Model, accessory: Instance, isPermanent: boolean)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then
		accessory:Destroy()
		return
	end
	-- Remove any existing accessory with the same assetId attribute to prevent stacking.
	local assetIdAttr = accessory:GetAttribute("CosmeticsAssetId")
	if assetIdAttr then
		for _, child in character:GetChildren() do
			if child:IsA("Accessory")
				and child:GetAttribute("CosmeticsAssetId") == assetIdAttr
			then
				child:Destroy()
			end
		end
	end
	accessory:SetAttribute("CosmeticsPermanent", isPermanent)
	hum:AddAccessory(accessory :: Accessory)
end

-- Wait up to `timeout` seconds for a player's data to finish loading from the
-- DataStore (onPlayerAdded spawns this asynchronously).
local function waitForData(userId: number, timeout: number?)
	local limit = timeout or 10
	local deadline = tick() + limit
	while not dataLoaded[userId] and tick() < deadline do
		task.wait(0.1)
	end
	if not dataLoaded[userId] then
		warn(("[CosmeticsManager] waitForData(%d): timed out after %ds -- DataStore load may have failed."):format(
			userId, limit))
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle hooks (called from CommandServer)
-- ---------------------------------------------------------------------------

function CosmeticsManager.onPlayerAdded(player: Player)
	task.spawn(function()
		print(("[CosmeticsManager] onPlayerAdded: loading data for %s (%d)"):format(
			player.Name, player.UserId))
		local data = loadData(player.UserId)
		permanentData[player.UserId] = data
		dataLoaded[player.UserId]    = true
		print(("[CosmeticsManager] onPlayerAdded: data ready for %s"):format(player.Name))
	end)
end

-- Save to DataStore before clearing in-memory state so any prior silent save
-- failure has a safety-net write on leave.  Wrapped in pcall so an unexpected
-- error inside saveData cannot block the cleanup lines below.
function CosmeticsManager.onPlayerRemoving(player: Player)
	local data = permanentData[player.UserId]
	if data then
		print(("[CosmeticsManager] onPlayerRemoving: saving data for %s (%d) before leaving."):format(
			player.Name, player.UserId))
		local saveOk, saveErr = pcall(saveData, player.UserId, data)
		if not saveOk then
			warn(("[CosmeticsManager] onPlayerRemoving: saveData threw unexpectedly for %s: %s"):format(
				player.Name, tostring(saveErr)))
		end
	end
	permanentData[player.UserId] = nil
	dataLoaded[player.UserId]    = nil
	print(("[CosmeticsManager] onPlayerRemoving: cleanup complete for %s (%d)."):format(
		player.Name, player.UserId))
end

-- Re-apply all permanent cosmetics when the character spawns.
function CosmeticsManager.onCharacterAdded(player: Player, character: Model)
	task.spawn(function()
		print(("[CosmeticsManager] onCharacterAdded: waiting for data for %s..."):format(player.Name))
		waitForData(player.UserId)

		local data = permanentData[player.UserId]
		if not data then
			warn(("[CosmeticsManager] onCharacterAdded: permanentData missing for %s -- skipping cosmetics."):format(
				player.Name))
			return
		end
		if not character.Parent then
			print(("[CosmeticsManager] onCharacterAdded: character already removed for %s -- skipping."):format(
				player.Name))
			return
		end

		-- Shirt
		if data.shirt then
			local assetId = tonumber(data.shirt)
			if assetId then
				print(("[CosmeticsManager] onCharacterAdded: applying shirt %s to %s"):format(
					data.shirt, player.Name))
				local ok, templateId = resolveClothingTemplate(assetId, "Shirt")
				if ok then
					if character.Parent then
						applyShirt(character, templateId :: string)
						print(("[CosmeticsManager] onCharacterAdded: shirt %s applied."):format(data.shirt))
					else
						print(("[CosmeticsManager] onCharacterAdded: character removed mid-load for %s, shirt skipped."):format(
							player.Name))
					end
				else
					warn(("[CosmeticsManager] onCharacterAdded: failed to apply shirt %s to %s: %s"):format(
						data.shirt, player.Name, tostring(templateId)))
				end
			end
		end

		-- Pants
		if data.pants then
			local assetId = tonumber(data.pants)
			if assetId then
				print(("[CosmeticsManager] onCharacterAdded: applying pants %s to %s"):format(
					data.pants, player.Name))
				local ok, templateId = resolveClothingTemplate(assetId, "Pants")
				if ok then
					if character.Parent then
						applyPants(character, templateId :: string)
						print(("[CosmeticsManager] onCharacterAdded: pants %s applied."):format(data.pants))
					else
						print(("[CosmeticsManager] onCharacterAdded: character removed mid-load for %s, pants skipped."):format(
							player.Name))
					end
				else
					warn(("[CosmeticsManager] onCharacterAdded: failed to apply pants %s to %s: %s"):format(
						data.pants, player.Name, tostring(templateId)))
				end
			end
		end

		-- Accessories / hair
		for assetIdStr in pairs(data.accessories) do
			if not character.Parent then
				print(("[CosmeticsManager] onCharacterAdded: character removed mid-loop for %s, stopping."):format(
					player.Name))
				break
			end
			local assetId = tonumber(assetIdStr)
			if assetId then
				print(("[CosmeticsManager] onCharacterAdded: applying accessory %s to %s"):format(
					assetIdStr, player.Name))
				local ok, accessory = loadAccessory(assetId)
				if ok then
					local acc = accessory :: Instance
					if character.Parent then
						acc:SetAttribute("CosmeticsAssetId", assetIdStr)
						attachAccessory(character, acc, true)
						print(("[CosmeticsManager] onCharacterAdded: accessory %s applied."):format(assetIdStr))
					else
						acc:Destroy()
						print(("[CosmeticsManager] onCharacterAdded: character removed mid-load for %s, accessory %s discarded."):format(
							player.Name, assetIdStr))
					end
				else
					warn(("[CosmeticsManager] onCharacterAdded: failed to apply accessory %s to %s: %s"):format(
						assetIdStr, player.Name, tostring(accessory)))
				end
			end
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Command implementations (called from CommandServer handlers)
-- All yield -- must be invoked inside task.spawn by the caller.
-- ---------------------------------------------------------------------------

-- Returns (success: boolean, message: string)
function CosmeticsManager.setHair(player: Player, assetId: number, permanent: boolean): (boolean, string)
	local character = player.Character
	if not character then
		warn(("[CosmeticsManager] setHair(%d): character not loaded for %s."):format(assetId, player.Name))
		return false, "Character not loaded."
	end

	local ok, accessory = loadAccessory(assetId)
	if not ok then
		warn(("[CosmeticsManager] setHair(%d): asset load failed for %s: %s"):format(
			assetId, player.Name, tostring(accessory)))
		return false, accessory :: string
	end

	local idStr = tostring(assetId)
	local acc = accessory :: Instance
	acc:SetAttribute("CosmeticsAssetId", idStr)
	attachAccessory(character, acc, permanent)

	-- Update persistence
	local data = permanentData[player.UserId]
	if not data then
		data = emptyData()
		permanentData[player.UserId] = data
	end

	if permanent then
		if not data.accessories[idStr] then
			data.accessories[idStr] = true
			print(("[CosmeticsManager] setHair: saving permanent accessory %s for %s"):format(idStr, player.Name))
			task.spawn(saveData, player.UserId, data)
		else
			print(("[CosmeticsManager] setHair: accessory %s already permanent for %s -- no save needed."):format(
				idStr, player.Name))
		end
	else
		-- If it was previously permanent, un-permanent it.
		if data.accessories[idStr] then
			data.accessories[idStr] = nil
			print(("[CosmeticsManager] setHair: removing permanent accessory %s for %s"):format(idStr, player.Name))
			task.spawn(saveData, player.UserId, data)
		end
	end

	return true, ""
end

-- Returns (success: boolean, message: string)
function CosmeticsManager.setShirt(player: Player, assetId: number, permanent: boolean): (boolean, string)
	local character = player.Character
	if not character then
		warn(("[CosmeticsManager] setShirt(%d): character not loaded for %s."):format(assetId, player.Name))
		return false, "Character not loaded."
	end

	local ok, templateId = resolveClothingTemplate(assetId, "Shirt")
	if not ok then
		warn(("[CosmeticsManager] setShirt(%d): asset load failed for %s: %s"):format(
			assetId, player.Name, tostring(templateId)))
		return false, templateId :: string
	end

	applyShirt(character, templateId :: string)

	local data = permanentData[player.UserId]
	if not data then
		data = emptyData()
		permanentData[player.UserId] = data
	end

	if permanent then
		data.shirt = tostring(assetId)
		print(("[CosmeticsManager] setShirt: saving permanent shirt %s for %s"):format(tostring(assetId), player.Name))
		task.spawn(saveData, player.UserId, data)
	else
		-- Clear any existing permanent shirt so it doesn't reapply on respawn.
		if data.shirt ~= nil then
			data.shirt = nil
			print(("[CosmeticsManager] setShirt: removing permanent shirt for %s"):format(player.Name))
			task.spawn(saveData, player.UserId, data)
		end
	end

	return true, ""
end

-- Returns (success: boolean, message: string)
function CosmeticsManager.setPants(player: Player, assetId: number, permanent: boolean): (boolean, string)
	local character = player.Character
	if not character then
		warn(("[CosmeticsManager] setPants(%d): character not loaded for %s."):format(assetId, player.Name))
		return false, "Character not loaded."
	end

	local ok, templateId = resolveClothingTemplate(assetId, "Pants")
	if not ok then
		warn(("[CosmeticsManager] setPants(%d): asset load failed for %s: %s"):format(
			assetId, player.Name, tostring(templateId)))
		return false, templateId :: string
	end

	applyPants(character, templateId :: string)

	local data = permanentData[player.UserId]
	if not data then
		data = emptyData()
		permanentData[player.UserId] = data
	end

	if permanent then
		data.pants = tostring(assetId)
		print(("[CosmeticsManager] setPants: saving permanent pants %s for %s"):format(tostring(assetId), player.Name))
		task.spawn(saveData, player.UserId, data)
	else
		if data.pants ~= nil then
			data.pants = nil
			print(("[CosmeticsManager] setPants: removing permanent pants for %s"):format(player.Name))
			task.spawn(saveData, player.UserId, data)
		end
	end

	return true, ""
end

-- Permanently remove all saved accessories from DataStore and immediately
-- destroy those accessories from the player's current character.
-- Temporary (non-permanent) accessories on the character are untouched.
-- Returns true if any permanent accessories were removed.
function CosmeticsManager.removePermanentAccessories(player: Player): boolean
	local data = permanentData[player.UserId]
	if not data then return false end
	if next(data.accessories) == nil then return false end

	-- Remove permanent accessories from the character by attribute.
	local character = player.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Accessory") and child:GetAttribute("CosmeticsPermanent") == true then
				child:Destroy()
			end
		end
	end

	data.accessories = {}
	print(("[CosmeticsManager] removePermanentAccessories: clearing all permanent accessories for %s"):format(
		player.Name))
	task.spawn(saveData, player.UserId, data)
	return true
end

-- Temporarily remove every accessory from the player's current character.
-- Does NOT modify DataStore -- permanent accessories will return on next respawn.
-- Returns the number of accessories removed.
function CosmeticsManager.clearCurrentAccessories(player: Player): number
	local character = player.Character
	if not character then return 0 end
	local count = 0
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") then
			child:Destroy()
			count += 1
		end
	end
	return count
end

print("[CosmeticsManager] module initialized.")
return CosmeticsManager
