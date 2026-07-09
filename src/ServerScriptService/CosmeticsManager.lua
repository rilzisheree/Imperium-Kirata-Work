local DataStoreService = game:GetService("DataStoreService")
local InsertService    = game:GetService("InsertService")

local CosmeticsManager = {}

-- DataStore — resolved lazily on first use so no DataStore call ever runs at
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
        if ok then ds = result end
        return ds
end

local DS_KEY_PREFIX = "player_"

-- In-memory state keyed by userId:
--   accessories = { ["assetId"] = true, ... }   (permanent hair/accessories)
--   shirt       = "assetId" | nil               (permanent shirt asset id)
--   pants       = "assetId" | nil               (permanent pants asset id)
local permanentData = {}  -- [userId] = { accessories, shirt, pants }
local dataLoaded    = {}  -- [userId] = true when the DataStore load has finished

-- ─────────────────────────────────────────────────────────────────────────────
-- DataStore helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function emptyData()
        return { accessories = {}, shirt = nil, pants = nil }
end

local function loadData(userId: number)
        local store = getDs()
        if not store then return emptyData() end
        local ok, result = pcall(function()
                return store:GetAsync(DS_KEY_PREFIX .. userId)
        end)
        if not ok or type(result) ~= "table" then return emptyData() end

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
        return clean
end

local function saveData(userId: number, data)
        local store = getDs()
        if not store then return end
        local accessoriesList = {}
        for id in pairs(data.accessories) do
                table.insert(accessoriesList, id)
        end
        pcall(function()
                store:SetAsync(DS_KEY_PREFIX .. userId, {
                        accessories = accessoriesList,
                        shirt       = data.shirt,
                        pants       = data.pants,
                })
        end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Asset loading helpers (all yield — must be called inside task.spawn or
-- a coroutine, never at module top level)
-- ─────────────────────────────────────────────────────────────────────────────

-- Load an Accessory from Roblox's asset catalogue.
-- Returns (true, Accessory) on success, (false, errorMsg) on failure.
local function loadAccessory(assetId: number): (boolean, any)
        local ok, model = pcall(function()
                return InsertService:LoadAsset(assetId)
        end)
        if not ok then
                return false, "Failed to load asset " .. assetId .. ": " .. tostring(model)
        end
        local accessory = model:FindFirstChildOfClass("Accessory")
        if not accessory then
                model:Destroy()
                return false, "Asset " .. assetId .. " is not an Accessory."
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
                return false, "Failed to load asset " .. assetId .. ": " .. tostring(model)
        end
        local item = model:FindFirstChildOfClass(className)
        if not item then
                model:Destroy()
                return false, "Asset " .. assetId .. " does not contain a " .. className .. "."
        end
        local rawTemplate: string = (className == "Shirt") and item.ShirtTemplate or item.PantsTemplate
        model:Destroy()
        -- Extract the numeric ID embedded in "rbxassetid://XXXXX"
        local numericId = tostring(rawTemplate):match("%d+") or tostring(assetId)
        return true, numericId
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Character application helpers
-- ─────────────────────────────────────────────────────────────────────────────

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
        local deadline = tick() + (timeout or 10)
        while not dataLoaded[userId] and tick() < deadline do
                task.wait(0.1)
        end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lifecycle hooks (called from CommandServer)
-- ─────────────────────────────────────────────────────────────────────────────

function CosmeticsManager.onPlayerAdded(player: Player)
        task.spawn(function()
                local data = loadData(player.UserId)
                permanentData[player.UserId] = data
                dataLoaded[player.UserId]    = true
        end)
end

function CosmeticsManager.onPlayerRemoving(player: Player)
        permanentData[player.UserId] = nil
        dataLoaded[player.UserId]    = nil
end

-- Re-apply all permanent cosmetics when the character spawns.
function CosmeticsManager.onCharacterAdded(player: Player, character: Model)
        task.spawn(function()
                waitForData(player.UserId)

                local data = permanentData[player.UserId]
                if not data then return end
                if not character.Parent then return end

                -- Shirt
                if data.shirt then
                        local assetId = tonumber(data.shirt)
                        if assetId then
                                local ok, templateId = resolveClothingTemplate(assetId, "Shirt")
                                if ok and character.Parent then
                                        applyShirt(character, templateId :: string)
                                end
                        end
                end

                -- Pants
                if data.pants then
                        local assetId = tonumber(data.pants)
                        if assetId then
                                local ok, templateId = resolveClothingTemplate(assetId, "Pants")
                                if ok and character.Parent then
                                        applyPants(character, templateId :: string)
                                end
                        end
                end

                -- Accessories / hair
                for assetIdStr in pairs(data.accessories) do
                        if not character.Parent then break end
                        local assetId = tonumber(assetIdStr)
                        if assetId then
                                local ok, accessory = loadAccessory(assetId)
                                if ok and character.Parent then
                                        (accessory :: Instance):SetAttribute("CosmeticsAssetId", assetIdStr)
                                        attachAccessory(character, accessory :: Instance, true)
                                end
                        end
                end
        end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Command implementations (called from CommandServer handlers)
-- All yield — must be invoked inside task.spawn by the caller.
-- ─────────────────────────────────────────────────────────────────────────────

-- Returns (success: boolean, message: string)
function CosmeticsManager.setHair(player: Player, assetId: number, permanent: boolean): (boolean, string)
        local character = player.Character
        if not character then return false, "Character not loaded." end

        local ok, accessory = loadAccessory(assetId)
        if not ok then return false, accessory :: string end

        local idStr = tostring(assetId)
        ;(accessory :: Instance):SetAttribute("CosmeticsAssetId", idStr)
        attachAccessory(character, accessory :: Instance, permanent)

        -- Update persistence
        local data = permanentData[player.UserId]
        if not data then
                data = emptyData()
                permanentData[player.UserId] = data
        end

        if permanent then
                if not data.accessories[idStr] then
                        data.accessories[idStr] = true
                        task.spawn(saveData, player.UserId, data)
                end
        else
                -- If it was previously permanent, un-permanent it.
                if data.accessories[idStr] then
                        data.accessories[idStr] = nil
                        task.spawn(saveData, player.UserId, data)
                end
        end

        return true, ""
end

-- Returns (success: boolean, message: string)
function CosmeticsManager.setShirt(player: Player, assetId: number, permanent: boolean): (boolean, string)
        local character = player.Character
        if not character then return false, "Character not loaded." end

        local ok, templateId = resolveClothingTemplate(assetId, "Shirt")
        if not ok then return false, templateId :: string end

        applyShirt(character, templateId :: string)

        local data = permanentData[player.UserId]
        if not data then
                data = emptyData()
                permanentData[player.UserId] = data
        end

        if permanent then
                data.shirt = tostring(assetId)
                task.spawn(saveData, player.UserId, data)
        else
                -- Clear any existing permanent shirt so it doesn't reapply on respawn.
                if data.shirt ~= nil then
                        data.shirt = nil
                        task.spawn(saveData, player.UserId, data)
                end
        end

        return true, ""
end

-- Returns (success: boolean, message: string)
function CosmeticsManager.setPants(player: Player, assetId: number, permanent: boolean): (boolean, string)
        local character = player.Character
        if not character then return false, "Character not loaded." end

        local ok, templateId = resolveClothingTemplate(assetId, "Pants")
        if not ok then return false, templateId :: string end

        applyPants(character, templateId :: string)

        local data = permanentData[player.UserId]
        if not data then
                data = emptyData()
                permanentData[player.UserId] = data
        end

        if permanent then
                data.pants = tostring(assetId)
                task.spawn(saveData, player.UserId, data)
        else
                if data.pants ~= nil then
                        data.pants = nil
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
        task.spawn(saveData, player.UserId, data)
        return true
end

-- Temporarily remove every accessory from the player's current character.
-- Does NOT modify DataStore — permanent accessories will return on next respawn.
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

return CosmeticsManager
