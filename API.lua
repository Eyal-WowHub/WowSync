local _, addon = ...
WowSync = addon:NewObject(addon:GetName())

local C = addon.Contracts
local L = addon.L

local Upgrade = addon:GetObject("Upgrade")

-- Loads the companion UI addon on demand, then fires WOWSYNC_UI_TOGGLED so the
-- UI can open or toggle its window. A pending one-time upgrade reset intercepts
-- the toggle, raising the reset prompt instead of opening the window.
local function ToggleUI()
    if Upgrade:ShowIfPending() then
        return
    end
    if not C_AddOns.IsAddOnLoaded("WowSync_UI") and not C_AddOns.LoadAddOn("WowSync_UI") then
        addon:Print(L["WowSync_UI addon not found."])
        return
    end
    WowSync:TriggerEvent("WOWSYNC_UI_TOGGLED")
end

-- The public export surface, resolved through WowSync:Import(name). A `true`
-- entry exports the whole object or table; a table of members exports a cached
-- proxy carrying only those — `member = true` forwards a method of the backing
-- addon object, `member = <function>` exposes that function directly. Only names
-- listed here can be imported.
local Exports = {
    -- Shared formatter/value tables.
    ChangeBadge = true,
    Contracts = true,

    -- Async primitive a plugin returns from Apply to defer completion until its
    -- own asynchronous work (e.g. a user prompt) settles.
    AsyncTask = true,

    -- Namespaced helper surfaces.
    Console = {
        Print = function(...) addon:Print(...) end,
        PrintLine = function(...) addon:PrintLine(...) end,
    },
    UI = {
        ToggleUI = ToggleUI,
    },

    -- Domain objects.
    ProfileManager = true,
    SnapshotManager = true,
    UndoManager = true,
    ImportManager = true,
    ExportManager = true,
    ImportedHashDictionary = true,
    CharacterManager = true,
    ModuleRegistry = true,
    Module = true,
    PluginManager = true,
    Debugger = true,
    GameWatcher = {
        Attach = true,
        Detach = true,
        HasAttachments = true,
    },
}

-- Internal objects exported only in a developer build (X-WowSync-DevMode), so the
-- WowSync_TestSuite can drive them in smoke/integration tests. That flag is
-- stripped from every release, so in a packaged build these stay unreachable and
-- the import surface is exactly the whitelist above.
if addon.DevMode then
    local devExports = {
        FrameTask = true,
        SaveTask = true,
        Debugger = true,
        Snapshot = true,
        SnapshotInfo = true,
        HashSet = true,
        Differ = true,
        Codec = true,
        ShareCodec = true,
        LiveStore = true,
        ProfileStore = true,
        ImportStore = true,
        SnapshotActionMonitor = true,
    }
    for name, spec in pairs(devExports) do
        Exports[name] = spec
    end
end

-- Built proxies, grouped by the export surface they belong to, so repeated
-- imports of a partially-exported name hand back the same proxy without colliding
-- with a like-named export in another addon's surface. Weak keys let a surface's
-- proxies fall away with the export table itself.
local proxyCaches = setmetatable({}, { __mode = "k" })

-- A proxy exposing only the whitelisted members of an export drawn from `tbl`. A
-- `true` member is forwarded to the method of that name on the backing object
-- (which stays the receiver). A function member is forwarded with the proxy
-- receiver dropped, so it is written as a plain function.
local function BuildProxy(tbl, name, members)
    local proxy = {}
    local object  -- the backing object, resolved only when a `true` member needs it
    for key, member in pairs(members) do
        if member == true then
            object = object or tbl:GetObject(name)
            local method = object[key]
            C:Ensures(type(method) == "function", "Import: '%s' has no method '%s'", name, key)
            proxy[key] = function(_, ...)
                return method(object, ...)
            end
        elseif type(member) == "function" then
            proxy[key] = function(_, ...)
                return member(...)
            end
        else
            C:Ensures(false, "Import: '%s.%s' must be true or a function", name, key)
        end
    end
    return proxy
end

-- Public value objects returned by this addon's APIs.
WowSync.Models = {
    SnapshotApplyMode = addon.SnapshotApplyMode,
}

-- Whether this is an unpackaged developer build (X-WowSync-DevMode). Exposed on
-- the public object so companion addons can gate dev-only behaviour on the same
-- flag without re-reading the metadata themselves.
WowSync.DevMode = addon.DevMode

-- Whether the pending-reset notice has been printed this session, so a burst of
-- plugin imports during a pending reset announces itself only once.
local wasImportUpgradeMessageDisplayedOnce = false

-- Resolve a name against an export surface: the whole object when fully exported
-- (`true`), or a cached proxy carrying only its whitelisted members. `tbl` is the
-- Addon-1.0 object backing the surface, so a companion addon or plugin can offer
-- its own import method over its own objects and whitelist. Only names present in
-- `exports` can be imported; anything else is a programming error.
function WowSync:ImportFrom(tbl, exports, name)
    C:IsTable(tbl, 2)
    C:IsTable(exports, 3)
    C:IsString(name, 4)

    local allowed = exports[name]
    C:Ensures(allowed ~= nil, "Import: '%s' is not an exported object", name)

    if allowed == true then
        return (tbl.GetObject and tbl:GetObject(name, true)) or tbl[name]
    end

    local cache = proxyCaches[exports]
    if not cache then
        cache = {}
        proxyCaches[exports] = cache
    end
    local proxy = cache[name]
    if not proxy then
        proxy = BuildProxy(tbl, name, allowed)
        cache[name] = proxy
    end
    return proxy
end

-- Resolve one of this addon's public objects by name, over the core export
-- surface. A pending one-time reset still hands the API out but warns once, so a
-- burst of plugin imports during a pending reset announces itself a single time.
function WowSync:Import(name)
    if Upgrade:IsPending() and not wasImportUpgradeMessageDisplayedOnce then
        addon:Warn(L["The database schema was changed and requires a one-time reset. Run /wowsync to reset it."])
        wasImportUpgradeMessageDisplayedOnce = true
    end

    return self:ImportFrom(addon, Exports, name)
end

--[[ Addon entry points ]]

function WowSync_OnAddonCompartmentClick()
    ToggleUI()
end
