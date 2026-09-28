---------------------------------------------------------------
-- DoiteEdit.lua
-- Secondary frame for editing Aura conditions / edit UI
-- Please respect license note: Ask permission
-- WoW 1.12 | Lua 5.0
---------------------------------------------------------------

local condFrame = nil
local currentKey = nil
local EnsureDBEntry
local ClearDropdown
local SafeRefresh
local SafeEvaluate
local srows
local ShowSeparatorsForType
local SetSeparator
local SetGroupMode
local DEFAULT_CUSTOM_FUNCTION_SOURCE

-- Icon-level category UI helpers (assigned later from CreateConditionsUI)

-- AuraCond_* definitions moved to Modules/DoiteEditAuraCond.lua (loaded after
-- this file). References below use _G["AuraCond_*"] or the proxies in
-- DoiteEditCtx. VfxCond_* stay local for now (extracted later).

-- file-scope forward declaration (used by UpdateConditionsUI)
local AuraOwner_UpdateDependentChecks

-- VfxCond_* definitions moved to Modules/DoiteEditAuraCond.lua (loaded after
-- this file). References below use _G["VfxCond_*"].


-- ==================================================================
-- Helpers moved to Modules/DoiteEditHelpers.lua
-- ==================================================================
-- Local aliases for hot-path use below.
local FONT_CHOICES_EDIT           = _G["DoiteEdit_FONT_CHOICES"]
local FLAG_CHOICES_EDIT           = _G["DoiteEdit_FLAG_CHOICES"]
local SOUND_FILES                 = _G["DoiteEdit_SOUND_FILES"]
local _EditFontLabelForValue      = _G["DoiteEdit_FontLabelForValue"]
local _EditFlagLabelForValue      = _G["DoiteEdit_FlagLabelForValue"]
local _ParseFadeAlphaFromBox      = _G["DoiteEdit_ParseFadeAlphaFromBox"]
local _NormalizeFadeBox           = _G["DoiteEdit_NormalizeFadeBox"]
local DoiteEdit_SetDropdownInteractive    = _G["DoiteEdit_SetDropdownInteractive"]
local DoiteEdit_HookDropDownButtonOnClick = _G["DoiteEdit_HookDropDownButtonOnClick"]

local function _ApplyFontsNowEdit()
    if type(DoiteAuras_ApplyFontsToAllIcons) == "function" then
        DoiteAuras_ApplyFontsToAllIcons()
    else
        if DoiteAuras_RefreshIcons then pcall(DoiteAuras_RefreshIcons) end
    end
end

local function DoiteEdit_SetSoundFromDropdown(typeKey, eventKey, value)
  if not currentKey then
    return
  end
  local d = EnsureDBEntry(currentKey)
  d.conditions = d.conditions or {}
  d.conditions[typeKey] = d.conditions[typeKey] or {}
  d.conditions[typeKey][eventKey] = value
  SafeRefresh();
  SafeEvaluate()
end

local function DoiteEdit_SetSoundEnabled(typeKey, enabledKey, enabled)
  if not currentKey then
    return
  end
  local d = EnsureDBEntry(currentKey)
  d.conditions = d.conditions or {}
  d.conditions[typeKey] = d.conditions[typeKey] or {}
  d.conditions[typeKey][enabledKey] = enabled and true or false
  SafeRefresh();
  SafeEvaluate()
end

local function DoiteEdit_InitSoundDropdown(dd, typeKey, eventKey, selectedValue)
  if not dd then
    return
  end

  -- Keep selection on the dropdown itself so paging stays correct
  dd._selectedSound = (selectedValue and selectedValue ~= "") and selectedValue or ""
  dd._soundPage = dd._soundPage or 1

  ClearDropdown(dd)

  local total = table.getn(SOUND_FILES)
  local perPage = 20  -- keep well under UIDropDownMenu button cap
  local maxPage = 1
  if total > 0 then
    maxPage = math.ceil(total / perPage)
  end
  if dd._soundPage < 1 then dd._soundPage = 1 end
  if dd._soundPage > maxPage then dd._soundPage = maxPage end

  local function ReopenNextFrame()
    local f = dd._reopenFrame
    if not f then
      f = CreateFrame("Frame", nil, UIParent)
      dd._reopenFrame = f
      f:Hide()
      f:SetScript("OnUpdate", function()
        f:Hide()
        ToggleDropDownMenu(nil, nil, dd, dd, 0, 0)
      end)
    end
    f:Show()
  end

  UIDropDownMenu_Initialize(dd, function(frame, level, menuList)
    level = level or 1
    local page = dd._soundPage or 1

    -- Prev
    if page > 1 then
      local infoPrev = UIDropDownMenu_CreateInfo()
      infoPrev.text = "|cffffd000<< Previous|r"
      infoPrev.notCheckable = true
      infoPrev.func = function()
        dd._soundPage = page - 1
        if CloseDropDownMenus then CloseDropDownMenus() end
        ReopenNextFrame()
      end
      UIDropDownMenu_AddButton(infoPrev, level)
    end

    -- Page items
    local startIndex = (page - 1) * perPage + 1
    local endIndex = math.min(startIndex + perPage - 1, total)

    local i = startIndex
    while i <= endIndex do
      local fname = SOUND_FILES[i]
      local info2 = UIDropDownMenu_CreateInfo()
      info2.text = fname
      info2.value = fname
      info2.checked = (dd._selectedSound == fname)
      info2.func = function(button)
        local picked = (button and button.value) or fname
        dd._selectedSound = picked
        UIDropDownMenu_SetSelectedValue(dd, picked)
        UIDropDownMenu_SetText(picked, dd)
        DoiteEdit_SetSoundFromDropdown(typeKey, eventKey, picked)
        if PlaySoundFile and picked and picked ~= "" then
          pcall(PlaySoundFile, "Interface\\AddOns\\DoiteAuras\\Sounds\\" .. picked)
        end
        if CloseDropDownMenus then CloseDropDownMenus() end
      end
      UIDropDownMenu_AddButton(info2, level)
      i = i + 1
    end

    -- Next
    if page < maxPage then
      local infoNext = UIDropDownMenu_CreateInfo()
      infoNext.text = "|cffffd000Next >>|r"
      infoNext.notCheckable = true
      infoNext.func = function()
        dd._soundPage = page + 1
        if CloseDropDownMenus then CloseDropDownMenus() end
        ReopenNextFrame()
      end
      UIDropDownMenu_AddButton(infoNext, level)
    end
  end)

  -- Restore visible text
  if dd._selectedSound ~= "" then
    UIDropDownMenu_SetSelectedValue(dd, dd._selectedSound)
    UIDropDownMenu_SetText(dd._selectedSound, dd)
  else
    UIDropDownMenu_SetSelectedValue(dd, "")
    UIDropDownMenu_SetText("Select sound", dd)
  end

  if _GoldifyDD then
    _GoldifyDD(dd)
  end
end

-- Class gates + cooldown/display helpers moved to Modules/DoiteEditHelpers.lua.
-- Local aliases below.
local _IsRogueOrDruid                  = _G["DoiteEdit_IsRogueOrDruid"]
local _IsHunterOrWarlock               = _G["DoiteEdit_IsHunterOrWarlock"]
local _DA_GetAbilityCooldownDuration   = _G["DoiteEdit_GetAbilityCooldownDuration"]
local _DA_SetSliderTimeDisplay         = _G["DoiteEdit_SetSliderTimeDisplay"]
local DoiteEdit_AbilitySupportsProcSound = _G["DoiteEdit_AbilitySupportsProcSound"]
local DoiteEdit_YellowifyButton        = _G["DoiteEdit_YellowifyButton"]
local DoiteEdit_EnableCheck            = _G["DoiteEdit_EnableCheck"]
local DoiteEdit_DisableCheck           = _G["DoiteEdit_DisableCheck"]

local function DoiteEdit_AddGroupModeOption(typeKey, text, value)
  local info = UIDropDownMenu_CreateInfo()
  info.text = text
  info.value = value
  info.func = function(button)
    local v = (button and button.value) or value
    if v == "__default" then
      SetGroupMode(typeKey, nil)
    else
      SetGroupMode(typeKey, v)
    end
  end
  UIDropDownMenu_AddButton(info)
end

-- === Throttle for heavy UI work moved to Modules/DoiteEditThrottle.lua ===
local DoiteEdit_QueueHeavy = _G["DoiteEdit_QueueHeavy"]
local DoiteEdit_FlushHeavy = _G["DoiteEdit_FlushHeavy"]

-- Sync sliders to new position after icon drag
function DoiteEdit_SyncSlidersToPosition(key, x, y)
  if condFrame and currentKey == key then
    if condFrame.sliderX then
      condFrame.sliderX._isSyncing = true
      condFrame.sliderX:SetValue(x)
      condFrame.sliderX._isSyncing = false
    end
    if condFrame.sliderY then
      condFrame.sliderY._isSyncing = true
      condFrame.sliderY:SetValue(y)
      condFrame.sliderY._isSyncing = false
    end
    if condFrame.sliderXBox then
      condFrame.sliderXBox:SetText(tostring(math.floor(x + 0.5)))
    end
    if condFrame.sliderYBox then
      condFrame.sliderYBox:SetText(tostring(math.floor(y + 0.5)))
    end
  end
end
_G["DoiteEdit_SyncSlidersToPosition"] = DoiteEdit_SyncSlidersToPosition

EnsureDBEntry = function(key)
  -- Ensure global categories table exists (shared across all icons)
  if DoiteAurasDB and not DoiteAurasDB.categories then
    DoiteAurasDB.categories = {}
  end

  if not DoiteAurasDB.spells[key] then
    DoiteAurasDB.spells[key] = {
      order = 999,
      type = "Ability",
      displayName = key,
      growth = "Horizontal Right",
      numAuras = 5,
      offsetX = 0,
      offsetY = 0,
      iconSize = 40,
      conditions = {}
    }
  end

  local d = DoiteAurasDB.spells[key]

  -- general defaults (don't override existing values)
  if not d.growth then
    d.growth = "Horizontal Right"
  end
  if not d.numAuras then
    d.numAuras = 5
  end
  if not d.offsetX then
    d.offsetX = 0
  end
  if not d.offsetY then
    d.offsetY = 0
  end
  if not d.iconSize then
    d.iconSize = 40
  end
  if not d.conditions then
    d.conditions = {}
  end

  -- create ONLY the correct subtable for this entry type and prune the other ones
  if d.type == "Ability" then
    -- keep ability; remove aura/item
    d.conditions.ability = d.conditions.ability or {}
    d.conditions.aura = nil
    d.conditions.item = nil
    -- dynamic Aura Conditions (extra Buff/Debuff checks)
    if not d.conditions.ability.auraConditions then
      d.conditions.ability.auraConditions = {}
    end

    -- defaults (ability)
    if d.conditions.ability.mode == nil then
      d.conditions.ability.mode = "notcd"
    end
    if d.conditions.ability.inCombat == nil then
      d.conditions.ability.inCombat = true
    end
    if d.conditions.ability.outCombat == nil then
      d.conditions.ability.outCombat = true
    end
    if d.conditions.ability.targetHelp == nil then
      d.conditions.ability.targetHelp = false
    end
    if d.conditions.ability.targetHarm == nil then
      d.conditions.ability.targetHarm = false
    end
    if d.conditions.ability.targetSelf == nil then
      d.conditions.ability.targetSelf = false
    end
    if d.conditions.ability.form == nil then
      d.conditions.ability.form = "All"
    end

    if d.conditions.ability.targetDistance == nil then
      d.conditions.ability.targetDistance = nil
    end
    if d.conditions.ability.targetUnitType == nil then
      d.conditions.ability.targetUnitType = nil
    end
    if d.conditions.ability.weaponFilter == nil then
      d.conditions.ability.weaponFilter = nil
    end

    -- legacy cleanup
    d.conditions.ability.target = nil

  elseif d.type == "Item" then
    -- keep item; remove ability/aura
    d.conditions.item = d.conditions.item or {}
    d.conditions.ability = nil
    d.conditions.aura = nil

    -- defaults (item)
    local ic = d.conditions.item

    -- dynamic Aura Conditions (extra Buff/Debuff checks)
    if not ic.auraConditions then
      ic.auraConditions = {}
    end

    if ic.whereEquipped == nil then
      ic.whereEquipped = true
    end
    if ic.whereBag == nil then
      ic.whereBag = true
    end
    if ic.whereMissing == nil then
      ic.whereMissing = false
    end

    if ic.mode == nil then
      ic.mode = "notcd"
    end
    if ic.inCombat == nil then
      ic.inCombat = true
    end
    if ic.outCombat == nil then
      ic.outCombat = true
    end
    if ic.targetHelp == nil then
      ic.targetHelp = false
    end
    if ic.targetHarm == nil then
      ic.targetHarm = false
    end
    if ic.targetSelf == nil then
      ic.targetSelf = false
    end
    if ic.form == nil then
      ic.form = "All"
    end

    if ic.targetDistance == nil then
      ic.targetDistance = nil
    end
    if ic.targetUnitType == nil then
      ic.targetUnitType = nil
    end
    if ic.weaponFilter == nil then
      ic.weaponFilter = nil
    end

  elseif d.type == "Custom" then
    -- custom code drives visibility/texture/overlay; no stock condition subtree
    d.conditions.ability = nil
    d.conditions.aura = nil
    d.conditions.item = nil

    if type(d.customFunctionSource) ~= "string" or d.customFunctionSource == "" then
      d.customFunctionSource = DEFAULT_CUSTOM_FUNCTION_SOURCE
    end

  else
    -- Buff / Debuff (treat anything not "Ability"/"Item" as an aura carrier)
    -- keep aura; remove ability/item
    d.conditions.aura = d.conditions.aura or {}
    d.conditions.ability = nil
    d.conditions.item = nil
    -- dynamic Aura Conditions (extra Buff/Debuff checks)
    if not d.conditions.aura.auraConditions then
      d.conditions.aura.auraConditions = {}
    end


    -- defaults (aura)
    if d.conditions.aura.mode == nil then
      d.conditions.aura.mode = "found"
    end
    if d.conditions.aura.inCombat == nil then
      d.conditions.aura.inCombat = true
    end
    if d.conditions.aura.outCombat == nil then
      d.conditions.aura.outCombat = true
    end
    if d.conditions.aura.targetSelf == nil then
      d.conditions.aura.targetSelf = true
    end
    if d.conditions.aura.targetHelp == nil then
      d.conditions.aura.targetHelp = false
    end
    if d.conditions.aura.targetHarm == nil then
      d.conditions.aura.targetHarm = false
    end
    if d.conditions.aura.form == nil then
      d.conditions.aura.form = "All"
    end

    if d.conditions.aura.targetDistance == nil then
      d.conditions.aura.targetDistance = nil
    end
    if d.conditions.aura.targetUnitType == nil then
      d.conditions.aura.targetUnitType = nil
    end
    if d.conditions.aura.weaponFilter == nil then
      d.conditions.aura.weaponFilter = nil
    end

    if d.conditions.aura.trackpet == nil then
      d.conditions.aura.trackpet = false
    end

    -- legacy cleanup
    d.conditions.aura.target = nil
    d.conditions.aura.targetTarget = nil
  end

  return d
end

-- clear a dropdown so it can be safely re-initialized
ClearDropdown = function(dd)
  if not dd then
    return
  end
  if UIDropDownMenu_Initialize then
    pcall(UIDropDownMenu_Initialize, dd, function()
    end)
  end
  if UIDropDownMenu_ClearAll then
    pcall(UIDropDownMenu_ClearAll, dd)
  end
  dd._initializedForKey = nil
  dd._initializedForType = nil
end

SafeEvaluate = function()
  DoiteEdit_QueueHeavy()
end

SafeRefresh = function()
  DoiteEdit_QueueHeavy()
end

-- Position/Size range helpers moved to Modules/DoiteEditHelpers.lua.
local _DA_GetParentDims        = _G["DoiteEdit_GetParentDims"]
local _DA_ComputePosSizeRanges = _G["DoiteEdit_ComputePosSizeRanges"]

-- apply to existing sliders and clamp the current DB values if out of range
local function _DA_ApplySliderRanges()
  if not condFrame or not condFrame.sliderX or not condFrame.sliderY or not condFrame.sliderSize then
    return
  end

  local minX, maxX, minY, maxY, minSize, maxSize = _DA_ComputePosSizeRanges()

  -- X
  condFrame.sliderX:SetMinMaxValues(minX, maxX)
  local lowX = _G[condFrame.sliderX:GetName() .. "Low"]
  local highX = _G[condFrame.sliderX:GetName() .. "High"]
  if lowX then
    lowX:SetText(tostring(minX))
  end
  if highX then
    highX:SetText(tostring(maxX))
  end

  -- Y
  condFrame.sliderY:SetMinMaxValues(minY, maxY)
  local lowY = _G[condFrame.sliderY:GetName() .. "Low"]
  local highY = _G[condFrame.sliderY:GetName() .. "High"]
  if lowY then
    lowY:SetText(tostring(minY))
  end
  if highY then
    highY:SetText(tostring(maxY))
  end

  -- Size
  condFrame.sliderSize:SetMinMaxValues(minSize, maxSize)
  local lowS = _G[condFrame.sliderSize:GetName() .. "Low"]
  local highS = _G[condFrame.sliderSize:GetName() .. "High"]
  if lowS then
    lowS:SetText(tostring(minSize))
  end
  if highS then
    highS:SetText(tostring(maxSize))
  end

  -- Clamp current values (and DB) into the new ranges
  local function clamp(v, lo, hi)
    if v < lo then
      return lo
    elseif v > hi then
      return hi
    else
      return v
    end
  end

  if currentKey then
    local d = DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[currentKey]
    if d then
      d.offsetX = clamp(d.offsetX or 0, minX, maxX)
      d.offsetY = clamp(d.offsetY or 0, minY, maxY)
      d.iconSize = clamp(d.iconSize or 40, minSize, maxSize)
    end
  end

  -- Push clamped values into sliders/boxes
  if currentKey then
    local d = DoiteAurasDB.spells[currentKey]
    if d then
      condFrame.sliderX:SetValue(d.offsetX or 0)
      condFrame.sliderY:SetValue(d.offsetY or 0)
      condFrame.sliderSize:SetValue(d.iconSize or 40)
      if condFrame.sliderXBox then
        condFrame.sliderXBox:SetText(tostring(math.floor((d.offsetX or 0) + 0.5)))
      end
      if condFrame.sliderYBox then
        condFrame.sliderYBox:SetText(tostring(math.floor((d.offsetY or 0) + 0.5)))
      end
      if condFrame.sliderSizeBox then
        condFrame.sliderSizeBox:SetText(tostring(math.floor((d.iconSize or 40) + 0.5)))
      end
    end
  end
end


-- Internal: initialize growth direction dropdown (leader-only control)
local function InitGrowthDropdown(dd, data)
  UIDropDownMenu_Initialize(dd, function(frame, level, menuList)
    local info
    local directions = { "Horizontal Right", "Horizontal Left", "Centered Horizontal", "Vertical Down", "Vertical Up", "Centered Vertical" }
    for _, dir in ipairs(directions) do
      info = {}
      info.text = dir
      info.value = dir
      local pickedDir = dir
      info.func = function(button)
        local picked = (button and button.value) or pickedDir
        if not currentKey then
          return
        end
        local d = EnsureDBEntry(currentKey)
        d.growth = picked
        UIDropDownMenu_SetSelectedValue(dd, picked)
        UIDropDownMenu_SetText(picked, dd)
        CloseDropDownMenus()
        SafeRefresh()
        SafeEvaluate()
      end
      info.checked = (data and data.growth == dir)
      UIDropDownMenu_AddButton(info)
    end
  end)
end

-- Internal: initialize numAuras dropdown (leader-only control)
local function InitNumAurasDropdown(dd, data)
  UIDropDownMenu_Initialize(dd, function(frame, level, menuList)
    local info
    for i = 1, 10 do
      info = {}
      info.text = tostring(i)
      info.value = i
      local pickedNum = i
      info.func = function(button)
        local picked = (button and button.value) or pickedNum
        if not currentKey then
          return
        end
        local d = EnsureDBEntry(currentKey)
        d.numAuras = picked
        UIDropDownMenu_SetSelectedValue(dd, picked)
        UIDropDownMenu_SetText(tostring(picked), dd)
        CloseDropDownMenus()
        SafeRefresh()
        SafeEvaluate()
      end
      info.checked = (data and data.numAuras == i)
      UIDropDownMenu_AddButton(info)
    end
    info = {}
    info.text = "Unlimited"
    info.value = "Unlimited"
    info.func = function(button)
      local picked = (button and button.value) or "Unlimited"
      if not currentKey then
        return
      end
      local d = EnsureDBEntry(currentKey)
      d.numAuras = picked
      UIDropDownMenu_SetSelectedValue(dd, picked)
      UIDropDownMenu_SetText(picked, dd)
      CloseDropDownMenus()
      SafeRefresh()
      SafeEvaluate()
    end
    info.checked = (data and data.numAuras == "Unlimited")
    UIDropDownMenu_AddButton(info)
  end)
end

-- Unified Form/Stance dropdown initializer (works for Ability / Aura / Item)
-- NOTE: must be a global (see comment on _SetDDEnabled above).
function InitFormDropdown(dd, data, condType)
  if not dd then
    return
  end
  condType = condType or "ability"

  local thisKey = currentKey
  if not thisKey then
    ClearDropdown(dd)
    return
  end

  if dd._initializedForKey == thisKey and dd._initializedForType == condType then
    return
  end

  -- Determine player class and build options (reordered + Priest added)
  local _, class = UnitClass("player")
  class = class and string.upper(class) or ""

  local forms = {}
  if class == "DRUID" then
    forms = {
      "All forms",
      "0. No forms", "1. Bear", "2. Aquatic", "3. Cat", "4. Travel",
      "5. Moonkin", "6. Tree", "7. Stealth", "8. No Stealth",
      "Multi: 0+5", "Multi: 0+6", "Multi: 1+3", "Multi: 3+7", "Multi: 3+8",
      "Multi: 5+6", "Multi: 0+5+6", "Multi: 1+3+8"
    }
  elseif class == "WARRIOR" then
    forms = { "All stances", "1. Battle", "2. Defensive", "3. Berserker",
              "Multi: 1+2", "Multi: 1+3", "Multi: 2+3" }
  elseif class == "ROGUE" then
    forms = { "All forms", "0. No Stealth", "1. Stealth" }
  elseif class == "PRIEST" then
    forms = { "All forms", "0. No form", "1. Shadowform" }
  elseif class == "PALADIN" then
    forms = {
      "All Auras", "No Aura", "1. Devotion", "2. Retribution", "3. Concentration",
      "4. Shadow Resistance", "5. Frost Resistance", "6. Fire Resistance", "7. Sanctity",
      "Multi: 1+2", "Multi: 1+3", "Multi: 1+4+5+6", "Multi: 1+7", "Multi: 1+2+3", "Multi: 1+2+3+4+5+6",
      "Multi: 2+3", "Multi: 2+4+5+6", "Multi: 2+7", "Multi: 2+3+4+5+6",
      "Multi: 3+4+5+6", "Multi: 3+7",
      "Multi: 4+5+6+7"
    }
  else
    dd:Hide()
    return
  end

  -- make absolutely sure the old menu is cleared before building
  ClearDropdown(dd)

  -- Build/initialize the dropdown
  UIDropDownMenu_Initialize(dd, function(frame, level, menuList)
    for i, form in ipairs(forms) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = form
      info.value = form
      local pickedForm = form

      info.func = function(button)
        local picked = (button and button.value) or pickedForm
        UIDropDownMenu_SetSelectedValue(dd, picked)
        UIDropDownMenu_SetText(picked, dd)

        if condType == "ability" then
          data.conditions.ability = data.conditions.ability or {}
          data.conditions.ability.form = picked
        elseif condType == "aura" then
          data.conditions.aura = data.conditions.aura or {}
          data.conditions.aura.form = picked
        elseif condType == "item" then
          data.conditions.item = data.conditions.item or {}
          data.conditions.item.form = picked
        end

        SafeRefresh()
        SafeEvaluate()
        UpdateCondFrameForKey(currentKey)
      end

      -- checked state based on the passed `data`
      local savedForm = (data and data.conditions and data.conditions[condType] and data.conditions[condType].form)
      info.checked = (savedForm == form)

      UIDropDownMenu_AddButton(info)
    end
  end)

  -- Restore visible value (saved or default)
  local savedForm = (data and data.conditions and data.conditions[condType] and data.conditions[condType].form)

  local matched = false
  if savedForm and savedForm ~= "All" and savedForm ~= "" then
    for i, f in ipairs(forms) do
      if f == savedForm then
        UIDropDownMenu_SetSelectedID(dd, i)
        matched = true
        break
      end
    end
  end

  if matched then
    UIDropDownMenu_SetText(savedForm, dd)
  else
    UIDropDownMenu_SetText("Select form", dd)
  end

  dd._initializedForKey = thisKey
  dd._initializedForType = condType
end

-- Unified Weapon/Fighting-style dropdown (class-specific: Warrior / Paladin / Shaman)
-- NOTE: must be a global (see comment on _SetDDEnabled above).
function InitWeaponDropdown(dd, data, condType)
  if not dd then
    return
  end
  condType = condType or "ability"

  local thisKey = currentKey
  if not thisKey then
    ClearDropdown(dd)
    return
  end

  -- Early-out: re-initializing on every UpdateConditionsUI is wasteful.
  if dd._initializedForKey == thisKey and dd._initializedForType == condType then
    return
  end

  -- Detect player class
  local _, class = UnitClass("player")
  class = class and string.upper(class) or ""

  -- Options by class
  local choices
  if class == "WARRIOR" then
    choices = { "Any", "Two-Hand", "Shield", "Dual-Wield" }
  elseif class == "PALADIN" or class == "SHAMAN" then
    choices = { "Any", "Two-Hand", "Shield" }
  else
    -- Not supported: just hide the dropdown
    dd:Hide()
    return
  end

  ClearDropdown(dd)

  UIDropDownMenu_Initialize(dd, function(frame, level, menuList)
    for _, val in ipairs(choices) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = val
      info.value = val
      local pickedVal = val

      info.func = function(button)
        local picked = (button and button.value) or pickedVal
        if not currentKey then
          return
        end

        -- Update widget
        UIDropDownMenu_SetSelectedValue(dd, picked)
        UIDropDownMenu_SetText(picked, dd)
        _GoldifyDD(dd)

        -- Persist into the correct conditions table
        local d = EnsureDBEntry(currentKey)
        d.conditions = d.conditions or {}

        if condType == "ability" then
          d.conditions.ability = d.conditions.ability or {}
          d.conditions.ability.weaponFilter = picked
        elseif condType == "aura" then
          d.conditions.aura = d.conditions.aura or {}
          d.conditions.aura.weaponFilter = picked
        elseif condType == "item" then
          d.conditions.item = d.conditions.item or {}
          d.conditions.item.weaponFilter = picked
        end

        SafeRefresh();
        SafeEvaluate()
        if UpdateCondFrameForKey then
          UpdateCondFrameForKey(currentKey)
        end
        if CloseDropDownMenus then
          CloseDropDownMenus()
        end
      end

      local saved
      if data and data.conditions and data.conditions[condType] then
        saved = data.conditions[condType].weaponFilter
      end
      info.checked = (saved == val)

      UIDropDownMenu_AddButton(info)
    end
  end)

  -- Initial visible state: saved value, or neutral "Equipped" placeholder
  local saved
  if data and data.conditions and data.conditions[condType] then
    saved = data.conditions[condType].weaponFilter
  end

  if saved then
    if UIDropDownMenu_SetSelectedValue then
      pcall(UIDropDownMenu_SetSelectedValue, dd, saved)
    end
    if UIDropDownMenu_SetText then
      pcall(UIDropDownMenu_SetText, saved, dd)
    end
    _GoldifyDD(dd)
  else
    if UIDropDownMenu_SetSelectedValue then
      pcall(UIDropDownMenu_SetSelectedValue, dd, nil)
    end
    if UIDropDownMenu_SetText then
      -- "Equipped" = default/neutral state
      pcall(UIDropDownMenu_SetText, "Equipped", dd)
    end
    _GoldifyDD(dd)
  end

  dd._initializedForKey = thisKey
  dd._initializedForType = condType
end

----------------------------------------------------------------
-- Exclusive helper functions
----------------------------------------------------------------
local function SetExclusiveAbilityMode(mode)
  if not currentKey then
    return
  end
  local d = EnsureDBEntry(currentKey)
  d.conditions = d.conditions or {}
  d.conditions.ability = d.conditions.ability or {}

  if mode ~= nil
      and mode ~= "usable"
      and mode ~= "notcd"
      and mode ~= "oncd"
      and mode ~= "usableoncd"
      and mode ~= "nocdoncd" then
    mode = "notcd"
  end

  d.conditions.ability.mode = mode
  UpdateCondFrameForKey(currentKey)
  SafeRefresh()
  SafeEvaluate()
end

local function SetExclusiveItemMode(mode)
  if not currentKey then return end
  local d = EnsureDBEntry(currentKey)
  d.conditions = d.conditions or {}
  d.conditions.item = d.conditions.item or {}

  -- mode is one of: "notcd", "oncd", "both"
  if mode ~= "notcd" and mode ~= "oncd" and mode ~= "both" then
    mode = "notcd"
  end

  d.conditions.item.mode = mode
  UpdateCondFrameForKey(currentKey)
end

-- independent combat flag toggles (inCombat / outCombat)
local function SetCombatFlag(typeTable, which, enabled)
  if not currentKey then
    return
  end
  local d = EnsureDBEntry(currentKey)
  d.conditions = d.conditions or {}
  d.conditions[typeTable] = d.conditions[typeTable] or {}

  -- hard separation: never allow the opposite table to exist
  if typeTable == "ability" then
    d.conditions.aura = nil
    d.conditions.item = nil
  elseif typeTable == "aura" then
    d.conditions.ability = nil
    d.conditions.item = nil
  elseif typeTable == "item" then
    d.conditions.ability = nil
    d.conditions.aura = nil
  end

  if which == "in" then
    d.conditions[typeTable].inCombat = enabled and true or false
  elseif which == "out" then
    d.conditions[typeTable].outCombat = enabled and true or false
  end
  d.conditions[typeTable].combat = nil
  UpdateCondFrameForKey(currentKey)
  SafeRefresh()
  SafeEvaluate()
end

-- Grouping dropdown mode:
local function _DeriveGroupingMode(t)
  if not t then
    return nil
  end
  if t.grouping ~= nil then
    return t.grouping
  end
  -- legacy fallback (best effort)
  if t.notInGroup == true then
    return "nogroup"
  end
  local p = (t.inParty == true)
  local r = (t.inRaid == true)
  if p and r then
    return "partyraid"
  elseif p then
    return "party"
  elseif r then
    return "raid"
  end
  return nil
end
_G["DoiteEdit_DeriveGroupingMode"] = _DeriveGroupingMode

SetGroupMode = function(typeTable, mode)
  if not currentKey then
    return
  end

  local d = EnsureDBEntry(currentKey)
  d.conditions = d.conditions or {}
  d.conditions[typeTable] = d.conditions[typeTable] or {}
  local t = d.conditions[typeTable]

  -- hard separation: never allow the opposite table to exist
  if typeTable == "ability" then
    d.conditions.aura = nil
    d.conditions.item = nil
  elseif typeTable == "aura" then
    d.conditions.ability = nil
    d.conditions.item = nil
  elseif typeTable == "item" then
    d.conditions.ability = nil
    d.conditions.aura = nil
  end

  -- store canonical mode
  if mode == nil then
    t.grouping = nil
  else
    t.grouping = mode
  end

  -- keep legacy fields mirrored (best effort compatibility)
  t.notInGroup = nil
  if mode == "nogroup" then
    t.notInGroup = true
    t.inParty = nil
    t.inRaid = nil
  elseif mode == "party" then
    t.inParty = true
    t.inRaid = nil
  elseif mode == "raid" then
    t.inParty = nil
    t.inRaid = true
  elseif mode == "partyraid" then
    t.inParty = true
    t.inRaid = true
  elseif mode == "any" then
    t.inParty = nil
    t.inRaid = nil
  else
    t.grouping = nil
    t.inParty = nil
    t.inRaid = nil
    t.notInGroup = nil
  end

  UpdateCondFrameForKey(currentKey)
  SafeRefresh()
  SafeEvaluate()
end

local function SetExclusiveAuraFoundMode(mode)
  if not currentKey then
    return
  end
  local d = EnsureDBEntry(currentKey)
  d.conditions = d.conditions or {}
  d.conditions.aura = d.conditions.aura or {}

  if mode ~= nil and mode ~= "found" and mode ~= "missing" and mode ~= "both" then
    mode = "found"
  end

  d.conditions.aura.mode = mode
  UpdateCondFrameForKey(currentKey)
  SafeRefresh()
  SafeEvaluate()
end

-- _GoldifyDD / _GreyifyDD / _WhiteifyDDText moved to Modules/DoiteEditHelpers.lua
-- (exposed as globals with same names).

-- Only touch the text / placeholder when DISABLING.
-- NOTE: must be a global, not a file-local. The DoiteEditCtx closure for
-- ctx.SetDDEnabled is defined earlier in the file (before this declaration),
-- so a file-local here would be invisible to it.
function _SetDDEnabled(dd, enabled, placeholderText)
  if not dd or not dd.GetName then
    return
  end
  local name = dd:GetName()
  local btn = name and _G[name .. "Button"]

  if enabled then
    -- Enable button and keep whatever text _RestoreDD (or Init*) put there.
    if btn and btn.Enable then
      btn:Enable()
    end
    _GoldifyDD(dd)
  else
    -- Disable and show the neutral placeholder.
    if btn and btn.Disable then
      btn:Disable()
    end
    if UIDropDownMenu_ClearAll then
      pcall(UIDropDownMenu_ClearAll, dd)
    end
    if placeholderText and UIDropDownMenu_SetText then
      UIDropDownMenu_SetText(placeholderText, dd)
    end
    _GreyifyDD(dd)
  end
end

-- Pretty-print helper: announce when entering edit for an icon
local lastAnnouncedKey = nil

-- Pretty-print helper: announce when entering edit for an icon
local function DoiteEdit_AnnounceEditingIcon(displayName)
  -- Only announce once per icon per edit session
  if currentKey and lastAnnouncedKey == currentKey then
    return
  end
  lastAnnouncedKey = currentKey

  if not displayName or displayName == "" then
    displayName = "Unknown"
  end

  local prefix = "|cff4da6ffDoiteAuras:|r "
  local name = "|cffffff00" .. tostring(displayName) .. "|r"

  local msg = prefix ..
      "During edit for " .. name ..
      ", this icon will stay visible and be pinned at the top of its dynamic group (if any) for convenience."

  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

DEFAULT_CUSTOM_FUNCTION_SOURCE = [[-- Define custom logic for this aura a table named 'data' will be passed in, you can store data between frames inside this

-- your code block must return the following:
local show = true -- [boolean] true to show the icon, false to hide
local texture = "Interface\\Icons\\Temp" -- [string] MPOWA icons available in "Interface\\Addons\\DoiteAuras\\Textures\\MPOWA\\AuraXX"

local hideBackground = false -- [boolean] if true will hide the default background behind the icon texture

local remaining = nil -- [number] if present will display in the center of the icon
local stacks = nil -- [number] if present will display in the bottom right of the icon

return show, texture, hideBackground, remaining, stacks]]

-- Share with other modules (e.g. DoiteConditions)
_G["DOITE_DEFAULT_CUSTOM_FUNCTION_SOURCE"] = DEFAULT_CUSTOM_FUNCTION_SOURCE

local function CompileCustomFunctionSource(source)
  if type(source) ~= "string" then
    return nil, "Custom function source must be a string."
  end
  if source == "" then
    return nil, "Custom function source cannot be empty."
  end

  local wrapped = "return function(data)\n" .. source .. "\nend"
  local chunk, err = loadstring(wrapped)
  if not chunk then
    return nil, err
  end

  local ok, fn = pcall(chunk)
  if not ok then
    return nil, fn
  end
  if type(fn) ~= "function" then
    return nil, "Compiled custom function is not callable."
  end
  return fn, nil
end

-- AuraCond_TitleCase moved to Modules/DoiteEditHelpers.lua.
local AuraCond_TitleCase = _G["DoiteEdit_AuraCond_TitleCase"]

----------------------------------------------------------------
-- Conditions UI creation & wiring
----------------------------------------------------------------
-- StylePlainEditBox moved to Modules/DoiteEditHelpers.lua.
local StylePlainEditBox = _G["DoiteEdit_StylePlainEditBox"]

-- ==================================================================
-- Shared context for DoiteEdit submodules (AuraCond, VfxCond, UIBuild, UpdateUI).
-- ==================================================================
-- Exposes state accessors and helper proxies via _G["DoiteEditCtx"].
-- Forward-decl helpers (SetSeparator, ShowSeparatorsForType, etc.) are
-- wrapped in lazy shims; they may be nil at load time but become valid
-- once CreateConditionsUI runs.
do
  local ctx = {}
  _G["DoiteEditCtx"] = ctx

  -- State accessors
  ctx.getCondFrame   = function() return condFrame end
  ctx.setCondFrame   = function(f) condFrame = f end
  ctx.getCurrentKey  = function() return currentKey end
  ctx.setCurrentKey  = function(k) currentKey = k end
  ctx.getSrows       = function() return srows end
  ctx.setSrows       = function(v) srows = v end

  -- Core helpers (defined at this point; safe to call directly)
  ctx.EnsureDBEntry = function(key) return EnsureDBEntry(key) end
  ctx.ClearDropdown = function(dd) return ClearDropdown(dd) end
  ctx.SafeRefresh   = function() SafeRefresh() end
  ctx.SafeEvaluate  = function() SafeEvaluate() end
  ctx.SetGroupMode  = function(typeTable, mode) return SetGroupMode(typeTable, mode) end
  ctx.SetExclusiveAbilityMode  = function(mode) return SetExclusiveAbilityMode(mode) end
  ctx.SetExclusiveItemMode     = function(mode) return SetExclusiveItemMode(mode) end
  ctx.SetCombatFlag            = function(t, w, e) return SetCombatFlag(t, w, e) end
  ctx.SetExclusiveAuraFoundMode = function(mode) return SetExclusiveAuraFoundMode(mode) end

  -- Forward-decl helpers (may be nil at load; become valid after CreateConditionsUI)
  ctx.SetSeparator = function(...)
    if SetSeparator then return SetSeparator(...) end
  end
  ctx.ShowSeparatorsForType = function(...)
    if ShowSeparatorsForType then return ShowSeparatorsForType(...) end
  end
  ctx.ReflowCondAreaHeight = function()
    local f = _G["DoiteEdit_ReflowCondAreaHeight"]
    if f then return f() end
  end
  ctx.getAuraOwnerUpdate = function() return AuraOwner_UpdateDependentChecks end
  ctx.setAuraOwnerUpdate = function(fn) AuraOwner_UpdateDependentChecks = fn end
  ctx.InitWeaponDropdown = function(...)
    if InitWeaponDropdown then return InitWeaponDropdown(...) end
  end
  ctx.InitFormDropdown = function(...)
    if InitFormDropdown then return InitFormDropdown(...) end
  end
  ctx.SetDDEnabled = function(...)
    if _SetDDEnabled then return _SetDDEnabled(...) end
  end
  ctx.ApplySliderRanges = function()
    if _DA_ApplySliderRanges then return _DA_ApplySliderRanges() end
  end
  ctx.ComputePosSizeRanges = function()
    if _DA_ComputePosSizeRanges then return _DA_ComputePosSizeRanges() end
  end

  -- Late-defined helper for the icon editor announcement
  ctx.AnnounceEditingIcon = function(name)
    if DoiteEdit_AnnounceEditingIcon then
      return DoiteEdit_AnnounceEditingIcon(name)
    end
  end
  ctx.UpdateCondFrameForKey = function(key)
    local f = _G["DoiteEdit_UpdateCondFrameForKey"]
    if f then return f(key) end
  end

  -- Sound helpers (used by DoiteEditUIBuild.lua via ctx.*)
  ctx.SetSoundFromDropdown = function(typeKey, eventKey, value)
    return DoiteEdit_SetSoundFromDropdown(typeKey, eventKey, value)
  end
  ctx.SetSoundEnabled = function(typeKey, enabledKey, enabled)
    return DoiteEdit_SetSoundEnabled(typeKey, enabledKey, enabled)
  end
  ctx.InitSoundDropdown = function(dd, typeKey, eventKey, selectedValue)
    return DoiteEdit_InitSoundDropdown(dd, typeKey, eventKey, selectedValue)
  end

  -- Group mode dropdown helper (used by DoiteEditUIBuild.lua via ctx.*)
  ctx.AddGroupModeOption = function(typeKey, text, value)
    return DoiteEdit_AddGroupModeOption(typeKey, text, value)
  end
end

-- show/hide entry point
function DoiteConditions_Show(key)
  -- toggle: if same key and shown -> hide
  if condFrame and condFrame:IsShown() and currentKey == key then
    -- Disable mouse on the icon frame when closing edit mode
    local _GetIconFrame = DoiteAuras_GetIconFrame or function(k)
      return k and _G["DoiteIcon_" .. k]
    end
    local oldFrame = _GetIconFrame(currentKey)
    if oldFrame then
      oldFrame:EnableMouse(false)
    end

    condFrame:Hide()
    currentKey = nil
    _G["DoiteEdit_CurrentKey"] = nil   -- clear the edit override
    return
  end

  -- Jeremy: This is the main frame and cond names, this comment is just a refence for me :D
  -- create the frame if needed
  if not condFrame then
    condFrame = CreateFrame("Frame", "DoiteConditionsFrame", UIParent)

    -- Esc closes the editor (standard 1.12 mechanism).
    if UISpecialFrames then
      table.insert(UISpecialFrames, "DoiteConditionsFrame")
    end

    condFrame:SetWidth(355)
    condFrame:SetHeight(585)
    if DoiteAurasFrame and DoiteAurasFrame:GetName() then
      condFrame:SetPoint("TOPLEFT", DoiteAurasFrame, "TOPRIGHT", 5, 0)
    else
      condFrame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end

    condFrame:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 16, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    condFrame:SetBackdropColor(0, 0, 0, 1)
    condFrame:SetBackdropBorderColor(1, 1, 1, 1)
    condFrame:SetFrameStrata("FULLSCREEN_DIALOG")

    -- Close button (X) in the top-right corner, same style as Settings/Import/Export.
    -- Hiding triggers OnHide below, which does all the cleanup automatically.
    local editCloseBtn = CreateFrame("Button", "DoiteConditionsCloseBtn", condFrame, "UIPanelCloseButton")
    editCloseBtn:SetPoint("TOPRIGHT", condFrame, "TOPRIGHT", -5, -5)
    editCloseBtn:SetScript("OnClick", function()
        condFrame:Hide()
    end)
    condFrame.editCloseBtn = editCloseBtn

    -- When the conditions editor hides by any means, drop the edit override
    condFrame:SetScript("OnHide", function()

      -- Disable mouse on the icon that was being edited (fixes drag after exit bug)
      local _GetIconFrame = DoiteAuras_GetIconFrame or function(k)
        return k and _G["DoiteIcon_" .. k]
      end
      if currentKey then
        local oldFrame = _GetIconFrame(currentKey)
        if oldFrame then
          oldFrame:EnableMouse(false)
        end
      end

      _G["DoiteEdit_CurrentKey"] = nil
      currentKey = nil
      lastAnnouncedKey = nil
      _G.DoiteConditions_EditOpen = false
      _G.DoiteConditions_EditKey  = nil
      if _G["DoiteConditions"] then
        _G["DoiteConditions"]._editOpenCached = false
        _G["DoiteConditions"]._editKeyCached  = nil
      end

      -- Auto-hide Grid if shown
      if _G["DoiteGridOverlay"] and _G["DoiteGridOverlay"]:IsShown() then
        _G["DoiteGridOverlay"]:Hide()
      end

      -- kick a repaint so the formerly-forced icon can hide if conditions say so
      if DoiteConditions_RequestEvaluate then
        DoiteConditions_RequestEvaluate()
      end
      if DoiteAuras_RefreshIcons then
        DoiteAuras_RefreshIcons()
      end
      -- Clean up any bar edit injection
      if DoiteBars and DoiteBars.CleanupCondFrame then
        DoiteBars.CleanupCondFrame(condFrame)
      end
    end)

    _G["DoiteEdit_Frame"] = condFrame

    -- === Suspend heavy work while dragging the main DoiteAuras frame; flush on release ===
    if DoiteAurasFrame then
      local _oldDown = DoiteAurasFrame:GetScript("OnMouseDown")
      DoiteAurasFrame:SetScript("OnMouseDown", function(self)
        _G["DoiteUI_Dragging"] = true
        if _oldDown then
          _oldDown(self)
        end
      end)

      local _oldUp = DoiteAurasFrame:GetScript("OnMouseUp")
      DoiteAurasFrame:SetScript("OnMouseUp", function(self)
        _G["DoiteUI_Dragging"] = false
        -- ensure one final repaint after dropping the frame
        DoiteEdit_FlushHeavy()
        if _oldUp then
          _oldUp(self)
        end
      end)
    end

    condFrame.header = condFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    condFrame.header:SetPoint("TOP", condFrame, "TOP", 0, -15)
    condFrame.header:SetText("Edit:")

    condFrame.groupTitle = condFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    condFrame.groupTitle:SetPoint("TOPLEFT", condFrame, "TOPLEFT", 20, -40)
    condFrame.groupTitle:SetText("|cff6FA8DCGROUP & LEADER|r")

    local sep = condFrame:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", condFrame, "TOPLEFT", 16, -55)
    sep:SetPoint("TOPRIGHT", condFrame, "TOPRIGHT", -16, -55)
    sep:SetTexture(1, 1, 1)
    if sep.SetVertexColor then
      sep:SetVertexColor(1, 1, 1, 0.25)
    end

    condFrame.groupLabel = condFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    condFrame.groupLabel:SetPoint("TOPLEFT", condFrame, "TOPLEFT", 20, -68)
    condFrame.groupLabel:SetText("If you want to Group or Categorize this icon, select an option below:")
    condFrame.groupLabel:SetWidth(315)
    condFrame.groupLabel:SetJustifyH("LEFT")

    condFrame.growthDD = CreateFrame("Frame", "DoiteConditions_GrowthDD", condFrame, "UIDropDownMenuTemplate")
    condFrame.growthDD:SetPoint("BOTTOMLEFT", condFrame.groupLabel, "BOTTOMLEFT", -18, -43)
    if UIDropDownMenu_SetWidth then
      pcall(UIDropDownMenu_SetWidth, 110, condFrame.growthDD)
    end
    condFrame.growthDD:Hide()

    -- Number of Auras label + dropdown
    condFrame.numAurasLabel = condFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    condFrame.numAurasLabel:SetPoint("LEFT", condFrame.growthDD, "RIGHT", -5, 2)
    condFrame.numAurasLabel:SetText("Limit of Auras?")
    condFrame.numAurasLabel:Hide()

    condFrame.numAurasDD = CreateFrame("Frame", "DoiteConditions_NumAurasDD", condFrame, "UIDropDownMenuTemplate")
    condFrame.numAurasDD:SetPoint("LEFT", condFrame.numAurasLabel, "RIGHT", -10, -2)
    if UIDropDownMenu_SetWidth then
      pcall(UIDropDownMenu_SetWidth, 75, condFrame.numAurasDD)
    end
    condFrame.numAurasDD:Hide()

    -- Spacing Label + Slider + EditBox
    condFrame.spacingLabel = condFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    condFrame.spacingLabel:SetPoint("BOTTOMLEFT", condFrame.growthDD, "BOTTOMLEFT", 18, -15)
    condFrame.spacingLabel:SetText("Spacing")
    condFrame.spacingLabel:Hide()

    condFrame.spacingSlider = CreateFrame("Slider", "DoiteConditions_SpacingSlider", condFrame, "OptionsSliderTemplate")
    condFrame.spacingSlider:SetWidth(100)
    condFrame.spacingSlider:SetHeight(16)
    condFrame.spacingSlider:SetPoint("LEFT", condFrame.spacingLabel, "RIGHT", 10, 0)
    condFrame.spacingSlider:SetMinMaxValues(0, 100)
    condFrame.spacingSlider:SetValueStep(1)
    condFrame.spacingSlider:Hide()

    _G[condFrame.spacingSlider:GetName() .. 'Low']:SetText("0")
    _G[condFrame.spacingSlider:GetName() .. 'High']:SetText("100")
    _G[condFrame.spacingSlider:GetName() .. 'Text']:SetText("")

    condFrame.spacingEdit = CreateFrame("EditBox", "DoiteConditions_SpacingEdit", condFrame)
    condFrame.spacingEdit:SetWidth(30)
    condFrame.spacingEdit:SetHeight(18)
    condFrame.spacingEdit:SetPoint("LEFT", condFrame.spacingSlider, "RIGHT", 10, 0)
    StylePlainEditBox(condFrame.spacingEdit, "CENTER")
    condFrame.spacingEdit:SetMaxLetters(3)
    condFrame.spacingEdit:Hide()

    -- Functions to handle updates
    local function UpdateSpacing(val)
      if not currentKey then return end
      local d = EnsureDBEntry(currentKey)
      d.spacing = val
      if not val then d.spacing = nil end
      DoiteGroup.RequestReflow()
    end

    condFrame.spacingSlider:SetScript("OnValueChanged", function()
      local val = math.floor(this:GetValue() + 0.5)
      if condFrame.spacingEdit then
         condFrame.spacingEdit:SetText(tostring(val))
      end
      UpdateSpacing(val)
    end)

    condFrame.spacingEdit:SetScript("OnEnterPressed", function()
      this:ClearFocus()
      local val = tonumber(this:GetText()) or 0
      if val < 0 then val = 0 end
      if val > 100 then val = 100 end
      
      condFrame.spacingSlider:SetValue(val)
      UpdateSpacing(val)
      this:SetText(tostring(val))
    end)

    condFrame.spacingEdit:SetScript("OnEscapePressed", function()
      this:ClearFocus()
      local val = math.floor(condFrame.spacingSlider:GetValue() + 0.5)
      this:SetText(tostring(val))
    end)

    condFrame.InitGrowthDropdown = InitGrowthDropdown
    condFrame.InitNumAurasDropdown = InitNumAurasDropdown

    if DoiteGroup and DoiteGroup.AttachEditGroupUI then
      DoiteGroup.AttachEditGroupUI(condFrame, {
        Ensure = EnsureDBEntry,
        SafeRefresh = SafeRefresh,
        SafeEvaluate = SafeEvaluate,
        ListRefresh = DoiteAuras_RefreshList,
        UpdateEditor = UpdateCondFrameForKey,
      })
    end

    condFrame.groupTitle2 = condFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    condFrame.groupTitle2:SetPoint("TOPLEFT", condFrame, "TOPLEFT", 20, -155)
    condFrame.groupTitle2:SetText("|cff6FA8DCCONDITIONS & RULES|r")

    local sep2 = condFrame:CreateTexture(nil, "ARTWORK")
    sep2:SetHeight(1)
    sep2:SetPoint("TOPLEFT", condFrame, "TOPLEFT", 16, -170)
    sep2:SetPoint("TOPRIGHT", condFrame, "TOPRIGHT", -16, -170)
    sep2:SetTexture(1, 1, 1)
    if sep2.SetVertexColor then
      sep2:SetVertexColor(1, 1, 1, 0.25)
    end

    -- === Scrollable container for CONDITIONS & RULES (no size/pos changes elsewhere) ===

    if not condFrame.condListContainer then
      local cW = condFrame:GetWidth() - 43
      local cH = 190

      local listContainer = CreateFrame("Frame", nil, condFrame)
      listContainer:SetWidth(cW)
      listContainer:SetHeight(cH)
      listContainer:SetPoint("TOPLEFT", condFrame, "TOPLEFT", 14, -173)
      listContainer:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16
      })
      listContainer:SetBackdropColor(0, 0, 0, 0.7)
      condFrame.condListContainer = listContainer

      local scrollFrame = CreateFrame("ScrollFrame", "DoiteConditionsScroll", listContainer, "UIPanelScrollFrameTemplate")
      scrollFrame:SetWidth(cW - 20)
      scrollFrame:SetHeight(cH - 9)
      scrollFrame:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 12, -5)
      condFrame.condScrollFrame = scrollFrame
      condFrame._scrollFrame = scrollFrame

      local listContent = CreateFrame("Frame", "DoiteConditionsListContent", scrollFrame)
      listContent:SetWidth(cW - 20)
      listContent:SetHeight(cH - 10)
      scrollFrame:SetScrollChild(listContent)
      condFrame._condArea = listContent

      listContent:SetHeight(900)

      -- 2) Make absolutely sure the visual stacking (levels) keeps the backdrop under the controls.
      local baseLevel = condFrame:GetFrameLevel() or 1
      listContainer:SetFrameLevel(baseLevel + 0)
      scrollFrame:SetFrameLevel(baseLevel + 1)
      listContent:SetFrameLevel(baseLevel + 2)

      -- Optional (helps click/scroll behavior feel solid)
      if scrollFrame.EnableMouseWheel then
        scrollFrame:EnableMouseWheel(true)
      end
    end

    -- Create the Conditions UI section (self-contained; lives in DoiteEditUIBuild.lua)
    local _buildUI = _G["DoiteEdit_CreateConditionsUI"]
    if _buildUI then _buildUI() end

    condFrame.groupTitle3 = condFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    condFrame.groupTitle3:SetPoint("TOPLEFT", condFrame, "TOPLEFT", 20, -375)
    condFrame.groupTitle3:SetText("|cff6FA8DCPOSITION & SIZE|r")

    condFrame.sep3 = condFrame:CreateTexture(nil, "ARTWORK")
    condFrame.sep3:SetHeight(1)
    condFrame.sep3:SetPoint("TOPLEFT", condFrame, "TOPLEFT", 16, -390)
    condFrame.sep3:SetPoint("TOPRIGHT", condFrame, "TOPRIGHT", -16, -390)
    condFrame.sep3:SetTexture(1, 1, 1)
    if condFrame.sep3.SetVertexColor then
      condFrame.sep3:SetVertexColor(1, 1, 1, 0.25)
    end
	
	-- Show Grid button
    local gridBtn = CreateFrame("Button", "DoiteConditions_GridBtn", condFrame, "UIPanelButtonTemplate")
    gridBtn:SetWidth(80)
    gridBtn:SetHeight(20)
	gridBtn:ClearAllPoints()
    gridBtn:SetPoint("LEFT", condFrame.groupTitle3, "RIGHT", 140, 3)
    gridBtn:SetText("Show Grid")
    gridBtn:SetScript("OnClick", function()
        DoiteEdit_ToggleGrid()
        if DoiteEdit_IsGridShown() then
            gridBtn:SetText("Hide Grid")
        else
            gridBtn:SetText("Show Grid")
        end
    end)
    -- Ensure distinct Draw Layer to not hide under standard dialog art
    gridBtn:SetFrameLevel(condFrame:GetFrameLevel() + 5)
    condFrame.gridBtn = gridBtn

    -- Custom-function Save button (to the left of Grid button, same row)
    local customSaveBtn = CreateFrame("Button", "DoiteConditions_CustomSaveBtn", condFrame, "UIPanelButtonTemplate")
    customSaveBtn:SetWidth(70)
    customSaveBtn:SetHeight(20)
    customSaveBtn:SetPoint("RIGHT", gridBtn, "LEFT", -8, 0)
    customSaveBtn:SetText("Save")
    customSaveBtn:SetFrameLevel(condFrame:GetFrameLevel() + 5)
    customSaveBtn:Hide()
    condFrame.cond_custom_function_save = customSaveBtn

    local customStatusText = condFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customStatusText:SetPoint("RIGHT", customSaveBtn, "LEFT", -8, 0)
    customStatusText:SetTextColor(0.7, 0.7, 0.7)
    customStatusText:SetText("")
    condFrame.cond_custom_function_status = customStatusText

    customSaveBtn:SetScript("OnClick", function()
      if not currentKey then
        return
      end

      local edit = condFrame and condFrame.cond_custom_function_edit
      local source = (edit and edit.GetText and edit:GetText()) or ""
      local fn, err = CompileCustomFunctionSource(source)
      if not fn then
        if condFrame and condFrame.cond_custom_function_status then
          condFrame.cond_custom_function_status:SetText("|cffff4040Error|r")
        end
        if DEFAULT_CHAT_FRAME then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff4040DoiteAuras: Custom function compile error:|r " .. tostring(err))
        end
        return
      end

      local d = EnsureDBEntry(currentKey)
      local okRun, show, texture, hideBackground, remaining, stacks = pcall(fn, {})
      if not okRun then
        if condFrame and condFrame.cond_custom_function_status then
          condFrame.cond_custom_function_status:SetText("|cffff4040Error|r")
        end
        if DEFAULT_CHAT_FRAME then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff4040DoiteAuras: Custom function runtime error:|r " .. tostring(show))
        end
        return
      end

      d.customFunctionSource = source
      d._daCustomCompiled = fn
      d._daCustomCompiledSrc = source
      -- Runtime-only per-key state: not saved to SavedVariables.
      local dc = _G["DoiteConditions"]
      if dc then
        dc._customStateByKey = dc._customStateByKey or {}
        dc._customStateByKey[currentKey] = {}
      end
      d._daCustomShow = (show == true or show == 1)
      d._daCustomTexture = (type(texture) == "string" and texture ~= "") and texture or nil
      d._daCustomHideBG = (hideBackground == true)
      d._daCustomRemaining = (type(remaining) == "number") and remaining or nil
      d._daCustomStacks = (type(stacks) == "number") and stacks or nil

      if condFrame and condFrame.cond_custom_function_status then
        condFrame.cond_custom_function_status:SetText("|cff22ff22Saved|r")
      end

      if DoiteConditions_RequestEvaluate then
        DoiteConditions_RequestEvaluate()
      end
      if DoiteAuras_RefreshIcons then
        DoiteAuras_RefreshIcons()
      end
    end)

    -- Sliders helper (makes a slider + small EditBox beneath it)
    local function MakeSlider(name, text, x, y, width, minVal, maxVal, step)
      local s = CreateFrame("Slider", name, condFrame, "OptionsSliderTemplate")
      s:SetWidth(width)
      s:SetHeight(16)
      s:SetMinMaxValues(minVal, maxVal)
      s:SetValueStep(step)
      s:SetPoint("TOPLEFT", condFrame, "TOPLEFT", x, y)

      local txt = _G[s:GetName() .. 'Text']
      local low = _G[s:GetName() .. 'Low']
      local high = _G[s:GetName() .. 'High']
      if txt then
        txt:SetText(text);
        txt:SetFontObject("GameFontNormalSmall")
      end
      if low then
        low:SetText(tostring(minVal));
        low:SetFontObject("GameFontNormalSmall")
      end
      if high then
        high:SetText(tostring(maxVal));
        high:SetFontObject("GameFontNormalSmall")
      end

      -- tiny EditBox below slider
      local eb = CreateFrame("EditBox", name .. "_EditBox", condFrame)
      eb:SetWidth(33);
      eb:SetHeight(18)
      eb:SetPoint("TOP", s, "BOTTOM", 3, -8)
      eb:SetText("0")
      StylePlainEditBox(eb, "CENTER")
      eb.slider = s
      eb._updating = false

      -- slider -> editbox (robust, avoids recursion)
      s:SetScript("OnValueChanged", function(self, value)
        local frame = self or s
        if frame._isSyncing then return end
        local v = tonumber(value)
        if not v and frame and frame.GetValue then
          v = frame:GetValue()
        end
        if not v then
          return
        end
        v = math.floor(v + 0.5)
        if eb and eb.SetText and not eb._updating then
          eb._updating = true
          eb:SetText(tostring(v))
          eb._updating = false
        end
        if frame and frame.updateFunc then
          frame.updateFunc(v)
        end
      end)

      -- mark “dragging” while the slider is held
      s:SetScript("OnMouseDown", function()
        _G["DoiteUI_Dragging"] = true
      end)

      -- on release: stop pausing and do a single heavy repaint
      s:SetScript("OnMouseUp", function()
        _G["DoiteUI_Dragging"] = false
        DoiteEdit_FlushHeavy()
      end)

      -- editbox commit helper (clamp + set slider)
      local function CommitEditBox(box)
        if not box or not box.slider then
          return
        end
        local sref = box.slider
        local txt = box:GetText()
        local val = tonumber(txt)
        if not val then
          -- revert to slider's current rounded value
          local cur = math.floor((sref:GetValue() or 0) + 0.5)
          box:SetText(tostring(cur))
        else
          if val < minVal then
            val = minVal
          end
          if val > maxVal then
            val = maxVal
          end
          -- set value on slider; OnValueChanged will handle DB update via updateFunc
          box._updating = true
          sref:SetValue(val)
          box._updating = false
        end
      end

      -- editbox -> slider while typing
      eb:SetScript("OnTextChanged", function()
        if this._updating then
          return
        end
        local txt = this:GetText()
        local num = tonumber(txt)
        if not num then
          return
        end

        -- clamp to slider bounds captured in MakeSlider
        if num < minVal then
          num = minVal
        end
        if num > maxVal then
          num = maxVal
        end

        -- drive the slider; its OnValueChanged will push to DB via updateFunc(...)
        this._updating = true
        this.slider:SetValue(num)
        this._updating = false
      end)

      eb:SetScript("OnEnterPressed", function(self)
        CommitEditBox(self)
        if self and self.ClearFocus then
          self:ClearFocus()
        end
      end)

      eb:SetScript("OnEscapePressed", function()
        if this.ClearFocus then
          this:ClearFocus()
        end
        -- also restore the current slider value visually
        local cur = math.floor((this.slider:GetValue() or 0) + 0.5)
        this._updating = true
        this:SetText(tostring(cur))
        this._updating = false
      end)

      eb:SetScript("OnEditFocusLost", function()
        CommitEditBox(this)
      end)

      return s, eb
    end

    -- slider widths (leave left margin + spacing)
    local totalAvailable = condFrame:GetWidth() - 60
    local sliderWidth = math.floor((totalAvailable - 20) / 3)
    if sliderWidth < 100 then
      sliderWidth = 100
    end

    local baseX = 20
    local baseY = -410
    local gap = 8

    do
      local minX, maxX, minY, maxY, minSize, maxSize = _DA_ComputePosSizeRanges()

      condFrame.sliderX, condFrame.sliderXBox = MakeSlider("DoiteConditions_SliderX", "Horizontal Position", baseX, baseY, sliderWidth, minX, maxX, 1)
      condFrame.sliderY, condFrame.sliderYBox = MakeSlider("DoiteConditions_SliderY", "Vertical Position", baseX + sliderWidth + gap, baseY, sliderWidth, minY, maxY, 1)
      condFrame.sliderSize, condFrame.sliderSizeBox = MakeSlider("DoiteConditions_SliderSize", "Icon Size", baseX + 2 * (sliderWidth + gap), baseY, sliderWidth, minSize, maxSize, 1)
    end


    -- update functions that the slider will call when changed
    condFrame.sliderX.updateFunc = function(value)
      if not currentKey then
        return
      end
      local d = EnsureDBEntry(currentKey)
      d.offsetX = value
      DoiteEdit_QueueHeavy()
    end
    condFrame.sliderY.updateFunc = function(value)
      if not currentKey then
        return
      end
      local d = EnsureDBEntry(currentKey)
      d.offsetY = value
      DoiteEdit_QueueHeavy()
    end
    condFrame.sliderSize.updateFunc = function(value)
      if not currentKey then
        return
      end
      local d = EnsureDBEntry(currentKey)
      d.iconSize = value
      DoiteEdit_QueueHeavy()
    end


    -- ==================================================================
    -- FONT OVERRIDES (per-icon)
    --
    -- Each field independently overrides the global Settings value.
    --   DB field == nil  -> inherit from Settings (grey text)
    --   DB field == value -> override for this icon (gold text)
    --
    -- "" is a valid override for flags ("None"), distinct from nil.
    -- ==================================================================

    -- Container frame (moved dynamically in UpdateCondFrameForKey)
    condFrame.fontContainer = CreateFrame("Frame", nil, condFrame)
    condFrame.fontContainer:SetWidth(330)
    condFrame.fontContainer:SetHeight(100)
    condFrame.fontContainer:SetPoint("TOPLEFT", condFrame, "TOPLEFT", 15, -460)
    local fc = condFrame.fontContainer

    condFrame.fontTitle = fc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    condFrame.fontTitle:SetPoint("TOPLEFT", fc, "TOPLEFT", 5, 0)
    condFrame.fontTitle:SetText("|cff6FA8DCFONT OVERRIDES|r")

    local fontSep2 = fc:CreateTexture(nil, "ARTWORK")
    fontSep2:SetHeight(1)
    fontSep2:SetPoint("TOPLEFT", fc, "TOPLEFT", 0, -15)
    fontSep2:SetPoint("TOPRIGHT", fc, "TOPRIGHT", 0, -15)
    fontSep2:SetTexture(1, 1, 1)
    if fontSep2.SetVertexColor then fontSep2:SetVertexColor(1, 1, 1, 0.25) end

    -- Lightweight refresh for a single size box: updates text + colour only.
    -- Replaces the heavier UpdateCondFrameForKey(currentKey) call, which
    -- rebuilt the entire conditions UI on every focus change.
    local function _RefreshSizeBoxDisplay(box, dbField)
        if not box then return end
        local fdb = DoiteAurasDB or {}
        local d = (currentKey
                   and DoiteAurasDB
                   and DoiteAurasDB.spells
                   and DoiteAurasDB.spells[currentKey]) or {}

        local override
        local effective
        if dbField == "timerFontSize" then
            override  = tonumber(d.timerFontSize)
            effective = override or tonumber(fdb.timerFontSize) or 15
        else
            override  = tonumber(d.stackFontSize)
            effective = override or tonumber(fdb.stackFontSize) or 10
        end

        box:SetText(tostring(effective))
        if override then
            box:SetTextColor(1, 0.82, 0)       -- gold = override
        else
            box:SetTextColor(0.5, 0.5, 0.5)    -- grey = inherit
        end
    end


    -- Size edit box: shows effective value; gold = override, grey = inherit.
    -- Clearing/Escape resets to nil (inherit).
    local function _MakeEditSizeBox(parent, x, y, dbField)
        local box = CreateFrame("EditBox", nil, parent)
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


        box._dbField = dbField

        box:SetScript("OnEditFocusLost", function()
            if not currentKey then return end

            -- If Escape was just pressed, skip the save-from-text step;
            -- OnEscapePressed already cleared the value to nil (inherit).
            if box._daSkipFocusLost then
                box._daSkipFocusLost = nil
                _RefreshSizeBoxDisplay(this, dbField)
                _ApplyFontsNowEdit()
                return
            end

            local txt = this:GetText() or ""
            local v = tonumber(txt)
            local d = EnsureDBEntry(currentKey)
            if v and v >= 4 and v <= 48 then
                d[dbField] = math.floor(v + 0.5)
            else
                d[dbField] = nil  -- inherit
            end

            -- Lightweight refresh: only this box's text/colour.
            _RefreshSizeBoxDisplay(this, dbField)
            _ApplyFontsNowEdit()
        end)

        box:SetScript("OnEnterPressed", function() this:ClearFocus() end)

        box:SetScript("OnEscapePressed", function()
            if currentKey then
                local d = EnsureDBEntry(currentKey)
                d[dbField] = nil
            end

            -- Suppress the save step in OnEditFocusLost (see above),
            -- then blur — that will run the skip branch.
            box._daSkipFocusLost = true
            this:ClearFocus()
        end)

        return box
    end


    -- Dropdown with an explicit "Inherit" option at the top.
    local function _MakeEditDropdown(name, parent, x, y, width, dbField, choices, labelFn)
        local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
        dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y)
        if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(width, dd) end

        dd._dbField = dbField
        dd._choices = choices
        dd._labelFn = labelFn

        UIDropDownMenu_Initialize(dd, function()
            local d = (DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[currentKey]) or {}
            local cur = d[dbField]

            -- Inherit option
            local info = UIDropDownMenu_CreateInfo()
            info.text    = "Inherit"
            info.value   = "__inherit__"
            info.checked = (cur == nil)
            info.func = function()
                if currentKey then
                    local d2 = EnsureDBEntry(currentKey)
                    d2[dbField] = nil
                end
                UIDropDownMenu_SetSelectedValue(dd, "__inherit__")
                UIDropDownMenu_SetText("Inherit", dd)
                _ApplyFontsNowEdit()
            end
            UIDropDownMenu_AddButton(info)

            -- Actual choices
            local i
            for i = 1, table.getn(choices) do
                local opt = choices[i]
                local info2 = UIDropDownMenu_CreateInfo()
                info2.text    = opt.text
                info2.value   = opt.value
                info2.checked = (cur == opt.value)
                info2.func = function(button)
                    local picked = (button and button.value) or opt.value
                    if currentKey then
                        local d2 = EnsureDBEntry(currentKey)
                        d2[dbField] = picked
                    end
                    UIDropDownMenu_SetSelectedValue(dd, picked)
                    UIDropDownMenu_SetText(opt.text, dd)
                    _ApplyFontsNowEdit()
                end
                UIDropDownMenu_AddButton(info2)
            end
        end)

        local t = _G[dd:GetName() .. "Text"]
        if t and t.SetTextColor then t:SetTextColor(1, 0.82, 0) end
        return dd
    end

    ---------------------------------------------------------------
    -- Timer row:  Label | Size | Font | Flag
    ---------------------------------------------------------------
    local TIMER_ROW_Y  = -25
    local STACKS_ROW_Y = -55

    local timerLblEdit = fc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerLblEdit:SetPoint("TOPLEFT", fc, "TOPLEFT", 5, TIMER_ROW_Y)
    timerLblEdit:SetText("Timer:")
    if timerLblEdit.SetTextColor then timerLblEdit:SetTextColor(1, 0.82, 0) end

    condFrame.fontTimerSize = _MakeEditSizeBox(
        fc, 40, TIMER_ROW_Y + 2, "timerFontSize"
    )

    condFrame.fontTimerFontDD = _MakeEditDropdown(
        "DoiteEdit_TimerFontDD", fc, 75, TIMER_ROW_Y + 6, 90,
        "timerFontPath", FONT_CHOICES_EDIT, _EditFontLabelForValue
    )

    condFrame.fontTimerFlagDD = _MakeEditDropdown(
        "DoiteEdit_TimerFlagDD", fc, 190, TIMER_ROW_Y + 6, 70,
        "timerFontFlags", FLAG_CHOICES_EDIT, _EditFlagLabelForValue
    )

    ---------------------------------------------------------------
    -- Stacks row:  Label | Size | Font | Flag
    ---------------------------------------------------------------
    local stackLblEdit = fc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stackLblEdit:SetPoint("TOPLEFT", fc, "TOPLEFT", 5, STACKS_ROW_Y)
    stackLblEdit:SetText("Stacks:")
    if stackLblEdit.SetTextColor then stackLblEdit:SetTextColor(1, 0.82, 0) end

    condFrame.fontStackSize = _MakeEditSizeBox(
        fc, 40, STACKS_ROW_Y + 2, "stackFontSize"
    )

    condFrame.fontStackFontDD = _MakeEditDropdown(
        "DoiteEdit_StackFontDD", fc, 75, STACKS_ROW_Y + 6, 90,
        "stackFontPath", FONT_CHOICES_EDIT, _EditFontLabelForValue
    )

    condFrame.fontStackFlagDD = _MakeEditDropdown(
        "DoiteEdit_StackFlagDD", fc, 190, STACKS_ROW_Y + 6, 70,
        "stackFontFlags", FLAG_CHOICES_EDIT, _EditFlagLabelForValue
    )

    -- Hint
    local fontHintEdit = fc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fontHintEdit:SetPoint("TOPLEFT", fc, "TOPLEFT", 5, -82)
    fontHintEdit:SetWidth(320)
    fontHintEdit:SetJustifyH("LEFT")
    if fontHintEdit.SetTextColor then fontHintEdit:SetTextColor(0.6, 0.6, 0.6) end
    fontHintEdit:SetText("Grey = inherits Settings. Gold = override for this icon.")

    -- (Grid Controls removed by request)

    -- Keep slider ranges in sync with current resolution/UI scale every time the panel shows
    condFrame:SetScript("OnShow", function(self)
      _DA_ApplySliderRanges()

      -- Show Grid by default when editor opens
      if not DoiteEdit_IsGridShown() then
        DoiteEdit_ToggleGrid()
      end
      if condFrame.gridBtn then
        condFrame.gridBtn:SetText("Hide Grid")
      end
    end)

    -- Initially hidden position section
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

    -- When the main DoiteAuras frame hides, hide the cond frame too
    if DoiteAurasFrame then
      local oldHide = DoiteAurasFrame:GetScript("OnHide")
      DoiteAurasFrame:SetScript("OnHide", function(self)
        if condFrame then
          condFrame:Hide()
        end
        if oldHide then
          oldHide(self)
        end
      end)
    end
  end

  -- Ensure Grid is shown by default when editing starts
  if not DoiteEdit_IsGridShown() then
    DoiteEdit_ToggleGrid()
  end
  if condFrame.gridBtn then
    condFrame.gridBtn:SetText("Hide Grid")
  end

  condFrame:Show()
  UpdateCondFrameForKey(key)

  -- Принудительно обновить кэш edit-состояния
  _G.DoiteConditions_EditOpen = true
  _G.DoiteConditions_EditKey  = key
  if _G["DoiteConditions"] then
    _G["DoiteConditions"]._editOpenCached = true
    _G["DoiteConditions"]._editKeyCached  = key
  end
end
