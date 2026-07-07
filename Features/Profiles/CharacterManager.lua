local _, addon = ...
local CharacterManager = addon:NewObject("CharacterManager")

local C = addon.Contracts

local CharacterInfo = LibStub("CharacterInfo-1.0")

local ProfileManager = addon:GetObject("ProfileManager")

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

-- Every character that has a profile (saved history) and/or a captured live
-- snapshot, including the logged-in one. Each entry:
--   { Key, ClassID, LastSeen, IsCharacterConnected, HasCurrent, HasHistory }
-- Sorted with the logged-in character first, then most-recently-seen.
function CharacterManager:GetSavedCharacters()
    local characters = {}

    for _, profile in ipairs(ProfileManager:GetProfiles()) do
        if not profile:IsEmpty() then
            tinsert(characters, {
                Key = profile:Key(),
                IsCharacterConnected = profile:IsCharacterConnected(),
                HasCurrent = profile:HasLiveSnapshot() or nil,
                HasHistory = profile:HasHistory() or nil,
                ClassID = profile:GetClassID(),
                LastSeen = profile:GetLastSeenTime(),
            })
        end
    end

    table.sort(characters, function(left, right)
        if left.IsCharacterConnected ~= right.IsCharacterConnected then
            return left.IsCharacterConnected
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
