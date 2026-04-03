-- =============================================================================
-- Core/Init.lua
-- Establishes the VoidAuras namespace and shared utilities.
-- Everything else in the addon receives VA as its first upvalue via `...`.
-- =============================================================================

local ADDON_NAME, VA = ...
_G[ADDON_NAME] = VA

VA.version    = "0.1.0"
VA.addonName  = ADDON_NAME

-- ---------------------------------------------------------------------------
-- Feature flags
-- Disabled features are hidden from the UI and skipped at runtime.
-- ---------------------------------------------------------------------------
VA.FEATURES = {
    -- Cooldown tracking is disabled: in WoW 12.x spell cooldowns are exposed
    -- only as private auras and are not accessible via GetSpellCooldown /
    -- SPELL_UPDATE_COOLDOWN in the normal way.
    COOLDOWN = false,
}

-- ---------------------------------------------------------------------------
-- Module registration
-- Modules call VA:Register("Name", table) so Init can sequence their :Init()
-- calls in a guaranteed order at PLAYER_LOGIN.
-- ---------------------------------------------------------------------------
VA._modules     = {}  -- ordered list: { name, tbl }
VA._moduleIndex = {}  -- name -> tbl for fast lookup

function VA:Register(name, tbl)
    assert(not self._moduleIndex[name], "VoidAuras: duplicate module '" .. name .. "'")
    tinsert(self._modules, { name = name, mod = tbl })
    self._moduleIndex[name] = tbl
    return tbl
end

function VA:GetModule(name)
    return self._moduleIndex[name]
end

-- ---------------------------------------------------------------------------
-- Error log (read by the Debug tab in the options panel)
-- ---------------------------------------------------------------------------
VA.errorLog     = {}
local LOG_LIMIT = 200

-- ---------------------------------------------------------------------------
-- Logging
-- ---------------------------------------------------------------------------
function VA:Print(msg)
    print("|cff9966ff[VoidAuras]|r " .. tostring(msg))
end

function VA:Debug(msg)
    if self.db and self.db.global and self.db.global.debug then
        print("|cff666699[VA:debug]|r " .. tostring(msg))
    end
end

function VA:Error(msg)
    local s = tostring(msg)
    -- Always print to chat
    print("|cffff4444[VoidAuras ERROR]|r " .. s)
    -- Append to in-memory log with timestamp
    tinsert(VA.errorLog, date("%H:%M:%S") .. "  " .. s)
    if #VA.errorLog > LOG_LIMIT then
        tremove(VA.errorLog, 1)
    end
    -- Notify the debug panel if it's open
    VA.Events:Fire("VA_ERROR_LOGGED")
end

-- ---------------------------------------------------------------------------
-- Utility
-- ---------------------------------------------------------------------------

-- Safe unit existence check (handles broken unit tokens in 12.x)
function VA.UnitExists(unit)
    return unit and UnitExists(unit) and UnitIsConnected(unit)
end

-- Shallow-copy a table
function VA.CopyTable(src)
    local out = {}
    for k, v in pairs(src) do out[k] = v end
    return out
end

-- Deep-copy a table
function VA.DeepCopy(src)
    if type(src) ~= "table" then return src end
    local out = {}
    for k, v in pairs(src) do
        out[VA.DeepCopy(k)] = VA.DeepCopy(v)
    end
    return setmetatable(out, getmetatable(src))
end

-- Clamp a number between min and max
function VA.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- ---------------------------------------------------------------------------
-- Bootstrap frame: sequences module Init calls on PLAYER_LOGIN
-- ---------------------------------------------------------------------------
local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("PLAYER_LOGOUT")

bootstrap:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- SavedData must initialise first (provides VA.db)
        local sd = VA._moduleIndex["SavedData"]
        if sd and sd.Init then sd:Init() end

        -- Events bus second (everything else fires events)
        local ev = VA._moduleIndex["Events"]
        if ev and ev.Init then ev:Init() end

        -- Remaining modules in registration order
        for _, entry in ipairs(VA._modules) do
            if entry.name ~= "SavedData" and entry.name ~= "Events" then
                if entry.mod.Init then
                    local ok, err = pcall(entry.mod.Init, entry.mod)
                    if not ok then
                        VA:Error("Module '" .. entry.name .. "' failed Init: " .. tostring(err))
                    end
                end
            end
        end

        VA:Print("v" .. VA.version .. " loaded.")

    elseif event == "PLAYER_LOGOUT" then
        local sd = VA._moduleIndex["SavedData"]
        if sd and sd.Flush then sd:Flush() end
    end
end)
