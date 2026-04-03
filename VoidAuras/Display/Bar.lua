-- =============================================================================
-- Display/Bar.lua
-- Horizontal progress bar: spell name label on left, countdown on right,
-- fill proportional to remaining duration. Void-themed border.
-- =============================================================================

local _, VA = ...
local T = VA.Theme

VA.BarDisplay = setmetatable({}, { __index = VA.DisplayProto })
local Bar = VA.BarDisplay

function Bar:_CreateFrame(auraDef)
    local dp = auraDef.display or {}
    local w  = dp.width  or 200
    local h  = dp.height or 20

    local root = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    root:SetFrameStrata("MEDIUM")
    root:SetSize(w, h)
    T:Apply(root, T.color.bg, T.color.borderHi)
    root:Hide()
    self.frame = root

    -- Icon (left side, square) — pre-load from spell ID immediately
    local ico = root:CreateTexture(nil, "ARTWORK")
    ico:SetSize(h - 2, h - 2)
    ico:SetPoint("LEFT", 1, 0)
    ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local spellId = auraDef.trigger and auraDef.trigger.spellId
    if spellId and spellId ~= 0 then
        local icon = C_Spell.GetSpellTexture(spellId)
        if icon then ico:SetTexture(icon) end
    end
    self._ico = ico

    -- Progress fill background
    local fillBg = root:CreateTexture(nil, "BACKGROUND")
    fillBg:SetTexture(T.WHITE)
    fillBg:SetVertexColor(T.color.accentLo[1], T.color.accentLo[2], T.color.accentLo[3], 0.3)
    fillBg:SetPoint("TOPLEFT",     ico, "TOPRIGHT",    1, 0)
    fillBg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -1, 1)
    self._fillBg = fillBg

    -- Progress fill (the actual bar)
    local fill = root:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(T.WHITE)
    local bc = dp.barColor or { T.color.accent[1], T.color.accent[2], T.color.accent[3], 0.7 }
    fill:SetVertexColor(bc[1], bc[2], bc[3], bc[4] or 0.7)
    fill:SetPoint("TOPLEFT",  fillBg, "TOPLEFT",  0, 0)
    fill:SetPoint("BOTTOMLEFT", fillBg, "BOTTOMLEFT", 0, 0)
    fill:SetWidth(1)  -- updated in Update()
    self._fill     = fill
    self._fillW    = 0  -- cache of fillBg width

    -- Spell name label
    local label = root:CreateFontString(nil, "OVERLAY")
    label:SetFont(T.font.body.path, T.font.body.size, T.font.body.flags)
    label:SetTextColor(T.color.text[1], T.color.text[2], T.color.text[3], 1)
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetPoint("LEFT",  fillBg, "LEFT",  4, 0)
    label:SetPoint("RIGHT", fillBg, "RIGHT", -40, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    self._label = label

    -- Timer text (right side)
    local timer = root:CreateFontString(nil, "OVERLAY")
    timer:SetFont(T.font.timer.path, T.font.timer.size, T.font.timer.flags)
    timer:SetTextColor(T.color.textAccent[1], T.color.textAccent[2], T.color.textAccent[3], 1)
    timer:SetShadowOffset(1, -1)
    timer:SetShadowColor(0, 0, 0, 1)
    timer:SetPoint("RIGHT", fillBg, "RIGHT", -4, 0)
    timer:SetText("")
    self._timer = timer

    -- User-configurable persistent glow ring
    local userGlow = root:CreateTexture(nil, "BACKGROUND")
    userGlow:SetTexture(T.WHITE)
    userGlow:SetPoint("TOPLEFT",     root, "TOPLEFT",     -6,  6)
    userGlow:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT",  6, -6)
    userGlow:SetBlendMode("ADD")
    userGlow:SetVertexColor(0, 0, 0, 0)
    self._userGlow = userGlow

    root:SetScript("OnUpdate", function() self:_Tick() end)
    root:SetScript("OnSizeChanged", function(_, nw, nh)
        -- recalculate fill width on resize
        local iconW = self._ico:GetWidth() + 2
        self._fillW = nw - iconW - 2
        self:_UpdateFill()
    end)

    self:_MakeDraggable(root, auraDef.id)
    self:_SetPosition(dp)
end

function Bar:_UpdateFill()
    if not self._expirationTime or not self._duration or self._duration <= 0 then
        self._fill:SetWidth(self._fillW or 1)
        return
    end
    local remaining = self._expirationTime - GetTime()
    local pct       = VA.Clamp(remaining / self._duration, 0, 1)
    local fw        = math.max(1, (self._fillW or 0) * pct)
    self._fill:SetWidth(fw)
end

local function FormatTime(s)
    if s <= 0   then return "" end
    if s < 10   then return string.format("%.1f", s) end
    if s < 60   then return string.format("%d", math.ceil(s)) end
    if s < 3600 then return string.format("%d:%02d", math.floor(s/60), s % 60) end
    return string.format("%dh", math.floor(s/3600))
end

function Bar:_Tick()
    if not self.active then return end
    local dp = self.auraDef.display or {}
    self:_UpdateFill()
    if dp.showTimer ~= false and self._expirationTime then
        local rem = self._expirationTime - GetTime()
        self._timer:SetText(FormatTime(rem))
    else
        self._timer:SetText("")
    end
end

function Bar:Update(auraData)
    if not auraData then return end
    local dp = self.auraDef.display or {}

    -- Icon
    local icon = auraData.icon or auraData.texture
    if icon then self._ico:SetTexture(icon) end

    -- Label
    if dp.showLabel ~= false then
        local name = auraData.name or ""
        if name == "" and auraData.spellId and auraData.spellId ~= 0 then
            name = C_Spell.GetSpellName(auraData.spellId) or ""
        end
        self._label:SetText(name)
    else
        self._label:SetText("")
    end

    -- Bar fill color
    local bc = dp.barColor or { T.color.accent[1], T.color.accent[2], T.color.accent[3], 0.7 }
    self._fill:SetVertexColor(bc[1], bc[2], bc[3], bc[4] or 0.7)

    -- Duration
    self._duration       = auraData.duration or 0
    self._expirationTime = auraData.expirationTime

    -- Recalc fill width from root size
    local iconW     = self._ico:GetWidth() + 2
    self._fillW     = (self.frame:GetWidth() or 200) - iconW - 2
    self:_UpdateFill()

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
