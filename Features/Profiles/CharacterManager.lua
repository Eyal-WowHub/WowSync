local _, addon = ...
local CharacterManager = addon:NewObject("CharacterManager")

local C = LibStub("Contracts-1.0")
local CharacterInfo = LibStub("CharacterInfo-1.0")

local ProfileStore = addon:GetObject("ProfileStore")

--[[
    CharacterManager — the merged roster of known characters.

    Lists every character that has a saved profile and/or a captured Current,
    and resolves a user-typed character token (name, name*, name-realm) to a
    stored profile key.
]]

-- A realm name lowercased and stripped of spaces, dashes and apostrophes, so a
-- typed shorthand ("ArgentDawn") matches a stored display realm ("Argent Dawn").
local function NormalizeRealm(realm)
    return (realm:gsub("[%s%-']", "")):lower()
end

-- Split a "Name - Realm" key on its first dash (a character name never contains
-- one). Returns the trimmed name and realm; realm is empty when no dash present.
local function SplitNameRealm(text)
    local name, realm = text:match("^(.-)%s*%-%s*(.*)$")
    if name then
        return strtrim(name), strtrim(realm)
    end
    return strtrim(text), ""
end

-- Every character that has a profile (saved history) and/or a captured Current,
-- including the logged-in one. Each entry:
--   { Key, ClassID, LastSeen, IsCurrent, HasCurrent, HasHistory }
-- Sorted with the logged-in character first, then most-recently-seen.
function CharacterManager:GetSavedCharacters()
    local currentCharKey = CharacterInfo:GetFullName()
    local characters = {}

    -- One record per character now holds both its Current and its history, so a
    -- single pass covers every character that has either.
    for key, profile in pairs(ProfileStore:GetProfiles()) do
        local capturedModules = profile.Current
        local hasCurrent = type(capturedModules) == "string"
            or (type(capturedModules) == "table" and next(capturedModules) ~= nil)
        local snapshots = profile.Snapshots
        local hasHistory = snapshots ~= nil and #snapshots > 0

        if hasCurrent or hasHistory then
            local metadata = profile.Metadata or {}
            local character = {
                Key = key,
                IsCurrent = key == currentCharKey,
                HasCurrent = hasCurrent or nil,
                HasHistory = hasHistory or nil,
                ClassID = metadata.ClassID,
                LastSeen = metadata.LastSeen,
            }

            -- Fall back to the latest snapshot's source for identity when the
            -- record carries no Current metadata (e.g. history kept, data pruned).
            if not character.ClassID and hasHistory then
                local latestSnapshot = snapshots[#snapshots]
                character.ClassID = latestSnapshot.Source and latestSnapshot.Source.ClassID
                character.LastSeen = character.LastSeen or latestSnapshot.Timestamp
            end

            tinsert(characters, character)
        end
    end

    table.sort(characters, function(left, right)
        if left.IsCurrent ~= right.IsCurrent then
            return left.IsCurrent
        end
        return (left.LastSeen or 0) > (right.LastSeen or 0)
    end)

    return characters
end

-- Resolve a user-typed character token to a stored profile key. Accepted forms:
--   "Name"          the character with that name on the current realm
--   "Name*"         that name on any other realm
--   "Name-Realm"    that name on a realm matched by (partial) realm name
-- Candidates are considered in the character-list order. Returns the matched
-- key, or nil plus a reason ("notfound"|"ambiguous") and the matching keys.
function CharacterManager:ResolveCharacterName(token)
    C:IsString(token, 2)

    local otherRealm = token:match("%*%s*$") ~= nil
    if otherRealm then
        token = (token:gsub("%*%s*$", ""))
    end

    local name, realmText = SplitNameRealm(token)
    local wantName = name:lower()
    local wantRealm = NormalizeRealm(realmText)
    local myRealm = NormalizeRealm(CharacterInfo:GetRealm())

    local matchingKeys = {}
    for _, character in ipairs(self:GetSavedCharacters()) do
        local charName, charRealm = SplitNameRealm(character.Key)
        if charName:lower() == wantName then
            local realm = NormalizeRealm(charRealm)
            local realmMatches
            if wantRealm ~= "" then
                realmMatches = realm:find(wantRealm, 1, true) == 1
            elseif otherRealm then
                realmMatches = realm ~= myRealm
            else
                realmMatches = realm == myRealm
            end
            if realmMatches then
                tinsert(matchingKeys, character.Key)
            end
        end
    end

    if #matchingKeys == 0 then
        return nil, "notfound"
    elseif #matchingKeys > 1 then
        return nil, "ambiguous", matchingKeys
    end
    return matchingKeys[1]
end
