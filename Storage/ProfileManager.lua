local _, addon = ...
local ProfileManager = addon:NewObject("ProfileManager")

local CharacterInfo = LibStub("CharacterInfo-1.0")
local C = LibStub("Contracts-1.0")

local DB
local modules = {}

--[[ Module Registration ]]

function ProfileManager:RegisterModule(module)
    C:IsTable(module, 2)
    C:Ensures(type(module.GetName) == "function", "RegisterModule: 'module' must have GetName()")
    C:Ensures(type(module.Capture) == "function", "RegisterModule: 'module' must have Capture()")
    C:Ensures(type(module.Apply) == "function", "RegisterModule: 'module' must have Apply()")
    C:Ensures(type(module.CanApply) == "function", "RegisterModule: 'module' must have CanApply()")

    local name = module:GetName()
    C:Ensures(not modules[name], "RegisterModule: module '%s' is already registered", name)

    modules[name] = module
end

function ProfileManager:GetModule(name)
    return modules[name]
end

function ProfileManager:IterableModules()
    return pairs(modules)
end

--[[ DB ]]

function ProfileManager:OnInitialized()
    DB = addon.DB.global
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

    for name, module in pairs(modules) do
        local ok, data = pcall(module.Capture, module)
        if ok then
            profile.Modules[name] = data
        end
    end

    DB.Profiles[profileName] = profile
    return true
end

function ProfileManager:Apply(profileName, selectedModules)
    C:IsString(profileName, 2)

    local profile = DB.Profiles[profileName]
    C:Ensures(profile, "Apply: profile '%s' does not exist", profileName)

    local modulesToApply = selectedModules or modules

    -- Snapshot current state before applying so the user can revert
    local snapshot = {}
    for name in pairs(modulesToApply) do
        local module = modules[name]
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
        local character = CharacterInfo:GetFullName()
        DB.RevertPoints[character] = {
            ProfileName = profileName,
            Timestamp = time(),
            Modules = snapshot,
        }
    end

    -- Apply the profile
    local results = {}

    for name in pairs(modulesToApply) do
        local module = modules[name]
        local data = profile.Modules[name]

        if module and data then
            local canApply, warning = module:CanApply(profile.Meta)
            if canApply then
                local ok, err = pcall(module.Apply, module, data, profile.Meta)
                if ok then
                    results[name] = { applied = true, warning = warning }
                else
                    results[name] = { applied = false, reason = tostring(err) }
                end
            else
                results[name] = { applied = false, reason = warning }
            end
        end
    end

    return results
end

function ProfileManager:Delete(profileName)
    C:IsString(profileName, 2)

    if DB.Profiles[profileName] then
        DB.Profiles[profileName] = nil
        return true
    end

    return false
end

function ProfileManager:GetProfile(profileName)
    return DB.Profiles[profileName]
end

function ProfileManager:GetProfiles()
    return DB.Profiles
end

function ProfileManager:HasRevertPoint()
    local character = CharacterInfo:GetFullName()
    return DB.RevertPoints[character] ~= nil
end

function ProfileManager:GetRevertInfo()
    local character = CharacterInfo:GetFullName()
    local revert = DB.RevertPoints[character]
    if not revert then return nil end

    local moduleNames = {}
    for name in pairs(revert.Modules) do
        tinsert(moduleNames, name)
    end
    table.sort(moduleNames)

    return {
        ProfileName = revert.ProfileName,
        Timestamp = revert.Timestamp,
        ModuleNames = moduleNames,
    }
end

function ProfileManager:Revert()
    local character = CharacterInfo:GetFullName()
    local revert = DB.RevertPoints[character]
    if not revert then
        return nil
    end

    local results = {}

    local meta = {
        ClassID = PlayerUtil.GetClassID(),
        LastCharacter = character,
        LastUpdated = revert.Timestamp,
    }

    for name, data in pairs(revert.Modules) do
        local module = modules[name]
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
    DB.RevertPoints[character] = nil

    return results
end

function ProfileManager:Rename(oldName, newName)
    C:IsString(oldName, 2)
    C:IsString(newName, 3)
    C:Ensures(newName ~= "", "Rename: 'newName' must be a non-empty string")

    local profile = DB.Profiles[oldName]
    if not profile then
        return false
    end

    if DB.Profiles[newName] then
        return false
    end

    DB.Profiles[newName] = profile
    DB.Profiles[oldName] = nil
    return true
end
