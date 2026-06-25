local _, addon = ...

--[[
    FrameTask — runs a body across frames so a long job never hitches one.

    The body is run as a coroutine that cooperatively yields. Each frame the task
    resumes it (driven by a hidden frame's OnUpdate) for up to a per-frame time
    budget, stopping before a step it predicts won't fit, so a frame overruns the
    budget by at most one step; the body's own yield granularity therefore bounds
    how long a frame can run. When the body returns, onComplete(true, ...) receives
    its return values; when it errors, the message is surfaced through the game's
    error handler and onComplete(false, message) runs instead. onComplete always
    runs exactly once.

    A caller that needs the result before the next frame calls Drain(), which runs
    the remaining steps to completion synchronously, ignoring the budget.
]]

local FrameTask = {}
addon.FrameTask = FrameTask

local Task = {}
Task.__index = Task

-- A runner that spends at most budgetMs in any single frame before yielding the
-- frame back to the game.
function FrameTask.New(budgetMs)
    return setmetatable({
        budgetMs = budgetMs,
        driver = CreateFrame("Frame"),
    }, Task)
end

-- True while a body is mid-flight: started and not yet completed.
function Task:IsRunning()
    return self.bodyCoroutine ~= nil
end

-- Tear down the in-flight body and deliver its outcome to onComplete exactly
-- once. Varargs are forwarded verbatim so nil returns are preserved.
local function Complete(self, succeeded, ...)
    self.driver:SetScript("OnUpdate", nil)
    self.driver:Hide()
    self.bodyCoroutine = nil

    local onComplete = self.onComplete
    self.onComplete = nil
    if onComplete then
        onComplete(succeeded, ...)
    end
end

-- Interpret one coroutine.resume of the body. Returns true once the task has
-- completed (Complete has run), false when the body merely yielded for the next
-- slice. Varargs carry the resume results so the body's returns pass untouched.
local function HandleResume(self, resumeSucceeded, ...)
    if not resumeSucceeded then
        -- The body errored; the first vararg is the message -- surface it through
        -- the game's error handler, then report a failed run, not a silent one.
        local message = ...
        geterrorhandler()(message)
        Complete(self, false, message)
        return true
    end

    if coroutine.status(self.bodyCoroutine) == "dead" then
        Complete(self, true, ...)
        return true
    end

    return false
end

-- Resume the body once.
local function Step(self)
    return HandleResume(self, coroutine.resume(self.bodyCoroutine))
end

-- Begin running body across frames. onComplete(ok, ...) runs once when the body
-- finishes (ok = true, with its return values) or errors (ok = false, with the
-- message). Calling Start while a body is already running replaces it.
function Task:Start(body, onComplete)
    self.bodyCoroutine = coroutine.create(body)
    self.onComplete = onComplete

    self.driver:SetScript("OnUpdate", function()
        local sliceStart = debugprofilestop()
        local lastStepMs = 0
        repeat
            local stepStart = debugprofilestop()
            if Step(self) then
                return
            end
            lastStepMs = debugprofilestop() - stepStart
            -- Stop before starting a step the budget likely can't absorb: a step
            -- runs to its next yield uninterrupted, so committing to one that
            -- won't fit is what pushes a frame past the budget. The first step
            -- always runs, so progress is guaranteed even when it alone overruns.
        until debugprofilestop() - sliceStart + lastStepMs >= self.budgetMs
    end)
    self.driver:Show()
end

-- Run the remaining steps to completion now, for a caller that needs the result
-- before the next frame. A no-op when nothing is running.
function Task:Drain()
    while self.bodyCoroutine do
        Step(self)
    end
end
