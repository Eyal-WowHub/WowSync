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
local function TryCaptureModule(moduleName, module)
    if module.ShouldCapture and not module:ShouldCapture() then
        return nil, false
    end

    local captureSucceeded, capturedData = pcall(module.Capture, module)
    if not captureSucceeded then
        -- A module's Capture() is not expected to error; surface it so a broken
        -- module is diagnosable instead of silently vanishing.
        addon:Print(addon.L["Could not capture module 'X': Y"]:format(moduleName, tostring(capturedData)))
        return nil, false
    end

    return capturedData, true
end

function CurrentStore:OnInitialized()
    -- A character's record exists from its first login.
    local profile = ProfileStore:CreateProfile(CharacterInfo:GetFullName())

    -- Decompress our own Current once so the live working set is a plain table
    -- for the session; every other character's stays compressed on its record.
    if type(profile.Current) == "string" then
        profile.Current = Codec:Decode(profile.Current) or {}
    end

    -- Persist the logged-in character's live setup on logout/reload so other
    -- characters can browse it without logging in, then compress it for storage.
    self:RegisterEvent("PLAYER_LOGOUT", function()
        self:Capture()
        self:Compress()
    end)
end

-- Compress the logged-in character's Current for storage, so what lands on disk
-- is the small blob rather than the raw table.
function CurrentStore:Compress()
    local profile = ProfileStore:CreateProfile(CharacterInfo:GetFullName())
    if type(profile.Current) ~= "table" then
        return
    end

    local encoded = Codec:Encode(profile.Current)
    if encoded then
        profile.Current = encoded
    end
end

-- Re-capture the logged-in character's live setup into its Current.
function CurrentStore:Capture()
    local profile = ProfileStore:CreateProfile(CharacterInfo:GetFullName())

    profile.Metadata.ClassID = PlayerUtil.GetClassID()
    profile.Metadata.LastSeen = time()

    local previousModules = profile.Current
    if type(previousModules) ~= "table" then
        previousModules = {}
    end
    local capturedModules = {}
    for name, module in ModuleRegistry:Iterate() do
        local capturedData, captured = TryCaptureModule(name, module)
        if captured then
            capturedModules[name] = capturedData
        else
            -- The module declined capture (e.g. combat lockdown) or errored;
            -- keep its last-known data rather than dropping it from Current.
            capturedModules[name] = previousModules[name]
        end

        -- When driven by a sliced save (a coroutine), let the frame breathe
        -- between modules so a full capture never hitches; a synchronous caller
        -- (logout, apply) runs straight through.
        if coroutine.running() then
            coroutine.yield()
        end
    end

    profile.Current = capturedModules
    return capturedModules
end

-- Re-capture a single module into the logged-in character's Current, leaving the
-- other modules untouched. Returns true when captured, or false when skipped
-- (unknown module, or ShouldCapture declined it, e.g. during combat).
function CurrentStore:CaptureModule(moduleName)
    local module = ModuleRegistry:Get(moduleName)
    if not module then
        return false
    end

    local profile = ProfileStore:CreateProfile(CharacterInfo:GetFullName())
    profile.Metadata.ClassID = PlayerUtil.GetClassID()
    profile.Metadata.LastSeen = time()

    local capturedData, captured = TryCaptureModule(moduleName, module)
    if not captured then
        return false
    end

    profile.Current[moduleName] = capturedData

    -- Signal listeners that the live setup changed. Only this single-module path
    -- fires it; a bulk Capture() stays silent, so a listener that reacts by
    -- recapturing cannot feed back into a loop.
    WowSync:TriggerEvent("WOWSYNC_CURRENT_CHANGED")

    return true
end

-- Current setup for a character (defaults to the logged-in one). Another
-- character's Current is stored compressed, so this decompresses a copy.
function CurrentStore:Get(profileName)
    profileName = profileName or CharacterInfo:GetFullName()
    local profile = ProfileStore:GetProfile(profileName)
    local capturedModules = profile and profile.Current
    if type(capturedModules) == "string" then
        return Codec:Decode(capturedModules)
    end
    return capturedModules
end

function CurrentStore:GetMetadata(profileName)
    profileName = profileName or CharacterInfo:GetFullName()
    local profile = ProfileStore:GetProfile(profileName)
    return profile and profile.Metadata
end
