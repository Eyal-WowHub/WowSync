local _, addon = ...
local PvpTalents = addon:NewObject("PvpTalents")
local ModuleRegistry = addon:GetObject("ModuleRegistry")

local L = addon.L
local HashSet = addon.HashSet
local SnapshotApplyMode = addon.SnapshotApplyMode

PvpTalents.Config = {
    -- Runs after Talents (so the spec is settled) but before ActionBars, since
    -- PvP talent spells can sit on the bars.
    ApplyPriority = 30,
    SnapshotApplyMode = SnapshotApplyMode.Merge,
}

-- PvP talents fill three fixed slots, unlocked progressively by honor level.
local PVP_TALENT_SLOT_COUNT = 3

--[[ Helpers ]]

-- The talent selected in each filled slot of the active spec, keyed by slot.
local function CaptureSlots()
    local slots = {}
    for slotIndex = 1, PVP_TALENT_SLOT_COUNT do
        local slotInfo = C_SpecializationInfo.GetPvpTalentSlotInfo(slotIndex)
        if slotInfo and slotInfo.selectedTalentID then
            slots[slotIndex] = slotInfo.selectedTalentID
        end
    end
    return slots
end

-- Whether a talent is one of the choices the slot currently offers.
local function SlotOffersTalent(slotInfo, talentID)
    for _, availableID in ipairs(slotInfo.availableTalentIDs or {}) do
        if availableID == talentID then
            return true
        end
    end
    return false
end

-- Flatten the active spec's stored slots into a keyed entry list for diffing.
local function FlattenSlots(capturedData)
    local entries = {}
    local specID = GetSpecializationInfo(GetSpecialization())
    local specEntry = specID and capturedData and capturedData.Specs and capturedData.Specs[specID]
    if specEntry and specEntry.Slots then
        for slotIndex = 1, PVP_TALENT_SLOT_COUNT do
            local talentID = specEntry.Slots[slotIndex]
            if talentID then
                tinsert(entries, { SlotIndex = slotIndex, TalentID = talentID })
            end
        end
    end
    return entries
end

local function SlotKey(entry)
    return entry.SlotIndex
end

-- The selected talent's name, for diff previews.
local function SlotLabel(entry)
    local talentInfo = C_SpecializationInfo.GetPvpTalentInfo(entry.TalentID)
    return talentInfo and talentInfo.name or tostring(entry.TalentID)
end

-- The selected talent's icon, for diff previews.
local function SlotIcon(entry)
    local talentInfo = C_SpecializationInfo.GetPvpTalentInfo(entry.TalentID)
    return talentInfo and talentInfo.icon
end

--[[ Module API ]]

function PvpTalents:Capture()
    local capturedData = { Specs = {} }

    local specID = GetSpecializationInfo(GetSpecialization())
    if not specID then
        return capturedData
    end

    local slots = CaptureSlots()
    if next(slots) then
        capturedData.Specs[specID] = { Slots = slots }
    end

    return capturedData
end

function PvpTalents:Apply(capturedData)
    local specID = GetSpecializationInfo(GetSpecialization())
    local specEntry = specID and capturedData.Specs and capturedData.Specs[specID]
    if not specEntry or not specEntry.Slots then
        return
    end

    for slotIndex = 1, PVP_TALENT_SLOT_COUNT do
        local talentID = specEntry.Slots[slotIndex]
        if talentID then
            local slotInfo = C_SpecializationInfo.GetPvpTalentSlotInfo(slotIndex)
            if slotInfo and slotInfo.enabled
                and slotInfo.selectedTalentID ~= talentID
                and SlotOffersTalent(slotInfo, talentID) then
                LearnPvpTalent(talentID, slotIndex)
            end
        end
    end
end

-- Preview of which PvP talent slots applying this snapshot would change.
function PvpTalents:Diff(currentData, snapshotData)
    local currentSet = HashSet:From(FlattenSlots(currentData), SlotKey, SlotLabel, SlotIcon)
    local snapshotSet = HashSet:From(FlattenSlots(snapshotData), SlotKey, SlotLabel, SlotIcon)

    return {
        added = currentSet:Added(snapshotSet),
        changed = currentSet:Changed(snapshotSet),
        removed = currentSet:Removed(snapshotSet),
    }
end

function PvpTalents:CanApply(sourceMetadata)
    if sourceMetadata.ClassID ~= PlayerUtil.GetClassID() then
        return false, L["PvP talents are class-specific"]
    end
    return true
end

-- Events that mean this module's live state may have changed, so the GameWatcher
-- can re-mirror it into Current (debounced).
function PvpTalents:GetWatchedEvents()
    return { "PLAYER_PVP_TALENT_UPDATE", "PLAYER_SPECIALIZATION_CHANGED" }
end

-- The active spec's selected PvP talent per slot, so the debug log shows what
-- was chosen before and after a sync.
function PvpTalents:GetDebugState()
    local specID = GetSpecializationInfo(GetSpecialization())

    local slots = {}
    for slotIndex = 1, PVP_TALENT_SLOT_COUNT do
        local slotInfo = C_SpecializationInfo.GetPvpTalentSlotInfo(slotIndex)
        local talentID = slotInfo and slotInfo.selectedTalentID
        local talentInfo = talentID and C_SpecializationInfo.GetPvpTalentInfo(talentID)
        slots[slotIndex] = {
            Enabled = slotInfo and slotInfo.enabled or false,
            TalentID = talentID,
            Name = talentInfo and talentInfo.name,
        }
    end

    return {
        SpecID = specID,
        Slots = slots,
    }
end

--[[ Registration ]]

function PvpTalents:OnInitialized()
    ModuleRegistry:Register(self)
end
