local _, addon = ...
local LiveStore = addon:NewObject("LiveStore")

local Codec = addon.Codec
local ModuleRegistry = addon.ModuleRegistry

--[[
    LiveStore — captures and (de)compresses a character's live setup.

    The live setup is the record's "Current" slice: the most recently captured
    live state for a character. LiveStore is a stateless transformer over a
    record it is handed by ProfileManager — it never looks records up itself.

    Only the logged-in character can be captured (the game only exposes live
    state for whoever is online). Every character's Current is stored COMPRESSED
    except the logged-in one, whose Current is decompressed into a plain table at
    login for fast in-session access and recompressed on logout.
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

-- Decompress a record's Current into a plain table for fast in-session access.
function LiveStore:Decompress(profile)
    if type(profile.Current) == "string" then
        profile.Current = Codec:Decode(profile.Current) or {}
    end
end

-- Compress a record's Current for storage, so what lands on disk is the small
-- blob rather than the raw table.
function LiveStore:Compress(profile)
    if type(profile.Current) ~= "table" then
        return
    end

    local encoded = Codec:Encode(profile.Current)
    if encoded then
        profile.Current = encoded
    end
end

-- Re-capture the logged-in character's live setup into the given record's
-- Current. Returns the captured modules.
function LiveStore:Capture(profile)
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

-- Re-capture a single module into the given record's Current, leaving the other
-- modules untouched. Returns true when captured, or false when skipped (unknown
-- module, or ShouldCapture declined it, e.g. during combat).
function LiveStore:CaptureModule(profile, moduleName)
    local module = ModuleRegistry:Get(moduleName)
    if not module then
        return false
    end

    profile.Metadata.ClassID = PlayerUtil.GetClassID()
    profile.Metadata.LastSeen = time()

    local capturedData, captured = TryCaptureModule(moduleName, module)
    if not captured then
        return false
    end

    profile.Current[moduleName] = capturedData
    return true
end

-- The decompressed live setup held by the given record (a throwaway copy when
-- the record's Current is stored compressed). Nil when the record is nil or
-- holds nothing.
function LiveStore:Get(profile)
    local capturedModules = profile and profile.Current
    if type(capturedModules) == "string" then
        return Codec:Decode(capturedModules)
    end
    return capturedModules
end
