-- =============================================================================
-- Options/Theme.lua
-- Single source of truth for all visual constants.
-- Every widget and display reads from here — restyling is a one-file change.
-- =============================================================================

local _, VA = ...

local T = {}
VA.Theme = T

-- ---------------------------------------------------------------------------
-- Colors  {r, g, b, a}
-- ---------------------------------------------------------------------------
T.color = {
    -- Backgrounds
    bg          = { 0.04, 0.00, 0.08, 0.96 },
    panel       = { 0.07, 0.02, 0.12, 1.00 },
    header      = { 0.05, 0.01, 0.09, 1.00 },

    -- Accent (void purple)
    accent      = { 0.55, 0.15, 0.90, 1.00 },
    accentHi    = { 0.68, 0.30, 1.00, 1.00 },
    accentLo    = { 0.35, 0.08, 0.60, 1.00 },
    accentGlow  = { 0.55, 0.15, 0.90, 0.35 },

    -- Text
    text        = { 0.92, 0.88, 1.00, 1.00 },
    textDim     = { 0.58, 0.52, 0.68, 1.00 },
    textAccent  = { 0.78, 0.62, 1.00, 1.00 },
    textDisable = { 0.35, 0.30, 0.42, 1.00 },

    -- Borders
    border      = { 0.22, 0.07, 0.38, 1.00 },
    borderHi    = { 0.50, 0.20, 0.75, 1.00 },

    -- Buttons
    btnNormal   = { 0.13, 0.04, 0.20, 1.00 },
    btnHover    = { 0.22, 0.08, 0.35, 1.00 },
    btnActive   = { 0.30, 0.10, 0.48, 1.00 },
    btnDisable  = { 0.08, 0.03, 0.12, 1.00 },

    -- List rows
    listItem    = { 0.09, 0.02, 0.14, 1.00 },
    listSel     = { 0.20, 0.06, 0.33, 1.00 },
    listHover   = { 0.14, 0.04, 0.22, 1.00 },

    -- Status
    danger      = { 0.85, 0.15, 0.20, 1.00 },
    success     = { 0.20, 0.80, 0.58, 1.00 },
    warning     = { 0.90, 0.65, 0.10, 1.00 },

    -- Misc
    divider     = { 0.30, 0.10, 0.50, 0.45 },
    shadow      = { 0.00, 0.00, 0.00, 0.80 },
    white       = { 1.00, 1.00, 1.00, 1.00 },
}

-- ---------------------------------------------------------------------------
-- Fonts  { path, size, flags }
-- ---------------------------------------------------------------------------
T.font = {
    header  = { path = "Fonts\\MORPHEUS.TTF", size = 15, flags = ""        },
    body    = { path = "Fonts\\FRIZQT__.TTF", size = 12, flags = ""        },
    small   = { path = "Fonts\\FRIZQT__.TTF", size = 10, flags = ""        },
    label   = { path = "Fonts\\FRIZQT__.TTF", size = 11, flags = ""        },
    timer   = { path = "Fonts\\skurri.ttf",   size = 14, flags = "OUTLINE" },
    count   = { path = "Fonts\\skurri.ttf",   size = 12, flags = "OUTLINE" },
    mono    = { path = "Fonts\\FRIZQT__.TTF", size = 11, flags = ""           },
}

-- ---------------------------------------------------------------------------
-- Sizes
-- ---------------------------------------------------------------------------
T.size = {
    panelW      = 720,
    panelH      = 500,
    headerH     = 32,
    footerH     = 36,
    tabH        = 28,
    listW       = 200,
    pad         = 10,
    padSm       = 5,
    btnH        = 24,
    scrollbarW  = 12,
    checkSize   = 14,
    inputH      = 22,
    swatchSize  = 22,
}

-- Solid-color texture used for all colored rectangles
T.WHITE = "Interface\\Buttons\\WHITE8X8"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Apply a backdrop (bg + 1px border) to any BackdropTemplate frame.
function T:Apply(frame, bgCol, borderCol)
    frame:SetBackdrop({
        bgFile   = T.WHITE,
        edgeFile = T.WHITE,
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    local bg = bgCol    or T.color.panel
    local bo = borderCol or T.color.border
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    frame:SetBackdropBorderColor(bo[1], bo[2], bo[3], bo[4])
end

-- Apply font + color to a FontString.
function T:Font(fs, fontDef, col)
    local f = fontDef or T.font.body
    local c = col     or T.color.text
    fs:SetFont(f.path, f.size, f.flags)
    fs:SetTextColor(c[1], c[2], c[3], c[4])
end

-- Tint a texture with a color table.
function T:Tint(tex, col)
    tex:SetVertexColor(col[1], col[2], col[3], col[4])
end
