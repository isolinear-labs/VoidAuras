-- =============================================================================
-- Triggers/ResourceTrigger.lua
-- Tracks health and power (mana, rage, energy, etc.) for relevant units.
-- Fires VA.E.RESOURCE_UPDATED(unit, resourceType, current, max, pct)
--
-- resourceType: "health" | "mana" | "power" (generalised primary power)
-- =============================================================================

local _, VA = ...

local ResourceTrigger = VA:Register("ResourceTrigger", {})
VA.ResourceTrigger = ResourceTrigger

-- unit -> { health, maxHealth, power, maxPower, powerType }
ResourceTrigger.state = {}

-- Units to watch (built from aura defs)
local watchedUnits = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function RefreshWatchList()
    wipe(watchedUnits)
    for _, def in pairs(VA.db.global.auras or {}) do
        if def.enabled and def.trigger and def.trigger.type == "resource" then
            local unit = def.trigger.unit
            if unit then watchedUnits[unit] = true end
        end
    end
end

-- WoW 12.x returns "secret number" values for health/power in some contexts;
-- arithmetic on them is blocked by the engine. Wrap in pcall and bail silently.
local function TryUpdate(fn)
    local ok, err = pcall(fn)
    if not ok then
        -- Secret-value restriction — resource tracking unavailable this tick.
        VA:Debug("ResourceTrigger: " .. tostring(err))
    end
end

local function UpdateHealth(unit)
    if not VA.UnitExists(unit) then return end
    TryUpdate(function()
        local cur = UnitHealth(unit)
        local max = UnitHealthMax(unit)
        local pct = (max and max > 0) and (cur / max) or 0
        local s = ResourceTrigger.state[unit] or {}
        ResourceTrigger.state[unit] = s
        s.health    = cur
        s.maxHealth = max
        VA.Events:Fire(VA.E.RESOURCE_UPDATED, unit, "health", cur, max, pct)
    end)
end

local function UpdatePower(unit)
    if not VA.UnitExists(unit) then return end
    TryUpdate(function()
        local powerType = UnitPowerType(unit)
        local cur       = UnitPower(unit, powerType)
        local max       = UnitPowerMax(unit, powerType)
        local pct       = (max and max > 0) and (cur / max) or 0
        local s = ResourceTrigger.state[unit] or {}
        ResourceTrigger.state[unit] = s
        s.power     = cur
        s.maxPower  = max
        s.powerType = powerType
        VA.Events:Fire(VA.E.RESOURCE_UPDATED, unit, "power", cur, max, pct)
        local typeName = _G["SPELL_POWER_" .. (GetPowerTypeString(powerType) or "")] or "power"
        if typeName ~= "power" then
            VA.Events:Fire(VA.E.RESOURCE_UPDATED, unit, typeName:lower(), cur, max, pct)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------------
local function OnUnitHealth(_, unit)
    if watchedUnits[unit] then UpdateHealth(unit) end
end

local function OnUnitPower(_, unit)
    if watchedUnits[unit] then UpdatePower(unit) end
end

local function OnEnteringWorld()
    for unit in pairs(watchedUnits) do
        UpdateHealth(unit)
        UpdatePower(unit)
    end
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------
function ResourceTrigger:Init()
    RefreshWatchList()

    VA.Events:WowOn("UNIT_HEALTH",          OnUnitHealth,     "ResourceTrigger_H")
    VA.Events:WowOn("UNIT_MAXHEALTH",       OnUnitHealth,     "ResourceTrigger_MH")
    VA.Events:WowOn("UNIT_POWER_UPDATE",    OnUnitPower,      "ResourceTrigger_P")
    VA.Events:WowOn("UNIT_MAXPOWER",        OnUnitPower,      "ResourceTrigger_MP")
    VA.Events:WowOn("PLAYER_ENTERING_WORLD", OnEnteringWorld, "ResourceTrigger_World")

    VA.Events:On(VA.E.CONFIG_CHANGED, function()
        RefreshWatchList()
    end, "ResourceTrigger_cfg")

    -- Initial snapshot
    OnEnteringWorld()
end
