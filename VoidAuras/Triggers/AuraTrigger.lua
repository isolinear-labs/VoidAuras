-- =============================================================================
-- Triggers/AuraTrigger.lua
-- Tracks normal and private auras using the WoW 12.x incremental API.
--
-- Private auras arrive through the same UNIT_AURA event as normal auras but
-- have isPrivateAura = true in the AuraData. They are routed to a separate
-- private sub-state keyed by spellId (not instanceId) since Blizzard does not
-- expose duration/expiration for them.
--
-- State layout:
--   AuraTrigger.state[unit][filter][auraInstanceID] = AuraData   (normal)
--   AuraTrigger.state["player"].private[spellId]    = PrivateData
--   AuraTrigger.state["player"].privateByInstance[instanceId] = spellId
-- =============================================================================

local _, VA = ...

local AuraTrigger = VA:Register("AuraTrigger", {})
VA.AuraTrigger = AuraTrigger

AuraTrigger.state = {}

-- ---------------------------------------------------------------------------
-- State init
-- ---------------------------------------------------------------------------
local function EnsureUnit(unit)
    if not AuraTrigger.state[unit] then
        AuraTrigger.state[unit] = {
            HELPFUL          = {},
            HARMFUL          = {},
            private          = {},   -- spellId  -> PrivateData
            privateByInstance = {},  -- instanceId -> spellId (reverse lookup)
        }
    end
end

-- ---------------------------------------------------------------------------
-- Private aura helpers
-- ---------------------------------------------------------------------------
local function RecordKnownPrivate(spellId)
    if VA.db and VA.db.global and VA.db.global.knownPrivateSpells then
        if not VA.db.global.knownPrivateSpells[spellId] then
            VA.db.global.knownPrivateSpells[spellId] = true
            VA.Events:Fire(VA.E.PRIVATE_SPELL_DISCOVERED, spellId)
        end
    end
end

local function HandlePrivateAuraAdded(spellId, icon, count, sourceUnit, auraInstanceID)
    EnsureUnit("player")
    local s = AuraTrigger.state["player"]
    local rec = {
        spellId        = spellId,
        icon           = icon,
        count          = count or 0,
        sourceUnit     = sourceUnit,
        auraInstanceID = auraInstanceID,
        isPrivateAura  = true,
        name           = nil,
        duration       = nil,
        expirationTime = nil,
    }
    s.private[spellId] = rec
    if auraInstanceID then
        s.privateByInstance[auraInstanceID] = spellId
    end
    RecordKnownPrivate(spellId)
    VA.Events:Fire(VA.E.PRIVATE_AURA_ADDED, "player", rec)
end

local function HandlePrivateAuraRemoved(spellId)
    local s = AuraTrigger.state["player"]
    if not s then return end
    local rec = s.private[spellId]
    if rec then
        if rec.auraInstanceID then
            s.privateByInstance[rec.auraInstanceID] = nil
        end
        s.private[spellId] = nil
        VA.Events:Fire(VA.E.PRIVATE_AURA_REMOVED, "player", rec)
    end
end

-- ---------------------------------------------------------------------------
-- Normal aura processing
-- ---------------------------------------------------------------------------
local function HandleAddedAura(unit, aura)
    if not aura then return end
    EnsureUnit(unit)

    -- Private auras piggyback on addedAuras — route to private path
    if aura.isPrivateAura then
        if unit == "player" then
            HandlePrivateAuraAdded(
                aura.spellId, aura.icon,
                aura.count or aura.applications or 0,
                aura.sourceUnit, aura.auraInstanceID
            )
        end
        return
    end

    -- UNIT_AURA addedAuras fields (isHelpful, isHarmful) are secret booleans that
    -- cannot be used in any conditional. Re-fetch via the explicit API which
    -- returns normal, non-secret values (confirmed: HandleUpdatedAura does this
    -- with the same API and isHelpful is accessible there).
    if aura.auraInstanceID then
        local fresh = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, aura.auraInstanceID)
        if fresh then aura = fresh end
    end

    local filter
    if aura.isHelpful == true then filter = "HELPFUL" else filter = "HARMFUL" end
    AuraTrigger.state[unit][filter][aura.auraInstanceID] = aura
    VA.Events:Fire(VA.E.AURA_ADDED, unit, filter, aura)
end

local function HandleUpdatedAura(unit, auraInstanceID)
    EnsureUnit(unit)
    local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
    if not aura then return end

    if aura.isPrivateAura then
        -- Private aura updated — refresh its record
        if unit == "player" then
            local s   = AuraTrigger.state["player"]
            local sid = s.privateByInstance[auraInstanceID]
            if sid and s.private[sid] then
                s.private[sid].count = aura.count or aura.applications or 0
                VA.Events:Fire(VA.E.PRIVATE_AURA_ADDED, "player", s.private[sid])
            end
        end
        return
    end

    local filter
    if aura.isHelpful == true then filter = "HELPFUL" else filter = "HARMFUL" end
    AuraTrigger.state[unit][filter][auraInstanceID] = aura
    VA.Events:Fire(VA.E.AURA_UPDATED, unit, filter, aura)
end

local function HandleRemovedAura(unit, auraInstanceID)
    local s = AuraTrigger.state[unit]
    if not s then return end

    -- Check if this was a private aura instance
    if s.privateByInstance and s.privateByInstance[auraInstanceID] then
        local spellId = s.privateByInstance[auraInstanceID]
        HandlePrivateAuraRemoved(spellId)
        return
    end

    -- Normal aura removal
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        if s[filter][auraInstanceID] then
            local aura = s[filter][auraInstanceID]
            s[filter][auraInstanceID] = nil
            VA.Events:Fire(VA.E.AURA_REMOVED, unit, filter, aura)
            return
        end
    end
end

-- Full rescan for a unit (isFullUpdate == true or no info table)
local function FullScanUnit(unit)
    EnsureUnit(unit)
    local s = AuraTrigger.state[unit]

    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        local current = {}
        local i = 1
        while true do
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
            if not aura then break end
            if aura.isPrivateAura then
                -- Route private auras found in a full scan
                if unit == "player" and not s.private[aura.spellId] then
                    HandlePrivateAuraAdded(
                        aura.spellId, aura.icon,
                        aura.count or aura.applications or 0,
                        aura.sourceUnit, aura.auraInstanceID
                    )
                end
            else
                current[aura.auraInstanceID] = aura
            end
            i = i + 1
        end

        -- Removals
        for id, old in pairs(s[filter]) do
            if not current[id] then
                s[filter][id] = nil
                VA.Events:Fire(VA.E.AURA_REMOVED, unit, filter, old)
            end
        end

        -- Additions / updates
        for id, aura in pairs(current) do
            if not s[filter][id] then
                s[filter][id] = aura
                VA.Events:Fire(VA.E.AURA_ADDED, unit, filter, aura)
            else
                s[filter][id] = aura
                VA.Events:Fire(VA.E.AURA_UPDATED, unit, filter, aura)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- UNIT_AURA handler
-- ---------------------------------------------------------------------------
local function OnUnitAura(_, unit, info)
    if not VA.UnitExists(unit) then return end

    if info == nil or info.isFullUpdate then
        FullScanUnit(unit)
        return
    end

    if info.addedAuras then
        for _, aura in ipairs(info.addedAuras) do
            HandleAddedAura(unit, aura)
        end
    end

    if info.updatedAuraInstanceIDs then
        for _, id in ipairs(info.updatedAuraInstanceIDs) do
            HandleUpdatedAura(unit, id)
        end
    end

    if info.removedAuraInstanceIDs then
        for _, id in ipairs(info.removedAuraInstanceIDs) do
            HandleRemovedAura(unit, id)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Public query API
-- ---------------------------------------------------------------------------
function AuraTrigger:GetAura(unit, filter, auraInstanceID)
    local s = self.state[unit]
    return s and s[filter] and s[filter][auraInstanceID]
end

function AuraTrigger:GetPrivateAura(spellId)
    local s = self.state["player"]
    return s and s.private[spellId]
end

function AuraTrigger:IterAuras(unit, filter)
    local s = self.state[unit]
    if not s or not s[filter] then return pairs({}) end
    return pairs(s[filter])
end

function AuraTrigger:IterPrivateAuras()
    local s = self.state["player"]
    if not s then return pairs({}) end
    return pairs(s.private)
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------
function AuraTrigger:Init()
    VA.Events:WowOn("UNIT_AURA", OnUnitAura, "AuraTrigger")

    VA.Events:WowOn("PLAYER_ENTERING_WORLD", function()
        AuraTrigger.state = {}
        FullScanUnit("player")
    end, "AuraTrigger_World")
end
