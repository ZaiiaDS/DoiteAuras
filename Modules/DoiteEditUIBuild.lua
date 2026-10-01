---------------------------------------------------------------
-- DoiteEditUIBuild.lua
-- Creates the entire Conditions UI tree (all ability / aura / item
-- controls, separators, sub-sections). Extracted from DoiteEdit.lua
-- (Phase 8 of the split).
--
-- Public globals (assigned at runtime by CreateConditionsUI):
--   _G["DoiteEdit_SetSeparator"]
--   _G["DoiteEdit_ShowSeparatorsForType"]
--   _G["DoiteEdit_AuraOwner_UpdateDependentChecks"]
--
-- Also writes srows via ctx.setSrows(...).
--
-- Loaded AFTER DoiteEdit.lua (needs DoiteEditCtx populated).
---------------------------------------------------------------

local ctx = _G["DoiteEditCtx"]
if not ctx then return end

-- File-scope locals: must be declared here so both the assignment inside
-- CreateConditionsUI and every inner helper see them as the same upvalue.
local srows

-- Local aliases: hide ctx plumbing from the extracted code.
local function _CF()              return ctx.getCondFrame() end
local function _CK()              return ctx.getCurrentKey() end
local function _EDB(k)            return ctx.EnsureDBEntry(k) end
local function _CD(dd)            return ctx.ClearDropdown(dd) end
local function _SR()               ctx.SafeRefresh()          end
local function _SE()               ctx.SafeEvaluate()         end
local function _Reflow()           ctx.ReflowCondAreaHeight() end

-- Global helpers already in DoiteEditHelpers.lua
local DoiteEdit_SetDropdownInteractive    = _G["DoiteEdit_SetDropdownInteractive"]
local DoiteEdit_EnableCheck               = _G["DoiteEdit_EnableCheck"]
local DoiteEdit_DisableCheck              = _G["DoiteEdit_DisableCheck"]
local StylePlainEditBox                   = _G["DoiteEdit_StylePlainEditBox"]
local _GoldifyDD                          = _G["_GoldifyDD"]
local _WhiteifyDDText                     = _G["_WhiteifyDDText"]

-- Lazy proxies for functions that CreateConditionsUI itself defines
-- into _G["DoiteEdit_SetSeparator"] / _G["DoiteEdit_ShowSeparatorsForType"].
-- Inner call sites use the plain names (SetSeparator / ShowSeparatorsForType),
-- which resolve here and are forwarded to the real function through _G.
local function SetSeparator(...)
  local f = _G["DoiteEdit_SetSeparator"]
  if f then return f(...) end
end

local function ShowSeparatorsForType(...)
  local f = _G["DoiteEdit_ShowSeparatorsForType"]
  if f then return f(...) end
end

local function AuraOwner_UpdateDependentChecks()
  local f = _G["DoiteEdit_AuraOwner_UpdateDependentChecks"]
  if f then return f() end
end

-- Additional proxies for helpers still living in DoiteEdit.lua (via ctx).
local function _TitleCase(s)
  local f = _G["DoiteEdit_AuraCond_TitleCase"]
  if f then return f(s) end
  return s or ""
end

local function _ParseFadeAlphaFromBox(box)
  local f = _G["DoiteEdit_ParseFadeAlphaFromBox"]
  if f then return f(box) end
  return 0
end

local function _NormalizeFadeBox(box, alpha)
  local f = _G["DoiteEdit_NormalizeFadeBox"]
  if f then return f(box, alpha) end
end

local function SetExclusiveAbilityMode(m)   return ctx.SetExclusiveAbilityMode(m)   end
local function SetExclusiveItemMode(m)      return ctx.SetExclusiveItemMode(m)      end
local function SetCombatFlag(t, w, e)       return ctx.SetCombatFlag(t, w, e)       end
local function SetExclusiveAuraFoundMode(m) return ctx.SetExclusiveAuraFoundMode(m) end
local function UpdateCondFrameForKey(k)     return ctx.UpdateCondFrameForKey(k)     end

-- Helpers still defined in DoiteEdit.lua (via ctx proxy or _G)
local function DoiteEdit_SetSoundFromDropdown(a, b, c)
  if ctx.SetSoundFromDropdown then return ctx.SetSoundFromDropdown(a, b, c) end
end
local function DoiteEdit_SetSoundEnabled(a, b, c)
  if ctx.SetSoundEnabled then return ctx.SetSoundEnabled(a, b, c) end
end
local function DoiteEdit_InitSoundDropdown(a, b, c, d)
  if ctx.InitSoundDropdown then return ctx.InitSoundDropdown(a, b, c, d) end
end
local function DoiteEdit_AddGroupModeOption(t, txt, v)
  if ctx.AddGroupModeOption then return ctx.AddGroupModeOption(t, txt, v) end
end
local function InitFormDropdown(dd, data, condType)
  if ctx.InitFormDropdown then return ctx.InitFormDropdown(dd, data, condType) end
end
local function InitWeaponDropdown(dd, data, condType)
  if ctx.InitWeaponDropdown then return ctx.InitWeaponDropdown(dd, data, condType) end
end
local function _DA_GetAbilityCooldownDuration(data)
  return _G["DoiteEdit_GetAbilityCooldownDuration"](data)
end
local function _DA_SetSliderTimeDisplay(box, v, data)
  return _G["DoiteEdit_SetSliderTimeDisplay"](box, v, data)
end

local function CreateConditionsUI()
  local condFrame = _CF()
  if not condFrame then
    return
  end
  if condFrame._conditionsUIBuilt then
    return
  end
  condFrame._conditionsUIBuilt = true

  -- helpers (parent to the scrollable content area)
  local function _Parent()
    return (condFrame and condFrame._condArea) or condFrame
  end

  local function MakeCheck(name, label, x, y)
    local parent = _Parent()
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetWidth(20);
    cb:SetHeight(20)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.text:SetText(label)
    return cb
  end

  local function MakeComparatorDD(name, x, y, width)
    local parent = _Parent()
    local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if UIDropDownMenu_SetWidth then
      pcall(UIDropDownMenu_SetWidth, width or 55, dd)
    end
    return dd
  end

  local function MakeSmallEdit(name, x, y, width)
    local parent = _Parent()
    local eb = CreateFrame("EditBox", name, parent)
    eb:SetWidth(width or 44)
    eb:SetHeight(18)
    eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    StylePlainEditBox(eb, "CENTER")
    return eb
  end

  local function MakeMiniFadeSlider(name, x, y)
    local parent = _Parent()
    local eb = CreateFrame("EditBox", name, parent)
    eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    eb:SetWidth(40)
    eb:SetHeight(18)
    StylePlainEditBox(eb, "CENTER")
    eb:SetNumeric(true)

    local pct = eb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pct:SetPoint("LEFT", eb, "RIGHT", 4, 0)
    pct:SetText("|cffffd000%|r")
    eb._pct = pct
    return eb
  end

  -- renders a small bold white title with a "split" separator line that does not pass under the text
  local function MakeSeparatorRow(parent, y, title, drawLine)
    drawLine = (drawLine ~= false)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    holder:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    holder:SetHeight(16)

    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetText("|cffffffff" .. (title or "") .. "|r")

    local lineY = -8
    local lineL = holder:CreateTexture(nil, "ARTWORK")
    lineL:SetHeight(1);
    lineL:SetTexture(1, 1, 1);
    lineL:SetVertexColor(1, 1, 1, 0.25)
    lineL:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, lineY)
    lineL:SetPoint("TOPRIGHT", label, "TOPLEFT", -6, lineY)

    local lineR = holder:CreateTexture(nil, "ARTWORK")
    lineR:SetHeight(1);
    lineR:SetTexture(1, 1, 1);
    lineR:SetVertexColor(1, 1, 1, 0.25)
    lineR:SetPoint("TOPLEFT", label, "TOPRIGHT", 6, lineY)
    lineR:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, lineY)

    if not drawLine then
      lineL:Hide();
      lineR:Hide()
    end

    holder._label = label
    holder._lineL = lineL
    holder._lineR = lineR
    holder:Hide() -- start hidden; visibility handled by manager
    return holder
  end

  local function SetSeparatorLineVisible(sep, visible)
    if not sep then
      return
    end
    if visible then
      if sep._lineL then
        sep._lineL:Show()
      end
      if sep._lineR then
        sep._lineR:Show()
      end
    else
      if sep._lineL then
        sep._lineL:Hide()
      end
      if sep._lineR then
        sep._lineR:Hide()
      end
    end
  end

  -- Extra gap below the SLIDING ICON block. Positive = push everything
  -- below further down. Only this value is meant to be tuned here.
  local SLIDING_EXTRA = 20
  condFrame._slidingExtra = SLIDING_EXTRA

  -- === Separator Y positions ===
  local srow1_y, srow2_y, srow3_y, srow4_y, srow5_y = -5, -45, -110, -150, -190
  local srow6_y, srow7_y = -230, -270
  -- srow8 (RESOURCE for abilities) is placed just under the EFFECT hint.
  local srow8_y,  srow9_y,  srow10_y = -347 - SLIDING_EXTRA, -385 - SLIDING_EXTRA, -425 - SLIDING_EXTRA
  local srow11_y, srow12_y, srow13_y = -465 - SLIDING_EXTRA, -505 - SLIDING_EXTRA, -545 - SLIDING_EXTRA
  local srow14_y, srow15_y           = -585 - SLIDING_EXTRA, -625 - SLIDING_EXTRA
  local srow16_y, srow17_y, srow18_y = -665 - SLIDING_EXTRA, -705 - SLIDING_EXTRA, -745 - SLIDING_EXTRA
  local srow19_y, srow20_y           = -785 - SLIDING_EXTRA, -825 - SLIDING_EXTRA

  srows = {
    srow1_y, srow2_y, srow3_y, srow4_y, srow5_y,
    srow6_y, srow7_y, srow8_y, srow9_y, srow10_y,
    srow11_y, srow12_y, srow13_y, srow14_y, srow15_y,
    srow16_y, srow17_y, srow18_y, srow19_y, srow20_y
  }
  ctx.setSrows(srows)

  -- === Per-type separator caches (ability/aura/item/custom are independent)
  condFrame._seps = condFrame._seps or { ability = {}, aura = {}, item = {}, custom = {} }

  local function _EnsureSep(typeKey, slot)
    local list = condFrame._seps[typeKey]
    if not list[slot] then
      local y = srows[slot] or srows[1]
      list[slot] = MakeSeparatorRow(_Parent(), y, "", true)
      list[slot]._visible = false
      list[slot]._lineOn = true
    end
    return list[slot]
  end

  -- Normalize any extended type keys (eg. "item_trinket", "item_weapon") to their base buckets.
  local function _NormalizeSepTypeKey(typeKey)
    if not typeKey then
      return nil
    end
    if typeKey == "ability" or typeKey == "aura" or typeKey == "item" or typeKey == "custom" then
      return typeKey
    end

    local lower = string.lower(tostring(typeKey))

    -- Map anything that *contains* these substrings back to the base key.
    -- e.g. "item_trinket_slots" -> "item"
    if string.find(lower, "ability", 1, true) then
      return "ability"
    elseif string.find(lower, "aura", 1, true) then
      return "aura"
    elseif string.find(lower, "item", 1, true) then
      return "item"
    elseif string.find(lower, "custom", 1, true) then
      return "custom"
    end

    return nil
  end

  -- typeKey = "ability" | "aura" | "item" (or extended forms like "item_trinket"); slot = 1..20
  _G["DoiteEdit_SetSeparator"] = function(typeKey, slot, title, showLine, isVisible)
    typeKey = _NormalizeSepTypeKey(typeKey)
    if not typeKey then
      return
    end
    if slot < 1 or slot > 20 then
      return
    end

    local sep = _EnsureSep(typeKey, slot)
    if sep._label then
      sep._label:SetText("|cffffffff" .. (title or "") .. "|r")
    end
    sep._lineOn = (showLine ~= false)
    SetSeparatorLineVisible(sep, sep._lineOn)
    sep._visible = (isVisible and true) or false
    if sep._visible then
      sep:Show()
    else
      sep:Hide()
    end
    return sep
  end

  -- exported: UpdateConditionsUI calls this
  _G["DoiteEdit_ShowSeparatorsForType"] = function(typeKey)
    -- Map any extended keys ("item_trinket", "item_weapon", etc.) onto base buckets.
    typeKey = _NormalizeSepTypeKey(typeKey)
    if not typeKey then
      -- Unknown type: don't touch anything
      return
    end

    -- Hide every separator first
    for _, list in pairs(condFrame._seps) do
      for _, sep in pairs(list) do
        sep:Hide()
      end
    end

    -- Then reveal only this type’s visible ones (with line state)
    local mine = condFrame._seps[typeKey] or {}
    for _, sep in pairs(mine) do
      if sep._visible then
        SetSeparatorLineVisible(sep, sep._lineOn)
        sep:Show()
      end
    end
  end

  -- row positions
  local row1_y, row2_y, row2b_y, row3_y, row4_y, row5_y = -20, -60, -85, -125, -165, -205
  local row6_y, row7_y = -245, -285
  local row8_y,  row9_y,  row10_y = -360 - SLIDING_EXTRA, -400 - SLIDING_EXTRA, -440 - SLIDING_EXTRA
  local row11_y, row12_y, row13_y = -480 - SLIDING_EXTRA, -520 - SLIDING_EXTRA, -560 - SLIDING_EXTRA
  local row14_y, row15_y          = -600 - SLIDING_EXTRA, -640 - SLIDING_EXTRA
  local row16_y, row17_y, row18_y = -655 - SLIDING_EXTRA, -695 - SLIDING_EXTRA, -735 - SLIDING_EXTRA
  local row19_y, row20_y          = -775 - SLIDING_EXTRA, -815 - SLIDING_EXTRA

  condFrame._rowY = {
    [7] = row7_y,
    [8] = row8_y,
    [10] = row10_y,
    [11] = row11_y,
  }

  --------------------------------------------------
  -- Ability rows
  --------------------------------------------------
  condFrame.cond_ability_usable = MakeCheck("DoiteCond_Ability_Usable", "Usable", 0, row1_y)
  condFrame.cond_ability_notcd = MakeCheck("DoiteCond_Ability_NotCD", "Not on cooldown", 70, row1_y)
  condFrame.cond_ability_oncd = MakeCheck("DoiteCond_Ability_OnCD", "On cooldown", 190, row1_y)
  SetSeparator("ability", 1, "USABILITY & COOLDOWN", true, true)

  condFrame.cond_ability_incombat = MakeCheck("DoiteCond_Ability_InCombat", "In combat", 0, row2_y)
  condFrame.cond_ability_outcombat = MakeCheck("DoiteCond_Ability_OutCombat", "Out of combat", 80, row2_y)

  -- Grouping dropdown (replaces In party / In raid checkboxes)
  do
    local parent = _Parent()
    condFrame.cond_ability_groupingDD = CreateFrame("Frame", "DoiteCond_Ability_GroupingDD", parent, "UIDropDownMenuTemplate")
    condFrame.cond_ability_groupingDD:SetPoint("TOPLEFT", parent, "TOPLEFT", -15, row2b_y + 5)
    if UIDropDownMenu_SetWidth then
      pcall(UIDropDownMenu_SetWidth, 100, condFrame.cond_ability_groupingDD)
    end

    _CD(condFrame.cond_ability_groupingDD)
    UIDropDownMenu_Initialize(condFrame.cond_ability_groupingDD, function(frame, level, menuList)
      DoiteEdit_AddGroupModeOption("ability", "Any", "any")
      DoiteEdit_AddGroupModeOption("ability", "Not in group", "nogroup")
      DoiteEdit_AddGroupModeOption("ability", "In party", "party")
      DoiteEdit_AddGroupModeOption("ability", "In raid", "raid")
      DoiteEdit_AddGroupModeOption("ability", "In party or raid", "partyraid")
    end)
  end

  SetSeparator("ability", 2, "COMBAT & GROUP STATE", true, true)

  condFrame.cond_ability_target_help = MakeCheck("DoiteCond_Ability_TargetHelp", "Target (help)", 0, row3_y)
  condFrame.cond_ability_target_harm = MakeCheck("DoiteCond_Ability_TargetHarm", "Target (harm)", 95, row3_y)
  condFrame.cond_ability_target_self = MakeCheck("DoiteCond_Ability_TargetSelf", "Target (self)", 200, row3_y)
  SetSeparator("ability", 3, "TARGET CONDITIONS", true, true)

  -- TARGET STATUS
  condFrame.cond_ability_target_alive = MakeCheck("DoiteCond_Ability_TargetAlive", "Alive", 0, row4_y)
  condFrame.cond_ability_target_dead = MakeCheck("DoiteCond_Ability_TargetDead", "Dead", 70, row4_y)
  SetSeparator("ability", 4, "TARGET STATUS", true, true)

  condFrame.cond_ability_glow = MakeCheck("DoiteCond_Ability_Glow", "Glow", 0, row5_y)
  condFrame.cond_ability_greyscale = MakeCheck("DoiteCond_Ability_Greyscale", "Grey", 70, row5_y)
  condFrame.cond_ability_fade = MakeCheck("DoiteCond_Ability_Fade", "Fade", 140, row5_y)
  condFrame.cond_ability_fade_slider = MakeMiniFadeSlider("DoiteCond_Ability_FadeSlider", 200, row5_y - 2)
  SetSeparator("ability", 5, "VISUAL EFFECTS", true, true)

  -- ABILITY ROW: TARGET DISTANCE & TYPE
  SetSeparator("ability", 6, "TARGET DISTANCE & TYPE", true, true)

  condFrame.cond_ability_distanceDD = CreateFrame("Frame", "DoiteCond_Ability_DistanceDD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_ability_distanceDD:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", -15, row6_y + 3)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 100, condFrame.cond_ability_distanceDD)
  end

  condFrame.cond_ability_unitTypeDD = CreateFrame("Frame", "DoiteCond_Ability_UnitTypeDD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_ability_unitTypeDD:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 120, row6_y + 3)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 100, condFrame.cond_ability_unitTypeDD)
  end

  condFrame.cond_ability_slider = MakeCheck("DoiteCond_Ability_Slider", "Soon off CD", 0, row7_y)

  -- Direction DD sits on the second row (below "Soon off CD").
  -- Template carries ~16px internal left padding, so anchor at -16 to
  -- land the visible left edge at 0.
  condFrame.cond_ability_slider_dir = CreateFrame("Frame", "DoiteCond_Ability_SliderDir", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_ability_slider_dir:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", -16, row7_y - 24 + 5)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 60, condFrame.cond_ability_slider_dir)
  end

  -- Effect dropdown (Slide / Shatter) sits on the same row as
  -- "Soon off CD". Width sized for "Shatter (assemble)".
  condFrame.cond_ability_slider_effect = CreateFrame("Frame", "DoiteCond_Ability_SliderEffect", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_ability_slider_effect:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 70, row7_y + 4)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 110, condFrame.cond_ability_slider_effect)
  end
  -- Row 7b: Slide window (seconds)
  -- Line 2: [slider] [EditBox] (sec.) on one line.
  -- Line 3: short hint text, thin separator under it.
  -- Empty value = whole cooldown (grey placeholder in the box).
  -- Hintline and bottom separator are children of the (sec.) label so
  -- they follow its show/hide automatically.
  local row7b_y = row7_y - 46

  condFrame.cond_ability_slider_time_slider = CreateFrame(
      "Slider", "DoiteCond_Ability_SliderTimeSlider", _Parent(), "OptionsSliderTemplate")
  condFrame.cond_ability_slider_time_slider:SetWidth(130)
  condFrame.cond_ability_slider_time_slider:SetHeight(16)
  condFrame.cond_ability_slider_time_slider:SetPoint(
      "TOPLEFT", _Parent(), "TOPLEFT", 0, row7b_y)
  condFrame.cond_ability_slider_time_slider:SetMinMaxValues(0, 180)
  condFrame.cond_ability_slider_time_slider:SetValueStep(1)
  condFrame.cond_ability_slider_time_slider:SetValue(0)
  do
    local n  = condFrame.cond_ability_slider_time_slider:GetName()
    local t  = _G[n .. "Text"]; if t  then t:SetText("")  end
    local lo = _G[n .. "Low"];  if lo then lo:SetText("") end
    local hi = _G[n .. "High"]; if hi then hi:SetText("") end
  end
  condFrame.cond_ability_slider_time_slider:EnableMouse(true)
  condFrame.cond_ability_slider_time_slider:SetScript("OnValueChanged", function()
    if this._isSyncing then return end
    if not _CK() then return end
    local cur = DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[_CK()]
    if not cur then return end
    local fullCD = _DA_GetAbilityCooldownDuration(cur)
    if not fullCD or fullCD <= 0 then return end
    cur.conditions = cur.conditions or {}
    cur.conditions.ability = cur.conditions.ability or {}
    local v = math.floor(this:GetValue() + 0.5)
    if v >= fullCD then
      cur.conditions.ability.sliderTime = nil
      _DA_SetSliderTimeDisplay(condFrame.cond_ability_slider_time, nil, cur)
    else
      cur.conditions.ability.sliderTime = v
      _DA_SetSliderTimeDisplay(condFrame.cond_ability_slider_time, v, cur)
    end
    _SR()
    _SE()
  end)

  condFrame.cond_ability_slider_time = CreateFrame("EditBox", "DoiteCond_Ability_SliderTime", _Parent())
  condFrame.cond_ability_slider_time:SetWidth(44)
  condFrame.cond_ability_slider_time:SetHeight(18)
  condFrame.cond_ability_slider_time:SetPoint(
      "LEFT", condFrame.cond_ability_slider_time_slider, "RIGHT", 6, 0)
  StylePlainEditBox(condFrame.cond_ability_slider_time, "CENTER")
  condFrame.cond_ability_slider_time:SetNumeric(true)

  -- (sec.) label next to the EditBox. Visibility is managed by
  -- UpdateConditionsUI (see _HideSlidingUI).
  condFrame.cond_ability_slider_time_label = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_ability_slider_time_label:SetPoint(
      "LEFT", condFrame.cond_ability_slider_time, "RIGHT", 2, 0)
  condFrame.cond_ability_slider_time_label:SetText("sec")
  if condFrame.cond_ability_slider_time_label.SetTextColor then
    condFrame.cond_ability_slider_time_label:SetTextColor(0.7, 0.7, 0.7)
  end

  condFrame.cond_ability_slider_time_hintline = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_ability_slider_time_hintline:SetPoint(
      "TOPLEFT", _Parent(), "TOPLEFT", 0, row7_y - 68)
  condFrame.cond_ability_slider_time_hintline:SetWidth(280)
  condFrame.cond_ability_slider_time_hintline:SetJustifyH("LEFT")
  if condFrame.cond_ability_slider_time_hintline.SetTextColor then
    condFrame.cond_ability_slider_time_hintline:SetTextColor(0.7, 0.7, 0.7)
  end
  condFrame.cond_ability_slider_time_hintline:SetText(
      "Empty = whole cooldown. N = slide during the last N sec")

  -- Fading checkbox: icon starts invisible and fades in while sliding.
  condFrame.cond_ability_slider_fading_cb = CreateFrame("CheckButton", "DoiteCond_Ability_SliderFading", _Parent(), "UICheckButtonTemplate")
  condFrame.cond_ability_slider_fading_cb:SetWidth(18)
  condFrame.cond_ability_slider_fading_cb:SetHeight(18)
  condFrame.cond_ability_slider_fading_cb:SetPoint("LEFT", condFrame.cond_ability_slider_time_label, "RIGHT", 14, 0)
  condFrame.cond_ability_slider_fading_cb.text = condFrame.cond_ability_slider_fading_cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_ability_slider_fading_cb.text:SetPoint("LEFT", condFrame.cond_ability_slider_fading_cb, "RIGHT", 4, 0)
  condFrame.cond_ability_slider_fading_cb.text:SetText("Fading")
  condFrame.cond_ability_slider_fading_cb:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.sliderFade = this:GetChecked() and true or nil
    _SR()
    _SE()
  end)
  condFrame.cond_ability_slider_fading_cb:SetScript("OnEnter", function()
    if GameTooltip then
      GameTooltip:SetOwner(this, "ANCHOR_TOP")
      GameTooltip:AddLine("Fading")
      GameTooltip:AddLine("While sliding, the icon fades in from invisible to fully visible.", 1, 1, 1, 1)
      GameTooltip:Show()
    end
  end)
  condFrame.cond_ability_slider_fading_cb:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)

  -- Placeholder handling: on focus gain we clear the grey placeholder so
  -- the user types into a blank field. On text change we mark the field as
  -- user-typed (not placeholder).
  condFrame.cond_ability_slider_time:SetScript("OnEditFocusGained", function()
    if this._daIsPlaceholder then
      this._daSettingPlaceholder = true
      this:SetText("")
      this._daSettingPlaceholder = false
      this._daIsPlaceholder = nil
    end
    this:SetTextColor(1, 0.82, 0)
  end)
  condFrame.cond_ability_slider_time:SetScript("OnTextChanged", function()
    if this._daSettingPlaceholder then return end
    -- Do not touch _daIsPlaceholder or SetTextColor here. On this
    -- client the callback can fire after _daSettingPlaceholder has
    -- already been cleared, which would clobber the placeholder
    -- state set by the programmatic path. Colour and flag are managed
    -- explicitly by _DA_SetSliderTimeDisplay and the focus handlers.

    -- Sync the slider position to the new numeric value.
    if not _CK() then return end
    local cur = DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[_CK()]
    if not cur then return end
    local fullCD = _DA_GetAbilityCooldownDuration(cur)
    if not fullCD or fullCD <= 0 then return end
    local v = tonumber(this:GetText())
    local slider = condFrame.cond_ability_slider_time_slider
    if not slider then return end
    if v and v > 0 then
      if v > fullCD then v = fullCD end
      slider._isSyncing = true
      slider:SetValue(v)
      slider._isSyncing = false
    end
  end)
  condFrame.cond_ability_remaining_cb = MakeCheck("DoiteCond_Ability_RemainingCB", "Remaining", 0, row7_y)
  condFrame.cond_ability_remaining_comp = MakeComparatorDD("DoiteCond_Ability_RemComp", 65, row7_y + 3, 50)
  condFrame.cond_ability_remaining_val = MakeSmallEdit("DoiteCond_Ability_RemVal", 160, row7_y - 2, 40)
  condFrame.cond_ability_remaining_val_enter = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_ability_remaining_val_enter:SetPoint("LEFT", condFrame.cond_ability_remaining_val, "RIGHT", 4, 0)
  condFrame.cond_ability_remaining_val_enter:SetText("(sec.)")
  condFrame.cond_ability_remaining_val_enter:Hide()
  -- Glow / Grey moved to row 2, to the right of the direction dropdown.
  condFrame.cond_ability_slider_glow = MakeCheck("DoiteCond_Ability_SliderGlow", "Glow", 90, row7_y - 24)
  condFrame.cond_ability_slider_grey = MakeCheck("DoiteCond_Ability_SliderGrey", "Grey", 160, row7_y - 24)

  SetSeparator("ability", 7, "EFFECT", true, true)

  condFrame.cond_ability_power = MakeCheck("DoiteCond_Ability_PowerCB", "Power", 0, row8_y)
  condFrame.cond_ability_power_comp = MakeComparatorDD("DoiteCond_Ability_PowerComp", 65, row8_y + 3, 50)
  condFrame.cond_ability_power_val = MakeSmallEdit("DoiteCond_Ability_PowerVal", 160, row8_y - 2, 40)
  condFrame.cond_ability_power_val_enter = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_ability_power_val_enter:SetPoint("LEFT", condFrame.cond_ability_power_val, "RIGHT", 4, 0)
  condFrame.cond_ability_power_val_enter:SetText("(%)")
  condFrame.cond_ability_power_val_enter:Hide()
  SetSeparator("ability", 8, "RESOURCE", true, true)

  condFrame.cond_ability_hp_my = MakeCheck("DoiteCond_Ability_HP_My", "My HP", 0, row9_y)
  condFrame.cond_ability_hp_tgt = MakeCheck("DoiteCond_Ability_HP_Tgt", "Target HP", 65, row9_y)
  condFrame.cond_ability_hp_comp = MakeComparatorDD("DoiteCond_Ability_HP_Comp", 130, row9_y + 3, 50)
  condFrame.cond_ability_hp_val = MakeSmallEdit("DoiteCond_Ability_HP_Val", 225, row9_y - 2, 40)
  condFrame.cond_ability_hp_val_enter = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_ability_hp_val_enter:SetPoint("LEFT", condFrame.cond_ability_hp_val, "RIGHT", 4, 0)
  condFrame.cond_ability_hp_val_enter:SetText("(%)")
  condFrame.cond_ability_hp_comp:Hide()
  condFrame.cond_ability_hp_val:Hide()
  condFrame.cond_ability_hp_val_enter:Hide()
  SetSeparator("ability", 9, "HEALTH CONDITION", true, true)

  condFrame.cond_ability_text_time = MakeCheck("DoiteCond_Ability_TextTime", "Icon text: Time remaining", 0, row10_y)
  SetSeparator("ability", 10, "ICON TEXT", true, true)

  -- Combo points dropdown (class-specific: druid / rogue)
  condFrame.cond_ability_cp_cb = MakeCheck("DoiteCond_Ability_CP_CB", "Combo points", 0, row11_y)
  condFrame.cond_ability_cp_comp = MakeComparatorDD("DoiteCond_Ability_CP_Comp", 85, row11_y + 3, 50)
  condFrame.cond_ability_cp_val = MakeSmallEdit("DoiteCond_Ability_CP_Val", 180, row11_y - 2, 40)
  condFrame.cond_ability_cp_val_enter = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_ability_cp_val_enter:SetPoint("LEFT", condFrame.cond_ability_cp_val, "RIGHT", 4, 0)
  condFrame.cond_ability_cp_val_enter:SetText("(#)")
  condFrame.cond_ability_cp_val_enter:Hide()
  SetSeparator("ability", 11, "CLASS-SPECIFIC", true, true)

  -- Ability: class-specific weapon / fighting-style dropdown (Shaman / Warrior / Paladin)
  condFrame.cond_ability_weaponDD = CreateFrame("Frame", "DoiteCond_Ability_WeaponDD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_ability_weaponDD:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", -15, row11_y + 3)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 90, condFrame.cond_ability_weaponDD)
  end
  condFrame.cond_ability_weaponDD:Hide()
  _CD(condFrame.cond_ability_weaponDD)

  -- Ability: class-specific note for classes without combo points
  condFrame.cond_ability_class_note = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_ability_class_note:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 0, row11_y)
  condFrame.cond_ability_class_note:SetTextColor(1, 0.82, 0)
  condFrame.cond_ability_class_note:SetText("No class-specific option added for your class.")
  condFrame.cond_ability_class_note:Hide()

  -- Ability: Sound effects
  condFrame.cond_ability_sound_oncd_cb = MakeCheck("DoiteCond_Ability_Sound_OnCD_CB", "On cooldown", 0, row12_y)
  condFrame.cond_ability_sound_oncd_dd = CreateFrame("Frame", "DoiteCond_Ability_Sound_OnCD_DD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_ability_sound_oncd_dd:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 100, row12_y + 3)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 140, condFrame.cond_ability_sound_oncd_dd)
  end

  condFrame.cond_ability_sound_offcd_cb = MakeCheck("DoiteCond_Ability_Sound_OffCD_CB", "Off cooldown", 0, row12_y - 25)
  condFrame.cond_ability_sound_offcd_dd = CreateFrame("Frame", "DoiteCond_Ability_Sound_OffCD_DD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_ability_sound_offcd_dd:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 100, row12_y - 22)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 140, condFrame.cond_ability_sound_offcd_dd)
  end

  condFrame.cond_ability_sound_onproc_cb = MakeCheck("DoiteCond_Ability_Sound_OnProc_CB", "On 'proc'", 0, row12_y - 50)
  condFrame.cond_ability_sound_onproc_dd = CreateFrame("Frame", "DoiteCond_Ability_Sound_OnProc_DD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_ability_sound_onproc_dd:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 100, row12_y - 47)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 140, condFrame.cond_ability_sound_onproc_dd)
  end
  SetSeparator("ability", 12, "SOUND EFFECTS", true, true)

  -- Ability: dynamic Aura Conditions section
  local abilityAuraBaseY = row14_y - 15
  local sepAbilityAura = SetSeparator("ability", 14, "EXTRA: VISIBILITY (SHOW/HIDE) CONDITIONS", true, true)
  if sepAbilityAura then
    local sepAuraY = ((srows and srows[14]) or 0) - 15
    sepAbilityAura:ClearAllPoints()
    sepAbilityAura:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 0, sepAuraY)
    sepAbilityAura:SetPoint("TOPRIGHT", _Parent(), "TOPRIGHT", 0, sepAuraY)
  end
  condFrame.abilityAuraAnchor = CreateFrame("Frame", nil, _Parent())
  condFrame.abilityAuraAnchor:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 0, abilityAuraBaseY)
  condFrame.abilityAuraAnchor:SetPoint("TOPRIGHT", _Parent(), "TOPRIGHT", 0, abilityAuraBaseY)
  condFrame.abilityAuraAnchor:SetHeight(20)

  -- Ability: dynamic Visual Effects Conditions section
  local abilityVfxBaseY = row15_y - 15
  local sepAbilityVfx = SetSeparator("ability", 15, "EXTRA: VISUAL EFFECT (GLOW/GREY) CONDITIONS", true, true)
  if sepAbilityVfx then
    local sepVfxY = ((srows and srows[15]) or 0) - 15
    sepAbilityVfx:ClearAllPoints()
    sepAbilityVfx:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 0, sepVfxY)
    sepAbilityVfx:SetPoint("TOPRIGHT", _Parent(), "TOPRIGHT", 0, sepVfxY)
  end
  condFrame.abilityVfxAnchor = CreateFrame("Frame", nil, _Parent())
  condFrame.abilityVfxAnchor:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 0, abilityVfxBaseY)
  condFrame.abilityVfxAnchor:SetPoint("TOPRIGHT", _Parent(), "TOPRIGHT", 0, abilityVfxBaseY)
  condFrame.abilityVfxAnchor:SetHeight(20)

  --------------------------------------------------
  -- Buff/Debuff rows
  --------------------------------------------------
  condFrame.cond_aura_found = MakeCheck("DoiteCond_Aura_Found", "Aura found", 0, row1_y)
  condFrame.cond_aura_missing = MakeCheck("DoiteCond_Aura_Missing", "Aura missing", 85, row1_y)
  condFrame.cond_aura_tip = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_aura_tip:SetPoint("LEFT", condFrame.cond_aura_missing.text, "RIGHT", 2, 0)
  condFrame.cond_aura_tip:SetText("(to show icon, aura must be applied once)")
  condFrame.cond_aura_tip:SetWidth(120)
  condFrame.cond_aura_tip:Hide()
  SetSeparator("aura", 1, "AURA PRESENCE", true, true)

  -- Custom function editor (Custom type)
  -- The edit box lives directly in _condArea; the outer conditions scrollbar drives it.
  -- No nested scroll frame – the EditBox just grows tall and the parent scrolls.
  SetSeparator("custom", 1, "CUSTOM FUNCTION", true, true)

  condFrame.cond_custom_function_edit = CreateFrame("EditBox", nil, _Parent())
  condFrame.cond_custom_function_edit:SetMultiLine(true)
  condFrame.cond_custom_function_edit:SetAutoFocus(false)
  condFrame.cond_custom_function_edit:SetFontObject("GameFontHighlightSmall")
  condFrame.cond_custom_function_edit:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 2, -5)
  condFrame.cond_custom_function_edit:SetPoint("TOPRIGHT", _Parent(), "TOPRIGHT", -2, -5)
  condFrame.cond_custom_function_edit:SetWidth((_Parent():GetWidth() or 260) - 4)
  condFrame.cond_custom_function_edit:SetHeight(500)
  condFrame.cond_custom_function_edit:EnableMouse(true)
  if condFrame.cond_custom_function_edit.SetTextInsets then
    condFrame.cond_custom_function_edit:SetTextInsets(4, 4, 4, 4)
  end
  -- Auto-grow height to fit content so the outer scroll area sizes correctly.
  condFrame.cond_custom_function_edit:SetScript("OnTextChanged", function()
    local eb = condFrame.cond_custom_function_edit
    if not eb then return end
    -- Count lines via newlines in the text
    local txt = eb:GetText() or ""
    local lines = 1
    for _ in string.gfind(txt, "\n") do
      lines = lines + 1
    end
    local lineH = 15  -- approximate line height for GameFontHighlightSmall
    local newH = math.max((lines + 3) * lineH, 180)
    eb:SetHeight(newH)
    _Reflow()
  end)
  -- Forward mouse wheel from the edit box to the outer conditions scroll frame.
  condFrame.cond_custom_function_edit:EnableMouseWheel(true)
  condFrame.cond_custom_function_edit:SetScript("OnMouseWheel", function()
    local sf = condFrame and condFrame._scrollFrame
    if not sf then return end
    local cur = sf:GetVerticalScroll() or 0
    local step = 40
    if arg1 and arg1 > 0 then
      sf:SetVerticalScroll(math.max(cur - step, 0))
    elseif arg1 and arg1 < 0 then
      local sbName = sf:GetName() and (sf:GetName() .. "ScrollBar")
      local sb = sbName and getglobal(sbName)
      local maxScroll = 0
      if sb and sb.GetMinMaxValues then
        local _, hi = sb:GetMinMaxValues()
        maxScroll = hi or 0
      end
      sf:SetVerticalScroll(math.min(cur + step, maxScroll))
    end
  end)
  condFrame.cond_custom_function_edit:Hide()

  -- Save button + status are created after gridBtn exists (see below gridBtn creation).

  condFrame.cond_aura_incombat = MakeCheck("DoiteCond_Aura_InCombat", "In combat", 0, row2_y)
  condFrame.cond_aura_outcombat = MakeCheck("DoiteCond_Aura_OutCombat", "Out of combat", 80, row2_y)

  -- Grouping dropdown (replaces In party / In raid checkboxes)
  do
    local parent = _Parent()
    condFrame.cond_aura_groupingDD = CreateFrame("Frame", "DoiteCond_Aura_GroupingDD", parent, "UIDropDownMenuTemplate")
    condFrame.cond_aura_groupingDD:SetPoint("TOPLEFT", parent, "TOPLEFT", -15, row2b_y + 5)
    if UIDropDownMenu_SetWidth then
      pcall(UIDropDownMenu_SetWidth, 100, condFrame.cond_aura_groupingDD)
    end

    _CD(condFrame.cond_aura_groupingDD)
    UIDropDownMenu_Initialize(condFrame.cond_aura_groupingDD, function(frame, level, menuList)
      DoiteEdit_AddGroupModeOption("aura", "Any", "any")
      DoiteEdit_AddGroupModeOption("aura", "Not in group", "nogroup")
      DoiteEdit_AddGroupModeOption("aura", "In party", "party")
      DoiteEdit_AddGroupModeOption("aura", "In raid", "raid")
      DoiteEdit_AddGroupModeOption("aura", "In party or raid", "partyraid")
    end)
  end

  SetSeparator("aura", 2, "COMBAT & GROUP STATE", true, true)

  condFrame.cond_aura_target_help = MakeCheck("DoiteCond_Aura_TargetHelp", "Target (help)", 0, row3_y)
  condFrame.cond_aura_target_harm = MakeCheck("DoiteCond_Aura_TargetHarm", "Target (harm)", 94, row3_y)
  condFrame.cond_aura_onself = MakeCheck("DoiteCond_Aura_OnSelf", "On player (self)", 192, row3_y)
  SetSeparator("aura", 3, "TARGET CONDITIONS", true, true)

  -- TARGET STATUS
  condFrame.cond_aura_target_alive = MakeCheck("DoiteCond_Aura_TargetAlive", "Alive", 0, row4_y)
  condFrame.cond_aura_target_dead = MakeCheck("DoiteCond_Aura_TargetDead", "Dead", 70, row4_y)
  SetSeparator("aura", 4, "TARGET STATUS", true, true)

  condFrame.cond_aura_glow = MakeCheck("DoiteCond_Aura_Glow", "Glow", 0, row5_y)
  condFrame.cond_aura_greyscale = MakeCheck("DoiteCond_Aura_Greyscale", "Grey", 70, row5_y)
  condFrame.cond_aura_fade = MakeCheck("DoiteCond_Aura_Fade", "Fade", 140, row5_y)
  condFrame.cond_aura_fade_slider = MakeMiniFadeSlider("DoiteCond_Aura_FadeSlider", 200, row5_y - 2)
  SetSeparator("aura", 5, "VISUAL EFFECTS", true, true)

  -- AURA ROW: TARGET DISTANCE & TYPE
  SetSeparator("aura", 6, "TARGET DISTANCE & TYPE", true, true)

  condFrame.cond_aura_distanceDD = CreateFrame("Frame", "DoiteCond_Aura_DistanceDD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_aura_distanceDD:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", -15, row6_y + 3)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 100, condFrame.cond_aura_distanceDD)
  end

  condFrame.cond_aura_unitTypeDD = CreateFrame("Frame", "DoiteCond_Aura_UnitTypeDD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_aura_unitTypeDD:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 120, row6_y + 3)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 100, condFrame.cond_aura_unitTypeDD)
  end

  condFrame.cond_aura_power = MakeCheck("DoiteCond_Aura_PowerCB", "Power", 0, row7_y)
  condFrame.cond_aura_power_comp = MakeComparatorDD("DoiteCond_Aura_PowerComp", 65, row7_y + 3, 50)
  condFrame.cond_aura_power_val = MakeSmallEdit("DoiteCond_Aura_PowerVal", 160, row7_y - 2, 40)
  condFrame.cond_aura_power_val_enter = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_aura_power_val_enter:SetPoint("LEFT", condFrame.cond_aura_power_val, "RIGHT", 4, 0)
  condFrame.cond_aura_power_val_enter:SetText("(%)")
  condFrame.cond_aura_power_comp:Hide()
  condFrame.cond_aura_power_val:Hide()
  condFrame.cond_aura_power_val_enter:Hide()
  SetSeparator("aura", 7, "RESOURCE", true, true)

  condFrame.cond_aura_hp_my = MakeCheck("DoiteCond_Aura_HP_My", "My HP", 0, row8_y)
  condFrame.cond_aura_hp_tgt = MakeCheck("DoiteCond_Aura_HP_Tgt", "Target HP", 65, row8_y)
  condFrame.cond_aura_hp_comp = MakeComparatorDD("DoiteCond_Aura_HP_Comp", 130, row8_y + 3, 50)
  condFrame.cond_aura_hp_val = MakeSmallEdit("DoiteCond_Aura_HP_Val", 225, row8_y - 2, 40)
  condFrame.cond_aura_hp_val_enter = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_aura_hp_val_enter:SetPoint("LEFT", condFrame.cond_aura_hp_val, "RIGHT", 4, 0)
  condFrame.cond_aura_hp_val_enter:SetText("(%)")
  condFrame.cond_aura_hp_comp:Hide()
  condFrame.cond_aura_hp_val:Hide()
  condFrame.cond_aura_hp_val_enter:Hide()
  SetSeparator("aura", 8, "HEALTH CONDITION", true, true)

  -- Aura owner
  condFrame.cond_aura_mine = MakeCheck("DoiteCond_Aura_MyAura", "My Aura", 0, row9_y)
  condFrame.cond_aura_others = MakeCheck("DoiteCond_Aura_OthersAura", "Others Aura", 75, row9_y)
  condFrame.cond_aura_owner_tip = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_aura_owner_tip:SetPoint("LEFT", condFrame.cond_aura_others, "RIGHT", 70, -3)
  condFrame._aura_owner_tip_default = condFrame._aura_owner_tip_default
      or "'Remaining' can only be used for a 'My Aura' on 'Target (Help/Harm)'"
  condFrame.cond_aura_owner_tip:SetText(condFrame._aura_owner_tip_default)
  condFrame.cond_aura_owner_tip:SetWidth(120)
  condFrame.cond_aura_owner_tip:SetTextColor(1, 0.82, 0)
  condFrame.cond_aura_owner_tip:Hide()

  SetSeparator("aura", 9, "AURA OWNER", true, true)

  -- Time remaining & stacks
  condFrame.cond_aura_remaining_cb = MakeCheck("DoiteCond_Aura_RemCB", "Remaining", 0, row10_y)
  condFrame.cond_aura_remaining_comp = MakeComparatorDD("DoiteCond_Aura_RemComp", 65, row10_y + 3, 50)
  condFrame.cond_aura_remaining_val = MakeSmallEdit("DoiteCond_Aura_RemVal", 160, row10_y - 2, 40)
  condFrame.cond_aura_remaining_val_enter = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_aura_remaining_val_enter:SetPoint("LEFT", condFrame.cond_aura_remaining_val, "RIGHT", 4, 0)
  condFrame.cond_aura_remaining_val_enter:SetText("(sec.)")
  condFrame.cond_aura_remaining_val_enter:Hide()

  condFrame.cond_aura_stacks_cb = MakeCheck("DoiteCond_Aura_StacksCB", "Stacks", 0, srow11_y)
  condFrame.cond_aura_stacks_comp = MakeComparatorDD("DoiteCond_Aura_StacksComp", 65, srow11_y + 3, 50)
  condFrame.cond_aura_stacks_val = MakeSmallEdit("DoiteCond_Aura_StacksVal", 160, srow11_y - 2, 40)
  condFrame.cond_aura_stacks_val_enter = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_aura_stacks_val_enter:SetPoint("LEFT", condFrame.cond_aura_stacks_val, "RIGHT", 4, 0)
  condFrame.cond_aura_stacks_val_enter:SetText("(#)")
  condFrame.cond_aura_stacks_val_enter:Hide()

  condFrame.cond_aura_text_time = MakeCheck("DoiteCond_Aura_TextTime", "Icon text: Time remaining", 0, row11_y - 11)
  condFrame.cond_aura_text_stack = MakeCheck("DoiteCond_Aura_TextStack", "Icon text: Stacks", 0, row12_y+3)
  condFrame.cond_aura_text_time_override = CreateFrame("EditBox", "DoiteCond_Aura_TextTimeOverride", _Parent())
  condFrame.cond_aura_text_time_override:SetWidth(100)
  condFrame.cond_aura_text_time_override:SetHeight(18)
  condFrame.cond_aura_text_time_override:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 165, row11_y - 11)
  StylePlainEditBox(condFrame.cond_aura_text_time_override, "LEFT")
  condFrame.cond_aura_text_time_override:Hide()

  condFrame.cond_aura_text_stack_override = CreateFrame("EditBox", "DoiteCond_Aura_TextStackOverride", _Parent())
  condFrame.cond_aura_text_stack_override:SetWidth(100)
  condFrame.cond_aura_text_stack_override:SetHeight(18)
  condFrame.cond_aura_text_stack_override:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 165, row12_y+3)
  StylePlainEditBox(condFrame.cond_aura_text_stack_override, "LEFT")
  condFrame.cond_aura_text_stack_override:Hide()

  condFrame.cond_aura_text_override_note = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_aura_text_override_note:SetPoint("TOPLEFT", condFrame.cond_aura_text_stack_override, "BOTTOMLEFT", -70, -2)
  condFrame.cond_aura_text_override_note:SetTextColor(1, 0.82, 0)
  condFrame.cond_aura_text_override_note:SetText("Input override aura Name or SpellID (on player based). Empty, equals default.")
  condFrame.cond_aura_text_override_note:SetWidth(220)
  condFrame.cond_aura_text_override_note:SetJustifyH("LEFT")
  condFrame.cond_aura_text_override_note:Hide()
  SetSeparator("aura", 10, "TIME REMAINING & STACKS", true, true)

  -- Class-specific (combo points)

  local auraClassRowY = row13_y -11

  condFrame.cond_aura_cp_cb = MakeCheck("DoiteCond_Aura_CP_CB", "Combo points", 0, auraClassRowY)
  condFrame.cond_aura_cp_comp = MakeComparatorDD("DoiteCond_Aura_CP_Comp", 85, auraClassRowY + 3, 50)
  condFrame.cond_aura_cp_val = MakeSmallEdit("DoiteCond_Aura_CP_Val", 180, auraClassRowY - 2, 40)
  condFrame.cond_aura_cp_val_enter = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_aura_cp_val_enter:SetPoint("LEFT", condFrame.cond_aura_cp_val, "RIGHT", 4, 0)
  condFrame.cond_aura_cp_val_enter:SetText("(#)")
  condFrame.cond_aura_cp_val_enter:Hide()

  local sepAuraClass = SetSeparator("aura", 13, "CLASS-SPECIFIC", true, true)
  if sepAuraClass and srows then
    local newY = (srows[13] or 0) - 10  -- original slot-10 Y minus 10
    sepAuraClass:ClearAllPoints()
    sepAuraClass:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 0, newY)
    sepAuraClass:SetPoint("TOPRIGHT", _Parent(), "TOPRIGHT", 0, newY)
  end

  -- Aura: class-specific weapon / fighting-style dropdown (Shaman / Warrior / Paladin)
  condFrame.cond_aura_weaponDD = CreateFrame("Frame", "DoiteCond_Aura_WeaponDD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_aura_weaponDD:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", -15, auraClassRowY + 3)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 90, condFrame.cond_aura_weaponDD)
  end
  condFrame.cond_aura_weaponDD:Hide()
  _CD(condFrame.cond_aura_weaponDD)

  -- Aura: class-specific note for classes without combo points
  condFrame.cond_aura_class_note = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_aura_class_note:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 0, auraClassRowY)
  condFrame.cond_aura_class_note:SetTextColor(1, 0.82, 0)
  condFrame.cond_aura_class_note:SetText("No class-specific option added for your class.")
  condFrame.cond_aura_class_note:Hide()

  condFrame.cond_aura_trackpet = MakeCheck("DoiteCond_Aura_TrackPet", "Track this Aura on pet", 0, auraClassRowY)
  condFrame.cond_aura_trackpet:Hide()

  -- Aura: Sound effects
  condFrame.cond_aura_sound_ongain_cb = MakeCheck("DoiteCond_Aura_Sound_OnGain_CB", "On gain", 0, row14_y - 10)
  condFrame.cond_aura_sound_ongain_dd = CreateFrame("Frame", "DoiteCond_Aura_Sound_OnGain_DD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_aura_sound_ongain_dd:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 100, row14_y - 7)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 140, condFrame.cond_aura_sound_ongain_dd)
  end

  condFrame.cond_aura_sound_onfade_cb = MakeCheck("DoiteCond_Aura_Sound_OnFade_CB", "On fade", 0, row14_y - 35)
  condFrame.cond_aura_sound_onfade_dd = CreateFrame("Frame", "DoiteCond_Aura_Sound_OnFade_DD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_aura_sound_onfade_dd:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 100, row14_y - 32)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 140, condFrame.cond_aura_sound_onfade_dd)
  end

  local sepAuraSound = SetSeparator("aura", 14, "SOUND EFFECTS", true, true)
  if sepAuraSound and srows then
    local newY = (srows[14] or 0) - 10
    sepAuraSound:ClearAllPoints()
    sepAuraSound:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 0, newY)
    sepAuraSound:SetPoint("TOPRIGHT", _Parent(), "TOPRIGHT", 0, newY)
  end

  local sepAuraBuff = SetSeparator("aura", 16, "EXTRA: VISIBILITY (SHOW/HIDE) CONDITIONS", true, true)
  if sepAuraBuff and srows then
    local newY = (srows[16] or 0)
    sepAuraBuff:ClearAllPoints()
    sepAuraBuff:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 0, newY)
    sepAuraBuff:SetPoint("TOPRIGHT", _Parent(), "TOPRIGHT", 0, newY)
  end

  -- Aura (Buff/Debuff): dynamic Aura Conditions section
  local auraAuraBaseY = row17_y + 15
  condFrame.auraAuraAnchor = CreateFrame("Frame", nil, _Parent())
  condFrame.auraAuraAnchor:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 0, auraAuraBaseY)
  condFrame.auraAuraAnchor:SetPoint("TOPRIGHT", _Parent(), "TOPRIGHT", 0, auraAuraBaseY)
  condFrame.auraAuraAnchor:SetHeight(20)

  -- Aura: dynamic Visual Effects Conditions section
  local auraVfxBaseY = row17_y
  SetSeparator("aura", 17, "EXTRA: VISUAL EFFECT (GLOW/GREY) CONDITIONS", true, true)
  condFrame.auraVfxAnchor = CreateFrame("Frame", nil, _Parent())
  condFrame.auraVfxAnchor:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 0, auraVfxBaseY)
  condFrame.auraVfxAnchor:SetPoint("TOPRIGHT", _Parent(), "TOPRIGHT", 0, auraVfxBaseY)
  condFrame.auraVfxAnchor:SetHeight(20)

  --------------------------------------------------
  -- Item rows
  --------------------------------------------------
  -- WHEREABOUTS / INVENTORY SLOT (special items)
  condFrame.cond_item_where_equipped = MakeCheck("DoiteCond_Item_WhereEquipped", "Equipped", 0, row1_y)
  condFrame.cond_item_where_bag = MakeCheck("DoiteCond_Item_WhereBag", "In backpack", 90, row1_y)
  condFrame.cond_item_where_missing = MakeCheck("DoiteCond_Item_WhereMissing", "Missing", 190, row1_y)

  -- Special inventory-slot radio groups for synthetic items:
  condFrame.cond_item_inv_trinket1 = MakeCheck("DoiteCond_Item_Inv_Trinket1", "Trinket 1", 0, row1_y)
  condFrame.cond_item_inv_trinket2 = MakeCheck("DoiteCond_Item_Inv_Trinket2", "Trinket 2", 73, row1_y)
  condFrame.cond_item_inv_trinket_first = MakeCheck("DoiteCond_Item_Inv_TrinketFirst", "First ready", 148, row1_y)
  condFrame.cond_item_inv_trinket_both = MakeCheck("DoiteCond_Item_Inv_TrinketBoth", "Both", 230, row1_y)

  condFrame.cond_item_inv_wep_mainhand = MakeCheck("DoiteCond_Item_Inv_WepMain", "Main-hand", 0, row1_y)
  condFrame.cond_item_inv_wep_offhand = MakeCheck("DoiteCond_Item_Inv_WepOff", "Off-hand", 87, row1_y)
  condFrame.cond_item_inv_wep_ranged = MakeCheck("DoiteCond_Item_Inv_WepRanged", "Ranged", 165, row1_y)
  condFrame.cond_item_inv_wep_ammo = MakeCheck("DoiteCond_Item_Inv_WepAmmo", "Ammo", 235, row1_y)

  -- Default title; changed dynamically in UpdateConditionsUI for special items
  SetSeparator("item", 1, "WHEREABOUTS", true, true)

  -- COMBAT STATE
  condFrame.cond_item_incombat = MakeCheck("DoiteCond_Item_InCombat", "In combat", 0, row2_y)
  condFrame.cond_item_outcombat = MakeCheck("DoiteCond_Item_OutCombat", "Out of combat", 80, row2_y)

  -- Grouping dropdown (replaces In party / In raid checkboxes)
  do
    local parent = _Parent()
    condFrame.cond_item_groupingDD = CreateFrame("Frame", "DoiteCond_Item_GroupingDD", parent, "UIDropDownMenuTemplate")
    condFrame.cond_item_groupingDD:SetPoint("TOPLEFT", parent, "TOPLEFT", -15, row2b_y + 5)
    if UIDropDownMenu_SetWidth then
      pcall(UIDropDownMenu_SetWidth, 100, condFrame.cond_item_groupingDD)
    end

    _CD(condFrame.cond_item_groupingDD)
    UIDropDownMenu_Initialize(condFrame.cond_item_groupingDD, function(frame, level, menuList)
      DoiteEdit_AddGroupModeOption("item", "Any", "any")
      DoiteEdit_AddGroupModeOption("item", "Not in group", "nogroup")
      DoiteEdit_AddGroupModeOption("item", "In party", "party")
      DoiteEdit_AddGroupModeOption("item", "In raid", "raid")
      DoiteEdit_AddGroupModeOption("item", "In party or raid", "partyraid")
    end)
  end

  SetSeparator("item", 2, "COMBAT & GROUP STATE", true, true)
   
  -- USABILITY & COOLDOWN (no "Usable")
  condFrame.cond_item_notcd = MakeCheck("DoiteCond_Item_NotCD", "No cooldown", 0, row3_y)
  condFrame.cond_item_oncd = MakeCheck("DoiteCond_Item_OnCD", "On cooldown", 100, row3_y)
  -- Clickable option
  condFrame.cond_item_clickable = MakeCheck("DoiteCond_Item_Clickable", "Use item", 200, row3_y)
  
  SetSeparator("item", 3, "USABILITY & COOLDOWN", true, true)
  
  -- ENCHANTED STATE (Only enabled for "---EQUIPPED WEAPON SLOTS---" when mode == "notcd" or mode == "both")
  do
    local parent = _Parent()
    condFrame.cond_item_enchant = CreateFrame("Frame", "DoiteCond_Item_Enchant", parent, "UIDropDownMenuTemplate")
    condFrame.cond_item_enchant:SetPoint("TOPLEFT", parent, "TOPLEFT", -15, row4_y + 3)
    if UIDropDownMenu_SetWidth then
      pcall(UIDropDownMenu_SetWidth, 120, condFrame.cond_item_enchant)
    end
    condFrame.cond_item_enchant:Hide()
  end
  condFrame.cond_item_text_enchant = MakeCheck("DoiteCond_Item_TextEnchant", "Icon text: Enchant uptime remaining", 150, row4_y)
  if condFrame.cond_item_text_enchant and condFrame.cond_item_text_enchant.text and condFrame.cond_item_text_enchant.text.SetWidth then
    condFrame.cond_item_text_enchant.text:SetWidth(90)
  end
  condFrame.cond_item_text_enchant:Hide()
  SetSeparator("item", 4, "TEMPORARY WEAPON ENCHANT", true, true)


  -- TARGET CONDITIONS
  condFrame.cond_item_target_help = MakeCheck("DoiteCond_Item_TargetHelp", "Target (help)", 0, row5_y)
  condFrame.cond_item_target_harm = MakeCheck("DoiteCond_Item_TargetHarm", "Target (harm)", 95, row5_y)
  condFrame.cond_item_target_self = MakeCheck("DoiteCond_Item_TargetSelf", "Target (self)", 200, row5_y)
  SetSeparator("item", 5, "TARGET CONDITIONS", true, true)

  -- TARGET STATUS (Item) – use row5_y so it sits near Visual Effects row for items
  condFrame.cond_item_target_alive = MakeCheck("DoiteCond_Item_TargetAlive", "Alive", 0, row6_y)
  condFrame.cond_item_target_dead = MakeCheck("DoiteCond_Item_TargetDead", "Dead", 70, row6_y)
  SetSeparator("item", 6, "TARGET STATUS", true, true)

  -- VISUAL EFFECTS
  condFrame.cond_item_glow = MakeCheck("DoiteCond_Item_Glow", "Glow", 0, row7_y)
  condFrame.cond_item_greyscale = MakeCheck("DoiteCond_Item_Greyscale", "Grey", 70, row7_y)
  condFrame.cond_item_fade = MakeCheck("DoiteCond_Item_Fade", "Fade", 140, row7_y)
  condFrame.cond_item_fade_slider = MakeMiniFadeSlider("DoiteCond_Item_FadeSlider", 200, row7_y - 2)
  SetSeparator("item", 7, "VISUAL EFFECTS", true, true)

  -- ITEM ROW: TARGET DISTANCE & TYPE
  SetSeparator("item", 8, "TARGET DISTANCE & TYPE", true, true)

  condFrame.cond_item_distanceDD = CreateFrame("Frame", "DoiteCond_Item_DistanceDD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_item_distanceDD:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", -15, row8_y + 3)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 100, condFrame.cond_item_distanceDD)
  end

  condFrame.cond_item_unitTypeDD = CreateFrame("Frame", "DoiteCond_Item_UnitTypeDD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_item_unitTypeDD:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 120, row8_y + 3)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 100, condFrame.cond_item_unitTypeDD)
  end

  -- Quantity (Item)
  condFrame.cond_item_text_stack = MakeCheck("DoiteCond_Item_TextStack", "Icon text", 0, row9_y)
  condFrame.cond_item_stacks_cb = MakeCheck("DoiteCond_Item_StacksCB", "Quantity", 75, row9_y)
  condFrame.cond_item_stacks_comp = MakeComparatorDD("DoiteCond_Item_StacksComp", 130, row9_y + 3, 50)
  condFrame.cond_item_stacks_val = MakeSmallEdit("DoiteCond_Item_StacksVal", 225, row9_y - 2, 40)
  condFrame.cond_item_stacks_val_enter = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_item_stacks_val_enter:SetPoint("LEFT", condFrame.cond_item_stacks_val, "RIGHT", 4, 0)
  condFrame.cond_item_stacks_val_enter:SetText("(#)")
  condFrame.cond_item_stacks_val_enter:Hide()
  SetSeparator("item", 9, "QUANTITY", true, true)

  -- RESOURCE (Power)
  condFrame.cond_item_power = MakeCheck("DoiteCond_Item_PowerCB", "Power", 0, row10_y)
  condFrame.cond_item_power_comp = MakeComparatorDD("DoiteCond_Item_PowerComp", 65, row10_y + 3, 50)
  condFrame.cond_item_power_val = MakeSmallEdit("DoiteCond_Item_PowerVal", 160, row10_y - 2, 40)
  condFrame.cond_item_power_val_enter = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_item_power_val_enter:SetPoint("LEFT", condFrame.cond_item_power_val, "RIGHT", 4, 0)
  condFrame.cond_item_power_val_enter:SetText("(%)")
  condFrame.cond_item_power_comp:Hide()
  condFrame.cond_item_power_val:Hide()
  condFrame.cond_item_power_val_enter:Hide()
  SetSeparator("item", 10, "RESOURCE", true, true)


  -- HEALTH CONDITION
  condFrame.cond_item_hp_my = MakeCheck("DoiteCond_Item_HP_My", "My HP", 0, row11_y)
  condFrame.cond_item_hp_tgt = MakeCheck("DoiteCond_Item_HP_Tgt", "Target HP", 65, row11_y)
  condFrame.cond_item_hp_comp = MakeComparatorDD("DoiteCond_Item_HP_Comp", 130, row11_y + 3, 50)
  condFrame.cond_item_hp_val = MakeSmallEdit("DoiteCond_Item_HP_Val", 225, row11_y - 2, 40)
  condFrame.cond_item_hp_val_enter = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_item_hp_val_enter:SetPoint("LEFT", condFrame.cond_item_hp_val, "RIGHT", 4, 0)
  condFrame.cond_item_hp_val_enter:SetText("(%)")
  condFrame.cond_item_hp_comp:Hide()
  condFrame.cond_item_hp_val:Hide()
  condFrame.cond_item_hp_val_enter:Hide()
  SetSeparator("item", 11, "HEALTH CONDITION", true, true)

  -- REMAINING TIME (no slider)
  condFrame.cond_item_remaining_cb = MakeCheck("DoiteCond_Item_RemCB", "Remaining", 0, row12_y)
  condFrame.cond_item_remaining_comp = MakeComparatorDD("DoiteCond_Item_RemComp", 80, row12_y + 3, 50)
  condFrame.cond_item_remaining_val = MakeSmallEdit("DoiteCond_Item_RemVal", 175, row12_y - 2, 40)
  condFrame.cond_item_remaining_val_enter = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_item_remaining_val_enter:SetPoint("LEFT", condFrame.cond_item_remaining_val, "RIGHT", 4, 0)
  condFrame.cond_item_remaining_val_enter:SetText("(sec.)")
  condFrame.cond_item_remaining_comp:Hide()
  condFrame.cond_item_remaining_val:Hide()
  condFrame.cond_item_remaining_val_enter:Hide()
  condFrame.cond_item_text_time = MakeCheck("DoiteCond_Item_TextTime", "Icon text: Time remaining", 0, row12_y - 25)
  condFrame.cond_item_text_time_override = CreateFrame("EditBox", "DoiteCond_Item_TextTimeOverride", _Parent())
  condFrame.cond_item_text_time_override:SetWidth(100)
  condFrame.cond_item_text_time_override:SetHeight(18)
  condFrame.cond_item_text_time_override:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 165, row12_y - 25)
  StylePlainEditBox(condFrame.cond_item_text_time_override, "LEFT")
  condFrame.cond_item_text_time_override:Hide()

  condFrame.cond_item_text_override_note = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_item_text_override_note:SetPoint("TOPLEFT", condFrame.cond_item_text_time_override, "BOTTOMLEFT", -70, -2)
  condFrame.cond_item_text_override_note:SetTextColor(1, 0.82, 0)
  condFrame.cond_item_text_override_note:SetText("Input override aura Name or SpellID (on player based). Empty, equals default.")
  condFrame.cond_item_text_override_note:SetWidth(220)
  condFrame.cond_item_text_override_note:SetJustifyH("LEFT")
  condFrame.cond_item_text_override_note:Hide()
  SetSeparator("item", 12, "REMAINING TIME", true, true)

  -- CLASS-SPECIFIC (Combo points)
  condFrame.cond_item_cp_cb = MakeCheck("DoiteCond_Item_CP_CB", "Combo points", 0, row14_y)
  condFrame.cond_item_cp_comp = MakeComparatorDD("DoiteCond_Item_CP_Comp", 85, row14_y + 3, 50)
  condFrame.cond_item_cp_val = MakeSmallEdit("DoiteCond_Item_CP_Val", 180, row14_y - 2, 40)
  condFrame.cond_item_cp_val_enter = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_item_cp_val_enter:SetPoint("LEFT", condFrame.cond_item_cp_val, "RIGHT", 4, 0)
  condFrame.cond_item_cp_val_enter:SetText("(#)")
  condFrame.cond_item_cp_val_enter:Hide()
  SetSeparator("item", 14, "CLASS-SPECIFIC", true, true)

  -- Item: class-specific weapon / fighting-style dropdown (Shaman / Warrior / Paladin)
  condFrame.cond_item_weaponDD = CreateFrame("Frame", "DoiteCond_Item_WeaponDD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_item_weaponDD:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", -15, row14_y + 3)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 90, condFrame.cond_item_weaponDD)
  end
  condFrame.cond_item_weaponDD:Hide()
  _CD(condFrame.cond_item_weaponDD)

  -- Item: class-specific note for classes without combo points
  condFrame.cond_item_class_note = _Parent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  condFrame.cond_item_class_note:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 0, row14_y)
  condFrame.cond_item_class_note:SetTextColor(1, 0.82, 0)
  condFrame.cond_item_class_note:SetText("No class-specific option added for your class.")
  condFrame.cond_item_class_note:Hide()

  -- Item: Sound effects
  condFrame.cond_item_sound_oncd_cb = MakeCheck("DoiteCond_Item_Sound_OnCD_CB", "On cooldown", 0, row15_y)
  condFrame.cond_item_sound_oncd_dd = CreateFrame("Frame", "DoiteCond_Item_Sound_OnCD_DD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_item_sound_oncd_dd:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 100, row15_y + 3)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 140, condFrame.cond_item_sound_oncd_dd)
  end

  condFrame.cond_item_sound_offcd_cb = MakeCheck("DoiteCond_Item_Sound_OffCD_CB", "Off cooldown", 0, row15_y - 25)
  condFrame.cond_item_sound_offcd_dd = CreateFrame("Frame", "DoiteCond_Item_Sound_OffCD_DD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_item_sound_offcd_dd:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 100, row15_y - 22)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 140, condFrame.cond_item_sound_offcd_dd)
  end
  SetSeparator("item", 15, "SOUND EFFECTS", true, true)

  -- Item: dynamic Aura Conditions section
  local itemAuraBaseY = row17_y - 25
  SetSeparator("item", 17, "EXTRA: VISIBILITY (SHOW/HIDE) CONDITIONS", true, true)
  condFrame.itemAuraAnchor = CreateFrame("Frame", nil, _Parent())
  condFrame.itemAuraAnchor:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 0, itemAuraBaseY)
  condFrame.itemAuraAnchor:SetPoint("TOPRIGHT", _Parent(), "TOPRIGHT", 0, itemAuraBaseY)
  condFrame.itemAuraAnchor:SetHeight(20)

  -- Item: dynamic Visual Effects Conditions section
  local itemVfxBaseY = row18_y
  SetSeparator("item", 18, "EXTRA: VISUAL EFFECT (GLOW/GREY) CONDITIONS", true, true)
  condFrame.itemVfxAnchor = CreateFrame("Frame", nil, _Parent())
  condFrame.itemVfxAnchor:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 0, itemVfxBaseY)
  condFrame.itemVfxAnchor:SetPoint("TOPRIGHT", _Parent(), "TOPRIGHT", 0, itemVfxBaseY)
  condFrame.itemVfxAnchor:SetHeight(20)

  -- Legacy icon-category widgets were removed; Group/Category is handled by DoiteGroup.AttachEditGroupUI.

  ----------------------------------------------------------------
  -- 'Form' dropdowns
  ----------------------------------------------------------------
  condFrame.cond_ability_formDD = CreateFrame("Frame", "DoiteCond_Ability_FormDD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_ability_formDD:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 165, row2_y + 3)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 90, condFrame.cond_ability_formDD)
  end
  condFrame.cond_ability_formDD:Hide()
  _CD(condFrame.cond_ability_formDD)

  condFrame.cond_aura_formDD = CreateFrame("Frame", "DoiteCond_Aura_FormDD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_aura_formDD:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 165, row2_y + 3)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 90, condFrame.cond_aura_formDD)
  end
  condFrame.cond_aura_formDD:Hide()
  _CD(condFrame.cond_aura_formDD)

  condFrame.cond_item_formDD = CreateFrame("Frame", "DoiteCond_Item_FormDD", _Parent(), "UIDropDownMenuTemplate")
  condFrame.cond_item_formDD:SetPoint("TOPLEFT", _Parent(), "TOPLEFT", 165, row2_y + 3)
  if UIDropDownMenu_SetWidth then
    pcall(UIDropDownMenu_SetWidth, 90, condFrame.cond_item_formDD)
  end
  condFrame.cond_item_formDD:Hide()
  _CD(condFrame.cond_item_formDD)

  ----------------------------------------------------------------
  -- Wiring: enforce exclusivity immediately + save to DB
  ----------------------------------------------------------------

  -- Ability row1 scripts (Usable / NotCD / OnCD)
  -- Rules:
  --  * At least one must stay checked.
  --  * Usable and NotCD are mutually exclusive.
  --  * Either Usable or NotCD can be combined with OnCD.
  local function _SaveAbilityModeFromUI()
    local usable = condFrame.cond_ability_usable:GetChecked() and true or false
    local notcd = condFrame.cond_ability_notcd:GetChecked() and true or false
    local oncd = condFrame.cond_ability_oncd:GetChecked() and true or false

    local mode
    if usable and oncd then
      mode = "usableoncd"
    elseif notcd and oncd then
      mode = "nocdoncd"
    elseif oncd then
      mode = "oncd"
    elseif usable then
      mode = "usable"
    else
      mode = "notcd"
    end

    SetExclusiveAbilityMode(mode)
  end

  condFrame.cond_ability_usable:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end

    if this:GetChecked() then
      condFrame.cond_ability_notcd:SetChecked(false)
    elseif not condFrame.cond_ability_notcd:GetChecked() and not condFrame.cond_ability_oncd:GetChecked() then
      this:SetChecked(true)
    end

    _SaveAbilityModeFromUI()
  end)

  condFrame.cond_ability_notcd:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end

    if this:GetChecked() then
      condFrame.cond_ability_usable:SetChecked(false)
    elseif not condFrame.cond_ability_usable:GetChecked() and not condFrame.cond_ability_oncd:GetChecked() then
      this:SetChecked(true)
    end

    _SaveAbilityModeFromUI()
  end)

  condFrame.cond_ability_oncd:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end

    if (not this:GetChecked())
        and (not condFrame.cond_ability_usable:GetChecked())
        and (not condFrame.cond_ability_notcd:GetChecked()) then
      this:SetChecked(true)
    end

    _SaveAbilityModeFromUI()
  end)

  -- Item Usability & Cooldown (NotCD / OnCD can be combined; at least one must be checked)
  condFrame.cond_item_notcd:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end

    -- enforce: at least one of notcd/oncd must remain checked
    if (not this:GetChecked()) and (not condFrame.cond_item_oncd:GetChecked()) then
      this:SetChecked(true)
    end

    local notcd = condFrame.cond_item_notcd:GetChecked() and true or false
    local oncd  = condFrame.cond_item_oncd:GetChecked() and true or false

    local mode
    if notcd and oncd then
      mode = "both"
    elseif notcd then
      mode = "notcd"
    else
      mode = "oncd"
    end

    SetExclusiveItemMode(mode)
  end)

  condFrame.cond_item_oncd:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end

    -- enforce: at least one of notcd/oncd must remain checked
    if (not this:GetChecked()) and (not condFrame.cond_item_notcd:GetChecked()) then
      this:SetChecked(true)
    end

    local notcd = condFrame.cond_item_notcd:GetChecked() and true or false
    local oncd  = condFrame.cond_item_oncd:GetChecked() and true or false

    local mode
    if notcd and oncd then
      mode = "both"
    elseif notcd then
      mode = "notcd"
    else
      mode = "oncd"
    end

    SetExclusiveItemMode(mode)
  end)

  local function _AbilitySoundToggle(which)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.ability = d.conditions.ability or {}

    local cb = (which == "oncd") and condFrame.cond_ability_sound_oncd_cb
        or ((which == "offcd") and condFrame.cond_ability_sound_offcd_cb or condFrame.cond_ability_sound_onproc_cb)
    local dd = (which == "oncd") and condFrame.cond_ability_sound_oncd_dd
        or ((which == "offcd") and condFrame.cond_ability_sound_offcd_dd or condFrame.cond_ability_sound_onproc_dd)
    local field = (which == "oncd") and "soundOnCD"
        or ((which == "offcd") and "soundOffCD" or "soundOnProc")
    local enabledField = (which == "oncd") and "soundOnCDEnabled"
        or ((which == "offcd") and "soundOffCDEnabled" or "soundOnProcEnabled")

    local enabled = cb and cb.GetChecked and cb:GetChecked()
    if enabled then
      DoiteEdit_SetSoundEnabled("ability", enabledField, true)
      DoiteEdit_SetDropdownInteractive(dd, true)
    else
      DoiteEdit_SetSoundEnabled("ability", enabledField, false)
      d.conditions.ability[field] = nil
      DoiteEdit_SetSoundFromDropdown("ability", field, nil)
      DoiteEdit_InitSoundDropdown(dd, "ability", field, nil)
      DoiteEdit_SetDropdownInteractive(dd, false)
    end
  end

  condFrame.cond_ability_sound_oncd_cb:SetScript("OnClick", function() _AbilitySoundToggle("oncd") end)
  condFrame.cond_ability_sound_offcd_cb:SetScript("OnClick", function() _AbilitySoundToggle("offcd") end)
  condFrame.cond_ability_sound_onproc_cb:SetScript("OnClick", function() _AbilitySoundToggle("onproc") end)

  local function _AuraSoundToggle(which)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.aura = d.conditions.aura or {}

    local cb = (which == "ongain") and condFrame.cond_aura_sound_ongain_cb or condFrame.cond_aura_sound_onfade_cb
    local dd = (which == "ongain") and condFrame.cond_aura_sound_ongain_dd or condFrame.cond_aura_sound_onfade_dd
    local field = (which == "ongain") and "soundOnGain" or "soundOnFade"
    local enabledField = (which == "ongain") and "soundOnGainEnabled" or "soundOnFadeEnabled"

    local enabled = cb and cb.GetChecked and cb:GetChecked()
    if enabled then
      DoiteEdit_SetSoundEnabled("aura", enabledField, true)
      DoiteEdit_SetDropdownInteractive(dd, true)
    else
      DoiteEdit_SetSoundEnabled("aura", enabledField, false)
      d.conditions.aura[field] = nil
      DoiteEdit_SetSoundFromDropdown("aura", field, nil)
      DoiteEdit_InitSoundDropdown(dd, "aura", field, nil)
      DoiteEdit_SetDropdownInteractive(dd, false)
    end
  end

  condFrame.cond_aura_sound_ongain_cb:SetScript("OnClick", function() _AuraSoundToggle("ongain") end)
  condFrame.cond_aura_sound_onfade_cb:SetScript("OnClick", function() _AuraSoundToggle("onfade") end)

  local function _ItemSoundToggle(which)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.item = d.conditions.item or {}

    local cb = (which == "oncd") and condFrame.cond_item_sound_oncd_cb or condFrame.cond_item_sound_offcd_cb
    local dd = (which == "oncd") and condFrame.cond_item_sound_oncd_dd or condFrame.cond_item_sound_offcd_dd
    local field = (which == "oncd") and "soundOnCD" or "soundOffCD"
    local enabledField = (which == "oncd") and "soundOnCDEnabled" or "soundOffCDEnabled"

    local enabled = cb and cb.GetChecked and cb:GetChecked()
    if enabled then
      DoiteEdit_SetSoundEnabled("item", enabledField, true)
      DoiteEdit_SetDropdownInteractive(dd, true)
    else
      DoiteEdit_SetSoundEnabled("item", enabledField, false)
      d.conditions.item[field] = nil
      DoiteEdit_SetSoundFromDropdown("item", field, nil)
      DoiteEdit_InitSoundDropdown(dd, "item", field, nil)
      DoiteEdit_SetDropdownInteractive(dd, false)
    end
  end

  condFrame.cond_item_sound_oncd_cb:SetScript("OnClick", function() _ItemSoundToggle("oncd") end)
  condFrame.cond_item_sound_offcd_cb:SetScript("OnClick", function() _ItemSoundToggle("offcd") end)
  
  condFrame.cond_item_clickable:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    -- Direct save to DB
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.item = d.conditions.item or {}
    local ic = d.conditions.item
    
    ic.clickable = this:GetChecked() and true or nil
    _SR()
    _SE()
  end)

  -- Item: Enchanted state dropdown
  if condFrame.cond_item_enchant then
    _CD(condFrame.cond_item_enchant)

    UIDropDownMenu_Initialize(condFrame.cond_item_enchant, function(frame, level, menuList)
      local function _Add(text, value)
        local info = UIDropDownMenu_CreateInfo()
        info.text = text
        info.value = value
        info.func = function(button)
          if not _CK() then
            return
          end

          local d = _EDB(_CK())
          d.conditions = d.conditions or {}
          d.conditions.item = d.conditions.item or {}
          local ic = d.conditions.item

          local v = (button and button.value) or value

          if v == "true" then
            ic.enchant = true
          elseif v == "false" then
            ic.enchant = false
          else
            -- "any" or anything else
            ic.enchant = nil
          end

          -- Update dropdown UI immediately so selection is visible even before refresh repaints
          if condFrame and condFrame.cond_item_enchant then
            local dd = condFrame.cond_item_enchant
            local txt = "Enchanted state"
            local sel = nil

            if ic.enchant == true then
              txt = "Enchanted"
              sel = "true"
            elseif ic.enchant == false then
              txt = "Not enchanted"
              sel = "false"
            else
              txt = "Enchanted state"
              sel = nil
            end

            if UIDropDownMenu_SetSelectedValue then
              pcall(UIDropDownMenu_SetSelectedValue, dd, sel)
            end
            if UIDropDownMenu_SetText then
              pcall(UIDropDownMenu_SetText, txt, dd)
            end
          end

          UpdateCondFrameForKey(_CK())
          _SR()
          _SE()
        end

        UIDropDownMenu_AddButton(info)
      end

      _Add("Any", "any")
      _Add("Enchanted", "true")
      _Add("Not enchanted", "false")
    end)
  end

  -- Item: Icon text: Enchant uptime remaining
  if condFrame.cond_item_text_enchant then
    condFrame.cond_item_text_enchant:SetScript("OnClick", function()
      if not _CK() then
        this:SetChecked(false)
        return
      end

      local d = _EDB(_CK())
      d.conditions = d.conditions or {}
      d.conditions.item = d.conditions.item or {}
      local ic = d.conditions.item

      if this:GetChecked() then
        ic.textTimeRemaining = true
      else
        ic.textTimeRemaining = nil
      end

      UpdateCondFrameForKey(_CK())
      _SR()
      _SE()
    end)
  end

  -- Ability combat row 2 - toggles are now independent (not exclusive)
  condFrame.cond_ability_incombat:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end

    if not this:GetChecked() and not condFrame.cond_ability_outcombat:GetChecked() then
      this:SetChecked(true)
      return
    end

    SetCombatFlag("ability", "in", this:GetChecked())
  end)

  condFrame.cond_ability_outcombat:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end

    if not this:GetChecked() and not condFrame.cond_ability_incombat:GetChecked() then
      this:SetChecked(true)
      return
    end

    SetCombatFlag("ability", "out", this:GetChecked())
  end)
  

  -- Item combat row (independent, at least one)
  condFrame.cond_item_incombat:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    if not this:GetChecked() and not condFrame.cond_item_outcombat:GetChecked() then
      this:SetChecked(true)
      return
    end
    SetCombatFlag("item", "in", this:GetChecked())
  end)

  condFrame.cond_item_outcombat:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    if not this:GetChecked() and not condFrame.cond_item_incombat:GetChecked() then
      this:SetChecked(true)
      return
    end
    SetCombatFlag("item", "out", this:GetChecked())
  end)

  -- Ability target row (multi-select) + target status row
  local function SaveAbilityTargetsFromUI()
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.ability = d.conditions.ability or {}

    local ca = d.conditions.ability

    ca.targetHelp = condFrame.cond_ability_target_help:GetChecked() and true or false
    ca.targetHarm = condFrame.cond_ability_target_harm:GetChecked() and true or false
    ca.targetSelf = condFrame.cond_ability_target_self:GetChecked() and true or false
    ca.targetAlive = condFrame.cond_ability_target_alive:GetChecked() and true or false
    ca.targetDead = condFrame.cond_ability_target_dead:GetChecked() and true or false
  end

  condFrame.cond_ability_target_alive:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end

    if this:GetChecked() then
      -- turn off Dead when Alive is ticked
      condFrame.cond_ability_target_dead:SetChecked(false)
    end

    SaveAbilityTargetsFromUI()
    _SR();
    _SE()
  end)

  condFrame.cond_ability_target_dead:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end

    if this:GetChecked() then
      -- turn off Alive when Dead is ticked
      condFrame.cond_ability_target_alive:SetChecked(false)
    end

    SaveAbilityTargetsFromUI()
    _SR();
    _SE()
  end)

  condFrame.cond_ability_target_help:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    SaveAbilityTargetsFromUI()
    _SR();
    _SE()
    -- Make sure Target Distance & Type DDs re-evaluate lock state
    UpdateCondFrameForKey(_CK())
  end)

  condFrame.cond_ability_target_harm:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    SaveAbilityTargetsFromUI()
    _SR();
    _SE()
    -- Make sure Target Distance & Type DDs re-evaluate lock state
    UpdateCondFrameForKey(_CK())
  end)

  condFrame.cond_ability_target_self:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    SaveAbilityTargetsFromUI()
    _SR();
    _SE()
    -- Make sure Target Distance & Type DDs re-evaluate lock state
    UpdateCondFrameForKey(_CK())
  end)

  -- Item target row (same logic as abilities)
  local function SaveItemTargetsFromUI()
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.item = d.conditions.item or {}

    local ca = d.conditions.item

    ca.targetHelp = condFrame.cond_item_target_help:GetChecked() and true or false
    ca.targetHarm = condFrame.cond_item_target_harm:GetChecked() and true or false
    ca.targetSelf = condFrame.cond_item_target_self:GetChecked() and true or false
    ca.targetAlive = condFrame.cond_item_target_alive:GetChecked() and true or false
    ca.targetDead = condFrame.cond_item_target_dead:GetChecked() and true or false
  end

  condFrame.cond_item_target_alive:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    if this:GetChecked() then
      condFrame.cond_item_target_dead:SetChecked(false)
    end
    SaveItemTargetsFromUI()
    _SR();
    _SE()
  end)

  condFrame.cond_item_target_dead:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    if this:GetChecked() then
      condFrame.cond_item_target_alive:SetChecked(false)
    end
    SaveItemTargetsFromUI()
    _SR();
    _SE()
  end)

  condFrame.cond_item_target_help:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    SaveItemTargetsFromUI()
    _SR();
    _SE()
    -- Re-evaluate Target Distance & Type DD lock state for item
    UpdateCondFrameForKey(_CK())
  end)

  condFrame.cond_item_target_harm:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    SaveItemTargetsFromUI()
    _SR();
    _SE()
    -- Re-evaluate Target Distance & Type DD lock state for item
    UpdateCondFrameForKey(_CK())
  end)

  condFrame.cond_item_target_self:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    SaveItemTargetsFromUI()
    _SR();
    _SE()
    -- Re-evaluate Target Distance & Type DD lock state for item
    UpdateCondFrameForKey(_CK())
  end)

  -- Item WHEREABOUTS row (Equipped / In backpack / Missing)
  local function SaveItemWhereaboutsFromUI()
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.item = d.conditions.item or {}
    local ic = d.conditions.item
    ic.whereEquipped = condFrame.cond_item_where_equipped:GetChecked() and true or false
    ic.whereBag = condFrame.cond_item_where_bag:GetChecked() and true or false
    ic.whereMissing = condFrame.cond_item_where_missing:GetChecked() and true or false
  end

  local function EnforceItemWhereabouts(clicked)
    local eq = condFrame.cond_item_where_equipped:GetChecked()
    local bg = condFrame.cond_item_where_bag:GetChecked()
    local ms = condFrame.cond_item_where_missing:GetChecked()

    -- (No exclusivity enforced anymore)

    eq = condFrame.cond_item_where_equipped:GetChecked()
    bg = condFrame.cond_item_where_bag:GetChecked()
    ms = condFrame.cond_item_where_missing:GetChecked()

    if not eq and not bg and not ms then
      if clicked then
        clicked:SetChecked(true)
      end
    end
  end

local function UpdateItemStacksForMissing()
    if not condFrame or not condFrame.cond_item_where_missing then
      return
    end

    local ms = condFrame.cond_item_where_missing:GetChecked() and true or false

    local function _setCheckState(cb, enabled, clearWhenDisabling)
      if not cb then
        return
      end
      if enabled then
        cb:Enable()
        if cb.text and cb.text.SetTextColor then
          cb.text:SetTextColor(1, 0.82, 0)
        end
      else
        if clearWhenDisabling and cb.SetChecked then
          cb:SetChecked(false)
        end
        cb:Disable()
        if cb.text and cb.text.SetTextColor then
          cb.text:SetTextColor(0.6, 0.6, 0.6)
        end
      end
    end

    -- If item is marked Missing ONLY: stacks condition + "Icon text: Stacks" do not apply.
    local eq = condFrame.cond_item_where_equipped and condFrame.cond_item_where_equipped:GetChecked()
    local bg = condFrame.cond_item_where_bag and condFrame.cond_item_where_bag:GetChecked()

    -- Only disable features if Missing is checked AND neither Equipped nor Bag is checked
    local shouldDisable = (ms and (not eq) and (not bg))
    
    _setCheckState(condFrame.cond_item_stacks_cb, (not shouldDisable), true)
    _setCheckState(condFrame.cond_item_text_stack, (not shouldDisable), true)

    if shouldDisable then
      if condFrame.cond_item_stacks_comp then
        condFrame.cond_item_stacks_comp:Hide()
      end
      if condFrame.cond_item_stacks_val then
        condFrame.cond_item_stacks_val:Hide()
      end
      if condFrame.cond_item_stacks_val_enter then
        condFrame.cond_item_stacks_val_enter:Hide()
      end
    end

    -- keep DB in sync with programmatic UI changes
    if _CK() then
      local d = _EDB(_CK())
      d.conditions = d.conditions or {}
      d.conditions.item = d.conditions.item or {}

      local stacksOn = (condFrame.cond_item_stacks_cb and condFrame.cond_item_stacks_cb.GetChecked
          and condFrame.cond_item_stacks_cb:GetChecked()) and true or false
      local textOn = (condFrame.cond_item_text_stack and condFrame.cond_item_text_stack.GetChecked
          and condFrame.cond_item_text_stack:GetChecked()) and true or false

      d.conditions.item.stacksEnabled = stacksOn and true or false
      d.conditions.item.textStackCounter = textOn and true or false
    end
  end

  condFrame.cond_item_where_equipped:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    EnforceItemWhereabouts(this)
    SaveItemWhereaboutsFromUI()
    UpdateItemStacksForMissing()
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
  end)

  condFrame.cond_item_where_bag:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    EnforceItemWhereabouts(this)
    SaveItemWhereaboutsFromUI()
    UpdateItemStacksForMissing()
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
  end)

  condFrame.cond_item_where_missing:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    EnforceItemWhereabouts(this)
    SaveItemWhereaboutsFromUI()
    UpdateItemStacksForMissing()
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
  end)

  -- Inventory-slot radio rows for synthetic items ("---EQUIPPED TRINKET SLOTS---" / "---EQUIPPED WEAPON SLOTS---")
  local function SaveItemInventoryTrinketFromUI()
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.item = d.conditions.item or {}
    local ic = d.conditions.item

    if condFrame.cond_item_inv_trinket1:GetChecked() then
      ic.inventorySlot = "TRINKET1"
    elseif condFrame.cond_item_inv_trinket2:GetChecked() then
      ic.inventorySlot = "TRINKET2"
    elseif condFrame.cond_item_inv_trinket_both:GetChecked() then
      ic.inventorySlot = "TRINKET_BOTH"
    else
      -- default / fallback
      ic.inventorySlot = "TRINKET_FIRST"
    end
  end

  local function SaveItemInventoryWeaponFromUI()
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.item = d.conditions.item or {}
    local ic = d.conditions.item

    if condFrame.cond_item_inv_wep_mainhand:GetChecked() then
      ic.inventorySlot = "MAINHAND"
    elseif condFrame.cond_item_inv_wep_offhand:GetChecked() then
      ic.inventorySlot = "OFFHAND"
    elseif condFrame.cond_item_inv_wep_ammo and condFrame.cond_item_inv_wep_ammo:GetChecked() then
      ic.inventorySlot = "AMMO"
    else
      -- default / fallback
      ic.inventorySlot = "RANGED"
    end
  end

  local function EnforceInventoryRadio(clicked, group)
    if not clicked then
      return
    end

    if group == "TRINKET" then
      local c1 = condFrame.cond_item_inv_trinket1
      local c2 = condFrame.cond_item_inv_trinket2
      local c3 = condFrame.cond_item_inv_trinket_first
      local c4 = condFrame.cond_item_inv_trinket_both

      if clicked:GetChecked() then
        if clicked ~= c1 then
          c1:SetChecked(false)
        end
        if clicked ~= c2 then
          c2:SetChecked(false)
        end
        if clicked ~= c3 then
          c3:SetChecked(false)
        end
        if clicked ~= c4 then
          c4:SetChecked(false)
        end
      end

      -- ensure at least one checked
      if not c1:GetChecked() and not c2:GetChecked() and not c3:GetChecked() and not c4:GetChecked() then
        clicked:SetChecked(true)
      end

    elseif group == "WEAPON" then
      local c1 = condFrame.cond_item_inv_wep_mainhand
      local c2 = condFrame.cond_item_inv_wep_offhand
      local c3 = condFrame.cond_item_inv_wep_ranged
      local c4 = condFrame.cond_item_inv_wep_ammo

      if clicked:GetChecked() then
        if clicked ~= c1 then
          c1:SetChecked(false)
        end
        if clicked ~= c2 then
          c2:SetChecked(false)
        end
        if clicked ~= c3 then
          c3:SetChecked(false)
        end
        if c4 and clicked ~= c4 then
          c4:SetChecked(false)
        end
      end

      -- ensure at least one checked
      if not c1:GetChecked() and not c2:GetChecked() and not c3:GetChecked() and (not c4 or not c4:GetChecked()) then
        clicked:SetChecked(true)
      end
    end
  end

  -- Trinket inventory-slot clicks
  condFrame.cond_item_inv_trinket1:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    EnforceInventoryRadio(this, "TRINKET")
    SaveItemInventoryTrinketFromUI()
    _SR();
    _SE()
  end)
  condFrame.cond_item_inv_trinket2:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    EnforceInventoryRadio(this, "TRINKET")
    SaveItemInventoryTrinketFromUI()
    _SR();
    _SE()
  end)
  condFrame.cond_item_inv_trinket_first:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    EnforceInventoryRadio(this, "TRINKET")
    SaveItemInventoryTrinketFromUI()
    _SR();
    _SE()
  end)
  condFrame.cond_item_inv_trinket_both:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    EnforceInventoryRadio(this, "TRINKET")
    SaveItemInventoryTrinketFromUI()
    _SR();
    _SE()
  end)

  -- Weapon inventory-slot clicks
  condFrame.cond_item_inv_wep_mainhand:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    EnforceInventoryRadio(this, "WEAPON")
    SaveItemInventoryWeaponFromUI()
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
  end)
  condFrame.cond_item_inv_wep_offhand:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    EnforceInventoryRadio(this, "WEAPON")
    SaveItemInventoryWeaponFromUI()
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
  end)
  condFrame.cond_item_inv_wep_ranged:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    EnforceInventoryRadio(this, "WEAPON")
    SaveItemInventoryWeaponFromUI()
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
  end)
  condFrame.cond_item_inv_wep_ammo:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    EnforceInventoryRadio(this, "WEAPON")
    SaveItemInventoryWeaponFromUI()
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
  end)


  -- Aura mode (found / missing; both allowed). At least one must stay checked.
  local function _SaveAuraModeFromUI()
    local found = condFrame.cond_aura_found:GetChecked() and true or false
    local missing = condFrame.cond_aura_missing:GetChecked() and true or false

    local mode
    if found and missing then
      mode = "both"
    elseif missing then
      mode = "missing"
    else
      mode = "found"
    end

    SetExclusiveAuraFoundMode(mode)
  end

  condFrame.cond_aura_found:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end

    if (not this:GetChecked()) and (not condFrame.cond_aura_missing:GetChecked()) then
      this:SetChecked(true)
    end

    _SaveAuraModeFromUI()

    -- Keep DB/UI logic in sync (needed later when greying out owner on "missing")
    if UpdateCondFrameForKey then
      UpdateCondFrameForKey(_CK())
    end
    _SR();
    _SE()
  end)

  condFrame.cond_aura_missing:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end

    if (not this:GetChecked()) and (not condFrame.cond_aura_found:GetChecked()) then
      this:SetChecked(true)
    end

    _SaveAuraModeFromUI()

    if UpdateCondFrameForKey then
      UpdateCondFrameForKey(_CK())
    end
    _SR();
    _SE()
  end)

  -- Aura combat row 2 - toggles (independent)
  condFrame.cond_aura_incombat:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end

    if not this:GetChecked() and not condFrame.cond_aura_outcombat:GetChecked() then
      this:SetChecked(true)
      return
    end

    SetCombatFlag("aura", "in", this:GetChecked())
  end)

  condFrame.cond_aura_outcombat:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end

    if not this:GetChecked() and not condFrame.cond_aura_incombat:GetChecked() then
      this:SetChecked(true)
      return
    end

    SetCombatFlag("aura", "out", this:GetChecked())
  end)

  -- Aura target row (Self is exclusive; Help/Harm can combine; at least one must be checked)
  local function SaveAuraTargets()
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}

    local ca = d.conditions.aura

    ca.targetHelp = condFrame.cond_aura_target_help:GetChecked() and true or false
    ca.targetHarm = condFrame.cond_aura_target_harm:GetChecked() and true or false
    ca.targetSelf = condFrame.cond_aura_onself:GetChecked() and true or false
    ca.targetAlive = condFrame.cond_aura_target_alive:GetChecked() and true or false
    ca.targetDead = condFrame.cond_aura_target_dead:GetChecked() and true or false
  end

  local function EnforceAuraExclusivity(changedBox)
    local h = condFrame.cond_aura_target_help:GetChecked()
    local hm = condFrame.cond_aura_target_harm:GetChecked()
    local s = condFrame.cond_aura_onself:GetChecked()

    -- Self exclusive: if Self checked, uncheck Help/Harm
    if changedBox == condFrame.cond_aura_onself and s then
      condFrame.cond_aura_target_help:SetChecked(false)
      condFrame.cond_aura_target_harm:SetChecked(false)
    end

    -- If Help/Harm gets checked while Self is on, turn Self off
    if (changedBox == condFrame.cond_aura_target_help and condFrame.cond_aura_target_help:GetChecked())
        or (changedBox == condFrame.cond_aura_target_harm and condFrame.cond_aura_target_harm:GetChecked()) then
      if condFrame.cond_aura_onself:GetChecked() then
        condFrame.cond_aura_onself:SetChecked(false)
      end
    end

    -- At least one must remain checked
    h = condFrame.cond_aura_target_help:GetChecked()
    hm = condFrame.cond_aura_target_harm:GetChecked()
    s = condFrame.cond_aura_onself:GetChecked()
    if (not h) and (not hm) and (not s) then
      -- Re-check the one the user just toggled off
      if changedBox then
        changedBox:SetChecked(true)
      end
    end
  end

  condFrame.cond_aura_target_alive:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    if this:GetChecked() then
      condFrame.cond_aura_target_dead:SetChecked(false)
    end
    SaveAuraTargets()
    _SR();
    _SE()
  end)

  condFrame.cond_aura_target_dead:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    if this:GetChecked() then
      condFrame.cond_aura_target_alive:SetChecked(false)
    end
    SaveAuraTargets()
    _SR();
    _SE()
  end)

  condFrame.cond_aura_target_help:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    EnforceAuraExclusivity(this)
    SaveAuraTargets()
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
  end)

  condFrame.cond_aura_target_harm:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    EnforceAuraExclusivity(this)
    SaveAuraTargets()
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
  end)

  condFrame.cond_aura_onself:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    EnforceAuraExclusivity(this)
    SaveAuraTargets()
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
  end)

  -- Aura owner flags ("My Aura" / "Others Aura") + dependent controls.
  local function _SetAuraCheckEnabled(cb, enabled, clearWhenDisabling)
    if not cb then
      return
    end

    if enabled then
      if cb.Enable then
        cb:Enable()
      end
      if cb.text and cb.text.SetTextColor then
        cb.text:SetTextColor(1, 0.82, 0)
      end
    else
      if clearWhenDisabling and cb.SetChecked then
        cb:SetChecked(false)
      end
      if cb.Disable then
        cb:Disable()
      end
      if cb.text and cb.text.SetTextColor then
        cb.text:SetTextColor(0.6, 0.6, 0.6)
      end
    end
  end

  _G["DoiteEdit_AuraOwner_UpdateDependentChecks"] = function()
    if not condFrame then
      return
    end

    local mine = condFrame.cond_aura_mine
        and condFrame.cond_aura_mine.GetChecked
        and condFrame.cond_aura_mine:GetChecked()
    local others = condFrame.cond_aura_others
        and condFrame.cond_aura_others.GetChecked
        and condFrame.cond_aura_others:GetChecked()

    local ownerActive = (mine or others) and true or false

    local rem = condFrame.cond_aura_remaining_cb
    local textR = condFrame.cond_aura_text_time

    -- keep DB in sync with programmatic UI changes (SetChecked doesn't fire OnClick)
    if _CK() then
      local d = _EDB(_CK())
      d.conditions = d.conditions or {}
      d.conditions.aura = d.conditions.aura or {}

      local remOn = (rem and rem.GetChecked and rem:GetChecked()) and true or false
      local textOn = (textR and textR.GetChecked and textR:GetChecked()) and true or false

      d.conditions.aura.remainingEnabled = remOn or false
      d.conditions.aura.textTimeRemaining = textOn or false
    end
  end

  local function AuraOwner_EnforceExclusivity(changed)
    if not condFrame then
      return
    end
    local mine = condFrame.cond_aura_mine
    local others = condFrame.cond_aura_others

    if not mine or not others then
      AuraOwner_UpdateDependentChecks()
      return
    end

    if changed == mine and mine:GetChecked() then
      others:SetChecked(false)
    elseif changed == others and others:GetChecked() then
      mine:SetChecked(false)
    end

    -- "Neither" is allowed; no extra enforcement here.

    AuraOwner_UpdateDependentChecks()
  end

  local function SaveAuraOwnerFlags(changed)
    if not _CK() then
      return
    end

    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.aura = d.conditions.aura or {}

    local mine = (condFrame.cond_aura_mine and condFrame.cond_aura_mine:GetChecked()) and true or false
    local others = (condFrame.cond_aura_others and condFrame.cond_aura_others:GetChecked()) and true or false

    -- Hard exclusivity at DB level: if both somehow end up true, keep only the one just clicked.
    if mine and others then
      if changed == condFrame.cond_aura_mine then
        others = false
        if condFrame.cond_aura_others and condFrame.cond_aura_others.SetChecked then
          condFrame.cond_aura_others:SetChecked(false)
        end
      elseif changed == condFrame.cond_aura_others then
        mine = false
        if condFrame.cond_aura_mine and condFrame.cond_aura_mine.SetChecked then
          condFrame.cond_aura_mine:SetChecked(false)
        end
      else
        -- Fallback: prefer "My Aura"
        others = false
        if condFrame.cond_aura_others and condFrame.cond_aura_others.SetChecked then
          condFrame.cond_aura_others:SetChecked(false)
        end
      end
    end

    d.conditions.aura.onlyMine = mine or nil
    d.conditions.aura.onlyOthers = others or nil

    -- Also update remaining/text checks whenever owner flags change.
    AuraOwner_UpdateDependentChecks()
  end


  -- Aura remaining toggle
  condFrame.cond_aura_remaining_cb:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.remainingEnabled = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK())
    _SR()
    _SE()
  end)

  -- Wire up the Aura owner checkboxes ("My Aura" / "Others Aura")
  if condFrame.cond_aura_mine then
    condFrame.cond_aura_mine:SetScript("OnClick", function()
      if not _CK() then
        this:SetChecked(false)
        return
      end

      -- Enforce exclusive state and update Remaining/Text logic
      AuraOwner_EnforceExclusivity(this)
      SaveAuraOwnerFlags(this)

      _SR();
      _SE()

      if UpdateCondFrameForKey then
        UpdateCondFrameForKey(_CK())
      end
    end)
  end

  if condFrame.cond_aura_others then
    condFrame.cond_aura_others:SetScript("OnClick", function()
      if not _CK() then
        this:SetChecked(false)
        return
      end

      -- Enforce exclusive state and update Remaining/Text logic
      AuraOwner_EnforceExclusivity(this)
      SaveAuraOwnerFlags(this)

      _SR();
      _SE()

      if UpdateCondFrameForKey then
        UpdateCondFrameForKey(_CK())
      end
    end)
  end

  -- Aura stacks toggle
  condFrame.cond_aura_stacks_cb:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.stacksEnabled = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK())
    _SR()
    _SE()
  end)


  -- Aura glow / greyscale
  condFrame.cond_aura_glow:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.glow = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK())
    _SR()
    _SE()
  end)

  condFrame.cond_aura_greyscale:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.greyscale = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK())
    _SR()
    _SE()
  end)

  condFrame.cond_aura_fade:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.fade = this:GetChecked() and true or false
    if d.conditions.aura.fade and not d.conditions.aura.fadeAlpha then
      d.conditions.aura.fadeAlpha = 0
    end
    UpdateCondFrameForKey(_CK())
    _SR()
    _SE()
  end)

  local function SaveAuraFadeAlpha()
    if not _CK() then return end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.fadeAlpha = _ParseFadeAlphaFromBox(condFrame.cond_aura_fade_slider)
    _NormalizeFadeBox(condFrame.cond_aura_fade_slider, d.conditions.aura.fadeAlpha)
    _SR()
    _SE()
  end
  condFrame.cond_aura_fade_slider:SetScript("OnEnterPressed", function() SaveAuraFadeAlpha(); this:ClearFocus() end)
  condFrame.cond_aura_fade_slider:SetScript("OnEditFocusLost", SaveAuraFadeAlpha)
  condFrame.cond_aura_fade_slider:SetScript("OnEscapePressed", function() this:ClearFocus() end)

  -- === Combo points enable toggles ===
  condFrame.cond_ability_cp_cb:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK());
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.cpEnabled = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK());
    _SR();
    _SE()
  end)
  condFrame.cond_aura_cp_cb:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK());
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.cpEnabled = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK());
    _SR();
    _SE()
  end)
  condFrame.cond_item_cp_cb:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK());
    d.conditions.item = d.conditions.item or {}
    d.conditions.item.cpEnabled = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK());
    _SR();
    _SE()
  end)

  -- === HP selectors (mutually exclusive, same X position widgets) ===
  local function _AbilityHP_Update(which)
    local d = _EDB(_CK());
    d.conditions.ability = d.conditions.ability or {}
    if which == "my" then
      condFrame.cond_ability_hp_tgt:SetChecked(false)
      d.conditions.ability.hpMode = "my"
    elseif which == "tgt" then
      condFrame.cond_ability_hp_my:SetChecked(false)
      d.conditions.ability.hpMode = "target"
    else
      d.conditions.ability.hpMode = nil
    end
    UpdateCondFrameForKey(_CK());
    _SR();
    _SE()
  end
  condFrame.cond_ability_hp_my:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    if this:GetChecked() then
      _AbilityHP_Update("my")
    else
      _AbilityHP_Update(nil)
    end
  end)
  condFrame.cond_ability_hp_tgt:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    if this:GetChecked() then
      _AbilityHP_Update("tgt")
    else
      _AbilityHP_Update(nil)
    end
  end)

  local function _AuraHP_Update(which)
    local d = _EDB(_CK());
    d.conditions.aura = d.conditions.aura or {}
    if which == "my" then
      condFrame.cond_aura_hp_tgt:SetChecked(false)
      d.conditions.aura.hpMode = "my"
    elseif which == "tgt" then
      condFrame.cond_aura_hp_my:SetChecked(false)
      d.conditions.aura.hpMode = "target"
    else
      d.conditions.aura.hpMode = nil
    end
    UpdateCondFrameForKey(_CK());
    _SR();
    _SE()
  end
  condFrame.cond_aura_hp_my:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    if this:GetChecked() then
      _AuraHP_Update("my")
    else
      _AuraHP_Update(nil)
    end
  end)
  condFrame.cond_aura_hp_tgt:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    if this:GetChecked() then
      _AuraHP_Update("tgt")
    else
      _AuraHP_Update(nil)
    end
  end)

  local function _ItemHP_Update(which)
    local d = _EDB(_CK());
    d.conditions.item = d.conditions.item or {}
    if which == "my" then
      condFrame.cond_item_hp_tgt:SetChecked(false)
      d.conditions.item.hpMode = "my"
    elseif which == "tgt" then
      condFrame.cond_item_hp_my:SetChecked(false)
      d.conditions.item.hpMode = "target"
    else
      d.conditions.item.hpMode = nil
    end
    UpdateCondFrameForKey(_CK());
    _SR();
    _SE()
  end
  condFrame.cond_item_hp_my:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    if this:GetChecked() then
      _ItemHP_Update("my")
    else
      _ItemHP_Update(nil)
    end
  end)
  condFrame.cond_item_hp_tgt:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    if this:GetChecked() then
      _ItemHP_Update("tgt")
    else
      _ItemHP_Update(nil)
    end
  end)

  -- === Ability slider extras ===
  condFrame.cond_ability_slider_glow:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK());
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.sliderGlow = this:GetChecked() and true or false
    _SR();
    _SE()
  end)
  condFrame.cond_ability_slider_grey:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK());
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.sliderGrey = this:GetChecked() and true or false
    _SR();
    _SE()
  end)

  -- === Text flags (ability/aura) ===
  condFrame.cond_ability_text_time:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK());
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.textTimeRemaining = this:GetChecked() and true or false
    _SR();
    _SE()
  end)
  condFrame.cond_aura_text_time:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK());
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.textTimeRemaining = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK())
    _SR();
    _SE()
  end)
  condFrame.cond_aura_text_stack:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK());
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.textStackCounter = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK())
    _SR();
    _SE()
  end)

  if condFrame.cond_aura_trackpet then
    condFrame.cond_aura_trackpet:SetScript("OnClick", function()
      if not _CK() then
        this:SetChecked(false)
        return
      end
      local d = _EDB(_CK());
      d.conditions.aura = d.conditions.aura or {}
      d.conditions.aura.trackpet = this:GetChecked() and true or false
      if UpdateCondFrameForKey then
        UpdateCondFrameForKey(_CK())
      end
      _SR();
      _SE()
    end)
  end

  -- === Aura Power toggle ===
  condFrame.cond_aura_power:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK());
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.powerEnabled = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK());
    _SR();
    _SE()
  end)

  -- Item Power toggle
  condFrame.cond_item_power:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK());
    d.conditions.item = d.conditions.item or {}
    d.conditions.item.powerEnabled = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK());
    _SR();
    _SE()
  end)

  -- Item Remaining toggle
  condFrame.cond_item_remaining_cb:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK());
    d.conditions.item = d.conditions.item or {}
    d.conditions.item.remainingEnabled = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK());
    _SR();
    _SE()
  end)

  -- Item Stacks toggle
  condFrame.cond_item_stacks_cb:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local enabled = this:GetChecked() and true or false
    local d = _EDB(_CK());
    d.conditions.item = d.conditions.item or {}
    d.conditions.item.stacksEnabled = enabled

    if enabled then
      condFrame.cond_item_stacks_comp:Show()
      condFrame.cond_item_stacks_val:Show()
      condFrame.cond_item_stacks_val_enter:Show()
    else
      condFrame.cond_item_stacks_comp:Hide()
      condFrame.cond_item_stacks_val:Hide()
      condFrame.cond_item_stacks_val_enter:Hide()
    end

    UpdateCondFrameForKey(_CK());
    _SR();
    _SE()
  end)

  -- Item text: stack counter
  condFrame.cond_item_text_stack:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK());
    d.conditions.item = d.conditions.item or {}
    d.conditions.item.textStackCounter = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK())
    _SR();
    _SE()
  end)

  -- Item glow/greyscale
  condFrame.cond_item_glow:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK());
    d.conditions.item = d.conditions.item or {}
    d.conditions.item.glow = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK());
    _SR();
    _SE()
  end)
  condFrame.cond_item_greyscale:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK());
    d.conditions.item = d.conditions.item or {}
    d.conditions.item.greyscale = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK());
    _SR();
    _SE()
  end)
  condFrame.cond_item_fade:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK());
    d.conditions.item = d.conditions.item or {}
    d.conditions.item.fade = this:GetChecked() and true or false
    if d.conditions.item.fade and not d.conditions.item.fadeAlpha then
      d.conditions.item.fadeAlpha = 0
    end
    UpdateCondFrameForKey(_CK());
    _SR();
    _SE()
  end)

  local function SaveItemFadeAlpha()
    if not _CK() then return end
    local d = _EDB(_CK())
    d.conditions.item = d.conditions.item or {}
    d.conditions.item.fadeAlpha = _ParseFadeAlphaFromBox(condFrame.cond_item_fade_slider)
    _NormalizeFadeBox(condFrame.cond_item_fade_slider, d.conditions.item.fadeAlpha)
    _SR()
    _SE()
  end
  condFrame.cond_item_fade_slider:SetScript("OnEnterPressed", function() SaveItemFadeAlpha(); this:ClearFocus() end)
  condFrame.cond_item_fade_slider:SetScript("OnEditFocusLost", SaveItemFadeAlpha)
  condFrame.cond_item_fade_slider:SetScript("OnEscapePressed", function() this:ClearFocus() end)


  -- Item text: remaining time
  condFrame.cond_item_text_time:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK());
    d.conditions.item = d.conditions.item or {}
    d.conditions.item.textTimeRemaining = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK())
    _SR();
    _SE()
  end)

  local function _SaveAuraTextOverride(which)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.aura = d.conditions.aura or {}
    local ca = d.conditions.aura
    local eb = (which == "stack") and condFrame.cond_aura_text_stack_override or condFrame.cond_aura_text_time_override
    local txt = ""
    if eb and eb.GetText then
      txt = eb:GetText() or ""
      txt = string.gsub(txt, "^%s*(.-)%s*$", "%1")
      if txt ~= "" and (not tonumber(txt)) then
        txt = _TitleCase(txt)
      end
    end
    if which == "stack" then
      ca.stackOverride = (txt ~= "") and txt or nil
    else
      ca.remOverride = (txt ~= "") and txt or nil
    end
    UpdateCondFrameForKey(_CK())
    _SR();
    _SE()
  end

  if condFrame.cond_aura_text_time_override then
    condFrame.cond_aura_text_time_override:SetScript("OnEnterPressed", function()
      _SaveAuraTextOverride("rem")
      this:ClearFocus()
    end)
    condFrame.cond_aura_text_time_override:SetScript("OnEscapePressed", function()
      this:ClearFocus()
      UpdateCondFrameForKey(_CK())
    end)
  end
  if condFrame.cond_aura_text_stack_override then
    condFrame.cond_aura_text_stack_override:SetScript("OnEnterPressed", function()
      _SaveAuraTextOverride("stack")
      this:ClearFocus()
    end)
    condFrame.cond_aura_text_stack_override:SetScript("OnEscapePressed", function()
      this:ClearFocus()
      UpdateCondFrameForKey(_CK())
    end)
  end

  local function _SaveItemTextOverride()
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.item = d.conditions.item or {}
    local ci = d.conditions.item
    local txt = ""
    local eb = condFrame.cond_item_text_time_override
    if eb and eb.GetText then
      txt = eb:GetText() or ""
      txt = string.gsub(txt, "^%s*(.-)%s*$", "%1")
      if txt ~= "" and (not tonumber(txt)) then
        txt = _TitleCase(txt)
      end
    end
    ci.remOverride = (txt ~= "") and txt or nil
    UpdateCondFrameForKey(_CK())
    _SR();
    _SE()
  end

  if condFrame.cond_item_text_time_override then
    condFrame.cond_item_text_time_override:SetScript("OnEnterPressed", function()
      _SaveItemTextOverride()
      this:ClearFocus()
    end)
    condFrame.cond_item_text_time_override:SetScript("OnEscapePressed", function()
      this:ClearFocus()
      UpdateCondFrameForKey(_CK())
    end)
  end

  -- dropdown initializers
  local function InitComparatorDD(ddframe, commitFunc)
    UIDropDownMenu_Initialize(ddframe, function(frame, level, menuList)
      local info
      local choices = { ">=", "<=", "==" }
      for _, c in ipairs(choices) do
        local picked = c
        info = {}
        info.text = picked
        info.value = picked
        info.func = function(button)
          local val = (button and button.value) or picked
          if commitFunc then
            pcall(commitFunc, val)
          end
          UIDropDownMenu_SetSelectedValue(ddframe, val)
          UIDropDownMenu_SetText(val, ddframe)
          CloseDropDownMenus()
        end
        info.checked = (UIDropDownMenu_GetSelectedValue(ddframe) == picked)
        UIDropDownMenu_AddButton(info)
      end
    end)
  end

  ----------------------------------------------------------------
  -- Target Distance & Type dropdowns (shared lists)
  ----------------------------------------------------------------
  local distanceChoices = { "Any", "In range", "Not in range", "Behind", "In front", "Behind & in range", "In front & in range" }
  local distanceNeedsUnitXP = {
    ["Behind"] = true,
    ["In front"] = true,
    ["Behind & in range"] = true,
    ["In front & in range"] = true
  }

  local function _HasUnitXP()
    if type(UnitXP) ~= "function" then
      return false
    end
    local ok = pcall(UnitXP, "nop", "nop")
    return ok == true
  end

  local unitTypeChoices = {
    "Any", "Players", "NPC", "Boss", "Not a boss",
    "1. Humanoid", "2. Beast", "3. Dragonkin", "4. Undead",
    "5. Demon", "6. Giant", "7. Mechanical", "8. Elemental",
    -- Multi: versions (like forms; add common combos)
    "Multi: 1+2",
    "Multi: 1+4",
    "Multi: 1+2+3",
    "Multi: 2+3",
    "Multi: 4+5",
    "Multi: 5+8"
  }

  local function _CommitTargetField(typeKey, field, picked)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions[typeKey] = d.conditions[typeKey] or {}
    -- store nil for "Any" to keep DB clean
    if picked == "Any" then
      d.conditions[typeKey][field] = nil
    else
      d.conditions[typeKey][field] = picked
    end
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
  end

  local function InitSimpleListDD(dd, choices, typeKey, field, placeholder)
    if not dd then
      return
    end
    _CD(dd)
    UIDropDownMenu_Initialize(dd, function(frame, level, menuList)
      local info
      local hasUnitXP = _HasUnitXP()
      for _, txt in ipairs(choices) do
        local picked = txt
        info = {}
        local requiresUnitXP = (field == "targetDistance") and (distanceNeedsUnitXP[picked] == true)
        if requiresUnitXP and (not hasUnitXP) then
          info.text = "|cff808080Req.UnitXP: " .. txt .. "|r"
          info.disabled = true
        else
          info.text = txt
        end
        info.value = txt
        info.func = function(button)
          if requiresUnitXP and (not hasUnitXP) then
            return
          end
          local val = (button and button.value) or picked
          -- Update widget text/selection
          if UIDropDownMenu_SetSelectedValue then
            UIDropDownMenu_SetSelectedValue(dd, val)
          end
          if UIDropDownMenu_SetText then
            -- UIDropDownMenu_SetText(text, dropdownFrame)
            UIDropDownMenu_SetText(val, dd)
          end
          _GoldifyDD(dd)
          -- Persist to DB and refresh logic
          _CommitTargetField(typeKey, field, val)
          -- Close the dropdown like other DDs
          if CloseDropDownMenus then
            CloseDropDownMenus()
          end
        end
        -- No checkmark for these lists
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)
      end
    end)

    -- initial placeholder text
    if UIDropDownMenu_SetSelectedValue then
      pcall(UIDropDownMenu_SetSelectedValue, dd, nil)
    end
    if UIDropDownMenu_SetText and placeholder then
      -- placeholder text first, then the dropdown frame
      pcall(UIDropDownMenu_SetText, placeholder, dd)
    end
    _WhiteifyDDText(dd)
  end

  -- Ability DDs
  InitSimpleListDD(condFrame.cond_ability_distanceDD, distanceChoices, "ability", "targetDistance", "Distance")
  InitSimpleListDD(condFrame.cond_ability_unitTypeDD, unitTypeChoices, "ability", "targetUnitType", "Unit type")

  -- Aura DDs
  InitSimpleListDD(condFrame.cond_aura_distanceDD, distanceChoices, "aura", "targetDistance", "Distance")
  InitSimpleListDD(condFrame.cond_aura_unitTypeDD, unitTypeChoices, "aura", "targetUnitType", "Unit type")

  -- Item DDs
  InitSimpleListDD(condFrame.cond_item_distanceDD, distanceChoices, "item", "targetDistance", "Distance")
  InitSimpleListDD(condFrame.cond_item_unitTypeDD, unitTypeChoices, "item", "targetUnitType", "Unit type")

  -- slider direction dd
  UIDropDownMenu_Initialize(condFrame.cond_ability_slider_dir, function(frame, level, menuList)
    local info
    local choices = { "left", "right", "center", "up", "down" }
    for _, c in ipairs(choices) do
      local picked = c
      info = {}
      info.text = picked
      info.value = picked
      info.func = function(button)
        local val = (button and button.value) or picked
        if not _CK() then
          return
        end
        local d = _EDB(_CK())
        d.conditions = d.conditions or {}
        d.conditions.ability = d.conditions.ability or {}
        d.conditions.ability.sliderDir = val
        UIDropDownMenu_SetSelectedValue(condFrame.cond_ability_slider_dir, val)
        UIDropDownMenu_SetText(val, condFrame.cond_ability_slider_dir)
        _GoldifyDD(condFrame.cond_ability_slider_dir)
        CloseDropDownMenus()
        _SR()
        _SE()
      end
      info.checked = (UIDropDownMenu_GetSelectedValue(condFrame.cond_ability_slider_dir) == picked)
      UIDropDownMenu_AddButton(info)
    end
  end)

  -- Slider effect dd: Slide / Shatter.
  -- "slide" stores nil (default), keeping older saved icons untouched.
  -- "shatter" stores ca.sliderEffect = "shatter" (read by
  -- DoiteConditions._HandleAbilitySlider to route to DoiteShatter_Mgr).
  UIDropDownMenu_Initialize(condFrame.cond_ability_slider_effect, function(frame, level, menuList)
    local choices = {
      { text = "Slide",              value = "slide"   },
      { text = "Shatter (assemble)", value = "shatter" },
    }
    for _, c in ipairs(choices) do
      -- Copy both fields into local upvalues *before* the closure below.
      -- In Lua 5.0 the for-loop variable `c` is a single shared local
      -- whose scope ends with the loop; a closure that touches c.text
      -- later (on user click) sees nil and crashes.
      local picked     = c.value
      local pickedText = c.text
      local info = {}
      info.text = pickedText
      info.value = picked
      info.func = function(button)
        local val = (button and button.value) or picked
        if not _CK() then
          return
        end
        local d = _EDB(_CK())
        d.conditions = d.conditions or {}
        d.conditions.ability = d.conditions.ability or {}
        if val == "shatter" then
          d.conditions.ability.sliderEffect = "shatter"
        else
          d.conditions.ability.sliderEffect = nil
        end
        UIDropDownMenu_SetSelectedValue(condFrame.cond_ability_slider_effect, val)
        UIDropDownMenu_SetText(pickedText, condFrame.cond_ability_slider_effect)
        _GoldifyDD(condFrame.cond_ability_slider_effect)
        CloseDropDownMenus()
        _SR()
        _SE()
      end
      info.checked = (UIDropDownMenu_GetSelectedValue(condFrame.cond_ability_slider_effect) == picked)
      UIDropDownMenu_AddButton(info)
    end
  end)

  -- Refresh hook: caller (UpdateConditionsUI for the edited key) can
  -- invoke this after the panel's data changes, so the visible label
  -- tracks the DB value.
  condFrame.cond_ability_slider_effect.Refresh = function()
    if not _CK() then return end
    local d = DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[_CK()]
    local sv = d and d.conditions and d.conditions.ability
        and d.conditions.ability.sliderEffect
    local cur = (sv == "shatter") and "shatter" or "slide"
    UIDropDownMenu_SetSelectedValue(condFrame.cond_ability_slider_effect, cur)
    local label = (cur == "shatter") and "Shatter (assemble)" or "Slide"
    UIDropDownMenu_SetText(label, condFrame.cond_ability_slider_effect)
    _GoldifyDD(condFrame.cond_ability_slider_effect)
  end

  -- Prime the visible state.
  UIDropDownMenu_SetSelectedValue(condFrame.cond_ability_slider_effect, "slide")
  UIDropDownMenu_SetText("Slide", condFrame.cond_ability_slider_effect)
  _GoldifyDD(condFrame.cond_ability_slider_effect)

  -- attach comparator inits with commit functions that write to DB
  InitComparatorDD(condFrame.cond_ability_power_comp, function(picked)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.powerComp = picked
    _SR()
    _SE()
  end)

  InitComparatorDD(condFrame.cond_ability_remaining_comp, function(picked)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.remainingComp = picked
    _SR()
    _SE()
  end)

  InitComparatorDD(condFrame.cond_aura_remaining_comp, function(picked)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.remainingComp = picked
    _SR()
    _SE()
  end)

  InitComparatorDD(condFrame.cond_aura_stacks_comp, function(picked)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.stacksComp = picked
    _SR()
    _SE()
  end)

  InitComparatorDD(condFrame.cond_ability_cp_comp, function(picked)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.cpComp = picked
    _SR();
    _SE()
  end)
  InitComparatorDD(condFrame.cond_aura_cp_comp, function(picked)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.cpComp = picked
    _SR();
    _SE()
  end)
  InitComparatorDD(condFrame.cond_item_cp_comp, function(picked)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions.item = d.conditions.item or {}
    d.conditions.item.cpComp = picked
    _SR();
    _SE()
  end)

  -- HP comparators
  InitComparatorDD(condFrame.cond_ability_hp_comp, function(picked)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.hpComp = picked
    _SR();
    _SE()
  end)
  InitComparatorDD(condFrame.cond_aura_hp_comp, function(picked)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.hpComp = picked
    _SR();
    _SE()
  end)
  InitComparatorDD(condFrame.cond_item_hp_comp, function(picked)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions.item = d.conditions.item or {}
    d.conditions.item.hpComp = picked
    _SR();
    _SE()
  end)

  -- Aura Power comparator
  InitComparatorDD(condFrame.cond_aura_power_comp, function(picked)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.powerComp = picked
    _SR();
    _SE()
  end)

  -- Item Power comparator
  InitComparatorDD(condFrame.cond_item_power_comp, function(picked)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions.item = d.conditions.item or {}
    d.conditions.item.powerComp = picked
    _SR();
    _SE()
  end)

  -- Item Remaining comparator
  InitComparatorDD(condFrame.cond_item_remaining_comp, function(picked)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions.item = d.conditions.item or {}
    d.conditions.item.remainingComp = picked
    _SR();
    _SE()
  end)

  -- Item Stacks comparator
  InitComparatorDD(condFrame.cond_item_stacks_comp, function(picked)
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions.item = d.conditions.item or {}
    d.conditions.item.stacksComp = picked
    _SR();
    _SE()
  end)

  -- editbox commit handlers (enter / focus lost)
  -- Ability CP value
  condFrame.cond_ability_cp_val:SetScript("OnEnterPressed", function()
    if not _CK() then
      return
    end
    local v = tonumber(this:GetText())
    if not v then
      local d = _EDB(_CK())
      this:SetText(tostring((d.conditions.ability and d.conditions.ability.cpVal) or 0))
      return
    end
    if v < 0 then
      v = 0
    end
    local d = _EDB(_CK())
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.cpVal = v
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
    if this.ClearFocus then
      this:ClearFocus()
    end
  end)
  do
    local _guard = false
    condFrame.cond_ability_cp_val:SetScript("OnEditFocusLost", function()
      if _guard then
        return
      end ;
      _guard = true
      this:GetScript("OnEnterPressed")()
      _guard = false
    end)
  end

  -- Aura CP value
  condFrame.cond_aura_cp_val:SetScript("OnEnterPressed", function()
    if not _CK() then
      return
    end
    local v = tonumber(this:GetText())
    if not v then
      local d = _EDB(_CK())
      this:SetText(tostring((d.conditions.aura and d.conditions.aura.cpVal) or 0))
      return
    end
    if v < 0 then
      v = 0
    end
    local d = _EDB(_CK())
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.cpVal = v
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
    if this.ClearFocus then
      this:ClearFocus()
    end
  end)
  do
    local _guard = false
    condFrame.cond_aura_cp_val:SetScript("OnEditFocusLost", function()
      if _guard then
        return
      end ;
      _guard = true
      this:GetScript("OnEnterPressed")()
      _guard = false
    end)
  end

  -- Ability HP value (%)
  condFrame.cond_ability_hp_val:SetScript("OnEnterPressed", function()
    if not _CK() then
      return
    end
    local v = tonumber(this:GetText())
    if not v then
      local d = _EDB(_CK())
      this:SetText(tostring((d.conditions.ability and d.conditions.ability.hpVal) or 0))
      return
    end
    if v < 0 then
      v = 0
    end
    if v > 100 then
      v = 100
    end
    local d = _EDB(_CK())
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.hpVal = v
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
    if this.ClearFocus then
      this:ClearFocus()
    end
  end)
  do
    local _guard = false
    condFrame.cond_ability_hp_val:SetScript("OnEditFocusLost", function()
      if _guard then
        return
      end ;
      _guard = true
      this:GetScript("OnEnterPressed")()
      _guard = false
    end)
  end

  -- Aura HP value (%)
  condFrame.cond_aura_hp_val:SetScript("OnEnterPressed", function()
    if not _CK() then
      return
    end
    local v = tonumber(this:GetText())
    if not v then
      local d = _EDB(_CK())
      this:SetText(tostring((d.conditions.aura and d.conditions.aura.hpVal) or 0))
      return
    end
    if v < 0 then
      v = 0
    end
    if v > 100 then
      v = 100
    end
    local d = _EDB(_CK())
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.hpVal = v
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
    if this.ClearFocus then
      this:ClearFocus()
    end
  end)
  do
    local _guard = false
    condFrame.cond_aura_hp_val:SetScript("OnEditFocusLost", function()
      if _guard then
        return
      end ;
      _guard = true
      this:GetScript("OnEnterPressed")()
      _guard = false
    end)
  end

  -- Aura Power value (%)
  condFrame.cond_aura_power_val:SetScript("OnEnterPressed", function()
    if not _CK() then
      return
    end
    local v = tonumber(this:GetText())
    if not v then
      local d = _EDB(_CK())
      this:SetText(tostring((d.conditions.aura and d.conditions.aura.powerVal) or 0))
      return
    end
    local d = _EDB(_CK())
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.powerVal = v
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
    if this.ClearFocus then
      this:ClearFocus()
    end
  end)
  do
    local _guard = false
    condFrame.cond_aura_power_val:SetScript("OnEditFocusLost", function()
      if _guard then
        return
      end ;
      _guard = true
      this:GetScript("OnEnterPressed")()
      _guard = false
    end)
  end

  condFrame.cond_ability_power_val:SetScript("OnEnterPressed", function()
    if not _CK() then
      return
    end
    local v = tonumber(this:GetText())
    local minv, maxv = -999999, 999999
    if not v then
      local d = _EDB(_CK())
      d.conditions = d.conditions or {}
      d.conditions.ability = d.conditions.ability or {}
      this:SetText(tostring(d.conditions.ability.powerVal or 0))
      return
    end
    if v < minv then
      v = minv
    end
    if v > maxv then
      v = maxv
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.powerVal = v
    _SR()
    _SE()
    UpdateCondFrameForKey(_CK())
    if this.ClearFocus then
      this:ClearFocus()
    end
  end)
  do
    local handling_power = false
    condFrame.cond_ability_power_val:SetScript("OnEditFocusLost", function()
      if handling_power then
        return
      end
      handling_power = true
      this:GetScript("OnEnterPressed")()
      handling_power = false
    end)
  end

  condFrame.cond_ability_remaining_val:SetScript("OnEnterPressed", function()
    if not _CK() then
      return
    end
    local v = tonumber(this:GetText())
    if not v then
      local d = _EDB(_CK())
      this:SetText(tostring((d.conditions and d.conditions.ability and d.conditions.ability.remainingVal) or 0))
      return
    end
    if v < 0 then
      v = 0
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.remainingVal = v
    _SR()
    _SE()
    UpdateCondFrameForKey(_CK())
    if this.ClearFocus then
      this:ClearFocus()
    end
  end)
  do
    local handling_ability_remaining = false
    condFrame.cond_ability_remaining_val:SetScript("OnEditFocusLost", function()
      if handling_ability_remaining then
        return
      end
      handling_ability_remaining = true
      this:GetScript("OnEnterPressed")()
      handling_ability_remaining = false
    end)
  end

  condFrame.cond_aura_remaining_val:SetScript("OnEnterPressed", function()
    if not _CK() then
      return
    end
    local v = tonumber(this:GetText())
    if not v then
      local d = _EDB(_CK())
      this:SetText(tostring((d.conditions and d.conditions.aura and d.conditions.aura.remainingVal) or 0))
      return
    end
    if v < 0 then
      v = 0
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.remainingVal = v
    _SR()
    _SE()
    UpdateCondFrameForKey(_CK())
    if this.ClearFocus then
      this:ClearFocus()
    end
  end)
  do
    local handling_aura_remaining = false
    condFrame.cond_aura_remaining_val:SetScript("OnEditFocusLost", function()
      if handling_aura_remaining then
        return
      end
      handling_aura_remaining = true
      this:GetScript("OnEnterPressed")()
      handling_aura_remaining = false
    end)
  end

  condFrame.cond_aura_stacks_val:SetScript("OnEnterPressed", function()
    if not _CK() then
      return
    end
    local v = tonumber(this:GetText())
    if not v then
      local d = _EDB(_CK())
      this:SetText(tostring((d.conditions and d.conditions.aura and d.conditions.aura.stacksVal) or 0))
      return
    end
    if v < 0 then
      v = 0
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.aura.stacksVal = v
    _SR()
    _SE()
    UpdateCondFrameForKey(_CK())
    if this.ClearFocus then
      this:ClearFocus()
    end
  end)
  do
    local handling_aura_stacks = false
    condFrame.cond_aura_stacks_val:SetScript("OnEditFocusLost", function()
      if handling_aura_stacks then
        return
      end
      handling_aura_stacks = true
      this:GetScript("OnEnterPressed")()
      handling_aura_stacks = false
    end)
  end

  -- Item CP value
  condFrame.cond_item_cp_val:SetScript("OnEnterPressed", function()
    if not _CK() then
      return
    end
    local v = tonumber(this:GetText())
    local d = _EDB(_CK())
    d.conditions.item = d.conditions.item or {}
    if not v then
      this:SetText(tostring(d.conditions.item.cpVal or 0))
      return
    end
    if v < 0 then
      v = 0
    end
    d.conditions.item.cpVal = v
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
    if this.ClearFocus then
      this:ClearFocus()
    end
  end)
  do
    local _g = false
    condFrame.cond_item_cp_val:SetScript("OnEditFocusLost", function()
      if _g then
        return
      end ;
      _g = true
      this:GetScript("OnEnterPressed")()
      _g = false
    end)
  end

  -- Item HP value (%)
  condFrame.cond_item_hp_val:SetScript("OnEnterPressed", function()
    if not _CK() then
      return
    end
    local v = tonumber(this:GetText())
    local d = _EDB(_CK())
    d.conditions.item = d.conditions.item or {}
    if not v then
      this:SetText(tostring(d.conditions.item.hpVal or 0))
      return
    end
    if v < 0 then
      v = 0
    end
    if v > 100 then
      v = 100
    end
    d.conditions.item.hpVal = v
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
    if this.ClearFocus then
      this:ClearFocus()
    end
  end)
  do
    local _g = false
    condFrame.cond_item_hp_val:SetScript("OnEditFocusLost", function()
      if _g then
        return
      end ;
      _g = true
      this:GetScript("OnEnterPressed")()
      _g = false
    end)
  end

  -- Item Power value
  condFrame.cond_item_power_val:SetScript("OnEnterPressed", function()
    if not _CK() then
      return
    end
    local v = tonumber(this:GetText())
    local d = _EDB(_CK())
    d.conditions.item = d.conditions.item or {}
    if not v then
      this:SetText(tostring(d.conditions.item.powerVal or 0))
      return
    end
    d.conditions.item.powerVal = v
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
    if this.ClearFocus then
      this:ClearFocus()
    end
  end)
  do
    local _g = false
    condFrame.cond_item_power_val:SetScript("OnEditFocusLost", function()
      if _g then
        return
      end ;
      _g = true
      this:GetScript("OnEnterPressed")()
      _g = false
    end)
  end

  -- Item Stacks value
  condFrame.cond_item_stacks_val:SetScript("OnEnterPressed", function()
    if not _CK() then
      return
    end
    local v = tonumber(this:GetText())
    local d = _EDB(_CK())
    d.conditions.item = d.conditions.item or {}
    if not v then
      this:SetText(tostring(d.conditions.item.stacksVal or 0))
      return
    end
    if v < 0 then
      v = 0
    end
    d.conditions.item.stacksVal = v
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
    if this.ClearFocus then
      this:ClearFocus()
    end
  end)
  do
    local _g = false
    condFrame.cond_item_stacks_val:SetScript("OnEditFocusLost", function()
      if _g then
        return
      end ;
      _g = true
      this:GetScript("OnEnterPressed")()
      _g = false
    end)
  end

  -- Item Remaining value (seconds)
  condFrame.cond_item_remaining_val:SetScript("OnEnterPressed", function()
    if not _CK() then
      return
    end
    local v = tonumber(this:GetText())
    local d = _EDB(_CK())
    d.conditions.item = d.conditions.item or {}
    if not v then
      this:SetText(tostring(d.conditions.item.remainingVal or 0))
      return
    end
    if v < 0 then
      v = 0
    end
    d.conditions.item.remainingVal = v
    _SR();
    _SE()
    UpdateCondFrameForKey(_CK())
    if this.ClearFocus then
      this:ClearFocus()
    end
  end)
  do
    local _g = false
    condFrame.cond_item_remaining_val:SetScript("OnEditFocusLost", function()
      if _g then
        return
      end ;
      _g = true
      this:GetScript("OnEnterPressed")()
      _g = false
    end)
  end

  -- Ability power toggle
  condFrame.cond_ability_power:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.powerEnabled = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK())
    _SR()
    _SE()
  end)

  -- Ability slider toggle
  condFrame.cond_ability_slider:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.slider = this:GetChecked() and true or false

    -- When the slider is turned off, drop the slide-window value
    -- and clear the edit box so it cannot linger in the DB.
    if not d.conditions.ability.slider then
      d.conditions.ability.sliderTime = nil
      if condFrame.cond_ability_slider_time then
        condFrame.cond_ability_slider_time:SetText("")
      end
    end

    if d.conditions.ability.slider and not d.conditions.ability.sliderDir then
      d.conditions.ability.sliderDir = "center"
    end
    UpdateCondFrameForKey(_CK())
    _SR()
    _SE()
  end)

  -- Slide window (seconds) edit box.
  --   empty / invalid -> no time limit (slide covers the whole cooldown)
  --   N > 0           -> slide only during the last N seconds of the cooldown
  local function SaveAbilitySliderTime()
    if not _CK() then
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.ability = d.conditions.ability or {}
    local box = condFrame.cond_ability_slider_time

    -- If the visible text is just the grey placeholder (the ability's
    -- full cooldown shown while the field is empty), do NOT persist it
    -- as a user-set sliderTime.
    if box._daIsPlaceholder then
      d.conditions.ability.sliderTime = nil
    else
      local txt = box:GetText() or ""
      -- Only accept digits (guard against stray "auto" left by mistake).
      if string.find(txt, "^%s*%d+%s*$") then
        local v = tonumber(txt)
        if v and v > 0 then
          local fullCD = _DA_GetAbilityCooldownDuration(d) or 180
          if v >= fullCD then
            d.conditions.ability.sliderTime = nil
          else
            d.conditions.ability.sliderTime = math.floor(v + 0.5)
          end
        else
          d.conditions.ability.sliderTime = nil
        end
      else
        d.conditions.ability.sliderTime = nil
      end
    end

    -- Re-render: field text/colour and slider position.
    _DA_SetSliderTimeDisplay(box, d.conditions.ability.sliderTime, d)
    if condFrame.cond_ability_slider_time_slider then
      local fullCD = _DA_GetAbilityCooldownDuration(d) or 180
      local v = tonumber(d.conditions.ability.sliderTime) or fullCD
      if v < 1 then v = 1 end
      if v > fullCD then v = fullCD end
      condFrame.cond_ability_slider_time_slider._isSyncing = true
      condFrame.cond_ability_slider_time_slider:SetValue(v)
      condFrame.cond_ability_slider_time_slider._isSyncing = false
    end

    _SR()
    _SE()
  end

  condFrame.cond_ability_slider_time:SetScript("OnEnterPressed", function()
    SaveAbilitySliderTime()
    if this and this.ClearFocus then
      this:ClearFocus()
    end
  end)
  condFrame.cond_ability_slider_time:SetScript("OnEditFocusLost", function()
    SaveAbilitySliderTime()
    -- Re-render: either the saved user value (gold) or the grey placeholder.
    if _CK() then
      local cur = DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[_CK()]
      local sv  = cur and cur.conditions and cur.conditions.ability and cur.conditions.ability.sliderTime
      _DA_SetSliderTimeDisplay(this, sv, cur)
    end
  end)
  condFrame.cond_ability_slider_time:SetScript("OnEscapePressed", function()
    if this and this.ClearFocus then
      this:ClearFocus()
    end
  end)

  -- Ability remaining toggle
  condFrame.cond_ability_remaining_cb:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.remainingEnabled = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK())
    _SR()
    _SE()
  end)

  -- Ability glow/greyscale (separate checkboxes)
  condFrame.cond_ability_glow:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.glow = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK())
    _SR()
    _SE()
  end)
  condFrame.cond_ability_greyscale:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.greyscale = this:GetChecked() and true or false
    UpdateCondFrameForKey(_CK())
    _SR()
    _SE()
  end)
  condFrame.cond_ability_fade:SetScript("OnClick", function()
    if not _CK() then
      this:SetChecked(false)
      return
    end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.fade = this:GetChecked() and true or false
    if d.conditions.ability.fade and not d.conditions.ability.fadeAlpha then
      d.conditions.ability.fadeAlpha = 0
    end
    UpdateCondFrameForKey(_CK())
    _SR()
    _SE()
  end)

  local function SaveAbilityFadeAlpha()
    if not _CK() then return end
    local d = _EDB(_CK())
    d.conditions = d.conditions or {}
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.ability.fadeAlpha = _ParseFadeAlphaFromBox(condFrame.cond_ability_fade_slider)
    _NormalizeFadeBox(condFrame.cond_ability_fade_slider, d.conditions.ability.fadeAlpha)
    _SR()
    _SE()
  end
  condFrame.cond_ability_fade_slider:SetScript("OnEnterPressed", function() SaveAbilityFadeAlpha(); this:ClearFocus() end)
  condFrame.cond_ability_fade_slider:SetScript("OnEditFocusLost", SaveAbilityFadeAlpha)
  condFrame.cond_ability_fade_slider:SetScript("OnEscapePressed", function() this:ClearFocus() end)

  -- Form dropdowns are initialized/updated from UpdateConditionsUI
  condFrame.cond_ability_formDD:Hide()
  condFrame.cond_aura_formDD:Hide()
  condFrame.cond_item_formDD:Hide()
  _CD(condFrame.cond_ability_formDD)
  _CD(condFrame.cond_aura_formDD)
  _CD(condFrame.cond_item_formDD)

  -- hide all controls by default
  condFrame.cond_ability_usable:Hide()
  condFrame.cond_ability_notcd:Hide()
  condFrame.cond_ability_oncd:Hide()
  condFrame.cond_ability_incombat:Hide()
  condFrame.cond_ability_outcombat:Hide()
  condFrame.cond_ability_target_help:Hide()
  condFrame.cond_ability_target_harm:Hide()
  condFrame.cond_ability_target_self:Hide()
  condFrame.cond_ability_power:Hide()
  condFrame.cond_ability_power_comp:Hide()
  condFrame.cond_ability_power_val:Hide()
  condFrame.cond_ability_power_val_enter:Hide()
  condFrame.cond_ability_glow:Hide()
  condFrame.cond_ability_slider:Hide()
  condFrame.cond_ability_slider_dir:Hide()
  condFrame.cond_ability_remaining_cb:Hide()
  condFrame.cond_ability_remaining_comp:Hide()
  condFrame.cond_ability_remaining_val:Hide()
  condFrame.cond_ability_remaining_val_enter:Hide()
  condFrame.cond_ability_greyscale:Hide()
  condFrame.cond_ability_fade:Hide()
  condFrame.cond_ability_fade_slider:Hide()
  condFrame.cond_ability_cp_cb:Hide()
  condFrame.cond_ability_cp_comp:Hide()
  condFrame.cond_ability_cp_val:Hide()
  condFrame.cond_ability_cp_val_enter:Hide()
  condFrame.cond_ability_hp_my:Hide()
  condFrame.cond_ability_hp_tgt:Hide()
  condFrame.cond_ability_hp_comp:Hide()
  condFrame.cond_ability_hp_val:Hide()
  condFrame.cond_ability_hp_val_enter:Hide()
  condFrame.cond_ability_slider_glow:Hide()
  condFrame.cond_ability_slider_grey:Hide()
  if condFrame.cond_ability_slider_effect then
    condFrame.cond_ability_slider_effect:Hide()
  end
  condFrame.cond_ability_text_time:Hide()
  condFrame.cond_ability_slider_time:Hide()
  condFrame.cond_ability_slider_time_label:Hide()
  if condFrame.cond_ability_slider_time_slider then
    condFrame.cond_ability_slider_time_slider:Hide()
  end
  if condFrame.cond_ability_slider_time_hintline then
    condFrame.cond_ability_slider_time_hintline:Hide()
  end
  if condFrame.cond_ability_slider_fading_cb then
    condFrame.cond_ability_slider_fading_cb:Hide()
  end
  if condFrame.cond_ability_weaponDD then
    condFrame.cond_ability_weaponDD:Hide()
  end

  if condFrame.cond_ability_distanceDD then
    condFrame.cond_ability_distanceDD:Hide()
  end
  if condFrame.cond_ability_unitTypeDD then
    condFrame.cond_ability_unitTypeDD:Hide()
  end

  if condFrame.cond_aura_distanceDD then
    condFrame.cond_aura_distanceDD:Hide()
  end
  if condFrame.cond_aura_unitTypeDD then
    condFrame.cond_aura_unitTypeDD:Hide()
  end

  condFrame.cond_aura_cp_cb:Hide()
  condFrame.cond_aura_cp_comp:Hide()
  condFrame.cond_aura_cp_val:Hide()
  condFrame.cond_aura_cp_val_enter:Hide()
  condFrame.cond_aura_hp_my:Hide()
  condFrame.cond_aura_hp_tgt:Hide()
  condFrame.cond_aura_hp_comp:Hide()
  condFrame.cond_aura_hp_val:Hide()
  condFrame.cond_aura_hp_val_enter:Hide()
  condFrame.cond_aura_text_time:Hide()
  condFrame.cond_aura_text_stack:Hide()
  condFrame.cond_aura_power:Hide()
  condFrame.cond_aura_power_comp:Hide()
  condFrame.cond_aura_power_val:Hide()
  condFrame.cond_aura_power_val_enter:Hide()
  condFrame.cond_aura_found:Hide()
  condFrame.cond_aura_missing:Hide()
  condFrame.cond_aura_incombat:Hide()
  condFrame.cond_aura_outcombat:Hide()
  condFrame.cond_aura_target_help:Hide()
  condFrame.cond_aura_target_harm:Hide()
  condFrame.cond_aura_onself:Hide()
  condFrame.cond_aura_glow:Hide()
  condFrame.cond_aura_remaining_cb:Hide()
  condFrame.cond_aura_remaining_comp:Hide()
  condFrame.cond_aura_remaining_val:Hide()
  condFrame.cond_aura_remaining_val_enter:Hide()
  condFrame.cond_aura_stacks_cb:Hide()
  condFrame.cond_aura_stacks_comp:Hide()
  condFrame.cond_aura_stacks_val:Hide()
  condFrame.cond_aura_stacks_val_enter:Hide()
  condFrame.cond_aura_greyscale:Hide()
  condFrame.cond_aura_fade:Hide()
  condFrame.cond_aura_fade_slider:Hide()
  condFrame.cond_aura_mine:Hide()
  if condFrame.cond_aura_trackpet then
    condFrame.cond_aura_trackpet:Hide()
  end
  if condFrame.cond_aura_others then
    condFrame.cond_aura_others:Hide()
  end
  if condFrame.cond_aura_owner_tip then
    condFrame.cond_aura_owner_tip:Hide()
  end
  if condFrame.cond_aura_distanceDD then
    condFrame.cond_aura_distanceDD:Hide()
  end
  if condFrame.cond_aura_unitTypeDD then
    condFrame.cond_aura_unitTypeDD:Hide()
  end
  if condFrame.cond_aura_weaponDD then
    condFrame.cond_aura_weaponDD:Hide()
  end

  condFrame.cond_item_where_equipped:Hide()
  condFrame.cond_item_where_bag:Hide()
  condFrame.cond_item_where_missing:Hide()
  condFrame.cond_item_notcd:Hide()
  condFrame.cond_item_oncd:Hide()
  if condFrame.cond_item_enchant then
    condFrame.cond_item_enchant:Hide()
  end
  if condFrame.cond_item_text_enchant then
    condFrame.cond_item_text_enchant:Hide()
  end
  condFrame.cond_item_incombat:Hide()
  condFrame.cond_item_outcombat:Hide()
  condFrame.cond_item_target_help:Hide()
  condFrame.cond_item_target_harm:Hide()
  condFrame.cond_item_target_self:Hide()
  condFrame.cond_item_glow:Hide()
  condFrame.cond_item_greyscale:Hide()
  condFrame.cond_item_fade:Hide()
  condFrame.cond_item_fade_slider:Hide()
  condFrame.cond_item_text_time:Hide()
  condFrame.cond_item_power:Hide()
  condFrame.cond_item_power_comp:Hide()
  condFrame.cond_item_power_val:Hide()
  condFrame.cond_item_power_val_enter:Hide()
  condFrame.cond_item_stacks_cb:Hide()
  condFrame.cond_item_stacks_comp:Hide()
  condFrame.cond_item_stacks_val:Hide()
  condFrame.cond_item_stacks_val_enter:Hide()
  condFrame.cond_item_text_stack:Hide()
  condFrame.cond_item_hp_my:Hide()
  condFrame.cond_item_hp_tgt:Hide()
  condFrame.cond_item_hp_comp:Hide()
  condFrame.cond_item_hp_val:Hide()
  condFrame.cond_item_hp_val_enter:Hide()
  condFrame.cond_item_remaining_cb:Hide()
  condFrame.cond_item_remaining_comp:Hide()
  condFrame.cond_item_remaining_val:Hide()
  condFrame.cond_item_remaining_val_enter:Hide()
  condFrame.cond_item_cp_cb:Hide()
  condFrame.cond_item_cp_comp:Hide()
  condFrame.cond_item_cp_val:Hide()
  condFrame.cond_item_cp_val_enter:Hide()
  if condFrame.cond_item_weaponDD then
    condFrame.cond_item_weaponDD:Hide()
  end
  condFrame.cond_item_inv_trinket1:Hide()
  condFrame.cond_item_inv_trinket2:Hide()
  condFrame.cond_item_inv_trinket_first:Hide()
  condFrame.cond_item_inv_trinket_both:Hide()
  condFrame.cond_item_inv_wep_mainhand:Hide()
  condFrame.cond_item_inv_wep_offhand:Hide()
  condFrame.cond_item_inv_wep_ranged:Hide()
  if condFrame.cond_item_inv_wep_ammo then
    condFrame.cond_item_inv_wep_ammo:Hide()
  end
  if condFrame.cond_item_class_note then
    condFrame.cond_item_class_note:Hide()
  end
  -- Register the three per-type Aura Conditions managers
  -- (AuraCond_RegisterManager now lives in Modules/DoiteEditAuraCond.lua).
  local _acRM = _G["AuraCond_RegisterManager"]
  if _acRM then
    if condFrame.abilityAuraAnchor then
      _acRM("ability", condFrame.abilityAuraAnchor)
    end
    if condFrame.auraAuraAnchor then
      _acRM("aura", condFrame.auraAuraAnchor)
    end
    if condFrame.itemAuraAnchor then
      _acRM("item", condFrame.itemAuraAnchor)
    end
  end

  -- Register the three per-type Visual Effects Conditions managers
  -- (VfxCond_RegisterManager now lives in Modules/DoiteEditAuraCond.lua).
  local _vcRM = _G["VfxCond_RegisterManager"]
  if _vcRM then
    if condFrame.abilityVfxAnchor then
      _vcRM("ability", condFrame.abilityVfxAnchor)
    end
    if condFrame.auraVfxAnchor then
      _vcRM("aura", condFrame.auraVfxAnchor)
    end
    if condFrame.itemVfxAnchor then
      _vcRM("item", condFrame.itemVfxAnchor)
    end
  end

  -- start hidden; visibility controlled from UpdateConditionsUI
  if condFrame.abilityAuraAnchor then
    condFrame.abilityAuraAnchor:Hide()
  end
  if condFrame.auraAuraAnchor then
    condFrame.auraAuraAnchor:Hide()
  end
  if condFrame.itemAuraAnchor then
    condFrame.itemAuraAnchor:Hide()
  end
  if condFrame.abilityVfxAnchor then
    condFrame.abilityVfxAnchor:Hide()
  end
  if condFrame.auraVfxAnchor then
    condFrame.auraVfxAnchor:Hide()
  end
  if condFrame.itemVfxAnchor then
    condFrame.itemVfxAnchor:Hide()
  end

  -- Make sure the AND/OR logic popup and buttons vanish when the edit frame is closed
  if condFrame and not condFrame._logicHideHooked then
    condFrame._logicHideHooked = true
    local oldOnHide = condFrame:GetScript("OnHide")

    condFrame:SetScript("OnHide", function()
      -- Close the AND/OR / () popup if it is open
      if DoiteAuraLogicFrame and DoiteAuraLogicFrame:IsShown() then
        DoiteAuraLogicFrame:Hide()
      end

      -- Hide all per-type logic buttons as well
      local _am = _G["AuraCond_Managers"]
      if _am then
        for _, mgr in pairs(_am) do
          if mgr.logicButton then
            mgr.logicButton:Hide()
          end
        end
      end

      if oldOnHide then
        oldOnHide()
      end
    end)
  end
end

-- DoiteEdit_SetSeparator / DoiteEdit_ShowSeparatorsForType /
-- DoiteEdit_AuraOwner_UpdateDependentChecks are installed as globals
-- inside CreateConditionsUI. Do not re-export them here: assigning a
-- local forwarder wrapper to the same key makes the global recursive.

_G["DoiteEdit_CreateConditionsUI"] = CreateConditionsUI