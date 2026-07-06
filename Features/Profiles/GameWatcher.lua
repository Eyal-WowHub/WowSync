local _, addon = ...
local GameWatcher = addon:NewObject("GameWatcher")

local C = LibStub("Contracts-1.0")

local ModuleRegistry = addon.ModuleRegistry

local ProfileManager = addon:GetObject("ProfileManager")

--[[
    GameWatcher — keeps each character's Current a *live* mirror of the game.

    Modules declare GetWatchedEvents() (e.g. UPDATE_MACROS). When one of those
    events fires, the matching module is marked dirty and a single short debounce
    timer is (re)started; on fire, only the dirty modules are re-captured into
    Current via ProfileManager:RefreshLiveSnapshotModule. A burst of events therefore collapses
    into one recapture, and unrelated modules are never touched.

    Feedback guard: our own Apply/Undo change the game and so fire these very
    events. SnapshotManager brackets those with SuspendTracking/ResumeTracking,
    which Suspend()s this object (Addon-1.0 drops event dispatch while suspended)
    across the apply plus a short settle window, so we never re-mirror our own
    writes. WoW delivers events between frames, never mid-function, so the
    synchronous apply loop itself cannot be interrupted by a recapture.

    Save isolation: SaveTask brackets a save with SuspendFlush/ResumeFlush,
    holding off recapture flushes while it reads Current (events still mark
    modules dirty) so the setup a save captures and fingerprints cannot change
    mid-save; the held changes flush the moment the save finishes.

    Combat: a module may decline capture in combat (ShouldCapture); such modules
    stay dirty and are flushed again on PLAYER_REGEN_ENABLED.

    Lazy by default: tracking runs only while a consumer is attached (e.g. the
    open companion UI); toggled with `/ws watcher off|lazy` (DB.Settings.Watcher).
]]

local DEBOUNCE_SECONDS = 0.5
local SETTLE_SECONDS = 0.2

-- eventName -> array of module names that care about it.
local watchedModules = {}
-- moduleName -> true: modules whose live state changed and await recapture.
local dirty = {}

local watching = false
local flushGeneration = 0
local resumeGeneration = 0

-- True while a save holds Current: recapture flushes are held off so the live
-- mirror never changes the setup a save is reading; dirty modules accumulate and
-- are flushed once it clears.
local flushSuspended = false

-- id -> true: consumers that want live tracking (e.g. the open companion UI).
local attachments = {}

--[[ Capture flush (debounced) ]]

-- Re-capture every dirty module into Current. A module that declines capture
-- (e.g. combat lockdown) stays dirty so PLAYER_REGEN_ENABLED can flush it later.
local function Flush()
    if flushSuspended then
        -- A save is reading Current; leave the changes dirty and recapture them
        -- once it finishes, so nothing mutates the setup mid-save.
        return
    end
    for name in pairs(dirty) do
        if ProfileManager:RefreshLiveSnapshotModule(name) then
            dirty[name] = nil
        end
    end
end

local function ScheduleFlush()
    flushGeneration = flushGeneration + 1
    local scheduledGeneration = flushGeneration
    C_Timer.After(DEBOUNCE_SECONDS, function()
        if scheduledGeneration == flushGeneration then
            Flush()
        end
    end)
end

local function OnWatchedEvent(_, event)
    local moduleNames = watchedModules[event]
    if not moduleNames then
        return
    end

    for _, name in ipairs(moduleNames) do
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

-- Start or stop live tracking to match the current mode and attachments: lazy
-- tracks only while attached; off never tracks.
local function ResolveActivationMode()
    if GameWatcher:GetTrackingMode() == "lazy" and GameWatcher:HasAttachments() then
        GameWatcher:Watch()
    else
        GameWatcher:Unwatch()
    end
end

--[[ Lifecycle ]]

function GameWatcher:OnInitialized()
    ResolveActivationMode()
end

-- Begin live tracking: register every module's watch events (each once) and the
-- combat-end retry. Safe to call repeatedly.
function GameWatcher:Watch()
    if watching then
        return
    end
    watching = true

    -- Catch up on everything that changed while inactive, so the mirror is
    -- correct before incremental events take over.
    ProfileManager:RefreshLiveSnapshot()

    wipe(watchedModules)
    for name, module in ModuleRegistry:Iterate() do
        if module.GetWatchedEvents then
            for _, event in ipairs(module:GetWatchedEvents()) do
                local moduleNames = watchedModules[event]
                if not moduleNames then
                    moduleNames = {}
                    watchedModules[event] = moduleNames
                    self:RegisterEvent(event, OnWatchedEvent)
                end
                tinsert(moduleNames, name)
            end
        end
    end

    self:RegisterEvent("PLAYER_REGEN_ENABLED", OnCombatEnd)
end

-- Stop live tracking: drop all watch registrations and any pending recapture.
function GameWatcher:Unwatch()
    if not watching then
        return
    end
    watching = false

    for event in pairs(watchedModules) do
        self:UnregisterEvent(event)
    end
    wipe(watchedModules)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")

    flushGeneration = flushGeneration + 1 -- cancel any pending flush
    wipe(dirty)
end

--[[ Mode & attachments ]]

-- The persisted tracking mode: "lazy" (track only while a consumer is attached)
-- or "off". Any unrecognised stored value resolves to the lazy default.
function GameWatcher:GetTrackingMode()
    return addon.DB.Settings.Watcher == "off" and "off" or "lazy"
end

-- Persist the tracking mode and converge live tracking to match it.
function GameWatcher:SetTrackingMode(mode)
    addon.DB.Settings.Watcher = mode == "off" and "off" or "lazy"
    ResolveActivationMode()
end

-- Register interest in live tracking under an id. Ids are deduplicated, so
-- attaching the same id twice still counts as one.
function GameWatcher:Attach(consumerId)
    C:IsString(consumerId, 2)
    attachments[consumerId] = true
    ResolveActivationMode()
end

-- Drop an attachment's interest. Live tracking stops once the last one leaves.
function GameWatcher:Detach(consumerId)
    C:IsString(consumerId, 2)
    attachments[consumerId] = nil
    ResolveActivationMode()
end

-- True while at least one consumer is attached.
function GameWatcher:HasAttachments()
    return next(attachments) ~= nil
end

--[[ Recapture guards: hold the live mirror still while we change the game
     ourselves (apply/undo), or while a save reads Current. ]]

-- Suspend live tracking for the duration of an apply so our own writes are not
-- mirrored back as if the player had made them.
function GameWatcher:SuspendTracking()
    resumeGeneration = resumeGeneration + 1 -- cancel any pending resume
    self:Suspend()
end

-- Resume after a short settle window, long enough for the apply's own events
-- (which WoW delivers on the following frame) to pass unheeded.
function GameWatcher:ResumeTracking()
    resumeGeneration = resumeGeneration + 1
    local scheduledGeneration = resumeGeneration
    C_Timer.After(SETTLE_SECONDS, function()
        if scheduledGeneration == resumeGeneration then
            self:Resume()
        end
    end)
end

-- Hold off recapture flushes while a save reads Current, so the setup it
-- captures and fingerprints cannot change underneath it. Events still mark
-- modules dirty for the matching ResumeFlush to flush.
function GameWatcher:SuspendFlush()
    flushSuspended = true
end

-- Resume recapture once a save is done and flush anything that changed while it
-- ran, so the live mirror catches up immediately rather than on the next event.
function GameWatcher:ResumeFlush()
    flushSuspended = false
    if next(dirty) then
        Flush()
    end
end
