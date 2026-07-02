local _, addon = ...
local ChangeBadge = {}
addon.ChangeBadge = ChangeBadge

local L = addon.L

--[[
    ChangeBadge — the formatter behind the UI's coloured change figure.

    Turns a counts table ({ added, changed, removed }) into +added ~changed
    -removed (dropping the removed term when it is zero), optionally prefixed
    as "Name:  <figure>". WowSync exposes this through API so companion UIs can
    render one consistent diff string everywhere.
]]

-- The coloured change figure (+added ~changed -removed), with the removed term
-- dropped when nothing is removed, and an empty string when there is no pending
-- change. When prefix is given the figure is labelled with it ("prefix:  +A ~C").
function ChangeBadge.FormatDiffString(counts, prefix)
    local added = counts and counts.added or 0
    local changed = counts and counts.changed or 0
    local removed = counts and counts.removed or 0

    local figure
    if added <= 0 and changed <= 0 and removed <= 0 then
        figure = ""
    elseif removed > 0 then
        figure = L["+A ~C -R"]:format(added, changed, removed)
    else
        figure = L["+A ~C"]:format(added, changed)
    end

    if prefix then
        return L["X: Y"]:format(prefix, figure)
    end
    return figure
end