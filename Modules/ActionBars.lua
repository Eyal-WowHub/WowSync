local _, addon = ...
local ActionBars = addon:NewObject("ActionBars")
local ModuleRegistry = addon:GetObject("ModuleRegistry")

local L = addon.L
local HashSet = addon.HashSet
local SnapshotApplyMode = addon.SnapshotApplyMode

ActionBars.Config = {
    -- Runs after macros and talents so the actions it places already exist.
    ApplyPriority = 50,
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

    -- For macros, store the slot's macro name so the action can be matched on
    -- any character. GetActionInfo's id is unreliable here: for dynamic
    -- #showtooltip macros it is the shown spell/item id, not the macro index,
    -- so the name is read from the slot itself.
    if actionType == "macro" then
        local name = C_ActionBar.GetActionText(slotID)
        if name and name ~= "" then
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

function ActionBars:Apply(capturedData, sourceMetadata, applyOptions)
    local isSameClass = sourceMetadata.ClassID == PlayerUtil.GetClassID()
    local exact = applyOptions and applyOptions.mode == "exact"

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

        -- Exact mode: empty every shared slot the snapshot doesn't define, so the
        -- bars end up matching the snapshot instead of merging onto what's there.
        if exact then
            self:ClearMissingSlots(SHARED_SLOT_RANGES, capturedData.Shared)
        end

        -- Apply spec-specific bars (only if same class and matching spec exists)
        if capturedData.Specs and isSameClass then
            local specID = GetSpecializationInfo(GetSpecialization())
            local specSlots = specID and capturedData.Specs[specID]

            if specSlots then
                for slotID, slotInfo in pairs(specSlots) do
                    self:PlaceAction(slotID, slotInfo, true)
                end

                if exact then
                    self:ClearMissingSlots({ SPEC_SLOTS }, specSlots)
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
        -- Macros are matched by name (indices differ per character); without a
        -- captured name the macro can't be resolved.
        if not slotInfo.macroName then
            return
        end
        local macroIndex = GetMacroIndexByName(slotInfo.macroName)
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

-- Empty any slot in the given ranges that the desired set doesn't define, so an
-- exact apply leaves only the snapshot's actions on the captured bars.
function ActionBars:ClearMissingSlots(ranges, desiredSlots)
    for _, range in ipairs(ranges) do
        for slotID = range[1], range[2] do
            if not (desiredSlots and desiredSlots[slotID]) and GetActionInfo(slotID) then
                PickupAction(slotID)
                ClearCursor()
            end
        end
    end
end

-- A friendly name for the action in a slot, for diff previews.
local function ActionLabel(entry)
    local slotInfo = entry.info
    if slotInfo.type == "spell" or slotInfo.type == "companion" then
        return C_Spell.GetSpellName(slotInfo.id) or ("Spell " .. tostring(slotInfo.id))
    elseif slotInfo.type == "item" then
        return (C_Item.GetItemNameByID and C_Item.GetItemNameByID(slotInfo.id)) or ("Item " .. tostring(slotInfo.id))
    elseif slotInfo.type == "macro" then
        -- No captured name: id is the shown spell/item id for dynamic macros,
        -- not a macro index, so don't render it as one.
        return slotInfo.macroName or "Unnamed macro"
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

-- The icon texture for the action in a slot, for diff previews.
local function ActionIcon(entry)
    local slotInfo = entry.info
    if slotInfo.type == "spell" or slotInfo.type == "companion" then
        return C_Spell.GetSpellTexture(slotInfo.id)
    elseif slotInfo.type == "item" then
        return C_Item.GetItemIconByID(slotInfo.id)
    end
    return nil
end

-- Preview of which action slots applying this snapshot would change.
function ActionBars:Diff(currentData, snapshotData)
    local currentSet = HashSet:From(FlattenSlots(currentData), SlotKey, ActionLabel, ActionIcon)
    local snapshotSet = HashSet:From(FlattenSlots(snapshotData), SlotKey, ActionLabel, ActionIcon)

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

-- Order slots by real slot ID, then by spec, so a live render and a stored
-- render line up entry for entry.
local function SortSlots(slots)
    table.sort(slots, function(a, b)
        if a.Slot ~= b.Slot then
            return a.Slot < b.Slot
        end
        return (a.Spec or 0) < (b.Spec or 0)
    end)
    return slots
end

-- The live action-slot layout as a flat, ordered list with each slot's real ID,
-- plus the spec and paging context that decide which slots are showing. Reading
-- it raw exposes any mismatch between what a snapshot stored and what landed.
function ActionBars:GetDebugState()
    local specID = GetSpecializationInfo(GetSpecialization())
    local slots = {}

    local function record(slotID, slotSpecID)
        local slotInfo = GetSlotInfo(slotID)
        if slotInfo then
            tinsert(slots, {
                Slot = slotID,
                Spec = slotSpecID,
                Type = slotInfo.type,
                Id = slotInfo.id,
                SubType = slotInfo.subType,
                Name = ActionLabel({ info = slotInfo }),
            })
        end
    end

    for _, range in ipairs(SHARED_SLOT_RANGES) do
        for slotID = range[1], range[2] do
            record(slotID)
        end
    end
    for slotID = SPEC_SLOTS[1], SPEC_SLOTS[2] do
        record(slotID, specID)
    end

    SortSlots(slots)

    return {
        Slots = slots,
        SpecID = specID,
        ShapeshiftForm = GetShapeshiftForm(),
        BonusBarOffset = GetBonusBarOffset(),
        ActionBarPage = GetActionBarPage(),
    }
end

-- Render a stored capture payload into the same flat, ordered shape as GetDebugState(),
-- so a saved or applied payload compares slot for slot against live state. A
-- sparse-key shift from serialization shows up here as wrong slot IDs.
function ActionBars:RenderDebugPayload(capturedData)
    local slots = {}

    local function record(slotID, slotInfo, specID)
        tinsert(slots, {
            Slot = slotID,
            Spec = specID,
            Type = slotInfo.type,
            Id = slotInfo.id,
            SubType = slotInfo.subType,
            Name = ActionLabel({ info = slotInfo }),
        })
    end

    if capturedData and capturedData.Shared then
        for slotID, slotInfo in pairs(capturedData.Shared) do
            record(slotID, slotInfo)
        end
    end
    if capturedData and capturedData.Specs then
        for specID, specSlots in pairs(capturedData.Specs) do
            for slotID, slotInfo in pairs(specSlots) do
                record(slotID, slotInfo, specID)
            end
        end
    end

    SortSlots(slots)

    return { Slots = slots }
end

--[[ Registration ]]

function ActionBars:OnInitialized()
    ModuleRegistry:Register(self)
end
