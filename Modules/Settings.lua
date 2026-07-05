local _, addon = ...
local Settings = addon:NewObject("Settings")
local ModuleRegistry = addon.ModuleRegistry

local HashSet = addon.HashSet
local SnapshotApplyMode = addon.SnapshotApplyMode

Settings.Config = {
    SnapshotApplyMode = SnapshotApplyMode.Merge,
    DefaultIcon = "Interface\\Icons\\Trade_Engineering",
}

local SETTINGS_CVARS = addon.SETTINGS_CVARS

-- The curated description of each tracked CVar, keyed by name for diff lookup.
local CVAR_DESCRIPTIONS = {}
for _, entry in ipairs(SETTINGS_CVARS) do
    CVAR_DESCRIPTIONS[entry.cvar] = entry.desc
end

--[[ Helpers ]]

local function SetTrackedCVar(cvar, value)
    -- GetCVarInfo returns: value, defaultValue, isStoredServerAccount,
    --   isStoredServerCharacter, isLockedFromUser, isSecure, isReadOnly
    local _, _, _, _, isLockedFromUser, isSecure, isReadOnly = C_CVar.GetCVarInfo(cvar)
    if isLockedFromUser or isSecure or isReadOnly then
        return
    end

    -- Isolate each SetCVar: a protected or erroring CVar must not abort the
    -- rest of the batch (the whole module Apply runs under a single pcall).
    pcall(C_CVar.SetCVar, cvar, value)
end

--[[ Module API ]]

function Settings:Capture()
    local account, character = {}, {}

    for _, entry in ipairs(SETTINGS_CVARS) do
        local cvar = entry.cvar
        local value = C_CVar.GetCVar(cvar)
        if value then
            -- GetCVarInfo returns: value, defaultValue, isStoredServerAccount,
            --   isStoredServerCharacter, isLockedFromUser, isSecure, isReadOnly
            local _, _, _, isStoredServerCharacter = C_CVar.GetCVarInfo(cvar)

            if isStoredServerCharacter then
                character[cvar] = value
            else
                account[cvar] = value
            end
        end
    end

    return {
        Account = account,
        Character = character,
    }
end

function Settings:Apply(capturedData, sourceMetadata)
    if capturedData.Account then
        for cvar, value in pairs(capturedData.Account) do
            SetTrackedCVar(cvar, value)
        end
    end

    if capturedData.Character then
        for cvar, value in pairs(capturedData.Character) do
            SetTrackedCVar(cvar, value)
        end
    end
end

-- Each tracked CVar as a keyed list entry, hashed by name + value.
local function CVarEntries(capturedData)
    local cvarEntries = {}
    if not capturedData then
        return cvarEntries
    end
    for _, scope in ipairs({ "Account", "Character" }) do
        local scopedCVars = capturedData[scope]
        if scopedCVars then
            for cvar, value in pairs(scopedCVars) do
                tinsert(cvarEntries, { Name = cvar, Value = value })
            end
        end
    end
    return cvarEntries
end

local function CVarKey(entry)
    return entry.Name
end

-- The curated human description of a tracked CVar, or nil when uncurated.
local function CVarDescription(entry)
    return CVAR_DESCRIPTIONS[entry.Name]
end

-- Preview of which CVars applying this snapshot would change.
function Settings:Diff(currentData, snapshotData)
    local currentSet = HashSet:From(CVarEntries(currentData), CVarKey, CVarKey, nil, CVarDescription)
    local snapshotSet = HashSet:From(CVarEntries(snapshotData), CVarKey, CVarKey, nil, CVarDescription)

    return {
        added = currentSet:Added(snapshotSet),
        changed = currentSet:Changed(snapshotSet),
        removed = currentSet:Removed(snapshotSet),
    }
end

function Settings:CanApply(sourceMetadata)
    return true
end

-- Events that mean this module's live state may have changed, so the GameWatcher
-- can re-mirror it into Current (debounced). CVAR_UPDATE is chatty, but the
-- watcher debounces and only this module re-captures.
function Settings:GetWatchedEvents()
    return { "CVAR_UPDATE" }
end

-- The current value of each tracked CVar, so the debug log shows which settings
-- changed before and after a sync.
function Settings:GetDebugState()
    local values = {}
    for _, entry in ipairs(SETTINGS_CVARS) do
        local cvar = entry.cvar
        values[cvar] = C_CVar.GetCVar(cvar)
    end
    return { CVars = values }
end

--[[ Registration ]]

function Settings:OnInitialized()
    ModuleRegistry:Register(self)
end
