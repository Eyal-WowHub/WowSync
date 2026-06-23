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
    whoever is online); other characters' Current is read-only here, kept fresh by
    a capture on logout. UndoStore owns the Undo list under the same entry.
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

-- Capture one module's live state, honoring its optional CanCapture() gate.
-- Returns the captured data and true on success; nil and false when the module
-- declined capture (e.g. combat lockdown) or its Capture() errored.
local function CaptureModule(name, module)
    if module.CanCapture and not module:CanCapture() then
        return nil, false
    end

    local ok, data = pcall(module.Capture, module)
    if not ok then
        -- A module's Capture() is not expected to error; surface it so a broken
        -- module is diagnosable instead of silently vanishing.
        addon:Print(addon.L["Could not capture module 'X': Y"]:format(name, tostring(data)))
        return nil, false
    end

    return data, true
end

function CurrentStore:OnInitialized()
    characters = addon.DB.global.Characters
    -- A character's Current exists from its first login.
    EnsureEntry(CharacterInfo:GetFullName())

    -- Persist the logged-in character's live setup on logout/reload so other
    -- characters can browse it without logging in.
    self:RegisterEvent("PLAYER_LOGOUT", function()
        self:Refresh()
    end)
end

-- Re-capture the logged-in character's live setup into its Current.
function CurrentStore:Refresh()
    local key = CharacterInfo:GetFullName()
    local entry = EnsureEntry(key)

    entry.Meta.ClassID = PlayerUtil.GetClassID()
    entry.Meta.LastSeen = time()

    local previous = entry.Current
    local current = {}
    for name, module in ModuleRegistry:Iterate() do
        local data, ok = CaptureModule(name, module)
        if ok then
            current[name] = data
        else
            -- The module declined capture (e.g. combat lockdown) or errored;
            -- keep its last-known data rather than dropping it from Current.
            current[name] = previous[name]
        end
    end

    entry.Current = current
    return current
end

-- Re-capture a single module into the logged-in character's Current, leaving the
-- other modules untouched. Used by the live GameWatcher to mirror just what
-- changed. Returns true when captured, or false when skipped (unknown module, or
-- CanCapture deferred it, e.g. during combat).
function CurrentStore:RefreshModule(name)
    local module = ModuleRegistry:Get(name)
    if not module then
        return false
    end

    local entry = EnsureEntry(CharacterInfo:GetFullName())
    entry.Meta.ClassID = PlayerUtil.GetClassID()
    entry.Meta.LastSeen = time()

    local data, ok = CaptureModule(name, module)
    if not ok then
        return false
    end

    entry.Current[name] = data
    return true
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
