local _, addon = ...
local Macros = addon:NewObject("Macros")

local ProfileManager = addon:GetObject("ProfileManager")
local HashSet = addon.HashSet
local SnapshotApplyMode = addon.SnapshotApplyMode
local L = addon.L

Macros.Config = {
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

--[[ Module API ]]

function Macros:Capture()
    return {
        Account = CaptureMacroRange(1, MAX_ACCOUNT_MACROS),
        Character = CaptureMacroRange(MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS),
    }
end

function Macros:Apply(data, meta, opts)
    local exact = opts and opts.mode == "exact"

    if data.Account then
        self:ApplyMacros(data.Account, false, exact)
    end

    if data.Character then
        self:ApplyMacros(data.Character, true, exact)
    end
end

function Macros:ApplyMacros(macros, isCharacterSpecific, exact)
    if exact then
        local keep = {}
        for _, macro in ipairs(macros) do
            keep[macro.Name] = true
        end
        DeleteExtraMacros(keep, isCharacterSpecific)
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
function Macros:Diff(current, snapshot)
    current = current or {}
    snapshot = snapshot or {}

    local added, changed, removed = {}, {}, {}

    local function MergeInto(target, source)
        for _, label in ipairs(source) do
            tinsert(target, label)
        end
    end

    local scopes = {
        { field = "Account", labelOf = MacroKey },
        { field = "Character", labelOf = function(macro) return L["X (character)"]:format(macro.Name) end },
    }

    for _, scope in ipairs(scopes) do
        local currentSet = HashSet:From(current[scope.field], MacroKey, scope.labelOf)
        local snapshotSet = HashSet:From(snapshot[scope.field], MacroKey, scope.labelOf)
        MergeInto(added, currentSet:Added(snapshotSet))
        MergeInto(changed, currentSet:Changed(snapshotSet))
        MergeInto(removed, currentSet:Removed(snapshotSet))
    end

    return { added = added, changed = changed, removed = removed }
end

function Macros:CanApply(meta)
    return true
end

--[[ Registration ]]

function Macros:OnInitialized()
    ProfileManager:RegisterModule(self)
end
