local _, addon = ...
local Macros = addon:NewObject("Macros")

local ProfileManager = addon:GetObject("ProfileManager")

local MAX_ACCOUNT_MACROS = MAX_ACCOUNT_MACROS or 120
local MAX_CHARACTER_MACROS = MAX_CHARACTER_MACROS or 18

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

local function FindMacroInScope(name, isCharacterSpecific)
    -- GetMacroIndexByName is scope-agnostic and returns the first match in
    -- either scope. Scan only the relevant index range so we never edit an
    -- account macro when applying a character macro (or vice versa).
    local startIndex, endIndex
    if isCharacterSpecific then
        startIndex = MAX_ACCOUNT_MACROS + 1
        endIndex = MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS
    else
        startIndex = 1
        endIndex = MAX_ACCOUNT_MACROS
    end

    for i = startIndex, endIndex do
        if GetMacroInfo(i) == name then
            return i
        end
    end

    return nil
end

--[[ Module API ]]

function Macros:Capture()
    return {
        Account = CaptureMacroRange(1, MAX_ACCOUNT_MACROS),
        Character = CaptureMacroRange(MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS),
    }
end

function Macros:Apply(data, meta)
    if data.Account then
        self:ApplyMacros(data.Account, false)
    end

    if data.Character then
        self:ApplyMacros(data.Character, true)
    end
end

function Macros:ApplyMacros(macros, isCharacterSpecific)
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

function Macros:CanApply(meta)
    return true
end

--[[ Registration ]]

function Macros:OnInitialized()
    ProfileManager:RegisterModule(self)
end
