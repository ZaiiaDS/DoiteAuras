---------------------------------------------------------------
-- DoiteEditUIUpdate.lua
-- Post-edit UI refresh pipeline:
--   _ReflowCondAreaHeight   - recompute scroll content height
--   UpdateConditionsUI      - render current icon's condition sections
--   UpdateCondFrameForKey   - entry point; called when Edit changes key
-- Extracted from DoiteEdit.lua (Phase 9 of the split).
--
-- Loaded AFTER DoiteEdit.lua and DoiteEditUIBuild.lua.
-- Uses DoiteEditCtx for state + helpers, and _G["DoiteEdit_*"] for
-- the functions exposed by DoiteEditUIBuild.lua.
---------------------------------------------------------------

local ctx = _G["DoiteEditCtx"]
if not ctx then return end

-- Frame state is resolved through ctx accessors at call time; we do not
-- keep local mirrors of the editor state in this module.
local function _CF() return ctx.getCondFrame() end
local function _CK() return ctx.getCurrentKey() end

-- Core helpers (through ctx)
local function _EDB(k)     return ctx.EnsureDBEntry(k) end
local function _SR()        ctx.SafeRefresh()          end
local function _SE()        ctx.SafeEvaluate()         end
local function _CD(dd)     return ctx.ClearDropdown(dd) end
local function _Reflow()    ctx.ReflowCondAreaHeight()  end

-- Global helpers from DoiteEditHelpers.lua
local DoiteEdit_EnableCheck               = _G["DoiteEdit_EnableCheck"]
local DoiteEdit_DisableCheck              = _G["DoiteEdit_DisableCheck"]
local DoiteEdit_SetDropdownInteractive    = _G["DoiteEdit_SetDropdownInteractive"]
local DoiteEdit_YellowifyButton           = _G["DoiteEdit_YellowifyButton"]
local StylePlainEditBox                   = _G["DoiteEdit_StylePlainEditBox"]
local _GoldifyDD                          = _G["_GoldifyDD"]
local _GreyifyDD                          = _G["_GreyifyDD"]
local _WhiteifyDDText                     = _G["_WhiteifyDDText"]
local _IsRogueOrDruid                     = _G["DoiteEdit_IsRogueOrDruid"]
local _IsHunterOrWarlock                  = _G["DoiteEdit_IsHunterOrWarlock"]
local DoiteEdit_AbilitySupportsProcSound  = _G["DoiteEdit_AbilitySupportsProcSound"]
local _DeriveGroupingMode                 = _G["DoiteEdit_DeriveGroupingMode"]
local DEFAULT_CUSTOM_FUNCTION_SOURCE      = _G["DOITE_DEFAULT_CUSTOM_FUNCTION_SOURCE"]

-- Lazy proxies for helpers that live in DoiteEdit.lua
local function DoiteEdit_AnnounceEditingIcon(name)
  if ctx.AnnounceEditingIcon then return ctx.AnnounceEditingIcon(name) end
end
local function DoiteEdit_SetSoundEnabled(a, b, c)
  if ctx.SetSoundEnabled then return ctx.SetSoundEnabled(a, b, c) end
end
local function DoiteEdit_InitSoundDropdown(a, b, c, d)
  if ctx.InitSoundDropdown then return ctx.InitSoundDropdown(a, b, c, d) end
end
local function InitFormDropdown(dd, data, condType)
  if ctx.InitFormDropdown then return ctx.InitFormDropdown(dd, data, condType) end
end
local function InitWeaponDropdown(dd, data, condType)
  if ctx.InitWeaponDropdown then return ctx.InitWeaponDropdown(dd, data, condType) end
end
local function _DA_GetAbilityCooldownDuration(data)
  local f = _G["DoiteEdit_GetAbilityCooldownDuration"]
  if f then return f(data) end
end
local function _DA_SetSliderTimeDisplay(box, v, data)
  local f = _G["DoiteEdit_SetSliderTimeDisplay"]
  if f then return f(box, v, data) end
end
local function _SetDDEnabled(dd, enabled, ph)
  if ctx.SetDDEnabled then return ctx.SetDDEnabled(dd, enabled, ph) end
end
local function _DA_ApplySliderRanges()
  if ctx.ApplySliderRanges then return ctx.ApplySliderRanges() end
end
local function _EditFontLabelForValue(v)
  return _G["DoiteEdit_FontLabelForValue"](v)
end
local function _EditFlagLabelForValue(v)
  return _G["DoiteEdit_FlagLabelForValue"](v)
end
local function AuraOwner_UpdateDependentChecks()
  local f = _G["DoiteEdit_AuraOwner_UpdateDependentChecks"]
  if f then return f() end
end

local function SetSeparator(...)
  local f = _G["DoiteEdit_SetSeparator"]
  if f then return f(...) end
end
local function ShowSeparatorsForType(...)
  local f = _G["DoiteEdit_ShowSeparatorsForType"]
  if f then return f(...) end
end

-- Per-check enable/disable with gold/grey label colour.
local function _SetAuraCheckEnabled(cb, enabled, clearWhenDisabling)
  if not cb then return end
  if enabled then
    if cb.Enable then cb:Enable() end
    if cb.text and cb.text.SetTextColor then cb.text:SetTextColor(1, 0.82, 0) end
  else
    if clearWhenDisabling and cb.SetChecked then cb:SetChecked(false) end
    if cb.Disable then cb:Disable() end
    if cb.text and cb.text.SetTextColor then cb.text:SetTextColor(0.6, 0.6, 0.6) end
  end
end

-- Dynamically resize the scroll/content area to fit the last visible row (+20px buffer) + Dynamically resize the scroll/content area AND reposition VFX sections
local function _ReflowCondAreaHeight()
  local condFrame = _CF()
  if not condFrame then
    return
  end
  local SLIDING_EXTRA = condFrame._slidingExtra or 0

  local parent = condFrame._condArea or condFrame.condArea or condFrame
  if not parent then
    return
  end

  if condFrame.abilityAuraAnchor and condFrame.abilityAuraAnchor:IsShown() then
    local visHeight = condFrame.abilityAuraAnchor:GetHeight() or 20
    
    local ROW14_Y = -585 - SLIDING_EXTRA
    local ROW15_Y = -640 - SLIDING_EXTRA
    
    local expansion = visHeight - 20
    if expansion < 0 then expansion = 0 end
    
    local newVfxY = ROW15_Y - expansion
    
    -- Move the separator
    if condFrame._seps and condFrame._seps.ability and condFrame._seps.ability[15] then
      local sep = condFrame._seps.ability[15]
      sep:ClearAllPoints()
      sep:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, newVfxY)
      sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, newVfxY)
    end
    
    -- Move the VFX anchor
    if condFrame.abilityVfxAnchor then
      condFrame.abilityVfxAnchor:ClearAllPoints()
      condFrame.abilityVfxAnchor:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, newVfxY)
      condFrame.abilityVfxAnchor:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, newVfxY)
    end
  end

  -- 2. Reflow Aura Section
  -- Aura Visibility base is (row16_y) = -630
  -- Aura VFX base is (row17_y) = -670
  if condFrame.auraAuraAnchor and condFrame.auraAuraAnchor:IsShown() then
    local visHeight = condFrame.auraAuraAnchor:GetHeight() or 20
    local AURA_VIS_Y = -665 - SLIDING_EXTRA
    local AURA_VFX_Y = -705 - SLIDING_EXTRA
    
    local expansion = visHeight - 20
    if expansion < 0 then expansion = 0 end
    
    local newVfxY = AURA_VFX_Y - expansion
    if condFrame._seps and condFrame._seps.aura and condFrame._seps.aura[17] then
      local sep = condFrame._seps.aura[17]
      sep:ClearAllPoints()
      sep:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, newVfxY)
      sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, newVfxY)
    end
    if condFrame.auraVfxAnchor then
      condFrame.auraVfxAnchor:ClearAllPoints()
      condFrame.auraVfxAnchor:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, newVfxY)
      condFrame.auraVfxAnchor:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, newVfxY)
    end
  end

  -- 3. Reflow Item Section
  -- Item Visibility base is row17_y = -550
  -- Item VFX base is row18_y = -590
  if condFrame.itemAuraAnchor and condFrame.itemAuraAnchor:IsShown() then
    local visHeight = condFrame.itemAuraAnchor:GetHeight() or 20
    local ITEM_VIS_Y = -705 - SLIDING_EXTRA
    local ITEM_VFX_Y = -745 - SLIDING_EXTRA
    
    local expansion = visHeight - 20
    if expansion < 0 then expansion = 0 end
    
    local newVfxY = ITEM_VFX_Y - expansion
    
    if condFrame._seps and condFrame._seps.item and condFrame._seps.item[18] then
      local sep = condFrame._seps.item[18]
      sep:ClearAllPoints()
      sep:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, newVfxY)
      sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, newVfxY)
    end
    if condFrame.itemVfxAnchor then
      condFrame.itemVfxAnchor:ClearAllPoints()
      condFrame.itemVfxAnchor:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, newVfxY)
      condFrame.itemVfxAnchor:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, newVfxY)
    end
  end


  -- Now calculate total height based on new positions
  if not parent.GetChildren then
    return
  end

  -- Reusable buffer (избегаем аллокации на каждый вызов).
  -- Храним в _G, потому что _ReflowCondAreaHeight — функция (на неё нельзя вешать поля).
  local children = _G["DoiteEdit_ReflowChildrenBuf"]
  if not children then
    children = {}
    _G["DoiteEdit_ReflowChildrenBuf"] = children
  end
  local oldN = table.getn(children)
  local nChild = 0
  local idx = 1
  while true do
    local c = select(idx, parent:GetChildren())
    if not c then break end
    nChild = nChild + 1
    children[nChild] = c
    idx = idx + 1
  end
  for j = nChild + 1, oldN do
    children[j] = nil
  end

  local minBottom = nil
  local i = 1
  while children[i] do
    local f = children[i]
    if f and f.IsShown and f:IsShown() and f.GetPoint and f.GetHeight then
      local _, _, _, _, y = f:GetPoint(1)
      if y then
        local h = f:GetHeight() or 0
        local bottom = y - h
        if not minBottom or bottom < minBottom then
          minBottom = bottom
        end
      end
    end
    i = i + 1
  end

  if not minBottom then
    return
  end

  local height = -minBottom + 20
  if height < 200 then
    height = 200
  end

  parent:SetHeight(height)

  local sf = condFrame._scrollFrame or condFrame.scrollFrame
  if sf then
    if sf.SetScrollChild then
      sf:SetScrollChild(parent)
    end
    if sf.UpdateScrollChildRect then
      sf:UpdateScrollChildRect()
    end
  end
end

-- Update conditions UI to reflect DB for the currentKey/data
local function UpdateConditionsUI(data)
  local condFrame = _CF()
  if not condFrame then
    return
  end
  if not data then
    return
  end
  if not data.conditions then
    data.conditions = {}
  end

  -- Always announce in chat when entering edit for this icon
  local dn = data.displayName
  if not dn or dn == "" then
    dn = _CK()
  end
  DoiteEdit_AnnounceEditingIcon(dn)

  local c = data.conditions

  local function _HideSoundControls()
    local list = {
      condFrame.cond_ability_sound_oncd_cb, condFrame.cond_ability_sound_oncd_dd,
      condFrame.cond_ability_sound_offcd_cb, condFrame.cond_ability_sound_offcd_dd,
      condFrame.cond_ability_sound_onproc_cb, condFrame.cond_ability_sound_onproc_dd,
      condFrame.cond_aura_sound_ongain_cb, condFrame.cond_aura_sound_ongain_dd,
      condFrame.cond_aura_sound_onfade_cb, condFrame.cond_aura_sound_onfade_dd,
      condFrame.cond_item_sound_oncd_cb, condFrame.cond_item_sound_oncd_dd,
      condFrame.cond_item_sound_offcd_cb, condFrame.cond_item_sound_offcd_dd,
    }
    local i
    for i = 1, table.getn(list) do
      if list[i] and list[i].Hide then
        list[i]:Hide()
      end
    end
  end
  _HideSoundControls()

  -- Hide the slider Effect dropdown by default; it is re-shown only for
  -- Ability icons with "Soon off CD" enabled (see the Ability branch
  -- below). Doing it here keeps Item/Aura/Custom branches from having to
  -- know about the widget.
  if condFrame.cond_ability_slider_effect then
    condFrame.cond_ability_slider_effect:Hide()
  end
  if condFrame.cond_ability_slider_effect_label then
    condFrame.cond_ability_slider_effect_label:Hide()
  end

  -- Reset fade controls upfront to prevent visual leakage between icon categories.
  if condFrame.cond_ability_fade then condFrame.cond_ability_fade:Hide() end
  if condFrame.cond_ability_fade_slider then condFrame.cond_ability_fade_slider:Hide() end
  if condFrame.cond_aura_fade then condFrame.cond_aura_fade:Hide() end
  if condFrame.cond_aura_fade_slider then condFrame.cond_aura_fade_slider:Hide() end
  if condFrame.cond_item_fade then condFrame.cond_item_fade:Hide() end
  if condFrame.cond_item_fade_slider then condFrame.cond_item_fade_slider:Hide() end

  -- Custom controls are hidden by default; shown only for Custom type.
  if condFrame.cond_custom_function_edit then
    condFrame.cond_custom_function_edit:Hide()
  end
  if condFrame.cond_custom_function_save then
    condFrame.cond_custom_function_save:Hide()
  end
  if condFrame.cond_custom_function_status then
    condFrame.cond_custom_function_status:Hide()
    condFrame.cond_custom_function_status:SetText("")
  end

  local function _IsWarriorPaladinShaman()
    local _, cls = UnitClass("player")
    cls = cls and string.upper(cls) or ""
    return (cls == "WARRIOR" or cls == "PALADIN" or cls == "SHAMAN")
  end


  -- ABILITY
  if data.type == "Ability" then
    -- show rows
    if ShowSeparatorsForType then ShowSeparatorsForType("ability") end
    -- ensure aura-only tip is hidden when not editing an aura
    if condFrame.cond_aura_tip then
      condFrame.cond_aura_tip:Hide()
    end
    local _acRef = _G["AuraCond_RefreshFromDB"]
    if _acRef then
      _acRef("ability")
    end
    local _vcRef = _G["VfxCond_RefreshFromDB"]
    if _vcRef then
      _vcRef("ability")
    end

    condFrame.cond_ability_usable:Show()
    condFrame.cond_ability_notcd:Show()
    condFrame.cond_ability_oncd:Show()
    condFrame.cond_ability_incombat:Show()
    condFrame.cond_ability_outcombat:Show()
    if condFrame.cond_ability_groupingDD then
      condFrame.cond_ability_groupingDD:Show()
    end
    condFrame.cond_ability_target_help:Show()
    condFrame.cond_ability_target_harm:Show()
    condFrame.cond_ability_target_self:Show()
    condFrame.cond_ability_sound_oncd_cb:Show()
    condFrame.cond_ability_sound_oncd_dd:Show()
    condFrame.cond_ability_sound_offcd_cb:Show()
    condFrame.cond_ability_sound_offcd_dd:Show()
    condFrame.cond_ability_sound_onproc_cb:Show()
    condFrame.cond_ability_sound_onproc_dd:Show()
    condFrame.cond_ability_power:Show()
    condFrame.cond_ability_glow:Show()
    condFrame.cond_ability_greyscale:Show()
    condFrame.cond_ability_fade:Show()
    condFrame.cond_ability_slider:Show()
    condFrame.cond_ability_remaining_cb:Show()

    -- exclusives
    local mode = (c.ability and c.ability.mode) or nil
    condFrame.cond_ability_usable:SetChecked(mode == "usable" or mode == "usableoncd")
    condFrame.cond_ability_notcd:SetChecked(mode == "notcd" or mode == "nocdoncd")
    condFrame.cond_ability_oncd:SetChecked(mode == "oncd" or mode == "usableoncd" or mode == "nocdoncd")

    -- combat -> now independent booleans, with fallback to legacy string 'combat'
    local inC, outC
    if c.ability and (c.ability.inCombat ~= nil or c.ability.outCombat ~= nil) then
      inC = c.ability.inCombat and true or false
      outC = c.ability.outCombat and true or false
    else
      -- legacy handling
      local cm = c.ability and c.ability.combat or nil
      if cm == "in" then
        inC, outC = true, false
      elseif cm == "out" then
        inC, outC = false, true
      else
        inC, outC = true, true -- default both
      end
    end
    condFrame.cond_ability_incombat:SetChecked(inC)
    condFrame.cond_ability_outcombat:SetChecked(outC)

    if condFrame.cond_ability_groupingDD then
      local gm = _DeriveGroupingMode(c.ability)
      local txt
      if gm == "any" then
        txt = "Any"
      elseif gm == "nogroup" then
        txt = "Not in group"
      elseif gm == "party" then
        txt = "In party"
      elseif gm == "raid" then
        txt = "In raid"
      elseif gm == "partyraid" then
        txt = "In party or raid"
      else
        txt = "Group state"
      end

      if gm == nil then
        if UIDropDownMenu_SetSelectedValue then pcall(UIDropDownMenu_SetSelectedValue, condFrame.cond_ability_groupingDD, "__default") end
      else
        if UIDropDownMenu_SetSelectedValue then pcall(UIDropDownMenu_SetSelectedValue, condFrame.cond_ability_groupingDD, gm) end
      end
      if UIDropDownMenu_SetText then pcall(UIDropDownMenu_SetText, txt, condFrame.cond_ability_groupingDD) end
      if _GoldifyDD then _GoldifyDD(condFrame.cond_ability_groupingDD) end
    end

    -- multi-select booleans
    local ah = (c.ability and c.ability.targetHelp) == true
    local ar = (c.ability and c.ability.targetHarm) == true
    local as = (c.ability and c.ability.targetSelf) == true
    condFrame.cond_ability_target_help:SetChecked(ah)
    condFrame.cond_ability_target_harm:SetChecked(ar)
    condFrame.cond_ability_target_self:SetChecked(as)

    -- TARGET STATUS (ability): mutually exclusive, but both can be off
    local ta = (c.ability and c.ability.targetAlive) == true
    local td = (c.ability and c.ability.targetDead) == true

    if condFrame.cond_ability_target_alive then
      condFrame.cond_ability_target_alive:SetChecked(ta)
      condFrame.cond_ability_target_alive:Show()
    end
    if condFrame.cond_ability_target_dead then
      condFrame.cond_ability_target_dead:SetChecked(td)
      condFrame.cond_ability_target_dead:Show()
    end

    local aSoundOn = (c.ability and c.ability.soundOnCDEnabled) == true
    local aSoundOff = (c.ability and c.ability.soundOffCDEnabled) == true
    local aSoundProc = (c.ability and c.ability.soundOnProcEnabled) == true
    local aOnCds = (c.ability and c.ability.soundOnCD) or nil
    local aOffCds = (c.ability and c.ability.soundOffCD) or nil
    local aProcSnd = (c.ability and c.ability.soundOnProc) or nil
    local canUseProcSound = DoiteEdit_AbilitySupportsProcSound(data)
    condFrame.cond_ability_sound_oncd_cb:SetChecked(aSoundOn)
    condFrame.cond_ability_sound_offcd_cb:SetChecked(aSoundOff)
    condFrame.cond_ability_sound_onproc_cb:SetChecked(aSoundProc)
    DoiteEdit_InitSoundDropdown(condFrame.cond_ability_sound_oncd_dd, "ability", "soundOnCD", aOnCds)
    DoiteEdit_InitSoundDropdown(condFrame.cond_ability_sound_offcd_dd, "ability", "soundOffCD", aOffCds)
    DoiteEdit_InitSoundDropdown(condFrame.cond_ability_sound_onproc_dd, "ability", "soundOnProc", aProcSnd)
    DoiteEdit_EnableCheck(condFrame.cond_ability_sound_oncd_cb)
    DoiteEdit_EnableCheck(condFrame.cond_ability_sound_offcd_cb)
    if aSoundOn then
      DoiteEdit_EnableCheck(condFrame.cond_ability_sound_oncd_cb)
      DoiteEdit_SetDropdownInteractive(condFrame.cond_ability_sound_oncd_dd, true)
    else
      DoiteEdit_SetDropdownInteractive(condFrame.cond_ability_sound_oncd_dd, false)
    end
    if aSoundOff then
      DoiteEdit_SetDropdownInteractive(condFrame.cond_ability_sound_offcd_dd, true)
    else
      DoiteEdit_SetDropdownInteractive(condFrame.cond_ability_sound_offcd_dd, false)
    end
    if canUseProcSound then
      DoiteEdit_EnableCheck(condFrame.cond_ability_sound_onproc_cb)
      if aSoundProc then
        DoiteEdit_SetDropdownInteractive(condFrame.cond_ability_sound_onproc_dd, true)
      else
        DoiteEdit_SetDropdownInteractive(condFrame.cond_ability_sound_onproc_dd, false)
      end
    else
      condFrame.cond_ability_sound_onproc_cb:SetChecked(false)
      DoiteEdit_DisableCheck(condFrame.cond_ability_sound_onproc_cb)
      DoiteEdit_SetDropdownInteractive(condFrame.cond_ability_sound_onproc_dd, false)
      if c.ability then
        c.ability.soundOnProcEnabled = false
      end
    end

    -- === TARGET DISTANCE & TYPE (Ability) ===
    if condFrame.cond_ability_distanceDD then
      condFrame.cond_ability_distanceDD:Show()
      condFrame.cond_ability_unitTypeDD:Show()

      local a = c.ability or {}

      local function _RestoreDD(dd, val, placeholder)
        if not dd then
          return
        end
        if val and val ~= "" then
          if UIDropDownMenu_SetSelectedValue then
            pcall(UIDropDownMenu_SetSelectedValue, dd, val)
          end
          if UIDropDownMenu_SetText then
            pcall(UIDropDownMenu_SetText, val, dd)
          end
          _GoldifyDD(dd)
        else
          if UIDropDownMenu_SetSelectedValue then
            pcall(UIDropDownMenu_SetSelectedValue, dd, nil)
          end
          if UIDropDownMenu_SetText then
            pcall(UIDropDownMenu_SetText, placeholder, dd)
          end
          _WhiteifyDDText(dd)
        end
      end

      _RestoreDD(condFrame.cond_ability_distanceDD, a.targetDistance, "Distance")
      _RestoreDD(condFrame.cond_ability_unitTypeDD, a.targetUnitType, "Unit type")

      -- Grey out and make unselectable when Target (self) is active
      local disableTargetRow = false
      if condFrame.cond_ability_target_self and condFrame.cond_ability_target_self.GetChecked then
        disableTargetRow = condFrame.cond_ability_target_self:GetChecked()
      end

      if disableTargetRow then
        -- clear DB fields
        a.targetDistance = nil
        a.targetUnitType = nil

        -- reset visible state and disable
        _SetDDEnabled(condFrame.cond_ability_distanceDD, false, "Distance")
        _SetDDEnabled(condFrame.cond_ability_unitTypeDD, false, "Unit type")
      else
        _SetDDEnabled(condFrame.cond_ability_distanceDD, true, "Distance")
        _SetDDEnabled(condFrame.cond_ability_unitTypeDD, true, "Unit type")
      end
    end

    -- power controls
    local pEnabled = (c.ability and c.ability.powerEnabled) and true or false
    condFrame.cond_ability_power:SetChecked(pEnabled)
    if pEnabled then
      condFrame.cond_ability_power_comp:Show()
      condFrame.cond_ability_power_val:Show()
      condFrame.cond_ability_power_val_enter:Show()
      local comp = (c.ability and c.ability.powerComp) or ""
      UIDropDownMenu_SetSelectedValue(condFrame.cond_ability_power_comp, comp)
      UIDropDownMenu_SetText(comp, condFrame.cond_ability_power_comp)
      _GoldifyDD(condFrame.cond_ability_power_comp)
      condFrame.cond_ability_power_val:SetText(tostring((c.ability and c.ability.powerVal) or 0))
    else
      condFrame.cond_ability_power_comp:Hide()
      condFrame.cond_ability_power_val:Hide()
      condFrame.cond_ability_power_val_enter:Hide()
    end

    -- glow & greyscale states
    condFrame.cond_ability_glow:SetChecked((c.ability and c.ability.glow) or false)
    condFrame.cond_ability_greyscale:SetChecked((c.ability and c.ability.greyscale) or false)
    condFrame.cond_ability_fade:SetChecked((c.ability and c.ability.fade) or false)
    if (c.ability and c.ability.fade) then
      local fadeAlpha = tonumber(c.ability.fadeAlpha) or 0
      if fadeAlpha < 0 then fadeAlpha = 0 end
      if fadeAlpha > 1 then fadeAlpha = 1 end
      condFrame.cond_ability_fade_slider:SetText(tostring(math.floor((fadeAlpha * 100) + 0.5)))
      condFrame.cond_ability_fade_slider:Show()
    else
      condFrame.cond_ability_fade_slider:Hide()
    end

    -- slider vs remaining
    local slidEnabled = (c.ability and c.ability.slider) and true or false
    condFrame.cond_ability_slider:SetChecked(slidEnabled)
    local remEnabled = (c.ability and c.ability.remainingEnabled) and true or false
    condFrame.cond_ability_remaining_cb:SetChecked(remEnabled)

    local abilityFullCD = _DA_GetAbilityCooldownDuration(data)
    local abilityHasCD = (abilityFullCD and abilityFullCD > 0) and true or false

    local function _SetHint(text)
      if not condFrame.cond_ability_slider_time_hintline then return end
      condFrame.cond_ability_slider_time_hintline:SetText(text)
      condFrame.cond_ability_slider_time_hintline:Show()
    end
    local function _HideBottomSep()
      -- Line under the hint removed by request; RESOURCE separator is enough.
      -- Named _Hide (not _Show) because it always hides. The "hard
      -- guarantee" block at the end of UpdateConditionsUI performs the
      -- same hide once more on every repaint; this helper keeps the
      -- intent explicit at the call site.
      if condFrame.cond_ability_slider_bottom_sep then
        condFrame.cond_ability_slider_bottom_sep:Hide()
      end
    end
    local function _HideSlidingUI()
      condFrame.cond_ability_slider_dir:Hide()
      if condFrame.cond_ability_slider_time then
        condFrame.cond_ability_slider_time:Hide()
      end
      if condFrame.cond_ability_slider_time_label then
        condFrame.cond_ability_slider_time_label:Hide()
      end
      if condFrame.cond_ability_slider_time_slider then
        condFrame.cond_ability_slider_time_slider:Hide()
      end
      if condFrame.cond_ability_slider_fading_cb then
        condFrame.cond_ability_slider_fading_cb:Hide()
      end
    end
    local function _GreyifySliderCB()
      condFrame.cond_ability_slider:Disable()
      if condFrame.cond_ability_slider.text and condFrame.cond_ability_slider.text.SetTextColor then
        condFrame.cond_ability_slider.text:SetTextColor(0.6, 0.6, 0.6)
      end
    end
    local function _EnableSliderCB()
      condFrame.cond_ability_slider:Enable()
      if condFrame.cond_ability_slider.text and condFrame.cond_ability_slider.text.SetTextColor then
        condFrame.cond_ability_slider.text:SetTextColor(1, 0.82, 0)
      end
    end

    if not abilityHasCD then
      condFrame.cond_ability_slider:SetChecked(false)
      _GreyifySliderCB()
      condFrame.cond_ability_slider:Show()
      _HideSlidingUI()
      _SetHint("No cooldown: sliding not available.")
      _HideBottomSep()

      condFrame.cond_ability_slider_glow:Hide()
      condFrame.cond_ability_slider_grey:Hide()
      condFrame.cond_ability_remaining_cb:SetChecked(false)
      condFrame.cond_ability_remaining_comp:Hide()
      condFrame.cond_ability_remaining_val:Hide()
      condFrame.cond_ability_remaining_val_enter:Hide()
      condFrame.cond_ability_remaining_cb:Hide()

    elseif mode == "oncd" or mode == "usableoncd" or mode == "nocdoncd" then
      condFrame.cond_ability_slider:Disable()
      condFrame.cond_ability_slider:Hide()
      condFrame.cond_ability_slider_dir:Hide()
      if condFrame.cond_ability_slider_time then
        condFrame.cond_ability_slider_time:Hide()
      end
      if condFrame.cond_ability_slider_time_label then
        condFrame.cond_ability_slider_time_label:Hide()
      end
      if condFrame.cond_ability_slider_time_slider then
        condFrame.cond_ability_slider_time_slider:Hide()
      end
      if condFrame.cond_ability_slider_time_hintline then
        condFrame.cond_ability_slider_time_hintline:Hide()
      end
      if condFrame.cond_ability_slider_fading_cb then
        condFrame.cond_ability_slider_fading_cb:Hide()
      end
      if condFrame.cond_ability_slider_bottom_sep then
        condFrame.cond_ability_slider_bottom_sep:Show()
      end
      if remEnabled then
        condFrame.cond_ability_remaining_comp:Show()
        condFrame.cond_ability_remaining_val:Show()
        condFrame.cond_ability_remaining_val_enter:Show()
        local comp = (c.ability and c.ability.remainingComp) or ""
        UIDropDownMenu_SetSelectedValue(condFrame.cond_ability_remaining_comp, comp)
        UIDropDownMenu_SetText(comp, condFrame.cond_ability_remaining_comp)
        _GoldifyDD(condFrame.cond_ability_remaining_comp)
        condFrame.cond_ability_remaining_val:SetText(tostring((c.ability and c.ability.remainingVal) or 0))
      else
        condFrame.cond_ability_remaining_comp:Hide()
        condFrame.cond_ability_remaining_val:Hide()
        condFrame.cond_ability_remaining_val_enter:Hide()
      end
    else
      _EnableSliderCB()
      condFrame.cond_ability_slider:Show()
      if slidEnabled then
        condFrame.cond_ability_slider_dir:Show()
        local dir = (c.ability and c.ability.sliderDir) or "center"
        UIDropDownMenu_SetSelectedValue(condFrame.cond_ability_slider_dir, dir)
        UIDropDownMenu_SetText(dir, condFrame.cond_ability_slider_dir)
        _GoldifyDD(condFrame.cond_ability_slider_dir)

        -- Effect dropdown (Slide / Shatter). Populated by the .Refresh
        -- hook that DoiteEditUIBuild installed on the dd object.
        if condFrame.cond_ability_slider_effect then
          condFrame.cond_ability_slider_effect:Show()
          if condFrame.cond_ability_slider_effect.Refresh then
            condFrame.cond_ability_slider_effect:Refresh()
          end
        end

        -- Slide window (seconds). Empty value = full cooldown (shown as
        -- grey placeholder in the edit box).
        if condFrame.cond_ability_slider_time then
          local sv = (c.ability and c.ability.sliderTime) or nil
          _DA_SetSliderTimeDisplay(condFrame.cond_ability_slider_time, sv, data)
          -- Belt and suspenders: the client may fire OnTextChanged
          -- asynchronously after SetText, so re-assert the placeholder
          -- state explicitly based on the DB value.
          condFrame.cond_ability_slider_time._daIsPlaceholder = (sv == nil) and true or nil
          condFrame.cond_ability_slider_time:Show()
        end
        if condFrame.cond_ability_slider_time_label then
          condFrame.cond_ability_slider_time_label:Show()
        end
        if condFrame.cond_ability_slider_time_slider then
          local fullCD = _DA_GetAbilityCooldownDuration(data) or 180
          local slider = condFrame.cond_ability_slider_time_slider
          slider._isSyncing = true
          slider:SetMinMaxValues(1, fullCD)
          local svv = (c.ability and c.ability.sliderTime) or nil
          local vv = tonumber(svv) or fullCD
          if vv < 1 then vv = 1 end
          if vv > fullCD then vv = fullCD end
          slider:SetValue(vv)
          slider._isSyncing = false
          slider:Show()
        end
        if condFrame.cond_ability_slider_time_hintline then
          condFrame.cond_ability_slider_time_hintline:SetText(
            "Empty = whole cooldown. N = slide during the last N sec")
          condFrame.cond_ability_slider_time_hintline:Show()
        end
        if condFrame.cond_ability_slider_fading_cb then
          condFrame.cond_ability_slider_fading_cb:Show()
          condFrame.cond_ability_slider_fading_cb:SetChecked((c.ability and c.ability.sliderFade) == true)
          if condFrame.cond_ability_slider_fading_cb.text and condFrame.cond_ability_slider_fading_cb.text.SetTextColor then
            condFrame.cond_ability_slider_fading_cb.text:SetTextColor(1, 0.82, 0)
          end
        end
        if condFrame.cond_ability_slider_bottom_sep then
          condFrame.cond_ability_slider_bottom_sep:Show()
        end
      else
        condFrame.cond_ability_slider_dir:Hide()
        if condFrame.cond_ability_slider_time then
          condFrame.cond_ability_slider_time:Hide()
        end
        if condFrame.cond_ability_slider_time_label then
          condFrame.cond_ability_slider_time_label:Hide()
        end
        if condFrame.cond_ability_slider_time_slider then
          condFrame.cond_ability_slider_time_slider:Hide()
        end
        if condFrame.cond_ability_slider_time_hintline then
          condFrame.cond_ability_slider_time_hintline:SetText(
            "Enable 'Soon off CD' to use sliding.")
          condFrame.cond_ability_slider_time_hintline:Show()
        end
        if condFrame.cond_ability_slider_bottom_sep then
          condFrame.cond_ability_slider_bottom_sep:Show()
        end
      end
      condFrame.cond_ability_remaining_cb:SetChecked(false)
      condFrame.cond_ability_remaining_comp:Hide()
      condFrame.cond_ability_remaining_val:Hide()
      condFrame.cond_ability_remaining_val_enter:Hide()
      condFrame.cond_ability_remaining_cb:Hide()
    end

    -- Hard guarantee: hide optional parts that must never leak out of
    -- their branches (bottom separator + Fading checkbox).
    if condFrame.cond_ability_slider_bottom_sep then
      condFrame.cond_ability_slider_bottom_sep:Hide()
    end
    if condFrame.cond_ability_slider_fading_cb then
      local cb = condFrame.cond_ability_slider_fading_cb
      -- Show Fading only when the slider UI is actually active.
      local sliderOn = (c.ability and c.ability.slider) == true
      if not sliderOn then
        cb:Hide()
      end
    end

    -- Combo points / class-specific note / weapon filter
    local isRogueOrDruid = _IsRogueOrDruid and _IsRogueOrDruid() or false
    local isWPS = _IsWarriorPaladinShaman()

    if condFrame.cond_ability_weaponDD then
      condFrame.cond_ability_weaponDD:Hide()
    end

    if isRogueOrDruid then
      -- Original combo-point behavior (Rogue / Druid)
      condFrame.cond_ability_cp_cb:Show()
      if condFrame.cond_ability_class_note then
        condFrame.cond_ability_class_note:Hide()
      end

      local cpOn = (c.ability and c.ability.cpEnabled) and true or false
      condFrame.cond_ability_cp_cb:SetChecked(cpOn)
      if cpOn then
        condFrame.cond_ability_cp_comp:Show()
        condFrame.cond_ability_cp_val:Show()
        condFrame.cond_ability_cp_val_enter:Show()
        local comp = (c.ability and c.ability.cpComp) or ""
        UIDropDownMenu_SetSelectedValue(condFrame.cond_ability_cp_comp, comp)
        UIDropDownMenu_SetText(comp, condFrame.cond_ability_cp_comp)
        _GoldifyDD(condFrame.cond_ability_cp_comp)
        condFrame.cond_ability_cp_val:SetText(tostring((c.ability and c.ability.cpVal) or 0))
      else
        condFrame.cond_ability_cp_comp:Hide()
        condFrame.cond_ability_cp_val:Hide()
        condFrame.cond_ability_cp_val_enter:Hide()
      end

    elseif isWPS and condFrame.cond_ability_weaponDD then
      -- Warrior / Paladin / Shaman: use weapon / fighting-style dropdown instead of CPs
      condFrame.cond_ability_cp_cb:Hide()
      condFrame.cond_ability_cp_comp:Hide()
      condFrame.cond_ability_cp_val:Hide()
      condFrame.cond_ability_cp_val_enter:Hide()
      if condFrame.cond_ability_class_note then
        condFrame.cond_ability_class_note:Hide()
      end

      condFrame.cond_ability_weaponDD:Show()
      InitWeaponDropdown(condFrame.cond_ability_weaponDD, data, "ability")

    else
      -- Other classes: neither CP nor weapon-filter → show neutral note
      condFrame.cond_ability_cp_cb:Hide()
      condFrame.cond_ability_cp_comp:Hide()
      condFrame.cond_ability_cp_val:Hide()
      condFrame.cond_ability_cp_val_enter:Hide()
      if condFrame.cond_ability_class_note then
        if _IsHunterOrWarlock and _IsHunterOrWarlock() then
          condFrame.cond_ability_class_note:SetText("Pet-tracking option for buff/debuff under this section.")
        else
          condFrame.cond_ability_class_note:SetText("No class-specific option added for your class.")
        end
        condFrame.cond_ability_class_note:Show()
      end
    end


    -- Row 8: HP selector (mutually exclusive)
    condFrame.cond_ability_hp_my:Show()
    condFrame.cond_ability_hp_tgt:Show()
    local hpMode = c.ability and c.ability.hpMode or nil
    condFrame.cond_ability_hp_my:SetChecked(hpMode == "my")
    condFrame.cond_ability_hp_tgt:SetChecked(hpMode == "target")
    if hpMode == "my" or hpMode == "target" then
      condFrame.cond_ability_hp_comp:Show()
      condFrame.cond_ability_hp_val:Show()
      condFrame.cond_ability_hp_val_enter:Show()
      local comp = (c.ability and c.ability.hpComp) or ""
      UIDropDownMenu_SetSelectedValue(condFrame.cond_ability_hp_comp, comp)
      UIDropDownMenu_SetText(comp, condFrame.cond_ability_hp_comp)
      _GoldifyDD(condFrame.cond_ability_hp_comp)
      condFrame.cond_ability_hp_val:SetText(tostring((c.ability and c.ability.hpVal) or 0))
    else
      condFrame.cond_ability_hp_comp:Hide()
      condFrame.cond_ability_hp_val:Hide()
      condFrame.cond_ability_hp_val_enter:Hide()
    end

    -- Row 9: Slider extras (only when slider is enabled AND mode is usable/notcd)
    -- (mode уже объявлена выше в этой ветке)
    local slidEnabled = (c.ability and c.ability.slider) and true or false
    if slidEnabled and (mode == "usable" or mode == "notcd") then
      condFrame.cond_ability_slider_glow:Show()
      condFrame.cond_ability_slider_grey:Show()
      condFrame.cond_ability_slider_glow:SetChecked((c.ability and c.ability.sliderGlow) or false)
      condFrame.cond_ability_slider_grey:SetChecked((c.ability and c.ability.sliderGrey) or false)
    else
      condFrame.cond_ability_slider_glow:Hide()
      condFrame.cond_ability_slider_grey:Hide()
    end

    -- Row 10: Text flag (time remaining only; abilities never have a stack text)

    -- Time remaining behaves as before (gated by slider when mode is usable/notcd; shown on 'oncd')
    if mode == "oncd" or mode == "usableoncd" or mode == "nocdoncd" then
      condFrame.cond_ability_text_time:Show()
      DoiteEdit_EnableCheck(condFrame.cond_ability_text_time)
      condFrame.cond_ability_text_time:SetChecked((c.ability and c.ability.textTimeRemaining) or false)

    elseif mode == "usable" or mode == "notcd" then
      condFrame.cond_ability_text_time:Show()
      if slidEnabled then
        DoiteEdit_EnableCheck(condFrame.cond_ability_text_time)
        condFrame.cond_ability_text_time:SetChecked((c.ability and c.ability.textTimeRemaining) or false)
      else
        if c.ability and c.ability.textTimeRemaining then
          c.ability.textTimeRemaining = false
        end
        condFrame.cond_ability_text_time:SetChecked(false)
        DoiteEdit_DisableCheck(condFrame.cond_ability_text_time)
      end
    else
      condFrame.cond_ability_text_time:Hide()
    end


    -- initialize and show/hide Form dropdown based on player class availability
    local choices = (function()
      local _, cls = UnitClass("player")
      cls = cls and string.upper(cls) or ""
      return (cls == "WARRIOR" or cls == "ROGUE" or cls == "DRUID" or cls == "PRIEST" or cls == "PALADIN")
    end)()

    -- hide the aura dropdown if it exists
    if condFrame.cond_aura_formDD then
      condFrame.cond_aura_formDD:Hide()
    end

    if choices and condFrame.cond_ability_formDD then
      condFrame.cond_ability_formDD:Show()
      _CD(condFrame.cond_ability_formDD)
      InitFormDropdown(condFrame.cond_ability_formDD, data, "ability")
      local v = c.ability and c.ability.form
      if v and v ~= "All" and v ~= "" then
        UIDropDownMenu_SetSelectedValue(condFrame.cond_ability_formDD, v)
        UIDropDownMenu_SetText(v, condFrame.cond_ability_formDD)
        _GoldifyDD(condFrame.cond_ability_formDD)
      else
        UIDropDownMenu_SetText("Select form", condFrame.cond_ability_formDD)
        _GoldifyDD(condFrame.cond_ability_formDD)
      end
    elseif condFrame.cond_ability_formDD then
      condFrame.cond_ability_formDD:Hide()
      _CD(condFrame.cond_ability_formDD)
    end

    -- hide aura controls
    condFrame.cond_aura_found:Hide()
    condFrame.cond_aura_missing:Hide()
    condFrame.cond_aura_incombat:Hide()
    condFrame.cond_aura_outcombat:Hide()
    if condFrame.cond_aura_groupingDD then
      condFrame.cond_aura_groupingDD:Hide()
    end
    condFrame.cond_aura_target_help:Hide()
    condFrame.cond_aura_target_harm:Hide()
    condFrame.cond_aura_onself:Hide()
    condFrame.cond_aura_glow:Hide()
    condFrame.cond_aura_greyscale:Hide()
    condFrame.cond_aura_fade:Hide()
    condFrame.cond_aura_fade_slider:Hide()
    condFrame.cond_aura_remaining_cb:Hide()
    condFrame.cond_aura_remaining_comp:Hide()
    condFrame.cond_aura_remaining_val:Hide()
    condFrame.cond_aura_remaining_val_enter:Hide()
    condFrame.cond_aura_stacks_cb:Hide()
    condFrame.cond_aura_stacks_comp:Hide()
    condFrame.cond_aura_stacks_val:Hide()
    condFrame.cond_aura_stacks_val_enter:Hide()
    condFrame.cond_aura_tip:Hide()
    if condFrame.cond_aura_text_time then
      condFrame.cond_aura_text_time:Hide()
    end
    if condFrame.cond_aura_text_stack then
      condFrame.cond_aura_text_stack:Hide()
    end
    if condFrame.cond_aura_text_time_override then
      condFrame.cond_aura_text_time_override:Hide()
    end
    if condFrame.cond_aura_text_stack_override then
      condFrame.cond_aura_text_stack_override:Hide()
    end
    if condFrame.cond_aura_text_override_note then
      condFrame.cond_aura_text_override_note:Hide()
    end

    if condFrame.cond_aura_power then
      condFrame.cond_aura_power:Hide()
    end
    if condFrame.cond_aura_power_comp then
      condFrame.cond_aura_power_comp:Hide()
    end
    if condFrame.cond_aura_power_val then
      condFrame.cond_aura_power_val:Hide()
    end
    if condFrame.cond_aura_power_val_enter then
      condFrame.cond_aura_power_val_enter:Hide()
    end

    if condFrame.cond_aura_hp_my then
      condFrame.cond_aura_hp_my:Hide()
    end
    if condFrame.cond_aura_hp_tgt then
      condFrame.cond_aura_hp_tgt:Hide()
    end
    if condFrame.cond_aura_hp_comp then
      condFrame.cond_aura_hp_comp:Hide()
    end
    if condFrame.cond_aura_hp_val then
      condFrame.cond_aura_hp_val:Hide()
    end
    if condFrame.cond_aura_hp_val_enter then
      condFrame.cond_aura_hp_val_enter:Hide()
    end

    if condFrame.cond_aura_cp_cb then
      condFrame.cond_aura_cp_cb:Hide()
    end
    if condFrame.cond_aura_cp_comp then
      condFrame.cond_aura_cp_comp:Hide()
    end
    if condFrame.cond_aura_cp_val then
      condFrame.cond_aura_cp_val:Hide()
    end
    if condFrame.cond_aura_cp_val_enter then
      condFrame.cond_aura_cp_val_enter:Hide()
    end
    if condFrame.cond_aura_class_note then
      condFrame.cond_aura_class_note:Hide()
    end
    if condFrame.cond_aura_trackpet then
      condFrame.cond_aura_trackpet:Hide()
    end
    if condFrame.cond_aura_weaponDD then
      condFrame.cond_aura_weaponDD:Hide()
    end

    -- hide aura target distance/type row when not editing an aura
    if condFrame.cond_aura_distanceDD then
      condFrame.cond_aura_distanceDD:Hide()
    end
    if condFrame.cond_aura_unitTypeDD then
      condFrame.cond_aura_unitTypeDD:Hide()
    end

    -- also hide item target distance/type row when not editing an item
    if condFrame.cond_item_distanceDD then
      condFrame.cond_item_distanceDD:Hide()
    end
    if condFrame.cond_item_unitTypeDD then
      condFrame.cond_item_unitTypeDD:Hide()
    end

    if condFrame.cond_aura_mine then
      condFrame.cond_aura_mine:Hide()
    end
    if condFrame.cond_aura_others then
      condFrame.cond_aura_others:Hide()
    end
    if condFrame.cond_aura_owner_tip then
      condFrame.cond_aura_owner_tip:Hide()
    end
    if condFrame.cond_item_where_equipped then
      condFrame.cond_item_where_equipped:Hide()
    end
    if condFrame.cond_item_where_bag then
      condFrame.cond_item_where_bag:Hide()
    end
    if condFrame.cond_item_where_missing then
      condFrame.cond_item_where_missing:Hide()
    end
    if condFrame.cond_item_notcd then
      condFrame.cond_item_notcd:Hide()
    end
    if condFrame.cond_item_oncd then
      condFrame.cond_item_oncd:Hide()
    end
    if condFrame.cond_item_incombat then
      condFrame.cond_item_incombat:Hide()
    end
    if condFrame.cond_item_outcombat then
      condFrame.cond_item_outcombat:Hide()
    end
    if condFrame.cond_item_groupingDD then
      condFrame.cond_item_groupingDD:Hide()
    end
    if condFrame.cond_item_target_help then
      condFrame.cond_item_target_help:Hide()
    end
    if condFrame.cond_item_target_harm then
      condFrame.cond_item_target_harm:Hide()
    end
    if condFrame.cond_item_target_self then
      condFrame.cond_item_target_self:Hide()
    end
    if condFrame.cond_item_glow then
      condFrame.cond_item_glow:Hide()
    end
    if condFrame.cond_item_greyscale then
      condFrame.cond_item_greyscale:Hide()
    end
    if condFrame.cond_item_fade then
      condFrame.cond_item_fade:Hide()
    end
    if condFrame.cond_item_fade_slider then
      condFrame.cond_item_fade_slider:Hide()
    end
    if condFrame.cond_item_text_time then
      condFrame.cond_item_text_time:Hide()
    end
    if condFrame.cond_item_text_time_override then
      condFrame.cond_item_text_time_override:Hide()
    end
    if condFrame.cond_item_text_override_note then
      condFrame.cond_item_text_override_note:Hide()
    end
    if condFrame.cond_item_enchant then
      condFrame.cond_item_enchant:Hide()
    end
    if condFrame.cond_item_text_enchant then
      condFrame.cond_item_text_enchant:Hide()
    end
    if condFrame.cond_item_power then
      condFrame.cond_item_power:Hide()
    end
    if condFrame.cond_item_power_comp then
      condFrame.cond_item_power_comp:Hide()
    end
    if condFrame.cond_item_power_val then
      condFrame.cond_item_power_val:Hide()
    end
    if condFrame.cond_item_power_val_enter then
      condFrame.cond_item_power_val_enter:Hide()
    end
    if condFrame.cond_item_hp_my then
      condFrame.cond_item_hp_my:Hide()
    end
    if condFrame.cond_item_hp_tgt then
      condFrame.cond_item_hp_tgt:Hide()
    end
    if condFrame.cond_item_hp_comp then
      condFrame.cond_item_hp_comp:Hide()
    end
    if condFrame.cond_item_hp_val then
      condFrame.cond_item_hp_val:Hide()
    end
    if condFrame.cond_item_hp_val_enter then
      condFrame.cond_item_hp_val_enter:Hide()
    end
    if condFrame.cond_item_remaining_cb then
      condFrame.cond_item_remaining_cb:Hide()
    end
    if condFrame.cond_item_remaining_comp then
      condFrame.cond_item_remaining_comp:Hide()
    end
    if condFrame.cond_item_remaining_val then
      condFrame.cond_item_remaining_val:Hide()
    end
    if condFrame.cond_item_remaining_val_enter then
      condFrame.cond_item_remaining_val_enter:Hide()
    end
    if condFrame.cond_item_cp_cb then
      condFrame.cond_item_cp_cb:Hide()
    end
    if condFrame.cond_item_cp_comp then
      condFrame.cond_item_cp_comp:Hide()
    end
    if condFrame.cond_item_cp_val then
      condFrame.cond_item_cp_val:Hide()
    end
    if condFrame.cond_item_cp_val_enter then
      condFrame.cond_item_cp_val_enter:Hide()
    end
    if condFrame.cond_item_formDD then
      condFrame.cond_item_formDD:Hide()
    end
    if condFrame.cond_item_inv_trinket1 then
      condFrame.cond_item_inv_trinket1:Hide()
    end
    if condFrame.cond_item_inv_trinket2 then
      condFrame.cond_item_inv_trinket2:Hide()
    end
    if condFrame.cond_item_inv_trinket_first then
      condFrame.cond_item_inv_trinket_first:Hide()
    end
    if condFrame.cond_item_inv_trinket_both then
      condFrame.cond_item_inv_trinket_both:Hide()
    end
    if condFrame.cond_item_inv_wep_mainhand then
      condFrame.cond_item_inv_wep_mainhand:Hide()
    end
    if condFrame.cond_item_inv_wep_offhand then
      condFrame.cond_item_inv_wep_offhand:Hide()
    end
    if condFrame.cond_item_inv_wep_ranged then
      condFrame.cond_item_inv_wep_ranged:Hide()
    end
    if condFrame.cond_item_inv_wep_ammo then
      condFrame.cond_item_inv_wep_ammo:Hide()
    end
    if condFrame.cond_item_class_note then
      condFrame.cond_item_class_note:Hide()
    end
    if condFrame.cond_item_weaponDD then
      condFrame.cond_item_weaponDD:Hide()
    end
    if condFrame.cond_item_clickable then
      condFrame.cond_item_clickable:Hide()
    end
    -- Hide TARGET STATUS for aura & item when editing an ability
    if condFrame.cond_aura_target_alive then
      condFrame.cond_aura_target_alive:Hide()
    end
    if condFrame.cond_aura_target_dead then
      condFrame.cond_aura_target_dead:Hide()
    end
    if condFrame.cond_item_target_alive then
      condFrame.cond_item_target_alive:Hide()
    end
    if condFrame.cond_item_target_dead then
      condFrame.cond_item_target_dead:Hide()
    end
    -- hide Item stacks row when not editing an item
    if condFrame.cond_item_stacks_cb then
      condFrame.cond_item_stacks_cb:Hide()
    end
    if condFrame.cond_item_text_stack then
      condFrame.cond_item_text_stack:Hide()
    end
    if condFrame.cond_item_stacks_comp then
      condFrame.cond_item_stacks_comp:Hide()
    end
    if condFrame.cond_item_stacks_val then
      condFrame.cond_item_stacks_val:Hide()
    end
    if condFrame.cond_item_stacks_val_enter then
      condFrame.cond_item_stacks_val_enter:Hide()
    end

    -- ITEM
  elseif data.type == "Item" then
    if ShowSeparatorsForType then ShowSeparatorsForType("item") end
    -- ensure aura-only tip is hidden when not editing an aura
    if condFrame.cond_aura_tip then
      condFrame.cond_aura_tip:Hide()
    end
    local _acRef = _G["AuraCond_RefreshFromDB"]
    if _acRef then
      _acRef("item")
    end
    local _vcRef = _G["VfxCond_RefreshFromDB"]
    if _vcRef then
      _vcRef("item")
    end

local ic = c.item or {}

    local function _enCheck(cb)
      if not cb then
        return
      end

      -- CheckButton/EditBox have :Enable(); UIDropDownMenuTemplate does NOT.
      if cb.Enable then
        cb:Enable()
      elseif UIDropDownMenu_EnableDropDown then
        -- treat as dropdown
        pcall(UIDropDownMenu_EnableDropDown, cb)
      end

      if cb.text and cb.text.SetTextColor then
        cb.text:SetTextColor(1, 0.82, 0)
      end
    end

    local function _disCheck(cb)
      if not cb then
        return
      end

      if cb.Disable then
        cb:Disable()
      elseif UIDropDownMenu_DisableDropDown then
        pcall(UIDropDownMenu_DisableDropDown, cb)
      end

      if cb.text and cb.text.SetTextColor then
        cb.text:SetTextColor(0.6, 0.6, 0.6)
      end
    end

	-- WHEREABOUTS / INVENTORY SLOT (special items)
	local dispName = data.displayName or _CK() or ""
	local isTrinketSlots = (dispName == "---EQUIPPED TRINKET SLOTS---")
	local isWeaponSlots = (dispName == "---EQUIPPED WEAPON SLOTS---")

	-- Swap "Quantity" -> "Stacks" only for main/off-hand weapon-slot entries WHEN mode=="notcd"/"both".
	condFrame._item_qty_cb_default = condFrame._item_qty_cb_default or "Quantity"
	condFrame._item_qty_sep_default = condFrame._item_qty_sep_default or "QUANTITY"

	-- mode is needed HERE (this block runs before the later mode-local)
	local _qtyMode = ic.mode or "notcd"
	if _qtyMode ~= "notcd" and _qtyMode ~= "oncd" and _qtyMode ~= "both" then
	  _qtyMode = "notcd"
	end

	local _qtySlot = ic.inventorySlot
	if _qtySlot ~= "MAINHAND" and _qtySlot ~= "OFFHAND" and _qtySlot ~= "RANGED" and _qtySlot ~= "AMMO" then
	  _qtySlot = "MAINHAND"
	end
	local useStacks = (isWeaponSlots and (_qtySlot == "MAINHAND" or _qtySlot == "OFFHAND") and (_qtyMode == "notcd" or _qtyMode == "both")) and true or false

	if useStacks then
	  if condFrame.cond_item_stacks_cb and condFrame.cond_item_stacks_cb.text and condFrame.cond_item_stacks_cb.text.SetText then
		condFrame.cond_item_stacks_cb.text:SetText("Stacks")
	  end
	  SetSeparator("item", 9, "STACKS (TEMPORARY WEAPON ENCHANT)", true, true)
	else
	  if condFrame.cond_item_stacks_cb and condFrame.cond_item_stacks_cb.text and condFrame.cond_item_stacks_cb.text.SetText then
		condFrame.cond_item_stacks_cb.text:SetText(condFrame._item_qty_cb_default)
	  end
	  SetSeparator("item", 9, condFrame._item_qty_sep_default, true, true)
	end

	local isMissing = false

    if isTrinketSlots or isWeaponSlots then
      -- Special synthetic entries: use "INVENTORY SLOT" row, never drive missing-logic
      SetSeparator("item", 1, "INVENTORY SLOT", true, true)

      -- Hide normal whereabouts
      condFrame.cond_item_where_equipped:Hide()
      condFrame.cond_item_where_bag:Hide()
      condFrame.cond_item_where_missing:Hide()

      if isTrinketSlots then
        -- Hide weapon radios
        if condFrame.cond_item_inv_wep_mainhand then
          condFrame.cond_item_inv_wep_mainhand:Hide()
          condFrame.cond_item_inv_wep_offhand:Hide()
          condFrame.cond_item_inv_wep_ranged:Hide()
          if condFrame.cond_item_inv_wep_ammo then
            condFrame.cond_item_inv_wep_ammo:Hide()
          end
        end

        -- Show trinket radios
        condFrame.cond_item_inv_trinket1:Show()
        condFrame.cond_item_inv_trinket2:Show()
        condFrame.cond_item_inv_trinket_first:Show()
        condFrame.cond_item_inv_trinket_both:Show()

        local slot = ic.inventorySlot
        if slot ~= "TRINKET1" and slot ~= "TRINKET2" and slot ~= "TRINKET_FIRST" and slot ~= "TRINKET_BOTH" then
          -- default: First ready
          slot = "TRINKET_FIRST"
          ic.inventorySlot = slot
        end

        condFrame.cond_item_inv_trinket1:SetChecked(slot == "TRINKET1")
        condFrame.cond_item_inv_trinket2:SetChecked(slot == "TRINKET2")
        condFrame.cond_item_inv_trinket_first:SetChecked(slot == "TRINKET_FIRST")
        condFrame.cond_item_inv_trinket_both:SetChecked(slot == "TRINKET_BOTH")

      else
        -- Hide trinket radios
        if condFrame.cond_item_inv_trinket1 then
          condFrame.cond_item_inv_trinket1:Hide()
          condFrame.cond_item_inv_trinket2:Hide()
          condFrame.cond_item_inv_trinket_first:Hide()
          condFrame.cond_item_inv_trinket_both:Hide()
        end

        -- Show weapon radios
        condFrame.cond_item_inv_wep_mainhand:Show()
        condFrame.cond_item_inv_wep_offhand:Show()
        condFrame.cond_item_inv_wep_ranged:Show()
        if condFrame.cond_item_inv_wep_ammo then
          condFrame.cond_item_inv_wep_ammo:Show()
        end

        local slot = ic.inventorySlot
        if slot ~= "MAINHAND" and slot ~= "OFFHAND" and slot ~= "RANGED" and slot ~= "AMMO" then
          -- default: Main hand
          slot = "MAINHAND"
          ic.inventorySlot = slot
        end

        local _, classTag = UnitClass("player")
        classTag = classTag and string.upper(classTag) or ""
        local ammoAllowed = (classTag == "WARRIOR" or classTag == "ROGUE" or classTag == "HUNTER")
        if (slot == "AMMO") and (not ammoAllowed) then
          slot = "MAINHAND"
          ic.inventorySlot = slot
        end

        condFrame.cond_item_inv_wep_mainhand:SetChecked(slot == "MAINHAND")
        condFrame.cond_item_inv_wep_offhand:SetChecked(slot == "OFFHAND")
        condFrame.cond_item_inv_wep_ranged:SetChecked(slot == "RANGED")
        if condFrame.cond_item_inv_wep_ammo then
          condFrame.cond_item_inv_wep_ammo:SetChecked(slot == "AMMO")
          if ammoAllowed then
            _enCheck(condFrame.cond_item_inv_wep_ammo)
          else
            condFrame.cond_item_inv_wep_ammo:SetChecked(false)
            _disCheck(condFrame.cond_item_inv_wep_ammo)
          end
        end
      end

      -- isMissing stays false here -> never greys out other rows

    else
      -- Normal items: original WHEREABOUTS behavior
      SetSeparator("item", 1, "WHEREABOUTS", true, true)

      -- Hide any inventory-slot radios if they exist
      if condFrame.cond_item_inv_trinket1 then
        condFrame.cond_item_inv_trinket1:Hide()
        condFrame.cond_item_inv_trinket2:Hide()
        condFrame.cond_item_inv_trinket_first:Hide()
        condFrame.cond_item_inv_trinket_both:Hide()
      end
      if condFrame.cond_item_inv_wep_mainhand then
        condFrame.cond_item_inv_wep_mainhand:Hide()
        condFrame.cond_item_inv_wep_offhand:Hide()
        condFrame.cond_item_inv_wep_ranged:Hide()
        if condFrame.cond_item_inv_wep_ammo then
          condFrame.cond_item_inv_wep_ammo:Hide()
        end
      end

      condFrame.cond_item_where_equipped:Show()
      condFrame.cond_item_where_bag:Show()
      condFrame.cond_item_where_missing:Show()

      local eq = (ic.whereEquipped ~= false)
      local bg = (ic.whereBag ~= false)
      local ms = (ic.whereMissing == true)

      if not eq and not bg and not ms then
        eq = true
      end

      condFrame.cond_item_where_equipped:SetChecked(eq)
      condFrame.cond_item_where_bag:SetChecked(bg)
      condFrame.cond_item_where_missing:SetChecked(ms)

      -- preserve outer isMissing flag for rest of Item logic
      -- Only consider "missing" effectively if it is the ONLY selection.
      -- If Equipped or Bag is also checked, allow configuring other properties (stacks, cooldowns, etc.)
      isMissing = (ms and (not eq) and (not bg))
    end

    ----------------------------------------------------------------
    -- === TARGET DISTANCE & TYPE (Item) ===   <-- now for ALL items
    ----------------------------------------------------------------
    if condFrame.cond_item_distanceDD then
      condFrame.cond_item_distanceDD:Show()
      condFrame.cond_item_unitTypeDD:Show()

      local function _RestoreItemDD(dd, val, placeholder)
        if not dd then
          return
        end
        if val and val ~= "" then
          if UIDropDownMenu_SetSelectedValue then
            pcall(UIDropDownMenu_SetSelectedValue, dd, val)
          end
          if UIDropDownMenu_SetText then
            pcall(UIDropDownMenu_SetText, val, dd)
          end
          _GoldifyDD(dd)
        else
          if UIDropDownMenu_SetSelectedValue then
            pcall(UIDropDownMenu_SetSelectedValue, dd, nil)
          end
          if UIDropDownMenu_SetText then
            pcall(UIDropDownMenu_SetText, placeholder, dd)
          end
          _WhiteifyDDText(dd)
        end
      end

      -- Always clear & hard-disable Distance for items
      ic.targetDistance = nil
      _RestoreItemDD(condFrame.cond_item_distanceDD, nil, "Distance")
      _SetDDEnabled(condFrame.cond_item_distanceDD, false, "Distance")

      -- UnitType still follow the old rules
      _RestoreItemDD(condFrame.cond_item_unitTypeDD, ic.targetUnitType, "Unit type")

      local isMissingForDD = (ic.whereMissing == true)
      local hasSelfTarget = (ic.targetSelf == true)

      if isMissingForDD or hasSelfTarget then
        ic.targetUnitType = nil
        _SetDDEnabled(condFrame.cond_item_unitTypeDD, false, "Unit type")
      else
        _SetDDEnabled(condFrame.cond_item_unitTypeDD, true, "Unit type")
      end
    end

    -- USABILITY & COOLDOWN
    condFrame.cond_item_notcd:Show()
    condFrame.cond_item_oncd:Show()
    condFrame.cond_item_sound_oncd_cb:Show()
    condFrame.cond_item_sound_oncd_dd:Show()
    condFrame.cond_item_sound_offcd_cb:Show()
    condFrame.cond_item_sound_offcd_dd:Show()

    _enCheck(condFrame.cond_item_notcd)

    local iSoundOn = (ic.soundOnCDEnabled == true)
    local iSoundOff = (ic.soundOffCDEnabled == true)
    local iSoundOnSel = ic.soundOnCD
    local iSoundOffSel = ic.soundOffCD
    condFrame.cond_item_sound_oncd_cb:SetChecked(iSoundOn)
    condFrame.cond_item_sound_offcd_cb:SetChecked(iSoundOff)
    DoiteEdit_InitSoundDropdown(condFrame.cond_item_sound_oncd_dd, "item", "soundOnCD", iSoundOnSel)
    DoiteEdit_InitSoundDropdown(condFrame.cond_item_sound_offcd_dd, "item", "soundOffCD", iSoundOffSel)
    DoiteEdit_EnableCheck(condFrame.cond_item_sound_oncd_cb)
    DoiteEdit_EnableCheck(condFrame.cond_item_sound_offcd_cb)
    DoiteEdit_SetDropdownInteractive(condFrame.cond_item_sound_oncd_dd, iSoundOn)
    DoiteEdit_SetDropdownInteractive(condFrame.cond_item_sound_offcd_dd, iSoundOff)
    _enCheck(condFrame.cond_item_oncd)
    
    -- CLICKABLE
    if condFrame.cond_item_clickable then
      condFrame.cond_item_clickable:Show()
      _enCheck(condFrame.cond_item_clickable)
      condFrame.cond_item_clickable:SetChecked(ic.clickable == true)
    end

    -- mode (must be defined BEFORE any mode-based UI logic)
    local mode = ic.mode or "notcd"
    if mode ~= "notcd" and mode ~= "oncd" and mode ~= "both" then
      mode = "notcd"
    end

    condFrame.cond_item_notcd:SetChecked(mode == "notcd" or mode == "both")
    condFrame.cond_item_oncd:SetChecked(mode == "oncd" or mode == "both")

    local isMainOffhandWeaponSlot = (ic.inventorySlot == "MAINHAND" or ic.inventorySlot == "OFFHAND")

    -- Enchanted state dropdown: Enabled ONLY for main/off-hand weapon slots + notcd/both + not missing. Disabled elsewhere, and clears ic.enchant when disabled.
    if condFrame.cond_item_enchant then
      condFrame.cond_item_enchant:Show()

      local allowEnchant = (not isMissing) and isWeaponSlots and isMainOffhandWeaponSlot and (mode == "notcd" or mode == "both")
      if allowEnchant then
        _enCheck(condFrame.cond_item_enchant)

        local txt = "Enchanted state"
        if ic.enchant == true then
          txt = "Enchanted"
          if UIDropDownMenu_SetSelectedValue then
            pcall(UIDropDownMenu_SetSelectedValue, condFrame.cond_item_enchant, "true")
          end
        elseif ic.enchant == false then
          txt = "Not enchanted"
          if UIDropDownMenu_SetSelectedValue then
            pcall(UIDropDownMenu_SetSelectedValue, condFrame.cond_item_enchant, "false")
          end
        else
		-- nil => placeholder; clear selected value to avoid stale selection
          if UIDropDownMenu_SetSelectedValue then
            pcall(UIDropDownMenu_SetSelectedValue, condFrame.cond_item_enchant, nil)
          end
        end

        if UIDropDownMenu_SetText then
          pcall(UIDropDownMenu_SetText, txt, condFrame.cond_item_enchant)
        end
        if _GoldifyDD then
          _GoldifyDD(condFrame.cond_item_enchant)
        end
      else
        -- Not allowed (including mode=="oncd" or non-weapon-slot items)
        if ic.enchant ~= nil then
          ic.enchant = nil
        end

        _disCheck(condFrame.cond_item_enchant)
        if UIDropDownMenu_SetText then
          pcall(UIDropDownMenu_SetText, "Enchanted state", condFrame.cond_item_enchant)
        end
        if _GreyifyDD then
          _GreyifyDD(condFrame.cond_item_enchant)
        end
      end
    end

    -- Icon text: Enchant uptime remaining. Enabled ONLY for main/off-hand weapon slots + notcd/both + not missing, AND only when enchanted-state is not explicitly "Not enchanted". If "Not enchanted" is selected, force OFF + disable + clear DB entry (cannot show uptime if not enchanted).
    if condFrame.cond_item_text_enchant then
      condFrame.cond_item_text_enchant:Show()

      local allowEnchantText = (not isMissing) and isWeaponSlots and isMainOffhandWeaponSlot and (mode == "notcd" or mode == "both")

      -- extra rule: "Not enchanted" disables this checkbox and clears its DB entry
      if allowEnchantText and (ic.enchant == false) then
        if ic.textTimeRemaining ~= nil then
          ic.textTimeRemaining = nil
        end
        condFrame.cond_item_text_enchant:SetChecked(false)
        _disCheck(condFrame.cond_item_text_enchant)

      elseif allowEnchantText then
        _enCheck(condFrame.cond_item_text_enchant)
        condFrame.cond_item_text_enchant:SetChecked(ic.textTimeRemaining == true)

      else
        -- opposite mode / non-weapon items: forced OFF + disabled (but do NOT clear DB)
        condFrame.cond_item_text_enchant:SetChecked(false)
        _disCheck(condFrame.cond_item_text_enchant)
      end
    end

    if isMissing then
      condFrame.cond_item_notcd:SetChecked(false)
      condFrame.cond_item_oncd:SetChecked(false)
      _disCheck(condFrame.cond_item_notcd)
      _disCheck(condFrame.cond_item_oncd)

      if condFrame.cond_item_enchant then
        if ic.enchant ~= nil then
          ic.enchant = nil
        end
        _disCheck(condFrame.cond_item_enchant)
        if UIDropDownMenu_SetText then
          pcall(UIDropDownMenu_SetText, "Enchanted state", condFrame.cond_item_enchant)
        end
        if _GreyifyDD then
          _GreyifyDD(condFrame.cond_item_enchant)
        end
      end

      if condFrame.cond_item_text_enchant then
        condFrame.cond_item_text_enchant:SetChecked(false)
        _disCheck(condFrame.cond_item_text_enchant)
      end
    end

    -- COMBAT STATE
    condFrame.cond_item_incombat:Show()
    condFrame.cond_item_outcombat:Show()
    if condFrame.cond_item_groupingDD then
      condFrame.cond_item_groupingDD:Show()
    end

    local inC, outC
    if ic.inCombat ~= nil or ic.outCombat ~= nil then
      inC = ic.inCombat and true or false
      outC = ic.outCombat and true or false
    else
      inC, outC = true, true
    end
    condFrame.cond_item_incombat:SetChecked(inC)
    condFrame.cond_item_outcombat:SetChecked(outC)

    if condFrame.cond_item_groupingDD then
      local gm = _DeriveGroupingMode(ic)
      local txt
      if gm == "any" then
        txt = "Any"
      elseif gm == "nogroup" then
        txt = "Not in group"
      elseif gm == "party" then
        txt = "In party"
      elseif gm == "raid" then
        txt = "In raid"
      elseif gm == "partyraid" then
        txt = "In party or raid"
      else
        txt = "Group state"
      end

      if gm ~= nil then
        if UIDropDownMenu_SetSelectedValue then
          pcall(UIDropDownMenu_SetSelectedValue, condFrame.cond_item_groupingDD, gm)
        end
      else
      end

      if UIDropDownMenu_SetText then
        pcall(UIDropDownMenu_SetText, txt, condFrame.cond_item_groupingDD)
      end
      if _GoldifyDD then _GoldifyDD(condFrame.cond_item_groupingDD) end
    end

    _enCheck(condFrame.cond_item_incombat)
    _enCheck(condFrame.cond_item_outcombat)
    _enCheck(condFrame.cond_item_groupingDD)

    -- TARGET CONDITIONS
    condFrame.cond_item_target_help:Show()
    condFrame.cond_item_target_harm:Show()
    condFrame.cond_item_target_self:Show()
    condFrame.cond_item_target_help:SetChecked(ic.targetHelp == true)
    condFrame.cond_item_target_harm:SetChecked(ic.targetHarm == true)
    condFrame.cond_item_target_self:SetChecked(ic.targetSelf == true)

    -- TARGET STATUS (item)
    if condFrame.cond_item_target_alive then
      condFrame.cond_item_target_alive:SetChecked(ic.targetAlive == true)
      condFrame.cond_item_target_alive:Show()
    end
    if condFrame.cond_item_target_dead then
      condFrame.cond_item_target_dead:SetChecked(ic.targetDead == true)
      condFrame.cond_item_target_dead:Show()
    end

    if condFrame.cond_aura_text_time_override then
      condFrame.cond_aura_text_time_override:Hide()
    end
    if condFrame.cond_aura_text_stack_override then
      condFrame.cond_aura_text_stack_override:Hide()
    end
    if condFrame.cond_aura_text_override_note then
      condFrame.cond_aura_text_override_note:Hide()
    end

    -- VISUAL EFFECTS
    condFrame.cond_item_glow:Show()
    condFrame.cond_item_greyscale:Show()
    condFrame.cond_item_fade:Show()
    condFrame.cond_item_text_time:Show()
    condFrame.cond_item_glow:SetChecked(ic.glow == true)
    condFrame.cond_item_greyscale:SetChecked(ic.greyscale == true)
    condFrame.cond_item_fade:SetChecked(ic.fade == true)
    if ic.fade == true then
      local fadeAlpha = tonumber(ic.fadeAlpha) or 0
      if fadeAlpha < 0 then fadeAlpha = 0 end
      if fadeAlpha > 1 then fadeAlpha = 1 end
      condFrame.cond_item_fade_slider:SetText(tostring(math.floor((fadeAlpha * 100) + 0.5)))
      condFrame.cond_item_fade_slider:Show()
    else
      condFrame.cond_item_fade_slider:Hide()
    end

    -- Keep item text-time label constant
    do
      local lbl = "Icon text: Time remaining"
      if condFrame.cond_item_text_time and condFrame.cond_item_text_time.text
          and condFrame.cond_item_text_time.text.SetText then
        condFrame.cond_item_text_time.text:SetText(lbl)
      end
    end

    -- Icon text: Time remaining (shared DB key: ic.textTimeRemaining)

    do
      local allowTime = (not isMissing) and (mode == "oncd" or ((not isMainOffhandWeaponSlot) and mode == "both"))

      if allowTime then
        _enCheck(condFrame.cond_item_text_time)
        condFrame.cond_item_text_time:SetChecked(ic.textTimeRemaining == true)
      else
        condFrame.cond_item_text_time:SetChecked(false)
        _disCheck(condFrame.cond_item_text_time)

        if not (isMainOffhandWeaponSlot and (mode == "notcd" or mode == "both")) then
          if ic.textTimeRemaining ~= nil then
            ic.textTimeRemaining = nil
          end
        end
      end

      if condFrame.cond_item_text_time_override then
        if allowTime and condFrame.cond_item_text_time:GetChecked() then
          condFrame.cond_item_text_time_override:Show()
          condFrame.cond_item_text_time_override:SetText(ic.remOverride or "")
        else
          condFrame.cond_item_text_time_override:Hide()
        end
      end
      if condFrame.cond_item_text_override_note then
        if allowTime and condFrame.cond_item_text_time:GetChecked() then
          condFrame.cond_item_text_override_note:Show()
        else
          condFrame.cond_item_text_override_note:Hide()
        end
      end
    end

    -- ITEM STACKS row (Item stacks + text stack counter)
    do
      local stacksOn = (ic.stacksEnabled == true)
      local textStacks = (ic.textStackCounter == true)

      -- Always show the two checkboxes for any Item-type entry
      condFrame.cond_item_stacks_cb:Show()
      condFrame.cond_item_text_stack:Show()

      if isMissing then
        condFrame.cond_item_stacks_cb:SetChecked(false)
        condFrame.cond_item_text_stack:SetChecked(false)

        _disCheck(condFrame.cond_item_stacks_cb)
        _disCheck(condFrame.cond_item_text_stack)

        if condFrame.cond_item_stacks_comp then
          condFrame.cond_item_stacks_comp:Hide()
        end
        if condFrame.cond_item_stacks_val then
          condFrame.cond_item_stacks_val:Hide()
        end
        if condFrame.cond_item_stacks_val_enter then
          condFrame.cond_item_stacks_val_enter:Hide()
        end
      else
        _enCheck(condFrame.cond_item_stacks_cb)
        _enCheck(condFrame.cond_item_text_stack)

        condFrame.cond_item_stacks_cb:SetChecked(stacksOn)
        condFrame.cond_item_text_stack:SetChecked(textStacks)

        if stacksOn then
          if condFrame.cond_item_stacks_comp then
            condFrame.cond_item_stacks_comp:Show()
          end
          if condFrame.cond_item_stacks_val then
            condFrame.cond_item_stacks_val:Show()
          end
          if condFrame.cond_item_stacks_val_enter then
            condFrame.cond_item_stacks_val_enter:Show()
          end

          local comp = ic.stacksComp or ""
          UIDropDownMenu_SetSelectedValue(condFrame.cond_item_stacks_comp, comp)
          UIDropDownMenu_SetText(comp, condFrame.cond_item_stacks_comp)
          _GoldifyDD(condFrame.cond_item_stacks_comp)

          condFrame.cond_item_stacks_val:SetText(tostring(ic.stacksVal or 0))
        else
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
      end
    end

    -- RESOURCE
    condFrame.cond_item_power:Show()
    local pOn = (ic.powerEnabled == true)
    condFrame.cond_item_power:SetChecked(pOn)

    if isMissing then
      condFrame.cond_item_power:SetChecked(false)
      _disCheck(condFrame.cond_item_power)
      condFrame.cond_item_power_comp:Hide()
      condFrame.cond_item_power_val:Hide()
      condFrame.cond_item_power_val_enter:Hide()
    else
      _enCheck(condFrame.cond_item_power)
      if pOn then
        condFrame.cond_item_power_comp:Show()
        condFrame.cond_item_power_val:Show()
        condFrame.cond_item_power_val_enter:Show()
        local comp = ic.powerComp or ""
        UIDropDownMenu_SetSelectedValue(condFrame.cond_item_power_comp, comp)
        UIDropDownMenu_SetText(comp, condFrame.cond_item_power_comp)
        _GoldifyDD(condFrame.cond_item_power_comp)
        condFrame.cond_item_power_val:SetText(tostring(ic.powerVal or 0))
      else
        condFrame.cond_item_power_comp:Hide()
        condFrame.cond_item_power_val:Hide()
        condFrame.cond_item_power_val_enter:Hide()
      end
    end

    -- HEALTH CONDITION
    condFrame.cond_item_hp_my:Show()
    condFrame.cond_item_hp_tgt:Show()
    local hpMode = ic.hpMode
    condFrame.cond_item_hp_my:SetChecked(hpMode == "my")
    condFrame.cond_item_hp_tgt:SetChecked(hpMode == "target")

    if isMissing then
      condFrame.cond_item_hp_my:SetChecked(false)
      condFrame.cond_item_hp_tgt:SetChecked(false)
      _disCheck(condFrame.cond_item_hp_my)
      _disCheck(condFrame.cond_item_hp_tgt)
      condFrame.cond_item_hp_comp:Hide()
      condFrame.cond_item_hp_val:Hide()
      condFrame.cond_item_hp_val_enter:Hide()
    else
      _enCheck(condFrame.cond_item_hp_my)
      _enCheck(condFrame.cond_item_hp_tgt)
      if hpMode == "my" or hpMode == "target" then
        condFrame.cond_item_hp_comp:Show()
        condFrame.cond_item_hp_val:Show()
        condFrame.cond_item_hp_val_enter:Show()
        local comp = ic.hpComp or ""
        UIDropDownMenu_SetSelectedValue(condFrame.cond_item_hp_comp, comp)
        UIDropDownMenu_SetText(comp, condFrame.cond_item_hp_comp)
        _GoldifyDD(condFrame.cond_item_hp_comp)
        condFrame.cond_item_hp_val:SetText(tostring(ic.hpVal or 0))
      else
        condFrame.cond_item_hp_comp:Hide()
        condFrame.cond_item_hp_val:Hide()
        condFrame.cond_item_hp_val_enter:Hide()
      end
    end

    -- REMAINING TIME
    do
      local sepTitle = "REMAINING TIME"
      if isMainOffhandWeaponSlot then
        if mode == "notcd" or mode == "both" then
          sepTitle = "REMAINING TIME (TEMPORARY WEAPON ENCHANT)"
        elseif mode == "oncd" then
          sepTitle = "REMAINING TIME"
        end
      end
      SetSeparator("item", 12, sepTitle, true, true)
    end
    condFrame.cond_item_remaining_cb:Show()
	if (not isMissing) and (mode == "oncd" or ((not isMainOffhandWeaponSlot) and mode == "both") or (isMainOffhandWeaponSlot and (mode == "notcd" or mode == "both"))) then
	  _enCheck(condFrame.cond_item_remaining_cb)
	  local remOn = (ic.remainingEnabled == true)
	  condFrame.cond_item_remaining_cb:SetChecked(remOn)
	  if remOn then
		condFrame.cond_item_remaining_comp:Show()
		condFrame.cond_item_remaining_val:Show()
		condFrame.cond_item_remaining_val_enter:Show()
		local comp = ic.remainingComp or ""
		UIDropDownMenu_SetSelectedValue(condFrame.cond_item_remaining_comp, comp)
		UIDropDownMenu_SetText(comp, condFrame.cond_item_remaining_comp)
		_GoldifyDD(condFrame.cond_item_remaining_comp)
		condFrame.cond_item_remaining_val:SetText(tostring(ic.remainingVal or 0))
	  else
		condFrame.cond_item_remaining_comp:Hide()
		condFrame.cond_item_remaining_val:Hide()
		condFrame.cond_item_remaining_val_enter:Hide()
	  end
	else
	  if ic.remainingEnabled then
		ic.remainingEnabled = false
	  end
	  condFrame.cond_item_remaining_cb:SetChecked(false)
	  _disCheck(condFrame.cond_item_remaining_cb)
	  condFrame.cond_item_remaining_comp:Hide()
	  condFrame.cond_item_remaining_val:Hide()
	  condFrame.cond_item_remaining_val_enter:Hide()
	end

    -- CLASS-SPECIFIC (combo points / note / weapon filter)
    local isRogueOrDruid = _IsRogueOrDruid and _IsRogueOrDruid() or false
    local isWPS = _IsWarriorPaladinShaman()

    -- Default: hide weapon dropdown; show+init only for W/P/S
    if condFrame.cond_item_weaponDD then
      condFrame.cond_item_weaponDD:Hide()
    end

    if isRogueOrDruid then
      condFrame.cond_item_cp_cb:Show()
      if condFrame.cond_item_class_note then
        condFrame.cond_item_class_note:Hide()
      end

      if isMissing then
        -- Item marked as Missing: keep CP row visible but forced off and greyed
        if ic.cpEnabled then
          ic.cpEnabled = false
        end
        condFrame.cond_item_cp_cb:SetChecked(false)
        _disCheck(condFrame.cond_item_cp_cb)
        condFrame.cond_item_cp_comp:Hide()
        condFrame.cond_item_cp_val:Hide()
        condFrame.cond_item_cp_val_enter:Hide()
      else
        _enCheck(condFrame.cond_item_cp_cb)
        local cpOn = (ic.cpEnabled == true)
        condFrame.cond_item_cp_cb:SetChecked(cpOn)
        if cpOn then
          condFrame.cond_item_cp_comp:Show()
          condFrame.cond_item_cp_val:Show()
          condFrame.cond_item_cp_val_enter:Show()
          local comp = ic.cpComp or ""
          UIDropDownMenu_SetSelectedValue(condFrame.cond_item_cp_comp, comp)
          UIDropDownMenu_SetText(comp, condFrame.cond_item_cp_comp)
          _GoldifyDD(condFrame.cond_item_cp_comp)
          condFrame.cond_item_cp_val:SetText(tostring(ic.cpVal or 0))
        else
          condFrame.cond_item_cp_comp:Hide()
          condFrame.cond_item_cp_val:Hide()
          condFrame.cond_item_cp_val_enter:Hide()
        end
      end

    elseif isWPS and condFrame.cond_item_weaponDD then
      -- Warrior / Paladin / Shaman: weapon / fighting-style dropdown instead of CP
      condFrame.cond_item_cp_cb:Hide()
      condFrame.cond_item_cp_comp:Hide()
      condFrame.cond_item_cp_val:Hide()
      condFrame.cond_item_cp_val_enter:Hide()
      if condFrame.cond_item_class_note then
        condFrame.cond_item_class_note:Hide()
      end

      condFrame.cond_item_weaponDD:Show()
      InitWeaponDropdown(condFrame.cond_item_weaponDD, data, "item")

    else
      -- Other classes: no CP and no weapon filter → show neutral note
      condFrame.cond_item_cp_cb:Hide()
      condFrame.cond_item_cp_comp:Hide()
      condFrame.cond_item_cp_val:Hide()
      condFrame.cond_item_cp_val_enter:Hide()
      if condFrame.cond_item_class_note then
        if _IsHunterOrWarlock and _IsHunterOrWarlock() then
          condFrame.cond_item_class_note:SetText("Pet-tracking option for buff/debuff under this section.")
        else
          condFrame.cond_item_class_note:SetText("No class-specific option added for your class.")
        end
        condFrame.cond_item_class_note:Show()
      end
    end

    -- Form dropdown (item)
    if condFrame.cond_ability_formDD then
      condFrame.cond_ability_formDD:Hide()
    end
    if condFrame.cond_aura_formDD then
      condFrame.cond_aura_formDD:Hide()
    end

    local choices = (function()
      local _, cls = UnitClass("player")
      cls = cls and string.upper(cls) or ""
      return (cls == "WARRIOR" or cls == "ROGUE" or cls == "DRUID" or cls == "PRIEST" or cls == "PALADIN")
    end)()
    if choices and condFrame.cond_item_formDD then
      condFrame.cond_item_formDD:Show()
      _CD(condFrame.cond_item_formDD)
      InitFormDropdown(condFrame.cond_item_formDD, data, "item")
      local v = ic.form
      if v and v ~= "All" and v ~= "" then
        UIDropDownMenu_SetSelectedValue(condFrame.cond_item_formDD, v)
        UIDropDownMenu_SetText(v, condFrame.cond_item_formDD)
        _GoldifyDD(condFrame.cond_item_formDD)
      else
        UIDropDownMenu_SetText("Select form", condFrame.cond_item_formDD)
        _GoldifyDD(condFrame.cond_item_formDD)
      end
    elseif condFrame.cond_item_formDD then
      condFrame.cond_item_formDD:Hide()
      _CD(condFrame.cond_item_formDD)
    end

    -- hide ability controls
    condFrame.cond_ability_usable:Hide()
    condFrame.cond_ability_notcd:Hide()
    condFrame.cond_ability_oncd:Hide()
    condFrame.cond_ability_incombat:Hide()
    condFrame.cond_ability_outcombat:Hide()
    if condFrame.cond_ability_groupingDD then
      condFrame.cond_ability_groupingDD:Hide()
    end
    condFrame.cond_ability_target_help:Hide()
    condFrame.cond_ability_target_harm:Hide()
    condFrame.cond_ability_target_self:Hide()
    condFrame.cond_ability_power:Hide()
    condFrame.cond_ability_power_comp:Hide()
    condFrame.cond_ability_power_val:Hide()
    condFrame.cond_ability_power_val_enter:Hide()
    condFrame.cond_ability_glow:Hide()
    condFrame.cond_ability_greyscale:Hide()
    condFrame.cond_ability_fade:Hide()
    condFrame.cond_ability_fade_slider:Hide()
    condFrame.cond_ability_slider:Hide()
    condFrame.cond_ability_slider_dir:Hide()
    if condFrame.cond_ability_slider_time then
      condFrame.cond_ability_slider_time:Hide()
    end
    if condFrame.cond_ability_slider_time_label then
      condFrame.cond_ability_slider_time_label:Hide()
    end
    if condFrame.cond_ability_slider_time_slider then
      condFrame.cond_ability_slider_time_slider:Hide()
    end
    if condFrame.cond_ability_slider_time_hintline then
      condFrame.cond_ability_slider_time_hintline:Hide()
    end
    if condFrame.cond_ability_slider_bottom_sep then
      condFrame.cond_ability_slider_bottom_sep:Hide()
    end
    condFrame.cond_ability_remaining_cb:Hide()
    condFrame.cond_ability_remaining_comp:Hide()
    condFrame.cond_ability_remaining_val:Hide()
    condFrame.cond_ability_remaining_val_enter:Hide()
    condFrame.cond_ability_text_time:Hide()
    condFrame.cond_ability_slider_glow:Hide()
    condFrame.cond_ability_slider_grey:Hide()
    condFrame.cond_ability_hp_my:Hide()
    condFrame.cond_ability_hp_tgt:Hide()
    condFrame.cond_ability_hp_comp:Hide()
    condFrame.cond_ability_hp_val:Hide()
    condFrame.cond_ability_hp_val_enter:Hide()
    condFrame.cond_ability_cp_cb:Hide()
    condFrame.cond_ability_cp_comp:Hide()
    condFrame.cond_ability_cp_val:Hide()
    condFrame.cond_ability_cp_val_enter:Hide()
    if condFrame.cond_ability_class_note then
      condFrame.cond_ability_class_note:Hide()
    end
    if condFrame.cond_ability_formDD then
      condFrame.cond_ability_formDD:Hide()
    end
    if condFrame.cond_ability_weaponDD then
      condFrame.cond_ability_weaponDD:Hide()
    end
    if condFrame.cond_ability_target_alive then
      condFrame.cond_ability_target_alive:Hide()
    end
    if condFrame.cond_ability_target_dead then
      condFrame.cond_ability_target_dead:Hide()
    end

    -- hide aura controls
    condFrame.cond_aura_found:Hide()
    condFrame.cond_aura_missing:Hide()
    condFrame.cond_aura_incombat:Hide()
    condFrame.cond_aura_outcombat:Hide()
    if condFrame.cond_aura_groupingDD then
      condFrame.cond_aura_groupingDD:Hide()
    end
    condFrame.cond_aura_target_help:Hide()
    condFrame.cond_aura_target_harm:Hide()
    condFrame.cond_aura_onself:Hide()
    if condFrame.cond_aura_target_alive then
      condFrame.cond_aura_target_alive:Hide()
    end
    if condFrame.cond_aura_target_dead then
      condFrame.cond_aura_target_dead:Hide()
    end
    condFrame.cond_aura_glow:Hide()
    condFrame.cond_aura_greyscale:Hide()
    condFrame.cond_aura_fade:Hide()
    condFrame.cond_aura_fade_slider:Hide()
    condFrame.cond_aura_power:Hide()
    condFrame.cond_aura_power_comp:Hide()
    condFrame.cond_aura_power_val:Hide()
    condFrame.cond_aura_power_val_enter:Hide()
    condFrame.cond_aura_hp_my:Hide()
    condFrame.cond_aura_hp_tgt:Hide()
    condFrame.cond_aura_hp_comp:Hide()
    condFrame.cond_aura_hp_val:Hide()
    condFrame.cond_aura_hp_val_enter:Hide()
    condFrame.cond_aura_remaining_cb:Hide()
    condFrame.cond_aura_remaining_comp:Hide()
    condFrame.cond_aura_remaining_val:Hide()
    condFrame.cond_aura_remaining_val_enter:Hide()
    condFrame.cond_aura_stacks_cb:Hide()
    condFrame.cond_aura_stacks_comp:Hide()
    condFrame.cond_aura_stacks_val:Hide()
    condFrame.cond_aura_stacks_val_enter:Hide()
    condFrame.cond_aura_text_time:Hide()
    condFrame.cond_aura_text_stack:Hide()
    condFrame.cond_aura_cp_cb:Hide()
    condFrame.cond_aura_cp_comp:Hide()
    condFrame.cond_aura_cp_val:Hide()
    condFrame.cond_aura_cp_val_enter:Hide()
    if condFrame.cond_aura_weaponDD then
      condFrame.cond_aura_weaponDD:Hide()
    end

    -- hide aura target distance/type row when not editing an aura
    if condFrame.cond_aura_distanceDD then
      condFrame.cond_aura_distanceDD:Hide()
    end
    if condFrame.cond_aura_unitTypeDD then
      condFrame.cond_aura_unitTypeDD:Hide()
    end

    -- hide ability target distance/type row when not editing an ability
    if condFrame.cond_ability_distanceDD then
      condFrame.cond_ability_distanceDD:Hide()
    end
    if condFrame.cond_ability_unitTypeDD then
      condFrame.cond_ability_unitTypeDD:Hide()
    end

    condFrame.cond_aura_mine:Hide()
    condFrame.cond_aura_others:Hide()
    if condFrame.cond_aura_owner_tip then
      condFrame.cond_aura_owner_tip:Hide()
    end
    if condFrame.cond_aura_tip then
      condFrame.cond_aura_tip:Hide()
    end
    if condFrame.cond_aura_formDD then
      condFrame.cond_aura_formDD:Hide()
    end
    if condFrame.cond_aura_class_note then
      condFrame.cond_aura_class_note:Hide()
    end
    if condFrame.cond_aura_trackpet then
      condFrame.cond_aura_trackpet:Hide()
    end

  elseif data.type == "Custom" then
    -- Hide all separators – the edit box fills the entire conditions area.
    for _, list in pairs(condFrame._seps or {}) do
      for _, sep in pairs(list) do
        sep:Hide()
      end
    end

    local _acRef = _G["AuraCond_RefreshFromDB"]
    if _acRef then
      _acRef(nil)
    end
    local _vcRef = _G["VfxCond_RefreshFromDB"]
    if _vcRef then
      _vcRef(nil)
    end

    -- Show custom function edit box (fills the outer scroll area)
    if condFrame.cond_custom_function_edit then
      condFrame.cond_custom_function_edit:Show()
      if condFrame._customFunctionLoadedKey ~= _CK() then
        local src = data.customFunctionSource
        if type(src) ~= "string" or src == "" then
          src = DEFAULT_CUSTOM_FUNCTION_SOURCE
        end
        condFrame.cond_custom_function_edit:SetText(src)
        condFrame._customFunctionLoadedKey = _CK()
      end
    end
    -- Save button + status (outside the scroll area, next to Grid button)
    if condFrame.cond_custom_function_save then
      condFrame.cond_custom_function_save:Show()
    end
    if condFrame.cond_custom_function_status then
      condFrame.cond_custom_function_status:Show()
    end

    -- Hide all stock ability/aura/item controls while editing custom code
    local function _Hide(v)
      if v and v.Hide then
        v:Hide()
      end
    end

    _Hide(condFrame.cond_ability_usable)
    _Hide(condFrame.cond_ability_notcd)
    _Hide(condFrame.cond_ability_oncd)
    _Hide(condFrame.cond_ability_incombat)
    _Hide(condFrame.cond_ability_outcombat)
    _Hide(condFrame.cond_ability_groupingDD)
    _Hide(condFrame.cond_ability_target_help)
    _Hide(condFrame.cond_ability_target_harm)
    _Hide(condFrame.cond_ability_target_self)
    _Hide(condFrame.cond_ability_target_alive)
    _Hide(condFrame.cond_ability_target_dead)
    _Hide(condFrame.cond_ability_glow)
    _Hide(condFrame.cond_ability_greyscale)
    _Hide(condFrame.cond_ability_fade)
    _Hide(condFrame.cond_ability_fade_slider)
    _Hide(condFrame.cond_ability_slider)
    _Hide(condFrame.cond_ability_slider_dir)
    _Hide(condFrame.cond_ability_slider_time)
    _Hide(condFrame.cond_ability_slider_time_label)
    _Hide(condFrame.cond_ability_slider_glow)
    _Hide(condFrame.cond_ability_slider_grey)
    _Hide(condFrame.cond_ability_remaining_cb)
    _Hide(condFrame.cond_ability_remaining_comp)
    _Hide(condFrame.cond_ability_remaining_val)
    _Hide(condFrame.cond_ability_remaining_val_enter)
    _Hide(condFrame.cond_ability_text_time)
    _Hide(condFrame.cond_ability_power)
    _Hide(condFrame.cond_ability_power_comp)
    _Hide(condFrame.cond_ability_power_val)
    _Hide(condFrame.cond_ability_power_val_enter)
    _Hide(condFrame.cond_ability_hp_my)
    _Hide(condFrame.cond_ability_hp_tgt)
    _Hide(condFrame.cond_ability_hp_comp)
    _Hide(condFrame.cond_ability_hp_val)
    _Hide(condFrame.cond_ability_hp_val_enter)
    _Hide(condFrame.cond_ability_cp_cb)
    _Hide(condFrame.cond_ability_cp_comp)
    _Hide(condFrame.cond_ability_cp_val)
    _Hide(condFrame.cond_ability_cp_val_enter)
    _Hide(condFrame.cond_ability_class_note)
    _Hide(condFrame.cond_ability_formDD)
    _Hide(condFrame.cond_ability_weaponDD)
    _Hide(condFrame.cond_ability_distanceDD)
    _Hide(condFrame.cond_ability_unitTypeDD)

    _Hide(condFrame.cond_aura_found)
    _Hide(condFrame.cond_aura_missing)
    _Hide(condFrame.cond_aura_tip)
    _Hide(condFrame.cond_aura_incombat)
    _Hide(condFrame.cond_aura_outcombat)
    _Hide(condFrame.cond_aura_groupingDD)
    _Hide(condFrame.cond_aura_target_help)
    _Hide(condFrame.cond_aura_target_harm)
    _Hide(condFrame.cond_aura_onself)
    _Hide(condFrame.cond_aura_target_alive)
    _Hide(condFrame.cond_aura_target_dead)
    _Hide(condFrame.cond_aura_glow)
    _Hide(condFrame.cond_aura_greyscale)
    _Hide(condFrame.cond_aura_fade)
    _Hide(condFrame.cond_aura_fade_slider)
    _Hide(condFrame.cond_aura_distanceDD)
    _Hide(condFrame.cond_aura_unitTypeDD)
    _Hide(condFrame.cond_aura_power)
    _Hide(condFrame.cond_aura_power_comp)
    _Hide(condFrame.cond_aura_power_val)
    _Hide(condFrame.cond_aura_power_val_enter)
    _Hide(condFrame.cond_aura_hp_my)
    _Hide(condFrame.cond_aura_hp_tgt)
    _Hide(condFrame.cond_aura_hp_comp)
    _Hide(condFrame.cond_aura_hp_val)
    _Hide(condFrame.cond_aura_hp_val_enter)
    _Hide(condFrame.cond_aura_mine)
    _Hide(condFrame.cond_aura_others)
    _Hide(condFrame.cond_aura_trackpet)
    _Hide(condFrame.cond_aura_owner_tip)
    _Hide(condFrame.cond_aura_remaining_cb)
    _Hide(condFrame.cond_aura_remaining_comp)
    _Hide(condFrame.cond_aura_remaining_val)
    _Hide(condFrame.cond_aura_remaining_val_enter)
    _Hide(condFrame.cond_aura_stacks_cb)
    _Hide(condFrame.cond_aura_stacks_comp)
    _Hide(condFrame.cond_aura_stacks_val)
    _Hide(condFrame.cond_aura_stacks_val_enter)
    _Hide(condFrame.cond_aura_text_time)
    _Hide(condFrame.cond_aura_text_stack)
    _Hide(condFrame.cond_aura_text_time_override)
    _Hide(condFrame.cond_aura_text_stack_override)
    _Hide(condFrame.cond_aura_text_override_note)
    _Hide(condFrame.cond_aura_cp_cb)
    _Hide(condFrame.cond_aura_cp_comp)
    _Hide(condFrame.cond_aura_cp_val)
    _Hide(condFrame.cond_aura_cp_val_enter)
    _Hide(condFrame.cond_aura_weaponDD)
    _Hide(condFrame.cond_aura_formDD)
    _Hide(condFrame.cond_aura_class_note)

    _Hide(condFrame.cond_item_where_equipped)
    _Hide(condFrame.cond_item_where_bag)
    _Hide(condFrame.cond_item_where_missing)
    _Hide(condFrame.cond_item_inv_trinket1)
    _Hide(condFrame.cond_item_inv_trinket2)
    _Hide(condFrame.cond_item_inv_trinket_first)
    _Hide(condFrame.cond_item_inv_trinket_both)
    _Hide(condFrame.cond_item_inv_wep_mainhand)
    _Hide(condFrame.cond_item_inv_wep_offhand)
    _Hide(condFrame.cond_item_inv_wep_ranged)
    _Hide(condFrame.cond_item_inv_wep_ammo)
    _Hide(condFrame.cond_item_incombat)
    _Hide(condFrame.cond_item_outcombat)
    _Hide(condFrame.cond_item_groupingDD)
    _Hide(condFrame.cond_item_notcd)
    _Hide(condFrame.cond_item_oncd)
    _Hide(condFrame.cond_item_target_help)
    _Hide(condFrame.cond_item_target_harm)
    _Hide(condFrame.cond_item_target_self)
    _Hide(condFrame.cond_item_target_alive)
    _Hide(condFrame.cond_item_target_dead)
    _Hide(condFrame.cond_item_glow)
    _Hide(condFrame.cond_item_greyscale)
    _Hide(condFrame.cond_item_fade)
    _Hide(condFrame.cond_item_fade_slider)
    _Hide(condFrame.cond_item_text_time)
    _Hide(condFrame.cond_item_text_time_override)
    _Hide(condFrame.cond_item_text_override_note)
    _Hide(condFrame.cond_item_enchant)
    _Hide(condFrame.cond_item_text_enchant)
    _Hide(condFrame.cond_item_stacks_cb)
    _Hide(condFrame.cond_item_stacks_comp)
    _Hide(condFrame.cond_item_stacks_val)
    _Hide(condFrame.cond_item_stacks_val_enter)
    _Hide(condFrame.cond_item_text_stack)
    _Hide(condFrame.cond_item_power)
    _Hide(condFrame.cond_item_power_comp)
    _Hide(condFrame.cond_item_power_val)
    _Hide(condFrame.cond_item_power_val_enter)
    _Hide(condFrame.cond_item_hp_my)
    _Hide(condFrame.cond_item_hp_tgt)
    _Hide(condFrame.cond_item_hp_comp)
    _Hide(condFrame.cond_item_hp_val)
    _Hide(condFrame.cond_item_hp_val_enter)
    _Hide(condFrame.cond_item_remaining_cb)
    _Hide(condFrame.cond_item_remaining_comp)
    _Hide(condFrame.cond_item_remaining_val)
    _Hide(condFrame.cond_item_remaining_val_enter)
    _Hide(condFrame.cond_item_cp_cb)
    _Hide(condFrame.cond_item_cp_comp)
    _Hide(condFrame.cond_item_cp_val)
    _Hide(condFrame.cond_item_cp_val_enter)
    _Hide(condFrame.cond_item_weaponDD)
    _Hide(condFrame.cond_item_class_note)
    _Hide(condFrame.cond_item_formDD)
    _Hide(condFrame.cond_item_distanceDD)
    _Hide(condFrame.cond_item_unitTypeDD)
    _Hide(condFrame.cond_item_clickable)

    -- AURA (Buff/Debuff)
  else
    if ShowSeparatorsForType then ShowSeparatorsForType("aura") end

    local _acRef = _G["AuraCond_RefreshFromDB"]
    if _acRef then
      _acRef("aura")
    end
    local _vcRef = _G["VfxCond_RefreshFromDB"]
    if _vcRef then
      _vcRef("aura")
    end

    -- small helpers used in this branch only
    local function _enableDD(dd)
      if not dd then
        return
      end
      local btn = _G[dd:GetName() .. "Button"]
      local txt = _G[dd:GetName() .. "Text"]
      if btn and btn.Enable then
        btn:Enable()
      end
      if txt and txt.SetTextColor then
        txt:SetTextColor(1, 0.82, 0)
      end
    end
    local function _hideRemInputs()
      condFrame.cond_aura_remaining_comp:Hide()
      condFrame.cond_aura_remaining_val:Hide()
      condFrame.cond_aura_remaining_val_enter:Hide()
    end

    condFrame.cond_aura_found:Show()
    condFrame.cond_aura_missing:Show()
    if condFrame.cond_aura_tip then
      condFrame.cond_aura_tip:Show()
    end
    if condFrame.cond_aura_owner_tip then
      condFrame.cond_aura_owner_tip:Show()
    end
    condFrame.cond_aura_incombat:Show()
    condFrame.cond_aura_outcombat:Show()
    condFrame.cond_aura_target_help:Show()
    condFrame.cond_aura_target_harm:Show()
    condFrame.cond_aura_onself:Show()
    condFrame.cond_aura_sound_ongain_cb:Show()
    condFrame.cond_aura_sound_ongain_dd:Show()
    condFrame.cond_aura_sound_onfade_cb:Show()
    condFrame.cond_aura_sound_onfade_dd:Show()
    condFrame.cond_aura_glow:Show()
    condFrame.cond_aura_greyscale:Show()
    condFrame.cond_aura_fade:Show()

    -- mode
    local amode = (c.aura and c.aura.mode) or "found"
    condFrame.cond_aura_found:SetChecked(amode == "found" or amode == "both")
    condFrame.cond_aura_missing:SetChecked(amode == "missing" or amode == "both")

    -- combat flags (independent)
    local aIn, aOut
    if c.aura and (c.aura.inCombat ~= nil or c.aura.outCombat ~= nil) then
      aIn = c.aura.inCombat and true or false
      aOut = c.aura.outCombat and true or false
    else
      local cm = c.aura and c.aura.combat or nil
      if cm == "in" then
        aIn, aOut = true, false
      elseif cm == "out" then
        aIn, aOut = false, true
      else
        aIn, aOut = true, true
      end
    end
    condFrame.cond_aura_incombat:SetChecked(aIn)
    condFrame.cond_aura_outcombat:SetChecked(aOut)

    if condFrame.cond_aura_groupingDD then
      condFrame.cond_aura_groupingDD:Show()
      local gm = _DeriveGroupingMode(c.aura)
      local txt
      if gm == "any" then
        txt = "Any"
      elseif gm == "nogroup" then
        txt = "Not in group"
      elseif gm == "party" then
        txt = "In party"
      elseif gm == "raid" then
        txt = "In raid"
      elseif gm == "partyraid" then
        txt = "In party or raid"
      else
        txt = "Group state"
      end

      if gm == nil then
        if UIDropDownMenu_SetSelectedValue then pcall(UIDropDownMenu_SetSelectedValue, condFrame.cond_aura_groupingDD, "__default") end
      else
        if UIDropDownMenu_SetSelectedValue then pcall(UIDropDownMenu_SetSelectedValue, condFrame.cond_aura_groupingDD, gm) end
      end
      if UIDropDownMenu_SetText then pcall(UIDropDownMenu_SetText, txt, condFrame.cond_aura_groupingDD) end
      if _GoldifyDD then _GoldifyDD(condFrame.cond_aura_groupingDD) end
    end

    -- target read
    local th = (c.aura and c.aura.targetHelp) and true or false
    local tm = (c.aura and c.aura.targetHarm) and true or false
    local ts = (c.aura and c.aura.targetSelf) and true or false

    -- TARGET STATUS
    local taa = (c.aura and c.aura.targetAlive) == true
    local tad = (c.aura and c.aura.targetDead) == true
    condFrame.cond_aura_target_alive:SetChecked(taa)
    condFrame.cond_aura_target_dead:SetChecked(tad)
    if condFrame.cond_aura_target_alive then
      condFrame.cond_aura_target_alive:Show()
    end
    if condFrame.cond_aura_target_dead then
      condFrame.cond_aura_target_dead:Show()
    end

    -- Normalize: Self is exclusive vs Help/Harm
    if ts then
      th, tm = false, false
    end

    -- If somehow all false (old state), default to Self-only
    if (not th) and (not tm) and (not ts) then
      ts = true
      if c.aura then
        c.aura.targetSelf = true
        c.aura.targetHelp = false
        c.aura.targetHarm = false
      end
    end

    -- derived target state
    local isSelfOnly = ts and (not th) and (not tm)
    local isHelpOrHarm = (th or tm) and (not ts)

    -- reflect target
    condFrame.cond_aura_target_help:SetChecked(th)
    condFrame.cond_aura_target_harm:SetChecked(tm)
    condFrame.cond_aura_onself:SetChecked(ts)

    local isTrackPetActive = (_IsHunterOrWarlock and _IsHunterOrWarlock() and c.aura and c.aura.trackpet) and true or false
    if condFrame.cond_aura_onself and condFrame.cond_aura_onself.text and condFrame.cond_aura_onself.text.SetText then
      if isTrackPetActive then
        condFrame.cond_aura_onself.text:SetText("Target (Any)")
      else
        condFrame.cond_aura_onself.text:SetText("On player (self)")
      end
    end

    -- === TARGET DISTANCE & TYPE (Aura) ===
    if condFrame.cond_aura_distanceDD then
      condFrame.cond_aura_distanceDD:Show()
      condFrame.cond_aura_unitTypeDD:Show()

      local a = c.aura or {}

      local function _RestoreAuraDD(dd, val, placeholder)
        if not dd then
          return
        end
        if val and val ~= "" then
          if UIDropDownMenu_SetSelectedValue then
            pcall(UIDropDownMenu_SetSelectedValue, dd, val)
          end
          if UIDropDownMenu_SetText then
            pcall(UIDropDownMenu_SetText, val, dd)
          end
          _GoldifyDD(dd)
        else
          if UIDropDownMenu_SetSelectedValue then
            pcall(UIDropDownMenu_SetSelectedValue, dd, nil)
          end
          if UIDropDownMenu_SetText then
            pcall(UIDropDownMenu_SetText, placeholder, dd)
          end
          _WhiteifyDDText(dd)
        end
      end

      -- Always clear & hard-disable Distance for auras
      if a then
        a.targetDistance = nil
      end
      _RestoreAuraDD(condFrame.cond_aura_distanceDD, nil, "Distance")
      _SetDDEnabled(condFrame.cond_aura_distanceDD, false, "Distance")

      -- UnitType remain usable
      _RestoreAuraDD(condFrame.cond_aura_unitTypeDD, a.targetUnitType, "Unit type")

      -- Self-only target: UnitType are meaningless
      local isSelfOnly = (a.targetSelf == true)
      if isSelfOnly then
        a.targetUnitType = nil

        _SetDDEnabled(condFrame.cond_aura_unitTypeDD, false, "Unit type")
      else
        _SetDDEnabled(condFrame.cond_aura_unitTypeDD, true, "Unit type")
      end
    end

    condFrame.cond_aura_glow:SetChecked((c.aura and c.aura.glow) or false)
    condFrame.cond_aura_greyscale:SetChecked((c.aura and c.aura.greyscale) or false)
    condFrame.cond_aura_fade:SetChecked((c.aura and c.aura.fade) or false)
    if (c.aura and c.aura.fade) then
      local fadeAlpha = tonumber(c.aura.fadeAlpha) or 0
      if fadeAlpha < 0 then fadeAlpha = 0 end
      if fadeAlpha > 1 then fadeAlpha = 1 end
      condFrame.cond_aura_fade_slider:SetText(tostring(math.floor((fadeAlpha * 100) + 0.5)))
      condFrame.cond_aura_fade_slider:Show()
    else
      condFrame.cond_aura_fade_slider:Hide()
    end

    local auraSoundGainOn = (c.aura and c.aura.soundOnGainEnabled) == true
    local auraSoundFadeOn = (c.aura and c.aura.soundOnFadeEnabled) == true
    local auraSoundGain = (c.aura and c.aura.soundOnGain) or nil
    local auraSoundFade = (c.aura and c.aura.soundOnFade) or nil
    condFrame.cond_aura_sound_ongain_cb:SetChecked(auraSoundGainOn)
    condFrame.cond_aura_sound_onfade_cb:SetChecked(auraSoundFadeOn)
    DoiteEdit_InitSoundDropdown(condFrame.cond_aura_sound_ongain_dd, "aura", "soundOnGain", auraSoundGain)
    DoiteEdit_InitSoundDropdown(condFrame.cond_aura_sound_onfade_dd, "aura", "soundOnFade", auraSoundFade)
    DoiteEdit_EnableCheck(condFrame.cond_aura_sound_ongain_cb)
    DoiteEdit_EnableCheck(condFrame.cond_aura_sound_onfade_cb)
    DoiteEdit_SetDropdownInteractive(condFrame.cond_aura_sound_ongain_dd, auraSoundGainOn)
    DoiteEdit_SetDropdownInteractive(condFrame.cond_aura_sound_onfade_dd, auraSoundFadeOn)

    local isBuff = (data.type == "Buff")

    -- Combo points / class-specific note / weapon filter
    local isRogueOrDruid = _IsRogueOrDruid and _IsRogueOrDruid() or false
    local isWPS = _IsWarriorPaladinShaman()

    if condFrame.cond_aura_weaponDD then
      condFrame.cond_aura_weaponDD:Hide()
    end

    if isRogueOrDruid then
      condFrame.cond_aura_cp_cb:Show()
      if condFrame.cond_aura_class_note then
        condFrame.cond_aura_class_note:Hide()
      end

      local cpOn = (c.aura and c.aura.cpEnabled) and true or false
      condFrame.cond_aura_cp_cb:SetChecked(cpOn)
      if cpOn then
        condFrame.cond_aura_cp_comp:Show()
        condFrame.cond_aura_cp_val:Show()
        condFrame.cond_aura_cp_val_enter:Show()
        local comp = (c.aura and c.aura.cpComp) or ""
        UIDropDownMenu_SetSelectedValue(condFrame.cond_aura_cp_comp, comp)
        UIDropDownMenu_SetText(comp, condFrame.cond_aura_cp_comp)
        _GoldifyDD(condFrame.cond_aura_cp_comp)
        condFrame.cond_aura_cp_val:SetText(tostring((c.aura and c.aura.cpVal) or 0))
      else
        condFrame.cond_aura_cp_comp:Hide()
        condFrame.cond_aura_cp_val:Hide()
        condFrame.cond_aura_cp_val_enter:Hide()
      end

    elseif isWPS and condFrame.cond_aura_weaponDD then
      -- Warrior / Paladin / Shaman: weapon / fighting-style dropdown instead of CPs
      condFrame.cond_aura_cp_cb:Hide()
      condFrame.cond_aura_cp_comp:Hide()
      condFrame.cond_aura_cp_val:Hide()
      condFrame.cond_aura_cp_val_enter:Hide()
      if condFrame.cond_aura_class_note then
        condFrame.cond_aura_class_note:Hide()
      end

      condFrame.cond_aura_weaponDD:Show()
      InitWeaponDropdown(condFrame.cond_aura_weaponDD, data, "aura")

    else
      condFrame.cond_aura_cp_cb:Hide()
      condFrame.cond_aura_cp_comp:Hide()
      condFrame.cond_aura_cp_val:Hide()
      condFrame.cond_aura_cp_val_enter:Hide()
      if condFrame.cond_aura_class_note then
        if _IsHunterOrWarlock and _IsHunterOrWarlock() then
          condFrame.cond_aura_class_note:Hide()
        else
          condFrame.cond_aura_class_note:SetText("No class-specific option added for your class.")
          condFrame.cond_aura_class_note:Show()
        end
      end
    end

    if condFrame.cond_aura_trackpet then
      local isHW = _IsHunterOrWarlock and _IsHunterOrWarlock() or false
      if isHW then
        condFrame.cond_aura_trackpet:Show()
        condFrame.cond_aura_trackpet:SetChecked((c.aura and c.aura.trackpet) and true or false)
      else
        condFrame.cond_aura_trackpet:Hide()
        condFrame.cond_aura_trackpet:SetChecked(false)
      end
    end

    -- Row 8: HP selector (mutually exclusive)
    condFrame.cond_aura_hp_my:Show()
    condFrame.cond_aura_hp_tgt:Show()
    local hpModeA = c.aura and c.aura.hpMode or nil
    condFrame.cond_aura_hp_my:SetChecked(hpModeA == "my")
    condFrame.cond_aura_hp_tgt:SetChecked(hpModeA == "target")
    if hpModeA == "my" or hpModeA == "target" then
      condFrame.cond_aura_hp_comp:Show()
      condFrame.cond_aura_hp_val:Show()
      condFrame.cond_aura_hp_val_enter:Show()
      local comp = (c.aura and c.aura.hpComp) or ""
      UIDropDownMenu_SetSelectedValue(condFrame.cond_aura_hp_comp, comp)
      UIDropDownMenu_SetText(comp, condFrame.cond_aura_hp_comp)
      _GoldifyDD(condFrame.cond_aura_hp_comp)
      condFrame.cond_aura_hp_val:SetText(tostring((c.aura and c.aura.hpVal) or 0))
    else
      condFrame.cond_aura_hp_comp:Hide()
      condFrame.cond_aura_hp_val:Hide()
      condFrame.cond_aura_hp_val_enter:Hide()
    end

    -- Aura owner flags ("My Aura" / "Others Aura") – buff and debuff identical.
    local function _AO_SetEnabled(cb, enabled, clearWhenDisabling)
      if not cb then
        return
      end
      if type(_SetAuraCheckEnabled) == "function" then
        _SetAuraCheckEnabled(cb, enabled, clearWhenDisabling)
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

    local onlyMine = (c.aura and c.aura.onlyMine) and true or false
    local onlyOthers = (c.aura and c.aura.onlyOthers) and true or false

    -- Sanitize DB: if both are somehow true, keep "My Aura" only.
    if onlyMine and onlyOthers then
      onlyOthers = false
      if c.aura then
        c.aura.onlyOthers = nil
      end
    end

    -- If target is "On player (self)", ownership is meaningless.
    local lockOwnerOnSelf = false
    if isTrackPetActive then
      lockOwnerOnSelf = true
    elseif isSelfOnly then
      lockOwnerOnSelf = true
    end

    if amode == "found" or amode == "both" then
      if lockOwnerOnSelf then
        -- Grey out / unselectable / uncheck "My Aura" + "Others Aura"
        if condFrame.cond_aura_mine then
          condFrame.cond_aura_mine:Show()
          condFrame.cond_aura_mine:SetChecked(false)
          _AO_SetEnabled(condFrame.cond_aura_mine, false, true)
        end
        if condFrame.cond_aura_others then
          condFrame.cond_aura_others:Show()
          condFrame.cond_aura_others:SetChecked(false)
          _AO_SetEnabled(condFrame.cond_aura_others, false, true)
        end
        if c.aura then
          c.aura.onlyMine = nil
          c.aura.onlyOthers = nil
        end
      else
        -- Owner row visible for FOUND. Always enabled.
        if condFrame.cond_aura_mine then
          condFrame.cond_aura_mine:Show()
          condFrame.cond_aura_mine:SetChecked(onlyMine)
          _AO_SetEnabled(condFrame.cond_aura_mine, true, true)
        end

        if condFrame.cond_aura_others then
          condFrame.cond_aura_others:Show()
          condFrame.cond_aura_others:SetChecked(onlyOthers)
          _AO_SetEnabled(condFrame.cond_aura_others, true, true)
        end
      end

    elseif amode == "missing" then
      -- Missing: keep row visible but disable + clear flags (always).
      if condFrame.cond_aura_mine then
        condFrame.cond_aura_mine:Show()
        condFrame.cond_aura_mine:SetChecked(false)
        _AO_SetEnabled(condFrame.cond_aura_mine, false, true)
      end

      if condFrame.cond_aura_others then
        condFrame.cond_aura_others:Show()
        condFrame.cond_aura_others:SetChecked(false)
        _AO_SetEnabled(condFrame.cond_aura_others, false, true)
      end

      if c.aura then
        c.aura.onlyMine = nil
        c.aura.onlyOthers = nil
      end

    else
      -- No aura mode selected → hide owner controls.
      if condFrame.cond_aura_mine then
        condFrame.cond_aura_mine:Hide()
      end
      if condFrame.cond_aura_others then
        condFrame.cond_aura_others:Hide()
      end
    end

    -- After setting the owner flags from DB, update Remaining/Text grey state.
    if AuraOwner_UpdateDependentChecks then
      AuraOwner_UpdateDependentChecks()
    end

    -- Row 10: Text flags (Text: stack + Text: remaining)
    if amode == "found" or amode == "both" then
      -- === Text: Stack counter ===
      condFrame.cond_aura_text_stack:Show()
      DoiteEdit_EnableCheck(condFrame.cond_aura_text_stack)
      condFrame.cond_aura_text_stack:SetChecked((c.aura and c.aura.textStackCounter) or false)

      -- === Text: Time remaining ===
      condFrame.cond_aura_text_time:Show()

      if isTrackPetActive or isSelfOnly then
        -- Pet-tracking (or On Player self): user may freely toggle Text: Remaining
        DoiteEdit_EnableCheck(condFrame.cond_aura_text_time)
        condFrame.cond_aura_text_time:SetChecked((c.aura and c.aura.textTimeRemaining) or false)

      elseif isHelpOrHarm then
        if onlyMine then
          -- My Aura checked -> user controls Text: Remaining
          DoiteEdit_EnableCheck(condFrame.cond_aura_text_time)
          condFrame.cond_aura_text_time:SetChecked((c.aura and c.aura.textTimeRemaining) or false)
        else
          -- My Aura NOT checked -> Text: Remaining forced OFF and greyed
          if c.aura and c.aura.textTimeRemaining then
            c.aura.textTimeRemaining = false
          end
          condFrame.cond_aura_text_time:SetChecked(false)
          DoiteEdit_DisableCheck(condFrame.cond_aura_text_time)
        end
      else
        -- Fallback: disable
        DoiteEdit_DisableCheck(condFrame.cond_aura_text_time)
        condFrame.cond_aura_text_time:SetChecked(false)
        if c.aura and c.aura.textTimeRemaining then
          c.aura.textTimeRemaining = false
        end
      end

    elseif amode == "missing" then
      -- Aura missing: keep text options visible but disabled and cleared
      condFrame.cond_aura_text_stack:Show()
      condFrame.cond_aura_text_time:Show()

      DoiteEdit_DisableCheck(condFrame.cond_aura_text_stack)
      DoiteEdit_DisableCheck(condFrame.cond_aura_text_time)

      condFrame.cond_aura_text_stack:SetChecked(false)
      condFrame.cond_aura_text_time:SetChecked(false)

      if c.aura then
        c.aura.textStackCounter = false
        c.aura.textTimeRemaining = false
      end
    else
      condFrame.cond_aura_text_time:Hide()
      condFrame.cond_aura_text_stack:Hide()
    end

    if condFrame.cond_item_text_time_override then
      condFrame.cond_item_text_time_override:Hide()
    end
    if condFrame.cond_item_text_override_note then
      condFrame.cond_item_text_override_note:Hide()
    end

    do
      local showRemOv = (condFrame.cond_aura_text_time and condFrame.cond_aura_text_time:IsShown() and condFrame.cond_aura_text_time:GetChecked()) and true or false
      local showStackOv = (condFrame.cond_aura_text_stack and condFrame.cond_aura_text_stack:IsShown() and condFrame.cond_aura_text_stack:GetChecked()) and true or false
      local showAnyOv = showRemOv or showStackOv

      if condFrame.cond_aura_text_time_override then
        if showRemOv then
          condFrame.cond_aura_text_time_override:Show()
          condFrame.cond_aura_text_time_override:SetText((c.aura and c.aura.remOverride) or "")
        else
          condFrame.cond_aura_text_time_override:Hide()
        end
      end

      if condFrame.cond_aura_text_stack_override then
        if showStackOv then
          condFrame.cond_aura_text_stack_override:Show()
          condFrame.cond_aura_text_stack_override:SetText((c.aura and c.aura.stackOverride) or "")
        else
          condFrame.cond_aura_text_stack_override:Hide()
        end
      end

      if condFrame.cond_aura_text_override_note then
        if showAnyOv then
          condFrame.cond_aura_text_override_note:Show()
        else
          condFrame.cond_aura_text_override_note:Hide()
        end
      end
    end

    -- Row 11: Aura Power (like ability)
    condFrame.cond_aura_power:Show()
    local pOn = (c.aura and c.aura.powerEnabled) and true or false
    condFrame.cond_aura_power:SetChecked(pOn)
    if pOn then
      condFrame.cond_aura_power_comp:Show()
      condFrame.cond_aura_power_val:Show()
      condFrame.cond_aura_power_val_enter:Show()
      local comp = (c.aura and c.aura.powerComp) or ""
      UIDropDownMenu_SetSelectedValue(condFrame.cond_aura_power_comp, comp)
      UIDropDownMenu_SetText(comp, condFrame.cond_aura_power_comp)
      _GoldifyDD(condFrame.cond_aura_power_comp)
      condFrame.cond_aura_power_val:SetText(tostring((c.aura and c.aura.powerVal) or 0))
    else
      condFrame.cond_aura_power_comp:Hide()
      condFrame.cond_aura_power_val:Hide()
      condFrame.cond_aura_power_val_enter:Hide()
    end

    -- Form dropdown for aura
    local choices = (function()
      local _, cls = UnitClass("player")
      cls = cls and string.upper(cls) or ""
      return (cls == "WARRIOR" or cls == "ROGUE" or cls == "DRUID" or cls == "PRIEST" or cls == "PALADIN")
    end)()

    if condFrame.cond_ability_formDD then
      condFrame.cond_ability_formDD:Hide()
    end

    if choices and condFrame.cond_aura_formDD then
      condFrame.cond_aura_formDD:Show()
      _CD(condFrame.cond_aura_formDD)
      InitFormDropdown(condFrame.cond_aura_formDD, data, "aura")
      local v = c.aura and c.aura.form
      if v and v ~= "All" and v ~= "" then
        UIDropDownMenu_SetSelectedValue(condFrame.cond_aura_formDD, v)
        UIDropDownMenu_SetText(v, condFrame.cond_aura_formDD)
        _GoldifyDD(condFrame.cond_aura_formDD)
      else
        UIDropDownMenu_SetText("Select form", condFrame.cond_aura_formDD)
        _GoldifyDD(condFrame.cond_aura_formDD)
      end
    elseif condFrame.cond_aura_formDD then
      condFrame.cond_aura_formDD:Hide()
      _CD(condFrame.cond_aura_formDD)
    end

    -- Remaining (Row 8): behavior depends on target + "My Aura"
    local aRemEnabled = (c.aura and c.aura.remainingEnabled) and true or false

    if amode == "found" or amode == "both" then
      condFrame.cond_aura_remaining_cb:Show()
      if condFrame.cond_aura_remaining_cb.text then
        condFrame.cond_aura_remaining_cb.text:SetText("Remaining")
      end

      if isTrackPetActive or isSelfOnly then
        -- Pet-tracking (or On Player self): user can freely toggle Remaining
        DoiteEdit_EnableCheck(condFrame.cond_aura_remaining_cb)
        condFrame.cond_aura_remaining_cb:SetChecked(aRemEnabled)

      elseif isHelpOrHarm then
        -- Help/Harm target: apply My Aura rules
        if onlyMine then
          -- My Aura checked -> user controls Remaining
          DoiteEdit_EnableCheck(condFrame.cond_aura_remaining_cb)
          condFrame.cond_aura_remaining_cb:SetChecked(aRemEnabled)
        else
          -- My Aura NOT checked -> Remaining disabled and cleared
          if c.aura and c.aura.remainingEnabled then
            c.aura.remainingEnabled = false
          end
          aRemEnabled = false
          condFrame.cond_aura_remaining_cb:SetChecked(false)
          DoiteEdit_DisableCheck(condFrame.cond_aura_remaining_cb)
        end
      else
        -- Fallback: disable
        DoiteEdit_DisableCheck(condFrame.cond_aura_remaining_cb)
        condFrame.cond_aura_remaining_cb:SetChecked(false)
        if c.aura then
          c.aura.remainingEnabled = false
        end
      end

      -- Inputs follow the *final* enabled flag
      local remOn = (c.aura and c.aura.remainingEnabled) and true or false
      if remOn then
        condFrame.cond_aura_remaining_comp:Show()
        condFrame.cond_aura_remaining_val:Show()
        condFrame.cond_aura_remaining_val_enter:Show()
        _enableDD(condFrame.cond_aura_remaining_comp)

        local comp = (c.aura and c.aura.remainingComp) or ""
        UIDropDownMenu_SetSelectedValue(condFrame.cond_aura_remaining_comp, comp)
        UIDropDownMenu_SetText(comp, condFrame.cond_aura_remaining_comp)
        _GoldifyDD(condFrame.cond_aura_remaining_comp)
        condFrame.cond_aura_remaining_val:SetText(tostring((c.aura and c.aura.remainingVal) or 0))
      else
        _hideRemInputs()
      end

    elseif amode == "missing" then
      -- Aura missing: keep Remaining visible but disabled and cleared
      condFrame.cond_aura_remaining_cb:Show()
      if condFrame.cond_aura_remaining_cb.text then
        condFrame.cond_aura_remaining_cb.text:SetText("Remaining")
      end

      DoiteEdit_DisableCheck(condFrame.cond_aura_remaining_cb)
      condFrame.cond_aura_remaining_cb:SetChecked(false)
      if c.aura then
        c.aura.remainingEnabled = false
      end
      _hideRemInputs()
    else
      condFrame.cond_aura_remaining_cb:Hide()
      _hideRemInputs()
    end

    -- Stacks row: enabled only when FOUND, greyed when MISSING
    local aStacksEnabled = (c.aura and c.aura.stacksEnabled) and true or false
    condFrame.cond_aura_stacks_cb:SetChecked(aStacksEnabled)
    if amode == "found" or amode == "both" then
      condFrame.cond_aura_stacks_cb:Show()
      DoiteEdit_EnableCheck(condFrame.cond_aura_stacks_cb)
      if aStacksEnabled then
        condFrame.cond_aura_stacks_comp:Show()
        condFrame.cond_aura_stacks_val:Show()
        condFrame.cond_aura_stacks_val_enter:Show()
        local comp = (c.aura and c.aura.stacksComp) or ""
        UIDropDownMenu_SetSelectedValue(condFrame.cond_aura_stacks_comp, comp)
        UIDropDownMenu_SetText(comp, condFrame.cond_aura_stacks_comp)
        _GoldifyDD(condFrame.cond_aura_stacks_comp)
        condFrame.cond_aura_stacks_val:SetText(tostring((c.aura and c.aura.stacksVal) or 0))
      else
        condFrame.cond_aura_stacks_comp:Hide()
        condFrame.cond_aura_stacks_val:Hide()
        condFrame.cond_aura_stacks_val_enter:Hide()
      end
    else
      -- Aura missing or no mode: show but disabled/cleared for MISSING, hide for nil-mode
      if amode == "missing" then
        condFrame.cond_aura_stacks_cb:Show()
        DoiteEdit_DisableCheck(condFrame.cond_aura_stacks_cb)
        condFrame.cond_aura_stacks_cb:SetChecked(false)
        if c.aura then
          c.aura.stacksEnabled = false
        end
      else
        condFrame.cond_aura_stacks_cb:Hide()
      end
      condFrame.cond_aura_stacks_comp:Hide()
      condFrame.cond_aura_stacks_val:Hide()
      condFrame.cond_aura_stacks_val_enter:Hide()
    end

    -- Hide all ability & item controls (unchanged)
    condFrame.cond_ability_usable:Hide()
    condFrame.cond_ability_notcd:Hide()
    condFrame.cond_ability_oncd:Hide()
    condFrame.cond_ability_incombat:Hide()
    condFrame.cond_ability_outcombat:Hide()
    if condFrame.cond_ability_groupingDD then
      condFrame.cond_ability_groupingDD:Hide()
    end
    condFrame.cond_ability_target_help:Hide()
    condFrame.cond_ability_target_harm:Hide()
    condFrame.cond_ability_target_self:Hide()
    condFrame.cond_ability_power:Hide()
    condFrame.cond_ability_power_comp:Hide()
    condFrame.cond_ability_power_val:Hide()
    condFrame.cond_ability_power_val_enter:Hide()
    condFrame.cond_ability_glow:Hide()
    condFrame.cond_ability_greyscale:Hide()
    condFrame.cond_ability_fade:Hide()
    condFrame.cond_ability_fade_slider:Hide()
    condFrame.cond_ability_slider:Hide()
    condFrame.cond_ability_slider_dir:Hide()
    if condFrame.cond_ability_slider_time then
      condFrame.cond_ability_slider_time:Hide()
    end
    if condFrame.cond_ability_slider_time_label then
      condFrame.cond_ability_slider_time_label:Hide()
    end
    if condFrame.cond_ability_slider_time_slider then
      condFrame.cond_ability_slider_time_slider:Hide()
    end
    if condFrame.cond_ability_slider_time_hintline then
      condFrame.cond_ability_slider_time_hintline:Hide()
    end
    if condFrame.cond_ability_slider_bottom_sep then
      condFrame.cond_ability_slider_bottom_sep:Hide()
    end
    condFrame.cond_ability_remaining_cb:Hide()
    condFrame.cond_ability_remaining_comp:Hide()
    condFrame.cond_ability_remaining_val:Hide()
    condFrame.cond_ability_remaining_val_enter:Hide()
    if condFrame.cond_ability_text_time then
      condFrame.cond_ability_text_time:Hide()
    end
    if condFrame.cond_ability_target_alive then
      condFrame.cond_ability_target_alive:Hide()
    end
    if condFrame.cond_ability_target_dead then
      condFrame.cond_ability_target_dead:Hide()
    end

    if condFrame.cond_ability_hp_my then
      condFrame.cond_ability_hp_my:Hide()
    end
    if condFrame.cond_ability_hp_tgt then
      condFrame.cond_ability_hp_tgt:Hide()
    end
    if condFrame.cond_ability_hp_comp then
      condFrame.cond_ability_hp_comp:Hide()
    end
    if condFrame.cond_ability_hp_val then
      condFrame.cond_ability_hp_val:Hide()
    end
    if condFrame.cond_ability_hp_val_enter then
      condFrame.cond_ability_hp_val_enter:Hide()
    end

    if condFrame.cond_ability_cp_cb then
      condFrame.cond_ability_cp_cb:Hide()
    end
    if condFrame.cond_ability_cp_comp then
      condFrame.cond_ability_cp_comp:Hide()
    end
    if condFrame.cond_ability_cp_val then
      condFrame.cond_ability_cp_val:Hide()
    end
    if condFrame.cond_ability_cp_val_enter then
      condFrame.cond_ability_cp_val_enter:Hide()
    end
    if condFrame.cond_ability_weaponDD then
      condFrame.cond_ability_weaponDD:Hide()
    end
    if condFrame.cond_ability_class_note then
      condFrame.cond_ability_class_note:Hide()
    end

    if condFrame.cond_ability_slider_glow then
      condFrame.cond_ability_slider_glow:Hide()
    end
    if condFrame.cond_ability_slider_grey then
      condFrame.cond_ability_slider_grey:Hide()
    end

    if condFrame.cond_item_where_equipped then
      condFrame.cond_item_where_equipped:Hide()
    end
    if condFrame.cond_item_where_bag then
      condFrame.cond_item_where_bag:Hide()
    end
    if condFrame.cond_item_where_missing then
      condFrame.cond_item_where_missing:Hide()
    end
    if condFrame.cond_item_notcd then
      condFrame.cond_item_notcd:Hide()
    end
    if condFrame.cond_item_oncd then
      condFrame.cond_item_oncd:Hide()
    end
    if condFrame.cond_item_incombat then
      condFrame.cond_item_incombat:Hide()
    end
    if condFrame.cond_item_outcombat then
      condFrame.cond_item_outcombat:Hide()
    end
    if condFrame.cond_item_groupingDD then
      condFrame.cond_item_groupingDD:Hide()
    end
    if condFrame.cond_item_target_help then
      condFrame.cond_item_target_help:Hide()
    end
    if condFrame.cond_item_target_harm then
      condFrame.cond_item_target_harm:Hide()
    end
    if condFrame.cond_item_target_self then
      condFrame.cond_item_target_self:Hide()
    end
    if condFrame.cond_item_glow then
      condFrame.cond_item_glow:Hide()
    end
    if condFrame.cond_item_greyscale then
      condFrame.cond_item_greyscale:Hide()
    end
    if condFrame.cond_item_fade then
      condFrame.cond_item_fade:Hide()
    end
    if condFrame.cond_item_fade_slider then
      condFrame.cond_item_fade_slider:Hide()
    end
    if condFrame.cond_item_text_time then
      condFrame.cond_item_text_time:Hide()
    end
    if condFrame.cond_item_enchant then
      condFrame.cond_item_enchant:Hide()
    end
    if condFrame.cond_item_text_enchant then
      condFrame.cond_item_text_enchant:Hide()
    end
    if condFrame.cond_item_power then
      condFrame.cond_item_power:Hide()
    end
    if condFrame.cond_item_power_comp then
      condFrame.cond_item_power_comp:Hide()
    end
    if condFrame.cond_item_power_val then
      condFrame.cond_item_power_val:Hide()
    end
    if condFrame.cond_item_power_val_enter then
      condFrame.cond_item_power_val_enter:Hide()
    end
    if condFrame.cond_item_hp_my then
      condFrame.cond_item_hp_my:Hide()
    end
    if condFrame.cond_item_hp_tgt then
      condFrame.cond_item_hp_tgt:Hide()
    end
    if condFrame.cond_item_hp_comp then
      condFrame.cond_item_hp_comp:Hide()
    end
    if condFrame.cond_item_hp_val then
      condFrame.cond_item_hp_val:Hide()
    end
    if condFrame.cond_item_hp_val_enter then
      condFrame.cond_item_hp_val_enter:Hide()
    end
    if condFrame.cond_item_remaining_cb then
      condFrame.cond_item_remaining_cb:Hide()
    end
    if condFrame.cond_item_remaining_comp then
      condFrame.cond_item_remaining_comp:Hide()
    end
    if condFrame.cond_item_remaining_val then
      condFrame.cond_item_remaining_val:Hide()
    end
    if condFrame.cond_item_remaining_val_enter then
      condFrame.cond_item_remaining_val_enter:Hide()
    end
    if condFrame.cond_item_cp_cb then
      condFrame.cond_item_cp_cb:Hide()
    end
    if condFrame.cond_item_cp_comp then
      condFrame.cond_item_cp_comp:Hide()
    end
    if condFrame.cond_item_cp_val then
      condFrame.cond_item_cp_val:Hide()
    end
    if condFrame.cond_item_cp_val_enter then
      condFrame.cond_item_cp_val_enter:Hide()
    end
    if condFrame.cond_item_formDD then
      condFrame.cond_item_formDD:Hide()
    end
    if condFrame.cond_item_inv_trinket1 then
      condFrame.cond_item_inv_trinket1:Hide()
    end
    if condFrame.cond_item_inv_trinket2 then
      condFrame.cond_item_inv_trinket2:Hide()
    end
    if condFrame.cond_item_inv_trinket_first then
      condFrame.cond_item_inv_trinket_first:Hide()
    end
    if condFrame.cond_item_inv_trinket_both then
      condFrame.cond_item_inv_trinket_both:Hide()
    end
    if condFrame.cond_item_inv_wep_mainhand then
      condFrame.cond_item_inv_wep_mainhand:Hide()
    end
    if condFrame.cond_item_inv_wep_offhand then
      condFrame.cond_item_inv_wep_offhand:Hide()
    end
    if condFrame.cond_item_inv_wep_ranged then
      condFrame.cond_item_inv_wep_ranged:Hide()
    end
    if condFrame.cond_item_inv_wep_ammo then
      condFrame.cond_item_inv_wep_ammo:Hide()
    end
    if condFrame.cond_item_class_note then
      condFrame.cond_item_class_note:Hide()
    end
    if condFrame.cond_item_target_alive then
      condFrame.cond_item_target_alive:Hide()
    end
    if condFrame.cond_item_target_dead then
      condFrame.cond_item_target_dead:Hide()
    end
    if condFrame.cond_item_weaponDD then
      condFrame.cond_item_weaponDD:Hide()
    end
    if condFrame.cond_item_clickable then
      condFrame.cond_item_clickable:Hide()
    end
    -- hide Item stacks row when not editing an item
    if condFrame.cond_item_stacks_cb then
      condFrame.cond_item_stacks_cb:Hide()
    end
    if condFrame.cond_item_text_stack then
      condFrame.cond_item_text_stack:Hide()
    end
    if condFrame.cond_item_stacks_comp then
      condFrame.cond_item_stacks_comp:Hide()
    end
    if condFrame.cond_item_stacks_val then
      condFrame.cond_item_stacks_val:Hide()
    end
    if condFrame.cond_item_stacks_val_enter then
      condFrame.cond_item_stacks_val_enter:Hide()
    end

    -- hide ability DDs when not editing an ability
    if condFrame.cond_ability_distanceDD then
      condFrame.cond_ability_distanceDD:Hide()
    end
    if condFrame.cond_ability_unitTypeDD then
      condFrame.cond_ability_unitTypeDD:Hide()
    end

    -- hide item DDs when not editing an item
    if condFrame.cond_item_distanceDD then
      condFrame.cond_item_distanceDD:Hide()
    end
    if condFrame.cond_item_unitTypeDD then
      condFrame.cond_item_unitTypeDD:Hide()
    end
  end
  _Reflow()
end

----------------------------------------------------------------
-- End Conditions UI section
----------------------------------------------------------------

-- Update frame controls to reflect db for `key`
function UpdateCondFrameForKey(key)
  local condFrame = _CF()
  if not condFrame or not key then
    return
  end

  local prevKey = ctx.getCurrentKey()
  ctx.setCurrentKey(key)
  _G["DoiteEdit_CurrentKey"] = key

  -- Jeremy added : Always clean up a previous bar injection before doing anything else
  if DoiteBars and DoiteBars.CleanupCondFrame then
    DoiteBars.CleanupCondFrame(condFrame)
  end

  -- Bar type: DoiteBars injection
  local _earlyData = DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[key]
  if _earlyData and _earlyData.type == "Bar" then
    -- Hide the per-icon font container for Bar type
    -- (bars have their own text settings inside DoiteBars editor)
    if condFrame.fontContainer then
      condFrame.fontContainer:Hide()
    end

    if DoiteBars and DoiteBars.InjectEditControls then
      DoiteBars.InjectEditControls(condFrame, key)
    end
    return
  else
    -- Ensure font container is visible for non-Bar entries
    if condFrame.fontContainer then
      condFrame.fontContainer:Show()
    end
  end

  -- When switching icons, force-close the AND/OR logic popup for the old icon
  if DoiteAuraLogicFrame and DoiteAuraLogicFrame:IsShown() then
    DoiteAuraLogicFrame:Hide()
  end

  -- Disable mouse on the previously edited icon (for dragging)
  local _GetIconFrame = DoiteAuras_GetIconFrame or function(k)
    return k and _G["DoiteIcon_" .. k]
  end
  if prevKey and prevKey ~= key then
    local oldFrame = _GetIconFrame(prevKey)
    if oldFrame then
      oldFrame:EnableMouse(false)
    end
  end

  -- Enable mouse on the newly edited icon frame (for dragging)
  local newFrame = _GetIconFrame(key)
  if newFrame then
    newFrame:EnableMouse(true)
  end

  -- EnsureDBEntry already enforces the correct condition subtree for this
  -- type; no need to duplicate the same pruning here.
  local data = _EDB(key)

  -- Header: colored by type
  local typeColor = "|cffffffff"
  if data.type == "Ability" then
    typeColor = "|cff4da6ff"
  elseif data.type == "Buff" then
    typeColor = "|cff22ff22"
  elseif data.type == "Debuff" then
    typeColor = "|cffff4d4d"
  elseif data.type == "Item" then
    typeColor = "|cffffd000"
  elseif data.type == "Bar" then
    typeColor = "|cffd27dff"
  elseif data.type == "Custom" then
    typeColor = "|cff7dd2ff"
  end
  condFrame.header:SetText("Edit: " .. (data.displayName or key) .. " " .. typeColor .. "(" .. (data.type or "") .. ")|r")

  if condFrame.DoiteGroupUIRefresh then
    condFrame:DoiteGroupUIRefresh(key)
  end

  -- Update Conditions UI (always visible area between top and POS & SIZE)
  UpdateConditionsUI(data)

  -- Show/hide Position & Size section (only when no group OR leader)
  local showPosSize = (not data.group) or data.isLeader
  if condFrame.DoiteGroupUIIsLeaderOrFree then
    showPosSize = condFrame:DoiteGroupUIIsLeaderOrFree()
  end

  if showPosSize then
    if condFrame.groupTitle3 then
      condFrame.groupTitle3:Show()
    end
    if condFrame.sep3 then
      condFrame.sep3:Show()
    end
    if condFrame.sliderX then
      condFrame.sliderX:Show()
    end
    if condFrame.sliderY then
      condFrame.sliderY:Show()
    end
    if condFrame.sliderSize then
      condFrame.sliderSize:Show()
    end
    if condFrame.sliderXBox then
      condFrame.sliderXBox:Show()
    end
    if condFrame.sliderYBox then
      condFrame.sliderYBox:Show()
    end
    if condFrame.sliderSizeBox then
      condFrame.sliderSizeBox:Show()
    end

    -- update slider positions/values (guarded)
    if condFrame.sliderX then
      condFrame.sliderX:SetValue(data.offsetX or 0)
    end
    if condFrame.sliderY then
      condFrame.sliderY:SetValue(data.offsetY or 0)
    end
    if condFrame.sliderSize then
      condFrame.sliderSize:SetValue(data.iconSize or 40)
    end
    _DA_ApplySliderRanges()

    -- update numeric editboxes if present
    if condFrame.sliderXBox then
      condFrame.sliderXBox:SetText(tostring(math.floor((data.offsetX or 0) + 0.5)))
    end
    if condFrame.sliderYBox then
      condFrame.sliderYBox:SetText(tostring(math.floor((data.offsetY or 0) + 0.5)))
    end
    if condFrame.sliderSizeBox then
      condFrame.sliderSizeBox:SetText(tostring(math.floor((data.iconSize or 40) + 0.5)))
    end
  else
    if condFrame.groupTitle3 then
      condFrame.groupTitle3:Hide()
    end
    if condFrame.sep3 then
      condFrame.sep3:Hide()
    end
    if condFrame.sliderX then
      condFrame.sliderX:Hide()
    end
    if condFrame.sliderY then
      condFrame.sliderY:Hide()
    end
    if condFrame.sliderSize then
      condFrame.sliderSize:Hide()
    end
    if condFrame.sliderXBox then
      condFrame.sliderXBox:Hide()
    end
    if condFrame.sliderYBox then
      condFrame.sliderYBox:Hide()
    end
    if condFrame.sliderSizeBox then
      condFrame.sliderSizeBox:Hide()
    end
  end


  ---------------------------------------------------------------
  -- Font Overrides section: always visible; repositioned based on
  -- whether the Position & Size section is shown.
  ---------------------------------------------------------------
  if condFrame.fontContainer then
    condFrame.fontContainer:ClearAllPoints()
    condFrame.fontContainer:SetPoint(
        "TOPLEFT", condFrame, "TOPLEFT", 15,
        showPosSize and -460 or -355
    )

    local fdb = DoiteAurasDB or {}

    -- ---- Timer size ----
    local timerOvr = tonumber(data.timerFontSize)
    local timerEff = timerOvr or tonumber(fdb.timerFontSize) or 15
    condFrame.fontTimerSize:SetText(tostring(timerEff))
    if timerOvr then
      condFrame.fontTimerSize:SetTextColor(1, 0.82, 0)
    else
      condFrame.fontTimerSize:SetTextColor(0.5, 0.5, 0.5)
    end

    -- ---- Stacks size ----
    local stackOvr = tonumber(data.stackFontSize)
    local stackEff = stackOvr or tonumber(fdb.stackFontSize) or 10
    condFrame.fontStackSize:SetText(tostring(stackEff))
    if stackOvr then
      condFrame.fontStackSize:SetTextColor(1, 0.82, 0)
    else
      condFrame.fontStackSize:SetTextColor(0.5, 0.5, 0.5)
    end

    -- ---- Timer font dropdown ----
    local timerFontOvr = data.timerFontPath
    if timerFontOvr == nil then
      UIDropDownMenu_SetSelectedValue(condFrame.fontTimerFontDD, "__inherit__")
      UIDropDownMenu_SetText("Inherit", condFrame.fontTimerFontDD)
    else
      UIDropDownMenu_SetSelectedValue(condFrame.fontTimerFontDD, timerFontOvr)
      UIDropDownMenu_SetText(
        _EditFontLabelForValue(timerFontOvr), condFrame.fontTimerFontDD
      )
    end

    -- ---- Stacks font dropdown ----
    local stackFontOvr = data.stackFontPath
    if stackFontOvr == nil then
      UIDropDownMenu_SetSelectedValue(condFrame.fontStackFontDD, "__inherit__")
      UIDropDownMenu_SetText("Inherit", condFrame.fontStackFontDD)
    else
      UIDropDownMenu_SetSelectedValue(condFrame.fontStackFontDD, stackFontOvr)
      UIDropDownMenu_SetText(
        _EditFontLabelForValue(stackFontOvr), condFrame.fontStackFontDD
      )
    end

    -- ---- Timer flag dropdown ----
    local timerFlagOvr = data.timerFontFlags
    if timerFlagOvr == nil then
      UIDropDownMenu_SetSelectedValue(condFrame.fontTimerFlagDD, "__inherit__")
      UIDropDownMenu_SetText("Inherit", condFrame.fontTimerFlagDD)
    else
      UIDropDownMenu_SetSelectedValue(condFrame.fontTimerFlagDD, timerFlagOvr)
      UIDropDownMenu_SetText(
        _EditFlagLabelForValue(timerFlagOvr), condFrame.fontTimerFlagDD
      )
    end

    -- ---- Stacks flag dropdown ----
    local stackFlagOvr = data.stackFontFlags
    if stackFlagOvr == nil then
      UIDropDownMenu_SetSelectedValue(condFrame.fontStackFlagDD, "__inherit__")
      UIDropDownMenu_SetText("Inherit", condFrame.fontStackFlagDD)
    else
      UIDropDownMenu_SetSelectedValue(condFrame.fontStackFlagDD, stackFlagOvr)
      UIDropDownMenu_SetText(
        _EditFlagLabelForValue(stackFlagOvr), condFrame.fontStackFlagDD
      )
    end
  end
end

-- Exports for DoiteEdit.lua (its proxies read these keys).
_G["DoiteEdit_ReflowCondAreaHeight"] = _ReflowCondAreaHeight
_G["DoiteEdit_UpdateConditionsUI"]    = UpdateConditionsUI
_G["DoiteEdit_UpdateCondFrameForKey"] = UpdateCondFrameForKey