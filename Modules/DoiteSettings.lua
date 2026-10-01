---------------------------------------------------------------
-- DoiteSettings.lua
-- Settings UI for DoiteAuras
-- Please respect license note: Ask permission
-- WoW 1.12 | Lua 5.0
---------------------------------------------------------------

DoiteSettings = DoiteSettings or {}

local settingsFrame

---------------------------------------------------------------
-- Quick section tuning
--
-- Edit these and /reload to nudge a section up or down. Each value
-- is an extra vertical offset applied just BEFORE that section is
-- placed in the stack, in pixels:
--
--   positive -> move the section (and every section below it) UP
--   negative -> move the section (and every section below it) DOWN
--
-- Requirements is fixed at the top and is not listed here.
--
-- Section order (top to bottom) inside DS_CreateSettingsFrame:
--   Requirements, Toggles, Fonts, Glow, Pop, Debug.
---------------------------------------------------------------
local SECTION_SHIFT = {
    Toggles = 7,
    Fonts   = 3,
    Glow    = 0,
    Pop     = 0,
    Debug   = 3,
}

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

    ---------------------------------------------------------------
    -- Outer window: backdrop, title, close, drag. Fixed chrome.
    ---------------------------------------------------------------
    local outer = CreateFrame("Frame", "DoiteAurasSettingsFrame", UIParent)
    settingsFrame = outer

    outer:SetWidth(320)
    outer:SetHeight(540)
    if DoiteAurasFrame and DoiteAurasFrame.GetName then
        outer:SetPoint("TOPRIGHT", DoiteAurasFrame, "TOPLEFT", -5, 0)
    else
        outer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    outer:EnableMouse(true)
    outer:SetMovable(true)
    outer:RegisterForDrag("LeftButton")
    outer:SetScript("OnDragStart", function() this:StartMoving() end)
    outer:SetScript("OnDragStop",  function() this:StopMovingOrSizing() end)

    outer:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    outer:SetBackdropColor(0, 0, 0, 1)
    outer:SetBackdropBorderColor(1, 1, 1, 1)
    outer:SetFrameStrata("FULLSCREEN_DIALOG")
    outer:Hide()

    local title = outer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", outer, "TOPLEFT", 20, -15)
    title:SetText("|cff6FA8DCDoiteSettings|r")

    local sep = outer:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", outer, "TOPLEFT", 15, -35)
    sep:SetPoint("TOPRIGHT", outer, "TOPRIGHT", -15, -35)
    sep:SetTexture(1, 1, 1)
    if sep.SetVertexColor then sep:SetVertexColor(1, 1, 1, 0.25) end

    local close = CreateFrame("Button", nil, outer, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", outer, "TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() outer:Hide() end)

    ---------------------------------------------------------------
    -- Scroll frame + content frame. Content width is 280 so the
    -- UIPanelScrollFrameTemplate scrollbar (attached to the right
    -- edge of the scroll frame) fits without overlapping.
    ---------------------------------------------------------------
    local scroll = CreateFrame("ScrollFrame", "DoiteAurasSettingsScroll",
        outer, "UIPanelScrollFrameTemplate")
    -- Scroll frame sits a bit inside the outer's left border, and is
    -- narrow enough that the template's scrollbar (right of the
    -- frame) still fits inside the window border.
    scroll:SetPoint("TOPLEFT", outer, "TOPLEFT", 8, -40)
    scroll:SetWidth(280)
    scroll:SetHeight(490)

    local content = CreateFrame("Frame", "DoiteAurasSettingsContent", scroll)
    content:SetWidth(280)
    scroll:SetScrollChild(content)

    ---------------------------------------------------------------
    -- Section stack manager.
    --
    -- Each Section_* is a factory: it takes a parent frame and
    -- returns a Frame sized to hold its own controls, positioned
    -- with the block's own TOPLEFT as origin. stackAdd() stacks
    -- them top-to-bottom with SECTION_GAP between adjacent ones,
    -- so section internals never need to know about each other.
    ---------------------------------------------------------------
    local SECTION_GAP = 12
    local stackChildren = {}
    -- Running depth of the stack, in pixels below content's TOPLEFT.
    -- GetPoint() on a block returns only the anchor offset relative
    -- to its neighbour, not the absolute position, so we track the
    -- cumulative depth here as we add blocks.
    local stackCursorY = 0

    local function stackAdd(factory, shift)
        local block = factory(content)
        local prev = stackChildren[table.getn(stackChildren)]
        -- Sign convention: positive shift = section (and everything
        -- below it) moves UP by that many pixels; negative = down.
        local up = shift or 0
        block:ClearAllPoints()
        if prev then
            -- Default gap is SECTION_GAP below the previous block.
            -- A positive `up` shrinks that gap (section sits higher),
            -- a negative `up` widens it.
            block:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -(SECTION_GAP - up))
            stackCursorY = stackCursorY + (SECTION_GAP - up)
        else
            -- First block always sits at content top; no shift.
            block:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        end
        stackCursorY = stackCursorY + (block:GetHeight() or 0)
        table.insert(stackChildren, block)
        return block
    end

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

        -- Custom fonts bundled with DoiteAuras
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

    local function _ApplyFontsNow()
        if type(DoiteAuras_ApplyFontsToAllIcons) == "function" then
            DoiteAuras_ApplyFontsToAllIcons()
        else
            if DoiteAuras_RefreshIcons then pcall(DoiteAuras_RefreshIcons) end
        end
    end

    ---------------------------------------------------------------
    -- Font dropdown builder. NOTE: UIDropDownMenuTemplate has ~16px
    -- internal left padding, so we offset by -16 to put the visible
    -- left edge at the requested x.
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

    ---------------------------------------------------------------
    -- Size EditBox builder (30px wide, numeric value).
    --
    -- Display rules (matches the per-icon Edit window):
    --   DB value == nil  -> show built-in defaultVal in grey ("inherit")
    --   DB value ~= nil  -> show explicit value in gold ("override")
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

        box.Refresh = _ShowValue
        _ShowValue()

        box:SetScript("OnEditFocusGained", function()
            box:SetTextColor(1, 0.82, 0)
        end)

        box:SetScript("OnEditFocusLost", function()
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
                DoiteAurasDB[dbField] = nil
            end
            _ShowValue()
            _ApplyFontsNow()
        end)

        box:SetScript("OnEnterPressed", function()
            box:ClearFocus()
        end)

        box:SetScript("OnEscapePressed", function()
            DoiteAurasDB[dbField] = nil
            box._daSkipFocusLost = true
            box:ClearFocus()
        end)

        return box
    end

    ---------------------------------------------------------------
    -- Section: Requirements (Nampower + UnitXP_SP3).
    ---------------------------------------------------------------
    local function Section_Requirements(parent)
        local b = CreateFrame("Frame", nil, parent)
        b:SetWidth(280)

        local reqHint = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        reqHint:SetPoint("TOPLEFT", b, "TOPLEFT", 15, 0)
        reqHint:SetWidth(250)
        reqHint:SetJustifyH("LEFT")

        local function Update()
            local getMissing = _G["DoiteAuras_GetMissingRequiredMods"]
            local missing = (type(getMissing) == "function") and getMissing() or {}
            local hasUnitXP = (type(UnitXP) == "function")

            local color = { 0.5, 0.9, 0.5 }
            local npLine, xpLine

            if table.getn(missing) > 0 then
                color = { 1, 0.25, 0.25 }
                npLine = "Requires Nampower 4.1.3+. Missing: " .. table.concat(missing, ", ")
            else
                npLine = "Requires Nampower 4.1.3+. OK"
            end

            if hasUnitXP then
                xpLine = "UnitXP_SP3. OK"
            else
                xpLine = "UnitXP_SP3 missing! Distance checks less accurate!"
                if color[1] == 0.5 then
                    color = { 1, 0.82, 0 }
                end
            end

            reqHint:SetTextColor(color[1], color[2], color[3])
            reqHint:SetText(npLine .. "\n" .. xpLine)
        end

        Update()
        b.Update = Update
        b:SetHeight(24)
        return b
    end

    ---------------------------------------------------------------
    -- Section: Toggles (pfUI border + item tooltip).
    ---------------------------------------------------------------
    local function Section_Toggles(parent)
        local b = CreateFrame("Frame", nil, parent)
        b:SetWidth(280)

        local pfuiBorderBtn = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
        pfuiBorderBtn:SetWidth(120)
        pfuiBorderBtn:SetHeight(20)
        pfuiBorderBtn:SetPoint("TOPLEFT", b, "TOPLEFT", 15, 0)

        local function DS_HasPfUI()
            if type(DoiteAuras_HasPfUI) == "function" then
                return DoiteAuras_HasPfUI() == true
            end
            return false
        end

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

        local itemTooltipBtn = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
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

        b.UpdatePfUI = DS_UpdatePfUIButton
        b.UpdateItemTooltip = DS_UpdateItemTooltipButton
        b:SetHeight(20)
        return b
    end

    ---------------------------------------------------------------
    -- Section: ICON TEXT FONTS (Timer + Stacks rows, size hint).
    ---------------------------------------------------------------
    local function Section_Fonts(parent)
        local b = CreateFrame("Frame", nil, parent)
        b:SetWidth(280)

        local fontHeader = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fontHeader:SetPoint("TOPLEFT", b, "TOPLEFT", 15, 0)
        fontHeader:SetText("ICON TEXT FONTS")
        if fontHeader.SetTextColor then fontHeader:SetTextColor(1, 1, 1) end

        local fontSep = b:CreateTexture(nil, "ARTWORK")
        fontSep:SetHeight(1)
        fontSep:SetPoint("TOPLEFT", fontHeader, "BOTTOMLEFT", 0, -4)
        fontSep:SetPoint("TOPRIGHT", b, "TOPRIGHT", -15, 0)
        fontSep:SetTexture(1, 1, 1)
        if fontSep.SetVertexColor then fontSep:SetVertexColor(1, 1, 1, 0.25) end

        local TIMER_Y  = -26
        local STACKS_Y = -54

        local timerLbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timerLbl:SetPoint("TOPLEFT", b, "TOPLEFT", 15, TIMER_Y)
        timerLbl:SetText("Timer:")
        if timerLbl.SetTextColor then timerLbl:SetTextColor(1, 0.82, 0) end

        local timerSizeBox = _MakeSizeBox(
            "DoiteSettings_TimerSize", b, 45, TIMER_Y + 2, "timerFontSize", 15
        )
        local timerFontDD = _MakeFontDropdown(
            "DoiteSettings_TimerFontDD", b, 75, TIMER_Y + 6, 90,
            "timerFontPath", _ApplyFontsNow
        )
        local timerFlagDD = _MakeFlagDropdown(
            "DoiteSettings_TimerFlagDD", b, 183, TIMER_Y + 6, 68,
            "timerFontFlags", _ApplyFontsNow
        )

        local stackLbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        stackLbl:SetPoint("TOPLEFT", b, "TOPLEFT", 15, STACKS_Y)
        stackLbl:SetText("Stacks:")
        if stackLbl.SetTextColor then stackLbl:SetTextColor(1, 0.82, 0) end

        local stackSizeBox = _MakeSizeBox(
            "DoiteSettings_StackSize", b, 45, STACKS_Y + 2, "stackFontSize", 10
        )
        local stackFontDD = _MakeFontDropdown(
            "DoiteSettings_StackFontDD", b, 75, STACKS_Y + 6, 90,
            "stackFontPath", _ApplyFontsNow
        )
        local stackFlagDD = _MakeFlagDropdown(
            "DoiteSettings_StackFlagDD", b, 183, STACKS_Y + 6, 68,
            "stackFontFlags", _ApplyFontsNow
        )

        local fontHint = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fontHint:SetPoint("TOPLEFT", b, "TOPLEFT", 15, STACKS_Y - 26)
        fontHint:SetWidth(250)
        fontHint:SetJustifyH("LEFT")
        if fontHint.SetTextColor then fontHint:SetTextColor(0.7, 0.7, 0.7) end
        fontHint:SetText("Size range: 4-48.")

        b.RefreshAll = function()
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
        end

        b:SetHeight(96)
        return b
    end

    ---------------------------------------------------------------
    -- Section: GLOW EFFECTS.
    --
    -- All controls write straight into DoiteAurasDB.glow (== the
    -- table returned by DG.GetSettings()), so values persist with no
    -- extra layer. Shape / color / texture / rotation changes call
    -- DG.BumpVersion() once per action to invalidate every cached
    -- overlay; speed changes live on OnUpdate ticks and skip the bump.
    ---------------------------------------------------------------
    local function Section_Glow(parent)
        local b = CreateFrame("Frame", nil, parent)
        b:SetWidth(280)

        local DG = _G["DoiteGlow"]
        if not (DG and type(DG.GetSettings) == "function") then
            b:SetHeight(0)
            return b
        end

        local gs = DG.GetSettings()

        local function _GlowCommit()
            if type(DG.BumpVersion) == "function" then
                DG.BumpVersion()
            end
        end

        -- Header + separator
        local glowHeader = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        glowHeader:SetPoint("TOPLEFT", b, "TOPLEFT", 15, 0)
        glowHeader:SetText("GLOW EFFECT")
        if glowHeader.SetTextColor then glowHeader:SetTextColor(1, 1, 1) end

        local glowSep = b:CreateTexture(nil, "ARTWORK")
        glowSep:SetHeight(1)
        glowSep:SetPoint("TOPLEFT", glowHeader, "BOTTOMLEFT", 0, -4)
        glowSep:SetPoint("TOPRIGHT", b, "TOPRIGHT", -15, 0)
        glowSep:SetTexture(1, 1, 1)
        if glowSep.SetVertexColor then glowSep:SetVertexColor(1, 1, 1, 0.25) end

        -- Row anchors, local to the section top.
        local GX        = 15
        local ROW_POS   = -30
        local ROW_SCALE = -56
        local ROW_ROT   = -78
        local ROW_SPEED = -100
        local ROW_ALPHA = -122
        local ROW_COL   = -148
        local ROW_TEX   = -189
        local ROW_PRESET      = ROW_TEX - 33
        local ROW_PRESET_HINT = ROW_TEX - 55

        -----------------------------------------------------------
        -- Position dropdown
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

        local posLbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        posLbl:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_POS)
        posLbl:SetText("Position:")
        if posLbl.SetTextColor then posLbl:SetTextColor(1, 0.82, 0) end

        local posDD = CreateFrame("Frame", "DoiteSettings_GlowPosDD",
            b, "UIDropDownMenuTemplate")
        posDD:SetPoint("TOPLEFT", b, "TOPLEFT", 42, ROW_POS + 6)
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
        -- Generic horizontal slider builder.
        --
        --   UI value = DB value * mult
        --   label    = UI value + suffix (or displayFn)
        -----------------------------------------------------------
        local function _MakeGlowSlider(name, y, field, minUI, maxUI, step, mult, suffix, asEditBox, displayFn)
            local slider = CreateFrame("Slider", name, b, "OptionsSliderTemplate")
            slider:SetWidth(130); slider:SetHeight(16)
            slider:SetPoint("TOPLEFT", b, "TOPLEFT", 58, y)
            slider:SetMinMaxValues(minUI, maxUI)
            slider:SetValueStep(step)
            slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
            if slider.SetOrientation then
                pcall(slider.SetOrientation, slider, "HORIZONTAL")
            end
            if slider.EnableMouse then slider:EnableMouse(true) end

            -- Re-assert range (OptionsSliderTemplate sometimes resets it).
            slider:SetMinMaxValues(minUI, maxUI)
            if slider.SetValueStep then slider:SetValueStep(step) end

            -- Hide built-in Low/High/Text fontstrings.
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

            local valTxt
            if asEditBox then
                local box = CreateFrame("EditBox", name .. "Value", b)
                box:SetWidth(50); box:SetHeight(18)
                box:SetAutoFocus(false)
                box:SetFontObject("GameFontNormalSmall")
                box:SetJustifyH("CENTER")
                box:SetPoint("TOPLEFT", b, "TOPLEFT", 190, y + 2)
                if box.SetTextInsets then box:SetTextInsets(2, 2, 0, 0) end
                if box.SetMaxLetters then box:SetMaxLetters(4) end

                if suffix and suffix ~= "" then
                    local sfx = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    sfx:SetPoint("LEFT", box, "RIGHT", 3, 0)
                    sfx:SetText(suffix)
                    if sfx.SetTextColor then sfx:SetTextColor(1, 0.82, 0) end
                end
                if box.EnableMouse then box:EnableMouse(true) end
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
                -- Same x as the EditBox branch so switching a slider
                -- between the two modes does not shift the label.
                valTxt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                valTxt:SetPoint("TOPLEFT", b, "TOPLEFT", 190, y)
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

        -- Scale
        local scaleLbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        scaleLbl:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_SCALE)
        scaleLbl:SetText("Scale:")
        if scaleLbl.SetTextColor then scaleLbl:SetTextColor(1, 0.82, 0) end

        local scaleSlider = _MakeGlowSlider(
            "DoiteSettings_GlowScaleSlider", ROW_SCALE,
            "scale", 50, 200, 5, 100, "%", true
        )

        -- Rotation (degrees). DB stores degrees; ApplyShape converts
        -- to radians when it (re)builds an overlay, so committing via
        -- _GlowCommit() redraws every active glow.
        local rotLbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rotLbl:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_ROT)
        rotLbl:SetText("Rotation:")
        if rotLbl.SetTextColor then rotLbl:SetTextColor(1, 0.82, 0) end

        local rotSlider = _MakeGlowSlider(
            "DoiteSettings_GlowRotationSlider", ROW_ROT,
            "rotation", 0, 360, 5, 1, "deg", true
        )

        -- Speed (relative units 1.0..10.0 in the UI; DB stores ms).
        local spdLbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        spdLbl:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_SPEED)
        spdLbl:SetText("Speed:")
        if spdLbl.SetTextColor then spdLbl:SetTextColor(1, 0.82, 0) end

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

        if spdSlider and spdSlider.SetScript then
            spdSlider:SetScript("OnEnter", function()
                if GameTooltip then
                    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                    GameTooltip:AddLine("Glow animation speed.", 1, 1, 1, 1)
                    GameTooltip:Show()
                end
            end)
            spdSlider:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
        end

        -- Alpha
        local alphaLbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        alphaLbl:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_ALPHA)
        alphaLbl:SetText("Alpha:")
        if alphaLbl.SetTextColor then alphaLbl:SetTextColor(1, 0.82, 0) end

        local alphaSlider = _MakeGlowSlider(
            "DoiteSettings_GlowAlphaSlider", ROW_ALPHA,
            "alpha", 0, 100, 5, 100, "%", true
        )

        -- Color
        local colLbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        colLbl:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_COL)
        colLbl:SetText("Color:")
        if colLbl.SetTextColor then colLbl:SetTextColor(1, 0.82, 0) end

        local colorBtn = CreateFrame("Button", "DoiteSettings_GlowColorBtn", b)
        colorBtn:SetWidth(60); colorBtn:SetHeight(18)
        colorBtn:SetPoint("TOPLEFT", b, "TOPLEFT", 62, ROW_COL + 3)
        colorBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        colorBtn:SetBackdropColor(0, 0, 0, 0.85)
        colorBtn:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

        local swatch = colorBtn:CreateTexture(nil, "ARTWORK")
        swatch:SetAllPoints(colorBtn)
        swatch:SetTexture("Interface\\Buttons\\WHITE8X8")

        colorBtn.Refresh = function()
            swatch:SetVertexColor(gs.r or 1, gs.g or 1, gs.b or 1, 1)
        end
        colorBtn.Refresh()

        colorBtn:SetScript("OnClick", function()
            if not ColorPickerFrame then return end

            if ColorPickerFrame.IsShown and ColorPickerFrame:IsShown() then
                ColorPickerFrame:Hide()
                return
            end

            -- Do NOT touch SetFrameLevel / SetToplevel on the picker:
            -- in 1.12 a top-level frame with an explicit high level
            -- can swallow clicks destined for its own child buttons
            -- (OK / Cancel stop responding). Strata + Raise is enough.
            if ColorPickerFrame.SetFrameStrata then
                ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            end
            if ColorPickerFrame.Raise then
                ColorPickerFrame:Raise()
            end

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

            local dragBar = _G["DoiteGlow_ColorPickerDragBar"]
            if not dragBar then
                dragBar = CreateFrame("Frame",
                    "DoiteGlow_ColorPickerDragBar", ColorPickerFrame)
                dragBar:SetHeight(18)
                dragBar:SetPoint("TOPLEFT",  ColorPickerFrame, "TOPLEFT",   6, -6)
                dragBar:SetPoint("TOPRIGHT", ColorPickerFrame, "TOPRIGHT", -36, -6)
                dragBar:EnableMouse(true)
                dragBar:RegisterForDrag("LeftButton")
                dragBar:SetScript("OnDragStart", function()
                    ColorPickerFrame:StartMoving()
                end)
                dragBar:SetScript("OnDragStop", function()
                    ColorPickerFrame:StopMovingOrSizing()
                end)
            end

            -- Shared ColorPicker plumbing. Only one OnHide hook is
            -- ever placed on the global ColorPickerFrame; whichever
            -- section opens the picker sets outer._cpCommit and the
            -- hook calls that on close. Section_Glow sets it to
            -- _GlowCommit (version bump), Section_Pop clears it
            -- (values are read fresh on the next pop, no bump).
            if not outer._cpHooked then
                outer._cpHooked = true
                local prevHide = nil
                if ColorPickerFrame.GetScript then
                    prevHide = ColorPickerFrame:GetScript("OnHide")
                end
                ColorPickerFrame:SetScript("OnHide", function()
                    if prevHide then prevHide() end
                    if outer._cpCommit then outer._cpCommit() end
                end)
            end
            outer._cpCommit = _GlowCommit

            ColorPickerFrame:Show()
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
            ColorPickerFrame.previousValues = {
                r = prevR, g = prevG, b = prevB, opacity = 1,
            }

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
        end)

        -----------------------------------------------------------
        -- Texture picker (thumbnail + button that opens the grid)
        -----------------------------------------------------------
        local texLbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        texLbl:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_TEX - 3)
        texLbl:SetText("Texture:")
        if texLbl.SetTextColor then texLbl:SetTextColor(1, 0.82, 0) end

        local texBtn = CreateFrame("Button", "DoiteSettings_GlowTexBtn",
            b, "UIPanelButtonTemplate")
        texBtn:SetWidth(126)
        texBtn:SetHeight(20)
        texBtn:SetPoint("TOPLEFT", b, "TOPLEFT", 60, ROW_TEX + 1)
        do
            local fs = texBtn.GetFontString and texBtn:GetFontString()
            if fs and fs.SetTextColor then fs:SetTextColor(1, 0.82, 0) end
        end

        local texPreview = b:CreateTexture(nil, "ARTWORK")
        texPreview:SetWidth(64)
        texPreview:SetHeight(64)
        texPreview:SetPoint("TOPLEFT", b, "TOPLEFT", 190, ROW_TEX + 44)

        local texPreviewBorder = b:CreateTexture(nil, "OVERLAY")
        texPreviewBorder:SetPoint("TOPLEFT",     texPreview, "TOPLEFT",     -1,  1)
        texPreviewBorder:SetPoint("BOTTOMRIGHT", texPreview, "BOTTOMRIGHT",  1, -1)
        texPreviewBorder:SetTexture(1, 1, 1, 0.25)

        local function _TexRefresh()
            local v = gs.texture

            local label = "?"
            if DG.GetTextureLabelForValue then
                label = DG.GetTextureLabelForValue(v)
            end
            texBtn:SetText(label)

            local tex, u0, u1, v0, v1 = v, 0, 1, 0, 1
            local list = DG.Textures
            if type(list) == "table" then
                local i
                for i = 1, table.getn(list) do
                    local e = list[i]
                    if e.value == v then
                        if e.tc then
                            u0, u1, v0, v1 = e.tc[1], e.tc[2], e.tc[3], e.tc[4]
                        end
                        break
                    end
                end
            end
            if v == "DOITE_GLOW" then
                tex = "Interface\\AddOns\\DoiteAuras\\Textures\\IconAlertAnts"
                u0, u1, v0, v1 = 0.0078, 0.1796, 0.0039, 0.1757
            end

            if type(tex) == "string" and tex ~= "" then
                texPreview:SetTexture(tex)
                texPreview:SetTexCoord(u0, u1, v0, v1)
            end
        end
        texBtn.Refresh = _TexRefresh

        texBtn:SetScript("OnClick", function()
            local P = _G["DoiteTexturePicker"]
            if not P or not P.Open then return end
            P.Open(
                DG.GetPickerEntries(),
                function() return gs.texture end,
                function(v)
                    gs.texture = v
                    _TexRefresh()
                    _GlowCommit()
                end,
                "Glow texture"
            )
        end)

        _TexRefresh()

        -----------------------------------------------------------
        -- Presets
        -----------------------------------------------------------
        local presetLbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        presetLbl:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_PRESET)
        presetLbl:SetText("Preset:")
        if presetLbl.SetTextColor then presetLbl:SetTextColor(1, 0.82, 0) end

        local presetDD = CreateFrame("Frame", "DoiteSettings_GlowPresetDD",
            b, "UIDropDownMenuTemplate")
        presetDD:SetPoint("TOPLEFT", b, "TOPLEFT", 30, ROW_PRESET + 6)
        if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(70, presetDD) end

        local function _PresetRefreshDD()
            local name = DoiteAurasDB and DoiteAurasDB.glowActivePreset
            if name then
                UIDropDownMenu_SetSelectedValue(presetDD, name)
                UIDropDownMenu_SetText(name, presetDD)
            else
                UIDropDownMenu_SetSelectedValue(presetDD, "__none")
                UIDropDownMenu_SetText("(none)", presetDD)
            end
        end

        UIDropDownMenu_Initialize(presetDD, function()
            local db = _G["DoiteAurasDB"]
            local cur = db and db.glowActivePreset or nil

            local info = UIDropDownMenu_CreateInfo()
            info.text    = "(none)"
            info.value   = "__none"
            info.checked = (cur == nil)
            info.func = function()
                if _G["DoiteAurasDB"] then
                    _G["DoiteAurasDB"].glowActivePreset = nil
                end
                _PresetRefreshDD()
            end
            UIDropDownMenu_AddButton(info)

            local names = DG.ListPresets()
            local i
            for i = 1, table.getn(names) do
                local pname = names[i]
                local info2 = UIDropDownMenu_CreateInfo()
                info2.text    = pname
                info2.value   = pname
                info2.checked = (cur == pname)
                info2.func = function(button)
                    local picked = (button and button.value) or pname
                    local db2 = _G["DoiteAurasDB"]
                    if not db2 or not db2.glowPresets then return end
                    local snap = db2.glowPresets[picked]
                    if not snap then return end
                    db2.glowActivePreset = picked
                    DG.ApplyPresetSnapshot(snap)
                    if content._daGlowRefreshAll then
                        content._daGlowRefreshAll()
                    end
                    _PresetRefreshDD()
                end
                UIDropDownMenu_AddButton(info2)
            end
        end)
        presetDD.Refresh = _PresetRefreshDD
        _PresetRefreshDD()
        do
            local t = _G[presetDD:GetName() .. "Text"]
            if t and t.SetTextColor then t:SetTextColor(1, 0.82, 0) end
        end

        local saveBtn = CreateFrame("Button", "DoiteSettings_GlowPresetSaveBtn",
            b, "UIPanelButtonTemplate")
        saveBtn:SetWidth(36)
        saveBtn:SetHeight(20)
        saveBtn:SetPoint("TOPLEFT", b, "TOPLEFT", 136, ROW_PRESET + 1)
        saveBtn:SetText("Save")

        local renBtn = CreateFrame("Button", "DoiteSettings_GlowPresetRenameBtn",
            b, "UIPanelButtonTemplate")
        renBtn:SetWidth(46)
        renBtn:SetHeight(20)
        renBtn:SetPoint("TOPLEFT", b, "TOPLEFT", 175, ROW_PRESET + 1)
        renBtn:SetText("Rename")

        local delBtn = CreateFrame("Button", "DoiteSettings_GlowPresetDeleteBtn",
            b, "UIPanelButtonTemplate")
        delBtn:SetWidth(46)
        delBtn:SetHeight(20)
        delBtn:SetPoint("TOPLEFT", b, "TOPLEFT", 224, ROW_PRESET + 1)
        delBtn:SetText("Delete")

        local presetHint = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        presetHint:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_PRESET_HINT - 2)
        presetHint:SetWidth(250)
        presetHint:SetJustifyH("LEFT")
        if presetHint.SetTextColor then presetHint:SetTextColor(0.7, 0.7, 0.7) end
        presetHint:SetText("Unsaved changes reset on reload.")

        -----------------------------------------------------------
        -- Rename / Delete dialogs, parented to outer so they do not
        -- scroll. Created lazily on first use.
        -----------------------------------------------------------
        local function _GlowShowRenameDialog()
            if not outer._glowRenameDlg then
                local d = CreateFrame("Frame", "DoiteSettings_GlowRenameDlg", outer)
                d:SetWidth(260)
                d:SetHeight(96)
                d:SetPoint("CENTER", outer, "CENTER", 0, 0)
                d:SetFrameStrata("FULLSCREEN_DIALOG")
                d:SetFrameLevel(outer:GetFrameLevel() + 10)
                d:EnableMouse(true)
                d:SetBackdrop({
                    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                    tile = true, tileSize = 16, edgeSize = 32,
                    insets = { left = 11, right = 12, top = 12, bottom = 11 },
                })
                d:SetBackdropColor(0, 0, 0, 1)
                d:SetBackdropBorderColor(1, 1, 1, 1)
                d:Hide()

                local dtitle = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                dtitle:SetPoint("TOPLEFT", d, "TOPLEFT", 15, -14)
                dtitle:SetText("Rename preset")

                local eb = CreateFrame("EditBox", "DoiteSettings_GlowRenameEB", d)
                eb:SetWidth(220)
                eb:SetHeight(20)
                eb:SetPoint("TOPLEFT", d, "TOPLEFT", 15, -38)
                eb:SetAutoFocus(false)
                eb:SetFontObject("GameFontNormalSmall")
                if eb.SetTextInsets then eb:SetTextInsets(4, 4, 0, 0) end
                eb:SetBackdrop({
                    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 12,
                    insets = { left = 3, right = 3, top = 3, bottom = 3 },
                })
                eb:SetBackdropColor(0, 0, 0, 0.85)
                eb:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
                d.eb = eb

                local okBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
                okBtn:SetWidth(80)
                okBtn:SetHeight(20)
                okBtn:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -15, 12)
                okBtn:SetText("OK")

                local cancelBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
                cancelBtn:SetWidth(80)
                cancelBtn:SetHeight(20)
                cancelBtn:SetPoint("RIGHT", okBtn, "LEFT", -6, 0)
                cancelBtn:SetText("Cancel")
                cancelBtn:SetScript("OnClick", function() d:Hide() end)

                local function _Commit()
                    local to = eb:GetText() or ""
                    to = string.gsub(to, "^%s*(.-)%s*$", "%1")
                    if to == "" then
                        d:Hide()
                        return
                    end
                    local from = d._from
                    if from and from ~= to then
                        DG.RenamePreset(from, to)
                        _PresetRefreshDD()
                    end
                    d:Hide()
                end

                okBtn:SetScript("OnClick", _Commit)
                eb:SetScript("OnEnterPressed", _Commit)
                eb:SetScript("OnEscapePressed", function()
                    eb:ClearFocus()
                    d:Hide()
                end)

                outer._glowRenameDlg = d
            end

            local d = outer._glowRenameDlg
            local cur = DoiteAurasDB and DoiteAurasDB.glowActivePreset
            d._from = cur
            d.eb:SetText(cur or "")
            d:Show()
            d.eb:SetFocus()
            d.eb:HighlightText()
        end

        local function _GlowShowDeleteDialog()
            if not outer._glowDeleteDlg then
                local d = CreateFrame("Frame", "DoiteSettings_GlowDeleteDlg", outer)
                d:SetWidth(260)
                d:SetHeight(90)
                d:SetPoint("CENTER", outer, "CENTER", 0, 0)
                d:SetFrameStrata("FULLSCREEN_DIALOG")
                d:SetFrameLevel(outer:GetFrameLevel() + 10)
                d:EnableMouse(true)
                d:SetBackdrop({
                    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                    tile = true, tileSize = 16, edgeSize = 32,
                    insets = { left = 11, right = 12, top = 12, bottom = 11 },
                })
                d:SetBackdropColor(0, 0, 0, 1)
                d:SetBackdropBorderColor(1, 1, 1, 1)
                d:Hide()

                local txt = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                txt:SetPoint("TOPLEFT", d, "TOPLEFT", 15, -20)
                txt:SetWidth(230)
                txt:SetJustifyH("LEFT")
                d.txt = txt

                local yesBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
                yesBtn:SetWidth(80)
                yesBtn:SetHeight(20)
                yesBtn:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -15, 12)
                yesBtn:SetText("Yes")

                local noBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
                noBtn:SetWidth(80)
                noBtn:SetHeight(20)
                noBtn:SetPoint("RIGHT", yesBtn, "LEFT", -6, 0)
                noBtn:SetText("No")
                noBtn:SetScript("OnClick", function() d:Hide() end)

                yesBtn:SetScript("OnClick", function()
                    local name = d._name
                    if name then
                        DG.DeletePreset(name)
                        _PresetRefreshDD()
                    end
                    d:Hide()
                end)

                outer._glowDeleteDlg = d
            end

            local d = outer._glowDeleteDlg
            local cur = DoiteAurasDB and DoiteAurasDB.glowActivePreset
            if not cur then return end
            d._name = cur
            d.txt:SetText("Delete preset '" .. cur .. "'?")
            d:Show()
        end

        saveBtn:SetScript("OnClick", function()
            DG.SaveCurrentAsPreset()
            _PresetRefreshDD()
        end)
        renBtn:SetScript("OnClick", _GlowShowRenameDialog)
        delBtn:SetScript("OnClick", _GlowShowDeleteDialog)

        -----------------------------------------------------------
        -- Persist the refresh aggregator on `content` so OnShow (which
        -- runs later with `content` in scope) can call it in one line.
        -----------------------------------------------------------
        local gc = {
            scale    = scaleSlider,
            rotation = rotSlider,
            alpha    = alphaSlider,
            speed    = spdSlider,
            pos      = posDD,
            tex      = texBtn,
            color    = colorBtn,
            preset   = presetDD,
        }
        content._daGlowControls = gc

        content._daGlowRefreshAll = function()
            if gc.scale    and gc.scale.Refresh    then gc.scale:Refresh()    end
            if gc.rotation and gc.rotation.Refresh then gc.rotation:Refresh() end
            if gc.alpha    and gc.alpha.Refresh    then gc.alpha:Refresh()    end
            if gc.speed    and gc.speed.Refresh    then gc.speed:Refresh()    end
            if gc.pos      and gc.pos.Refresh      then gc.pos:Refresh()      end
            if gc.tex      and gc.tex.Refresh      then gc.tex:Refresh()      end
            if gc.color    and gc.color.Refresh    then gc.color:Refresh()    end
            if gc.preset   and gc.preset.Refresh   then gc.preset:Refresh()   end
        end

        b:SetHeight(-ROW_PRESET_HINT + 20)
        return b
    end

    ---------------------------------------------------------------
    -- Section: CAST POPUP (DoitePop).
    --
    -- Controls the cast-confirmation pop animation: a copy of the
    -- icon scales up and fades out, plus an additive glow that
    -- peaks mid-flight. All values live in DoiteAurasDB.pop; the
    -- module snapshots them per pop in Start(), so changes here
    -- take effect on the next cast.
    ---------------------------------------------------------------
    local function Section_Pop(parent)
        local b = CreateFrame("Frame", nil, parent)
        b:SetWidth(280)

        local DP = _G["DoitePop"]
        if not (DP and type(DP.GetSettings) == "function") then
            b:SetHeight(0)
            return b
        end

        local ps = DP.GetSettings()

        local popHeader = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        popHeader:SetPoint("TOPLEFT", b, "TOPLEFT", 15, 0)
        popHeader:SetText("POPUP EFFECT")
        if popHeader.SetTextColor then popHeader:SetTextColor(1, 1, 1) end

        local popSep = b:CreateTexture(nil, "ARTWORK")
        popSep:SetHeight(1)
        popSep:SetPoint("TOPLEFT", popHeader, "BOTTOMLEFT", 0, -4)
        popSep:SetPoint("TOPRIGHT", b, "TOPRIGHT", -15, 0)
        popSep:SetTexture(1, 1, 1)
        if popSep.SetVertexColor then popSep:SetVertexColor(1, 1, 1, 0.25) end

        -- Short description under the header. Deliberately not worded
        -- around ability casts, because the effect is designed to be
        -- reusable for other trigger events (e.g. aura expiry).
        local popHint = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        popHint:SetPoint("TOPLEFT", b, "TOPLEFT", 15, -24)
        popHint:SetWidth(250)
        popHint:SetJustifyH("LEFT")
        if popHint.SetTextColor then popHint:SetTextColor(0.7, 0.7, 0.7) end
        popHint:SetText("A short scale + glow burst over the icon. Reusable for various in-game events.")

        -- Reserve vertical space for the hint above; rows below shift
        -- down by this amount. ROW_PRESET* derive from ROW_GLOW_T so
        -- they auto-follow. Section height is derived from ROW_PRESET_HINT
        -- at the end, so the block auto-grows.
        local POP_HINT_SHIFT = 30

        local GX           = 15
        local ROW_DURATION = -30 - POP_HINT_SHIFT
        local ROW_PEAK     = -52 - POP_HINT_SHIFT
        local ROW_GLOW_A   = -74 - POP_HINT_SHIFT
        local ROW_GLOW_S   = -96 - POP_HINT_SHIFT
        local ROW_GLOW_C   = -122 - POP_HINT_SHIFT
        local ROW_GLOW_T   = -163 - POP_HINT_SHIFT
        local ROW_PRESET      = ROW_GLOW_T - 33
        local ROW_PRESET_HINT = ROW_GLOW_T - 55

        -----------------------------------------------------------
        -- Slider builder. Same visual recipe as the Glow sliders;
        -- EditBox is always present since every value here is
        -- numeric. `mult` maps DB value -> UI integer.
        -----------------------------------------------------------
        local function _MakePopSlider(name, y, field, minUI, maxUI, step, mult, suffix, displayFn)
            local slider = CreateFrame("Slider", name, b, "OptionsSliderTemplate")
            slider:SetWidth(130); slider:SetHeight(16)
            slider:SetPoint("TOPLEFT", b, "TOPLEFT", 58, y)
            slider:SetMinMaxValues(minUI, maxUI)
            slider:SetValueStep(step)
            slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
            if slider.SetOrientation then
                pcall(slider.SetOrientation, slider, "HORIZONTAL")
            end
            if slider.EnableMouse then slider:EnableMouse(true) end

            slider:SetMinMaxValues(minUI, maxUI)
            if slider.SetValueStep then slider:SetValueStep(step) end

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

            local box = CreateFrame("EditBox", name .. "Value", b)
            box:SetWidth(50); box:SetHeight(18)
            box:SetAutoFocus(false)
            box:SetFontObject("GameFontNormalSmall")
            box:SetJustifyH("CENTER")
            box:SetPoint("TOPLEFT", b, "TOPLEFT", 190, y + 2)
            if box.SetTextInsets then box:SetTextInsets(2, 2, 0, 0) end
            if box.SetMaxLetters then box:SetMaxLetters(5) end

            if suffix and suffix ~= "" then
                local sfx = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                sfx:SetPoint("LEFT", box, "RIGHT", 3, 0)
                sfx:SetText(suffix)
                if sfx.SetTextColor then sfx:SetTextColor(1, 0.82, 0) end
            end
            if box.EnableMouse then box:EnableMouse(true) end
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

            local function _Show()
                local ui = math.floor((tonumber(ps[field]) or 0) * mult + 0.5)
                if displayFn then
                    box:SetText(displayFn(ui))
                else
                    box:SetText(tostring(ui))
                end
            end

            slider.Refresh = function()
                if slider.SetMinMaxValues then
                    slider:SetMinMaxValues(minUI, maxUI)
                end
                local ui = math.floor((tonumber(ps[field]) or 0) * mult + 0.5)
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
                ps[field] = rounded / mult
                _Show()
            end)

            box:SetScript("OnEditFocusGained", function()
                box:SetTextColor(1, 0.82, 0)
            end)
            box:SetScript("OnEditFocusLost", function()
                local v = tonumber(box:GetText() or "")
                if v and v >= minUI and v <= maxUI then
                    ps[field] = math.floor(v + 0.5) / mult
                end
                if slider.SetValue then
                    slider:SetValue(math.floor((tonumber(ps[field]) or 0) * mult + 0.5))
                end
            end)
            box:SetScript("OnEnterPressed", function() box:ClearFocus() end)
            box:SetScript("OnEscapePressed", function()
                box:SetText(tostring(math.floor((tonumber(ps[field]) or 0) * mult + 0.5)))
                box:ClearFocus()
            end)

            slider.Refresh()
            return slider
        end

        -- Duration (ms in UI, seconds in DB). 50..2000 ms.
        local durLbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        durLbl:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_DURATION)
        durLbl:SetText("Duration:")
        if durLbl.SetTextColor then durLbl:SetTextColor(1, 0.82, 0) end

        local durationSlider = _MakePopSlider(
            "DoiteSettings_PopDurationSlider", ROW_DURATION,
            "duration", 50, 2000, 25, 1000, "ms"
        )

        if durationSlider and durationSlider.SetScript then
            durationSlider:SetScript("OnEnter", function()
                if GameTooltip then
                    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                    GameTooltip:AddLine("Pop animation length.", 1, 1, 1, 1)
                    GameTooltip:Show()
                end
            end)
            durationSlider:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
        end

        -- Peak scale (UI integer 100..300 = 1.00..3.00).
        local peakLbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        peakLbl:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_PEAK)
        peakLbl:SetText("Peak scale:")
        if peakLbl.SetTextColor then peakLbl:SetTextColor(1, 0.82, 0) end

        local peakSlider = _MakePopSlider(
            "DoiteSettings_PopPeakSlider", ROW_PEAK,
            "peakScale", 100, 300, 5, 100, "%"
        )

        if peakSlider and peakSlider.SetScript then
            peakSlider:SetScript("OnEnter", function()
                if GameTooltip then
                    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                    GameTooltip:AddLine("Maximum icon scale during the pop.", 1, 1, 1, 1)
                    GameTooltip:Show()
                end
            end)
            peakSlider:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
        end

        -- Glow peak alpha (0..100).
        local glowALbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        glowALbl:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_GLOW_A)
        glowALbl:SetText("Glow alpha:")
        if glowALbl.SetTextColor then glowALbl:SetTextColor(1, 0.82, 0) end

        local glowASlider = _MakePopSlider(
            "DoiteSettings_PopGlowAlphaSlider", ROW_GLOW_A,
            "glowAlpha", 0, 100, 5, 100, "%"
        )

        -- Extra glow scale at the end (0..1000 = 0..10.00x).
        local glowSLbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        glowSLbl:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_GLOW_S)
        glowSLbl:SetText("Glow scale:")
        if glowSLbl.SetTextColor then glowSLbl:SetTextColor(1, 0.82, 0) end

        local glowSSlider = _MakePopSlider(
            "DoiteSettings_PopGlowScaleSlider", ROW_GLOW_S,
            "glowScaleExtra", 0, 1000, 25, 100, "x"
        )

        -- Glow color.
        local glowCLbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        glowCLbl:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_GLOW_C)
        glowCLbl:SetText("Glow color:")
        if glowCLbl.SetTextColor then glowCLbl:SetTextColor(1, 0.82, 0) end

        local glowColorBtn = CreateFrame("Button", "DoiteSettings_PopColorBtn", b)
        glowColorBtn:SetWidth(60); glowColorBtn:SetHeight(18)
        glowColorBtn:SetPoint("TOPLEFT", b, "TOPLEFT", 75, ROW_GLOW_C + 3)
        glowColorBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        glowColorBtn:SetBackdropColor(0, 0, 0, 0.85)
        glowColorBtn:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

        local glowSwatch = glowColorBtn:CreateTexture(nil, "ARTWORK")
        glowSwatch:SetAllPoints(glowColorBtn)
        glowSwatch:SetTexture("Interface\\Buttons\\WHITE8X8")

        glowColorBtn.Refresh = function()
            glowSwatch:SetVertexColor(ps.glowR or 1, ps.glowG or 1, ps.glowB or 1, 1)
        end
        glowColorBtn.Refresh()

        glowColorBtn:SetScript("OnClick", function()
            if not ColorPickerFrame then return end
            -- Pop commits the color directly into DoiteAurasDB.pop as
            -- the user drags; no version bump is needed (the next pop
            -- reads fresh). Clear the shared ColorPicker commit so the
            -- OnHide hook installed by Section_Glow does not fire
            -- _GlowCommit for a picker that belonged to Pop.
            outer._cpCommit = nil

            if ColorPickerFrame.IsShown and ColorPickerFrame:IsShown() then
                ColorPickerFrame:Hide()
                return
            end

            if ColorPickerFrame.SetFrameStrata then
                ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            end
            if ColorPickerFrame.Raise then
                ColorPickerFrame:Raise()
            end

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

            local dragBar = _G["DoiteGlow_ColorPickerDragBar"]
            if not dragBar then
                dragBar = CreateFrame("Frame",
                    "DoiteGlow_ColorPickerDragBar", ColorPickerFrame)
                dragBar:SetHeight(18)
                dragBar:SetPoint("TOPLEFT",  ColorPickerFrame, "TOPLEFT",   6, -6)
                dragBar:SetPoint("TOPRIGHT", ColorPickerFrame, "TOPRIGHT", -36, -6)
                dragBar:EnableMouse(true)
                dragBar:RegisterForDrag("LeftButton")
                dragBar:SetScript("OnDragStart", function()
                    ColorPickerFrame:StartMoving()
                end)
                dragBar:SetScript("OnDragStop", function()
                    ColorPickerFrame:StopMovingOrSizing()
                end)
            end

            ColorPickerFrame:Show()
            if ColorPickerFrame.Raise then ColorPickerFrame:Raise() end

            local prevR, prevG, prevB = ps.glowR or 1, ps.glowG or 1, ps.glowB or 1

            if ColorPickerFrame.SetColorRGB then
                ColorPickerFrame:SetColorRGB(prevR, prevG, prevB)
            end
            if ColorPickerFrame.hasOpacity ~= nil then
                ColorPickerFrame.hasOpacity = false
            end
            ColorPickerFrame.previousValues = {
                r = prevR, g = prevG, b = prevB, opacity = 1,
            }

            ColorPickerFrame.func = function()
                if ColorPickerFrame.GetColorRGB then
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    if r then ps.glowR = r end
                    if g then ps.glowG = g end
                    if b then ps.glowB = b end
                    glowColorBtn.Refresh()
                end
            end
            ColorPickerFrame.cancelFunc = function()
                ps.glowR, ps.glowG, ps.glowB = prevR, prevG, prevB
                glowColorBtn.Refresh()
            end
        end)

        -- Glow texture: button opens the grid picker, small preview
        -- beside it. Same layout pattern as Section_Glow.
        local glowTLbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        glowTLbl:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_GLOW_T)
        glowTLbl:SetText("Texture:")
        if glowTLbl.SetTextColor then glowTLbl:SetTextColor(1, 0.82, 0) end

        local glowTexBtn = CreateFrame("Button", "DoiteSettings_PopTexBtn",
            b, "UIPanelButtonTemplate")
        glowTexBtn:SetWidth(126)
        glowTexBtn:SetHeight(20)
        glowTexBtn:SetPoint("TOPLEFT", b, "TOPLEFT", 60, ROW_GLOW_T + 1)
        do
            local fs = glowTexBtn.GetFontString and glowTexBtn:GetFontString()
            if fs and fs.SetTextColor then fs:SetTextColor(1, 0.82, 0) end
        end

        local popTexPreview = b:CreateTexture(nil, "ARTWORK")
        popTexPreview:SetWidth(64)
        popTexPreview:SetHeight(64)
        popTexPreview:SetPoint("TOPLEFT", b, "TOPLEFT", 190, ROW_GLOW_T + 44)

        local popTexPreviewBorder = b:CreateTexture(nil, "OVERLAY")
        popTexPreviewBorder:SetPoint("TOPLEFT",     popTexPreview, "TOPLEFT",     -1,  1)
        popTexPreviewBorder:SetPoint("BOTTOMRIGHT", popTexPreview, "BOTTOMRIGHT",  1, -1)
        popTexPreviewBorder:SetTexture(1, 1, 1, 0.25)

        local function _PopTexRefresh()
            local v = ps.glowTexture

            local label = "?"
            if DP.GetTextureLabelForValue then
                label = DP.GetTextureLabelForValue(v)
            end
            glowTexBtn:SetText(label)

            if type(v) == "string" and v ~= "" then
                popTexPreview:SetTexture(v)
                popTexPreview:SetTexCoord(0, 1, 0, 1)
            end
        end
        glowTexBtn.Refresh = _PopTexRefresh

        glowTexBtn:SetScript("OnClick", function()
            local P = _G["DoiteTexturePicker"]
            if not P or not P.Open then return end
            P.Open(
                DP.GetPickerEntries(),
                function() return ps.glowTexture end,
                function(v)
                    ps.glowTexture = v
                    _PopTexRefresh()
                end,
                "Pop glow texture"
            )
        end)

        _PopTexRefresh()

        -----------------------------------------------------------
        -- Presets. Same UX as Section_Glow, with one protected entry:
        -- "default" cannot be renamed or deleted.
        -----------------------------------------------------------
        local presetLbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        presetLbl:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_PRESET)
        presetLbl:SetText("Preset:")
        if presetLbl.SetTextColor then presetLbl:SetTextColor(1, 0.82, 0) end

        local popPresetDD = CreateFrame("Frame", "DoiteSettings_PopPresetDD",
            b, "UIDropDownMenuTemplate")
        popPresetDD:SetPoint("TOPLEFT", b, "TOPLEFT", 30, ROW_PRESET + 6)
        if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(70, popPresetDD) end

        local function _PopPresetRefreshDD()
            local name = DoiteAurasDB and DoiteAurasDB.popActivePreset
            if name then
                UIDropDownMenu_SetSelectedValue(popPresetDD, name)
                UIDropDownMenu_SetText(name, popPresetDD)
            else
                UIDropDownMenu_SetSelectedValue(popPresetDD, "__none")
                UIDropDownMenu_SetText("(none)", popPresetDD)
            end
        end

        UIDropDownMenu_Initialize(popPresetDD, function()
            local db = _G["DoiteAurasDB"]
            local cur = db and db.popActivePreset or nil

            local info = UIDropDownMenu_CreateInfo()
            info.text    = "(none)"
            info.value   = "__none"
            info.checked = (cur == nil)
            info.func = function()
                if _G["DoiteAurasDB"] then
                    _G["DoiteAurasDB"].popActivePreset = nil
                end
                _PopPresetRefreshDD()
            end
            UIDropDownMenu_AddButton(info)

            local names = DP.ListPresets()
            local i
            for i = 1, table.getn(names) do
                local pname = names[i]
                local info2 = UIDropDownMenu_CreateInfo()
                info2.text    = pname
                info2.value   = pname
                info2.checked = (cur == pname)
                info2.func = function(button)
                    local picked = (button and button.value) or pname
                    local db2 = _G["DoiteAurasDB"]
                    if not db2 or not db2.popPresets then return end
                    local snap = db2.popPresets[picked]
                    if not snap then return end
                    db2.popActivePreset = picked
                    DP.ApplyPresetSnapshot(snap)
                    if content._daPopRefreshAll then
                        content._daPopRefreshAll()
                    end
                    _PopPresetRefreshDD()
                end
                UIDropDownMenu_AddButton(info2)
            end
        end)
        popPresetDD.Refresh = _PopPresetRefreshDD
        _PopPresetRefreshDD()
        do
            local t = _G[popPresetDD:GetName() .. "Text"]
            if t and t.SetTextColor then t:SetTextColor(1, 0.82, 0) end
        end

        local popSaveBtn = CreateFrame("Button", "DoiteSettings_PopPresetSaveBtn",
            b, "UIPanelButtonTemplate")
        popSaveBtn:SetWidth(36)
        popSaveBtn:SetHeight(20)
        popSaveBtn:SetPoint("TOPLEFT", b, "TOPLEFT", 136, ROW_PRESET + 1)
        popSaveBtn:SetText("Save")

        local popRenBtn = CreateFrame("Button", "DoiteSettings_PopPresetRenameBtn",
            b, "UIPanelButtonTemplate")
        popRenBtn:SetWidth(46)
        popRenBtn:SetHeight(20)
        popRenBtn:SetPoint("TOPLEFT", b, "TOPLEFT", 175, ROW_PRESET + 1)
        popRenBtn:SetText("Rename")

        local popDelBtn = CreateFrame("Button", "DoiteSettings_PopPresetDeleteBtn",
            b, "UIPanelButtonTemplate")
        popDelBtn:SetWidth(46)
        popDelBtn:SetHeight(20)
        popDelBtn:SetPoint("TOPLEFT", b, "TOPLEFT", 224, ROW_PRESET + 1)
        popDelBtn:SetText("Delete")

        local popPresetHint = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        popPresetHint:SetPoint("TOPLEFT", b, "TOPLEFT", GX, ROW_PRESET_HINT - 2)
        popPresetHint:SetWidth(250)
        popPresetHint:SetJustifyH("LEFT")
        if popPresetHint.SetTextColor then popPresetHint:SetTextColor(0.7, 0.7, 0.7) end
        popPresetHint:SetText("'default' preset is protected.")

        -----------------------------------------------------------
        -- Rename dialog. Refuses when "default" is active.
        -----------------------------------------------------------
        local function _PopShowRenameDialog()
            local cur = DoiteAurasDB and DoiteAurasDB.popActivePreset
            if not cur then return end
            if DP.IsDefaultPreset(cur) then
                local cf = (DEFAULT_CHAT_FRAME or ChatFrame1)
                if cf then
                    cf:AddMessage("|cff6FA8DCDoiteSettings:|r cannot rename the protected 'default' preset.")
                end
                return
            end

            if not outer._popRenameDlg then
                local d = CreateFrame("Frame", "DoiteSettings_PopRenameDlg", outer)
                d:SetWidth(260)
                d:SetHeight(96)
                d:SetPoint("CENTER", outer, "CENTER", 0, 0)
                d:SetFrameStrata("FULLSCREEN_DIALOG")
                d:SetFrameLevel(outer:GetFrameLevel() + 10)
                d:EnableMouse(true)
                d:SetBackdrop({
                    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                    tile = true, tileSize = 16, edgeSize = 32,
                    insets = { left = 11, right = 12, top = 12, bottom = 11 },
                })
                d:SetBackdropColor(0, 0, 0, 1)
                d:SetBackdropBorderColor(1, 1, 1, 1)
                d:Hide()

                local dtitle = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                dtitle:SetPoint("TOPLEFT", d, "TOPLEFT", 15, -14)
                dtitle:SetText("Rename preset")

                local eb = CreateFrame("EditBox", "DoiteSettings_PopRenameEB", d)
                eb:SetWidth(220)
                eb:SetHeight(20)
                eb:SetPoint("TOPLEFT", d, "TOPLEFT", 15, -38)
                eb:SetAutoFocus(false)
                eb:SetFontObject("GameFontNormalSmall")
                if eb.SetTextInsets then eb:SetTextInsets(4, 4, 0, 0) end
                eb:SetBackdrop({
                    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 12,
                    insets = { left = 3, right = 3, top = 3, bottom = 3 },
                })
                eb:SetBackdropColor(0, 0, 0, 0.85)
                eb:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
                d.eb = eb

                local okBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
                okBtn:SetWidth(80)
                okBtn:SetHeight(20)
                okBtn:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -15, 12)
                okBtn:SetText("OK")

                local cancelBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
                cancelBtn:SetWidth(80)
                cancelBtn:SetHeight(20)
                cancelBtn:SetPoint("RIGHT", okBtn, "LEFT", -6, 0)
                cancelBtn:SetText("Cancel")
                cancelBtn:SetScript("OnClick", function() d:Hide() end)

                local function _Commit()
                    local to = eb:GetText() or ""
                    to = string.gsub(to, "^%s*(.-)%s*$", "%1")
                    if to == "" then
                        d:Hide()
                        return
                    end
                    local from = d._from
                    if from and from ~= to then
                        DP.RenamePreset(from, to)
                        _PopPresetRefreshDD()
                    end
                    d:Hide()
                end

                okBtn:SetScript("OnClick", _Commit)
                eb:SetScript("OnEnterPressed", _Commit)
                eb:SetScript("OnEscapePressed", function()
                    eb:ClearFocus()
                    d:Hide()
                end)

                outer._popRenameDlg = d
            end

            local d = outer._popRenameDlg
            d._from = cur
            d.eb:SetText(cur or "")
            d:Show()
            d.eb:SetFocus()
            d.eb:HighlightText()
        end

        -----------------------------------------------------------
        -- Delete dialog. Refuses when "default" is active.
        -----------------------------------------------------------
        local function _PopShowDeleteDialog()
            local cur = DoiteAurasDB and DoiteAurasDB.popActivePreset
            if not cur then return end
            if DP.IsDefaultPreset(cur) then
                local cf = (DEFAULT_CHAT_FRAME or ChatFrame1)
                if cf then
                    cf:AddMessage("|cff6FA8DCDoiteSettings:|r cannot delete the protected 'default' preset.")
                end
                return
            end

            if not outer._popDeleteDlg then
                local d = CreateFrame("Frame", "DoiteSettings_PopDeleteDlg", outer)
                d:SetWidth(260)
                d:SetHeight(90)
                d:SetPoint("CENTER", outer, "CENTER", 0, 0)
                d:SetFrameStrata("FULLSCREEN_DIALOG")
                d:SetFrameLevel(outer:GetFrameLevel() + 10)
                d:EnableMouse(true)
                d:SetBackdrop({
                    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                    tile = true, tileSize = 16, edgeSize = 32,
                    insets = { left = 11, right = 12, top = 12, bottom = 11 },
                })
                d:SetBackdropColor(0, 0, 0, 1)
                d:SetBackdropBorderColor(1, 1, 1, 1)
                d:Hide()

                local txt = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                txt:SetPoint("TOPLEFT", d, "TOPLEFT", 15, -20)
                txt:SetWidth(230)
                txt:SetJustifyH("LEFT")
                d.txt = txt

                local yesBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
                yesBtn:SetWidth(80)
                yesBtn:SetHeight(20)
                yesBtn:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -15, 12)
                yesBtn:SetText("Yes")

                local noBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
                noBtn:SetWidth(80)
                noBtn:SetHeight(20)
                noBtn:SetPoint("RIGHT", yesBtn, "LEFT", -6, 0)
                noBtn:SetText("No")
                noBtn:SetScript("OnClick", function() d:Hide() end)

                yesBtn:SetScript("OnClick", function()
                    local name = d._name
                    if name then
                        DP.DeletePreset(name)
                        _PopPresetRefreshDD()
                    end
                    d:Hide()
                end)

                outer._popDeleteDlg = d
            end

            local d = outer._popDeleteDlg
            d._name = cur
            d.txt:SetText("Delete preset '" .. cur .. "'?")
            d:Show()
        end

        popSaveBtn:SetScript("OnClick", function()
            DP.SaveCurrentAsPreset()
            _PopPresetRefreshDD()
        end)
        popRenBtn:SetScript("OnClick", _PopShowRenameDialog)
        popDelBtn:SetScript("OnClick", _PopShowDeleteDialog)

        -- Refresh aggregator, called from outer OnShow and after a
        -- preset is applied.
        content._daPopRefreshAll = function()
            durationSlider:Refresh()
            peakSlider:Refresh()
            glowASlider:Refresh()
            glowSSlider:Refresh()
            glowColorBtn.Refresh()
            glowTexBtn.Refresh()
            popPresetDD.Refresh()
        end

        b:SetHeight(-ROW_PRESET_HINT + 20)
        return b
    end

    ---------------------------------------------------------------
    -- Section: DEBUG (aura counts, overcap sim, spell cast debug).
    ---------------------------------------------------------------
    local function Section_Debug(parent)
        local b = CreateFrame("Frame", nil, parent)
        b:SetWidth(280)

        local debugHeader = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        debugHeader:SetPoint("TOPLEFT", b, "TOPLEFT", 15, 0)
        debugHeader:SetText("DEBUG")
        if debugHeader.SetTextColor then debugHeader:SetTextColor(1, 1, 1) end

        local debugSep = b:CreateTexture(nil, "ARTWORK")
        debugSep:SetHeight(1)
        debugSep:SetPoint("TOPLEFT", debugHeader, "BOTTOMLEFT", 0, -4)
        debugSep:SetPoint("TOPRIGHT", b, "TOPRIGHT", -15, 0)
        debugSep:SetTexture(1, 1, 1)
        if debugSep.SetVertexColor then debugSep:SetVertexColor(1, 1, 1, 0.25) end

        local overcapBtn = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
        overcapBtn:SetWidth(120); overcapBtn:SetHeight(20)
        overcapBtn:SetPoint("TOPLEFT", b, "TOPLEFT", 15, -25)

        local spellCastDebugBtn = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
        spellCastDebugBtn:SetWidth(120); spellCastDebugBtn:SetHeight(20)
        spellCastDebugBtn:SetPoint("TOPLEFT", overcapBtn, "TOPLEFT", 0, -25)

        local playerAuraCountBtn = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
        playerAuraCountBtn:SetWidth(120); playerAuraCountBtn:SetHeight(20)
        playerAuraCountBtn:SetPoint("LEFT", spellCastDebugBtn, "RIGHT", 5, 0)

        local targetAuraCountBtn = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
        targetAuraCountBtn:SetWidth(120); targetAuraCountBtn:SetHeight(20)
        targetAuraCountBtn:SetPoint("LEFT", overcapBtn, "RIGHT", 5, 0)

        -----------------------------------------------------------
        -- Live aura count overlay (UIParent-anchored, not scrolled).
        -----------------------------------------------------------
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

        -- Prime each once so the initial state is correct.
        DS_UpdateSpellCastDebugButton()
        DS_UpdateOvercapButton()
        DS_UpdatePlayerAuraCountButton()
        DS_UpdateTargetAuraCountButton()
        DS_SetAuraCountOverlayRunning(false)

        b.UpdateAll = function()
            DS_UpdateSpellCastDebugButton()
            DS_UpdateOvercapButton()
            DS_UpdatePlayerAuraCountButton()
            DS_UpdateTargetAuraCountButton()
            DS_UpdateAuraCountOverlayOnce()
        end

        b:SetHeight(70)
        return b
    end

    ---------------------------------------------------------------
    -- Stack the sections and size the content frame.
    ---------------------------------------------------------------
    local reqBlock     = stackAdd(Section_Requirements)
    local togglesBlock = stackAdd(Section_Toggles, SECTION_SHIFT.Toggles)
    local fontsBlock   = stackAdd(Section_Fonts,   SECTION_SHIFT.Fonts)
    local glowBlock    = stackAdd(Section_Glow,    SECTION_SHIFT.Glow)
    local popBlock     = stackAdd(Section_Pop,     SECTION_SHIFT.Pop)
    local debugBlock   = stackAdd(Section_Debug,   SECTION_SHIFT.Debug)

    -- Content height = running stack depth + bottom padding.
    content:SetHeight(stackCursorY + 20)

    ---------------------------------------------------------------
    -- Outer lifecycle.
    ---------------------------------------------------------------
    outer:SetScript("OnHide", function()
        if ColorPickerFrame
           and ColorPickerFrame.IsShown
           and ColorPickerFrame:IsShown() then
            ColorPickerFrame:Hide()
        end
    end)

    outer:SetScript("OnShow", function()
        DS_CloseOtherWindows()
        DS_MakeTopMost(this)
        reqBlock.Update()

        -- Pre-warm the dropdown system. On a fresh login / reload,
        -- WoW 1.12 lazily creates DropDownList1-3 the very first time
        -- any dropdown opens, which on a populated UI can freeze for
        -- 1-2 seconds. We open-and-close one menu here (offscreen) so
        -- by the time the user clicks any real dropdown it is already
        -- built.
        if not content._daDropWarmed then
            content._daDropWarmed = true
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

        -- Re-anchor to the left of the main frame every time we open.
        if DoiteAurasFrame and DoiteAurasFrame.GetName then
            this:ClearAllPoints()
            this:SetPoint("TOPRIGHT", DoiteAurasFrame, "TOPLEFT", -5, 0)
        end

        togglesBlock.UpdatePfUI()
        togglesBlock.UpdateItemTooltip()
        fontsBlock.RefreshAll()
        debugBlock.UpdateAll()

        if content._daGlowRefreshAll then
            content._daGlowRefreshAll()
        end
        if content._daPopRefreshAll then
            content._daPopRefreshAll()
        end
    end)

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