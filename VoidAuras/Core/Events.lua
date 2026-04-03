-- =============================================================================
-- Core/Events.lua
-- Central event bus. Two layers:
--   1. WoW events  → dispatched through a single hidden frame
--   2. Internal VA events → pub/sub for inter-module communication
--
-- WoW event subscription:
--   VA.Events:WowOn(event, callback, token)
--   VA.Events:WowOff(event, token)
--
-- Internal event subscription:
--   VA.Events:On(event, callback, token)
--   VA.Events:Off(event, token)
--   VA.Events:Fire(event, ...)
-- =============================================================================

local _, VA = ...

local Events = VA:Register("Events", {})
VA.Events = Events

-- ---------------------------------------------------------------------------
-- Internal pub/sub
-- ---------------------------------------------------------------------------
local _subs = {}  -- [event] = { [token] = callback }

function Events:On(event, callback, token)
    assert(type(event) == "string",   "VA.Events:On — event must be a string")
    assert(type(callback) == "function", "VA.Events:On — callback must be a function")
    assert(token ~= nil,              "VA.Events:On — token must be non-nil")
    _subs[event] = _subs[event] or {}
    _subs[event][token] = callback
end

function Events:Off(event, token)
    if _subs[event] then
        _subs[event][token] = nil
    end
end

function Events:Fire(event, ...)
    local bucket = _subs[event]
    if not bucket then return end
    for _, cb in pairs(bucket) do
        local ok, err = pcall(cb, ...)
        if not ok then
            VA:Error("Events:Fire '" .. event .. "': " .. tostring(err))
        end
    end
end

-- ---------------------------------------------------------------------------
-- WoW event dispatch
-- ---------------------------------------------------------------------------
local _wowSubs   = {}   -- [wowEvent] = { [token] = callback }
local _wowCounts = {}   -- [wowEvent] = number of active subscribers
local _frame     = CreateFrame("Frame")
_frame:SetScript("OnEvent", function(_, wowEvent, ...)
    local bucket = _wowSubs[wowEvent]
    if not bucket then return end
    for _, cb in pairs(bucket) do
        local ok, err = pcall(cb, wowEvent, ...)
        if not ok then
            VA:Error("WoW event '" .. wowEvent .. "': " .. tostring(err))
        end
    end
end)

function Events:WowOn(wowEvent, callback, token)
    assert(type(wowEvent) == "string",    "VA.Events:WowOn — event must be a string")
    assert(type(callback) == "function",  "VA.Events:WowOn — callback must be a function")
    assert(token ~= nil,                  "VA.Events:WowOn — token must be non-nil")

    _wowSubs[wowEvent]   = _wowSubs[wowEvent] or {}
    _wowCounts[wowEvent] = _wowCounts[wowEvent] or 0

    if not _wowSubs[wowEvent][token] then
        _wowCounts[wowEvent] = _wowCounts[wowEvent] + 1
        if _wowCounts[wowEvent] == 1 then
            _frame:RegisterEvent(wowEvent)
        end
    end

    _wowSubs[wowEvent][token] = callback
end

function Events:WowOff(wowEvent, token)
    local bucket = _wowSubs[wowEvent]
    if not bucket or not bucket[token] then return end

    bucket[token] = nil
    _wowCounts[wowEvent] = _wowCounts[wowEvent] - 1

    if _wowCounts[wowEvent] <= 0 then
        _frame:UnregisterEvent(wowEvent)
        _wowCounts[wowEvent] = 0
    end
end

-- ---------------------------------------------------------------------------
-- Well-known internal event names (string constants to avoid typos)
-- ---------------------------------------------------------------------------
VA.E = {
    -- Aura lifecycle
    AURA_ADDED            = "VA_AURA_ADDED",
    AURA_UPDATED          = "VA_AURA_UPDATED",
    AURA_REMOVED          = "VA_AURA_REMOVED",
    PRIVATE_AURA_ADDED    = "VA_PRIVATE_AURA_ADDED",
    PRIVATE_AURA_REMOVED  = "VA_PRIVATE_AURA_REMOVED",

    -- Cooldown lifecycle
    COOLDOWN_STARTED      = "VA_COOLDOWN_STARTED",
    COOLDOWN_FINISHED     = "VA_COOLDOWN_FINISHED",

    -- Resource (health/power/etc.)
    RESOURCE_UPDATED      = "VA_RESOURCE_UPDATED",

    -- Display management
    DISPLAY_SHOW          = "VA_DISPLAY_SHOW",
    DISPLAY_HIDE          = "VA_DISPLAY_HIDE",
    DISPLAY_UPDATE        = "VA_DISPLAY_UPDATE",

    -- Options / config
    CONFIG_CHANGED        = "VA_CONFIG_CHANGED",
    PROFILE_CHANGED       = "VA_PROFILE_CHANGED",

    -- Debug
    ERROR_LOGGED              = "VA_ERROR_LOGGED",

    -- Discovery
    PRIVATE_SPELL_DISCOVERED  = "VA_PRIVATE_SPELL_DISCOVERED",

    -- Combat state (true = entered combat, false = left combat)
    COMBAT_CHANGED            = "VA_COMBAT_CHANGED",
}

function Events:Init()
    -- Relay WoW combat state events onto the internal bus so any module
    -- can react without registering its own WoW events.
    local function FireCombat(_, event)
        VA.Events:Fire(VA.E.COMBAT_CHANGED, event == "PLAYER_REGEN_DISABLED")
    end
    VA.Events:WowOn("PLAYER_REGEN_DISABLED", FireCombat, "Events_CombatIn")
    VA.Events:WowOn("PLAYER_REGEN_ENABLED",  FireCombat, "Events_CombatOut")
end
