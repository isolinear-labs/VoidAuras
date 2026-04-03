-- =============================================================================
-- Display/Text.lua
-- Pure text display. Renders a template string with substitutions:
--   {name}     — spell/aura name
--   {timer}    — remaining time (formatted)
--   {count}    — stack count
--   {pct}      — percentage (for resource triggers)
--   {current}  — current value (resource)
--   {max}      — max value (resource)
-- =============================================================================

local _, VA = ...
local T = VA.Theme

VA.TextDisplay = setmetatable({}, { __index = VA.DisplayProto })
local Text = VA.TextDisplay

-- Offsets used for the 8-directional colored outline copies
local OUTLINE_OFFSETS = { {-1,0},{1,0},{0,-1},{0,1},{-1,-1},{-1,1},{1,-1},{1,1} }

function Text:_CreateFrame(auraDef)
    local dp = auraDef.display or {}

    local root = CreateFrame("Frame", nil, UIParent)
    root:SetFrameStrata("MEDIUM")
    root:SetSize(dp.width or 120, dp.height or 24)
    root:Hide()
    self.frame = root

    local path  = dp.fontPath  or T.font.body.path
    local sz    = dp.fontSize  or T.font.body.size
    local col   = dp.fontColor or T.color.text
    local bc    = dp.borderColor or { 0, 0, 0, 1 }
    local showOutline = dp.fontOutline ~= false

    -- Colored outline copies rendered below the main text (ARTWORK sublayer)
    local outlines = {}
    for _, off in ipairs(OUTLINE_OFFSETS) do
        local o = root:CreateFontString(nil, "ARTWORK")
        o:SetFont(path, sz, "")
        o:SetTextColor(bc[1], bc[2], bc[3], bc[4] or 1)
        o:SetPoint("CENTER", root, "CENTER", off[1], off[2])
        o:SetJustifyH("CENTER")
        o:SetShown(showOutline)
        outlines[#outlines + 1] = o
    end
    self._outlines = outlines

    -- Main text (OVERLAY sublayer — always in front of outline copies)
    local fs = root:CreateFontString(nil, "OVERLAY")
    local flags = dp.fontBold and "THICKOUTLINE" or ""
    fs:SetFont(path, sz, flags)
    fs:SetTextColor(col[1], col[2], col[3], col[4] or 1)
    fs:SetPoint("CENTER", root, "CENTER")
    fs:SetJustifyH("CENTER")
    self._fs = fs

    root:SetScript("OnUpdate", function() self:_Tick() end)

    self:_MakeDraggable(root, auraDef.id)
    self:_SetPosition(dp)
end

local function FormatTime(s)
    if not s or s <= 0 then return "" end
    if s < 10   then return string.format("%.1f", s) end
    if s < 60   then return string.format("%d", math.ceil(s)) end
    if s < 3600 then return string.format("%d:%02d", math.floor(s/60), s % 60) end
    return string.format("%dh", math.floor(s/3600))
end

function Text:_Render()
    local dp   = self.auraDef.display or {}
    local tmpl = dp.template or "{name} {timer}"
    local d    = self._data or {}

    local remaining = ""
    if self._expirationTime then
        remaining = FormatTime(self._expirationTime - GetTime())
    end

    local out = tmpl
        :gsub("{name}",    d.name    or "")
        :gsub("{count}",   tostring(d.count   or ""))
        :gsub("{pct}",     d.pct    and string.format("%.0f%%", d.pct * 100) or "")
        :gsub("{current}", tostring(d.current or ""))
        :gsub("{max}",     tostring(d.max     or ""))
        :gsub("{timer}",   remaining)

    self._fs:SetText(out)
    for _, o in ipairs(self._outlines or {}) do o:SetText(out) end

    local tw = self._fs:GetStringWidth()
    local th = self._fs:GetStringHeight()
    if tw > 0 and th > 0 then
        self.frame:SetSize(tw + 4, th + 4)
    end
end

function Text:_Tick()
    if self.active then self:_Render() end
end

function Text:Update(auraData)
    if not auraData then return end
    local dp = self.auraDef.display or {}

    self._expirationTime = auraData.expirationTime
    self._data = {
        name    = auraData.name or (auraData.spellId and C_Spell.GetSpellName(auraData.spellId) or ""),
        count   = auraData.count or auraData.applications,
        pct     = auraData.pct,
        current = auraData.current,
        max     = auraData.max,
    }

    local path  = dp.fontPath  or T.font.body.path
    local sz    = dp.fontSize  or T.font.body.size
    local col   = dp.fontColor or T.color.text
    local bc    = dp.borderColor or { 0, 0, 0, 1 }
    local flags = dp.fontBold and "THICKOUTLINE" or ""

    self._fs:SetFont(path, sz, flags)
    self._fs:SetTextColor(col[1], col[2], col[3], col[4] or 1)

    local showOutline = dp.fontOutline ~= false
    for _, o in ipairs(self._outlines or {}) do
        o:SetFont(path, sz, "")
        o:SetTextColor(bc[1], bc[2], bc[3], bc[4] or 1)
        o:SetShown(showOutline)
    end

    self:_Render()
end
