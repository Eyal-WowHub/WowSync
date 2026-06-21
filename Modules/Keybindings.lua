local _, addon = ...
local Keybindings = addon:NewObject("Keybindings")

local ProfileManager = addon:GetObject("ProfileManager")

--[[ Module API ]]

function Keybindings:Capture()
    local bindings = {}

    for i = 1, GetNumBindings() do
        -- GetBinding returns: command, category, key1, key2, ...
        local command, category, key1, key2 = GetBinding(i)
        if command and (key1 or key2) then
            bindings[command] = {
                Key1 = key1,
                Key2 = key2,
            }
        end
    end

    return bindings
end

function Keybindings:Apply(data, meta)
    -- Apply saved bindings. SetBinding overrides existing key assignments,
    -- but extra bindings not present in the profile are left intact.
    local currentSet = GetCurrentBindingSet()
    if not currentSet then
        -- Binding set isn't determinable yet; don't touch bindings.
        return
    end

    for action, keys in pairs(data) do
        if keys.Key1 then
            SetBinding(keys.Key1, action)
        end
        if keys.Key2 then
            SetBinding(keys.Key2, action)
        end
    end

    SaveBindings(currentSet)
end

function Keybindings:CanApply(meta)
    return true
end

--[[ Registration ]]

function Keybindings:OnInitialized()
    ProfileManager:RegisterModule(self)
end
