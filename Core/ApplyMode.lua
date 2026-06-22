local _, addon = ...

--[[
    ApplyMode — the set of apply strategies a module supports.

    A flags enum (bitmask) so a module can advertise any combination:

        Merge   — apply adds and updates entries, never removes (SAFE).
        Replace — apply makes the target exactly match the snapshot, removing
                  entries the snapshot does not contain (DESTRUCTIVE).
        All     — both Merge and Replace are offered (Merge + Replace).
        None    — the module cannot be applied (capture/diff only).

    Each module declares its support via a Config table, e.g.

        Macros.Config = { ApplyMode = ApplyMode.All }       -- collection module
        ActionBars.Config = { ApplyMode = ApplyMode.Merge } -- indexed module

    Consumers (apply UI, orchestrator) test support with ApplyMode.Has:

        ApplyMode.Has(module.Config.ApplyMode, ApplyMode.Replace)
]]

local ApplyMode = {
    None = 0,
    Merge = 1,
    Replace = 2,
}

ApplyMode.All = bit.bor(ApplyMode.Merge, ApplyMode.Replace)

addon.ApplyMode = ApplyMode

-- True if `modes` includes the single `mode` flag (Merge or Replace).
function ApplyMode.Has(modes, mode)
    return bit.band(modes or ApplyMode.None, mode) == mode
end
