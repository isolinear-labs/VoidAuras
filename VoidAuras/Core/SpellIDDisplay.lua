-- =============================================================================
-- Core/SpellIDDisplay.lua
-- Appends spell IDs to tooltips when VA.db.global.showSpellIDs is true.
--
-- Hooks covered:
--   • Spell tooltips  (spellbook, action bars, talent tree)
--   • UnitAura tooltips (buff/debuff frames)
--   • Fallback: old-style GameTooltip:OnTooltipSetSpell if
--     TooltipDataProcessor is unavailable
-- =============================================================================

local _, VA = ...

local SpellIDDisplay = VA:Register("SpellIDDisplay", {})
VA.SpellIDDisplay = SpellIDDisplay

local R, G, B = 0.70, 0.50, 1.00   -- void purple tint for the ID line

local function ShouldShow()
    return VA.db and VA.db.global and VA.db.global.showSpellIDs
end

local function AppendID(tooltip, id)
    if not id then return end
    tooltip:AddLine("Spell ID: " .. id, R, G, B)
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------
function SpellIDDisplay:Init()
    -- -----------------------------------------------------------------------
    -- Spell tooltips: spellbook, action bars, talent tree
    -- -----------------------------------------------------------------------
    if TooltipDataProcessor and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(
            Enum.TooltipDataType.Spell,
            function(tip, data)
                if ShouldShow() and data and data.id then
                    AppendID(tip, data.id)
                end
            end
        )
    else
        -- Fallback for older API versions
        GameTooltip:HookScript("OnTooltipSetSpell", function(tip)
            if not ShouldShow() then return end
            local _, id = tip:GetSpell()
            if id then AppendID(tip, id); tip:Show() end
        end)
    end

    -- -----------------------------------------------------------------------
    -- Buff / debuff frame tooltips
    -- OnTooltipSetUnitAura gives us unit+index+filter so we can look up
    -- the spell ID directly — more reliable than TooltipDataProcessor.UnitAura
    -- whose data structure has changed across WoW versions.
    -- -----------------------------------------------------------------------
    if GameTooltip:HasScript("OnTooltipSetUnitAura") then
        GameTooltip:HookScript("OnTooltipSetUnitAura", function(tip, unit, index, filter)
            if not ShouldShow() then return end
            local auraData = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
            local id = auraData and auraData.spellId
            if id then AppendID(tip, id); tip:Show() end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------
function SpellIDDisplay:SetEnabled(enabled)
    VA.db.global.showSpellIDs = enabled == true
end

function SpellIDDisplay:IsEnabled()
    return VA.db.global.showSpellIDs == true
end
