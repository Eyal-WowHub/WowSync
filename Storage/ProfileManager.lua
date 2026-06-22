local _, addon = ...
local ProfileManager = addon:NewObject("ProfileManager")

local CharacterInfo = LibStub("CharacterInfo-1.0")
local C = LibStub("Contracts-1.0")

local registry
local store
local revert

function ProfileManager:OnInitialized()
    registry = addon:GetObject("ModuleRegistry")
    store = addon:GetObject("ProfileStore")
    revert = addon:GetObject("RevertManager")
end

--[[ Module Registration ]]

function ProfileManager:RegisterModule(module)
    registry:Register(module)
end

function ProfileManager:GetModule(name)
    return registry:Get(name)
end

function ProfileManager:IterableModules()
    return registry:Iterate()
end

--[[ Profile CRUD ]]

function ProfileManager:Save(profileName)
    C:IsString(profileName, 2)
    C:Ensures(profileName ~= "", "Save: 'profileName' must be a non-empty string")

    local profile = {
        Meta = {
            ClassID = PlayerUtil.GetClassID(),
            LastCharacter = CharacterInfo:GetFullName(),
            LastUpdated = time(),
        },
        Modules = {},
    }

    for name, module in registry:Iterate() do
        local ok, data = pcall(module.Capture, module)
        if ok then
            profile.Modules[name] = data
        end
    end

    store:Set(profileName, profile)
    return true
end

function ProfileManager:Apply(profileName, selectedModules)
    C:IsString(profileName, 2)

    local profile = store:Get(profileName)
    C:Ensures(profile, "Apply: profile '%s' does not exist", profileName)

    local names = {}
    if selectedModules then
        for name in pairs(selectedModules) do
            names[name] = true
        end
    else
        for name in registry:Iterate() do
            names[name] = true
        end
    end

    -- Snapshot current state before applying so the user can revert
    local snapshot = {}
    for name in pairs(names) do
        local module = registry:Get(name)
        local data = profile.Modules[name]
        if module and data then
            local canApply = module:CanApply(profile.Meta)
            if canApply then
                local ok, captured = pcall(module.Capture, module)
                if ok then
                    snapshot[name] = captured
                end
            end
        end
    end

    if next(snapshot) then
        revert:Set(CharacterInfo:GetFullName(), {
            ProfileName = profileName,
            Timestamp = time(),
            Modules = snapshot,
        })
    end

    -- Apply the profile
    local results = {}

    for name in pairs(names) do
        local module = registry:Get(name)
        local data = profile.Modules[name]

        if module and data then
            local canApply, warning = module:CanApply(profile.Meta)
            if not canApply then
                results[name] = { applied = false, reason = warning }
            elseif not snapshot[name] then
                -- Refuse to apply a module we could not back up, so the
                -- revert point always restores everything that changed.
                results[name] = { applied = false, reason = addon.L["Could not back up current state"] }
            else
                local ok, err = pcall(module.Apply, module, data, profile.Meta)
                if ok then
                    results[name] = { applied = true, warning = warning }
                else
                    results[name] = { applied = false, reason = tostring(err) }
                end
            end
        end
    end

    return results
end

function ProfileManager:Delete(profileName)
    C:IsString(profileName, 2)
    return store:Delete(profileName)
end

function ProfileManager:GetProfile(profileName)
    return store:Get(profileName)
end

function ProfileManager:GetProfiles()
    return store:GetAll()
end

--[[ Revert ]]

function ProfileManager:HasRevertPoint()
    return revert:Has(CharacterInfo:GetFullName())
end

function ProfileManager:GetRevertInfo()
    return revert:GetInfo(CharacterInfo:GetFullName())
end

function ProfileManager:Revert()
    local character = CharacterInfo:GetFullName()
    local revertPoint = revert:Get(character)
    if not revertPoint then
        return nil
    end

    local results = {}

    local meta = {
        ClassID = PlayerUtil.GetClassID(),
        LastCharacter = character,
        LastUpdated = revertPoint.Timestamp,
    }

    for name, data in pairs(revertPoint.Modules) do
        local module = registry:Get(name)
        if module then
            local ok, err = pcall(module.Apply, module, data, meta)
            if ok then
                results[name] = { applied = true }
            else
                results[name] = { applied = false, reason = tostring(err) }
            end
        end
    end

    -- Clear the revert point after reverting
    revert:Clear(character)

    return results
end

function ProfileManager:Rename(oldName, newName)
    C:IsString(oldName, 2)
    C:IsString(newName, 3)
    C:Ensures(newName ~= "", "Rename: 'newName' must be a non-empty string")
    return store:Rename(oldName, newName)
end
