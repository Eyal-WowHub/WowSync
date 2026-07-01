local _, addon = ...
local ImportedHashDictionary = addon:NewObject("ImportedHashDictionary")

local ImportStore = addon:GetObject("ImportStore")

--[[
    ImportedHashDictionary — cross-container hash ownership for imported snapshots.

    The same captured setup can be imported into several containers. For each
    hash present anywhere in the imports, this resolves the single owning
    container: the one holding the earliest-imported copy. It lets the UI flag
    later copies as repeats of an original while leaving the first-added copy
    unmarked, resolving every row's owner from one scan instead of per row.
]]

-- Map of hash -> owning container for every hash present across all imports, in
-- a single pass. The owner is the container holding the earliest-imported copy
-- (by ImportedAt; ties broken by the older container, then its id for
-- determinism). Each entry is { ID = importID, Name = containerName }.
function ImportedHashDictionary:GetHashOwners()
    local owners = {}
    for importID, record in pairs(ImportStore:GetImports()) do
        local created = record.Created or 0
        for index = 1, #record.Snapshots do
            local hash = record.Snapshots[index].Hash
            if hash then
                local added = record.Snapshots[index].ImportedAt or 0
                local best = owners[hash]
                if not best
                    or added < best.Added
                    or (added == best.Added and created < best.Created)
                    or (added == best.Added and created == best.Created and importID < best.ID) then
                    owners[hash] = { ID = importID, Name = record.Name, Added = added, Created = created }
                end
            end
        end
    end
    return owners
end
