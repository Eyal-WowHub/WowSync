local _, addon = ...
local HashSet = {}
addon.HashSet = HashSet

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
    human labels, ready for the apply preview.
]]

local Hash = addon.Hash

HashSet.__index = HashSet

-- Build a set from an entry list. keyOf(entry) -> unique key (nil entries skipped);
-- labelOf(entry) -> human label (defaults to the key).
function HashSet:From(entryList, keyOf, labelOf)
    local entries = {}

    for _, entry in ipairs(entryList or {}) do
        local key = keyOf(entry)
        if key ~= nil then
            entries[key] = {
                hash = Hash:Create(entry),
                label = labelOf and labelOf(entry) or tostring(key),
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

-- Labels of keys present in `otherSet` but not in self.
function HashSet:Added(otherSet)
    local labels = {}
    for key, setEntry in pairs(otherSet.entries) do
        if not self.entries[key] then
            tinsert(labels, setEntry.label)
        end
    end
    table.sort(labels)
    return labels
end

-- Labels of keys present in self but not in `otherSet`.
function HashSet:Removed(otherSet)
    local labels = {}
    for key, setEntry in pairs(self.entries) do
        if not otherSet.entries[key] then
            tinsert(labels, setEntry.label)
        end
    end
    table.sort(labels)
    return labels
end

-- Labels of keys present in both whose fingerprint differs.
function HashSet:Changed(otherSet)
    local labels = {}
    for key, setEntry in pairs(self.entries) do
        local otherEntry = otherSet.entries[key]
        if otherEntry and otherEntry.hash ~= setEntry.hash then
            tinsert(labels, otherEntry.label)
        end
    end
    table.sort(labels)
    return labels
end
