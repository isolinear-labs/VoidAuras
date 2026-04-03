-- =============================================================================
-- Options/Widgets.lua
-- Reusable UI primitives built on Theme. All constructors return a container
-- frame that exposes :SetValue() / :GetValue() where appropriate.
--
-- VA.UI.Label(parent, text [, fontDef [, col]])
-- VA.UI.Button(parent, text, w, h, onClick)
-- VA.UI.IconButton(parent, icon, size, onClick)
-- VA.UI.Checkbox(parent, label, checked, onChange)
-- VA.UI.Slider(parent, opts)          -- opts: label,value,min,max,step,width,onChange
-- VA.UI.Dropdown(parent, opts)        -- opts: label,value,options,width,onChange
-- VA.UI.TextInput(parent, opts)       -- opts: label,value,width,numeric,onChange
-- VA.UI.ColorSwatch(parent, opts)     -- opts: label,r,g,b,a,onChange
-- VA.UI.Divider(parent, width)
-- VA.UI.ScrollList(parent, w, h)      -- returns list with :Refresh(items, onSelect)
-- VA.UI.TabBar(parent, tabs, width, onSwitch) -- tabs: {{id,label},...}
-- =============================================================================

local _, VA = ...
local T  = VA.Theme
local UI = {}
VA.UI    = UI

-- ---------------------------------------------------------------------------
-- Internal: styled backdrop frame
-- ---------------------------------------------------------------------------
local function Backdrop(parent, bgCol, borderCol)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    T:Apply(f, bgCol, borderCol)
    return f
end

-- ---------------------------------------------------------------------------
-- Label
-- ---------------------------------------------------------------------------
function UI.Label(parent, text, fontDef, col)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    T:Font(fs, fontDef, col)
    fs:SetText(text or "")
    return fs
end

-- ---------------------------------------------------------------------------
-- Button
-- ---------------------------------------------------------------------------
function UI.Button(parent, text, w, h, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(w or 80, h or T.size.btnH)
    T:Apply(btn, T.color.btnNormal, T.color.border)

    local lbl = btn:CreateFontString(nil, "OVERLAY")
    T:Font(lbl, T.font.body, T.color.text)
    lbl:SetText(text or "")
    lbl:SetPoint("CENTER")

    btn:SetScript("OnEnter", function()
        btn:SetBackdropColor(T.color.btnHover[1], T.color.btnHover[2], T.color.btnHover[3], T.color.btnHover[4])
        btn:SetBackdropBorderColor(T.color.borderHi[1], T.color.borderHi[2], T.color.borderHi[3], T.color.borderHi[4])
        lbl:SetTextColor(T.color.textAccent[1], T.color.textAccent[2], T.color.textAccent[3], 1)
    end)
    btn:SetScript("OnLeave", function()
        btn:SetBackdropColor(T.color.btnNormal[1], T.color.btnNormal[2], T.color.btnNormal[3], T.color.btnNormal[4])
        btn:SetBackdropBorderColor(T.color.border[1], T.color.border[2], T.color.border[3], T.color.border[4])
        lbl:SetTextColor(T.color.text[1], T.color.text[2], T.color.text[3], 1)
    end)
    btn:SetScript("OnClick", onClick or function() end)

    function btn:SetLabel(s) lbl:SetText(s) end
    function btn:Disable()
        btn:SetBackdropColor(T.color.btnDisable[1], T.color.btnDisable[2], T.color.btnDisable[3], 1)
        lbl:SetTextColor(T.color.textDisable[1], T.color.textDisable[2], T.color.textDisable[3], 1)
        btn:EnableMouse(false)
    end
    function btn:Enable()
        btn:SetBackdropColor(T.color.btnNormal[1], T.color.btnNormal[2], T.color.btnNormal[3], 1)
        lbl:SetTextColor(T.color.text[1], T.color.text[2], T.color.text[3], 1)
        btn:EnableMouse(true)
    end

    return btn
end

-- Small danger-styled button (delete, remove, etc.)
function UI.DangerButton(parent, text, w, h, onClick)
    local btn = UI.Button(parent, text, w, h, onClick)
    btn:SetBackdropColor(0.20, 0.04, 0.06, 1)
    btn:SetBackdropBorderColor(T.color.danger[1], T.color.danger[2], T.color.danger[3], 0.6)
    return btn
end

-- ---------------------------------------------------------------------------
-- Checkbox
-- ---------------------------------------------------------------------------
function UI.Checkbox(parent, label, checked, onChange)
    local sz  = T.size.checkSize
    local con = CreateFrame("Frame", nil, parent)
    con:SetSize(sz + 6 + 160, sz)

    local box = CreateFrame("Frame", nil, con, "BackdropTemplate")
    box:SetSize(sz, sz)
    box:SetPoint("LEFT")
    T:Apply(box, T.color.btnNormal, T.color.border)

    local tick = box:CreateTexture(nil, "OVERLAY")
    tick:SetTexture(T.WHITE)
    tick:SetVertexColor(T.color.accent[1], T.color.accent[2], T.color.accent[3], 1)
    tick:SetPoint("TOPLEFT",     box, "TOPLEFT",     3, -3)
    tick:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3,  3)
    tick:SetShown(checked == true)

    local lbl = con:CreateFontString(nil, "OVERLAY")
    T:Font(lbl, T.font.body, T.color.text)
    lbl:SetText(label or "")
    lbl:SetPoint("LEFT", box, "RIGHT", 6, 0)

    local hit = CreateFrame("Button", nil, con)
    hit:SetAllPoints()
    hit:SetScript("OnClick", function()
        checked = not checked
        tick:SetShown(checked)
        local cb = con.onChange or onChange
        if cb then cb(checked) end
    end)
    hit:SetScript("OnEnter", function()
        box:SetBackdropBorderColor(T.color.borderHi[1], T.color.borderHi[2], T.color.borderHi[3], 1)
        lbl:SetTextColor(T.color.textAccent[1], T.color.textAccent[2], T.color.textAccent[3], 1)
    end)
    hit:SetScript("OnLeave", function()
        box:SetBackdropBorderColor(T.color.border[1], T.color.border[2], T.color.border[3], 1)
        lbl:SetTextColor(T.color.text[1], T.color.text[2], T.color.text[3], 1)
    end)

    function con:SetValue(v)
        checked = v == true
        tick:SetShown(checked)
    end
    function con:GetValue() return checked end

    return con
end

-- ---------------------------------------------------------------------------
-- Slider
-- ---------------------------------------------------------------------------
function UI.Slider(parent, opts)
    -- opts: label, value, min, max, step, width, onChange
    local w   = opts.width or 200
    local con = CreateFrame("Frame", nil, parent)
    con:SetSize(w, 40)

    local lbl = con:CreateFontString(nil, "OVERLAY")
    T:Font(lbl, T.font.label, T.color.textDim)
    lbl:SetText(opts.label or "")
    lbl:SetPoint("TOPLEFT")

    local valStr = con:CreateFontString(nil, "OVERLAY")
    T:Font(valStr, T.font.label, T.color.textAccent)
    valStr:SetPoint("TOPRIGHT")
    if opts.hideLabel then valStr:Hide() end

    local sl = CreateFrame("Slider", nil, con, "BackdropTemplate")
    sl:SetSize(w, 16)
    sl:SetOrientation("HORIZONTAL")
    sl:SetPoint("BOTTOMLEFT")
    sl:SetMinMaxValues(opts.min or 0, opts.max or 100)
    sl:SetValue(opts.value or opts.min or 0)
    sl:SetValueStep(opts.step or 1)
    sl:SetObeyStepOnDrag(true)
    T:Apply(sl, T.color.btnNormal, T.color.border)

    -- Always create the thumb directly on the slider and register it via
    -- SetThumbTexture so that WoW 12.x (which returns nil from GetThumbTexture
    -- before a thumb is set) doesn't silently attach the texture to the wrong frame.
    local thumb = sl:CreateTexture(nil, "OVERLAY")
    sl:SetThumbTexture(thumb)
    thumb:SetTexture(T.WHITE)
    thumb:SetSize(12, 22)
    T:Tint(thumb, T.color.accent)

    local function Fmt(v)
        if (opts.step or 1) >= 1 then
            return tostring(math.floor(v + 0.5))
        end
        return string.format("%.2f", v)
    end

    valStr:SetText(Fmt(opts.value or opts.min or 0))

    sl:SetScript("OnValueChanged", function(_, v)
        valStr:SetText(Fmt(v))
        local cb = con.onChange or opts.onChange
        if cb then cb(v) end
    end)

    function con:SetValue(v) sl:SetValue(v) end
    function con:GetValue() return sl:GetValue() end

    return con
end

-- ---------------------------------------------------------------------------
-- Dropdown  (fully custom — no UIDropDownMenu dependency)
-- ---------------------------------------------------------------------------
-- opts: label, value, options = { {value, label}, ... }, width, onChange
function UI.Dropdown(parent, opts)
    local w   = opts.width or 180
    local h   = T.size.inputH
    local con = CreateFrame("Frame", nil, parent)
    con:SetSize(w, h + (opts.label and 18 or 0))

    local yOff = 0
    if opts.label then
        local lbl = con:CreateFontString(nil, "OVERLAY")
        T:Font(lbl, T.font.label, T.color.textDim)
        lbl:SetText(opts.label)
        lbl:SetPoint("TOPLEFT")
        yOff = -16
    end

    local btn = CreateFrame("Button", nil, con, "BackdropTemplate")
    btn:SetSize(w, h)
    btn:SetPoint("TOPLEFT", 0, yOff)
    T:Apply(btn, T.color.btnNormal, T.color.border)

    local bText = btn:CreateFontString(nil, "OVERLAY")
    T:Font(bText, T.font.body, T.color.text)
    bText:SetPoint("LEFT", 6, 0)
    bText:SetPoint("RIGHT", -20, 0)
    bText:SetJustifyH("LEFT")

    local arrow = btn:CreateFontString(nil, "OVERLAY")
    T:Font(arrow, T.font.body, T.color.textDim)
    arrow:SetText("v")
    arrow:SetPoint("RIGHT", -5, 0)

    -- Track current value so GetValue() works
    local currentVal = opts.value

    local function LabelFor(val)
        for _, opt in ipairs(opts.options or {}) do
            if opt[1] == val or opt.value == val then
                return opt[2] or opt.label or tostring(val)
            end
        end
        return tostring(val or "")
    end
    bText:SetText(LabelFor(opts.value))

    -- Popup
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetFrameStrata("TOOLTIP")
    popup:SetWidth(w)
    popup:Hide()
    T:Apply(popup, T.color.panel, T.color.borderHi)

    local function BuildPopup()
        -- Clear old rows
        for _, child in ipairs({ popup:GetChildren() }) do child:Hide() end

        local rows = opts.options or {}
        popup:SetHeight(#rows * h + 2)

        for i, opt in ipairs(rows) do
            local val   = opt[1] or opt.value
            local label = opt[2] or opt.label or tostring(val)

            local row = CreateFrame("Button", nil, popup)
            row:SetSize(w - 2, h)
            row:SetPoint("TOPLEFT", 1, -(i - 1) * h - 1)

            local rt = row:CreateTexture(nil, "BACKGROUND")
            rt:SetTexture(T.WHITE)
            rt:SetAllPoints()
            rt:SetVertexColor(T.color.listItem[1], T.color.listItem[2], T.color.listItem[3], 0)

            local rl = row:CreateFontString(nil, "OVERLAY")
            T:Font(rl, T.font.body, T.color.text)
            rl:SetText(label)
            rl:SetPoint("LEFT", 8, 0)

            row:SetScript("OnEnter", function()
                rt:SetVertexColor(T.color.listHover[1], T.color.listHover[2], T.color.listHover[3], 1)
                rl:SetTextColor(T.color.textAccent[1], T.color.textAccent[2], T.color.textAccent[3], 1)
            end)
            row:SetScript("OnLeave", function()
                rt:SetVertexColor(T.color.listItem[1], T.color.listItem[2], T.color.listItem[3], 0)
                rl:SetTextColor(T.color.text[1], T.color.text[2], T.color.text[3], 1)
            end)
            row:SetScript("OnClick", function()
                currentVal = val
                bText:SetText(label)
                popup:Hide()
                local cb = con.onChange or opts.onChange
                if cb then cb(val) end
            end)
        end
    end

    btn:SetScript("OnClick", function()
        if popup:IsShown() then
            popup:Hide()
        else
            BuildPopup()
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            popup:Show()
        end
    end)
    btn:SetScript("OnEnter", function()
        btn:SetBackdropBorderColor(T.color.borderHi[1], T.color.borderHi[2], T.color.borderHi[3], 1)
    end)
    btn:SetScript("OnLeave", function()
        btn:SetBackdropBorderColor(T.color.border[1], T.color.border[2], T.color.border[3], 1)
    end)

    -- Close popup when the dropdown itself is hidden (e.g. tab switch)
    con:HookScript("OnHide", function() popup:Hide() end)

    function con:SetOptions(newOpts)
        opts.options = newOpts
    end
    function con:SetValue(v)
        currentVal = v
        bText:SetText(LabelFor(v))
    end
    function con:GetValue()
        return currentVal
    end

    return con
end

-- ---------------------------------------------------------------------------
-- TextInput
-- ---------------------------------------------------------------------------
-- opts: label, value, width, numeric, placeholder, onChange
function UI.TextInput(parent, opts)
    local w   = opts.width or 200
    local h   = T.size.inputH
    local con = CreateFrame("Frame", nil, parent)
    con:SetSize(w, h + (opts.label and 18 or 0))

    local yOff = 0
    if opts.label then
        local lbl = con:CreateFontString(nil, "OVERLAY")
        T:Font(lbl, T.font.label, T.color.textDim)
        lbl:SetText(opts.label)
        lbl:SetPoint("TOPLEFT")
        yOff = -16
    end

    local box = CreateFrame("EditBox", nil, con, "BackdropTemplate")
    box:SetSize(w, h)
    box:SetPoint("TOPLEFT", 0, yOff)
    T:Apply(box, T.color.btnNormal, T.color.border)
    box:SetFont(T.font.body.path, T.font.body.size, T.font.body.flags)
    box:SetTextColor(T.color.text[1], T.color.text[2], T.color.text[3], 1)
    box:SetAutoFocus(false)
    box:SetTextInsets(6, 6, 0, 0)
    if opts.numeric then box:SetNumeric(true) end
    box:SetText(tostring(opts.value or ""))

    box:SetScript("OnEditFocusGained", function()
        box:SetBackdropBorderColor(T.color.borderHi[1], T.color.borderHi[2], T.color.borderHi[3], 1)
    end)
    box:SetScript("OnEditFocusLost", function()
        box:SetBackdropBorderColor(T.color.border[1], T.color.border[2], T.color.border[3], 1)
        local cb = con.onChange or opts.onChange
        if cb then cb(box:GetText()) end
    end)
    box:SetScript("OnEnterPressed", function()
        box:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function()
        box:ClearFocus()
    end)

    function con:SetValue(v) box:SetText(tostring(v or "")) end
    function con:GetValue()  return box:GetText() end

    return con
end

-- ---------------------------------------------------------------------------
-- ColorSwatch  (opens WoW's native ColorPickerFrame)
-- ---------------------------------------------------------------------------
-- opts: label, r, g, b, a, onChange(r,g,b,a)
function UI.ColorSwatch(parent, opts)
    local sz  = T.size.swatchSize
    local con = CreateFrame("Frame", nil, parent)
    con:SetSize(sz + 6 + 100, sz + (opts.label and 18 or 0))

    local yOff = 0
    if opts.label then
        local lbl = con:CreateFontString(nil, "OVERLAY")
        T:Font(lbl, T.font.label, T.color.textDim)
        lbl:SetText(opts.label)
        lbl:SetPoint("TOPLEFT")
        yOff = -16
    end

    local r, g, b, a = opts.r or 1, opts.g or 1, opts.b or 1, opts.a or 1
    local prevR, prevG, prevB, prevA

    local swatch = CreateFrame("Button", nil, con, "BackdropTemplate")
    swatch:SetSize(sz, sz)
    swatch:SetPoint("TOPLEFT", 0, yOff)
    T:Apply(swatch, { r, g, b, 1 }, T.color.white)

    local inner = swatch:CreateTexture(nil, "OVERLAY")
    inner:SetTexture(T.WHITE)
    inner:SetPoint("TOPLEFT",     swatch, "TOPLEFT",     1, -1)
    inner:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -1, 1)
    inner:SetVertexColor(r, g, b, a)

    local function Refresh()
        inner:SetVertexColor(r, g, b, a)
        swatch:SetBackdropColor(r, g, b, 1)
    end

    swatch:SetScript("OnClick", function()
        prevR, prevG, prevB, prevA = r, g, b, a
        local function Fire() local cb = con.onChange or opts.onChange; if cb then cb(r, g, b, a) end end
        ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc = function()
                r, g, b = ColorPickerFrame:GetColorRGB()
                Refresh(); Fire()
            end,
            opacityFunc = function()
                a = 1 - ColorPickerFrame:GetColorAlpha()
                Refresh(); Fire()
            end,
            cancelFunc = function()
                r, g, b, a = prevR, prevG, prevB, prevA
                Refresh(); Fire()
            end,
            hasOpacity = true,
            r = r, g = g, b = b,
            opacity = 1 - a,
        })
    end)

    function con:SetValue(nr, ng, nb, na)
        r, g, b, a = nr, ng, nb, na or 1
        Refresh()
    end
    function con:GetValue() return r, g, b, a end

    return con
end

-- ---------------------------------------------------------------------------
-- Divider
-- ---------------------------------------------------------------------------
function UI.Divider(parent, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 200, 1)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(T.WHITE)
    tex:SetAllPoints()
    T:Tint(tex, T.color.divider)
    return f
end

-- ---------------------------------------------------------------------------
-- ScrollList
-- Returns a frame with :Refresh(items, onSelect, selectedId)
-- items: { { id, label, [icon] }, ... }
-- ---------------------------------------------------------------------------
function UI.ScrollList(parent, w, h)
    local ROW_H = 26

    local outer = Backdrop(parent, T.color.bg, T.color.border)
    outer:SetSize(w, h)

    local sf = CreateFrame("ScrollFrame", nil, outer)
    sf:SetPoint("TOPLEFT", 1, -1)
    sf:SetPoint("BOTTOMRIGHT", -T.size.scrollbarW - 1, 1)

    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(w - T.size.scrollbarW - 2)
    content:SetHeight(1)  -- will be set dynamically
    sf:SetScrollChild(content)

    -- Scrollbar
    local sb = CreateFrame("Slider", nil, outer, "BackdropTemplate")
    sb:SetOrientation("VERTICAL")
    sb:SetPoint("TOPRIGHT", outer, "TOPRIGHT", -1, -1)
    sb:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT", -1, 1)
    sb:SetWidth(T.size.scrollbarW)
    T:Apply(sb, T.color.btnNormal, T.color.border)
    sb:SetMinMaxValues(0, 0)
    sb:SetValue(0)
    sb:SetValueStep(ROW_H)

    local sbThumb = sb:GetThumbTexture() or sb:CreateTexture(nil, "OVERLAY")
    sbThumb:SetTexture(T.WHITE)
    sbThumb:SetWidth(T.size.scrollbarW - 4)
    T:Tint(sbThumb, T.color.accentLo)

    sb:SetScript("OnValueChanged", function(_, v)
        sf:SetVerticalScroll(v)
    end)
    sf:SetScript("OnMouseWheel", function(_, d)
        local cur = sb:GetValue()
        local lo, hi = sb:GetMinMaxValues()
        sb:SetValue(VA.Clamp(cur - d * ROW_H * 3, lo, hi))
    end)

    local rows = {}

    function outer:Refresh(items, onSelect, selectedId)
        local n = #items
        content:SetHeight(math.max(n * ROW_H, 1))

        local maxScroll = math.max(0, n * ROW_H - h + 2)
        sb:SetMinMaxValues(0, maxScroll)
        if sb:GetValue() > maxScroll then sb:SetValue(maxScroll) end
        sb:SetShown(maxScroll > 0)

        -- Reuse / create rows
        for i = 1, math.max(n, #rows) do
            if i > n then
                if rows[i] then rows[i]:Hide() end
            else
                local item = items[i]
                local row  = rows[i]

                if not row then
                    row = CreateFrame("Button", nil, content)
                    row:SetSize(content:GetWidth(), ROW_H)

                    local bg = row:CreateTexture(nil, "BACKGROUND")
                    bg:SetTexture(T.WHITE)
                    bg:SetAllPoints()
                    row._bg = bg

                    local lbl = row:CreateFontString(nil, "OVERLAY")
                    T:Font(lbl, T.font.body, T.color.text)
                    lbl:SetJustifyH("LEFT")
                    row._lbl = lbl

                    -- Per-item action button (e.g. eye/preview toggle)
                    local ab = CreateFrame("Button", nil, row)
                    ab:SetSize(ROW_H, ROW_H)
                    ab:SetPoint("RIGHT", 0, 0)
                    local abTex = ab:CreateTexture(nil, "ARTWORK")
                    abTex:SetPoint("TOPLEFT",     ab, "TOPLEFT",     1, -1)
                    abTex:SetPoint("BOTTOMRIGHT", ab, "BOTTOMRIGHT", -1,  1)
                    ab:Hide()
                    row._actionBtn = ab
                    row._actionTex = abTex

                    rows[i] = row
                end

                row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
                row._lbl:SetText(item.label or "")

                -- Action button visibility and state
                local hasAction = item.onAction ~= nil
                row._actionBtn:SetShown(hasAction)
                row._lbl:ClearAllPoints()
                row._lbl:SetPoint("LEFT", 8, 0)
                if hasAction then
                    row._lbl:SetPoint("RIGHT", row._actionBtn, "LEFT", -2, 0)
                    local isActive = item.actionActive
                    if isActive then
                        row._actionTex:SetTexture(item.actionIcon)
                        row._actionTex:SetVertexColor(T.color.accent[1], T.color.accent[2], T.color.accent[3], 1)
                    else
                        row._actionTex:SetTexture(item.actionIconInactive or item.actionIcon)
                        row._actionTex:SetVertexColor(1, 1, 1, 1)
                    end
                    local onAct = item.onAction
                    local actActive = item.actionActive
                    row._actionBtn:SetScript("OnClick", function() if onAct then onAct() end end)
                    row._actionBtn:SetScript("OnEnter", function()
                        row._actionTex:SetVertexColor(1, 1, 1, 1)
                    end)
                    row._actionBtn:SetScript("OnLeave", function()
                        if actActive then
                            row._actionTex:SetVertexColor(T.color.accent[1], T.color.accent[2], T.color.accent[3], 1)
                        else
                            row._actionTex:SetVertexColor(1, 1, 1, 1)
                        end
                    end)
                else
                    row._lbl:SetPoint("RIGHT", -4, 0)
                end

                local isSel = item.id == selectedId
                T:Tint(row._bg, isSel and T.color.listSel or T.color.listItem)
                if isSel then
                    row._lbl:SetTextColor(T.color.textAccent[1], T.color.textAccent[2], T.color.textAccent[3], 1)
                else
                    row._lbl:SetTextColor(T.color.text[1], T.color.text[2], T.color.text[3], 1)
                end

                row:SetScript("OnEnter", function()
                    if item.id ~= selectedId then
                        T:Tint(row._bg, T.color.listHover)
                    end
                end)
                row:SetScript("OnLeave", function()
                    T:Tint(row._bg, item.id == selectedId and T.color.listSel or T.color.listItem)
                end)
                row:SetScript("OnClick", function()
                    if onSelect then onSelect(item.id, item) end
                end)
                row:Show()
            end
        end
    end

    return outer
end

-- ---------------------------------------------------------------------------
-- TabBar
-- tabs: { { id = "id", label = "Label" }, ... }
-- Returns: tabBar frame + a Show(id) function to activate a tab
-- ---------------------------------------------------------------------------
function UI.TabBar(parent, tabs, width, onSwitch)
    local h      = T.size.tabH
    local tabW   = math.floor(width / #tabs)
    local bar    = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, h)

    local buttons = {}
    local active  = nil

    local function Activate(id)
        active = id
        for _, btn in pairs(buttons) do
            local isSel = btn._id == id
            btn._underline:SetShown(isSel)
            if isSel then
                btn._lbl:SetTextColor(T.color.textAccent[1], T.color.textAccent[2], T.color.textAccent[3], 1)
                btn:SetBackdropColor(T.color.panel[1], T.color.panel[2], T.color.panel[3], 1)
            else
                btn._lbl:SetTextColor(T.color.textDim[1], T.color.textDim[2], T.color.textDim[3], 1)
                btn:SetBackdropColor(T.color.header[1], T.color.header[2], T.color.header[3], 1)
            end
        end
        if onSwitch then onSwitch(id) end
    end

    for i, tab in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, bar, "BackdropTemplate")
        btn:SetSize(tabW, h)
        btn:SetPoint("TOPLEFT", (i - 1) * tabW, 0)
        T:Apply(btn, T.color.header, T.color.border)
        btn._id = tab.id

        local lbl = btn:CreateFontString(nil, "OVERLAY")
        T:Font(lbl, T.font.label, T.color.textDim)
        lbl:SetText(tab.label)
        lbl:SetPoint("CENTER")
        btn._lbl = lbl

        -- Active underline
        local ul = btn:CreateTexture(nil, "OVERLAY")
        ul:SetTexture(T.WHITE)
        ul:SetHeight(2)
        ul:SetPoint("BOTTOMLEFT", 4, 0)
        ul:SetPoint("BOTTOMRIGHT", -4, 0)
        T:Tint(ul, T.color.accent)
        ul:Hide()
        btn._underline = ul

        btn:SetScript("OnClick", function() Activate(tab.id) end)
        btn:SetScript("OnEnter", function()
            if btn._id ~= active then
                lbl:SetTextColor(T.color.text[1], T.color.text[2], T.color.text[3], 1)
            end
        end)
        btn:SetScript("OnLeave", function()
            if btn._id ~= active then
                lbl:SetTextColor(T.color.textDim[1], T.color.textDim[2], T.color.textDim[3], 1)
            end
        end)

        buttons[tab.id] = btn
    end

    -- Activate first tab by default
    if tabs[1] then Activate(tabs[1].id) end

    bar.Activate = Activate
    return bar
end
