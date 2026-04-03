-- =============================================================================
-- Core/SavedData.lua
-- Manages VoidAurasSaved. Provides per-character and global storage with
-- schema versioning so future changes can migrate old data cleanly.
-- =============================================================================

local _, VA = ...

local SavedData = VA:Register("SavedData", {})
VA.SavedData = SavedData

local SCHEMA_VERSION = 1

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------
local GLOBAL_DEFAULTS = {
    schemaVersion = SCHEMA_VERSION,
    debug              = false,
    showSpellIDs       = false,
    -- spell IDs seen to be private at runtime — persists across sessions
    knownPrivateSpells = {},
    -- aura definitions keyed by GUID string
    auras              = {},
}

local CHAR_DEFAULTS = {
    schemaVersion = SCHEMA_VERSION,
    -- per-character overrides (position, profile selection, etc.)
    profile       = "Default",
}

local PROFILE_DEFAULTS = {
    -- display positions and sizes
    displays = {},
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = VA.DeepCopy(v)
            else
                target[k] = v
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Migration table — add functions here as schema versions increase.
-- Each function receives (global, char) and mutates them in place.
-- ---------------------------------------------------------------------------
local migrations = {
    -- [1] = function(g, c) ... end,
}

local function RunMigrations(g, c)
    local from = g.schemaVersion or 0
    for v = from + 1, SCHEMA_VERSION do
        if migrations[v] then
            local ok, err = pcall(migrations[v], g, c)
            if not ok then
                VA:Error("SavedData migration v" .. v .. " failed: " .. tostring(err))
            end
        end
        g.schemaVersion = v
    end
end

-- ---------------------------------------------------------------------------
-- Public API: VA.db.global, VA.db.char, VA.db:Profile()
-- ---------------------------------------------------------------------------
VA.db = {}

function VA.db:Profile()
    local name = VA.db.char.profile or "Default"
    if not VA.db.global.profiles then
        VA.db.global.profiles = {}
    end
    if not VA.db.global.profiles[name] then
        VA.db.global.profiles[name] = VA.DeepCopy(PROFILE_DEFAULTS)
    end
    return VA.db.global.profiles[name]
end

function VA.db:SetProfile(name)
    VA.db.char.profile = name
    VA.Events:Fire(VA.E.PROFILE_CHANGED, name)
end

function VA.db:ListProfiles()
    local out = {}
    for k in pairs(VA.db.global.profiles or {}) do
        tinsert(out, k)
    end
    table.sort(out)
    return out
end

-- ---------------------------------------------------------------------------
-- Init / Flush
-- ---------------------------------------------------------------------------
function SavedData:Init()
    -- VoidAurasSaved is the SavedVariables table injected by WoW at login
    if type(VoidAurasSaved) ~= "table" then
        VoidAurasSaved = {}
    end

    -- Ensure top-level keys exist
    if type(VoidAurasSaved.global) ~= "table" then
        VoidAurasSaved.global = {}
    end
    if type(VoidAurasSaved.chars) ~= "table" then
        VoidAurasSaved.chars = {}
    end

    -- Per-character key: "RealmName/CharacterName"
    local charKey = GetRealmName() .. "/" .. UnitName("player")
    if type(VoidAurasSaved.chars[charKey]) ~= "table" then
        VoidAurasSaved.chars[charKey] = {}
    end

    -- Apply defaults
    ApplyDefaults(VoidAurasSaved.global, GLOBAL_DEFAULTS)
    ApplyDefaults(VoidAurasSaved.chars[charKey], CHAR_DEFAULTS)

    -- Run any pending schema migrations
    RunMigrations(VoidAurasSaved.global, VoidAurasSaved.chars[charKey])

    -- Expose live references
    VA.db.global = VoidAurasSaved.global
    VA.db.char   = VoidAurasSaved.chars[charKey]
end

-- Called on PLAYER_LOGOUT — nothing to do since WoW writes SavedVariables
-- automatically, but a hook point for any cleanup needed in the future.
function SavedData:Flush()
end
