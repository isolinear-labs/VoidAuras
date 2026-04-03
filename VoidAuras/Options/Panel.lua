-- =============================================================================
-- Options/Panel.lua
-- Main configuration window. Opens with /va or /voidauras.
--
-- Layout:
--   ┌─ Header ─────────────────────────────────────────────────────────────┐
--   ├─ Top Nav: [Auras] [Debug] ───────────────────────────────────────────┤
--   │  ┌─ Auras view ─────────────────────────────────────────────────────┤
--   │  │  Left: aura list + add/del  │  Right: name + [Trigger][Display]  │
--   │  └──────────────────────────────────────────────────────────────────┤
--   │  ┌─ Debug view (full width, hidden by default) ──────────────────── ┤
--   │  └──────────────────────────────────────────────────────────────────┤
--   └─ Footer: global settings ────────────────────────────────────────────┘
-- =============================================================================

local _, VA = ...
local T  = VA.Theme
local UI = VA.UI

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local PAD       = T.size.pad
local PAD_SM    = T.size.padSm
local W         = T.size.panelW
local H         = T.size.panelH
local HDR_H     = T.size.headerH
local FTR_H     = T.size.footerH     -- left-panel add/del footer
local LIST_W    = T.size.listW
local TOP_NAV_H = 28
local GFOOTER_H = 30
local CONTENT_H = H - HDR_H - TOP_NAV_H - GFOOTER_H

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function GenID()
    return "va_" .. time() .. "_" .. math.random(100000, 999999)
end

local function GetAuras()
    return VA.db and VA.db.global and VA.db.global.auras or {}
end

local function GetAuraDef(id)
    return GetAuras()[id]
end

local function SaveAuraDef(def)
    GetAuras()[def.id] = def
    VA.Events:Fire(VA.E.CONFIG_CHANGED, def.id)
end

local function DeleteAuraDef(id)
    GetAuras()[id] = nil
    VA.Events:Fire(VA.E.DISPLAY_HIDE, id)
end

local function NewAuraDef()
    local id = GenID()
    return {
        id      = id,
        name    = "New Aura",
        enabled = true,
        trigger = {
            type           = "aura",
            spellId        = 0,
            unit           = "player",
            filter         = "HELPFUL",
            isPrivate      = false,
            loadWhen       = "always",
            missing        = false,
            onlyOnCooldown = false,
        },
        display = {
            type         = "icon",
            width        = 40,
            height       = 40,
            point        = "CENTER",
            relPoint     = "CENTER",
            x            = 0,
            y            = 0,
            showCooldown = true,
            showCount    = true,
            showTimer    = true,
            -- Text display settings
            fontPath     = "Fonts\\FRIZQT__.TTF",
            fontSize     = 14,
            fontColor    = { 1, 1, 1, 1 },
            fontBold     = false,
            fontOutline  = true,
            borderColor  = { 0, 0, 0, 1 },
            template     = "{name} {timer}",
            -- Glow
            showGlow     = false,
            glowColor    = { 1, 0.8, 0, 1 },
        },
    }
end

-- ---------------------------------------------------------------------------
-- Private aura auto-detection
-- Returns: status ("private"|"normal"|"unknown"|"none"), hint string
-- ---------------------------------------------------------------------------
local function DetectPrivateStatus(spellId)
    spellId = tonumber(spellId)
    if not spellId or spellId == 0 then
        return "none", "Enter a Spell ID above"
    end

    -- Live: currently active as a private aura on the player?
    if VA.AuraTrigger and VA.AuraTrigger.state then
        local ps = VA.AuraTrigger.state["player"]
        if ps and ps.private and ps.private[spellId] then
            return "private", "Private aura — currently active"
        end
    end

    -- History: encountered as private in a previous session
    if VA.db and VA.db.global and VA.db.global.knownPrivateSpells then
        if VA.db.global.knownPrivateSpells[spellId] then
            return "private", "Private aura — seen before"
        end
    end

    -- Live: currently active as a normal aura on the player?
    if VA.AuraTrigger and VA.AuraTrigger.state then
        local ps = VA.AuraTrigger.state["player"]
        if ps then
            for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
                for _, aura in pairs(ps[filter] or {}) do
                    if aura.spellId == spellId then
                        return "normal", "Standard aura — currently active"
                    end
                end
            end
        end
    end

    return "unknown", "Not yet seen — will auto-detect on first encounter"
end

-- ---------------------------------------------------------------------------
-- Module-level state
-- ---------------------------------------------------------------------------
local panel      = nil
local selId      = nil
local previewedId = nil
local soloMode   = false   -- when true, only the selected aura's display is visible
-- Suppresses onChange-triggered saves while LoadEditor is populating widgets
local _loading   = false

local listWidget   = nil
local rightFrame   = nil
local triggerFrame = nil
local displayFrame = nil

-- Forward decls (defined inside BuildPanel, used across closures)
local RefreshList    = function() end
local LoadEditor     = function() end
local RebuildLog     = function() end
local RebuildConsole = function() end
local RebuildScan    = function() end
local FlashSaved     = function() end   -- defined inside BuildPanel after saveBar
local TogglePreview  = function() end
local ApplySoloMode  = function() end

-- ---------------------------------------------------------------------------
-- Selection indicator — animated dashed border around the selected aura frame
-- ---------------------------------------------------------------------------
local selIndicator = nil  -- created lazily on first use

local function UpdateSelectionIndicator()
    -- Build the marching-ants frame on first call (needs WoW API, so not at file-scope)
    if not selIndicator then
        local THICK = 2
        local DASH  = 8    -- dash length (px)
        local GAP   = 8    -- gap between dashes (px)
        local STEP  = DASH + GAP   -- = 16
        local SPEED = 60   -- px / sec
        local MAX_D = 30   -- max dash textures per edge

        local f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("MEDIUM")
        f:SetFrameLevel(200)
        f:Hide()

        -- 4 groups: 1=top(L→R), 2=right(T→B), 3=bottom(R→L), 4=left(B→T)
        local eg = {}
        for side = 1, 4 do
            eg[side] = {}
            for j = 1, MAX_D do
                local t = f:CreateTexture(nil, "OVERLAY")
                t:SetTexture(T.WHITE)
                t:SetVertexColor(1, 1, 1, 1)
                t:Hide()
                eg[side][j] = t
            end
        end

        local elapsed = 0
        f:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            local w = f:GetWidth()
            local h = f:GetHeight()
            if w <= 4 or h <= 4 then return end

            -- Phase each edge so dashes march clockwise around the border
            local base = elapsed * SPEED
            local off1 = base % STEP
            local off2 = (base + w)         % STEP
            local off3 = (base + w + h)     % STEP
            local off4 = (base + 2*w + h)   % STEP

            -- top: L→R
            local g, pos, i = eg[1], off1, 1
            while pos < w and i <= MAX_D do
                local len = math.min(DASH, w - pos)
                g[i]:Show(); g[i]:ClearAllPoints()
                g[i]:SetPoint("TOPLEFT", f, "TOPLEFT", pos, 0)
                g[i]:SetSize(len, THICK)
                i, pos = i+1, pos+STEP
            end
            while i <= MAX_D do g[i]:Hide(); i=i+1 end

            -- right: T→B
            g, pos, i = eg[2], off2, 1
            while pos < h and i <= MAX_D do
                local len = math.min(DASH, h - pos)
                g[i]:Show(); g[i]:ClearAllPoints()
                g[i]:SetPoint("TOPLEFT", f, "TOPRIGHT", -THICK, -pos)
                g[i]:SetSize(THICK, len)
                i, pos = i+1, pos+STEP
            end
            while i <= MAX_D do g[i]:Hide(); i=i+1 end

            -- bottom: R→L (pos = distance from right edge)
            g, pos, i = eg[3], off3, 1
            while pos < w and i <= MAX_D do
                local len = math.min(DASH, w - pos)
                g[i]:Show(); g[i]:ClearAllPoints()
                g[i]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pos, -(h - THICK))
                g[i]:SetSize(len, THICK)
                i, pos = i+1, pos+STEP
            end
            while i <= MAX_D do g[i]:Hide(); i=i+1 end

            -- left: B→T (pos = distance from bottom edge)
            g, pos, i = eg[4], off4, 1
            while pos < h and i <= MAX_D do
                local len = math.min(DASH, h - pos)
                g[i]:Show(); g[i]:ClearAllPoints()
                g[i]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, pos)
                g[i]:SetSize(THICK, len)
                i, pos = i+1, pos+STEP
            end
            while i <= MAX_D do g[i]:Hide(); i=i+1 end
        end)
        selIndicator = f
    end

    local ind = selIndicator
    if not selId then ind:Hide() return end
    local mgr = VA.DisplayManager
    if not mgr then ind:Hide() return end
    local inst = mgr.instances[selId]
    if not inst or not inst.frame then ind:Hide() return end
    ind:ClearAllPoints()
    ind:SetPoint("TOPLEFT",     inst.frame, "TOPLEFT",     -3,  3)
    ind:SetPoint("BOTTOMRIGHT", inst.frame, "BOTTOMRIGHT",  3, -3)
    ind:Show()
end

-- ---------------------------------------------------------------------------
-- BuildPanel
-- ---------------------------------------------------------------------------
local function BuildPanel()

    -- -----------------------------------------------------------------------
    -- Root window
    -- -----------------------------------------------------------------------
    local win = CreateFrame("Frame", "VoidAurasPanel", UIParent, "BackdropTemplate")
    win:SetSize(W, H)
    win:SetPoint("CENTER")
    win:SetFrameStrata("HIGH")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetClampedToScreen(true)
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop",  win.StopMovingOrSizing)
    T:Apply(win, T.color.bg, T.color.border)
    win:Hide()

    -- -----------------------------------------------------------------------
    -- Header
    -- -----------------------------------------------------------------------
    local hdr = CreateFrame("Frame", nil, win, "BackdropTemplate")
    hdr:SetPoint("TOPLEFT")
    hdr:SetPoint("TOPRIGHT")
    hdr:SetHeight(HDR_H)
    T:Apply(hdr, T.color.header, T.color.borderHi)

    local sigil = hdr:CreateFontString(nil, "OVERLAY")
    T:Font(sigil, T.font.header, T.color.accent)
    sigil:SetText("*")
    sigil:SetPoint("LEFT", PAD, 0)

    local title = hdr:CreateFontString(nil, "OVERLAY")
    T:Font(title, T.font.header, T.color.textAccent)
    title:SetText("VoidAuras")
    title:SetPoint("LEFT", sigil, "RIGHT", 6, 0)

    local ver = hdr:CreateFontString(nil, "OVERLAY")
    T:Font(ver, T.font.small, T.color.textDim)
    ver:SetText("v" .. VA.version)
    ver:SetPoint("LEFT", title, "RIGHT", 6, -1)

    local closeBtn = CreateFrame("Button", nil, hdr, "BackdropTemplate")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", -PAD, 0)
    T:Apply(closeBtn, T.color.btnNormal, T.color.danger)
    local closeX = closeBtn:CreateFontString(nil, "OVERLAY")
    closeX:SetFont(T.font.body.path, 14, "OUTLINE")
    closeX:SetTextColor(T.color.danger[1], T.color.danger[2], T.color.danger[3], 1)
    closeX:SetText("X")
    closeX:SetPoint("CENTER")
    closeBtn:SetScript("OnClick", function() win:Hide() end)
    closeBtn:SetScript("OnEnter", function()
        closeBtn:SetBackdropColor(0.25, 0.04, 0.06, 1)
        closeX:SetTextColor(1, 0.4, 0.4, 1)
    end)
    closeBtn:SetScript("OnLeave", function()
        T:Apply(closeBtn, T.color.btnNormal, T.color.danger)
        closeX:SetTextColor(T.color.danger[1], T.color.danger[2], T.color.danger[3], 1)
    end)

    -- -----------------------------------------------------------------------
    -- Top navigation bar
    -- -----------------------------------------------------------------------
    local topNav = CreateFrame("Frame", nil, win, "BackdropTemplate")
    topNav:SetPoint("TOPLEFT",  0, -HDR_H)
    topNav:SetPoint("TOPRIGHT", 0, -HDR_H)
    topNav:SetHeight(TOP_NAV_H)
    T:Apply(topNav, T.color.panel, T.color.border)

    -- Views (shown/hidden by top nav)
    local aurasView = CreateFrame("Frame", nil, win)
    aurasView:SetPoint("TOPLEFT",    0, -(HDR_H + TOP_NAV_H))
    aurasView:SetPoint("BOTTOMRIGHT", 0, GFOOTER_H)
    aurasView:Show()

    local consoleView = CreateFrame("Frame", nil, win)
    consoleView:SetPoint("TOPLEFT",    0, -(HDR_H + TOP_NAV_H))
    consoleView:SetPoint("BOTTOMRIGHT", 0, GFOOTER_H)
    consoleView:Hide()

    local debugView = CreateFrame("Frame", nil, win)
    debugView:SetPoint("TOPLEFT",    0, -(HDR_H + TOP_NAV_H))
    debugView:SetPoint("BOTTOMRIGHT", 0, GFOOTER_H)
    debugView:Hide()

    local scanView = CreateFrame("Frame", nil, win)
    scanView:SetPoint("TOPLEFT",     0, -(HDR_H + TOP_NAV_H))
    scanView:SetPoint("BOTTOMRIGHT", 0, GFOOTER_H)
    scanView:Hide()

    -- Top nav tab bar
    local navDefs = {
        { id = "auras",   label = "Auras"   },
        { id = "scan",    label = "Scan"    },
        { id = "console", label = "Console" },
        { id = "debug",   label = "Debug"   },
    }
    local navBar = UI.TabBar(topNav, navDefs, W, function(id)
        aurasView:SetShown(id == "auras")
        scanView:SetShown(id == "scan")
        consoleView:SetShown(id == "console")
        debugView:SetShown(id == "debug")
        if id == "scan"    then RebuildScan()    end
        if id == "console" then RebuildConsole() end
        if id == "debug"   then RebuildLog()     end
    end)
    navBar:SetAllPoints(topNav)

    -- -----------------------------------------------------------------------
    -- Auras view: left panel
    -- -----------------------------------------------------------------------
    local left = CreateFrame("Frame", nil, aurasView, "BackdropTemplate")
    left:SetPoint("TOPLEFT")
    left:SetSize(LIST_W, CONTENT_H)
    T:Apply(left, T.color.panel, T.color.border)

    local listH = CONTENT_H - FTR_H - 2
    listWidget = UI.ScrollList(left, LIST_W - 2, listH)
    listWidget:SetPoint("TOPLEFT", 1, -1)

    -- -----------------------------------------------------------------------
    -- Preview toggle: show/hide the display frame for a specific aura id
    -- without affecting its real trigger state.
    -- -----------------------------------------------------------------------
    TogglePreview = function(id)
        local mgr = VA.DisplayManager
        -- Stop any currently active preview
        if previewedId then
            local prev = mgr and mgr.instances[previewedId]
            if prev then prev:StopPreview() end
        end
        if previewedId == id then
            -- Same id clicked again → toggle off
            previewedId = nil
        else
            previewedId = id
            local inst = mgr and mgr.instances[id]
            if inst then
                local def = GetAuraDef(id)
                local sid = def and def.trigger and def.trigger.spellId or 0
                local now = GetTime()
                local fakeAura = {
                    spellId        = sid,
                    icon           = sid ~= 0 and C_Spell.GetSpellTexture(sid) or nil,
                    count          = 3,         -- non-zero so Show Stack Count can demonstrate
                    applications   = 3,
                    duration       = 30,        -- non-zero so Show Cooldown Spiral can demonstrate
                    expirationTime = now + 30,
                    name           = sid ~= 0 and (C_Spell.GetSpellName(sid) or "Preview") or "Preview",
                }
                inst:Preview(fakeAura)
            end
        end
        RefreshList()
    end

    local addBtn = UI.Button(left, "+ Add", (LIST_W / 2) - PAD_SM - 1, T.size.btnH, function()
        local def = NewAuraDef()
        SaveAuraDef(def)
        selId = def.id
        RefreshList()
        LoadEditor(def.id)
    end)
    addBtn:SetPoint("BOTTOMLEFT", PAD_SM, PAD_SM)

    local delBtn = UI.DangerButton(left, "X Del", (LIST_W / 2) - PAD_SM - 1, T.size.btnH, function()
        if not selId then return end
        if previewedId == selId then
            local inst = VA.DisplayManager and VA.DisplayManager.instances[selId]
            if inst then inst:StopPreview() end
            previewedId = nil
        end
        DeleteAuraDef(selId)
        selId = nil
        RefreshList()
        if rightFrame then rightFrame:Hide() end
        UpdateSelectionIndicator()
    end)
    delBtn:SetPoint("BOTTOMRIGHT", -PAD_SM, PAD_SM)

    -- Vertical divider
    local divLine = aurasView:CreateTexture(nil, "ARTWORK")
    divLine:SetTexture(T.WHITE)
    divLine:SetWidth(1)
    divLine:SetPoint("TOPLEFT",    LIST_W, 0)
    divLine:SetPoint("BOTTOMLEFT", LIST_W, 0)
    T:Tint(divLine, T.color.border)

    -- -----------------------------------------------------------------------
    -- Auras view: right panel (per-aura editor)
    -- -----------------------------------------------------------------------
    rightFrame = CreateFrame("Frame", nil, aurasView)
    rightFrame:SetPoint("TOPLEFT",    LIST_W + 1, 0)
    rightFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    rightFrame:Hide()

    local rightW = W - LIST_W - 2

    -- Aura name input
    local nameInput = UI.TextInput(rightFrame, {
        label = "Name",
        value = "",
        width = rightW - PAD * 2,
    })
    nameInput:SetPoint("TOPLEFT", PAD, -PAD)
    nameInput.onChange = function(v)
        if not selId then return end
        local def = GetAuraDef(selId)
        if def then
            def.name = v
            SaveAuraDef(def)
            FlashSaved()
            RefreshList()
        end
    end

    -- Save bar (pinned to bottom of rightFrame)
    local saveBar = CreateFrame("Frame", nil, rightFrame, "BackdropTemplate")
    saveBar:SetHeight(32)
    saveBar:SetPoint("BOTTOMLEFT")
    saveBar:SetPoint("BOTTOMRIGHT")
    T:Apply(saveBar, T.color.header, T.color.border)

    local savedLbl = saveBar:CreateFontString(nil, "OVERLAY")
    T:Font(savedLbl, T.font.small, T.color.textDim)
    savedLbl:SetText("Auto-saved")
    savedLbl:SetPoint("LEFT", PAD, 0)
    savedLbl:SetAlpha(0)  -- hidden until a save fires

    local applyBtn = CreateFrame("Button", nil, saveBar, "BackdropTemplate")
    applyBtn:SetSize(110, 22)
    applyBtn:SetPoint("RIGHT", -PAD, 0)
    T:Apply(applyBtn, T.color.accentLo, T.color.accent)
    local applyLbl = applyBtn:CreateFontString(nil, "OVERLAY")
    T:Font(applyLbl, T.font.body, T.color.textAccent)
    applyLbl:SetText("Apply")
    applyLbl:SetPoint("CENTER")
    applyBtn:SetScript("OnEnter", function()
        applyBtn:SetBackdropColor(T.color.accent[1], T.color.accent[2], T.color.accent[3], 1)
    end)
    applyBtn:SetScript("OnLeave", function()
        T:Apply(applyBtn, T.color.accentLo, T.color.accent)
    end)

    -- Flash "Saved" label briefly after any save
    FlashSaved = function()
        savedLbl:SetAlpha(1)
        C_Timer.After(2, function() savedLbl:SetAlpha(0) end)
    end

    applyBtn:SetScript("OnClick", function()
        if not selId then return end
        local def = GetAuraDef(selId)
        if def then
            SaveAuraDef(def)
            FlashSaved()
        end
    end)

    -- Sub-tab bar (Trigger / Display)
    local subTabDefs = {
        { id = "trigger", label = "Trigger" },
        { id = "display", label = "Display" },
    }
    local subTabBar = UI.TabBar(rightFrame, subTabDefs, rightW, function(id)
        if triggerFrame then triggerFrame:SetShown(id == "trigger") end
        if displayFrame then displayFrame:SetShown(id == "display") end
    end)
    subTabBar:SetPoint("TOPLEFT", 0, -PAD - T.size.inputH - 20)

    local contentY = -(PAD + T.size.inputH + 20 + T.size.tabH + PAD_SM)

    -- -----------------------------------------------------------------------
    -- Trigger tab
    -- -----------------------------------------------------------------------
    triggerFrame = CreateFrame("ScrollFrame", nil, rightFrame)
    triggerFrame:SetPoint("TOPLEFT",     0, contentY)
    triggerFrame:SetPoint("BOTTOMRIGHT", 0, 32)
    triggerFrame:SetScript("OnMouseWheel", function(sf, d)
        sf:SetVerticalScroll(VA.Clamp(sf:GetVerticalScroll() - d * 30, 0, sf:GetVerticalScrollRange()))
    end)
    local triggerContent = CreateFrame("Frame", nil, triggerFrame)
    triggerContent:SetSize(rightW, 280)
    triggerFrame:SetScrollChild(triggerContent)

    local UNIT_OPTS = {
        { "player",  "Player"  },
        { "target",  "Target"  },
        { "focus",   "Focus"   },
        { "pet",     "Pet"     },
        { "party1",  "Party 1" },
        { "party2",  "Party 2" },
        { "party3",  "Party 3" },
        { "party4",  "Party 4" },
    }
    local FILTER_OPTS = {
        { "HELPFUL", "Buff (Helpful)"   },
        { "HARMFUL", "Debuff (Harmful)" },
    }
    local TYPE_OPTS = {
        { "aura",     "Aura (Buff / Debuff)" },
        -- Cooldown type hidden until VA.FEATURES.COOLDOWN is enabled.
        -- Cooldowns are currently private auras and not accessible via the
        -- normal SPELL_UPDATE_COOLDOWN / GetSpellCooldown path in WoW 12.x.
        VA.FEATURES.COOLDOWN and { "cooldown", "Cooldown" } or nil,
        { "resource", "Resource"              },
    }

    local trTypeDD = UI.Dropdown(triggerContent, {
        label   = "Trigger Type",
        value   = "aura",
        options = TYPE_OPTS,
        width   = 200,
    })
    trTypeDD:SetPoint("TOPLEFT", PAD, -PAD)

    local spellInput = UI.TextInput(triggerContent, {
        label   = "Spell ID",
        value   = "",
        width   = 160,
        numeric = true,
    })
    spellInput:SetPoint("TOPLEFT", PAD, -PAD - 44)

    local unitDD = UI.Dropdown(triggerContent, {
        label   = "Unit",
        value   = "player",
        options = UNIT_OPTS,
        width   = 160,
    })
    unitDD:SetPoint("LEFT", spellInput, "RIGHT", PAD, 0)
    unitDD:SetPoint("TOP",  spellInput, "TOP",   0,   0)

    local filterDD = UI.Dropdown(triggerContent, {
        label   = "Filter",
        value   = "HELPFUL",
        options = FILTER_OPTS,
        width   = 180,
    })
    filterDD:SetPoint("TOPLEFT", PAD, -PAD - 130)

    local LOAD_OPTS = {
        { "always", "Always"         },
        { "combat", "In Combat Only" },
        { "never",  "Never (Paused)" },
    }
    local loadWhenDD = UI.Dropdown(triggerContent, {
        label   = "Show When",
        value   = "always",
        options = LOAD_OPTS,
        width   = 180,
    })
    loadWhenDD:SetPoint("TOPLEFT", PAD, -PAD - 174)

    local missingCk = UI.Checkbox(triggerContent, "Show when buff is missing", false, nil)
    missingCk:SetPoint("TOPLEFT", PAD, -PAD - 222)

    local onlyOnCooldownCk = UI.Checkbox(triggerContent, "Only show when on cooldown", false, nil)
    onlyOnCooldownCk:SetPoint("TOPLEFT", PAD, -PAD - 174)

    -- -----------------------------------------------------------------------
    -- Private aura status badge
    -- Shown below the Spell ID input — auto-detects based on live state and
    -- historical data. Updates in real-time as auras are encountered.
    -- -----------------------------------------------------------------------
    local badge = CreateFrame("Frame", nil, triggerContent, "BackdropTemplate")
    -- Badge sits below spellInput row (label 18px + input 22px = 40px) + gap
    badge:SetSize(rightW - PAD * 2, 22)
    badge:SetPoint("TOPLEFT", PAD, -PAD - 44 - 40 - PAD_SM)
    T:Apply(badge, T.color.btnNormal, T.color.border)

    local badgeDot = badge:CreateFontString(nil, "OVERLAY")
    T:Font(badgeDot, T.font.label, T.color.textDim)
    badgeDot:SetPoint("LEFT", 6, 0)

    local badgeText = badge:CreateFontString(nil, "OVERLAY")
    T:Font(badgeText, T.font.label, T.color.textDim)
    badgeText:SetPoint("LEFT", badgeDot, "RIGHT", 5, 0)

    local function UpdateBadge(spellId)
        local status, hint = DetectPrivateStatus(spellId)
        if status == "private" then
            badgeDot:SetText("*")
            badgeDot:SetTextColor(T.color.accent[1], T.color.accent[2], T.color.accent[3], 1)
            badgeText:SetText(hint)
            badgeText:SetTextColor(T.color.textAccent[1], T.color.textAccent[2], T.color.textAccent[3], 1)
            badge:SetBackdropColor(0.12, 0.03, 0.20, 1)
            badge:SetBackdropBorderColor(T.color.accentLo[1], T.color.accentLo[2], T.color.accentLo[3], 1)
        elseif status == "normal" then
            badgeDot:SetText("o")
            badgeDot:SetTextColor(T.color.success[1], T.color.success[2], T.color.success[3], 1)
            badgeText:SetText(hint)
            badgeText:SetTextColor(T.color.text[1], T.color.text[2], T.color.text[3], 1)
            T:Apply(badge, T.color.btnNormal, T.color.border)
        elseif status == "unknown" then
            badgeDot:SetText("?")
            badgeDot:SetTextColor(T.color.warning[1], T.color.warning[2], T.color.warning[3], 1)
            badgeText:SetText(hint)
            badgeText:SetTextColor(T.color.textDim[1], T.color.textDim[2], T.color.textDim[3], 1)
            T:Apply(badge, T.color.btnNormal, T.color.border)
        else
            badgeDot:SetText("-")
            badgeDot:SetTextColor(T.color.textDisable[1], T.color.textDisable[2], T.color.textDisable[3], 1)
            badgeText:SetText(hint or "")
            badgeText:SetTextColor(T.color.textDisable[1], T.color.textDisable[2], T.color.textDisable[3], 1)
            T:Apply(badge, T.color.btnNormal, T.color.border)
        end
        return status
    end

    -- Show/hide trigger fields appropriate to the selected trigger type.
    local function UpdateTriggerTypeVis(ttype)
        local isAura     = ttype == "aura"
        local isCooldown = ttype == "cooldown"
        local isResource = ttype == "resource"
        spellInput:SetShown(isAura or isCooldown)
        unitDD:SetShown(isAura or isResource)
        filterDD:SetShown(isAura)
        missingCk:SetShown(isAura)
        badge:SetShown(isAura)
        onlyOnCooldownCk:SetShown(isCooldown)
    end

    -- Wire trigger widgets → SaveAuraDef on change
    local function SaveTrigger()
        if _loading or not selId then return end
        local def = GetAuraDef(selId)
        if not def then return end
        local ttype = trTypeDD:GetValue()
        def.trigger.type     = ttype
        def.trigger.loadWhen = loadWhenDD:GetValue()
        if ttype == "aura" then
            local sid = tonumber(spellInput:GetValue()) or 0
            local status = UpdateBadge(sid)
            def.trigger.spellId   = sid
            def.trigger.unit      = unitDD:GetValue()
            def.trigger.filter    = filterDD:GetValue()
            def.trigger.missing   = missingCk:GetValue()
            def.trigger.isPrivate = (status == "private")
        elseif ttype == "cooldown" then
            def.trigger.spellId        = tonumber(spellInput:GetValue()) or 0
            def.trigger.onlyOnCooldown = onlyOnCooldownCk:GetValue()
        elseif ttype == "resource" then
            def.trigger.unit = unitDD:GetValue()
        end
        SaveAuraDef(def)
        FlashSaved()
    end
    spellInput.onChange  = SaveTrigger
    trTypeDD.onChange    = function(v)
        UpdateTriggerTypeVis(v)
        SaveTrigger()
    end
    unitDD.onChange      = SaveTrigger
    filterDD.onChange    = SaveTrigger
    loadWhenDD.onChange  = SaveTrigger
    missingCk.onChange          = SaveTrigger
    onlyOnCooldownCk.onChange   = SaveTrigger

    -- Update badge in real-time when a new private spell is discovered
    VA.Events:On(VA.E.PRIVATE_SPELL_DISCOVERED, function(spellId)
        if not selId then return end
        local def = GetAuraDef(selId)
        if def and def.trigger.spellId == spellId then
            local status = UpdateBadge(spellId)
            def.trigger.isPrivate = (status == "private")
            SaveAuraDef(def)
        end
    end, "Panel_PrivateDiscover")

    -- -----------------------------------------------------------------------
    -- Display tab
    -- -----------------------------------------------------------------------
    displayFrame = CreateFrame("ScrollFrame", nil, rightFrame)
    displayFrame:SetPoint("TOPLEFT",     0, contentY)
    displayFrame:SetPoint("BOTTOMRIGHT", -(T.size.scrollbarW + PAD_SM), 32)
    displayFrame:SetScript("OnMouseWheel", function(sf, d)
        sf:SetVerticalScroll(VA.Clamp(sf:GetVerticalScroll() - d * 30, 0, sf:GetVerticalScrollRange()))
    end)
    displayFrame:Hide()
    local displayContent = CreateFrame("Frame", nil, displayFrame)
    displayContent:SetSize(rightW, 370)
    displayFrame:SetScrollChild(displayContent)

    -- Themed vertical scrollbar for the display tab
    local dispSB = CreateFrame("Slider", nil, rightFrame, "BackdropTemplate")
    dispSB:SetPoint("TOPLEFT",    displayFrame, "TOPRIGHT",    PAD_SM, 0)
    dispSB:SetPoint("BOTTOMLEFT", displayFrame, "BOTTOMRIGHT", PAD_SM, 0)
    dispSB:SetWidth(T.size.scrollbarW)
    dispSB:SetOrientation("VERTICAL")
    dispSB:SetMinMaxValues(0, 0)
    dispSB:SetValue(0)
    dispSB:Hide()
    T:Apply(dispSB, T.color.btnNormal, T.color.border)
    local dispSBThumb = dispSB:CreateTexture(nil, "OVERLAY")
    dispSBThumb:SetTexture(T.WHITE)
    T:Tint(dispSBThumb, T.color.accent)
    dispSBThumb:SetWidth(T.size.scrollbarW - 4)
    dispSB:SetThumbTexture(dispSBThumb)

    displayFrame:HookScript("OnShow", function(sf)
        if sf:GetVerticalScrollRange() > 0 then dispSB:Show() end
    end)
    displayFrame:HookScript("OnHide", function() dispSB:Hide() end)
    displayFrame:SetScript("OnScrollRangeChanged", function(sf, _, yRange)
        local max = yRange or sf:GetVerticalScrollRange()
        if max <= 0 then
            dispSB:SetMinMaxValues(0, 0); dispSB:Hide()
        else
            dispSB:SetMinMaxValues(0, max)
            if sf:IsShown() then dispSB:Show() end
        end
    end)
    displayFrame:SetScript("OnVerticalScroll", function(_, offset)
        dispSB._upd = true; dispSB:SetValue(offset); dispSB._upd = false
    end)
    dispSB:SetScript("OnValueChanged", function(self, val)
        if not self._upd then displayFrame:SetVerticalScroll(val) end
    end)

    local DISP_OPTS = {
        { "icon", "Icon" },
        { "bar",  "Bar"  },
        { "text", "Text" },
    }

    local dispTypeDD = UI.Dropdown(displayContent, {
        label   = "Display Type",
        value   = "icon",
        options = DISP_OPTS,
        width   = 160,
    })
    dispTypeDD:SetPoint("TOPLEFT", PAD, -PAD)

    local widthSl = UI.Slider(displayContent, {
        label = "Width",  value = 40, min = 10, max = 400, step = 1, width = 200, hideLabel = true,
    })
    widthSl:SetPoint("TOPLEFT", PAD, -PAD - 52)

    local widthNum = CreateFrame("EditBox", nil, displayContent, "BackdropTemplate")
    widthNum:SetSize(46, 20)
    widthNum:SetPoint("BOTTOMLEFT", widthSl, "BOTTOMRIGHT", 4, 0)
    T:Apply(widthNum, T.color.btnNormal, T.color.border)
    widthNum:SetFont(T.font.body.path, T.font.body.size, T.font.body.flags)
    widthNum:SetTextColor(T.color.text[1], T.color.text[2], T.color.text[3], 1)
    widthNum:SetTextInsets(4, 4, 0, 0)
    widthNum:SetNumeric(true)
    widthNum:SetMaxLetters(4)
    widthNum:SetAutoFocus(false)
    widthNum:SetText("40")
    widthNum:SetScript("OnEnterPressed", function(self)
        local v = VA.Clamp(tonumber(self:GetText()) or 40, 10, 400)
        widthSl:SetValue(v)
        self:ClearFocus()
    end)
    widthNum:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(math.floor(widthSl:GetValue() + 0.5)))
        self:ClearFocus()
    end)
    widthNum:SetScript("OnEditFocusLost", function(self)
        local v = VA.Clamp(tonumber(self:GetText()) or 40, 10, 400)
        widthSl:SetValue(v)
    end)

    local heightSl = UI.Slider(displayContent, {
        label = "Height", value = 40, min = 10, max = 400, step = 1, width = 200, hideLabel = true,
    })
    heightSl:SetPoint("TOPLEFT", PAD, -PAD - 96)

    local heightNum = CreateFrame("EditBox", nil, displayContent, "BackdropTemplate")
    heightNum:SetSize(46, 20)
    heightNum:SetPoint("BOTTOMLEFT", heightSl, "BOTTOMRIGHT", 4, 0)
    T:Apply(heightNum, T.color.btnNormal, T.color.border)
    heightNum:SetFont(T.font.body.path, T.font.body.size, T.font.body.flags)
    heightNum:SetTextColor(T.color.text[1], T.color.text[2], T.color.text[3], 1)
    heightNum:SetTextInsets(4, 4, 0, 0)
    heightNum:SetNumeric(true)
    heightNum:SetMaxLetters(4)
    heightNum:SetAutoFocus(false)
    heightNum:SetText("40")
    heightNum:SetScript("OnEnterPressed", function(self)
        local v = VA.Clamp(tonumber(self:GetText()) or 40, 10, 400)
        heightSl:SetValue(v)
        self:ClearFocus()
    end)
    heightNum:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(math.floor(heightSl:GetValue() + 0.5)))
        self:ClearFocus()
    end)
    heightNum:SetScript("OnEditFocusLost", function(self)
        local v = VA.Clamp(tonumber(self:GetText()) or 40, 10, 400)
        heightSl:SetValue(v)
    end)

    -- -----------------------------------------------------------------------
    -- Icon / Bar specific options
    -- -----------------------------------------------------------------------
    local iconBarOpts = CreateFrame("Frame", nil, displayContent)
    iconBarOpts:SetPoint("TOPLEFT", PAD, -PAD - 148)
    iconBarOpts:SetSize(rightW - PAD * 2, 96)

    local showCooldownCk = UI.Checkbox(iconBarOpts, "Show Cooldown Spiral", true, nil)
    showCooldownCk:SetPoint("TOPLEFT", 0, 0)
    local showCountCk = UI.Checkbox(iconBarOpts, "Show Stack Count", true, nil)
    showCountCk:SetPoint("TOPLEFT", 0, -24)
    local showTimerCk = UI.Checkbox(iconBarOpts, "Show Timer", true, nil)
    showTimerCk:SetPoint("TOPLEFT", 0, -48)
    local showGlowCk = UI.Checkbox(iconBarOpts, "Glow", false, nil)
    showGlowCk:SetPoint("TOPLEFT", 0, -72)
    -- SW_X: x offset within iconBarOpts that aligns swatches with the width/height
    -- number boxes (slider width 200 + 4px gap = 204).
    local SW_X = 204
    local glowColorSwatch = UI.ColorSwatch(iconBarOpts, { r = 1, g = 0.8, b = 0, a = 1 })
    -- Default icon position: centered on Glow row (y=-72, checkbox 14px → center=-79 → swatch top=-68)
    glowColorSwatch:SetPoint("TOPLEFT", iconBarOpts, "TOPLEFT", SW_X, -68)

    local barColorLabel = iconBarOpts:CreateFontString(nil, "OVERLAY")
    T:Font(barColorLabel, T.font.label, T.color.textDim)
    barColorLabel:SetText("Bar Color")
    barColorLabel:SetPoint("TOPLEFT", 0, -4)
    barColorLabel:Hide()
    local barColorSwatch = UI.ColorSwatch(iconBarOpts, { r = 0.55, g = 0.15, b = 0.90, a = 0.70 })
    barColorSwatch:SetPoint("TOPLEFT", iconBarOpts, "TOPLEFT", SW_X, 0)
    barColorSwatch:Hide()

    -- -----------------------------------------------------------------------
    -- Text-specific options (hidden unless display type = "text")
    -- -----------------------------------------------------------------------
    local textOpts = CreateFrame("Frame", nil, displayContent)
    textOpts:SetPoint("TOPLEFT", PAD, -PAD - 148)
    textOpts:SetSize(rightW - PAD * 2, 270)
    textOpts:Hide()

    local FONT_OPTS = {
        { "Fonts\\FRIZQT__.TTF", "Default (Friz)" },
        { "Fonts\\MORPHEUS.TTF", "Morpheus"        },
        { "Fonts\\ARIALN.TTF",   "Arial Narrow"    },
        { "Fonts\\skurri.ttf",   "Skurri"          },
    }
    local templateTI = UI.TextInput(textOpts, {
        label = "Template", value = "{name} {timer}", width = 200,
    })
    templateTI:SetPoint("TOPLEFT", 0, 0)

    local fontDD = UI.Dropdown(textOpts, {
        label = "Font", value = "Fonts\\FRIZQT__.TTF", options = FONT_OPTS, width = 200,
    })
    fontDD:SetPoint("TOPLEFT", 0, -48)

    local fontSizeSl = UI.Slider(textOpts, {
        label = "Font Size", value = 14, min = 8, max = 48, step = 1, width = 200,
    })
    fontSizeSl:SetPoint("TOPLEFT", 0, -96)

    local fontColorLabel = textOpts:CreateFontString(nil, "OVERLAY")
    T:Font(fontColorLabel, T.font.label, T.color.textDim)
    fontColorLabel:SetText("Font Color")
    fontColorLabel:SetPoint("TOPLEFT", 0, -148)
    local fontColorSwatch = UI.ColorSwatch(textOpts, { r = 1, g = 1, b = 1, a = 1 })
    fontColorSwatch:SetPoint("TOPLEFT", SW_X, -144)

    local boldCk = UI.Checkbox(textOpts, "Bold", false, nil)
    boldCk:SetPoint("TOPLEFT", 0, -174)

    local outlineCk = UI.Checkbox(textOpts, "Outline", true, nil)
    outlineCk:SetPoint("LEFT", boldCk, "RIGHT", 48, 0)

    local borderColorLabel = textOpts:CreateFontString(nil, "OVERLAY")
    T:Font(borderColorLabel, T.font.label, T.color.textDim)
    borderColorLabel:SetText("Border Color")
    borderColorLabel:SetPoint("TOPLEFT", 0, -200)
    local borderColorSwatch = UI.ColorSwatch(textOpts, { r = 0, g = 0, b = 0, a = 1 })
    borderColorSwatch:SetPoint("TOPLEFT", SW_X, -196)

    -- Show correct sub-options for the chosen display type
    local function UpdateDispTypeVis(dtype)
        local isText = dtype == "text"
        local isBar  = dtype == "bar"
        widthSl:SetShown(not isText)
        widthNum:SetShown(not isText)
        heightSl:SetShown(not isText)
        heightNum:SetShown(not isText)
        iconBarOpts:SetShown(not isText)
        showCooldownCk:SetShown(not isBar)
        showCountCk:SetShown(not isBar)
        barColorLabel:SetShown(isBar)
        barColorSwatch:SetShown(isBar)
        -- For bar type: Bar Color fills the gap left by the two hidden checkboxes,
        -- then Show Timer and Glow shift up to follow it.
        if isBar then
            barColorLabel:ClearAllPoints()
            barColorLabel:SetPoint("TOPLEFT", iconBarOpts, "TOPLEFT", 0, -4)
            barColorSwatch:ClearAllPoints()
            barColorSwatch:SetPoint("TOPLEFT", iconBarOpts, "TOPLEFT", SW_X, 0)
            showTimerCk:ClearAllPoints()
            showTimerCk:SetPoint("TOPLEFT", iconBarOpts, "TOPLEFT", 0, -24)
            showGlowCk:ClearAllPoints()
            showGlowCk:SetPoint("TOPLEFT", iconBarOpts, "TOPLEFT", 0, -48)
            -- Glow swatch: centered on row at y=-48 (checkbox center=-55, swatch top=-44)
            glowColorSwatch:ClearAllPoints()
            glowColorSwatch:SetPoint("TOPLEFT", iconBarOpts, "TOPLEFT", SW_X, -44)
        else
            showTimerCk:ClearAllPoints()
            showTimerCk:SetPoint("TOPLEFT", iconBarOpts, "TOPLEFT", 0, -48)
            showGlowCk:ClearAllPoints()
            showGlowCk:SetPoint("TOPLEFT", iconBarOpts, "TOPLEFT", 0, -72)
            -- Glow swatch: centered on row at y=-72 (checkbox center=-79, swatch top=-68)
            glowColorSwatch:ClearAllPoints()
            glowColorSwatch:SetPoint("TOPLEFT", iconBarOpts, "TOPLEFT", SW_X, -68)
        end
        textOpts:ClearAllPoints()
        if isText then
            textOpts:SetPoint("TOPLEFT", PAD, -PAD - 52)
        else
            textOpts:SetPoint("TOPLEFT", PAD, -PAD - 148)
        end
        textOpts:SetShown(isText)
    end
    UpdateDispTypeVis("icon")

    local function SaveDisplay()
        if _loading or not selId then return end
        local def = GetAuraDef(selId)
        if not def then return end
        local dtype = dispTypeDD:GetValue()
        def.display.type         = dtype
        def.display.width        = math.floor(widthSl:GetValue() + 0.5)
        def.display.height       = math.floor(heightSl:GetValue() + 0.5)
        def.display.showCooldown = showCooldownCk:GetValue()
        def.display.showCount    = showCountCk:GetValue()
        def.display.showTimer    = showTimerCk:GetValue()
        def.display.showGlow     = showGlowCk:GetValue()
        local gr, gg, gb, ga     = glowColorSwatch:GetValue()
        def.display.glowColor    = { gr, gg, gb, ga }
        local bcr, bcg, bcb, bca = barColorSwatch:GetValue()
        def.display.barColor     = { bcr, bcg, bcb, bca }
        def.display.fontPath     = fontDD:GetValue()
        def.display.fontSize     = math.floor(fontSizeSl:GetValue() + 0.5)
        local fr, fg, fb, fa     = fontColorSwatch:GetValue()
        def.display.fontColor    = { fr, fg, fb, fa }
        def.display.fontBold     = boldCk:GetValue()
        def.display.fontOutline  = outlineCk:GetValue()
        local br, bg, bb, ba     = borderColorSwatch:GetValue()
        def.display.borderColor  = { br, bg, bb, ba }
        def.display.template     = templateTI:GetValue()
        SaveAuraDef(def)
        FlashSaved()
    end
    dispTypeDD.onChange = function(v)
        UpdateDispTypeVis(v)
        SaveDisplay()
    end
    widthSl.onChange        = function(v)
        if not _loading then widthNum:SetText(tostring(math.floor(v + 0.5))) end
        SaveDisplay()
    end
    heightSl.onChange       = function(v)
        if not _loading then heightNum:SetText(tostring(math.floor(v + 0.5))) end
        SaveDisplay()
    end
    showCooldownCk.onChange  = SaveDisplay
    showCountCk.onChange     = SaveDisplay
    showTimerCk.onChange     = SaveDisplay
    showGlowCk.onChange      = SaveDisplay
    glowColorSwatch.onChange = SaveDisplay
    barColorSwatch.onChange  = SaveDisplay
    fontDD.onChange              = SaveDisplay
    fontSizeSl.onChange          = SaveDisplay
    fontColorSwatch.onChange     = SaveDisplay
    boldCk.onChange              = SaveDisplay
    outlineCk.onChange           = SaveDisplay
    borderColorSwatch.onChange   = SaveDisplay
    templateTI.onChange          = SaveDisplay

    -- -----------------------------------------------------------------------
    -- LoadEditor
    -- -----------------------------------------------------------------------
    function LoadEditor(id)
        local def = GetAuraDef(id)
        if not def then rightFrame:Hide() return end
        selId    = id
        _loading = true
        rightFrame:Show()
        triggerFrame:SetVerticalScroll(0)
        displayFrame:SetVerticalScroll(0)

        nameInput:SetValue(def.name or "")

        local tr = def.trigger or {}
        local ttype = tr.type or "aura"
        trTypeDD:SetValue(ttype)
        spellInput:SetValue(tostring(tr.spellId or ""))
        unitDD:SetValue(tr.unit or "player")
        filterDD:SetValue(tr.filter or "HELPFUL")
        loadWhenDD:SetValue(tr.loadWhen or "always")
        missingCk:SetValue(tr.missing == true)
        onlyOnCooldownCk:SetValue(tr.onlyOnCooldown == true)
        UpdateBadge(tr.spellId or 0)
        UpdateTriggerTypeVis(ttype)

        local dp = def.display or {}
        local dtype = dp.type or "icon"
        dispTypeDD:SetValue(dtype)
        widthSl:SetValue(dp.width or 40)
        widthNum:SetText(tostring(dp.width or 40))
        heightSl:SetValue(dp.height or 40)
        heightNum:SetText(tostring(dp.height or 40))
        showCooldownCk:SetValue(dp.showCooldown ~= false)
        showCountCk:SetValue(dp.showCount ~= false)
        showTimerCk:SetValue(dp.showTimer ~= false)
        showGlowCk:SetValue(dp.showGlow == true)
        local gc = dp.glowColor or { 1, 0.8, 0, 1 }
        glowColorSwatch:SetValue(gc[1], gc[2], gc[3], gc[4] or 1)
        local bcc = dp.barColor or { 0.55, 0.15, 0.90, 0.70 }
        barColorSwatch:SetValue(bcc[1], bcc[2], bcc[3], bcc[4] or 0.70)
        fontDD:SetValue(dp.fontPath or "Fonts\\FRIZQT__.TTF")
        fontSizeSl:SetValue(dp.fontSize or 14)
        local fc = dp.fontColor or { 1, 1, 1, 1 }
        fontColorSwatch:SetValue(fc[1], fc[2], fc[3], fc[4] or 1)
        boldCk:SetValue(dp.fontBold == true)
        outlineCk:SetValue(dp.fontOutline ~= false)
        local bc = dp.borderColor or { 0, 0, 0, 1 }
        borderColorSwatch:SetValue(bc[1], bc[2], bc[3], bc[4] or 1)
        templateTI:SetValue(dp.template or "{name} {timer}")
        UpdateDispTypeVis(dtype)

        _loading = false
        subTabBar.Activate("trigger")
        UpdateSelectionIndicator()
        ApplySoloMode()

        -- Auto-preview with representative data so display settings are immediately testable
        local mgr = VA.DisplayManager
        if mgr then
            if previewedId and previewedId ~= id then
                local prevInst = mgr.instances[previewedId]
                if prevInst then prevInst:StopPreview() end
            end
            previewedId = id
            local inst = mgr.instances[id]
            if inst then
                local sid = (def.trigger and def.trigger.spellId) or 0
                local now = GetTime()
                inst:Preview({
                    spellId        = sid,
                    icon           = sid ~= 0 and C_Spell.GetSpellTexture(sid) or nil,
                    count          = 3,
                    applications   = 3,
                    duration       = 30,
                    expirationTime = now + 30,
                    name           = sid ~= 0 and (C_Spell.GetSpellName(sid) or "Preview") or "Preview",
                })
            end
            RefreshList()
        end
    end

    -- -----------------------------------------------------------------------
    -- RefreshList
    -- -----------------------------------------------------------------------
    function RefreshList()
        local items = {}
        for id, def in pairs(GetAuras()) do
            local capturedId = id
            tinsert(items, {
                id                 = id,
                label              = (def.enabled and "" or "|cff666666") .. (def.name or id),
                onAction           = function() TogglePreview(capturedId) end,
                actionActive       = previewedId == id,
                actionIcon         = "Interface\\AddOns\\VoidAuras\\Media\\void-eye.png",
                actionIconInactive = "Interface\\AddOns\\VoidAuras\\Media\\void-eye-closed.png",
            })
        end
        table.sort(items, function(a, b) return a.label < b.label end)
        listWidget:Refresh(items, function(id)
            selId = id
            LoadEditor(id)
            RefreshList()
        end, selId)
    end

    -- -----------------------------------------------------------------------
    -- Scan view — enumerate active auras with clickable spell IDs
    -- -----------------------------------------------------------------------
    local SCAN_ROW_H  = 22
    local SCAN_CAT_H  = 20
    local COPY_BOX_H  = 28
    local COPY_HINT_H = 16
    local SCAN_ID_COL = { 0.70, 0.50, 1.00, 1.00 }  -- void purple, matches SpellIDDisplay

    local scanBtn = UI.Button(scanView, "Scan Active Auras", 150, T.size.btnH, function()
        RebuildScan()
    end)
    scanBtn:SetPoint("TOPLEFT", PAD, -PAD_SM)

    local scanHint = scanView:CreateFontString(nil, "OVERLAY")
    T:Font(scanHint, T.font.small, T.color.textDim)
    scanHint:SetText("Click a row to copy its spell ID")
    scanHint:SetPoint("RIGHT",  -PAD, 0)
    scanHint:SetPoint("BOTTOM", scanBtn, "BOTTOM", 0, 0)

    -- Scroll frame — fills between the button and the copy bar
    local scanScroll = CreateFrame("ScrollFrame", nil, scanView, "BackdropTemplate")
    scanScroll:SetPoint("TOPLEFT",     PAD,  -PAD_SM - T.size.btnH - PAD_SM)
    scanScroll:SetPoint("BOTTOMRIGHT", -PAD,  COPY_BOX_H + COPY_HINT_H + PAD * 2)
    T:Apply(scanScroll, T.color.bg, T.color.border)
    scanScroll:SetScript("OnMouseWheel", function(sf, d)
        sf:SetVerticalScroll(VA.Clamp(sf:GetVerticalScroll() - d * SCAN_ROW_H * 3, 0, sf:GetVerticalScrollRange()))
    end)

    local scanContent = CreateFrame("Frame", nil, scanScroll)
    scanContent:SetWidth(W - PAD * 2 - 4)
    scanContent:SetHeight(1)
    scanScroll:SetScrollChild(scanContent)

    -- Copy bar at the bottom
    local scanCopyHintLabel = scanView:CreateFontString(nil, "OVERLAY")
    T:Font(scanCopyHintLabel, T.font.small, T.color.textDim)
    scanCopyHintLabel:SetText("Spell ID - press Ctrl+C after clicking a row")
    scanCopyHintLabel:SetPoint("BOTTOMLEFT", PAD, COPY_BOX_H + PAD + 3)

    local scanCopyBox = CreateFrame("EditBox", nil, scanView, "BackdropTemplate")
    scanCopyBox:SetPoint("BOTTOMLEFT",  PAD,  PAD)
    scanCopyBox:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    scanCopyBox:SetHeight(COPY_BOX_H)
    T:Apply(scanCopyBox, T.color.btnNormal, T.color.border)
    scanCopyBox:SetFont(T.font.mono.path, T.font.mono.size, T.font.mono.flags)
    scanCopyBox:SetTextColor(SCAN_ID_COL[1], SCAN_ID_COL[2], SCAN_ID_COL[3], 1)
    scanCopyBox:SetMultiLine(false)
    scanCopyBox:SetAutoFocus(false)
    scanCopyBox:SetTextInsets(6, 6, 0, 0)
    scanCopyBox:SetText("Click a row above to copy its spell ID here")
    scanCopyBox:SetScript("OnEscapePressed", function() scanCopyBox:ClearFocus() end)

    -- Row pool — we wipe and recreate on each scan
    local scanRows = {}

    local function ClearScanRows()
        for _, obj in ipairs(scanRows) do obj:Hide() end
        wipe(scanRows)
    end

    local function AddCategoryHeader(yOff, text)
        local fs = scanContent:CreateFontString(nil, "OVERLAY")
        T:Font(fs, T.font.label, T.color.accent)
        fs:SetText(text)
        fs:SetPoint("TOPLEFT",  6, yOff)
        fs:SetPoint("TOPRIGHT", -6, yOff)
        fs:SetJustifyH("LEFT")
        table.insert(scanRows, fs)
        return yOff - SCAN_CAT_H - 2
    end

    local function AddAuraRow(yOff, spellId, spellName)
        local row = CreateFrame("Button", nil, scanContent, "BackdropTemplate")
        row:SetPoint("TOPLEFT",  2, yOff)
        row:SetPoint("TOPRIGHT", -2, yOff)
        row:SetHeight(SCAN_ROW_H)
        T:Apply(row, T.color.listItem, T.color.border)

        local idLabel = row:CreateFontString(nil, "OVERLAY")
        T:Font(idLabel, T.font.label, SCAN_ID_COL)
        idLabel:SetText(tostring(spellId))
        idLabel:SetPoint("LEFT", 6, 0)
        idLabel:SetWidth(72)
        idLabel:SetJustifyH("LEFT")

        -- "Make into Aura" button on the far right
        local makeBtn = UI.Button(row, "Make into Aura", 108, SCAN_ROW_H - 4, function()
            local def = NewAuraDef()
            def.name              = spellName or "New Aura"
            def.trigger.spellId   = spellId
            SaveAuraDef(def)
            navBar.Activate("auras")
            RefreshList()
            LoadEditor(def.id)
        end)
        makeBtn:SetPoint("RIGHT", -4, 0)

        local nameLabel = row:CreateFontString(nil, "OVERLAY")
        T:Font(nameLabel, T.font.label, T.color.text)
        nameLabel:SetText(spellName or "Unknown")
        nameLabel:SetPoint("LEFT",  idLabel, "RIGHT", 6, 0)
        nameLabel:SetPoint("RIGHT", makeBtn, "LEFT",  -4, 0)
        nameLabel:SetJustifyH("LEFT")

        row:SetScript("OnEnter", function() T:Apply(row, T.color.listHover, T.color.borderHi) end)
        row:SetScript("OnLeave", function() T:Apply(row, T.color.listItem,  T.color.border)   end)
        row:SetScript("OnClick", function()
            scanCopyBox:SetText(tostring(spellId))
            scanCopyBox:SetFocus()
            scanCopyBox:HighlightText()
        end)

        table.insert(scanRows, row)
        return yOff - SCAN_ROW_H - 1
    end

    function RebuildScan()
        ClearScanRows()
        scanContent:SetHeight(1)
        scanScroll:SetVerticalScroll(0)

        local yOff   = -4
        local total  = 0

        local unitDefs = {
            { unit = "player", label = "Player"  },
            { unit = "target", label = "Target"  },
            { unit = "focus",  label = "Focus"   },
        }
        local filterDefs = {
            { filter = "HELPFUL", label = "Helpful (Buffs)"   },
            { filter = "HARMFUL", label = "Harmful (Debuffs)" },
        }

        for _, ud in ipairs(unitDefs) do
            if UnitExists(ud.unit) then
                for _, fd in ipairs(filterDefs) do
                    local auras = {}
                    local idx = 1
                    while true do
                        local data = C_UnitAuras.GetAuraDataByIndex(ud.unit, idx, fd.filter)
                        if not data then break end
                        table.insert(auras, data)
                        idx = idx + 1
                    end
                    if #auras > 0 then
                        local unitName = UnitName(ud.unit) or ud.unit
                        yOff = AddCategoryHeader(yOff, ud.label .. " (" .. unitName .. ")  —  " .. fd.label)
                        for _, a in ipairs(auras) do
                            yOff = AddAuraRow(yOff, a.spellId, a.name)
                            total = total + 1
                        end
                        yOff = yOff - 4  -- spacing between sections
                    end
                end
            end
        end

        if total == 0 then
            local empty = scanContent:CreateFontString(nil, "OVERLAY")
            T:Font(empty, T.font.body, T.color.textDim)
            empty:SetText("No auras found. Make sure a unit is targeted if scanning target/focus.")
            empty:SetPoint("TOPLEFT", 8, -12)
            empty:SetPoint("RIGHT",  -8, 0)
            empty:SetJustifyH("LEFT")
            empty:SetWordWrap(true)
            table.insert(scanRows, empty)
            yOff = yOff - 40
        end

        local contentH = math.max(-yOff + 4, 1)
        scanContent:SetHeight(contentH)
    end

    -- -----------------------------------------------------------------------
    -- Console view — state dump, fully selectable/copyable
    -- -----------------------------------------------------------------------
    local conAreaW = W - PAD * 2
    local conAreaH = CONTENT_H - T.size.btnH - PAD * 3

    local refreshConBtn = UI.Button(consoleView, "Refresh", 100, T.size.btnH, function()
        RebuildConsole()
    end)
    refreshConBtn:SetPoint("TOPLEFT", PAD, -PAD_SM)

    local clearConBtn = UI.DangerButton(consoleView, "Clear", 60, T.size.btnH, function()
        -- reassigned inside RebuildConsole closure
    end)
    clearConBtn:SetPoint("LEFT", refreshConBtn, "RIGHT", PAD_SM, 0)

    local conHint = consoleView:CreateFontString(nil, "OVERLAY")
    T:Font(conHint, T.font.small, T.color.textDim)
    conHint:SetText("Click inside > Ctrl+A > Ctrl+C to copy all")
    conHint:SetPoint("RIGHT", -PAD, 0)
    conHint:SetPoint("BOTTOM", refreshConBtn, "BOTTOM", 0, 0)

    -- Scroll frame + multiline EditBox
    local conScroll = CreateFrame("ScrollFrame", nil, consoleView, "BackdropTemplate")
    conScroll:SetSize(conAreaW, conAreaH)
    conScroll:SetPoint("TOPLEFT",  PAD, -PAD_SM - T.size.btnH - PAD_SM)
    T:Apply(conScroll, T.color.bg, T.color.border)
    conScroll:SetScript("OnMouseWheel", function(sf, d)
        sf:SetVerticalScroll(VA.Clamp(sf:GetVerticalScroll() - d * 30, 0, sf:GetVerticalScrollRange()))
    end)

    local conEdit = CreateFrame("EditBox", nil, conScroll)
    conEdit:SetWidth(conAreaW - 8)
    conEdit:SetHeight(conAreaH)           -- grows via SetHeight after text is set
    conEdit:SetMultiLine(true)
    conEdit:SetAutoFocus(false)
    conEdit:SetFont(T.font.mono.path, T.font.mono.size, T.font.mono.flags)
    conEdit:SetTextColor(T.color.text[1], T.color.text[2], T.color.text[3], 1)
    conEdit:SetTextInsets(6, 6, 4, 4)
    conEdit:SetScript("OnEscapePressed", function() conEdit:ClearFocus() end)
    conScroll:SetScrollChild(conEdit)

    -- Wire Clear button now that conEdit exists
    clearConBtn:SetScript("OnClick", function()
        conEdit:SetText("")
    end)

    function RebuildConsole()
        local cd = VA.CooldownTrigger
        local str = cd and cd:DumpString() or "(CooldownTrigger not loaded)"
        -- Size the edit box tall enough for the content so the scroll frame can scroll it
        local lineCount = 1
        for _ in str:gmatch("\n") do lineCount = lineCount + 1 end
        local lineH = T.font.mono.size + 2
        conEdit:SetHeight(math.max(lineCount * lineH + 8, conAreaH))
        conEdit:SetText(str)
        conScroll:SetVerticalScroll(0)
    end

    -- -----------------------------------------------------------------------
    -- Debug view (full width)
    -- -----------------------------------------------------------------------
    local dbgLabel = debugView:CreateFontString(nil, "OVERLAY")
    T:Font(dbgLabel, T.font.label, T.color.textDim)
    dbgLabel:SetText("Error Log")
    dbgLabel:SetPoint("TOPLEFT", PAD, -PAD)

    local clearBtn = UI.DangerButton(debugView, "Clear", 60, T.size.btnH, function()
        wipe(VA.errorLog)
        RebuildLog()
    end)
    clearBtn:SetPoint("TOPRIGHT", -PAD, -PAD_SM)

    -- Copy-to-clipboard EditBox (hidden, populated when a row is clicked)
    local copyBox = CreateFrame("EditBox", nil, debugView, "BackdropTemplate")
    copyBox:SetPoint("BOTTOMLEFT",  PAD,  PAD)
    copyBox:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    copyBox:SetHeight(28)
    T:Apply(copyBox, T.color.btnNormal, T.color.border)
    copyBox:SetFont(T.font.mono.path, T.font.mono.size, T.font.mono.flags)
    copyBox:SetTextColor(T.color.textDim[1], T.color.textDim[2], T.color.textDim[3], 1)
    copyBox:SetMultiLine(false)
    copyBox:SetAutoFocus(false)
    copyBox:SetTextInsets(4, 4, 0, 0)
    copyBox:SetText("Click a row to copy it here, then Ctrl+C")
    copyBox:SetScript("OnEscapePressed", function() copyBox:ClearFocus() end)

    local copyHint = debugView:CreateFontString(nil, "OVERLAY")
    T:Font(copyHint, T.font.small, T.color.textDim)
    copyHint:SetText("Click any row to select it for copying")
    copyHint:SetPoint("BOTTOMLEFT", copyBox, "TOPLEFT", 0, 3)

    -- Scrollable row list
    local ROW_H    = 20
    local logAreaH = CONTENT_H - T.size.btnH - PAD * 3 - 28 - 18 - PAD
    local logAreaW = W - PAD * 2

    local logScroll = CreateFrame("ScrollFrame", nil, debugView, "BackdropTemplate")
    logScroll:SetSize(logAreaW, logAreaH)
    logScroll:SetPoint("TOPLEFT",  PAD, -PAD - T.size.btnH - PAD)
    logScroll:SetPoint("BOTTOMRIGHT", -PAD, 28 + 18 + PAD * 2)
    T:Apply(logScroll, T.color.bg, T.color.border)

    local logContent = CreateFrame("Frame", nil, logScroll)
    logContent:SetWidth(logAreaW - 4)
    logContent:SetHeight(1)
    logScroll:SetScrollChild(logContent)

    logScroll:SetScript("OnMouseWheel", function(_, d)
        local cur = logScroll:GetVerticalScroll()
        local mx  = logScroll:GetVerticalScrollRange()
        logScroll:SetVerticalScroll(VA.Clamp(cur - d * ROW_H * 3, 0, mx))
    end)

    local logRows = {}

    function RebuildLog()
        local entries = {}
        for i = #VA.errorLog, 1, -1 do tinsert(entries, VA.errorLog[i]) end
        if #entries == 0 then entries = { "(no errors recorded)" } end

        logContent:SetHeight(math.max(#entries * ROW_H, 1))

        for i = 1, math.max(#entries, #logRows) do
            if i > #entries then
                if logRows[i] then logRows[i]:Hide() end
            else
                local row = logRows[i]
                if not row then
                    row = CreateFrame("Button", nil, logContent)
                    row:SetHeight(ROW_H)
                    local bg = row:CreateTexture(nil, "BACKGROUND")
                    bg:SetTexture(T.WHITE)
                    bg:SetAllPoints()
                    row._bg = bg
                    local fs = row:CreateFontString(nil, "OVERLAY")
                    fs:SetFont(T.font.mono.path, T.font.mono.size, T.font.mono.flags)
                    fs:SetTextColor(T.color.text[1], T.color.text[2], T.color.text[3], 1)
                    fs:SetPoint("LEFT", 4, 0)
                    fs:SetPoint("RIGHT", -4, 0)
                    fs:SetJustifyH("LEFT")
                    fs:SetWordWrap(false)
                    row._fs = fs
                    logRows[i] = row
                end
                row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
                row:SetWidth(logContent:GetWidth())
                row._fs:SetText(entries[i])
                T:Tint(row._bg, T.color.listItem)
                row:SetScript("OnEnter", function() T:Tint(row._bg, T.color.listHover) end)
                row:SetScript("OnLeave", function() T:Tint(row._bg, T.color.listItem)  end)
                local entry = entries[i]
                row:SetScript("OnClick", function()
                    copyBox:SetText(entry)
                    copyBox:SetFocus()
                    copyBox:HighlightText()
                end)
                row:Show()
            end
        end
        logScroll:SetVerticalScroll(0)
    end

    VA.Events:On(VA.E.ERROR_LOGGED, function()
        if debugView:IsShown() then RebuildLog() end
    end, "DebugPanel")

    -- -----------------------------------------------------------------------
    -- Global footer
    -- -----------------------------------------------------------------------
    local footer = CreateFrame("Frame", nil, win, "BackdropTemplate")
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(GFOOTER_H)
    T:Apply(footer, T.color.header, T.color.border)

    -- Solo mode: hide all display frames except the selected aura's.
    -- Restores visibility (based on inst.active) when turned off.
    ApplySoloMode = function()
        local mgr = VA.DisplayManager
        if not mgr then return end
        for id, inst in pairs(mgr.instances or {}) do
            if inst and inst.frame then
                if soloMode then
                    inst.frame:SetShown(id == selId)
                else
                    inst.frame:SetShown(inst.active == true or inst._previewing == true)
                end
            end
        end
    end

    local ICON_SIZE = GFOOTER_H - 8   -- 22px within 30px footer
    local TEX_OPEN   = "Interface\\AddOns\\VoidAuras\\Media\\void-eye.png"
    local TEX_CLOSED = "Interface\\AddOns\\VoidAuras\\Media\\void-eye-closed.png"

    local soloBtn = CreateFrame("Button", nil, footer)
    soloBtn:SetSize(ICON_SIZE, ICON_SIZE)
    soloBtn:SetPoint("LEFT", PAD, 0)

    local soloTex = soloBtn:CreateTexture(nil, "ARTWORK")
    soloTex:SetAllPoints()
    soloTex:SetTexture(TEX_OPEN)
    soloTex:SetVertexColor(1, 1, 1, 1)

    soloBtn:SetScript("OnClick", function()
        soloMode = not soloMode
        soloTex:SetTexture(soloMode and TEX_CLOSED or TEX_OPEN)
        ApplySoloMode()
    end)
    soloBtn:SetScript("OnEnter", function()
        soloTex:SetVertexColor(T.color.accent[1], T.color.accent[2], T.color.accent[3], 1)
        GameTooltip:SetOwner(soloBtn, "ANCHOR_TOP")
        GameTooltip:SetText(soloMode and "Show all auras" or "Focus selected aura", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    soloBtn:SetScript("OnLeave", function()
        soloTex:SetVertexColor(1, 1, 1, 1)
        GameTooltip:Hide()
    end)

    local spellIDCheck = UI.Checkbox(footer, "Show Spell IDs on tooltips", false, function(v)
        if VA.SpellIDDisplay then VA.SpellIDDisplay:SetEnabled(v) end
    end)
    spellIDCheck:SetPoint("LEFT", soloBtn, "RIGHT", PAD, 0)

    win:HookScript("OnShow", function()
        if VA.SpellIDDisplay then
            spellIDCheck:SetValue(VA.SpellIDDisplay:IsEnabled())
        end
        UpdateSelectionIndicator()
    end)

    win:HookScript("OnHide", function()
        if previewedId then
            local inst = VA.DisplayManager and VA.DisplayManager.instances[previewedId]
            if inst then inst:StopPreview() end
            previewedId = nil
        end
        if selIndicator then selIndicator:Hide() end
        if soloMode then
            soloMode = false
            soloTex:SetTexture(TEX_OPEN)
            ApplySoloMode()
        end
    end)

    -- Re-anchor indicator and refresh preview after CONFIG_CHANGED recreates the instance
    VA.Events:On(VA.E.CONFIG_CHANGED, function(id)
        if id ~= selId then return end
        -- Hide immediately so the indicator doesn't sit on a dead frame for one frame
        if selIndicator then selIndicator:Hide() end
        C_Timer.After(0, function()
            UpdateSelectionIndicator()
            -- Always refresh preview with fresh fake data when settings change
            if previewedId == id then
                local inst2 = VA.DisplayManager and VA.DisplayManager.instances[id]
                if inst2 then
                    local def2 = GetAuraDef(id)
                    local sid2 = def2 and def2.trigger and def2.trigger.spellId or 0
                    local now2 = GetTime()
                    inst2:Preview({
                        spellId        = sid2,
                        icon           = sid2 ~= 0 and C_Spell.GetSpellTexture(sid2) or nil,
                        count          = 3,
                        applications   = 3,
                        duration       = 30,
                        expirationTime = now2 + 30,
                        name           = sid2 ~= 0 and (C_Spell.GetSpellName(sid2) or "Preview") or "Preview",
                    })
                end
            end
        end)
    end, "Panel_SelIndicator")

    return win
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
local function GetPanel()
    if not panel then panel = BuildPanel() end
    return panel
end

function VA.TogglePanel()
    local p = GetPanel()
    if p:IsShown() then
        p:Hide()
    else
        RefreshList()
        p:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
SLASH_VOIDAURAS1 = "/voidauras"
SLASH_VOIDAURAS2 = "/va"
SlashCmdList["VOIDAURAS"] = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "debug" then
        VA.db.global.debug = not VA.db.global.debug
        VA:Print("Debug " .. (VA.db.global.debug and "ON" or "OFF"))
    elseif cmd == "cd" then
        if VA.CooldownTrigger then
            VA.CooldownTrigger:Dump()
        else
            VA:Print("CooldownTrigger not loaded")
        end
        -- Also refresh the Console tab if the panel is open
        RebuildConsole()
    else
        VA.TogglePanel()
    end
end
