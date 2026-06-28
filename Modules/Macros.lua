local _, addon = ...
local Macros = addon:NewObject("Macros")
local ModuleRegistry = addon:GetObject("ModuleRegistry")

local L = addon.L
local HashSet = addon.HashSet
local SnapshotApplyMode = addon.SnapshotApplyMode

Macros.Config = {
    -- Runs early: bars and bindings resolve macros by name, so they must exist first.
    ApplyPriority = 10,
    SnapshotApplyMode = SnapshotApplyMode.All,
}

local MAX_ACCOUNT_MACROS = MAX_ACCOUNT_MACROS or 120
local MAX_CHARACTER_MACROS = MAX_CHARACTER_MACROS or 30

--[[ Helpers ]]

local function CaptureMacroRange(startIndex, endIndex)
    local macros = {}

    for i = startIndex, endIndex do
        local name, iconTexture, body = GetMacroInfo(i)
        if name then
            tinsert(macros, {
                Name = name,
                Icon = iconTexture,
                Body = body,
            })
        end
    end

    return macros
end

local function ScopeRange(isCharacterSpecific)
    if isCharacterSpecific then
        return MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS
    end
    return 1, MAX_ACCOUNT_MACROS
end

local function FindMacroInScope(name, isCharacterSpecific)
    -- GetMacroIndexByName is scope-agnostic and returns the first match in
    -- either scope. Scan only the relevant index range so we never edit an
    -- account macro when applying a character macro (or vice versa).
    local startIndex, endIndex = ScopeRange(isCharacterSpecific)

    for i = startIndex, endIndex do
        if GetMacroInfo(i) == name then
            return i
        end
    end

    return nil
end

-- Exact mode: delete in-scope macros whose name is not in keepNames.
-- Iterate descending so deleting an index never shifts one we have yet to see.
local function DeleteExtraMacros(keepNames, isCharacterSpecific)
    local startIndex, endIndex = ScopeRange(isCharacterSpecific)
    for i = endIndex, startIndex, -1 do
        local name = GetMacroInfo(i)
        if name and not keepNames[name] then
            DeleteMacro(i)
        end
    end
end

local function MacroKey(macro)
    return macro.Name
end

local function MacroIcon(macro)
    return macro.Icon
end

--[[ Module API ]]

function Macros:Capture()
    return {
        Account = CaptureMacroRange(1, MAX_ACCOUNT_MACROS),
        Character = CaptureMacroRange(MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS),
    }
end

function Macros:Apply(capturedData, sourceMetadata, applyOptions)
    local exact = applyOptions and applyOptions.mode == "exact"

    if capturedData.Account then
        self:ApplyMacros(capturedData.Account, false, exact)
    end

    if capturedData.Character then
        self:ApplyMacros(capturedData.Character, true, exact)
    end
end

function Macros:ApplyMacros(macros, isCharacterSpecific, exact)
    if exact then
        local keepNames = {}
        for _, macro in ipairs(macros) do
            keepNames[macro.Name] = true
        end
        DeleteExtraMacros(keepNames, isCharacterSpecific)
    end

    for _, macro in ipairs(macros) do
        local existingIndex = FindMacroInScope(macro.Name, isCharacterSpecific)

        if existingIndex then
            EditMacro(existingIndex, macro.Name, macro.Icon, macro.Body)
        else
            local numAccountMacros, numCharacterMacros = GetNumMacros()

            if isCharacterSpecific then
                if numCharacterMacros < MAX_CHARACTER_MACROS then
                    CreateMacro(macro.Name, macro.Icon, macro.Body, true)
                end
            else
                if numAccountMacros < MAX_ACCOUNT_MACROS then
                    CreateMacro(macro.Name, macro.Icon, macro.Body, false)
                end
            end
        end
    end
end

-- Preview of what applying these macros would change, per scope.
function Macros:Diff(currentData, snapshotData)
    currentData = currentData or {}
    snapshotData = snapshotData or {}

    local added, changed, removed = {}, {}, {}

    local function AppendEntries(target, entries)
        for _, entry in ipairs(entries) do
            tinsert(target, entry)
        end
    end

    local scopes = {
        { field = "Account", labelOf = MacroKey },
        { field = "Character", labelOf = function(macro) return L["X (character)"]:format(macro.Name) end },
    }

    for _, scope in ipairs(scopes) do
        local currentSet = HashSet:From(currentData[scope.field], MacroKey, scope.labelOf, MacroIcon)
        local snapshotSet = HashSet:From(snapshotData[scope.field], MacroKey, scope.labelOf, MacroIcon)
        AppendEntries(added, currentSet:Added(snapshotSet))
        AppendEntries(changed, currentSet:Changed(snapshotSet))
        AppendEntries(removed, currentSet:Removed(snapshotSet))
    end

    return { added = added, changed = changed, removed = removed }
end

function Macros:CanApply(sourceMetadata)
    return true
end

-- Events that mean this module's live state may have changed, so the GameWatcher
-- can re-mirror it into Current (debounced).
function Macros:GetWatchedEvents()
    return { "UPDATE_MACROS" }
end

-- The live macro names per scope, so the debug log shows which macros existed
-- before and after a sync without dumping every macro body.
function Macros:GetDebugState()
    local function names(startIndex, endIndex)
        local list = {}
        for i = startIndex, endIndex do
            local name = GetMacroInfo(i)
            if name then
                tinsert(list, { Index = i, Name = name })
            end
        end
        return list
    end

    local numAccount, numCharacter = GetNumMacros()
    return {
        Counts = { Account = numAccount, Character = numCharacter },
        Account = names(1, MAX_ACCOUNT_MACROS),
        Character = names(MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS),
    }
end

--[[ Registration ]]

function Macros:OnInitialized()
    ModuleRegistry:Register(self)
end
