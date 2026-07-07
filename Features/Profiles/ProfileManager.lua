local _, addon = ...
local ProfileManager = addon:NewObject("ProfileManager")

local C = addon.Contracts
local Snapshot = addon.Snapshot
local SnapshotInfo = addon.SnapshotInfo
local Profile = addon.Profile

local CharacterInfo = LibStub("CharacterInfo-1.0")

local LiveStore = addon:GetObject("LiveStore")
local ProfileStore = addon:GetObject("ProfileStore")

--[[
    ProfileManager — the business layer over the profile store.

    A profile is one character's record: its saved snapshot history plus the live
    snapshot (its current setup) and the metadata kept alongside them.
    ProfileManager owns the RULES — assigning a snapshot's index, pruning to the
    cap (protecting pinned entries), resolving a selector, the pin/note/delete
    mutations, and producing the character's live snapshot and full timeline. It
    accepts and returns Snapshot objects; ProfileStore underneath only stores and
    retrieves the raw records, and LiveStore holds the live setup the live
    snapshot wraps.
]]

-- One stable live-snapshot snapshotInfo per character, refreshed in place so the
-- live snapshot keeps its Snapshot identity across captures.
local cachedLiveSnapshots = {}

--[[ Profile CRUD ]]

-- The character's profile as a Profile object, or nil when none is stored.
function ProfileManager:GetProfile(profileName)
    C:IsString(profileName, 2)
    local record = ProfileStore:GetProfile(profileName)
    return record and Profile:Create(profileName, record) or nil
end

-- Every stored character profile as Profile objects.
function ProfileManager:GetProfiles()
    local profiles = {}
    for key, record in pairs(ProfileStore:GetProfiles()) do
        tinsert(profiles, Profile:Create(key, record))
    end
    return profiles
end

-- The logged-in character's profile, created if it does not exist yet.
function ProfileManager:GetCurrentProfile()
    local charKey = CharacterInfo:GetFullName()
    return Profile:Create(charKey, ProfileStore:CreateProfile(charKey))
end

function ProfileManager:DeleteProfile(profileName)
    C:IsString(profileName, 2)
    return ProfileStore:DeleteProfile(profileName)
end

-- Wipes every character record (saved snapshots, current captures and undo
-- history) while leaving user settings intact. The table is emptied in place so
-- the stores' cached references stay valid; callers are expected to reload the
-- UI afterwards so every view reinitialises from the now-empty database.
function ProfileManager:ResetDatabase()
    wipe(addon.DB.Profiles)
end

--[[ Live snapshot ]]

-- Decompress the logged-in character's Current into a plain table at login for
-- fast in-session access; SnapshotManager captures and recompresses it on logout
-- (so other characters can browse its final state).
function ProfileManager:OnInitialized()
    LiveStore:Decompress(self:GetCurrentProfile():ToStore())

    -- Modules that fail to capture are announced by the store; surface them here
    -- so a broken module is diagnosable instead of silently vanishing.
    WowSync:RegisterEvent("WOWSYNC_MODULE_CAPTURE_FAILED", function(_, _, moduleName, err)
        addon:Print(addon.L["Could not capture module 'X': Y"]:format(moduleName, err))
    end)
end

-- Re-scan the logged-in character's live setup into its Current and return the
-- refreshed live snapshot, or nil when nothing was captured.
function ProfileManager:RefreshLiveSnapshot()
    local profile = self:GetCurrentProfile()
    LiveStore:Capture(profile:ToStore())
    return self:GetLiveSnapshot(profile)
end

-- Re-scan a single module of the logged-in character's live setup; returns true
-- when captured, false when skipped. Signals listeners on a successful capture;
-- the bulk RefreshLiveSnapshot stays silent, so a listener that reacts by
-- recapturing cannot feed back into a loop.
function ProfileManager:RefreshLiveSnapshotModule(moduleName)
    C:IsString(moduleName, 2)
    local profile = self:GetCurrentProfile()
    local captured = LiveStore:CaptureModule(profile:ToStore(), moduleName)
    if captured then
        WowSync:TriggerEvent("WOWSYNC_MODULE_DATA_UPDATED")
    end
    return captured
end

-- Capture the logged-in character's live setup and compress it for storage, so
-- its final state persists on logout for other characters to browse.
function ProfileManager:StoreLiveSnapshot()
    local profile = self:GetCurrentProfile()
    LiveStore:Capture(profile:ToStore())
    LiveStore:Compress(profile:ToStore())
end

--[[ Snapshot history ]]

-- The soft cap on snapshots kept per character profile.
function ProfileManager:GetMaxSnapshots()
    return ProfileStore:GetMaxSnapshots()
end

-- Append a snapshot to its character's history: a save always appends, even when
-- nothing changed. Returns the stored Snapshot.
function ProfileManager:AddSnapshot(snapshot, note)
    Snapshot.Validate(snapshot, 2)
    return ProfileStore:AppendSnapshot(snapshot, note)
end

-- The snapshot a save would prune to stay within the cap (the oldest un-pinned
-- once the history is at/over the cap) as a Snapshot, or nil when a save would
-- evict nothing (under the cap, or every snapshot is pinned).
function ProfileManager:PendingEviction(profile)
    Profile.Validate(profile, 2)
    local snapshots = profile:Snapshots()
    if #snapshots < ProfileStore:GetMaxSnapshots() then
        return nil
    end
    for index = 1, #snapshots do
        if not snapshots[index]:IsPinned() then
            return snapshots[index]
        end
    end
    return nil
end

-- A character's live snapshot: its current setup as a live Snapshot (the
-- connected character's is live, an alt's is its last capture), or nil when
-- nothing is captured. The live snapshot carries no Index; the companion UI
-- floats it above the saved history as the always-current top of the timeline
-- (the "head"). The snapshotInfo is kept and refreshed in place so the live
-- snapshot keeps its Snapshot identity across captures.
function ProfileManager:GetLiveSnapshot(profile)
    Profile.Validate(profile, 2)
    local charKey = profile:Key()

    local capturedModules = LiveStore:Get(profile:ToStore())
    if not capturedModules or not next(capturedModules) then
        cachedLiveSnapshots[charKey] = nil
        return nil
    end

    local charMeta = profile:ToStore().Metadata
    local fresh = SnapshotInfo:CreateForLiveSnapshot(capturedModules, {
        CharacterName = charKey,
        ClassID = charMeta and charMeta.ClassID,
        LastSeen = charMeta and charMeta.LastSeen,
        Connected = profile:IsCharacterConnected(),
    })

    local liveSnapshotInfo = cachedLiveSnapshots[charKey]
    if liveSnapshotInfo then
        wipe(liveSnapshotInfo)
        for key, value in pairs(fresh) do
            liveSnapshotInfo[key] = value
        end
    else
        liveSnapshotInfo = fresh
        cachedLiveSnapshots[charKey] = liveSnapshotInfo
    end
    return Snapshot:Create(charKey, liveSnapshotInfo)
end

-- A character's full timeline as ordered Snapshot objects: the live snapshot
-- first (when anything is captured), then its saved history (pinned newest-first,
-- then un-pinned newest-first).
function ProfileManager:GetTimeline(profile)
    Profile.Validate(profile, 2)

    local timeline = {}
    local liveSnapshot = self:GetLiveSnapshot(profile)
    if liveSnapshot then
        tinsert(timeline, liveSnapshot)
    end
    for _, snapshot in ipairs(profile:GetHistory()) do
        tinsert(timeline, snapshot)
    end
    return timeline
end

-- Resolve a selector (<hash>, an unambiguous <hash-prefix>, or <hash>#<index>)
-- within a character's history. Returns a Snapshot, or nil + a reason
-- ("not-found" / "ambiguous") + a list of candidate Snapshots.
function ProfileManager:FindSnapshot(profile, selector)
    Profile.Validate(profile, 2)
    C:IsString(selector, 3)

    local snapshots = profile:Snapshots()
    local hash, wantedIndex = SnapshotInfo.ParseSelector(selector)

    if wantedIndex then
        for index = 1, #snapshots do
            local snapshot = snapshots[index]
            if snapshot:GetIndex() == wantedIndex then
                if snapshot:HashValue():sub(1, #hash) == hash then
                    return snapshot
                end
                return nil, "not-found"
            end
        end
        return nil, "not-found"
    end

    local exactMatches = {}
    for index = 1, #snapshots do
        if snapshots[index]:HashValue() == hash then
            tinsert(exactMatches, snapshots[index])
        end
    end
    if #exactMatches > 1 then
        return nil, "ambiguous", exactMatches
    elseif #exactMatches == 1 then
        return exactMatches[1]
    end

    local prefixMatch, candidates
    for index = 1, #snapshots do
        if snapshots[index]:HashValue():sub(1, #hash) == hash then
            if prefixMatch then
                candidates = candidates or { prefixMatch }
                tinsert(candidates, snapshots[index])
            else
                prefixMatch = snapshots[index]
            end
        end
    end
    if candidates then
        return nil, "ambiguous", candidates
    end
    if prefixMatch then
        return prefixMatch
    end
    return nil, "not-found"
end

--[[ Snapshot mutations (take a Snapshot) ]]

-- Pin a saved snapshot so pruning skips it.
function ProfileManager:Pin(snapshot)
    Snapshot.Validate(snapshot, 2)
    snapshot:ToStore().Pinned = true
end

-- Clear a saved snapshot's pin.
function ProfileManager:Unpin(snapshot)
    Snapshot.Validate(snapshot, 2)
    snapshot:ToStore().Pinned = false
end

-- Set the editable note on a saved snapshot.
function ProfileManager:SetNotes(snapshot, text)
    Snapshot.Validate(snapshot, 2)
    C:IsString(text, 3)
    snapshot:ToStore().Notes = text
end

-- Permanently remove a snapshot from its character's history. Returns whether it
-- was found and removed.
function ProfileManager:Remove(snapshot)
    Snapshot.Validate(snapshot, 2)
    return ProfileStore:RemoveSnapshot(snapshot)
end
