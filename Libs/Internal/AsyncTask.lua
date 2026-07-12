local _, addon = ...

--[[
    AsyncTask — a single-shot completion handle (a minimal promise/future).

    Represents a piece of work that finishes later. The producer settles it
    exactly once -- AsyncTask:Resolve() on success, AsyncTask:Reject(reason) on
    failure -- and consumers register AsyncTask:OnSettled(callback), which runs
    when it settles or immediately if it already has. It carries only the success
    flag and an optional failure reason: enough to gate work on "is it done, and
    did it succeed."

    This is deliberately not a promise library: no chaining, no scheduler, and no
    internal use of frames or coroutines. A producer drives it to settlement from
    wherever its own completion is known -- an event handler, a timer, or straight
    away. AsyncTask:WhenAll gathers several into one for "done when all are done."
]]

local AsyncTask = {}
addon.AsyncTask = AsyncTask
AsyncTask.__index = AsyncTask

-- A new, pending task.
function AsyncTask:New()
    return setmetatable({ settled = false, succeeded = nil, reason = nil, callbacks = {} }, self)
end

-- Create a task and hand a body the means to settle it: body(resolve, reject).
-- The body kicks off its asynchronous work and captures resolve/reject to call
-- when it finishes -- so a producer holds only the settle capability, never the
-- task itself. Returns the task. A body that errors while starting rejects the
-- task, so a failed start never leaves it pending.
function AsyncTask:Run(body)
    local task = self:New()
    local ok, err = pcall(body,
        function() task:Resolve() end,
        function(reason) task:Reject(reason) end)
    if not ok then
        task:Reject(err)
    end
    return task
end

-- Settle a task and run its callbacks exactly once; later settles are ignored.
local function Settle(task, succeeded, reason)
    if task.settled then return end
    task.settled = true
    task.succeeded = succeeded
    task.reason = reason

    local callbacks = task.callbacks
    task.callbacks = nil
    for _, callback in ipairs(callbacks) do
        callback(succeeded, reason)
    end
end

-- Settle as successful.
function AsyncTask:Resolve()
    Settle(self, true, nil)
end

-- Settle as failed, carrying an optional reason.
function AsyncTask:Reject(reason)
    Settle(self, false, reason)
end

-- True once the task has settled (resolved or rejected).
function AsyncTask:IsSettled()
    return self.settled
end

-- Register a completion callback, called with (succeeded, reason). Fires now when
-- the task has already settled, so a caller can never miss a finished task.
function AsyncTask:OnSettled(callback)
    if self.settled then
        callback(self.succeeded, self.reason)
    else
        tinsert(self.callbacks, callback)
    end
    return self
end

-- A task that is already resolved, for the common "nothing ran asynchronously"
-- path so callers can treat the sync and async cases uniformly.
function AsyncTask:Resolved()
    local task = self:New()
    task:Resolve()
    return task
end

-- One task that settles once every given task has: resolved when all resolved,
-- rejected with the first failure otherwise. An empty list resolves immediately.
function AsyncTask:WhenAll(tasks)
    local combined = self:New()
    local remaining = #tasks
    if remaining == 0 then
        combined:Resolve()
        return combined
    end

    local firstReason
    local anyFailed = false
    for _, task in ipairs(tasks) do
        task:OnSettled(function(succeeded, reason)
            if not succeeded and not anyFailed then
                anyFailed = true
                firstReason = reason
            end
            remaining = remaining - 1
            if remaining == 0 then
                if anyFailed then
                    combined:Reject(firstReason)
                else
                    combined:Resolve()
                end
            end
        end)
    end
    return combined
end
