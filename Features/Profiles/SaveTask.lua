local _, addon = ...
local SaveTask = addon:NewObject("SaveTask")

local FrameTask = addon.FrameTask

--[[
    SaveTask — runs a save body across frames without hitching the game.

    The body is sliced across frames so its capture and fingerprint never hitch a
    single frame, bracketed by WOWSYNC_SNAPSHOT_SAVE_STARTED/FINISHED. The
    live-mirror watcher listens for those and holds off its recapture flushes so
    the setup cannot change mid-save. At most one save runs at a time; a request
    made while one is in flight is rejected with "busy". A body that crashes is
    reported as "error".
]]

-- The most time a save spends in any single frame before yielding, kept low
-- enough that capturing and fingerprinting never produce a visible hitch.
local FRAME_BUDGET_MS = 6

-- The across-frames runner for the in-flight save.
local task = FrameTask.New(FRAME_BUDGET_MS)

-- True while a save is in flight.
function SaveTask:IsRunning()
    return task:IsRunning()
end

-- Run a save body across frames, bracketed by WOWSYNC_SNAPSHOT_SAVE_STARTED/FINISHED. The
-- body returns the stored snapshot, or nil plus a reason; a body that crashes is
-- reported as "error" (its message already surfaced through the game's error
-- handler). The result is forwarded to the finish event and the optional
-- onComplete, which always runs exactly once. A request made while a save is
-- already in flight is rejected with "busy". The live mirror's recapture is held
-- off for the duration so it cannot change Current mid-save.
function SaveTask:Run(saveBody, onComplete)
    if task:IsRunning() then
        if onComplete then
            onComplete(nil, "busy")
        end
        return
    end

    WowSync:TriggerEvent("WOWSYNC_SNAPSHOT_SAVE_STARTED")

    task:Start(saveBody, function(saveSucceeded, storedSnapshot, reason)
        -- A crash surfaces as (false, message); map it to the "error" reason. A
        -- successful body may still decline with (true, nil, reason).
        if not saveSucceeded then
            storedSnapshot, reason = nil, "error"
        end
        WowSync:TriggerEvent("WOWSYNC_SNAPSHOT_SAVE_FINISHED", storedSnapshot, reason)
        if onComplete then
            onComplete(storedSnapshot, reason)
        end
    end)
end

-- Finish any in-flight save now, running its remaining steps synchronously. A
-- no-op when nothing is running.
function SaveTask:Drain()
    if task:IsRunning() then
        task:Drain()
    end
end
