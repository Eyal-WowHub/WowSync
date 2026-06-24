local _, addon = ...
local CurrentStore = addon:NewObject("CurrentStore")
local ModuleRegistry = addon:GetObject("ModuleRegistry")
local ProfileStore = addon:GetObject("ProfileStore")

local CharacterInfo = LibStub("CharacterInfo-1.0")
local Codec = addon.Codec

--[[
    CurrentStore — the live "Current" setup, one per character.

    Current lives on the character's record under DB.Profiles[charKey].Current
    (the record itself is owned by ProfileStore). It is the most recently
    captured live state for that character. Only the logged-in character can be
    captured (the game only exposes live state for whoever is online); other
    characters' Current is read-only here, refreshed by a capture on logout.

    To keep the file small, every character's Current is stored COMPRESSED except
    the logged-in one: its Current is decompressed into a plain table at login for
    fast in-session access and recompressed on logout. Reading another
    character's Current decompresses a throwaway copy on demand.
]]

-- Capture one module's live state, honoring its optional ShouldCapture() gate.
-- Returns the captured data and true on success; nil and false when the module
-- declined capture (e.g. combat lockdown) or its Capture() errored.
local function CaptureModule(name, module)
    if module.ShouldCapture and not module:ShouldCapture() then
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
    -- A character's record exists from its first login.
    local entry = ProfileStore:CreateProfile(CharacterInfo:GetFullName())

    -- Decompress our own Current once so the live working set is a plain table
    -- for the session; every other character's stays compressed on its record.
    if type(entry.Current) == "string" then
        entry.Current = Codec:Decode(entry.Current) or {}
    end

    -- Persist the logged-in character's live setup on logout/reload so other
    -- characters can browse it without logging in, then compress it for storage.
    self:RegisterEvent("PLAYER_LOGOUT", function()
        self:Refresh()
        self:Compress()
    end)
end

-- Compress the logged-in character's Current for storage, so what lands on disk
-- is the small blob rather than the raw table.
function CurrentStore:Compress()
    local entry = ProfileStore:CreateProfile(CharacterInfo:GetFullName())
    if type(entry.Current) ~= "table" then
        return
    end

    local encoded = Codec:Encode(entry.Current)
    if encoded then
        entry.Current = encoded
    end
end

-- Re-capture the logged-in character's live setup into its Current.
function CurrentStore:Refresh()
    local entry = ProfileStore:CreateProfile(CharacterInfo:GetFullName())

    entry.Metadata.ClassID = PlayerUtil.GetClassID()
    entry.Metadata.LastSeen = time()

    local previous = entry.Current
    if type(previous) ~= "table" then
        previous = {}
    end
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
-- ShouldCapture declined it, e.g. during combat).
function CurrentStore:RefreshModule(name)
    local module = ModuleRegistry:Get(name)
    if not module then
        return false
    end

    local entry = ProfileStore:CreateProfile(CharacterInfo:GetFullName())
    entry.Metadata.ClassID = PlayerUtil.GetClassID()
    entry.Metadata.LastSeen = time()

    local data, ok = CaptureModule(name, module)
    if not ok then
        return false
    end

    entry.Current[name] = data

    -- Signal listeners (e.g. the companion UI's "unsaved changes" badge) that the
    -- live setup changed. Only this single-module live path fires the event;
    -- Refresh() deliberately does not, since PreviewApply() calls Refresh() and
    -- a UI that recomputes on this event would otherwise loop.
    WowSync:TriggerEvent("WOWSYNC_CURRENT_CHANGED")

    return true
end

-- Current setup for a character (defaults to the logged-in one). Another
-- character's Current is stored compressed, so this decompresses a copy.
function CurrentStore:Get(key)
    key = key or CharacterInfo:GetFullName()
    local profile = ProfileStore:GetProfile(key)
    local current = profile and profile.Current
    if type(current) == "string" then
        return Codec:Decode(current)
    end
    return current
end

function CurrentStore:GetMeta(key)
    key = key or CharacterInfo:GetFullName()
    local profile = ProfileStore:GetProfile(key)
    return profile and profile.Metadata
end
