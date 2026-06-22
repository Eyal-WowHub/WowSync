local _, addon = ...

--[[
    SnapshotApplyMode — the set of apply strategies a module supports.

    A flags enum (bitmask) so a module can advertise any combination:

        Merge   — apply adds and updates entries, never removes (SAFE).
        Exact   — apply makes the target exactly match the snapshot, removing
                  entries the snapshot does not contain (DESTRUCTIVE).
        All     — both Merge and Exact are offered (Merge + Exact).
        None    — the module cannot be applied (capture/diff only).

    Each module declares its support via a Config table, e.g.

        Macros.Config = { SnapshotApplyMode = SnapshotApplyMode.All }       -- collection module
        ActionBars.Config = { SnapshotApplyMode = SnapshotApplyMode.Merge } -- indexed module

    Consumers (apply UI, orchestrator) test support with the predicates:

        SnapshotApplyMode.CanExact(module.Config.SnapshotApplyMode)
        SnapshotApplyMode.CanMerge(module.Config.SnapshotApplyMode)
]]

local SnapshotApplyMode = {
    None = 0,
    Merge = 1,
    Exact = 2,
}

SnapshotApplyMode.All = bit.bor(SnapshotApplyMode.Merge, SnapshotApplyMode.Exact)

addon.SnapshotApplyMode = SnapshotApplyMode

-- True if `modes` includes the single `flag`.
local function Has(modes, flag)
    return bit.band(modes or SnapshotApplyMode.None, flag) == flag
end

-- True when `modes` offers Merge (non-destructive add/update).
function SnapshotApplyMode.CanMerge(modes)
    return Has(modes, SnapshotApplyMode.Merge)
end

-- True when `modes` offers Exact (destructive: removes entries the snapshot omits).
function SnapshotApplyMode.CanExact(modes)
    return Has(modes, SnapshotApplyMode.Exact)
end
