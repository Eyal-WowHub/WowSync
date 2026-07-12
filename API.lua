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

-- Loads the companion UI addon on demand, then fires WOWSYNC_UI_OPEN_SHARE_DIALOG
-- so the UI can open its share dialog; action is "import" or "export".
local function OpenShareDialog(action)
    if not C_AddOns.IsAddOnLoaded("WowSync_UI") and not C_AddOns.LoadAddOn("WowSync_UI") then
        addon:Print(L["WowSync_UI is required to import and export. Enable it in your AddOns list."])
        return
    end
    WowSync:TriggerEvent("WOWSYNC_UI_OPEN_SHARE_DIALOG", action)
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
        OpenShareDialog = OpenShareDialog,
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

-- Built proxies, keyed by name, so repeated imports of a partially-exported
-- surface hand back the same proxy. Fully-exported entries need no cache.
local proxies = {}

-- A proxy exposing only the whitelisted members of an export. A `true` member is
-- forwarded to the method of that name on the backing addon object (which stays
-- the receiver). A function member is forwarded with the proxy receiver dropped,
-- so it is written as a plain function.
local function BuildProxy(name, members)
    local proxy = {}
    local object  -- the backing addon object, resolved only when a `true` member needs it
    for key, member in pairs(members) do
        if member == true then
            object = object or addon:GetObject(name)
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

-- Whether the pending-reset notice has been printed this session, so a burst of
-- plugin imports during a pending reset announces itself only once.
local wasImportUpgradeMessageDisplayedOnce = false

-- Resolve a public object by name: the whole object when fully exported, or a
-- cached proxy carrying only its whitelisted methods. Only names in the Exports
-- whitelist can be imported; anything else is a programming error.
function WowSync:Import(name)
    -- A pending one-time reset means the stored data is from an older schema. The
    -- API is still handed out — plugins can register and wire themselves up — but
    -- warn once so the player knows the saved data is stale until they run the
    -- reset (nothing here raises the prompt; /wowsync does).
    if Upgrade:IsPending() and not wasImportUpgradeMessageDisplayedOnce then
        addon:Warn(L["The database schema was changed and requires a one-time reset. Run /wowsync to reset it."])
        wasImportUpgradeMessageDisplayedOnce = true
    end

    local allowed = Exports[name]
    C:Ensures(allowed ~= nil, "Import: '%s' is not an exported object", tostring(name))

    if allowed == true then
        return addon:GetObject(name, true) or addon[name]
    end

    local proxy = proxies[name]
    if not proxy then
        proxy = BuildProxy(name, allowed)
        proxies[name] = proxy
    end
    return proxy
end

--[[ Addon entry points ]]

function WowSync_OnAddonCompartmentClick()
    ToggleUI()
end
