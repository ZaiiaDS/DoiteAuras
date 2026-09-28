---------------------------------------------------------------
-- DoiteSettings.lua
-- Settings UI for DoiteAuras
-- Please respect license note: Ask permission
-- WoW 1.12 | Lua 5.0
---------------------------------------------------------------

DoiteSettings = DoiteSettings or {}

local settingsFrame
----------------------------------------
-- Local helpers
----------------------------------------
-- NOTE: UIDropDownMenu always creates its popup menu on the
-- FULLSCREEN_DIALOG strata. If our window sits on TOOLTIP (which is
-- above FULLSCREEN_DIALOG), the popups render *underneath* the window
-- and become unselectable. We therefore keep the window on
-- FULLSCREEN_DIALOG — same as DoiteEdit.lua, where dropdowns work.
local function DS_MakeTopMost(frame)
    if not frame then return end
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    if frame.SetToplevel then frame:SetToplevel(true) end
    if frame.Raise then frame:Raise() end
end

local function DS_CloseOtherWindows()
    local f

    f = _G["DoiteAurasImportFrame"]
    if f and f.IsShown and f:IsShown() then
        f:Hide()
    end

    f = _G["DoiteAurasExportFrame"]
    if f and f.IsShown and f:IsShown() then
        f:Hide()
    end
end

----------------------------------------
-- Frame
----------------------------------------
local function DS_CreateSettingsFrame()
    if settingsFrame then
        return
    end

    local f = CreateFrame("Frame", "DoiteAurasSettingsFrame", UIParent)
    settingsFrame = f

    f:SetWidth(280)
    f:SetHeight(540)
    -- Position to the LEFT of the main DoiteAuras frame so the two windows
    -- don't overlap. Fallback to screen center if the main frame is absent
    -- (e.g. on a fresh login before UI is built).
    if DoiteAurasFrame and DoiteAurasFrame.GetName then
        f:SetPoint("TOPRIGHT", DoiteAurasFrame, "TOPLEFT", -5, 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop",  function() this:StopMovingOrSizing() end)

    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:SetBackdropColor(0, 0, 0, 1)
    f:SetBackdropBorderColor(1, 1, 1, 1)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -15)
    title:SetText("|cff6FA8DCDoiteSettings|r")

    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -35)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -15, -35)
    sep:SetTexture(1, 1, 1)
    if sep.SetVertexColor then sep:SetVertexColor(1, 1, 1, 0.25) end

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() f:Hide() end)

    ---------------------------------------------------------------
    -- Nampower requirement hint (re-checked every OnShow)
    ---------------------------------------------------------------
    local reqHint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reqHint:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -40)
    reqHint:SetWidth(250)
    reqHint:SetJustifyH("LEFT")

    local function DS_UpdateReqHint()
        local getMissing = _G["DoiteAuras_GetMissingRequiredMods"]
        local missing = (type(getMissing) == "function") and getMissing() or {}
        if table.getn(missing) > 0 then
            reqHint:SetTextColor(1, 0.25, 0.25)
            reqHint:SetText("Requires Nampower 4.1.3+. Missing: " .. table.concat(missing, ", "))
        else
            reqHint:SetTextColor(0.5, 0.9, 0.5)
            reqHint:SetText("Requires Nampower 4.1.3+ (OK).")
        end
    end
    DS_UpdateReqHint()

    ---------------------------------------------------------------
    -- pfUI border toggle
    ---------------------------------------------------------------
    local pfuiBorderBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    pfuiBorderBtn:SetWidth(120)
    pfuiBorderBtn:SetHeight(20)
    pfuiBorderBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -62)

    local function DS_HasPfUI()
        if type(DoiteAuras_HasPfUI) == "function" then
            return DoiteAuras_HasPfUI() == true
        end
        return false
    end

    -- Single source of truth for the *default* lives in DoiteAuras.lua
    -- (DA_EnsurePfUIBorderDefault, applied on ADDON_LOADED and
    -- PLAYER_ENTERING_WORLD). This module must not duplicate it -- it
    -- only reflects the current state and writes to DB when the user
    -- explicitly toggles the button.
    --
    -- Edge case: if the button is somehow shown before the normalizer
    -- ran, DB may still be nil. In that case treat it as the same
    -- default (ON when pfUI is present) WITHOUT persisting it.
    local function DS_GetEffectivePfUIBorder()
        if not DS_HasPfUI() then return false end
        local v = DoiteAurasDB and DoiteAurasDB.pfuiBorder
        if v == nil then return true end
        return v == true
    end

    local function DS_UpdatePfUIButton()
        local hasPfUI = DS_HasPfUI()
        local effective = DS_GetEffectivePfUIBorder()

        if effective then
            pfuiBorderBtn:SetText("pfUI icons: ON")
        else
            pfuiBorderBtn:SetText("pfUI icons: OFF")
        end

        if not hasPfUI then
            if pfuiBorderBtn.Disable then pfuiBorderBtn:Disable() end
            local fs = pfuiBorderBtn.GetFontString and pfuiBorderBtn:GetFontString()
            if fs and fs.SetTextColor then fs:SetTextColor(0.6, 0.6, 0.6) end
        else
            if pfuiBorderBtn.Enable then pfuiBorderBtn:Enable() end
            local fs = pfuiBorderBtn.GetFontString and pfuiBorderBtn:GetFontString()
            if fs and fs.SetTextColor then fs:SetTextColor(1, 0.82, 0) end
        end
    end

    pfuiBorderBtn:SetScript("OnClick", function()
        if not DS_HasPfUI() then return end

        -- Materialize the implicit default into an explicit choice
        -- before flipping it, so the click always produces a value the
        -- user explicitly set (rather than leaving DB at nil).
        if DoiteAurasDB.pfuiBorder == nil then
            DoiteAurasDB.pfuiBorder = DS_GetEffectivePfUIBorder()
        end
        DoiteAurasDB.pfuiBorder = not (DoiteAurasDB.pfuiBorder == true)
        DS_UpdatePfUIButton()

        if type(DoiteAuras_ApplyBorderToAllIcons) == "function" then
            DoiteAuras_ApplyBorderToAllIcons()
        end
        if DoiteAuras_RefreshIcons then
            pcall(DoiteAuras_RefreshIcons)
        end
    end)

    DS_UpdatePfUIButton()

    ---------------------------------------------------------------
    -- Item tooltip toggle
    ---------------------------------------------------------------
    local itemTooltipBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    itemTooltipBtn:SetWidth(120)
    itemTooltipBtn:SetHeight(20)
    itemTooltipBtn:SetPoint("TOPLEFT", pfuiBorderBtn, "TOPRIGHT", 5, 0)

    local function DS_UpdateItemTooltipButton()
        if not DoiteAurasDB then DoiteAurasDB = {} end
        if DoiteAurasDB.showtooltip == nil then
            DoiteAurasDB.showtooltip = true
        end

        if DoiteAurasDB.showtooltip == true then
            itemTooltipBtn:SetText("Item tooltip: ON")
        else
            itemTooltipBtn:SetText("Item tooltip: OFF")
        end

        if itemTooltipBtn.Enable then itemTooltipBtn:Enable() end
        local fs = itemTooltipBtn.GetFontString and itemTooltipBtn:GetFontString()
        if fs and fs.SetTextColor then fs:SetTextColor(1, 0.82, 0) end
    end

    itemTooltipBtn:SetScript("OnClick", function()
        if not DoiteAurasDB then DoiteAurasDB = {} end
        DoiteAurasDB.showtooltip = not (DoiteAurasDB.showtooltip == true)
        DS_UpdateItemTooltipButton()

        if DoiteAuras_RefreshIcons then
            pcall(DoiteAuras_RefreshIcons)
        end
    end)

    DS_UpdateItemTooltipButton()

    ---------------------------------------------------------------
    -- ICON TEXT FONTS (timer + stacks)
    ---------------------------------------------------------------
    local fontHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontHeader:SetPoint("TOPLEFT", pfuiBorderBtn, "BOTTOMLEFT", 0, -14)
    fontHeader:SetText("ICON TEXT FONTS")
    if fontHeader.SetTextColor then fontHeader:SetTextColor(1, 1, 1) end

    local fontSep = f:CreateTexture(nil, "ARTWORK")
    fontSep:SetHeight(1)
    fontSep:SetPoint("TOPLEFT", fontHeader, "BOTTOMLEFT", 0, -4)
    fontSep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -15, 0)
    fontSep:SetTexture(1, 1, 1)
    if fontSep.SetVertexColor then fontSep:SetVertexColor(1, 1, 1, 0.25) end

    ---------------------------------------------------------------
    -- Font / flag option tables
    ---------------------------------------------------------------
    local FONT_CHOICES = {
        -- Game built-in fonts
        { text = "Default",   value = "" },
        { text = "Frizqt",    value = "Fonts\\FRIZQT__.TTF" },
        { text = "ArialN",    value = "Fonts\\ARIALN.TTF" },
        { text = "Morpheus",  value = "Fonts\\MORPHEUS.TTF" },
        { text = "Skurri",    value = "Fonts\\SKURRI.TTF" },

        -- Custom fonts bundled with DoiteAuras (Interface\AddOns\DoiteAuras\Fonts\)
        { text = "BigNoodleTitling",    value = "Interface\\AddOns\\DoiteAuras\\Fonts\\BigNoodleTitling.ttf" },
        { text = "Continuum",           value = "Interface\\AddOns\\DoiteAuras\\Fonts\\Continuum.ttf" },
        { text = "DieDieDie",           value = "Interface\\AddOns\\DoiteAuras\\Fonts\\DieDieDie.ttf" },
        { text = "Expressway",          value = "Interface\\AddOns\\DoiteAuras\\Fonts\\Expressway.ttf" },
        { text = "Homespun",            value = "Interface\\AddOns\\DoiteAuras\\Fonts\\Homespun.ttf" },
        { text = "Hooge",               value = "Interface\\AddOns\\DoiteAuras\\Fonts\\Hooge.ttf" },
        { text = "Myriad Pro",          value = "Interface\\AddOns\\DoiteAuras\\Fonts\\Myriad-Pro.ttf" },
        { text = "PT Sans Narrow Bold", value = "Interface\\AddOns\\DoiteAuras\\Fonts\\PT-Sans-Narrow-Bold.ttf" },
        { text = "PT Sans Narrow Reg",  value = "Interface\\AddOns\\DoiteAuras\\Fonts\\PT-Sans-Narrow-Regular.ttf" },
        { text = "Roboto Mono",         value = "Interface\\AddOns\\DoiteAuras\\Fonts\\RobotoMono.ttf" },
    }
    local FLAG_CHOICES = {
        { text = "None",          value = "" },
        { text = "Outline",       value = "OUTLINE" },
        { text = "Thick outline", value = "THICKOUTLINE" },
    }

    local function _FontLabelForValue(v)
        local i
        for i = 1, table.getn(FONT_CHOICES) do
            if FONT_CHOICES[i].value == (v or "") then
                return FONT_CHOICES[i].text
            end
        end
        return "Default"
    end
    local function _FlagLabelForValue(v)
        local i
        for i = 1, table.getn(FLAG_CHOICES) do
            if FLAG_CHOICES[i].value == (v or "") then
                return FLAG_CHOICES[i].text
            end
        end
        return "Outline"
    end

    ---------------------------------------------------------------
    -- Dropdown builders
    -- NOTE: UIDropDownMenuTemplate has ~16px internal left padding,
    -- so we offset the anchor by -16 to make the visible left edge
    -- land exactly at the requested x.
    ---------------------------------------------------------------
    local function _MakeFontDropdown(name, parent, x, y, width, dbField, onPick)
        local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
        dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y)
        if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(width, dd) end

        dd._dbField = dbField
        dd._onPick  = onPick

        UIDropDownMenu_Initialize(dd, function()
            local cur = (DoiteAurasDB and DoiteAurasDB[dbField]) or ""
            local i
            for i = 1, table.getn(FONT_CHOICES) do
                local opt = FONT_CHOICES[i]
                local info = UIDropDownMenu_CreateInfo()
                info.text    = opt.text
                info.value   = opt.value
                info.checked = (opt.value == cur)
                info.func = function(button)
                    local picked = (button and button.value) or opt.value
                    if DoiteAurasDB then
                        DoiteAurasDB[dbField] = (picked ~= "") and picked or nil
                    end
                    UIDropDownMenu_SetSelectedValue(dd, picked)
                    UIDropDownMenu_SetText(opt.text, dd)
                    if onPick then onPick() end
                end
                UIDropDownMenu_AddButton(info)
            end
        end)

        local cur = (DoiteAurasDB and DoiteAurasDB[dbField]) or ""
        UIDropDownMenu_SetSelectedValue(dd, cur)
        UIDropDownMenu_SetText(_FontLabelForValue(cur), dd)

        local t = _G[dd:GetName() .. "Text"]
        if t and t.SetTextColor then t:SetTextColor(1, 0.82, 0) end
        return dd
    end

    local function _MakeFlagDropdown(name, parent, x, y, width, dbField, onPick)
        local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
        dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y)
        if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(width, dd) end

        dd._dbField = dbField
        dd._onPick  = onPick

        UIDropDownMenu_Initialize(dd, function()
            local cur = (DoiteAurasDB and DoiteAurasDB[dbField]) or ""
            local i
            for i = 1, table.getn(FLAG_CHOICES) do
                local opt = FLAG_CHOICES[i]
                local info = UIDropDownMenu_CreateInfo()
                info.text    = opt.text
                info.value   = opt.value
                info.checked = (opt.value == cur)
                info.func = function(button)
                    local picked = (button and button.value) or opt.value
                    if DoiteAurasDB then
                        -- "" is a valid "None" value; store it explicitly
                        DoiteAurasDB[dbField] = picked
                    end
                    UIDropDownMenu_SetSelectedValue(dd, picked)
                    UIDropDownMenu_SetText(opt.text, dd)
                    if onPick then onPick() end
                end
                UIDropDownMenu_AddButton(info)
            end
        end)

        local cur = (DoiteAurasDB and DoiteAurasDB[dbField]) or ""
        UIDropDownMenu_SetSelectedValue(dd, cur)
        UIDropDownMenu_SetText(_FlagLabelForValue(cur), dd)

        local t = _G[dd:GetName() .. "Text"]
        if t and t.SetTextColor then t:SetTextColor(1, 0.82, 0) end
        return dd
    end

    local function _ApplyFontsNow()
        if type(DoiteAuras_ApplyFontsToAllIcons) == "function" then
            DoiteAuras_ApplyFontsToAllIcons()
        else
            if DoiteAuras_RefreshIcons then pcall(DoiteAuras_RefreshIcons) end
        end
    end

    ---------------------------------------------------------------
    -- Size EditBox builder (30px wide, numeric value)
    --
    -- Display rules (matches the per-icon Edit window):
    --   DB value == nil  -> show built-in defaultVal in grey ("inherit")
    --   DB value ~= nil  -> show explicit value in gold ("override")
    --
    -- DB is only ever written by an explicit user action:
    --   valid typed value  -> store it (gold)
    --   empty / out-of-range / Escape -> clear DB to nil (grey default)
    -- The built-in default value itself is never persisted.
    ---------------------------------------------------------------
    local function _MakeSizeBox(name, parent, x, y, dbField, defaultVal)
        local box = CreateFrame("EditBox", name, parent)
        box:SetWidth(30); box:SetHeight(18)
        box:SetAutoFocus(false)
        box:SetFontObject("GameFontNormalSmall")
        box:SetJustifyH("CENTER")
        box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        if box.SetTextInsets then box:SetTextInsets(2, 2, 0, 0) end
        if box.SetBackdrop then
            box:SetBackdrop({
                bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            box:SetBackdropColor(0, 0, 0, 0.85)
            box:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        end

        -- Display: nil DB value -> show built-in default in grey (inherit),
        -- non-nil -> show the explicit value in gold. Mirrors Edit-window
        -- behaviour. Never writes to DB from here.
        local function _ShowValue()
            local v = DoiteAurasDB and DoiteAurasDB[dbField]
            if v then
                box:SetText(tostring(v))
                box:SetTextColor(1, 0.82, 0)       -- gold = explicit
            else
                box:SetText(tostring(defaultVal))
                box:SetTextColor(0.5, 0.5, 0.5)    -- grey = default
            end
        end

        -- Expose refresh for external callers (OnShow)
        box.Refresh = _ShowValue

        _ShowValue()

        box:SetScript("OnEditFocusGained", function()
            box:SetTextColor(1, 0.82, 0)
        end)

        box:SetScript("OnEditFocusLost", function()
            -- Escape path: do not save whatever is left in the box.
            if box._daSkipFocusLost then
                box._daSkipFocusLost = nil
                _ShowValue()
                _ApplyFontsNow()
                return
            end

            local txt = box:GetText() or ""
            local v = tonumber(txt)
            if v and v >= 4 and v <= 48 then
                DoiteAurasDB[dbField] = math.floor(v + 0.5)
            else
                -- Empty / out-of-range -> back to default (grey)
                DoiteAurasDB[dbField] = nil
            end
            _ShowValue()
            _ApplyFontsNow()
        end)

        box:SetScript("OnEnterPressed", function()
            box:ClearFocus()
        end)

        box:SetScript("OnEscapePressed", function()
            -- Escape = reset to default (grey 15 / 10)
            DoiteAurasDB[dbField] = nil
            box._daSkipFocusLost = true
            box:ClearFocus()
        end)

        return box
    end

    ---------------------------------------------------------------
    -- Timer row  (label | size | font | flag)
    --
    -- Layout for a 280px-wide window:
    --   x=15  : "Timer:" label
    --   x=45  : size box (30px)   -> ends at 75
    --   x=75  : font DD (90px)    -> ends at 165
    --   x=183 : flag DD (68px)    -> ends at 251
    ---------------------------------------------------------------
    local TIMER_Y  = -120
    local STACKS_Y = -148

    -- Timer row
    local timerLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 15, TIMER_Y)
    timerLbl:SetText("Timer:")
    if timerLbl.SetTextColor then timerLbl:SetTextColor(1, 0.82, 0) end

    local timerSizeBox = _MakeSizeBox(
        "DoiteSettings_TimerSize", f, 45, TIMER_Y + 2, "timerFontSize", 15
    )

    local timerFontDD = _MakeFontDropdown(
        "DoiteSettings_TimerFontDD", f, 75, TIMER_Y + 6, 90,
        "timerFontPath", _ApplyFontsNow
    )

    local timerFlagDD = _MakeFlagDropdown(
        "DoiteSettings_TimerFlagDD", f, 183, TIMER_Y + 6, 68,
        "timerFontFlags", _ApplyFontsNow
    )

    -- Stacks row
    local stackLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stackLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 15, STACKS_Y)
    stackLbl:SetText("Stacks:")
    if stackLbl.SetTextColor then stackLbl:SetTextColor(1, 0.82, 0) end

    local stackSizeBox = _MakeSizeBox(
        "DoiteSettings_StackSize", f, 45, STACKS_Y + 2, "stackFontSize", 10
    )

    local stackFontDD = _MakeFontDropdown(
        "DoiteSettings_StackFontDD", f, 75, STACKS_Y + 6, 90,
        "stackFontPath", _ApplyFontsNow
    )

    local stackFlagDD = _MakeFlagDropdown(
        "DoiteSettings_StackFlagDD", f, 183, STACKS_Y + 6, 68,
        "stackFontFlags", _ApplyFontsNow
    )

    -- Hint
    local fontHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fontHint:SetPoint("TOPLEFT", f, "TOPLEFT", 15, STACKS_Y - 26)
    fontHint:SetWidth(250)
    fontHint:SetJustifyH("LEFT")
    if fontHint.SetTextColor then fontHint:SetTextColor(0.7, 0.7, 0.7) end
    fontHint:SetText("Size range: 4-48.")

    -- =============================================================
    -- GLOW EFFECTS section
    -- =============================================================
    -- Rendered between fontHint and the bottom-anchored DEBUG block.
    -- All controls write directly into DoiteAurasDB.glow (== DG.GetSettings())
    -- so values persist without an extra layer. Shape/color changes call
    -- DG.BumpVersion() once per user action to invalidate every cached
    -- overlay; the speed slider skips this because live overlays read
    -- s.speed fresh on every OnUpdate tick.
    do
        local DG = _G["DoiteGlow"]
        if DG and type(DG.GetSettings) == "function" then
            local gs = DG.GetSettings()

            local function _GlowCommit()
                if type(DG.BumpVersion) == "function" then
                    DG.BumpVersion()
                end
            end

            -----------------------------------------------------------
            -- Header + separator (auto-follows fontHint)
            -----------------------------------------------------------
            local glowHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            glowHeader:SetPoint("TOPLEFT", fontHint, "BOTTOMLEFT", 0, -14)
            glowHeader:SetText("GLOW EFFECTS")
            if glowHeader.SetTextColor then glowHeader:SetTextColor(1, 1, 1) end

            local glowSep = f:CreateTexture(nil, "ARTWORK")
            glowSep:SetHeight(1)
            glowSep:SetPoint("TOPLEFT", glowHeader, "BOTTOMLEFT", 0, -4)
            glowSep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -15, 0)
            glowSep:SetTexture(1, 1, 1)
            if glowSep.SetVertexColor then glowSep:SetVertexColor(1, 1, 1, 0.25) end

            -----------------------------------------------------------
            -- Row anchors (relative to f TOPLEFT)
            -----------------------------------------------------------
            local GX        = 15
            local ROW_POS   = -226
            local ROW_SCALE = -252
            local ROW_SPEED = -274
            local ROW_ALPHA = -296
            local ROW_COL   = -322
            local ROW_TEX   = -348

            -----------------------------------------------------------
            -- Position dropdown (in front / behind)
            -----------------------------------------------------------
            local POS_CHOICES = {
                { text = "In front of icon", value = "front"  },
                { text = "Behind icon",      value = "behind" },
            }
            local function _PosCur()
                return gs.behind and "behind" or "front"
            end
            local function _PosLabel()
                return (gs.behind == true) and "Behind icon" or "In front of icon"
            end

            local posLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            posLbl:SetPoint("TOPLEFT", f, "TOPLEFT", GX, ROW_POS)
            posLbl:SetText("Position:")
            if posLbl.SetTextColor then posLbl:SetTextColor(1, 0.82, 0) end

            local posDD = CreateFrame("Frame", "DoiteSettings_GlowPosDD", f, "UIDropDownMenuTemplate")
            -- UIDropDownMenuTemplate carries ~16px internal left padding.
            -- Position the *frame* at 42 so the visible left edge lands
            -- at 58 -- same as the sliders and the color swatch button.
            posDD:SetPoint("TOPLEFT", f, "TOPLEFT", 42, ROW_POS + 6)
            if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(110, posDD) end

            UIDropDownMenu_Initialize(posDD, function()
                local i
                for i = 1, table.getn(POS_CHOICES) do
                    local opt = POS_CHOICES[i]
                    local info = UIDropDownMenu_CreateInfo()
                    info.text    = opt.text
                    info.value   = opt.value
                    info.checked = (_PosCur() == opt.value)
                    info.func = function(button)
                        local picked = (button and button.value) or opt.value
                        gs.behind = (picked == "behind")
                        UIDropDownMenu_SetSelectedValue(posDD, picked)
                        UIDropDownMenu_SetText(_PosLabel(), posDD)
                        _GlowCommit()
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end)
            posDD.Refresh = function()
                local cur = _PosCur()
                UIDropDownMenu_SetSelectedValue(posDD, cur)
                UIDropDownMenu_SetText(_PosLabel(), posDD)
            end
            posDD.Refresh()
            do
                local t = _G[posDD:GetName() .. "Text"]
                if t and t.SetTextColor then t:SetTextColor(1, 0.82, 0) end
            end

            -----------------------------------------------------------
            -- Generic horizontal slider for a numeric glow setting.
            --
            --   UI value = DB value * mult   (scale 1.0 -> 100,
            --                                 speed 0.04 -> 40 ms,
            --                                 alpha 1.0 -> 100)
            --   label    = UI value + suffix
            --
            -- All three sliders share this builder, so they look and
            -- behave identically. Scale/alpha are read only when an
            -- overlay is (re)built, so those commit via BumpVersion on
            -- mouse-up (not on every OnValueChanged tick -- that would
            -- recreate every active overlay dozens of times per drag).
            -----------------------------------------------------------
            local function _MakeGlowSlider(name, y, field, minUI, maxUI, step, mult, suffix, asEditBox, displayFn)
                local slider = CreateFrame("Slider", name, f, "OptionsSliderTemplate")
                slider:SetWidth(130); slider:SetHeight(16)
                slider:SetPoint("TOPLEFT", f, "TOPLEFT", 58, y)
                slider:SetMinMaxValues(minUI, maxUI)
                slider:SetValueStep(step)
                slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
                if slider.SetOrientation then
                    pcall(slider.SetOrientation, slider, "HORIZONTAL")
                end
                if slider.EnableMouse then slider:EnableMouse(true) end

                -- OptionsSliderTemplate in 1.12 carries its own default
                -- range (0..100) and occasionally re-applies it on the
                -- first layout pass. Re-assert our range a few times to
                -- win the race: immediately, on the next frame, and in
                -- Refresh(). Without this, Speed caps at 100 ms.
                slider:SetMinMaxValues(minUI, maxUI)
                if slider.SetValueStep then slider:SetValueStep(step) end

                -- Hide OptionsSliderTemplate's built-in Low/High/Text
                -- fontstrings; we render our own value label instead.
                do
                    local sname = slider.GetName and slider:GetName()
                    if sname then
                        local suffixes = { "Low", "High", "Text" }
                        local i
                        for i = 1, table.getn(suffixes) do
                            local fs = _G[sname .. suffixes[i]]
                            if fs and fs.Hide then fs:Hide() end
                        end
                    end
                end

                -- Value display: either a FontString (read-only) or an
                -- EditBox the user can type into. Only Scale and Alpha
                -- get EditBoxes; Speed stays read-only.
                local valTxt
                if asEditBox then
                    local box = CreateFrame("EditBox", name .. "Value", f)
                    box:SetWidth(50); box:SetHeight(18)
                    box:SetAutoFocus(false)
                    box:SetFontObject("GameFontNormalSmall")
                    box:SetJustifyH("CENTER")
                    box:SetPoint("TOPLEFT", f, "TOPLEFT", 190, y + 2)
                    if box.SetTextInsets then box:SetTextInsets(2, 2, 0, 0) end
                    if box.SetMaxLetters then box:SetMaxLetters(4) end

                    -- Suffix label ("%" for scale/alpha). EditBox only
                    -- holds digits, so the unit sits next to it.
                    if suffix and suffix ~= "" then
                        local sfx = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        sfx:SetPoint("LEFT", box, "RIGHT", 3, 0)
                        sfx:SetText(suffix)
                        if sfx.SetTextColor then sfx:SetTextColor(1, 0.82, 0) end
                    end
                    if box.EnableMouse   then box:EnableMouse(true) end
                    if box.SetBackdrop then
                        box:SetBackdrop({
                            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
                            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                            tile = true, tileSize = 16, edgeSize = 12,
                            insets = { left = 3, right = 3, top = 3, bottom = 3 },
                        })
                        box:SetBackdropColor(0, 0, 0, 0.85)
                        box:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
                    end

                    box:SetScript("OnEditFocusGained", function()
                        box:SetTextColor(1, 0.82, 0)
                    end)
                    box:SetScript("OnEditFocusLost", function()
                        local v = tonumber(box:GetText() or "")
                        if v and v >= minUI and v <= maxUI then
                            gs[field] = math.floor(v + 0.5) / mult
                        end
                        -- Rebuild from DB (valid -> applied, invalid -> reverted)
                        if slider.SetValue then
                            slider:SetValue(math.floor((tonumber(gs[field]) or 0) * mult + 0.5))
                        end
                        _GlowCommit()
                    end)
                    box:SetScript("OnEnterPressed", function() box:ClearFocus() end)
                    box:SetScript("OnEscapePressed", function()
                        box:SetText(tostring(math.floor((tonumber(gs[field]) or 0) * mult + 0.5)))
                        box:ClearFocus()
                    end)

                    valTxt = box
                else
                    valTxt = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    valTxt:SetPoint("TOPLEFT", f, "TOPLEFT", 200, y)
                    valTxt:SetWidth(60)
                    valTxt:SetJustifyH("LEFT")
                    if valTxt.SetTextColor then valTxt:SetTextColor(1, 0.82, 0) end
                end

                local function _Show()
                    local ui = math.floor((tonumber(gs[field]) or 0) * mult + 0.5)
                    if displayFn then
                        valTxt:SetText(displayFn(ui))
                    elseif asEditBox then
                        valTxt:SetText(tostring(ui))
                    else
                        valTxt:SetText(tostring(ui) .. suffix)
                    end
                end

                slider.Refresh = function()
                    -- Re-assert range (see comment at top).
                    if slider.SetMinMaxValues then
                        slider:SetMinMaxValues(minUI, maxUI)
                    end
                    local ui = math.floor((tonumber(gs[field]) or 0) * mult + 0.5)
                    if ui < minUI then ui = minUI end
                    if ui > maxUI then ui = maxUI end
                    if slider.SetValue then slider:SetValue(ui) end
                    _Show()
                end

                slider:SetScript("OnValueChanged", function()
                    local v = 0
                    if this and this.GetValue then v = this:GetValue() or 0 end
                    local rounded = math.floor(v / step + 0.5) * step
                    if rounded < minUI then rounded = minUI end
                    if rounded > maxUI then rounded = maxUI end
                    gs[field] = rounded / mult
                    _Show()
                end)

                slider:SetScript("OnMouseUp", function()
                    _GlowCommit()
                end)

                slider.Refresh()
                return slider
            end

            -----------------------------------------------------------
            -- Scale
            -----------------------------------------------------------
            local scaleLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            scaleLbl:SetPoint("TOPLEFT", f, "TOPLEFT", GX, ROW_SCALE)
            scaleLbl:SetText("Scale:")
            if scaleLbl.SetTextColor then scaleLbl:SetTextColor(1, 0.82, 0) end

            local scaleSlider = _MakeGlowSlider(
                "DoiteSettings_GlowScaleSlider", ROW_SCALE,
                "scale", 50, 200, 5, 100, "%", true
            )

            -----------------------------------------------------------
            -- Speed
            -----------------------------------------------------------
            local spdLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            spdLbl:SetPoint("TOPLEFT", f, "TOPLEFT", GX, ROW_SPEED)
            spdLbl:SetText("Speed:")
            if spdLbl.SetTextColor then spdLbl:SetTextColor(1, 0.82, 0) end

            -- Speed slider uses relative units, not milliseconds. 1.0 =
            -- slowest (10 ms) .. 10.0 = fastest (500 ms). Range 490 ms
            -- with step 5 ms -> 98 slider ticks -> relative display
            -- changes in ~0.1 increments. The DB still stores seconds.
            local spdSlider = _MakeGlowSlider(
                "DoiteSettings_GlowSpeedSlider", ROW_SPEED,
                "speed", 10, 500, 5, 1000, nil, false,
                function(ms)
                    local n = 1 + (ms - 10) * 9 / 490
                    if n < 1  then n = 1  end
                    if n > 10 then n = 10 end
                    return string.format("%.1f", n)
                end
            )

            -----------------------------------------------------------
            -- Alpha
            -----------------------------------------------------------
            local alphaLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            alphaLbl:SetPoint("TOPLEFT", f, "TOPLEFT", GX, ROW_ALPHA)
            alphaLbl:SetText("Alpha:")
            if alphaLbl.SetTextColor then alphaLbl:SetTextColor(1, 0.82, 0) end

            local alphaSlider = _MakeGlowSlider(
                "DoiteSettings_GlowAlphaSlider", ROW_ALPHA,
                "alpha", 0, 100, 5, 100, "%", true
            )

            -----------------------------------------------------------
            -- Color picker button
            -----------------------------------------------------------
            local colLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            colLbl:SetPoint("TOPLEFT", f, "TOPLEFT", GX, ROW_COL)
            colLbl:SetText("Color:")
            if colLbl.SetTextColor then colLbl:SetTextColor(1, 0.82, 0) end

            local colorBtn = CreateFrame("Button", "DoiteSettings_GlowColorBtn", f)
            colorBtn:SetWidth(60); colorBtn:SetHeight(18)
            colorBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 62, ROW_COL + 3)
            colorBtn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            -- Backdrop only provides the border frame; the fill is a
            -- solid-white texture tinted by vertex color. This is more
            -- reliable than SetBackdropColor on this client, which does
            -- not always apply to a Button's bgFile (swatch looked grey).
            colorBtn:SetBackdropColor(0, 0, 0, 0.85)
            colorBtn:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

            -- Real solid-white texture (Interface\Buttons\WHITE8X8);
            -- SetTexture(r,g,b,a) does NOT produce a solid fill on 1.12
            -- -- the swatch would stay grey. Vertex tint gives the color.
            local swatch = colorBtn:CreateTexture(nil, "ARTWORK")
            swatch:SetAllPoints(colorBtn)
            swatch:SetTexture("Interface\\Buttons\\WHITE8X8")

            colorBtn.Refresh = function()
                swatch:SetVertexColor(gs.r or 1, gs.g or 1, gs.b or 1, 1)
            end
            colorBtn.Refresh()

            local _cpHooked = false

            colorBtn:SetScript("OnClick", function()
                if not ColorPickerFrame then return end

                -- Toggle: click while open -> close (accepts current color).
                if ColorPickerFrame.IsShown and ColorPickerFrame:IsShown() then
                    ColorPickerFrame:Hide()
                    return
                end

                -- Bring above our FULLSCREEN_DIALOG settings window.
                -- Vanilla ColorPickerFrame sits on DIALOG, which is below
                -- FULLSCREEN_DIALOG -- without this it renders behind us.
                if ColorPickerFrame.SetFrameStrata then
                    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                end
                if ColorPickerFrame.SetFrameLevel then
                    ColorPickerFrame:SetFrameLevel(1000)
                end
                -- Our settings window is top-level (DS_MakeTopMost calls
                -- SetToplevel(true)). Non-top-level frames render below
                -- top-level ones on the same strata regardless of frame
                -- level, so raising the level alone does nothing. Give
                -- the picker top-level too, then Raise() it.
                if ColorPickerFrame.SetToplevel then
                    ColorPickerFrame:SetToplevel(true)
                end
                if ColorPickerFrame.Raise then
                    ColorPickerFrame:Raise()
                end

                -- Ensure the picker is draggable.
                --
                -- On vanilla 1.12 ColorPickerFrameHeader is often a
                -- Texture or FontString -- those do NOT have :SetScript,
                -- only real Frames do. Calling header:SetScript on such
                -- an object raises "attempt to call method SetScript
                -- (a nil value)". Guard both the table and the method.
                local header = _G["ColorPickerFrameHeader"]
                if header and header.SetScript then
                    if header.EnableMouse     then header:EnableMouse(true) end
                    if header.RegisterForDrag then header:RegisterForDrag("LeftButton") end
                    header:SetScript("OnDragStart", function()
                        ColorPickerFrame:StartMoving()
                    end)
                    header:SetScript("OnDragStop", function()
                        ColorPickerFrame:StopMovingOrSizing()
                    end)
                end

                -- Fallback drag strip across the top of the picker, so
                -- the window is grabbable even when the header above
                -- could not be hooked.
                local dragBar = _G["DoiteGlow_ColorPickerDragBar"]
                if not dragBar then
                    dragBar = CreateFrame("Frame",
                        "DoiteGlow_ColorPickerDragBar", ColorPickerFrame)
                    dragBar:SetHeight(18)
                    -- Stop short of the Close button (top-right); if the
                    -- bar covers it, the user cannot close the picker
                    -- and it looks like the window is "dead".
                    dragBar:SetPoint("TOPLEFT",  ColorPickerFrame, "TOPLEFT",   6, -6)
                    dragBar:SetPoint("TOPRIGHT", ColorPickerFrame, "TOPRIGHT", -36, -6)
                    -- Drop to the lowest level so real picker controls
                    -- (sliders, buttons) always win mouse priority.
                    dragBar:SetFrameLevel(1)
                    dragBar:EnableMouse(true)
                    dragBar:RegisterForDrag("LeftButton")
                    dragBar:SetScript("OnDragStart", function()
                        ColorPickerFrame:StartMoving()
                    end)
                    dragBar:SetScript("OnDragStop", function()
                        ColorPickerFrame:StopMovingOrSizing()
                    end)
                end

                -- One-time hook on picker close (Okay / Cancel / X).
                -- Commits a single BumpVersion so overlays repaint with
                -- the final color.
                if not _cpHooked then
                    _cpHooked = true
                    local prevHide = nil
                    if ColorPickerFrame.GetScript then
                        prevHide = ColorPickerFrame:GetScript("OnHide")
                    end
                    ColorPickerFrame:SetScript("OnHide", function()
                        if prevHide then prevHide() end
                        _GlowCommit()
                    end)
                end

                -- Re-assert top-level status *after* Show(), because our
                -- settings frame is also top-level and may have been
                -- raised by the click that opened the picker.
                ColorPickerFrame:Show()
                if ColorPickerFrame.SetToplevel then
                    ColorPickerFrame:SetToplevel(true)
                end
                if ColorPickerFrame.Raise then
                    ColorPickerFrame:Raise()
                end

                local prevR, prevG, prevB = gs.r or 1, gs.g or 1, gs.b or 1

                if ColorPickerFrame.SetColorRGB then
                    ColorPickerFrame:SetColorRGB(prevR, prevG, prevB)
                end
                if ColorPickerFrame.hasOpacity ~= nil then
                    ColorPickerFrame.hasOpacity = false
                end
                -- Seed the picker's own previousValues so its Cancel
                -- button has something to hand to cancelFunc.
                ColorPickerFrame.previousValues = {
                    r = prevR, g = prevG, b = prevB, opacity = 1,
                }

                -- Live preview: fires on every slider drag inside picker.
                ColorPickerFrame.func = function()
                    if ColorPickerFrame.GetColorRGB then
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        if r then gs.r = r end
                        if g then gs.g = g end
                        if b then gs.b = b end
                        colorBtn.Refresh()
                    end
                end
                ColorPickerFrame.cancelFunc = function()
                    gs.r, gs.g, gs.b = prevR, prevG, prevB
                    colorBtn.Refresh()
                end
                -- Show() + toplevel/raise already handled above, right
                -- before the `return`.
            end)

            -----------------------------------------------------------
            -- Texture dropdown
            -----------------------------------------------------------
            local texLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            texLbl:SetPoint("TOPLEFT", f, "TOPLEFT", GX, ROW_TEX)
            texLbl:SetText("Texture:")
            if texLbl.SetTextColor then texLbl:SetTextColor(1, 0.82, 0) end

            local texDD = CreateFrame("Frame", "DoiteSettings_GlowTexDD", f, "UIDropDownMenuTemplate")
            texDD:SetPoint("TOPLEFT", f, "TOPLEFT", 42, ROW_TEX + 6)
            if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(130, texDD) end

            local function _TexLabelForValue(v)
                local list = DG.Textures
                if type(list) ~= "table" then return "?" end
                local i
                for i = 1, table.getn(list) do
                    if list[i].value == v then return list[i].text end
                end
                return "?"
            end

            UIDropDownMenu_Initialize(texDD, function()
                local list = DG.Textures
                if type(list) ~= "table" then return end
                local cur = gs.texture
                local i
                for i = 1, table.getn(list) do
                    local opt = list[i]
                    local info = UIDropDownMenu_CreateInfo()
                    info.text    = opt.text
                    info.value   = opt.value
                    info.checked = (opt.value == cur)
                    info.func = function(button)
                        local picked = (button and button.value) or opt.value
                        gs.texture = picked
                        UIDropDownMenu_SetSelectedValue(texDD, picked)
                        UIDropDownMenu_SetText(_TexLabelForValue(picked), texDD)
                        _GlowCommit()
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end)

            texDD.Refresh = function()
                local cur = gs.texture
                UIDropDownMenu_SetSelectedValue(texDD, cur)
                UIDropDownMenu_SetText(_TexLabelForValue(cur), texDD)
            end
            texDD.Refresh()
            do
                local t = _G[texDD:GetName() .. "Text"]
                if t and t.SetTextColor then t:SetTextColor(1, 0.82, 0) end
            end

            -----------------------------------------------------------
            -- Expose controls for the OnShow sync
            -----------------------------------------------------------
            f._daGlowControls = {
                scale = scaleSlider,
                alpha = alphaSlider,
                speed = spdSlider,
                pos   = posDD,
                tex   = texDD,
                color = colorBtn,
            }
        end
    end

    ---------------------------------------------------------------
    -- DEBUG section (bottom-anchored)
    ---------------------------------------------------------------
    local debugHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    debugHeader:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 15, 78)
    debugHeader:SetText("DEBUG")
    if debugHeader.SetTextColor then debugHeader:SetTextColor(1, 1, 1) end

    local debugSep = f:CreateTexture(nil, "ARTWORK")
    debugSep:SetHeight(1)
    debugSep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 15, 70)
    debugSep:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -15, 70)
    debugSep:SetTexture(1, 1, 1)
    if debugSep.SetVertexColor then debugSep:SetVertexColor(1, 1, 1, 0.25) end

    local overcapBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    overcapBtn:SetWidth(120); overcapBtn:SetHeight(20)
    overcapBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 15, 20)

    local spellCastDebugBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    spellCastDebugBtn:SetWidth(120); spellCastDebugBtn:SetHeight(20)
    spellCastDebugBtn:SetPoint("BOTTOMLEFT", overcapBtn, "TOPLEFT", 0, 5)

    ---------------------------------------------------------------
    -- Live aura count debug
    ---------------------------------------------------------------
    local DS_PlayerAuraCountEnabled = false
    local DS_TargetAuraCountEnabled = false

    local auraCountOverlay = CreateFrame("Frame", "DoiteSettings_AuraCountOverlay", UIParent)
    auraCountOverlay:SetFrameStrata("TOOLTIP")
    auraCountOverlay:SetFrameLevel(4000)
    auraCountOverlay:SetToplevel(true)
    auraCountOverlay:Hide()

    local AURA_COUNTER_ROW_HEIGHT  = 20
    local AURA_COUNTER_ROW_SPACING = 6

    local playerRow = CreateFrame("Frame", nil, auraCountOverlay)
    playerRow:SetWidth(1000); playerRow:SetHeight(AURA_COUNTER_ROW_HEIGHT)
    playerRow:SetPoint("TOP", UIParent, "TOP", 0, -20)
    playerRow:EnableMouse(true)
    playerRow:SetMovable(true)
    playerRow:RegisterForDrag("LeftButton")

    local targetRow = CreateFrame("Frame", nil, auraCountOverlay)
    targetRow:SetWidth(1000); targetRow:SetHeight(AURA_COUNTER_ROW_HEIGHT)
    targetRow:SetPoint("TOPLEFT", playerRow, "BOTTOMLEFT", 0, -AURA_COUNTER_ROW_SPACING)
    targetRow:EnableMouse(true)
    targetRow:SetMovable(true)
    targetRow:RegisterForDrag("LeftButton")

    local playerPrefix = playerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    playerPrefix:SetPoint("TOPLEFT", playerRow, "TOPLEFT", 0, 0)
    playerPrefix:SetDrawLayer("OVERLAY", 7)
    playerPrefix:SetText("|cff6FA8DCPLAYER AURAS:|r")

    local playerSuffix = playerRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    playerSuffix:SetPoint("LEFT", playerPrefix, "RIGHT", 4, -2)
    playerSuffix:SetDrawLayer("OVERLAY", 7)
    playerSuffix:SetText("")

    local targetPrefix = targetRow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    targetPrefix:SetPoint("TOPLEFT", targetRow, "TOPLEFT", 0, 0)
    targetPrefix:SetDrawLayer("OVERLAY", 7)
    targetPrefix:SetText("|cff6FA8DCTARGET AURAS:|r")

    local targetSuffix = targetRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    targetSuffix:SetPoint("LEFT", targetPrefix, "RIGHT", 4, -2)
    targetSuffix:SetDrawLayer("OVERLAY", 7)
    targetSuffix:SetText("")

    local DS_AuraCounterDrag = { active=false, frame=nil, source=nil, watcher=nil }

    local function DS_IsAuraCounterDragModifierDown()
        return IsControlKeyDown() or IsShiftKeyDown()
    end

    local function DS_ReanchorTargetBelowPlayer()
        targetRow:ClearAllPoints()
        targetRow:SetPoint("TOPLEFT", playerRow, "BOTTOMLEFT", 0, -AURA_COUNTER_ROW_SPACING)
    end

    local function DS_ReanchorPlayerAboveTarget()
        local targetLeft = targetRow:GetLeft()
        local targetTop  = targetRow:GetTop()
        local parentLeft = UIParent:GetLeft() or 0
        local parentTop  = UIParent:GetTop()  or 0
        if not targetLeft or not targetTop then return end

        playerRow:ClearAllPoints()
        playerRow:SetPoint(
            "TOPLEFT", UIParent, "TOPLEFT",
            targetLeft - parentLeft,
            (targetTop - parentTop) + AURA_COUNTER_ROW_HEIGHT + AURA_COUNTER_ROW_SPACING
        )
    end

    local function DS_StopAuraCounterDrag()
        if not DS_AuraCounterDrag.active or not DS_AuraCounterDrag.frame then return end

        if DS_AuraCounterDrag.watcher then
            DS_AuraCounterDrag.watcher:SetScript("OnUpdate", nil)
            DS_AuraCounterDrag.watcher = nil
        end

        DS_AuraCounterDrag.frame:StopMovingOrSizing()

        if DS_AuraCounterDrag.source == "target" and not (DS_PlayerAuraCountEnabled and DS_TargetAuraCountEnabled) then
            DS_ReanchorPlayerAboveTarget()
            DS_ReanchorTargetBelowPlayer()
        else
            DS_ReanchorTargetBelowPlayer()
        end

        DS_AuraCounterDrag.active = false
        DS_AuraCounterDrag.frame = nil
        DS_AuraCounterDrag.source = nil
    end

    local function DS_StartAuraCounterDrag(source)
        if not DS_IsAuraCounterDragModifierDown() then return end

        local dragFrame = nil
        if source == "target" and not (DS_PlayerAuraCountEnabled and DS_TargetAuraCountEnabled) then
            dragFrame = targetRow
        else
            dragFrame = playerRow
        end

        DS_AuraCounterDrag.active = true
        DS_AuraCounterDrag.frame = dragFrame
        DS_AuraCounterDrag.source = source
        DS_AuraCounterDrag.watcher = dragFrame
        dragFrame:SetScript("OnUpdate", function()
            if DS_AuraCounterDrag.active and (not DS_IsAuraCounterDragModifierDown()) then
                DS_StopAuraCounterDrag()
            end
        end)
        dragFrame:StartMoving()
    end

    playerRow:SetScript("OnDragStart", function() DS_StartAuraCounterDrag("player") end)
    targetRow:SetScript("OnDragStart", function() DS_StartAuraCounterDrag("target") end)
    playerRow:SetScript("OnDragStop", DS_StopAuraCounterDrag)
    targetRow:SetScript("OnDragStop", DS_StopAuraCounterDrag)

    local function DS_CanReadPlayerAuraCounts()
        return DoitePlayerAuras and type(DoitePlayerAuras.GetAuraCountSummary) == "function"
    end
    local function DS_CanReadTargetAuraCounts()
        return DoiteTargetAuras and type(DoiteTargetAuras.GetAuraCountSummary) == "function"
    end

    local function DS_FormatAuraCountLine(buffs, debuffs, total, visible, hidden)
        return string.format(
            "|cffffffff B:|r|cffffff00%d|r|cffffffff + D:|r|cffffff00%d|r|cffffffff = T:|r|cffffff00%d|r|cffffffff (Visible: |r|cffffff00%d|r|cffffffff / Hidden: |r|cffffff00%d|r|cffffffff)|r",
            buffs or 0, debuffs or 0, total or 0, visible or 0, hidden or 0
        )
    end

    local function DS_UpdateAuraCountOverlayOnce()
        local pb, pd, ph, pt
        local tb, td, th, tt

        if DS_PlayerAuraCountEnabled and DS_CanReadPlayerAuraCounts() then
            pb, pd, ph, pt = DoitePlayerAuras.GetAuraCountSummary()
            playerRow:Show(); playerPrefix:Show(); playerSuffix:Show()
            playerSuffix:SetText(DS_FormatAuraCountLine(pb, pd, pt, (pb + pd), ph))
        else
            playerRow:Hide(); playerPrefix:Hide(); playerSuffix:Hide()
        end

        if DS_TargetAuraCountEnabled and DS_CanReadTargetAuraCounts() then
            tb, td, th, tt = DoiteTargetAuras.GetAuraCountSummary()
            targetRow:Show(); targetPrefix:Show(); targetSuffix:Show()
            targetSuffix:SetText(DS_FormatAuraCountLine(tb, td, tt, (tb + td), th))
        else
            targetRow:Hide(); targetPrefix:Hide(); targetSuffix:Hide()
        end

        if DS_PlayerAuraCountEnabled or DS_TargetAuraCountEnabled then
            auraCountOverlay:Show()
        else
            auraCountOverlay:Hide()
        end
    end

    local auraCountElapsed = 0
    local function DS_SetAuraCountOverlayRunning(enable)
        if enable then
            auraCountElapsed = 0
            auraCountOverlay:SetScript("OnUpdate", function()
                auraCountElapsed = auraCountElapsed + arg1
                if auraCountElapsed >= 1.0 then
                    auraCountElapsed = 0
                    DS_UpdateAuraCountOverlayOnce()
                end
            end)
            DS_UpdateAuraCountOverlayOnce()
        else
            DS_StopAuraCounterDrag()
            auraCountOverlay:SetScript("OnUpdate", nil)
            auraCountOverlay:Hide()
        end
    end

    local playerAuraCountBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    playerAuraCountBtn:SetWidth(120); playerAuraCountBtn:SetHeight(20)
    playerAuraCountBtn:SetPoint("LEFT", spellCastDebugBtn, "RIGHT", 5, 0)

    local targetAuraCountBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    targetAuraCountBtn:SetWidth(120); targetAuraCountBtn:SetHeight(20)
    targetAuraCountBtn:SetPoint("LEFT", overcapBtn, "RIGHT", 5, 0)

    local function DS_UpdatePlayerAuraCountButton()
        if DS_PlayerAuraCountEnabled then
            playerAuraCountBtn:SetText("# of PlayerAuras: ON")
        else
            playerAuraCountBtn:SetText("# of PlayerAuras: OFF")
        end

        if not DS_CanReadPlayerAuraCounts() then
            if playerAuraCountBtn.Disable then playerAuraCountBtn:Disable() end
            local fs = playerAuraCountBtn.GetFontString and playerAuraCountBtn:GetFontString()
            if fs and fs.SetTextColor then fs:SetTextColor(0.6, 0.6, 0.6) end
        else
            if playerAuraCountBtn.Enable then playerAuraCountBtn:Enable() end
            local fs = playerAuraCountBtn.GetFontString and playerAuraCountBtn:GetFontString()
            if fs and fs.SetTextColor then fs:SetTextColor(1, 0.82, 0) end
        end
    end

    local function DS_UpdateTargetAuraCountButton()
        if DS_TargetAuraCountEnabled then
            targetAuraCountBtn:SetText("# of TargetAuras: ON")
        else
            targetAuraCountBtn:SetText("# of TargetAuras: OFF")
        end

        if not DS_CanReadTargetAuraCounts() then
            if targetAuraCountBtn.Disable then targetAuraCountBtn:Disable() end
            local fs = targetAuraCountBtn.GetFontString and targetAuraCountBtn:GetFontString()
            if fs and fs.SetTextColor then fs:SetTextColor(0.6, 0.6, 0.6) end
        else
            if targetAuraCountBtn.Enable then targetAuraCountBtn:Enable() end
            local fs = targetAuraCountBtn.GetFontString and targetAuraCountBtn:GetFontString()
            if fs and fs.SetTextColor then fs:SetTextColor(1, 0.82, 0) end
        end
    end

    playerAuraCountBtn:SetScript("OnClick", function()
        if not DS_CanReadPlayerAuraCounts() then return end
        DS_PlayerAuraCountEnabled = not DS_PlayerAuraCountEnabled
        DS_UpdatePlayerAuraCountButton()
        DS_UpdateAuraCountOverlayOnce()
        DS_SetAuraCountOverlayRunning(DS_PlayerAuraCountEnabled or DS_TargetAuraCountEnabled)
    end)

    targetAuraCountBtn:SetScript("OnClick", function()
        if not DS_CanReadTargetAuraCounts() then return end
        DS_TargetAuraCountEnabled = not DS_TargetAuraCountEnabled
        DS_UpdateTargetAuraCountButton()
        DS_UpdateAuraCountOverlayOnce()
        DS_SetAuraCountOverlayRunning(DS_PlayerAuraCountEnabled or DS_TargetAuraCountEnabled)
    end)

    local function DS_GetSpellCastDebugState()
        if _G["DoiteTrack_NPDebug"] then return true end
        return false
    end
    local function DS_SetSpellCastDebugState(wantOn)
        local fn = _G["DoiteTrack_SetNPDebug"]
        if type(fn) == "function" then
            fn(wantOn and true or false)
            return true
        end
        return false
    end

    local function DS_UpdateSpellCastDebugButton()
        local on = DS_GetSpellCastDebugState()
        if on then
            spellCastDebugBtn:SetText("Spell cast: ON")
        else
            spellCastDebugBtn:SetText("Spell cast: OFF")
        end

        if type(_G["DoiteTrack_SetNPDebug"]) ~= "function" then
            if spellCastDebugBtn.Disable then spellCastDebugBtn:Disable() end
            local fs = spellCastDebugBtn.GetFontString and spellCastDebugBtn:GetFontString()
            if fs and fs.SetTextColor then fs:SetTextColor(0.6, 0.6, 0.6) end
        else
            if spellCastDebugBtn.Enable then spellCastDebugBtn:Enable() end
            local fs = spellCastDebugBtn.GetFontString and spellCastDebugBtn:GetFontString()
            if fs and fs.SetTextColor then fs:SetTextColor(1, 0.82, 0) end
        end
    end

    spellCastDebugBtn:SetScript("OnClick", function()
        local cur = DS_GetSpellCastDebugState()
        local ok = DS_SetSpellCastDebugState(not cur)
        if not ok then
            local cf = (DEFAULT_CHAT_FRAME or ChatFrame1)
            if cf then
                cf:AddMessage("|cff6FA8DCDoiteSettings:|r debug toggle not available (DoiteTrack not loaded?).")
            end
            return
        end
        DS_UpdateSpellCastDebugButton()
    end)

    local function DS_GetOvercapSimState()
        local available = 0
        local enabled   = 0

        if DoitePlayerAuras and type(DoitePlayerAuras.ToggleDebugBuffCap) == "function" then
            available = available + 1
            if DoitePlayerAuras.debugBuffCap then enabled = enabled + 1 end
        end
        if DoiteTargetAuras and type(DoiteTargetAuras.ToggleDebugBuffCap) == "function" then
            available = available + 1
            if DoiteTargetAuras.debugBuffCap then enabled = enabled + 1 end
        end

        if available <= 0 then return false end
        return enabled == available
    end

    local function DS_CanToggleOvercapSim()
        if DoitePlayerAuras and type(DoitePlayerAuras.ToggleDebugBuffCap) == "function" then return true end
        if DoiteTargetAuras and type(DoiteTargetAuras.ToggleDebugBuffCap) == "function" then return true end
        return false
    end

    local function DS_UpdateOvercapButton()
        local on = DS_GetOvercapSimState()
        if on then
            overcapBtn:SetText("Aura cap. sim.: ON")
        else
            overcapBtn:SetText("Aura cap. sim.: OFF")
        end

        if not DS_CanToggleOvercapSim() then
            if overcapBtn.Disable then overcapBtn:Disable() end
            local fs = overcapBtn.GetFontString and overcapBtn:GetFontString()
            if fs and fs.SetTextColor then fs:SetTextColor(0.6, 0.6, 0.6) end
        else
            if overcapBtn.Enable then overcapBtn:Enable() end
            local fs = overcapBtn.GetFontString and overcapBtn:GetFontString()
            if fs and fs.SetTextColor then fs:SetTextColor(1, 0.82, 0) end
        end
    end

    overcapBtn:SetScript("OnClick", function()
        local okAny = false
        local newState = not DS_GetOvercapSimState()

        if DoitePlayerAuras and type(DoitePlayerAuras.SetDebugBuffCap) == "function" then
            DoitePlayerAuras.SetDebugBuffCap(newState)
            okAny = true
        elseif DoitePlayerAuras and type(DoitePlayerAuras.ToggleDebugBuffCap) == "function" then
            if (DoitePlayerAuras.debugBuffCap == true) ~= newState then
                DoitePlayerAuras.ToggleDebugBuffCap()
            end
            okAny = true
        end

        if DoiteTargetAuras and type(DoiteTargetAuras.SetDebugBuffCap) == "function" then
            DoiteTargetAuras.SetDebugBuffCap(newState)
            okAny = true
        elseif DoiteTargetAuras and type(DoiteTargetAuras.ToggleDebugBuffCap) == "function" then
            if (DoiteTargetAuras.debugBuffCap == true) ~= newState then
                DoiteTargetAuras.ToggleDebugBuffCap()
            end
            okAny = true
        end

        if not okAny then
            local cf = (DEFAULT_CHAT_FRAME or ChatFrame1)
            if cf then
                cf:AddMessage("|cff6FA8DCDoiteSettings:|r overcap simulation toggle not available.")
            end
            return
        end

        DS_UpdateOvercapButton()
    end)

    DS_UpdateSpellCastDebugButton()
    DS_UpdateOvercapButton()
    DS_UpdatePlayerAuraCountButton()
    DS_UpdateTargetAuraCountButton()
    DS_SetAuraCountOverlayRunning(false)

    f:SetScript("OnShow", function()
        DS_CloseOtherWindows()
        DS_MakeTopMost(f)
        DS_UpdateReqHint()

        -- Pre-warm the dropdown system. On a fresh login / reload,
        -- WoW 1.12 lazily creates DropDownList1-3 the very first time
        -- any dropdown opens, which on a populated UI can freeze for
        -- 1-2 seconds. We open-and-close one menu here (offscreen) so
        -- by the time the user clicks any real dropdown it is already
        -- built.
        if not f._daDropWarmed then
            f._daDropWarmed = true
            if ToggleDropDownMenu and CloseDropDownMenus then
                local warmDD = _G["DoiteSettings_TimerFontDD"]
                if warmDD then
                    pcall(function()
                        ToggleDropDownMenu(1, nil, warmDD, "cursor", -1000, -1000)
                        CloseDropDownMenus()
                    end)
                end
            end
        end

        -- Re-anchor to the left of the main frame every time we open,
        -- so the window follows the main frame if the user moved it.
        if DoiteAurasFrame and DoiteAurasFrame.GetName then
            f:ClearAllPoints()
            f:SetPoint("TOPRIGHT", DoiteAurasFrame, "TOPLEFT", -5, 0)
        end

        DS_UpdatePfUIButton()
        DS_UpdateItemTooltipButton()

        -- Sync font controls to current DB in case they were changed elsewhere.
        timerSizeBox:Refresh()
        stackSizeBox:Refresh()

        local cur
        cur = (DoiteAurasDB.timerFontPath) or ""
        UIDropDownMenu_SetSelectedValue(timerFontDD, cur)
        UIDropDownMenu_SetText(_FontLabelForValue(cur), timerFontDD)

        cur = (DoiteAurasDB.stackFontPath) or ""
        UIDropDownMenu_SetSelectedValue(stackFontDD, cur)
        UIDropDownMenu_SetText(_FontLabelForValue(cur), stackFontDD)

        cur = (DoiteAurasDB.timerFontFlags) or ""
        UIDropDownMenu_SetSelectedValue(timerFlagDD, cur)
        UIDropDownMenu_SetText(_FlagLabelForValue(cur), timerFlagDD)

        cur = (DoiteAurasDB.stackFontFlags) or ""
        UIDropDownMenu_SetSelectedValue(stackFlagDD, cur)
        UIDropDownMenu_SetText(_FlagLabelForValue(cur), stackFlagDD)

        DS_UpdateSpellCastDebugButton()
        DS_UpdateOvercapButton()
        DS_UpdatePlayerAuraCountButton()
        DS_UpdateTargetAuraCountButton()
        DS_UpdateAuraCountOverlayOnce()

        -- Glow controls: re-sync every visible value from the DB.
        -- (In case another addon/script touched DoiteAurasDB.glow, or
        --  the settings window was closed and reopened.)
        local gc = f._daGlowControls
        if gc then
            if gc.scale and gc.scale.Refresh then gc.scale:Refresh() end
            if gc.alpha and gc.alpha.Refresh then gc.alpha:Refresh() end
            if gc.speed and gc.speed.Refresh then gc.speed:Refresh() end
            if gc.pos   and gc.pos.Refresh   then gc.pos:Refresh()   end
            if gc.tex   and gc.tex.Refresh   then gc.tex:Refresh()   end
            if gc.color and gc.color.Refresh then gc.color:Refresh() end
        end
    end)

    DS_MakeTopMost(f)
end

function DoiteAuras_ShowSettings()
    if not settingsFrame then
        DS_CreateSettingsFrame()
    end
    DS_CloseOtherWindows()
    settingsFrame:Show()
end
----------------------------------------
-- End of frame
----------------------------------------