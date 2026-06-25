local _, addon = ...
local ActionBars = addon:NewObject("ActionBars")
local ModuleRegistry = addon:GetObject("ModuleRegistry")

local L = addon.L
local HashSet = addon.HashSet
local SnapshotApplyMode = addon.SnapshotApplyMode

ActionBars.Config = {
    SnapshotApplyMode = SnapshotApplyMode.Merge,
}

--[[ Slot Layout (see https://warcraft.wiki.gg/wiki/ActionSlot)
    Spec-specific (change when switching spec):
        1-12    Main Action Bar (page 1)

    Shared (persist across specs):
        13-24   Action Bar page 2
        25-36   Action Bar 4 (MultiBarRight)
        37-48   Action Bar 5 (MultiBarLeft)
        49-60   Action Bar 3 (MultiBarBottomRight)
        61-72   Action Bar 2 (MultiBarBottomLeft)
        145-156 Action Bar 6
        157-168 Action Bar 7
        169-180 Action Bar 8

    Class-specific stance/form bars (73-120) and
    possess/skyriding bar (121-132) are not captured.
]]

local SPEC_SLOTS = { 1, 12 }
local SHARED_SLOT_RANGES = {
    { 13, 72 },
    { 145, 180 },
}

--[[ Helpers ]]

local function FindFlyoutInSpellBook(flyoutID)
    local numTabs = C_SpellBook.GetNumSpellBookSkillLines()
    if not numTabs or numTabs == 0 then return nil end

    local lastTabInfo = C_SpellBook.GetSpellBookSkillLineInfo(numTabs)
    if not lastTabInfo then return nil end

    local totalSlots = lastTabInfo.itemIndexOffset + lastTabInfo.numSpellBookItems

    for i = 1, totalSlots do
        local itemInfo = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
        if itemInfo and itemInfo.itemType == Enum.SpellBookItemType.Flyout and itemInfo.actionID == flyoutID then
            return i
        end
    end
    return nil
end

local function GetSlotInfo(slotID)
    local actionType, actionID, actionSubType = GetActionInfo(slotID)

    if not actionType then
        return nil
    end

    local slotInfo = {
        type = actionType,
        id = actionID,
        subType = actionSubType,
    }

    -- For macros, store the name so we can find them on another character
    -- (macro indices differ per character)
    if actionType == "macro" and type(actionID) == "number" then
        local name = GetMacroInfo(actionID)
        if name then
            slotInfo.macroName = name
        end
    end

    -- For equipment sets, store the name for cross-character lookup
    if actionType == "equipmentset" then
        local setName = C_EquipmentSet.GetEquipmentSetInfo(actionID)
        if setName then
            slotInfo.setName = setName
        end
    end

    return slotInfo
end

local function CaptureSlotRange(startSlot, endSlot)
    local slots = {}
    for slotID = startSlot, endSlot do
        local slotInfo = GetSlotInfo(slotID)
        if slotInfo then
            slots[slotID] = slotInfo
        end
    end
    return slots
end

--[[ Module API ]]

function ActionBars:Capture()
    local shared = {}

    for _, range in ipairs(SHARED_SLOT_RANGES) do
        local slots = CaptureSlotRange(range[1], range[2])
        for slotID, info in pairs(slots) do
            shared[slotID] = info
        end
    end

    local specs = {}
    local specID = GetSpecializationInfo(GetSpecialization())
    if specID then
        specs[specID] = CaptureSlotRange(SPEC_SLOTS[1], SPEC_SLOTS[2])
    end

    return {
        Shared = shared,
        Specs = specs,
    }
end

function ActionBars:Apply(capturedData, sourceMetadata)
    local isSameClass = sourceMetadata.ClassID == PlayerUtil.GetClassID()

    -- Mute UI sounds during bulk slot placement. Restore the original value
    -- even if placement errors, so we never leave the game muted.
    local savedSFX = C_CVar.GetCVar("Sound_EnableSFX")
    C_CVar.SetCVar("Sound_EnableSFX", "0")

    local placementSucceeded, placementError = pcall(function()
        -- Apply shared bars
        if capturedData.Shared then
            for slotID, slotInfo in pairs(capturedData.Shared) do
                self:PlaceAction(slotID, slotInfo, isSameClass)
            end
        end

        -- Apply spec-specific bars (only if same class and matching spec exists)
        if capturedData.Specs and isSameClass then
            local specID = GetSpecializationInfo(GetSpecialization())
            local specSlots = specID and capturedData.Specs[specID]

            if specSlots then
                for slotID, slotInfo in pairs(specSlots) do
                    self:PlaceAction(slotID, slotInfo, true)
                end
            end
        end
    end)

    C_CVar.SetCVar("Sound_EnableSFX", savedSFX)

    -- Re-surface any placement error so SnapshotManager reports the failure.
    if not placementSucceeded then
        error(placementError)
    end
end

function ActionBars:PlaceAction(slotID, slotInfo, isSameClass)
    -- Skip if slot already has the desired action
    local currentType, currentID = GetActionInfo(slotID)
    if currentType == slotInfo.type and currentID == slotInfo.id then
        return
    end

    -- Pick up the action onto the cursor, then place it in the slot
    if slotInfo.type == "spell" then
        if not C_SpellBook.IsPlayerSpell(slotInfo.id) then
            if not isSameClass then
                return -- Cross-class: skip unknown spells
            end
        end
        C_Spell.PickupSpell(slotInfo.id)
    elseif slotInfo.type == "item" then
        C_Item.PickupItem(slotInfo.id)
    elseif slotInfo.type == "macro" then
        -- Use macro name for cross-character compatibility
        local macroName = slotInfo.macroName or slotInfo.id
        local macroIndex = GetMacroIndexByName(macroName)
        if macroIndex and macroIndex > 0 then
            PickupMacro(macroIndex)
        else
            return -- Macro doesn't exist on this character
        end
    elseif slotInfo.type == "companion" and slotInfo.subType == "MOUNT" then
        -- Mount spells can be picked up as spells
        C_Spell.PickupSpell(slotInfo.id)
    elseif slotInfo.type == "summonpet" then
        C_PetJournal.PickupPet(slotInfo.id)
    elseif slotInfo.type == "flyout" then
        local bookSlot = FindFlyoutInSpellBook(slotInfo.id)
        if bookSlot then
            C_SpellBook.PickupSpellBookItem(bookSlot, Enum.SpellBookSpellBank.Player)
        else
            return
        end
    elseif slotInfo.type == "equipmentset" then
        -- Look up by name for cross-character compatibility
        local setID = nil
        if slotInfo.setName then
            for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
                local name = C_EquipmentSet.GetEquipmentSetInfo(id)
                if name == slotInfo.setName then
                    setID = id
                    break
                end
            end
        end
        if setID then
            C_EquipmentSet.PickupEquipmentSet(setID)
        else
            return
        end
    else
        return
    end

    PlaceAction(slotID)
    ClearCursor()
end

-- A friendly name for the action in a slot, for diff previews.
local function ActionLabel(entry)
    local slotInfo = entry.info
    if slotInfo.type == "spell" or slotInfo.type == "companion" then
        return C_Spell.GetSpellName(slotInfo.id) or ("Spell " .. tostring(slotInfo.id))
    elseif slotInfo.type == "item" then
        return (C_Item.GetItemNameByID and C_Item.GetItemNameByID(slotInfo.id)) or ("Item " .. tostring(slotInfo.id))
    elseif slotInfo.type == "macro" then
        return slotInfo.macroName or ("Macro " .. tostring(slotInfo.id))
    elseif slotInfo.type == "equipmentset" then
        return slotInfo.setName or "Equipment set"
    elseif slotInfo.type == "summonpet" then
        return "Battle pet"
    elseif slotInfo.type == "flyout" then
        return "Flyout " .. tostring(slotInfo.id)
    end
    return tostring(slotInfo.type)
end

-- Flatten the nested Shared/Specs maps into a keyed list for comparison.
-- Mirror Apply: shared slots plus only the current spec's slots, so the
-- preview never reports changes to inactive specs that Apply won't make.
local function FlattenSlots(capturedData)
    local slotEntries = {}
    if not capturedData then
        return slotEntries
    end

    if capturedData.Shared then
        for slotID, slotInfo in pairs(capturedData.Shared) do
            tinsert(slotEntries, { key = "shared:" .. slotID, info = slotInfo })
        end
    end

    if capturedData.Specs then
        local specID = GetSpecializationInfo(GetSpecialization())
        local specSlots = specID and capturedData.Specs[specID]
        if specSlots then
            for slotID, slotInfo in pairs(specSlots) do
                tinsert(slotEntries, { key = specID .. ":" .. slotID, info = slotInfo })
            end
        end
    end

    return slotEntries
end

local function SlotKey(entry)
    return entry.key
end

-- Preview of which action slots applying this snapshot would change.
function ActionBars:Diff(currentData, snapshotData)
    local currentSet = HashSet:From(FlattenSlots(currentData), SlotKey, ActionLabel)
    local snapshotSet = HashSet:From(FlattenSlots(snapshotData), SlotKey, ActionLabel)

    return {
        added = currentSet:Added(snapshotSet),
        changed = currentSet:Changed(snapshotSet),
        removed = currentSet:Removed(snapshotSet),
    }
end

function ActionBars:CanApply(sourceMetadata)
    if sourceMetadata.ClassID ~= PlayerUtil.GetClassID() then
        return true, L["Only common actions will be applied"]
    end
    return true
end

-- Defer capture during combat: bonus/stance bar paging swaps the visible slots,
-- so the live state then reflects a transient bar, not the player's real setup.
-- (Action bars can't be edited in combat, so nothing real is missed by waiting.)
function ActionBars:ShouldCapture()
    return not InCombatLockdown()
end

-- Events that mean this module's live state may have changed, so the GameWatcher
-- can re-mirror it into Current (debounced).
function ActionBars:GetWatchedEvents()
    return { "ACTIONBAR_SLOT_CHANGED", "PLAYER_SPECIALIZATION_CHANGED" }
end

--[[ Registration ]]

function ActionBars:OnInitialized()
    ModuleRegistry:Register(self)
end
