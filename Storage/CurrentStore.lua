local _, addon = ...
local CurrentStore = addon:NewObject("CurrentStore")

local ModuleRegistry = addon:GetObject("ModuleRegistry")
local CharacterInfo = LibStub("CharacterInfo-1.0")

--[[
    CurrentStore — the live "Current" setup, one per character.

    Each character owns an entry under DB.global.Characters[charKey]:

        { Meta = { ClassID, LastSeen }, Current = { ... }, Undo = { ... } }

    Current is the most recently captured live state for that character. Only the
    logged-in character can be captured (the game only exposes live state for
    whoever is online); other characters' Current is read-only here (persisted in
    a later phase). UndoStore owns the Undo list under the same entry.
]]

local characters

local function EnsureEntry(key)
    local entry = characters[key]
    if not entry then
        entry = { Meta = {}, Current = {}, Undo = {} }
        characters[key] = entry
    end
    return entry
end

function CurrentStore:OnInitialized()
    characters = addon.DB.global.Characters
    -- A character's Current exists from its first login.
    EnsureEntry(CharacterInfo:GetFullName())
end

-- Re-capture the logged-in character's live setup into its Current.
function CurrentStore:Refresh()
    local key = CharacterInfo:GetFullName()
    local entry = EnsureEntry(key)

    entry.Meta.ClassID = PlayerUtil.GetClassID()
    entry.Meta.LastSeen = time()

    local current = {}
    for name, module in ModuleRegistry:Iterate() do
        if not module.CanCapture or module:CanCapture() then
            local ok, data = pcall(module.Capture, module)
            if ok then
                current[name] = data
            end
        end
    end

    entry.Current = current
    return current
end

-- Current setup for a character (defaults to the logged-in one).
function CurrentStore:Get(key)
    key = key or CharacterInfo:GetFullName()
    local entry = characters[key]
    return entry and entry.Current
end

function CurrentStore:GetMeta(key)
    key = key or CharacterInfo:GetFullName()
    local entry = characters[key]
    return entry and entry.Meta
end

-- The full per-character table (for the cross-character browser, later phase).
function CurrentStore:GetCharacters()
    return characters
end
