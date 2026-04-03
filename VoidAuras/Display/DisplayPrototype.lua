-- =============================================================================
-- Display/DisplayPrototype.lua
-- Base display mixin + DisplayManager.
--
-- Usage:
--   local MyDisplay = setmetatable({}, { __index = VA.DisplayProto })
--   function MyDisplay:_CreateFrame(auraDef)  ... end
--   function MyDisplay:Update(auraData)        ... end
--
-- DisplayManager.Init() creates instances for all saved aura defs and
-- responds to CONFIG_CHANGED / DISPLAY_HIDE events.
-- =============================================================================

local _, VA = ...
local T = VA.Theme

-- ---------------------------------------------------------------------------
-- DisplayProto — base mixin
-- ---------------------------------------------------------------------------
VA.DisplayProto = {}
local Proto = VA.DisplayProto

function Proto:New(auraDef)
    local inst = setmetatable({}, { __index = self })
    inst.auraDef = auraDef
    inst.active  = false
    inst.frame   = nil
    inst:_CreateFrame(auraDef)
    inst:_SetPosition(auraDef.display)
    inst:_Subscribe()
    inst:_InitialActivate()
    return inst
end

-- Subclasses override this to create their frame hierarchy.
function Proto:_CreateFrame(auraDef)
    local dp = auraDef.display or {}
    local f  = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(dp.width or 40, dp.height or 40)
    T:Apply(f, T.color.panel, T.color.border)
    f:Hide()
    self.frame = f
    self:_MakeDraggable(f, auraDef.id)
end

-- Apply saved position from the active profile.
function Proto:_SetPosition(dp)
    if not self.frame then return end
    local p   = VA.db:Profile()
    local pos = p.displays and p.displays[self.auraDef.id]
    if pos then
        self.frame:ClearAllPoints()
        self.frame:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
    else
        local point = dp and dp.point or "CENTER"
        self.frame:ClearAllPoints()
        self.frame:SetPoint(point, UIParent, dp and dp.relPoint or "CENTER", dp and dp.x or 0, dp and dp.y or 0)
    end
end

-- Save current frame position into the active profile.
function Proto:_SavePosition()
    if not self.frame then return end
    local p = VA.db:Profile()
    p.displays = p.displays or {}
    local pt, _, rpt, x, y = self.frame:GetPoint(1)
    p.displays[self.auraDef.id] = { point = pt, relPoint = rpt, x = x, y = y }
end

-- Make the display frame draggable by the user.
function Proto:_MakeDraggable(f, id)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop",  function()
        f:StopMovingOrSizing()
        self:_SavePosition()
    end)
end

-- Subclasses override to update visual state from an AuraData record.
function Proto:Update(auraData) end

-- Returns true if the loadWhen condition currently permits showing.
function Proto:_LoadOK()
    local lw = self.auraDef.trigger and self.auraDef.trigger.loadWhen or "always"
    if lw == "never"  then return false end
    if lw == "combat" then return not not UnitAffectingCombat("player") end
    return true   -- "always"
end

function Proto:Show(auraData)
    -- Always remember trigger state so combat-entry can show the display.
    self._triggerActive = true
    self._lastAuraData  = auraData
    if not self:_LoadOK() then return end
    self.active = true
    -- Don't overwrite preview visuals with real trigger data.
    if self._previewing then return end
    if self.frame then self.frame:Show() end
    self:Update(auraData)
end

function Proto:Hide()
    self._triggerActive = false
    self._lastAuraData  = nil
    self.active = false
    -- Leave the frame visible if a manual preview is active.
    if not self._previewing then
        if self.frame then self.frame:Hide() end
    end
end

-- Preview: show the display visually without touching trigger state.
-- Safe to call while a real aura is (or isn't) active.
function Proto:Preview(auraData)
    self._previewing  = true
    self._previewData = auraData
    if self.frame then self.frame:Show() end
    self:Update(auraData)
end

-- Stop preview and restore display to its real trigger state.
function Proto:StopPreview()
    if not self._previewing then return end
    self._previewing  = false
    self._previewData = nil
    if self.active then
        -- Real trigger was (and still is) active — keep showing with real data.
        if self.frame then self.frame:Show() end
        if self._lastAuraData then self:Update(self._lastAuraData) end
    else
        if self.frame then self.frame:Hide() end
    end
end

function Proto:Destroy()
    self:_Unsubscribe()
    if self.frame then
        self.frame:Hide()
        self.frame:SetParent(nil)
        self.frame = nil
    end
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Placeholder aura shown when trigger.missing = true (spell is absent),
-- or when a cooldown trigger is in always-show mode and the spell is ready.
local function MakePlaceholder(auraDef)
    local sid = auraDef.trigger and auraDef.trigger.spellId or 0
    return {
        spellId        = sid,
        icon           = sid ~= 0 and C_Spell.GetSpellTexture(sid) or nil,
        name           = sid ~= 0 and (C_Spell.GetSpellName(sid) or "") or "",
        duration       = 0,
        expirationTime = nil,
    }
end

-- ---------------------------------------------------------------------------
-- Trigger matching helpers
-- ---------------------------------------------------------------------------

-- Returns true if a normal AuraData matches this display's trigger config.
local function MatchesAura(auraDef, unit, filter, aura)
    local tr = auraDef.trigger
    if tr.type ~= "aura" then return false end
    if tr.unit ~= unit   then return false end
    if tr.filter ~= filter then return false end
    if tr.isPrivate        then return false end  -- private auras use separate path
    if tr.spellId and tr.spellId ~= 0 and tr.spellId ~= aura.spellId then
        return false
    end
    return true
end

local function MatchesPrivate(auraDef, rec)
    local tr = auraDef.trigger
    if tr.type ~= "aura" or not tr.isPrivate then return false end
    if tr.spellId and tr.spellId ~= 0 and tr.spellId ~= rec.spellId then
        return false
    end
    return true
end

local function MatchesCooldown(auraDef, spellId)
    local tr = auraDef.trigger
    return tr.type == "cooldown" and (tr.spellId == 0 or tr.spellId == spellId)
end

local function MatchesResource(auraDef, unit, resourceType)
    local tr = auraDef.trigger
    return tr.type == "resource"
        and tr.unit == unit
        and (not tr.resourceType or tr.resourceType == resourceType)
end

-- ---------------------------------------------------------------------------
-- Initial activation check
-- Called from New() after _Subscribe(). Shows the display immediately if
-- the trigger condition is already met (buff was active before the instance
-- was created — e.g. user configured the aura while the buff was up).
-- ---------------------------------------------------------------------------
function Proto:_InitialActivate()
    local tr = self.auraDef.trigger
    if not tr or not VA.AuraTrigger then return end

    local missing = tr.missing

    if tr.type == "aura" then
        if tr.isPrivate then
            local rec = VA.AuraTrigger:GetPrivateAura(tr.spellId)
            if missing then
                if not rec then self:Show(MakePlaceholder(self.auraDef)) end
            else
                if rec then self:Show(rec) end
            end
        else
            local filter = tr.filter or "HELPFUL"
            local unit   = tr.unit   or "player"
            local found
            for _, aura in VA.AuraTrigger:IterAuras(unit, filter) do
                if MatchesAura(self.auraDef, unit, filter, aura) then
                    found = aura
                    break
                end
            end
            if missing then
                if not found then self:Show(MakePlaceholder(self.auraDef)) end
            else
                if found then self:Show(found) end
            end
        end
    elseif VA.FEATURES.COOLDOWN and tr.type == "cooldown" and tr.spellId and tr.spellId ~= 0 then
        local info = C_Spell.GetSpellCooldown(tr.spellId)
        if info and info.startTime > 0 and info.duration > 1.6 then
            self:Show({
                spellId        = tr.spellId,
                duration       = info.duration,
                expirationTime = info.startTime + info.duration,
            })
        elseif not tr.onlyOnCooldown then
            -- Always-show mode: display the icon immediately, no cooldown active.
            self:Show(MakePlaceholder(self.auraDef))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Event subscriptions
-- ---------------------------------------------------------------------------
function Proto:_Subscribe()
    local id  = self.auraDef.id
    local E   = VA.Events

    E:On(VA.E.AURA_ADDED, function(unit, filter, aura)
        if MatchesAura(self.auraDef, unit, filter, aura) then
            if self.auraDef.trigger.missing then self:Hide()
            else self:Show(aura) end
        end
    end, "disp_added_" .. id)

    E:On(VA.E.AURA_UPDATED, function(unit, filter, aura)
        if self._previewing then return end
        if self.active and MatchesAura(self.auraDef, unit, filter, aura) then
            if not self.auraDef.trigger.missing then self:Update(aura) end
        end
    end, "disp_updated_" .. id)

    E:On(VA.E.AURA_REMOVED, function(unit, filter, aura)
        if MatchesAura(self.auraDef, unit, filter, aura) then
            if self.auraDef.trigger.missing then self:Show(MakePlaceholder(self.auraDef))
            else self:Hide() end
        end
    end, "disp_removed_" .. id)

    E:On(VA.E.PRIVATE_AURA_ADDED, function(unit, rec)
        if MatchesPrivate(self.auraDef, rec) then
            if self.auraDef.trigger.missing then self:Hide()
            else self:Show(rec) end
        end
    end, "disp_pa_added_" .. id)

    E:On(VA.E.PRIVATE_AURA_REMOVED, function(unit, rec)
        if MatchesPrivate(self.auraDef, rec) then
            if self.auraDef.trigger.missing then self:Show(MakePlaceholder(self.auraDef))
            else self:Hide() end
        end
    end, "disp_pa_removed_" .. id)

    if VA.FEATURES.COOLDOWN then
        E:On(VA.E.COOLDOWN_STARTED, function(spellId, start, duration)
            if MatchesCooldown(self.auraDef, spellId) then
                self:Show({ spellId = spellId, duration = duration, expirationTime = start + duration })
            end
        end, "disp_cd_started_" .. id)

        E:On(VA.E.COOLDOWN_FINISHED, function(spellId)
            if MatchesCooldown(self.auraDef, spellId) then
                if self.auraDef.trigger.onlyOnCooldown then
                    self:Hide()
                elseif not self._previewing then
                    -- Always-show mode: keep visible but clear the cooldown display.
                    self:Update(MakePlaceholder(self.auraDef))
                end
            end
        end, "disp_cd_finished_" .. id)
    end

    E:On(VA.E.RESOURCE_UPDATED, function(unit, resourceType, current, max, pct)
        if MatchesResource(self.auraDef, unit, resourceType) then
            self:Show({ unit = unit, resourceType = resourceType, current = current, max = max, pct = pct })
        end
    end, "disp_res_" .. id)

    -- Re-evaluate visibility when combat state changes (for loadWhen = "combat")
    E:On(VA.E.COMBAT_CHANGED, function(inCombat)
        local lw = self.auraDef.trigger and self.auraDef.trigger.loadWhen or "always"
        if lw ~= "combat" then return end
        if self._triggerActive then
            if inCombat then
                self.active = true
                if self.frame then self.frame:Show() end
                if self._lastAuraData then self:Update(self._lastAuraData) end
            else
                self.active = false
                if self.frame then self.frame:Hide() end
            end
        end
    end, "disp_combat_" .. id)
end

function Proto:_Unsubscribe()
    local id = self.auraDef.id
    local E  = VA.Events
    E:Off(VA.E.AURA_ADDED,           "disp_added_"      .. id)
    E:Off(VA.E.AURA_UPDATED,         "disp_updated_"    .. id)
    E:Off(VA.E.AURA_REMOVED,         "disp_removed_"    .. id)
    E:Off(VA.E.PRIVATE_AURA_ADDED,   "disp_pa_added_"   .. id)
    E:Off(VA.E.PRIVATE_AURA_REMOVED, "disp_pa_removed_" .. id)
    E:Off(VA.E.COOLDOWN_STARTED,     "disp_cd_started_" .. id)
    E:Off(VA.E.COOLDOWN_FINISHED,    "disp_cd_finished_" .. id)
    E:Off(VA.E.RESOURCE_UPDATED,     "disp_res_"        .. id)
    E:Off(VA.E.COMBAT_CHANGED,       "disp_combat_"     .. id)
end

-- ---------------------------------------------------------------------------
-- DisplayManager
-- ---------------------------------------------------------------------------
local DisplayManager = VA:Register("Display", {})
VA.DisplayManager = DisplayManager

DisplayManager.instances = {}

local function MakeInstance(def)
    if not def or not def.enabled then return end
    local dtype = def.display and def.display.type or "icon"
    local proto
    if dtype == "icon" then
        proto = VA.IconDisplay
    elseif dtype == "bar" then
        proto = VA.BarDisplay
    elseif dtype == "text" then
        proto = VA.TextDisplay
    end
    if not proto then
        VA:Error("DisplayManager: unknown display type '" .. tostring(dtype) .. "'")
        return
    end
    local ok, result = pcall(proto.New, proto, def)
    if not ok then
        VA:Error("DisplayManager: failed to create display for '" .. tostring(def.id) .. "': " .. tostring(result))
        return
    end
    return result
end

function DisplayManager:Init()
    -- Create display instances for all persisted aura defs
    for id, def in pairs(VA.db.global.auras or {}) do
        self.instances[id] = MakeInstance(def)
    end

    -- React to aura config changes (save from Panel)
    VA.Events:On(VA.E.CONFIG_CHANGED, function(id)
        local old           = self.instances[id]
        local wasActive     = old and old._triggerActive
        local lastData      = old and old._lastAuraData
        local wasPreviewing = old and old._previewing
        local previewData   = old and old._previewData
        if old then old:Destroy() end
        local def  = VA.db.global.auras[id]
        local inst = def and MakeInstance(def) or nil
        self.instances[id] = inst
        if inst then
            -- Carry live trigger state so size / type changes are visible immediately.
            if wasActive and not inst.active and lastData then
                inst:Show(lastData)
            end
            -- Carry preview state so an active preview survives config saves.
            if wasPreviewing then
                inst:Preview(previewData or {})
            end
        end
    end, "DisplayManager_config")

    -- React to explicit hide (delete from Panel)
    VA.Events:On(VA.E.DISPLAY_HIDE, function(id)
        local inst = self.instances[id]
        if inst then
            inst:Destroy()
            self.instances[id] = nil
        end
    end, "DisplayManager_hide")
end
