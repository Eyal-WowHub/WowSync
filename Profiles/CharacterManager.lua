local _, addon = ...
local CharacterManager = addon:NewObject("CharacterManager")
local ProfileStore = addon:GetObject("ProfileStore")

local CharacterInfo = LibStub("CharacterInfo-1.0")
local C = LibStub("Contracts-1.0")

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
    local me = CharacterInfo:GetFullName()
    local out = {}

    -- One record per character now holds both its Current and its history, so a
    -- single pass covers every character that has either.
    for key, record in pairs(ProfileStore:GetProfiles()) do
        local current = record.Current
        local hasCurrent = type(current) == "string"
            or (type(current) == "table" and next(current) ~= nil)
        local history = record.Snapshots
        local hasHistory = history ~= nil and #history > 0

        if hasCurrent or hasHistory then
            local metadata = record.Metadata or {}
            local entry = {
                Key = key,
                IsCurrent = key == me,
                HasCurrent = hasCurrent or nil,
                HasHistory = hasHistory or nil,
                ClassID = metadata.ClassID,
                LastSeen = metadata.LastSeen,
            }

            -- Fall back to the latest snapshot's source for identity when the
            -- record carries no Current metadata (e.g. history kept, data pruned).
            if not entry.ClassID and hasHistory then
                local latest = history[#history]
                entry.ClassID = latest.Source and latest.Source.ClassID
                entry.LastSeen = entry.LastSeen or latest.Timestamp
            end

            tinsert(out, entry)
        end
    end

    table.sort(out, function(a, b)
        if a.IsCurrent ~= b.IsCurrent then
            return a.IsCurrent
        end
        return (a.LastSeen or 0) > (b.LastSeen or 0)
    end)

    return out
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

    local matches = {}
    for _, entry in ipairs(self:GetSavedCharacters()) do
        local charName, charRealm = SplitNameRealm(entry.Key)
        if charName:lower() == wantName then
            local realm = NormalizeRealm(charRealm)
            local ok
            if wantRealm ~= "" then
                ok = realm:find(wantRealm, 1, true) == 1
            elseif otherRealm then
                ok = realm ~= myRealm
            else
                ok = realm == myRealm
            end
            if ok then
                tinsert(matches, entry.Key)
            end
        end
    end

    if #matches == 0 then
        return nil, "notfound"
    elseif #matches > 1 then
        return nil, "ambiguous", matches
    end
    return matches[1]
end
