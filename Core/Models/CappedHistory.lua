local _, addon = ...
local CappedHistory = {}
addon.CappedHistory = CappedHistory

--[[
    CappedHistory — a bounded, append-only view over a plain array.

    Both the per-character undo stack and a profile's snapshot list are plain
    arrays kept near a soft cap: append to the end, then evict the oldest
    entries once the count exceeds the limit. CappedHistory centralizes that
    "push and trim" rule.

    It deliberately never stores itself: it wraps the live (persisted) array by
    reference, mutates it in place, and is thrown away. That keeps saved
    variables as plain tables — WoW strips metatables on reload, so a persisted
    wrapper would lose its methods.

        CappedHistory:Wrap(stack, {
            max = function() return Settings.MaxUndo end,
        }):Push(snapshot)

    Options:
      max          a number, or a function returning the cap (re-read on push).
      isProtected  optional predicate; protected entries are never evicted, so
                   the count can exceed max (a soft cap).
]]

CappedHistory.__index = CappedHistory

function CappedHistory:Wrap(list, options)
    options = options or {}
    return setmetatable({
        list = list,
        max = options.max,
        isProtected = options.isProtected,
    }, self)
end

local function CapOf(self)
    local max = self.max
    if type(max) == "function" then
        return max()
    end
    return max
end

-- Append an entry, then evict the oldest non-protected entries past the cap.
function CappedHistory:Push(entry)
    local list = self.list
    tinsert(list, entry)

    local max = CapOf(self)
    if max then
        local index = 1
        while #list > max and index <= #list do
            if self.isProtected and self.isProtected(list[index]) then
                index = index + 1
            else
                tremove(list, index)
            end
        end
    end

    return entry
end

function CappedHistory:Peek()
    return self.list[#self.list]
end

function CappedHistory:Pop()
    return tremove(self.list)
end

function CappedHistory:Count()
    return #self.list
end

function CappedHistory:Items()
    return self.list
end
