local _, addon = ...
local GameWatcher = addon:NewObject("GameWatcher")
local C = LibStub("Contracts-1.0")

--[[
    GameWatcher — keeps each character's Current a *live* mirror of the game.

    Modules declare GetWatchedEvents() (e.g. UPDATE_MACROS). When one of those
    events fires, the matching module is marked dirty and a single short debounce
    timer is (re)started; on fire, only the dirty modules are re-captured into
    Current via CurrentStore:RefreshModule. A burst of events therefore collapses
    into one recapture, and unrelated modules are never touched.

    Feedback guard: our own Apply/Undo change the game and so fire these very
    events. ProfileManager brackets those with PauseForApply/ResumeAfterApply,
    which Suspend()s this object (Addon-1.0 drops event dispatch while suspended)
    across the apply plus a short settle window, so we never re-mirror our own
    writes. WoW delivers events between frames, never mid-function, so the
    synchronous apply loop itself cannot be interrupted by a recapture.

    Combat: a module may decline capture in combat (ShouldCapture); such modules
    stay dirty and are flushed again on PLAYER_REGEN_ENABLED.

    Lazy by default: tracking runs only while a consumer is attached (e.g. the
    open companion UI); toggled with `/ws watcher off|lazy` (DB.Settings.Watcher).
]]

local DEBOUNCE_SECONDS = 0.5
local SETTLE_SECONDS = 0.2

local registry
local currentStore

-- eventName -> array of module names that care about it.
local watchedModules = {}
-- moduleName -> true: modules whose live state changed and await recapture.
local dirty = {}

local started = false
local flushToken = 0
local resumeToken = 0

-- id -> true: consumers that want live tracking (e.g. the open companion UI).
local attachments = {}

--[[ Capture flush (debounced) ]]

-- Re-capture every dirty module into Current. A module that declines capture
-- (e.g. combat lockdown) stays dirty so PLAYER_REGEN_ENABLED can flush it later.
local function Flush()
    for name in pairs(dirty) do
        if currentStore:RefreshModule(name) then
            dirty[name] = nil
        end
    end
end

local function ScheduleFlush()
    flushToken = flushToken + 1
    local mine = flushToken
    C_Timer.After(DEBOUNCE_SECONDS, function()
        if mine == flushToken then
            Flush()
        end
    end)
end

local function OnWatchedEvent(_, event)
    local names = watchedModules[event]
    if not names then
        return
    end

    for _, name in ipairs(names) do
        dirty[name] = true
    end
    ScheduleFlush()
end

-- Combat ended: any modules deferred during combat can be captured now.
local function OnCombatEnd()
    if next(dirty) then
        Flush()
    end
end

--[[ Lifecycle ]]

function GameWatcher:OnInitialized()
    registry = addon:GetObject("ModuleRegistry")
    currentStore = addon:GetObject("CurrentStore")

    self:ResolveActivationMode()
end

-- Begin live tracking: register every module's watch events (each once) and the
-- combat-end retry. Safe to call repeatedly.
function GameWatcher:Start()
    if started then
        return
    end
    started = true

    -- Catch up on everything that changed while inactive, so the mirror is
    -- correct before incremental events take over.
    currentStore:Refresh()

    wipe(watchedModules)
    for name, module in registry:Iterate() do
        if module.GetWatchedEvents then
            for _, event in ipairs(module:GetWatchedEvents()) do
                local names = watchedModules[event]
                if not names then
                    names = {}
                    watchedModules[event] = names
                    self:RegisterEvent(event, OnWatchedEvent)
                end
                tinsert(names, name)
            end
        end
    end

    self:RegisterEvent("PLAYER_REGEN_ENABLED", OnCombatEnd)
end

-- Stop live tracking: drop all watch registrations and any pending recapture.
function GameWatcher:Stop()
    if not started then
        return
    end
    started = false

    for event in pairs(watchedModules) do
        self:UnregisterEvent(event)
    end
    wipe(watchedModules)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")

    flushToken = flushToken + 1 -- cancel any pending flush
    wipe(dirty)
end

--[[ Mode & attachments ]]

-- The persisted tracking mode: "lazy" (track only while a consumer is attached)
-- or "off". Any unrecognised stored value resolves to the lazy default.
function GameWatcher:GetMode()
    return addon.DB.Settings.Watcher == "off" and "off" or "lazy"
end

-- Persist the tracking mode and converge live tracking to match it.
function GameWatcher:SetMode(mode)
    addon.DB.Settings.Watcher = mode == "off" and "off" or "lazy"
    self:ResolveActivationMode()
end

-- Register interest in live tracking under an id. Ids are deduplicated, so
-- attaching the same id twice still counts as one.
function GameWatcher:Attach(id)
    C:IsString(id, 2)
    attachments[id] = true
    self:ResolveActivationMode()
end

-- Drop an attachment's interest. Live tracking stops once the last one leaves.
function GameWatcher:Detach(id)
    C:IsString(id, 2)
    attachments[id] = nil
    self:ResolveActivationMode()
end

-- True while at least one consumer is attached.
function GameWatcher:HasAttachments()
    return next(attachments) ~= nil
end

-- Start or stop live tracking to match the current mode and attachments: lazy
-- tracks only while attached; off never tracks.
function GameWatcher:ResolveActivationMode()
    if self:GetMode() == "lazy" and self:HasAttachments() then
        self:Start()
    else
        self:Stop()
    end
end

--[[ Feedback guard (called by ProfileManager around Apply/Undo) ]]

-- Suspend live tracking for the duration of an apply so our own writes are not
-- mirrored back as if the player had made them.
function GameWatcher:PauseForApply()
    resumeToken = resumeToken + 1 -- cancel any pending resume
    self:Suspend()
end

-- Resume after a short settle window, long enough for the apply's own events
-- (which WoW delivers on the following frame) to pass unheeded.
function GameWatcher:ResumeAfterApply()
    resumeToken = resumeToken + 1
    local mine = resumeToken
    C_Timer.After(SETTLE_SECONDS, function()
        if mine == resumeToken then
            self:Resume()
        end
    end)
end
