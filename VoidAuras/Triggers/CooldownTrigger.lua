-- =============================================================================
-- Triggers/CooldownTrigger.lua
-- Tracks spell cooldowns via SPELL_UPDATE_COOLDOWN.
-- Fires VA.E.COOLDOWN_STARTED(spellId, start, duration)
-- Fires VA.E.COOLDOWN_FINISHED(spellId)
--
-- Only spells that are registered in VA.db.global.auras with trigger.type ==
-- "cooldown" are tracked, to avoid unnecessary GetSpellCooldown calls.
-- =============================================================================

local _, VA = ...

local CooldownTrigger = VA:Register("CooldownTrigger", {})
VA.CooldownTrigger = CooldownTrigger

-- spellId -> { start, duration, isOnCooldown }
CooldownTrigger.state = {}

-- spellIds we need to watch (populated from aura defs at Init and on CONFIG_CHANGED)
local watchedSpells = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local GCD_THRESHOLD = 1.6  -- ignore GCDs shorter than this

local function IsRealCooldown(duration)
    if not duration then return false end
    -- WoW returns a "secret number" for the GCD duration that cannot be compared
    -- with > using normal Lua. pcall catches that error and treats it as GCD (not real).
    local ok, result = pcall(function() return duration > GCD_THRESHOLD end)
    return ok and result
end

local function RefreshWatchList()
    wipe(watchedSpells)
    local count = 0
    for _, def in pairs(VA.db.global.auras or {}) do
        if def.enabled and def.trigger and def.trigger.type == "cooldown" then
            local sid = def.trigger.spellId
            if sid and sid ~= 0 then
                watchedSpells[sid] = true
                count = count + 1
                VA:Debug("CooldownTrigger: watching spellId " .. sid)
            end
        end
    end
    VA:Debug("CooldownTrigger: RefreshWatchList complete, " .. count .. " spell(s) watched")
end

local function CheckSpell(spellId)
    if not watchedSpells[spellId] then return end

    local info = C_Spell.GetSpellCooldown(spellId)
    if not info then
        VA:Debug("CooldownTrigger: GetSpellCooldown(" .. spellId .. ") returned nil")
        return
    end
    local start, duration = info.startTime, info.duration

    local prev = CooldownTrigger.state[spellId]
    local onCD = IsRealCooldown(duration)

    local durStr = "secret"
    pcall(function() durStr = string.format("%.2f", duration or 0) end)
    VA:Debug(string.format("CooldownTrigger: CheckSpell(%d) start=%.2f dur=%s onCD=%s prevOnCD=%s",
        spellId, start or 0, durStr, tostring(onCD), tostring(prev and prev.isOnCooldown)))

    if onCD then
        if not prev or not prev.isOnCooldown then
            CooldownTrigger.state[spellId] = { start = start, duration = duration, isOnCooldown = true }
            VA:Debug("CooldownTrigger: firing COOLDOWN_STARTED for " .. spellId)
            VA.Events:Fire(VA.E.COOLDOWN_STARTED, spellId, start, duration)
        end
    else
        if prev and prev.isOnCooldown then
            CooldownTrigger.state[spellId] = { isOnCooldown = false }
            VA:Debug("CooldownTrigger: firing COOLDOWN_FINISHED for " .. spellId)
            VA.Events:Fire(VA.E.COOLDOWN_FINISHED, spellId)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------------
local function OnSpellUpdateCooldown()
    if next(watchedSpells) == nil then return end  -- skip if nothing watched
    VA:Debug("CooldownTrigger: SPELL_UPDATE_COOLDOWN fired, checking " .. (function() local n=0 for _ in pairs(watchedSpells) do n=n+1 end return n end)() .. " spell(s)")
    for spellId in pairs(watchedSpells) do
        CheckSpell(spellId)
    end
end

local function OnSpellsChanged()
    -- Re-check all watched spells after spell book updates
    for spellId in pairs(watchedSpells) do
        CheckSpell(spellId)
    end
end

-- UNIT_SPELLCAST_SUCCEEDED fires when the player successfully casts a spell.
-- We use this as a reliable fallback: if the cast is a watched spell, schedule
-- a one-frame delayed check so the cooldown has time to register.
local function OnSpellCastSucceeded(_, unit, _, spellId)
    if unit ~= "player" then return end
    if not watchedSpells[spellId] then return end
    VA:Debug("CooldownTrigger: cast succeeded for watched spell " .. spellId .. ", scheduling check")
    C_Timer.After(0, function() CheckSpell(spellId) end)
end

-- ---------------------------------------------------------------------------
-- Debug dump — returns a formatted string; Dump() prints it to chat.
-- ---------------------------------------------------------------------------
function CooldownTrigger:DumpString()
    local out = {}
    local function add(s) tinsert(out, s) end

    add("=== CooldownTrigger: Watched Spells ===")
    local watchCount = 0
    for sid in pairs(watchedSpells) do
        local name = C_Spell.GetSpellName(sid) or "?"
        add(string.format("  Watching: %d (%s)", sid, name))
        watchCount = watchCount + 1
    end
    if watchCount == 0 then
        add("  (none — check trigger type is 'cooldown' and spellId != 0)")
    end

    add("")
    add("=== CooldownTrigger: Current State ===")
    local stateCount = 0
    for sid, st in pairs(CooldownTrigger.state) do
        local name = C_Spell.GetSpellName(sid) or "?"
        if st.isOnCooldown then
            local rem = (st.start + st.duration) - GetTime()
            add(string.format("  %d (%s): ON COOLDOWN, %.1fs remaining", sid, name, rem))
        else
            add(string.format("  %d (%s): off cooldown", sid, name))
        end
        stateCount = stateCount + 1
    end
    if stateCount == 0 then add("  (no state recorded yet)") end

    add("")
    add("=== Display Instances ===")
    local mgr = VA.DisplayManager
    if not mgr then
        add("  DisplayManager not ready")
    else
        local instCount = 0
        for id, inst in pairs(mgr.instances or {}) do
            if inst then
                local tr = inst.auraDef and inst.auraDef.trigger or {}
                add(string.format("  [%s]  type=%-10s  spellId=%-6s  active=%-5s  frame=%s",
                    id, tostring(tr.type), tostring(tr.spellId),
                    tostring(inst.active), inst.frame and "ok" or "NIL"))
                instCount = instCount + 1
            end
        end
        if instCount == 0 then add("  (no instances — MakeInstance may have failed silently)") end
    end

    add("")
    add("=== Aura Defs (saved) ===")
    local defCount = 0
    for id, def in pairs(VA.db.global.auras or {}) do
        local tr = def.trigger or {}
        add(string.format("  [%s]  name=%-20s  type=%-10s  spellId=%-6s  enabled=%s",
            id, tostring(def.name), tostring(tr.type), tostring(tr.spellId), tostring(def.enabled)))
        defCount = defCount + 1
    end
    if defCount == 0 then add("  (no auras saved)") end

    return table.concat(out, "\n")
end

function CooldownTrigger:Dump()
    local str = self:DumpString()
    for line in str:gmatch("[^\n]+") do
        VA:Print(line)
    end
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------
function CooldownTrigger:Init()
    if not VA.FEATURES.COOLDOWN then
        VA:Debug("CooldownTrigger: disabled by feature flag (COOLDOWN = false)")
        return
    end

    RefreshWatchList()

    VA.Events:WowOn("SPELL_UPDATE_COOLDOWN",    OnSpellUpdateCooldown,  "CooldownTrigger")
    VA.Events:WowOn("SPELLS_CHANGED",           OnSpellsChanged,        "CooldownTrigger_SC")
    VA.Events:WowOn("UNIT_SPELLCAST_SUCCEEDED", OnSpellCastSucceeded,   "CooldownTrigger_cast")

    -- Rebuild watch list when aura definitions change
    VA.Events:On(VA.E.CONFIG_CHANGED, function()
        RefreshWatchList()
    end, "CooldownTrigger_cfg")
end
