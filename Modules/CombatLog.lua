local _, addon = ...
local CombatLog = addon:NewObject("CombatLog")
local ModuleRegistry = addon:GetObject("ModuleRegistry")

local HashSet = addon.HashSet
local SnapshotApplyMode = addon.SnapshotApplyMode

CombatLog.Config = {
    -- Applying replaces the whole filter set wholesale, so the result always
    -- matches the snapshot exactly; there is no additive merge to offer.
    SnapshotApplyMode = SnapshotApplyMode.Exact,
}

--[[
    CombatLog Module

    Captures and restores the Blizzard Combat Log filter and color settings.
    These are stored in the Blizzard_CombatLog addon's SavedVariables:
    - Blizzard_CombatLog_Filters: filter presets (events, colors, formatting)
    - Blizzard_CombatLog_CurrentSettings: reference to the active filter

    Because Blizzard_CombatLog is a load-on-demand addon, it may not be loaded
    at capture/apply time. The module handles this gracefully.
]]

--[[ Helpers ]]

local function DeepCopy(source)
    if type(source) ~= "table" then
        return source
    end

    local copy = {}
    for key, value in pairs(source) do
        copy[DeepCopy(key)] = DeepCopy(value)
    end

    return copy
end

local function IsBlizzardCombatLogLoaded()
    return C_AddOns.IsAddOnLoaded("Blizzard_CombatLog")
end

--[[ Module API ]]

function CombatLog:Capture()
    local capturedData = {}

    -- Attempt to load Blizzard_CombatLog if not already loaded
    if not IsBlizzardCombatLogLoaded() then
        C_AddOns.LoadAddOn("Blizzard_CombatLog")
    end

    -- Capture filter settings if the addon is loaded
    if IsBlizzardCombatLogLoaded() and Blizzard_CombatLog_Filters then
        capturedData.Filters = DeepCopy(Blizzard_CombatLog_Filters)

        -- Track which filter index is currently active
        if Blizzard_CombatLog_CurrentSettings then
            for i, filter in ipairs(Blizzard_CombatLog_Filters) do
                if filter.settings == Blizzard_CombatLog_CurrentSettings then
                    capturedData.ActiveFilterIndex = i
                    break
                end
            end
        end
    end

    return capturedData
end

function CombatLog:Apply(capturedData, sourceMetadata)
    if not capturedData.Filters then
        return
    end

    -- Ensure Blizzard_CombatLog is loaded before applying
    if not IsBlizzardCombatLogLoaded() then
        C_AddOns.LoadAddOn("Blizzard_CombatLog")
    end

    if not IsBlizzardCombatLogLoaded() then
        return
    end

    -- Restore filter settings
    Blizzard_CombatLog_Filters = DeepCopy(capturedData.Filters)

    -- Restore the active filter reference
    local activeIndex = capturedData.ActiveFilterIndex or 1
    if Blizzard_CombatLog_Filters[activeIndex] then
        Blizzard_CombatLog_CurrentSettings = Blizzard_CombatLog_Filters[activeIndex].settings
    end

    -- Refresh the combat log display if the update function exists
    if Blizzard_CombatLog_Update_QuickButtons then
        Blizzard_CombatLog_Update_QuickButtons()
    end

    if Blizzard_CombatLog_Refilter then
        Blizzard_CombatLog_Refilter()
    end
end

-- Each combat-log filter preset as a keyed list entry, hashed by its content.
local function FilterEntries(capturedData)
    local filterEntries = {}
    if capturedData and capturedData.Filters then
        for i, filter in ipairs(capturedData.Filters) do
            local label = filter.name or ("Filter " .. i)
            tinsert(filterEntries, { key = filter.name or i, label = label, filter = filter })
        end
    end
    return filterEntries
end

local function FilterKey(entry)
    return entry.key
end

local function FilterLabel(entry)
    return entry.label
end

-- Preview of which combat-log filters applying this snapshot would change.
function CombatLog:Diff(currentData, snapshotData)
    local currentSet = HashSet:From(FilterEntries(currentData), FilterKey, FilterLabel)
    local snapshotSet = HashSet:From(FilterEntries(snapshotData), FilterKey, FilterLabel)

    return {
        added = currentSet:Added(snapshotSet),
        changed = currentSet:Changed(snapshotSet),
        removed = currentSet:Removed(snapshotSet),
    }
end

function CombatLog:CanApply(sourceMetadata)
    return true
end

-- Whether the load-on-demand combat-log addon is loaded and how many filters it
-- holds, so the debug log shows the filter state before and after a sync.
function CombatLog:GetDebugState()
    local loaded = IsBlizzardCombatLogLoaded()
    return {
        Loaded = loaded,
        FilterCount = (loaded and Blizzard_CombatLog_Filters) and #Blizzard_CombatLog_Filters or 0,
    }
end

--[[ Registration ]]

function CombatLog:OnInitialized()
    ModuleRegistry:Register(self)
end
