local _, addon = ...
local ActionBars = addon:NewObject("ActionBars")
local ProfileManager = addon:GetObject("ProfileManager")

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
    local actionType, id, subType = GetActionInfo(slotID)

    if not actionType then
        return nil
    end

    local info = {
        type = actionType,
        id = id,
        subType = subType,
    }

    -- For macros, store the name so we can find them on another character
    -- (macro indices differ per character)
    if actionType == "macro" and type(id) == "number" then
        local name = GetMacroInfo(id)
        if name then
            info.macroName = name
        end
    end

    -- For equipment sets, store the name for cross-character lookup
    if actionType == "equipmentset" then
        local setName = C_EquipmentSet.GetEquipmentSetInfo(id)
        if setName then
            info.setName = setName
        end
    end

    return info
end

local function CaptureSlotRange(startSlot, endSlot)
    local slots = {}
    for slotID = startSlot, endSlot do
        local info = GetSlotInfo(slotID)
        if info then
            slots[slotID] = info
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

function ActionBars:Apply(data, meta)
    local isSameClass = meta.ClassID == PlayerUtil.GetClassID()

    -- Mute UI sounds during bulk slot placement. Restore the original value
    -- even if placement errors, so we never leave the game muted.
    local savedSFX = C_CVar.GetCVar("Sound_EnableSFX")
    C_CVar.SetCVar("Sound_EnableSFX", "0")

    local ok, err = pcall(function()
        -- Apply shared bars
        if data.Shared then
            for slotID, info in pairs(data.Shared) do
                self:PlaceAction(slotID, info, isSameClass)
            end
        end

        -- Apply spec-specific bars (only if same class and matching spec exists)
        if data.Specs and isSameClass then
            local specID = GetSpecializationInfo(GetSpecialization())
            local specData = specID and data.Specs[specID]

            if specData then
                for slotID, info in pairs(specData) do
                    self:PlaceAction(slotID, info, true)
                end
            end
        end
    end)

    C_CVar.SetCVar("Sound_EnableSFX", savedSFX)

    -- Re-surface any placement error so ProfileManager reports the failure.
    if not ok then
        error(err)
    end
end

function ActionBars:PlaceAction(slotID, info, isSameClass)
    -- Skip if slot already has the desired action
    local currentType, currentID = GetActionInfo(slotID)
    if currentType == info.type and currentID == info.id then
        return
    end

    -- Pick up the action onto the cursor, then place it in the slot
    if info.type == "spell" then
        if not C_SpellBook.IsPlayerSpell(info.id) then
            if not isSameClass then
                return -- Cross-class: skip unknown spells
            end
        end
        C_Spell.PickupSpell(info.id)
    elseif info.type == "item" then
        C_Item.PickupItem(info.id)
    elseif info.type == "macro" then
        -- Use macro name for cross-character compatibility
        local macroName = info.macroName or info.id
        local macroIndex = GetMacroIndexByName(macroName)
        if macroIndex and macroIndex > 0 then
            PickupMacro(macroIndex)
        else
            return -- Macro doesn't exist on this character
        end
    elseif info.type == "companion" and info.subType == "MOUNT" then
        -- Mount spells can be picked up as spells
        C_Spell.PickupSpell(info.id)
    elseif info.type == "summonpet" then
        C_PetJournal.PickupPet(info.id)
    elseif info.type == "flyout" then
        local bookSlot = FindFlyoutInSpellBook(info.id)
        if bookSlot then
            C_SpellBook.PickupSpellBookItem(bookSlot, Enum.SpellBookSpellBank.Player)
        else
            return
        end
    elseif info.type == "equipmentset" then
        -- Look up by name for cross-character compatibility
        local setID = nil
        if info.setName then
            for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
                local name = C_EquipmentSet.GetEquipmentSetInfo(id)
                if name == info.setName then
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
    local info = entry.info
    if info.type == "spell" or info.type == "companion" then
        return C_Spell.GetSpellName(info.id) or ("Spell " .. tostring(info.id))
    elseif info.type == "item" then
        return (C_Item.GetItemNameByID and C_Item.GetItemNameByID(info.id)) or ("Item " .. tostring(info.id))
    elseif info.type == "macro" then
        return info.macroName or ("Macro " .. tostring(info.id))
    elseif info.type == "equipmentset" then
        return info.setName or "Equipment set"
    elseif info.type == "summonpet" then
        return "Battle pet"
    elseif info.type == "flyout" then
        return "Flyout " .. tostring(info.id)
    end
    return tostring(info.type)
end

-- Flatten the nested Shared/Specs maps into a keyed list for comparison.
-- Mirror Apply: shared slots plus only the current spec's slots, so the
-- preview never reports changes to inactive specs that Apply won't make.
local function FlattenSlots(data)
    local list = {}
    if not data then
        return list
    end

    if data.Shared then
        for slot, info in pairs(data.Shared) do
            tinsert(list, { key = "shared:" .. slot, info = info })
        end
    end

    if data.Specs then
        local specID = GetSpecializationInfo(GetSpecialization())
        local slots = specID and data.Specs[specID]
        if slots then
            for slot, info in pairs(slots) do
                tinsert(list, { key = specID .. ":" .. slot, info = info })
            end
        end
    end

    return list
end

local function SlotKey(entry)
    return entry.key
end

-- Preview of which action slots applying this profile would change.
function ActionBars:Diff(current, snapshot)
    local currentSet = HashSet:From(FlattenSlots(current), SlotKey, ActionLabel)
    local snapshotSet = HashSet:From(FlattenSlots(snapshot), SlotKey, ActionLabel)

    return {
        added = currentSet:Added(snapshotSet),
        changed = currentSet:Changed(snapshotSet),
        removed = currentSet:Removed(snapshotSet),
    }
end

function ActionBars:CanApply(meta)
    if meta.ClassID ~= PlayerUtil.GetClassID() then
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
    ProfileManager:RegisterModule(self)
end
