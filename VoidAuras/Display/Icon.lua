-- =============================================================================
-- Display/Icon.lua
-- Icon display: spell icon + cooldown spiral + stack count + countdown timer.
-- Void-themed border, draggable.
-- =============================================================================

local _, VA = ...
local T = VA.Theme

VA.IconDisplay = setmetatable({}, { __index = VA.DisplayProto })
local Icon = VA.IconDisplay

-- ---------------------------------------------------------------------------
-- Frame hierarchy per icon instance:
--   root (BackdropTemplate) — border + drag target
--     tex     — spell icon
--     cd      — Cooldown frame (the spiral)
--     overlay — dark tint when on cooldown
--     count   — stack count (top-right)
--     timer   — countdown text (bottom-center)
-- ---------------------------------------------------------------------------
function Icon:_CreateFrame(auraDef)
    local dp = auraDef.display or {}
    local w  = dp.width  or 40
    local h  = dp.height or 40

    local root = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    root:SetFrameStrata("MEDIUM")
    root:SetSize(w, h)
    T:Apply(root, T.color.bg, T.color.borderHi)
    root:Hide()
    self.frame = root

    -- Icon texture — pre-load from spell ID so the icon is ready immediately
    local tex = root:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT",     root, "TOPLEFT",     1, -1)
    tex:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -1,  1)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trim default icon border
    local spellId = auraDef.trigger and auraDef.trigger.spellId
    if spellId and spellId ~= 0 then
        local icon = C_Spell.GetSpellTexture(spellId)
        if icon then tex:SetTexture(icon) end
    end
    self._tex = tex

    -- Cooldown spiral
    local cd = CreateFrame("Cooldown", nil, root, "CooldownFrameTemplate")
    cd:SetAllPoints(tex)
    cd:SetDrawSwipe(true)
    cd:SetDrawBling(false)
    cd:SetReverse(false)
    cd:SetHideCountdownNumbers(true)  -- we draw our own
    self._cd = cd

    -- Dark overlay (shown when on cooldown)
    local overlay = root:CreateTexture(nil, "OVERLAY")
    overlay:SetTexture(T.WHITE)
    overlay:SetAllPoints(tex)
    overlay:SetVertexColor(0, 0, 0, 0.4)
    overlay:Hide()
    self._overlay = overlay

    -- Stack count (top-right)
    local count = root:CreateFontString(nil, "OVERLAY")
    count:SetFont(T.font.count.path, T.font.count.size, T.font.count.flags)
    count:SetTextColor(T.color.white[1], T.color.white[2], T.color.white[3], 1)
    count:SetShadowOffset(1, -1)
    count:SetShadowColor(0, 0, 0, 1)
    count:SetPoint("TOPRIGHT", root, "TOPRIGHT", -2, -2)
    count:SetText("")
    self._count = count

    -- Timer (bottom-center)
    local timer = root:CreateFontString(nil, "OVERLAY")
    timer:SetFont(T.font.timer.path, T.font.timer.size, T.font.timer.flags)
    timer:SetTextColor(T.color.white[1], T.color.white[2], T.color.white[3], 1)
    timer:SetShadowOffset(1, -1)
    timer:SetShadowColor(0, 0, 0, 1)
    timer:SetPoint("BOTTOM", root, "BOTTOM", 0, 2)
    timer:SetText("")
    self._timer = timer

    -- Accent glow border (pulse when first shown)
    local glow = root:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(T.WHITE)
    glow:SetPoint("TOPLEFT",     -2, 2)
    glow:SetPoint("BOTTOMRIGHT",  2,-2)
    glow:SetVertexColor(T.color.accentGlow[1], T.color.accentGlow[2], T.color.accentGlow[3], 0)
    self._glow = glow

    -- User-configurable persistent glow ring (ADD-blended, extends 6px beyond icon)
    local userGlow = root:CreateTexture(nil, "BACKGROUND")
    userGlow:SetTexture(T.WHITE)
    userGlow:SetPoint("TOPLEFT",     root, "TOPLEFT",     -6,  6)
    userGlow:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT",  6, -6)
    userGlow:SetBlendMode("ADD")
    userGlow:SetVertexColor(0, 0, 0, 0)
    self._userGlow = userGlow

    -- OnUpdate to tick the timer text
    root:SetScript("OnUpdate", function() self:_TickTimer() end)

    self:_MakeDraggable(root, auraDef.id)
    self:_SetPosition(dp)
end

-- ---------------------------------------------------------------------------
-- Timer tick
-- ---------------------------------------------------------------------------
local function FormatTime(seconds)
    if seconds <= 0      then return "" end
    if seconds < 10      then return string.format("%.1f", seconds) end
    if seconds < 60      then return string.format("%d",   math.ceil(seconds)) end
    if seconds < 3600    then return string.format("%d:%02d", math.floor(seconds/60), seconds%60) end
    return string.format("%dh", math.floor(seconds/3600))
end

function Icon:_TickTimer()
    if not self.active or not self._expirationTime then
        self._timer:SetText("")
        return
    end
    local dp = self.auraDef.display or {}
    if dp.showTimer == false then
        self._timer:SetText("")
        return
    end
    local remaining = self._expirationTime - GetTime()
    if remaining <= 0 then
        self._timer:SetText("")
    else
        self._timer:SetText(FormatTime(remaining))
    end
end

-- ---------------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------------
function Icon:Update(auraData)
    if not auraData then return end
    local dp = self.auraDef.display or {}

    -- Icon texture
    local icon = auraData.icon or auraData.texture
    if icon then
        self._tex:SetTexture(icon)
    end

    -- Stack count
    local stacks = auraData.count or auraData.applications or 0
    if dp.showCount ~= false and stacks > 0 then
        self._count:SetText(tostring(stacks))
    else
        self._count:SetText("")
    end

    -- Cooldown spiral
    local start    = auraData.expirationTime and (auraData.expirationTime - (auraData.duration or 0)) or 0
    local duration = auraData.duration or 0
    self._expirationTime = auraData.expirationTime

    if dp.showCooldown ~= false and duration and duration > 0 and start > 0 then
        self._cd:SetCooldown(start, duration)
        self._overlay:Show()
    else
        self._cd:Clear()
        self._overlay:Hide()
    end

    -- User glow
    if self._userGlow then
        if dp.showGlow then
            local gc = dp.glowColor or { 1, 0.8, 0, 1 }
            self._userGlow:SetVertexColor(gc[1], gc[2], gc[3], 0.65)
        else
            self._userGlow:SetVertexColor(0, 0, 0, 0)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Show override: flash the glow border briefly
-- ---------------------------------------------------------------------------
function Icon:Show(auraData)
    VA.DisplayProto.Show(self, auraData)

    -- Quick accent pulse
    local glow = self._glow
    local alpha = 0.7
    local elapsed = 0
    local function Fade(_, dt)
        elapsed = elapsed + dt
        alpha   = 0.7 * (1 - elapsed / 0.4)
        if alpha <= 0 then
            glow:SetVertexColor(T.color.accentGlow[1], T.color.accentGlow[2], T.color.accentGlow[3], 0)
            self.frame:SetScript("OnUpdate", function() self:_TickTimer() end)
            return
        end
        glow:SetVertexColor(T.color.accentGlow[1], T.color.accentGlow[2], T.color.accentGlow[3], alpha)
    end
    self.frame:SetScript("OnUpdate", Fade)
end
