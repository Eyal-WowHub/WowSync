local _, addon = ...
local HashSet = {}
addon.HashSet = HashSet
HashSet.__index = HashSet

local Hash = addon.Hash

--[[
    HashSet — a key-addressed set of entries with content fingerprints.

    Each module's collection (macros, keybindings, chat tabs, enabled addons)
    is a list of entries identified by some key. A HashSet turns such a list
    into a { key -> { hash, label } } map so two captures can be compared with
    plain set operations:

        local current  = HashSet:From(currentList, keyOf, labelOf)
        local snapshot = HashSet:From(snapshotList, keyOf, labelOf)

        current:Added(snapshot)    -- in snapshot, not in current
        current:Removed(snapshot)  -- in current, not in snapshot
        current:Changed(snapshot)  -- in both, different fingerprint

    The fingerprint comes from Core/Hash, so "changed" is detected without
    knowing an entry's internal shape. Each operation returns a sorted list of
    preview entries -- a human label plus an optional icon texture -- ready for
    the apply preview.
]]

-- Order preview entries by their human label.
local function SortByLabel(a, b)
    return a.label < b.label
end

-- A preview entry handed to consumers: the human label plus an optional icon
-- and an optional one-line description.
local function PreviewEntry(setEntry)
    return { label = setEntry.label, icon = setEntry.icon, description = setEntry.description }
end

-- Build a set from an entry list. keyOf(entry) -> unique key (nil entries skipped);
-- labelOf(entry) -> human label (defaults to the key); iconOf(entry) -> optional
-- icon texture, or nil when the entry has none; descriptionOf(entry) -> optional
-- one-line description shown beneath the label, or nil when the entry has none.
function HashSet:From(entryList, keyOf, labelOf, iconOf, descriptionOf)
    local entries = {}

    for _, entry in ipairs(entryList or {}) do
        local key = keyOf(entry)
        if key ~= nil then
            entries[key] = {
                hash = Hash:Create(entry),
                label = labelOf and labelOf(entry) or tostring(key),
                icon = iconOf and iconOf(entry) or nil,
                description = descriptionOf and descriptionOf(entry) or nil,
            }
        end
    end

    return setmetatable({ entries = entries }, self)
end

function HashSet:Has(key)
    return self.entries[key] ~= nil
end

function HashSet:Label(key)
    local setEntry = self.entries[key]
    return setEntry and setEntry.label
end

-- Entries present in `otherSet` but not in self.
function HashSet:Added(otherSet)
    local entries = {}
    for key, setEntry in pairs(otherSet.entries) do
        if not self.entries[key] then
            tinsert(entries, PreviewEntry(setEntry))
        end
    end
    table.sort(entries, SortByLabel)
    return entries
end

-- Entries present in self but not in `otherSet`.
function HashSet:Removed(otherSet)
    local entries = {}
    for key, setEntry in pairs(self.entries) do
        if not otherSet.entries[key] then
            tinsert(entries, PreviewEntry(setEntry))
        end
    end
    table.sort(entries, SortByLabel)
    return entries
end

-- Entries present in both whose fingerprint differs; the entry reflects the
-- snapshot side (what the entry would become).
function HashSet:Changed(otherSet)
    local entries = {}
    for key, setEntry in pairs(self.entries) do
        local otherEntry = otherSet.entries[key]
        if otherEntry and otherEntry.hash ~= setEntry.hash then
            tinsert(entries, PreviewEntry(otherEntry))
        end
    end
    table.sort(entries, SortByLabel)
    return entries
end
