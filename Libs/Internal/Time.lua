local _, addon = ...
local Time = {}
addon.Time = Time

--[[
    Time — the timestamp concept.

    Centralizes "now" and the single human-readable subject format so every
    place that records or displays a moment uses the same representation.
]]

-- The one subject format, e.g. "22 Jun 2026 16:47".
local SUBJECT_FORMAT = "%d %b %Y %H:%M"

-- Current epoch time, in seconds.
function Time:Now()
    return time()
end

-- Format a timestamp into its display subject (empty string when absent).
function Time:ToShortDisplay(timestamp)
    if not timestamp then
        return ""
    end
    return date(SUBJECT_FORMAT, timestamp)
end
