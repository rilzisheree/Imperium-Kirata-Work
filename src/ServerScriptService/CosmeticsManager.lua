local DataStoreService = game:GetService("DataStoreService")
local HttpService       = game:GetService("HttpService")
local InsertService     = game:GetService("InsertService")

local CosmeticsManager = {}

local DS_KEY_PREFIX = "player_"
local ds = DataStoreService:GetDataStore("PlayerCosmetics_v1")

-- In-memory cache keyed by userId (number)
-- { accessories = { [assetIdString] = true, ... }, shirt = assetIdString?, pants = assetIdString? }
local playerData = {}

-- caches so repeated sethair/respawns don't hit InsertService every time
local accessoryTemplateCache = {} -- [assetIdString] = Accessory/Hat instance template (not parented)
local shirtTemplateCache     = {} -- [assetIdString] = resolved ShirtTemplate content id string
local pantsTemplateCache     = {} -- [assetIdString] = resolved PantsTemplate content id string

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

-- Loads an asset by ID and returns the Model InsertService produces, or nil + reason.
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

-- Returns a reusable (unparented) Accessory/Hat template instance for the given
-- asset ID, validating that the asset actually is one. Caches successful lookups.
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

-- Removes any accessory on the character tagged with this asset ID, so
-- re-applying the same hair replaces it instead of stacking a duplicate.
local function removeAccessoryInstance(character: Model, idStr: string)
        for _, inst in character:GetChildren() do
                if (inst:IsA("Accessory") or inst:IsA("Hat")) and inst:GetAttribute("CosmeticAssetId") == idStr then
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

-- searches the full descendant tree, not just direct children, since catalog
-- clothing assets loaded via InsertService can come back wrapped in an extra
-- container Model rather than exposing the Shirt/Pants as a direct child
local function findDescendantOfClass(root: Instance, className: string): Instance?
        for _, inst in root:GetDescendants() do
                if inst:IsA(className) then
                        return inst
                end
        end
        return nil
end

-- Resolves the given asset ID to an actual usable ShirtTemplate/PantsTemplate
-- content id. We can't just build "rbxassetid://<assetId>" ourselves: if the
-- admin passed a bundle/package ID (the ID shown on most catalog pages) rather
-- than the underlying individual Shirt/Pants asset ID, that URL doesn't point
-- to a real clothing texture and the clothing renders as nothing (bare body).
-- Instead we load the asset, find the actual Shirt/Pants instance inside it,
-- and reuse its own template property, which is always correct.
local function resolveClothingTemplate(assetId: number, className: string, cache: { [string]: string }): (string?, string?)
        local idStr = tostring(assetId)
        if cache[idStr] then
                return cache[idStr], nil
        end

        local model, err = loadAssetModel(assetId)
        if not model then
                return nil, err
        end

        local found = findDescendantOfClass(model, className)
        local template = found and (found :: any)[className == "Shirt" and "ShirtTemplate" or "PantsTemplate"] or nil
        model:Destroy()

        if not found or type(template) ~= "string" or template == "" then
                -- don't cache negatives: a transient load hiccup shouldn't permanently
                -- brand a valid asset ID as invalid for the rest of the server's life
                return nil, "Asset " .. idStr .. " is not a " .. className .. " asset."
        end

        cache[idStr] = template
        return template, nil
end

local function applyShirtToCharacter(character: Model, template: string)
        local shirt = character:FindFirstChildOfClass("Shirt")
        if not shirt then
                shirt = Instance.new("Shirt")
                shirt.Parent = character
        end
        shirt.ShirtTemplate = template
end

local function applyPantsToCharacter(character: Model, template: string)
        local pants = character:FindFirstChildOfClass("Pants")
        if not pants then
                pants = Instance.new("Pants")
                pants.Parent = character
        end
        pants.PantsTemplate = template
end

-- setshirt <target> <assetId> <permanent>
function CosmeticsManager.setShirt(player: Player, assetId: number, permanent: boolean): (boolean, string)
        local template, err = resolveClothingTemplate(assetId, "Shirt", shirtTemplateCache)
        if not template then
                return false, err or "Invalid asset ID."
        end

        local character = player.Character
        if character then
                applyShirtToCharacter(character, template)
        end

        local data = getData(player.UserId)
        data.shirt = permanent and tostring(assetId) or nil
        task.spawn(saveData, player.UserId, data)

        return true, character and "applied" or "saved (no character loaded)"
end

-- setpants <target> <assetId> <permanent>
function CosmeticsManager.setPants(player: Player, assetId: number, permanent: boolean): (boolean, string)
        local template, err = resolveClothingTemplate(assetId, "Pants", pantsTemplateCache)
        if not template then
                return false, err or "Invalid asset ID."
        end

        local character = player.Character
        if character then
                applyPantsToCharacter(character, template)
        end

        local data = getData(player.UserId)
        data.pants = permanent and tostring(assetId) or nil
        task.spawn(saveData, player.UserId, data)

        return true, character and "applied" or "saved (no character loaded)"
end

-- removehat <target>: permanently removes every saved accessory, and strips
-- them from the current character immediately. Temporary accessories are untouched.
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
                        local template, err = resolveClothingTemplate(assetId, "Shirt", shirtTemplateCache)
                        if template then
                                applyShirtToCharacter(character, template)
                        else
                                warn("[CosmeticsManager] failed to reapply shirt " .. data.shirt .. ": " .. tostring(err))
                        end
                end
        end
        if data.pants then
                local assetId = tonumber(data.pants)
                if assetId then
                        local template, err = resolveClothingTemplate(assetId, "Pants", pantsTemplateCache)
                        if template then
                                applyPantsToCharacter(character, template)
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
