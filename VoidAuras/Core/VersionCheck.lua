-- =============================================================================
-- Core/VersionCheck.lua
-- Peer-to-peer version broadcast via addon messages.
--
-- On login, broadcasts VA.version to guild + party/raid.
-- When a player running a newer version is detected, notifies the local
-- player once per session.
-- =============================================================================

local _, VA = ...

local VersionCheck = VA:Register("VersionCheck", {})

local PREFIX = "VoidAuras"
local _notified = false  -- only nag once per session

-- ---------------------------------------------------------------------------
-- Compare two "major.minor.patch" strings.
-- Returns true if `received` is strictly newer than `current`.
-- ---------------------------------------------------------------------------
local function IsNewer(current, received)
    local function parts(s)
        local a, b, c = s:match("^(%d+)%.(%d+)%.(%d+)$")
        return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
    end
    local ca, cb, cc = parts(current)
    local ra, rb, rc = parts(received)
    if ra ~= ca then return ra > ca end
    if rb ~= cb then return rb > cb end
    return rc > cc
end

-- ---------------------------------------------------------------------------
-- Send our version to whichever channels make sense right now.
-- ---------------------------------------------------------------------------
local function BroadcastVersion()
    local msg = "VERSION:" .. VA.version
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "PARTY")
    end
    if IsInGuild() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD")
    end
end

-- ---------------------------------------------------------------------------
-- React to incoming addon messages.
-- CHAT_MSG_ADDON args: prefix, message, distribution, sender
-- ---------------------------------------------------------------------------
local function OnAddonMessage(_, prefix, msg, _, sender)
    if prefix ~= PREFIX then return end

    local ver = msg:match("^VERSION:(.+)$")
    if not ver then return end

    -- Ignore our own broadcasts (sender may be "Name" or "Name-Realm")
    local myName = UnitName("player") or ""
    local senderBase = sender:match("^([^%-]+)") or sender
    if senderBase == myName then return end

    if not _notified and IsNewer(VA.version, ver) then
        _notified = true
        VA:Print(string.format(
            "A newer version |cffffd700%s|r is available (you have %s). "
            .. "|cff00ccff%s|r has the newer version.",
            ver, VA.version, senderBase
        ))
    end
end

-- ---------------------------------------------------------------------------
-- Module init
-- ---------------------------------------------------------------------------
local _wasInGroup = false

local function OnRosterUpdate()
    local inGroup = IsInGroup() or IsInRaid()
    if inGroup and not _wasInGroup then
        BroadcastVersion()
    end
    _wasInGroup = inGroup
end

function VersionCheck:Init()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    VA.Events:WowOn("CHAT_MSG_ADDON",       OnAddonMessage, "VersionCheck")
    VA.Events:WowOn("GROUP_ROSTER_UPDATE",  OnRosterUpdate, "VersionCheck_Roster")
    _wasInGroup = IsInGroup() or IsInRaid()
    BroadcastVersion()
end
