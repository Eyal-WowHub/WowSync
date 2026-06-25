local _, addon = ...
local Addons = addon:NewObject("Addons")
local ModuleRegistry = addon:GetObject("ModuleRegistry")

local HashSet = addon.HashSet
local SnapshotApplyMode = addon.SnapshotApplyMode

Addons.Config = {
    SnapshotApplyMode = SnapshotApplyMode.All,
}

--[[
    Addon enabled/disabled state sync.

    Captures which user (non-Blizzard) addons are enabled, and restores
    that state when applying a snapshot. Changes take effect on reload.

    API:
        C_AddOns.GetNumAddOns()                   → total addon count
        C_AddOns.GetAddOnInfo(index)               → name, title, notes, loadable, reason, security
        C_AddOns.GetAddOnEnableState(name, char)   → 0=disabled, 1=some, 2=enabled
        C_AddOns.EnableAddOn(name, character)       → marks enabled (next reload)
        C_AddOns.DisableAddOn(name, character)      → marks disabled (next reload)

    IMPORTANT:
        - character param must be provided (UnitName("player")) for per-character state
        - Omitting character defaults to ALL characters since 10.2.0
        - Blizzard addons (security ~= "INSECURE") cannot be disabled (hotfix 10.2.7)
        - WowSync and its companion addons must never be disabled
]]

-- Addons that must never be disabled to prevent self-lockout
local PROTECTED_ADDONS = {
    ["WowSync"] = true,
    ["WowSync_UI"] = true,
}

local function IsUserAddOn(index)
    local _, _, _, _, _, security = C_AddOns.GetAddOnInfo(index)
    return security == "INSECURE"
end

local function IsProtected(name)
    return PROTECTED_ADDONS[name]
end

local function Identity(value)
    return value
end

--[[ Module API ]]

function Addons:Capture()
    local character = UnitName("player")
    local enabled = {}

    for i = 1, C_AddOns.GetNumAddOns() do
        if IsUserAddOn(i) then
            local name = C_AddOns.GetAddOnInfo(i)
            local state = C_AddOns.GetAddOnEnableState(name, character)

            if state > 0 then
                tinsert(enabled, name)
            end
        end
    end

    table.sort(enabled)

    return {
        Enabled = enabled,
    }
end

function Addons:Apply(capturedData, sourceMetadata, applyOptions)
    if not capturedData or not capturedData.Enabled then
        return
    end

    local exact = applyOptions and applyOptions.mode == "exact"
    local character = UnitName("player")

    -- Build a lookup set from the snapshot's enabled list.
    local shouldBeEnabled = {}
    for _, name in ipairs(capturedData.Enabled) do
        shouldBeEnabled[name] = true
    end

    local changed = false

    for i = 1, C_AddOns.GetNumAddOns() do
        if IsUserAddOn(i) then
            local name = C_AddOns.GetAddOnInfo(i)

            if IsProtected(name) then
                -- Never disable WowSync or its companions
                C_AddOns.EnableAddOn(name, character)
            elseif shouldBeEnabled[name] then
                local state = C_AddOns.GetAddOnEnableState(name, character)
                if state == 0 then
                    C_AddOns.EnableAddOn(name, character)
                    changed = true
                end
            elseif exact then
                -- Only Exact mode disables addons missing from the snapshot.
                local state = C_AddOns.GetAddOnEnableState(name, character)
                if state > 0 then
                    C_AddOns.DisableAddOn(name, character)
                    changed = true
                end
            end
        end
    end

    if changed then
        StaticPopup_Show("WOWSYNC_RELOAD_UI")
    end
end

-- Preview of which addons applying this snapshot would enable or disable.
function Addons:Diff(currentData, snapshotData)
    local currentSet = HashSet:From(currentData and currentData.Enabled, Identity, Identity)
    local snapshotSet = HashSet:From(snapshotData and snapshotData.Enabled, Identity, Identity)

    return {
        added = currentSet:Added(snapshotSet),
        changed = {},
        removed = currentSet:Removed(snapshotSet),
    }
end

function Addons:CanApply(sourceMetadata)
    return true
end

--[[ Registration ]]

function Addons:OnInitialized()
    ModuleRegistry:Register(self)
end
