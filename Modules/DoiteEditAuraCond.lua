---------------------------------------------------------------
-- DoiteEditAuraCond.lua
-- Aura Conditions manager for the Edit panel.
-- Extracted from DoiteEdit.lua (Phase 6 of the split).
--
-- Public globals:
--   AuraCond_Managers
--   AuraCond_RegisterManager
--   AuraCond_RefreshFromDB
--   AuraCond_ResetEditing
--
-- Loaded AFTER DoiteEdit.lua (needs DoiteEditCtx populated).
-- Uses ctx getters/setters for currentKey, EnsureDBEntry,
-- SafeRefresh/SafeEvaluate, ClearDropdown and ReflowCondAreaHeight.
---------------------------------------------------------------

local ctx = _G["DoiteEditCtx"]
if not ctx then
  return
end

-- Local aliases: hide ctx plumbing from the extracted code.
local function _EnsureDBEntry(k)   return ctx.EnsureDBEntry(k)   end
local function _SafeRefresh()       ctx.SafeRefresh()            end
local function _SafeEvaluate()      ctx.SafeEvaluate()           end
local function _ClearDropdown(dd)  return ctx.ClearDropdown(dd)  end
local function _Reflow()            ctx.ReflowCondAreaHeight()   end
local function _TitleCase(s)
  local f = _G["DoiteEdit_AuraCond_TitleCase"]
  if f then return f(s) end
  return s or ""
end
local _ParseFadeAlpha            = _G["DoiteEdit_ParseFadeAlphaFromBox"]
local _NormalizeFade             = _G["DoiteEdit_NormalizeFadeBox"]
local function _UpdateCondFrameForKey(k)
  local ctxU = _G["DoiteEditCtx"]
  if ctxU and ctxU.UpdateCondFrameForKey then
    ctxU.UpdateCondFrameForKey(k)
  end
end

local AuraCond_Managers = {}
local AuraCond_RegisterManager
local AuraCond_RefreshFromDB
local AuraCond_ResetEditing

-- Dynamic "Aura Conditions" manager (Ability / Aura / Item)
do
  -- Small helper to reopen the dropdown a frame later (like the item version)
  local _ddReopenFrame = CreateFrame("Frame", "DoiteEditReopenFrame")
  local _ddReopenRow = nil

  _ddReopenFrame:Hide()
  _ddReopenFrame:SetScript("OnUpdate", function()
    _ddReopenFrame:Hide()
    if not _ddReopenRow or not _ddReopenRow.abilityDD then
      _ddReopenRow = nil
      return
    end
    ToggleDropDownMenu(nil, nil, _ddReopenRow.abilityDD, _ddReopenRow.abilityDD, 0, 0)
    _ddReopenRow = nil
  end)

  local function AuraCond_ReopenDDNextFrame(row)
    _ddReopenRow = row
    _ddReopenFrame:Show()
  end

  local function AuraCond_Len(t)
    if not t then
      return 0
    end
    local n = 0
    while t[n + 1] ~= nil do
      n = n + 1
    end
    return n
  end

  local function AuraCond_GetListForType(typeKey)
    local ck = _G["DoiteEdit_CurrentKey"]
    if not ck or not DoiteAurasDB or not DoiteAurasDB.spells then
      return nil
    end
    local d = _EnsureDBEntry(ck)
    if not d or not d.conditions then
      return nil
    end

    if typeKey == "ability" then
      d.conditions.ability = d.conditions.ability or {}
      d.conditions.ability.auraConditions = d.conditions.ability.auraConditions or {}
      return d.conditions.ability.auraConditions
    elseif typeKey == "aura" then
      d.conditions.aura = d.conditions.aura or {}
      d.conditions.aura.auraConditions = d.conditions.aura.auraConditions or {}
      return d.conditions.aura.auraConditions
    elseif typeKey == "item" then
      d.conditions.item = d.conditions.item or {}
      d.conditions.item.auraConditions = d.conditions.item.auraConditions or {}
      return d.conditions.item.auraConditions
    end
    return nil
  end

  local function AuraCond_BuildAbilitySpellList()
    local spells = {}
    local seen = {}
    local passiveAllow = _G["DA_AbilityDropdownPassiveAllow"] or {}

    local function scanBook(bookType)
      local i = 1
      while true do
        local name, rank = GetSpellName(i, bookType)
        if not name then
          break
        end

        local isPassive = false
        if IsPassiveSpell then
          local ok, passive = pcall(IsPassiveSpell, i, bookType)
          if ok and passive then
            isPassive = true
          end
        end
        if (not isPassive) and rank and string.find(rank, "Passive") then
          isPassive = true
        end

        if name and name ~= "" then
          local allowPassive = (passiveAllow[name] == true)
          if ((not isPassive) or allowPassive) and not seen[name] then
            table.insert(spells, name)
            seen[name] = true
          end
        end

        i = i + 1
      end
    end

    scanBook(BOOKTYPE_SPELL)
    scanBook(BOOKTYPE_PET)

    table.sort(spells, function(a, b)
      a = string.lower(a or "")
      b = string.lower(b or "")
      return a < b
    end)

    return spells
  end

  local function AuraCond_InitAbilityDropdown(row)
    if not row or not row.abilityDD then
      return
    end

    local spells = AuraCond_BuildAbilitySpellList()
    row._abilitySpells = spells

    local total = table.getn(spells)
    local perPage = 10

    if total == 0 then
      UIDropDownMenu_Initialize(row.abilityDD, function()
      end)
      if UIDropDownMenu_SetText then
        pcall(UIDropDownMenu_SetText, "No abilities found", row.abilityDD)
      end
      return
    end

    local maxPage = math.max(1, math.ceil(total / perPage))
    local page = row._abilityPage or 1
    if page < 1 then
      page = 1
    end
    if page > maxPage then
      page = maxPage
    end
    row._abilityPage = page

    local startIndex = (page - 1) * perPage + 1
    local endIndex = math.min(startIndex + perPage - 1, total)

    UIDropDownMenu_Initialize(row.abilityDD, function(frame, level, menuList)
      local info

      if page > 1 then
        info = {}
        info.text = "|cffffd000<< Previous|r"
        info.value = "PREV"
        info.notCheckable = true
        info.func = function()
          row._abilityPage = page - 1
          AuraCond_InitAbilityDropdown(row)
          AuraCond_ReopenDDNextFrame(row)
        end
        UIDropDownMenu_AddButton(info)
      end

      local idx = startIndex
      while idx <= endIndex do
        local name = spells[idx]
        info = {}
        info.text = name
        info.value = name
        local pickedName = name
        info.func = function(button)
          local val = (button and button.value) or pickedName
          row._spellName = val
          if UIDropDownMenu_SetSelectedValue then
            pcall(UIDropDownMenu_SetSelectedValue, row.abilityDD, val)
          end
          if UIDropDownMenu_SetText then
            pcall(UIDropDownMenu_SetText, val, row.abilityDD)
          end
          if _GoldifyDD then
            _GoldifyDD(row.abilityDD)
          end
        end
        info.checked = (row._spellName == name)
        UIDropDownMenu_AddButton(info)
        idx = idx + 1
      end

      if page < maxPage then
        info = {}
        info.text = "|cffffd000Next >>|r"
        info.value = "NEXT"
        info.notCheckable = true
        info.func = function()
          row._abilityPage = page + 1
          AuraCond_InitAbilityDropdown(row)
          AuraCond_ReopenDDNextFrame(row)
        end
        UIDropDownMenu_AddButton(info)
      end
    end)

    local label = row._spellName or "Select ability"
    if UIDropDownMenu_SetText then
      pcall(UIDropDownMenu_SetText, label, row.abilityDD)
    end
    if _GoldifyDD then
      _GoldifyDD(row.abilityDD)
    end
  end

  local function AuraCond_BuildItemOptions()
    local items, seen = {}, {}
    local function _Add(name)
      if not name or name == "" or seen[name] then return end
      seen[name] = true
      table.insert(items, name)
    end
    local function _NameFromId(itemId)
      if not itemId then return nil end
      local nm = GetItemInfo and GetItemInfo(itemId)
      if nm and nm ~= "" then return nm end
      return nil
    end
    local slots = {13, 14, 16, 17, 18}
    local i
    for i = 1, table.getn(slots) do
      local info = GetEquippedItem and GetEquippedItem("player", slots[i])
      _Add(_NameFromId(info and info.itemId))
    end
    local bags = GetBagItems and GetBagItems()
    if bags then
      local bag = 0
      while bag <= 4 do
        local bagData = bags[bag]
        if bagData then
          local slot, itemInfo
          for slot, itemInfo in pairs(bagData) do
            _Add(_NameFromId(itemInfo and itemInfo.itemId))
          end
        end
        bag = bag + 1
      end
    end
    table.sort(items, function(a, b)
      return string.lower(a or "") < string.lower(b or "")
    end)
    table.insert(items, 1, "---EQUIPPED WEAPON SLOTS---")
    table.insert(items, 1, "---EQUIPPED TRINKET SLOTS---")
    return items
  end

  local function AuraCond_InitItemDropdown(row)
    if not row or not row.itemDD then return end

    local items = AuraCond_BuildItemOptions()
    row._itemOptions = items

    local total = table.getn(items)
    local perPage = 10

    if total == 0 then
      UIDropDownMenu_Initialize(row.itemDD, function() end)
      if UIDropDownMenu_SetText then
        pcall(UIDropDownMenu_SetText, "No items found", row.itemDD)
      end
      return
    end

    local maxPage = math.max(1, math.ceil(total / perPage))
    local page = row._itemPage or 1
    if page < 1 then page = 1 end
    if page > maxPage then page = maxPage end
    row._itemPage = page

    local function ReopenItemDDNextFrame()
      local f = row.itemDD and row.itemDD._reopenFrame
      if not f then
        f = CreateFrame("Frame", nil, UIParent)
        if row.itemDD then
          row.itemDD._reopenFrame = f
        end
        f:Hide()
        f:SetScript("OnUpdate", function()
          f:Hide()
          if row and row.itemDD then
            ToggleDropDownMenu(nil, nil, row.itemDD, row.itemDD, 0, 0)
          end
        end)
      end
      f:Show()
    end

    local startIndex = (page - 1) * perPage + 1
    local endIndex = math.min(startIndex + perPage - 1, total)

    UIDropDownMenu_Initialize(row.itemDD, function(frame, level, menuList)
      local info

      if page > 1 then
        info = {}
        info.text = "|cffffd000<< Previous|r"
        info.value = "PREV"
        info.notCheckable = true
        info.func = function()
          row._itemPage = page - 1
          AuraCond_InitItemDropdown(row)
          if CloseDropDownMenus then
            CloseDropDownMenus()
          end
          ReopenItemDDNextFrame()
        end
        UIDropDownMenu_AddButton(info)
      end

      local idx = startIndex
      while idx <= endIndex do
        local name = items[idx]
        info = {}
        info.text = name
        info.value = name
        local pickedName = name
        info.func = function(button)
          local val = (button and button.value) or pickedName
          row._itemName = val
          if UIDropDownMenu_SetSelectedValue then
            pcall(UIDropDownMenu_SetSelectedValue, row.itemDD, val)
          end
          if UIDropDownMenu_SetText then
            pcall(UIDropDownMenu_SetText, val, row.itemDD)
          end
          if _GoldifyDD then
            _GoldifyDD(row.itemDD)
          end
        end
        info.checked = (row._itemName == name)
        UIDropDownMenu_AddButton(info)
        idx = idx + 1
      end

      if page < maxPage then
        info = {}
        info.text = "|cffffd000Next >>|r"
        info.value = "NEXT"
        info.notCheckable = true
        info.func = function()
          row._itemPage = page + 1
          AuraCond_InitItemDropdown(row)
          if CloseDropDownMenus then
            CloseDropDownMenus()
          end
          ReopenItemDDNextFrame()
        end
        UIDropDownMenu_AddButton(info)
      end
    end)

    if UIDropDownMenu_SetText then
      pcall(UIDropDownMenu_SetText, row._itemName or "Select item", row.itemDD)
    end
    if _GoldifyDD then
      _GoldifyDD(row.itemDD)
    end
  end

  local function AuraCond_BuildDescription(buffType, mode, unit, name, stacksEnabled, stacksComp, stacksVal)
    local niceName = _TitleCase(name or "")

    local yellow = "|cffffd000"
    local white  = "|cffffffff"
    local sep    = "|cffffffff | |r"

    if buffType == "ABILITY" then
      local typeColor = "|cff4da6ff"
      local typePart = typeColor .. "Ability" .. "|r"

      local modeWord
      if mode == "oncd" or mode == "usableoncd" or mode == "nocdoncd" then
        modeWord = "On CD"
      else
        modeWord = "Not on CD"
      end
      local modePart = yellow .. modeWord .. "|r"
      local namePart = white .. (niceName or "") .. "|r"

      return typePart .. " " .. sep .. modePart .. ": " .. namePart

    elseif buffType == "TALENT" then
      local modeStr = mode or ""
      local lower = string.lower(modeStr)

      local isKnown = (lower == "known")
      local stateWord
      if isKnown then
        stateWord = "Known"
      else
        stateWord = "Not known"
      end

      local stateColor = isKnown and "|cff00ff00" or "|cffff0000"
      local statePart = stateColor .. stateWord .. "|r"

      local talentPart = yellow .. "Talent" .. "|r"
      local namePart = white .. (niceName or "") .. "|r"

      return talentPart .. " " .. sep .. statePart .. ": " .. namePart
    elseif buffType == "ITEM" then
      local whereWord = (mode == "missing") and "Missing" or "In bag/equipped"
      local cdWord = (unit == "oncd") and "On CD" or "Not on CD"
      local itemPart = yellow .. "Item" .. "|r"
      local wherePart = yellow .. whereWord .. "|r"

      local prefix = ""
      if stacksEnabled and stacksComp and stacksComp ~= "" and stacksVal and tostring(stacksVal) ~= "" then
        local sym = stacksComp
        if sym == ">=" then sym = "\226\137\165"
        elseif sym == "<=" then sym = "\226\137\164"
        elseif sym == "==" then sym = "="
        end
        prefix = tostring(sym) .. tostring(stacksVal) .. "x"
      end

      local namePart = white .. prefix .. (niceName or "") .. "|r"

      if mode == "missing" then
        return itemPart .. " " .. sep .. wherePart .. ": " .. namePart
      end

      local cdPart = yellow .. cdWord .. "|r"
      return itemPart .. " " .. sep .. wherePart .. " " .. sep .. cdPart .. ": " .. namePart
    end

    local typeWord = (buffType == "DEBUFF") and "Debuff" or "Buff"
    local modeWord = (mode == "missing") and "Missing" or "Found"
    local unitWord
    if unit == "target" then
      unitWord = "Target"
    else
      unitWord = "Player"
    end

    local typeColor = (buffType == "DEBUFF") and "|cffff0000" or "|cff00ff00"

    local typePart = typeColor .. typeWord .. "|r"
    local modePart = yellow .. modeWord .. "|r"
    local unitPart = yellow .. unitWord .. "|r"

    local prefix = ""
    if stacksEnabled and stacksComp and stacksComp ~= "" and stacksVal and tostring(stacksVal) ~= "" then
      local sym = stacksComp
      if sym == ">=" then sym = "\226\137\165"
      elseif sym == "<=" then sym = "\226\137\164"
      elseif sym == "==" then sym = "="
      end
      prefix = tostring(sym) .. tostring(stacksVal) .. "x"
    end

    local namePart = white .. prefix .. (niceName or "") .. "|r"
    return typePart .. " " .. sep .. modePart .. " " .. sep .. unitPart .. ": " .. namePart
  end

  local function AuraCond_ParseAuraInput(rawText)
    local text = string.gsub(rawText or "", "^%s*(.-)%s*$", "%1")
    if text == "" then
      return nil
    end

    local sid = tonumber(text)
    if sid and sid > 0 then
      local sidStr = tostring(sid)
      local displayName = sidStr

      if type(GetSpellNameAndRankForId) == "function" then
        local ok, sn = pcall(GetSpellNameAndRankForId, sid)
        if ok and sn and sn ~= "" then
          displayName = tostring(sn)
        end
      end

      return {
        name = displayName,
        spellid = sidStr,
        Addedviaspellid = true,
      }
    end

    if string.sub(text, -1) == "*" then
      local prefix = string.gsub(text, "%*$", "")
      prefix = string.gsub(prefix, "%s+$", "")
      if prefix ~= "" then
        return {
          name = prefix .. "*",
          spellid = nil,
          Addedviaspellid = nil,
        }
      end
    end

    return {
      name = _TitleCase(text),
      spellid = nil,
      Addedviaspellid = nil,
    }
  end

  local function AuraCond_UpdateStacksUI(row)
    if not row then return end

    local enabled = row._stacksEnabled and true or false

    if row.stacksCompDD then
      if enabled then row.stacksCompDD:Show() else row.stacksCompDD:Hide() end
    end
    if row.stacksVal then
      if enabled then row.stacksVal:Show() else row.stacksVal:Hide() end
    end
    if row.stacksValEnter then
      if enabled then row.stacksValEnter:Show() else row.stacksValEnter:Hide() end
    end

    local ok = true
    if enabled then
      local comp = row._stacksComp
      local val  = row._stacksVal
      comp = string.gsub(tostring(comp or ""), "^%s*(.-)%s*$", "%1")
      val  = string.gsub(tostring(val  or ""), "^%s*(.-)%s*$", "%1")
      if comp == "" or val == "" then
        ok = false
      end
    end
    if row.okBtn and row.okBtn.SetEnabled then
      row.okBtn:SetEnabled(ok and 1 or 0)
    end
  end

  local function AuraCond_SetRowState(row, state)
    row._state = state

    row.btn1:Hide()
    row.btn2:Hide()
    if row.btn3 then row.btn3:Hide() end
    if row.btn4 then row.btn4:Hide() end
    row.closeBtn:Show()
    -- VfxCond_SetRowState guards this; AuraCond_SetRowState historically
    -- assumed okBtn always exists. It does today, but matching VfxCond
    -- keeps both managers safe if row creation ever changes.
    if row.okBtn then row.okBtn:Hide() end
    row.editBox:Hide()
    row.addButton:Hide()
    row.labelFS:Hide()
    if row.abilityDD then row.abilityDD:Hide() end
    if row.itemDD then row.itemDD:Hide() end

    if row.stacksLabel then row.stacksLabel:Hide() end
    if row.stacksCB then row.stacksCB:Hide() end
    if row.stacksCompDD then row.stacksCompDD:Hide() end
    if row.stacksVal then row.stacksVal:Hide() end
    if row.stacksValEnter then row.stacksValEnter:Hide() end

    local spacing = row._spacing or 4
    local parentWidth = row._parentWidth or 260
    local closeWidth = row._closeWidth or 20
    local okWidth = row._okWidth or 20

    if state == "STEP1" then
      row._branch = nil

      local available = parentWidth - closeWidth - spacing * 6
      if available < 80 then available = 80 end
      local w = math.floor(available / 5)

      row.btn1:SetWidth(w)
      row.btn2:SetWidth(w)
      row.addButton:SetWidth(w)
      if row.btn3 then row.btn3:SetWidth(w) end
      if row.btn4 then row.btn4:SetWidth(w) end

      row.btn1:ClearAllPoints()
      row.btn2:ClearAllPoints()
      row.addButton:ClearAllPoints()
      if row.btn3 then row.btn3:ClearAllPoints() end
      if row.btn4 then row.btn4:ClearAllPoints() end

      row.btn1:SetPoint("LEFT", row, "LEFT", 0, 0)
      row.btn2:SetPoint("LEFT", row.btn1, "RIGHT", spacing, 0)
      row.addButton:SetPoint("LEFT", row.btn2, "RIGHT", spacing, 0)
      if row.btn3 then row.btn3:SetPoint("LEFT", row.addButton, "RIGHT", spacing, 0) end
      if row.btn4 then row.btn4:SetPoint("LEFT", row.btn3, "RIGHT", spacing, 0) end

      row.btn1:SetText("Ability")
      row.btn2:SetText("Buff")
      row.addButton:SetText("Debuff")
      if row.btn3 then row.btn3:SetText("Talent") end
      if row.btn4 then row.btn4:SetText("Item") end

      row.btn1:Show()
      row.btn2:Show()
      row.addButton:Show()
      if row.btn3 then row.btn3:Show() end
      if row.btn4 then row.btn4:Show() end

    elseif state == "STEP2" then
      local available = parentWidth - closeWidth - spacing * 3
      if available < 120 then available = 120 end
      local w = math.floor(available / 2)

      row.btn1:SetWidth(w)
      row.btn2:SetWidth(w)

      row.btn1:ClearAllPoints()
      row.btn2:ClearAllPoints()
      row.btn1:SetPoint("LEFT", row, "LEFT", 0, 0)
      row.btn2:SetPoint("LEFT", row.btn1, "RIGHT", spacing, 0)

      if row._branch == "ABILITY" then
        row.btn1:SetText("Not on CD")
        row.btn2:SetText("On CD")
      elseif row._branch == "ITEM" then
        row.btn1:SetText("In bag/equipped")
        row.btn2:SetText("Missing")
      elseif row._branch == "TALENT" then
        row.btn1:SetText("Known")
        row.btn2:SetText("Not known")
      else
        row.btn1:SetText("Found")
        row.btn2:SetText("Missing")
      end

      row.btn1:Show()
      row.btn2:Show()

    elseif state == "STEP3" then
      local available = parentWidth - closeWidth - spacing * 3
      if available < 120 then available = 120 end
      local w = math.floor(available / 2)

      row.btn1:SetWidth(w)
      row.btn2:SetWidth(w)

      row.btn1:ClearAllPoints()
      row.btn2:ClearAllPoints()
      row.btn1:SetPoint("LEFT", row, "LEFT", 0, 0)
      row.btn2:SetPoint("LEFT", row.btn1, "RIGHT", spacing, 0)

      if row._branch == "ITEM" then
        row.btn1:SetText("Not on CD")
        row.btn2:SetText("On CD")
      else
        row.btn1:SetText("On player")
        row.btn2:SetText("On target")
      end
      row.btn1:Show()
      row.btn2:Show()

    elseif state == "STACKS" then
      if row.okBtn then row.okBtn:Show() end

      row.closeBtn:ClearAllPoints()
      if row.okBtn then row.okBtn:ClearAllPoints() end
      row.closeBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
      if row.okBtn then
        row.okBtn:SetPoint("RIGHT", row.closeBtn, "LEFT", -spacing, 0)
      end

      if row.stacksLabel then
        row.stacksLabel:ClearAllPoints()
        row.stacksLabel:SetPoint("LEFT", row, "LEFT", 0, 0)
        if row._branch == "ITEM" then row.stacksLabel:SetText("Quantity?") else row.stacksLabel:SetText("Stacks?") end
        row.stacksLabel:Show()
      end
      if row.stacksCB then
        row.stacksCB:ClearAllPoints()
        row.stacksCB:SetPoint("LEFT", row, "LEFT", 52, 0)
        row.stacksCB:Show()
        row.stacksCB:SetChecked(row._stacksEnabled and true or false)
      end
      if row.stacksCompDD then
        row.stacksCompDD:ClearAllPoints()
        row.stacksCompDD:SetPoint("LEFT", row, "LEFT", 57, -3)
      end
      if row.stacksVal then
        row.stacksVal:ClearAllPoints()
        row.stacksVal:SetPoint("LEFT", row, "LEFT", 142, 0)
      end
      if row.stacksValEnter then
        row.stacksValEnter:ClearAllPoints()
        row.stacksValEnter:SetPoint("LEFT", row.stacksVal, "RIGHT", 4, 0)
      end

      AuraCond_UpdateStacksUI(row)

    elseif state == "INPUT" then
      local addWidth = row.addButton:GetWidth() or 40
      local rightGap = 2
      local totalRight = closeWidth + spacing + addWidth + rightGap

      local editWidth = parentWidth - spacing - totalRight
      if editWidth < 60 then editWidth = 60 end

      row.editBox:ClearAllPoints()
      row.addButton:ClearAllPoints()
      if row.abilityDD then row.abilityDD:ClearAllPoints() end
      if row.itemDD then row.itemDD:ClearAllPoints() end

      row.editBox:SetWidth(editWidth)
      row.editBox:SetPoint("LEFT", row, "LEFT", 10, 0)

      row.addButton:SetPoint("RIGHT", row.closeBtn, "LEFT", -rightGap, 0)
      row.addButton:SetText("Add")

      if row._branch == "ABILITY" then
        if row.abilityDD then
          row.editBox:Hide()
          row.abilityDD:SetPoint("LEFT", row, "LEFT", -15, -3)
          if UIDropDownMenu_SetWidth then
            pcall(UIDropDownMenu_SetWidth, editWidth, row.abilityDD)
          end
          AuraCond_InitAbilityDropdown(row)
          row.abilityDD:Show()
        end
        row.addButton:Show()
      elseif row._branch == "ITEM" then
        if row.itemDD then
          row.editBox:Hide()
          row.itemDD:SetPoint("LEFT", row, "LEFT", -15, -3)
          if UIDropDownMenu_SetWidth then
            pcall(UIDropDownMenu_SetWidth, editWidth, row.itemDD)
          end
          AuraCond_InitItemDropdown(row)
          row.itemDD:Show()
        end
        row.addButton:Show()
      else
        row.editBox:Show()
        row.addButton:Show()
      end

    elseif state == "SAVED" then
      row.labelFS:SetText(row._desc or "")
      row.labelFS:Show()
    end
  end

  local function AuraCond_OnCancelEditing(row)
    row._branch = nil
    row._choiceBuffType = nil
    row._choiceMode = nil
    row._choiceUnit = nil
    row._spellName = nil
    row._itemName = nil
    row._choiceItemCd = nil
    row._abilityPage = 1

    row._stacksEnabled = nil
    row._stacksComp = nil
    row._stacksVal = nil

    if row.stacksCB then
      row.stacksCB:SetChecked(false)
    end
    if row.stacksVal and row.stacksVal.SetText then
      row.stacksVal:SetText("")
    end
    if row.stacksCompDD then
      if UIDropDownMenu_ClearAll then
        pcall(UIDropDownMenu_ClearAll, row.stacksCompDD)
      end
      if UIDropDownMenu_SetText then
        pcall(UIDropDownMenu_SetText, "", row.stacksCompDD)
      end
    end

    if row.editBox and row.editBox.SetText then
      row.editBox:SetText("")
    end

    if row.abilityDD then
      if UIDropDownMenu_ClearAll then
        pcall(UIDropDownMenu_ClearAll, row.abilityDD)
      end
      if UIDropDownMenu_SetText then
        pcall(UIDropDownMenu_SetText, "Select ability", row.abilityDD)
      end
    end

    AuraCond_SetRowState(row, "STEP1")
  end

  local function AuraCond_RebuildFromDB_Internal(typeKey)
    local mgr = AuraCond_Managers[typeKey]
    if not mgr or not mgr.anchor then
      return
    end

    local list = AuraCond_GetListForType(typeKey) or {}
    local count = AuraCond_Len(list)

    if not mgr.savedRows then
      mgr.savedRows = {}
    end

    local i
    for i = 1, count do
      local entry = list[i]
      local row = mgr.savedRows[i]
      if not row then
        row = mgr._createRow(mgr, false)
        mgr.savedRows[i] = row
      end
      row._entryIndex = i
      row._choiceBuffType = (entry and entry.buffType) or "BUFF"
      row._choiceMode = (entry and entry.mode) or "found"
      row._choiceUnit = (entry and entry.unit) or "player"
      row._spellName = (entry and entry.name) or ""
      row._itemName = (entry and entry.name) or ""
      row._choiceItemCd = (entry and entry.unit) or "notcd"
      row._stacksEnabled = (entry and entry.stacksEnabled) and true or nil
      row._stacksComp    = (entry and entry.stacksComp) or nil
      row._stacksVal     = (entry and entry.stacksVal) or nil

      row._desc = AuraCond_BuildDescription(
        row._choiceBuffType,
        row._choiceMode,
        row._choiceUnit,
        row._spellName,
        row._stacksEnabled,
        row._stacksComp,
        row._stacksVal
      )
      AuraCond_SetRowState(row, "SAVED")
      row:Show()
    end

    local nRows = AuraCond_Len(mgr.savedRows)
    for i = count + 1, nRows do
      if mgr.savedRows[i] then
        mgr.savedRows[i]:Hide()
        mgr.savedRows[i]._entryIndex = nil
      end
    end

    if not mgr.editRow then
      mgr.editRow = mgr._createRow(mgr, true)
    end
    AuraCond_OnCancelEditing(mgr.editRow)
    mgr.editRow:Show()

    local y = -26

    i = 1
    while mgr.savedRows and mgr.savedRows[i] do
      local row = mgr.savedRows[i]
      if row:IsShown() then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", mgr.anchor, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", mgr.anchor, "TOPRIGHT", 0, y)
        y = y - 18
      end
      i = i + 1
    end

    local list2 = AuraCond_GetListForType(typeKey) or {}
    local count2 = AuraCond_Len(list2)

    if mgr.logicButton then
      if count2 >= 2 then
        mgr.logicButton:Show()
        mgr.logicButton:ClearAllPoints()
        mgr.logicButton:SetPoint("TOPLEFT", mgr.anchor, "TOPLEFT", 0, y)
        mgr.logicButton:SetWidth(110)
        y = y - 20
      else
        mgr.logicButton:Hide()
      end
    end

    if mgr.editRow and mgr.editRow:IsShown() then
      mgr.editRow:ClearAllPoints()
      mgr.editRow:SetPoint("TOPLEFT", mgr.anchor, "TOPLEFT", 0, y)
      mgr.editRow:SetPoint("TOPRIGHT", mgr.anchor, "TOPRIGHT", 0, y)
      y = y - 18
    end

    mgr.anchor:SetHeight(-y + 4)
    _Reflow()
  end

  local function AuraCond_OnAdd(row)
    if not _G["DoiteEdit_CurrentKey"] then
      return
    end
    local mgr = row._manager
    if not mgr then
      return
    end

    local text
    if row._branch == "ABILITY" then
      text = row._spellName or ""
    elseif row._branch == "ITEM" then
      text = row._itemName or ""
    else
      text = row.editBox and row.editBox:GetText() or ""
    end
    local parsedInput = AuraCond_ParseAuraInput(text)
    if not parsedInput then
      return
    end

    local buffType = row._choiceBuffType or "BUFF"
    local mode = row._choiceMode or "found"
    local unit

    if row._branch == "ABILITY" then
      unit = nil
      buffType = "ABILITY"
    elseif row._branch == "ITEM" then
      if row._choiceMode == "missing" then
        unit = nil
      else
        unit = row._choiceItemCd or "notcd"
      end
      buffType = "ITEM"
    elseif row._branch == "TALENT" then
      unit = nil
    else
      unit = row._choiceUnit or "player"
    end

    local list = AuraCond_GetListForType(mgr.typeKey)
    if not list then
      return
    end

    local entry = {
      buffType = buffType,
      mode = mode,
      unit = unit,
      name = parsedInput.name,
      spellid = parsedInput.spellid,
      Addedviaspellid = parsedInput.Addedviaspellid,
    }

    if row._branch ~= "ABILITY" and row._branch ~= "TALENT" then
      entry.stacksEnabled = row._stacksEnabled and true or nil
      if entry.stacksEnabled then
        entry.stacksComp = row._stacksComp
        entry.stacksVal  = row._stacksVal
      else
        entry.stacksComp = nil
        entry.stacksVal  = nil
      end
    end

    local n = AuraCond_Len(list)
    list[n + 1] = entry

    AuraCond_RebuildFromDB_Internal(mgr.typeKey)
  end

  local function AuraCond_OnDeleteSaved(row)
    if not _G["DoiteEdit_CurrentKey"] then
      return
    end
    local mgr = row._manager
    if not mgr then
      return
    end

    local list = AuraCond_GetListForType(mgr.typeKey)
    if not list then
      return
    end

    local idx = row._entryIndex or 0
    local n = AuraCond_Len(list)
    if idx < 1 or idx > n then
      return
    end

    local deletedEntry = list[idx]
    local hadParens = deletedEntry and (deletedEntry.parenOpen or deletedEntry.parenClose)

    local i
    for i = idx, n - 1 do
      list[i] = list[i + 1]
    end
    list[n] = nil

    if hadParens and DoiteLogic and DoiteLogic.ValidateOrResetCurrentLogic then
      DoiteLogic.ValidateOrResetCurrentLogic(mgr.typeKey)
    end

    list._daDirty = true

    AuraCond_RebuildFromDB_Internal(mgr.typeKey)
  end

  local AuraCond_RowCounter = (AuraCond_RowCounter or 0)

  local function AuraCond_InitComparatorDD(ddframe, commitFunc)
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

  local function AuraCond_CreateRow(mgr, isEditing)
    AuraCond_RowCounter = AuraCond_RowCounter + 1

    local parent = mgr.anchor
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(18)

    row._manager = mgr
    row._abilityPage = 1

    local parentWidth = (parent and parent.GetWidth and parent:GetWidth()) or 0
    if parentWidth <= 0 then
      parentWidth = 260
    end
    local closeWidth = 20
    local spacing = 4
    local mainWidth = math.floor((parentWidth - closeWidth - spacing * 3) / 2)

    row._parentWidth = parentWidth
    row._closeWidth = closeWidth
    row._spacing = spacing
    row._mainWidth = mainWidth

    row.btn1 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.btn2 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.btn3 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.btn4 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.closeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.editBox = CreateFrame("EditBox", nil, row)
    row.addButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.labelFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

    row.editBox:SetAutoFocus(false)
    row.editBox:SetFontObject("GameFontNormalSmall")
    if row.editBox.SetTextInsets then
      row.editBox:SetTextInsets(6, 6, 0, 0)
    end
    if row.editBox.SetBackdrop then
      row.editBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
      })
      row.editBox:SetBackdropColor(0, 0, 0, 0.85)
      row.editBox:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end

    local ddName = "DoiteAuraCond_AbilityDD_" .. tostring(mgr.typeKey or "X") .. "_" .. tostring(AuraCond_RowCounter)
    row.abilityDD = CreateFrame("Frame", ddName, row, "UIDropDownMenuTemplate")
    row.itemDD = CreateFrame("Frame", "DoiteAuraCond_ItemDD_" .. tostring(mgr.typeKey or "X") .. "_" .. tostring(AuraCond_RowCounter), row, "UIDropDownMenuTemplate")
    DoiteEdit_HookDropDownButtonOnClick(row.itemDD, function()
      if row and row._branch == "ITEM" then
        AuraCond_InitItemDropdown(row)
      end
    end)

    row.okBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.okBtn:SetWidth(60)
    row.okBtn:SetHeight(18)
    row.okBtn:SetText("Continue")

    row.stacksLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.stacksLabel:SetText("Stacks?")

    row.stacksCB = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.stacksCB:SetWidth(18); row.stacksCB:SetHeight(18)

    local dd2Name = "DoiteAuraCond_StacksCompDD_" .. tostring(mgr.typeKey or "X") .. "_" .. tostring(AuraCond_RowCounter)
    row.stacksCompDD = CreateFrame("Frame", dd2Name, row, "UIDropDownMenuTemplate")

    row._stacksCompWidth = 45
    if UIDropDownMenu_SetWidth then
      pcall(UIDropDownMenu_SetWidth, row._stacksCompWidth, row.stacksCompDD)
    end

    row.stacksVal = CreateFrame("EditBox", nil, row)
    row.stacksVal:SetWidth(40)
    row.stacksVal:SetHeight(18)
    row.stacksVal:SetAutoFocus(false)
    row.stacksVal:SetFontObject("GameFontNormalSmall")
    if row.stacksVal.SetTextInsets then
      row.stacksVal:SetTextInsets(6, 6, 0, 0)
    end
    if row.stacksVal.SetBackdrop then
      row.stacksVal:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
      })
      row.stacksVal:SetBackdropColor(0, 0, 0, 0.85)
      row.stacksVal:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end

    row.stacksValEnter = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.stacksValEnter:SetText("(#)")

    row.btn1:SetWidth(mainWidth)
    row.btn2:SetWidth(mainWidth)
    row.btn3:SetWidth(mainWidth)
    row.btn4:SetWidth(mainWidth)
    row.btn1:SetHeight(18)
    row.btn2:SetHeight(18)
    row.btn3:SetHeight(18)
    row.btn4:SetHeight(18)

    row.closeBtn:SetWidth(closeWidth)
    row.closeBtn:SetHeight(18)

    local editWidth = parentWidth - closeWidth - spacing * 3 - 40
    if editWidth < 60 then
      editWidth = 60
    end

    row.editBox:SetWidth(editWidth)
    row.editBox:SetHeight(18)
    row.editBox:SetAutoFocus(false)
    row.editBox:SetFontObject("GameFontNormalSmall")

    row.addButton:SetWidth(40)
    row.addButton:SetHeight(18)

    row.btn1:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.btn2:SetPoint("LEFT", row.btn1, "RIGHT", spacing, 0)
    row.closeBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    row.editBox:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.addButton:SetPoint("LEFT", row.editBox, "RIGHT", spacing, 0)

    row.abilityDD:SetPoint("LEFT", row, "LEFT", 0, -2)
    if UIDropDownMenu_SetWidth then
      pcall(UIDropDownMenu_SetWidth, parentWidth - closeWidth - spacing * 3 - 40, row.abilityDD)
    end

    row.labelFS:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.labelFS:SetTextColor(1, 1, 1)
    row.labelFS:SetNonSpaceWrap(false)

    row.closeBtn:SetText("X")

    DoiteEdit_YellowifyButton(row.btn1)
    DoiteEdit_YellowifyButton(row.btn2)
    DoiteEdit_YellowifyButton(row.btn3)
    DoiteEdit_YellowifyButton(row.btn4)
    DoiteEdit_YellowifyButton(row.addButton)
    DoiteEdit_YellowifyButton(row.closeBtn)
    DoiteEdit_YellowifyButton(row.okBtn)

    row.btn1:SetScript("OnClick", function()
      if not _G["DoiteEdit_CurrentKey"] then
        return
      end
      local state = row._state

      if state == "STEP1" then
        row._branch = "ABILITY"
        row._choiceBuffType = "ABILITY"
        row._choiceMode = nil
        row._choiceUnit = nil
        AuraCond_SetRowState(row, "STEP2")

      elseif state == "STEP2" then
        if row._branch == "ABILITY" then
          row._choiceMode = "notcd"
          AuraCond_SetRowState(row, "INPUT")

        elseif row._branch == "ITEM" then
          row._choiceMode = "found"
          AuraCond_SetRowState(row, "STEP3")

        elseif row._branch == "TALENT" then
          row._choiceMode = "Known"
          AuraCond_SetRowState(row, "INPUT")

        else
          row._choiceMode = "found"
          AuraCond_SetRowState(row, "STEP3")
        end

      elseif state == "STEP3" then
        if row._branch == "ITEM" then
          row._choiceItemCd = "notcd"
          if row._choiceMode == "missing" then
            AuraCond_SetRowState(row, "INPUT")
          else
            AuraCond_SetRowState(row, "STACKS")
          end
          return
        end
        row._choiceUnit = "player"

        if row._choiceMode == "missing" then
          AuraCond_SetRowState(row, "INPUT")
        else
          AuraCond_SetRowState(row, "STACKS")
        end
      end
    end)

    row.btn2:SetScript("OnClick", function()
      if not _G["DoiteEdit_CurrentKey"] then
        return
      end
      local state = row._state

      if state == "STEP1" then
        row._branch = "AURA"
        row._choiceBuffType = "BUFF"
        row._choiceMode = nil
        row._choiceUnit = nil
        AuraCond_SetRowState(row, "STEP2")

      elseif state == "STEP2" then
        if row._branch == "ABILITY" then
          row._choiceMode = "oncd"
          AuraCond_SetRowState(row, "INPUT")

        elseif row._branch == "ITEM" then
          row._choiceMode = "missing"
          row._choiceItemCd = nil
          row._stacksEnabled = nil
          row._stacksComp = nil
          row._stacksVal  = nil
          AuraCond_SetRowState(row, "INPUT")

        elseif row._branch == "TALENT" then
          row._choiceMode = "Not Known"
          AuraCond_SetRowState(row, "INPUT")

        else
          row._choiceMode = "missing"

          row._stacksEnabled = nil
          row._stacksComp = nil
          row._stacksVal  = nil
          if row.stacksCB then
            row.stacksCB:SetChecked(false)
          end
          if row.stacksVal and row.stacksVal.SetText then
            row.stacksVal:SetText("")
          end
          if row.stacksCompDD then
            if UIDropDownMenu_ClearAll then
              pcall(UIDropDownMenu_ClearAll, row.stacksCompDD)
            end
            if UIDropDownMenu_SetText then
              pcall(UIDropDownMenu_SetText, "", row.stacksCompDD)
            end
          end

          AuraCond_SetRowState(row, "STEP3")
        end

      elseif state == "STEP3" then
        if row._branch == "ITEM" then
          row._choiceItemCd = "oncd"
          if row._choiceMode == "missing" then
            AuraCond_SetRowState(row, "INPUT")
          else
            AuraCond_SetRowState(row, "STACKS")
          end
          return
        end
        row._choiceUnit = "target"

        if row._choiceMode == "missing" then
          AuraCond_SetRowState(row, "INPUT")
        else
          AuraCond_SetRowState(row, "STACKS")
        end
      end
    end)

    row.btn3:SetScript("OnClick", function()
      if not _G["DoiteEdit_CurrentKey"] then
        return
      end
      local state = row._state

      if state == "STEP1" then
        row._branch = "TALENT"
        row._choiceBuffType = "TALENT"
        row._choiceMode = nil
        row._choiceUnit = nil
        AuraCond_SetRowState(row, "STEP2")
      end
    end)

    row.btn4:SetScript("OnClick", function()
      if not _G["DoiteEdit_CurrentKey"] then
        return
      end
      if row._state == "STEP1" then
        row._branch = "ITEM"
        row._choiceBuffType = "ITEM"
        row._choiceMode = nil
        row._choiceUnit = nil
        row._choiceItemCd = nil
        AuraCond_SetRowState(row, "STEP2")
      end
    end)

    row.addButton:SetText("Add")
    row.addButton:SetScript("OnClick", function()
      if not _G["DoiteEdit_CurrentKey"] then
        return
      end
      local state = row._state

      if state == "STEP1" then
        row._branch = "AURA"
        row._choiceBuffType = "DEBUFF"
        row._choiceMode = nil
        row._choiceUnit = nil
        AuraCond_SetRowState(row, "STEP2")
        return
      end

      if state == "INPUT" then
        AuraCond_OnAdd(row)
      end
    end)

    row.editBox:SetScript("OnEnterPressed", function()
      if not _G["DoiteEdit_CurrentKey"] then
        return
      end
      AuraCond_OnAdd(row)
      if this and this.ClearFocus then
        this:ClearFocus()
      end
    end)

    row.closeBtn:SetScript("OnClick", function()
      if row._state == "SAVED" then
        AuraCond_OnDeleteSaved(row)
      else
        AuraCond_OnCancelEditing(row)
        _Reflow()
      end
    end)

    AuraCond_InitComparatorDD(row.stacksCompDD, function(val)
      row._stacksComp = val
      if row._state == "STACKS" then
        AuraCond_UpdateStacksUI(row)
      end
    end)
    if UIDropDownMenu_SetText then
      pcall(UIDropDownMenu_SetText, "", row.stacksCompDD)
    end

    row.stacksCB:SetScript("OnClick", function()
      row._stacksEnabled = this:GetChecked() and true or nil
      if not row._stacksEnabled then
        row._stacksComp = nil
        row._stacksVal  = nil
        if row.stacksVal and row.stacksVal.SetText then
          row.stacksVal:SetText("")
        end
        if UIDropDownMenu_ClearAll then
          pcall(UIDropDownMenu_ClearAll, row.stacksCompDD)
        end
        if UIDropDownMenu_SetText then
          pcall(UIDropDownMenu_SetText, "", row.stacksCompDD)
        end
      end

      if row._state == "STACKS" then
        AuraCond_UpdateStacksUI(row)
      end
    end)

    row.stacksVal:SetScript("OnTextChanged", function()
      row._stacksVal = row.stacksVal:GetText()
      if row._state == "STACKS" then
        AuraCond_UpdateStacksUI(row)
      end
    end)

    row.okBtn:SetScript("OnClick", function()
      if not _G["DoiteEdit_CurrentKey"] then return end
      if row._state ~= "STACKS" then return end

      if row._stacksEnabled then
        local comp = string.gsub(tostring(row._stacksComp or ""), "^%s*(.-)%s*$", "%1")
        local val  = string.gsub(tostring(row._stacksVal  or ""), "^%s*(.-)%s*$", "%1")
        if comp == "" or val == "" then
          return
        end
      end

      AuraCond_SetRowState(row, "INPUT")
    end)

    if isEditing then
      AuraCond_OnCancelEditing(row)
    else
      row._state = "SAVED"
      AuraCond_SetRowState(row, "SAVED")
    end

    row:Hide()
    return row
  end

  AuraCond_RegisterManager = function(typeKey, anchorFrame)
    if not anchorFrame then
      return
    end

    local mgr = AuraCond_Managers[typeKey]
    if not mgr then
      mgr = {}
      AuraCond_Managers[typeKey] = mgr
    end

    mgr.typeKey = typeKey
    mgr.anchor = anchorFrame
    mgr.savedRows = mgr.savedRows or {}
    mgr.editRow = mgr.editRow or nil
    mgr._createRow = AuraCond_CreateRow

    if not mgr.label then
      local label = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      label:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)
      label:SetJustifyH("LEFT")
      label:SetTextColor(1, 0.82, 0)
      label:SetText("Add extra visibility conditions to show/hide:")
      mgr.label = label
    end
    if not mgr.wildcardHint then
      local hint = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      hint:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, -11)
      hint:SetJustifyH("LEFT")
      hint:SetTextColor(0.7, 0.7, 0.7)
      hint:SetText("Add '*' at the end for prefix match (e.g. 'Seal of*').")
      mgr.wildcardHint = hint
    end

    if not mgr.logicButton then
      local btnName = "DoiteAuraLogicButton_" .. tostring(typeKey)
      local btn = CreateFrame("Button", btnName, anchorFrame, "UIPanelButtonTemplate")
      btn:SetWidth(50)
      btn:SetHeight(18)
      btn:SetText("And/Or Logic")

      btn:ClearAllPoints()
      btn:SetPoint("TOPRIGHT", anchorFrame, "TOPRIGHT", 0, 0)

      if btn.SetFrameStrata then
        btn:SetFrameStrata("HIGH")
      end
      if anchorFrame.GetFrameLevel and btn.SetFrameLevel then
        btn:SetFrameLevel(anchorFrame:GetFrameLevel() + 1)
      end

      local fs = btn:GetFontString()
      if fs and fs.SetTextColor then
        fs:SetTextColor(1, 0.82, 0)
      end

      btn:Hide()

      btn:SetScript("OnClick", function()
        local DL = _G["DoiteLogic"]
        if DL and DL.OpenAuraLogicEditor then
          DL.OpenAuraLogicEditor(typeKey)
        end
      end)

      mgr.logicButton = btn
    end

    anchorFrame:SetHeight(20)
    anchorFrame:Hide()
  end

  AuraCond_RefreshFromDB = function(typeKey)
    local tk, mgr
    for tk, mgr in pairs(AuraCond_Managers) do
      if mgr.anchor then
        if tk == typeKey then
          mgr.anchor:Show()
        else
          mgr.anchor:Hide()
        end
      end
    end

    if typeKey then
      AuraCond_RebuildFromDB_Internal(typeKey)
    end

    -- Editor changes may add/remove target-aura or item usage; ask the
    -- main evaluator to rebuild its flag cache on the next tick.
    if DoiteConditions then
      DoiteConditions._flagsDirty = true
    end

    _Reflow()
  end

  _G["AuraCond_RefreshFromDB"] = AuraCond_RefreshFromDB

  AuraCond_ResetEditing = function()
  end
end

_G["AuraCond_Managers"]        = AuraCond_Managers
_G["AuraCond_RegisterManager"] = AuraCond_RegisterManager
_G["AuraCond_RefreshFromDB"]   = AuraCond_RefreshFromDB
_G["AuraCond_ResetEditing"]    = AuraCond_ResetEditing

---------------------------------------------------------------
-- VfxCond: Visual Effects Conditions System
-- Uses the same Ability/Buff/Debuff/Talent UI as AuraCond but
-- stores to *vfxConditions instead of *auraConditions.
---------------------------------------------------------------
do
  -- Declared up here so every helper inside this block sees the same
  -- upvalue. Earlier code below still refers to VfxCond_Managers through
  -- _G["VfxCond_Managers"], which worked but created two paths to the
  -- same table (a silent-failure risk if the _G export is ever moved).
  local VfxCond_Managers = {}
  local VfxCond_RegisterManager
  local VfxCond_RefreshFromDB
  local VfxCond_ResetEditing

  local function VfxCond_GetListForType(typeKey)
    local ck = _G["DoiteEdit_CurrentKey"]
    if not ck then
      return nil
    end

    local d = _EnsureDBEntry(ck)
    if not d then
      return nil
    end

    if not d.conditions then d.conditions = {} end

    if typeKey == "ability" then
      d.conditions.ability = d.conditions.ability or {}
      d.conditions.ability.vfxConditions = d.conditions.ability.vfxConditions or {}
      return d.conditions.ability.vfxConditions

    elseif typeKey == "aura" then
      d.conditions.aura = d.conditions.aura or {}
      d.conditions.aura.vfxConditions = d.conditions.aura.vfxConditions or {}
      return d.conditions.aura.vfxConditions

    elseif typeKey == "item" then
      d.conditions.item = d.conditions.item or {}
      d.conditions.item.vfxConditions = d.conditions.item.vfxConditions or {}
      return d.conditions.item.vfxConditions
    end

    return nil
  end

  local VfxCond_TitleCase = _G["DoiteEdit_AuraCond_TitleCase"]

  local function VfxCond_BuildItemOptions()
    local items, seen = {}, {}
    local function _Add(name)
      if not name or name == "" or seen[name] then return end
      seen[name] = true
      table.insert(items, name)
    end
    local function _NameFromId(itemId)
      if not itemId then return nil end
      local nm = GetItemInfo and GetItemInfo(itemId)
      if nm and nm ~= "" then return nm end
      return nil
    end
    local slots = {13, 14, 16, 17, 18}
    local i
    for i = 1, table.getn(slots) do
      local info = GetEquippedItem and GetEquippedItem("player", slots[i])
      _Add(_NameFromId(info and info.itemId))
    end
    local bags = GetBagItems and GetBagItems()
    if bags then
      local bag = 0
      while bag <= 4 do
        local bagData = bags[bag]
        if bagData then
          local slot, itemInfo
          for slot, itemInfo in pairs(bagData) do
            _Add(_NameFromId(itemInfo and itemInfo.itemId))
          end
        end
        bag = bag + 1
      end
    end
    table.sort(items, function(a, b)
      return string.lower(a or "") < string.lower(b or "")
    end)
    table.insert(items, 1, "---EQUIPPED WEAPON SLOTS---")
    table.insert(items, 1, "---EQUIPPED TRINKET SLOTS---")
    return items
  end

  local function VfxCond_InitItemDropdown(row)
    if not row or not row.itemDD then return end

    local items = VfxCond_BuildItemOptions()
    row._itemOptions = items

    local total = table.getn(items)
    local perPage = 10

    if total == 0 then
      UIDropDownMenu_Initialize(row.itemDD, function() end)
      if UIDropDownMenu_SetText then
        pcall(UIDropDownMenu_SetText, "No items found", row.itemDD)
      end
      return
    end

    local maxPage = math.max(1, math.ceil(total / perPage))
    local page = row._itemPage or 1
    if page < 1 then page = 1 end
    if page > maxPage then page = maxPage end
    row._itemPage = page

    local function ReopenItemDDNextFrame()
      local f = row.itemDD and row.itemDD._reopenFrame
      if not f then
        f = CreateFrame("Frame", nil, UIParent)
        if row.itemDD then
          row.itemDD._reopenFrame = f
        end
        f:Hide()
        f:SetScript("OnUpdate", function()
          f:Hide()
          if row and row.itemDD then
            ToggleDropDownMenu(nil, nil, row.itemDD, row.itemDD, 0, 0)
          end
        end)
      end
      f:Show()
    end

    local startIndex = (page - 1) * perPage + 1
    local endIndex = math.min(startIndex + perPage - 1, total)

    UIDropDownMenu_Initialize(row.itemDD, function(frame, level, menuList)
      local info

      if page > 1 then
        info = {}
        info.text = "|cffffd000<< Previous|r"
        info.value = "PREV"
        info.notCheckable = true
        info.func = function()
          row._itemPage = page - 1
          VfxCond_InitItemDropdown(row)
          if CloseDropDownMenus then
            CloseDropDownMenus()
          end
          ReopenItemDDNextFrame()
        end
        UIDropDownMenu_AddButton(info)
      end

      local idx = startIndex
      while idx <= endIndex do
        local name = items[idx]
        info = {}
        info.text = name
        info.value = name
        local pickedName = name
        info.func = function(button)
          local val = (button and button.value) or pickedName
          row._itemName = val
          if UIDropDownMenu_SetSelectedValue then
            pcall(UIDropDownMenu_SetSelectedValue, row.itemDD, val)
          end
          if UIDropDownMenu_SetText then
            pcall(UIDropDownMenu_SetText, val, row.itemDD)
          end
          if _GoldifyDD then
            _GoldifyDD(row.itemDD)
          end
        end
        info.checked = (row._itemName == name)
        UIDropDownMenu_AddButton(info)
        idx = idx + 1
      end

      if page < maxPage then
        info = {}
        info.text = "|cffffd000Next >>|r"
        info.value = "NEXT"
        info.notCheckable = true
        info.func = function()
          row._itemPage = page + 1
          VfxCond_InitItemDropdown(row)
          if CloseDropDownMenus then
            CloseDropDownMenus()
          end
          ReopenItemDDNextFrame()
        end
        UIDropDownMenu_AddButton(info)
      end
    end)

    if UIDropDownMenu_SetText then
      pcall(UIDropDownMenu_SetText, row._itemName or "Select item", row.itemDD)
    end
    if _GoldifyDD then
      _GoldifyDD(row.itemDD)
    end
  end

  local function VfxCond_BuildDescription(buffType, mode, unit, name, stacksEnabled, stacksComp, stacksVal)
    local niceName = VfxCond_TitleCase(name or "")

    local yellow = "|cffffd000"
    local white  = "|cffffffff"
    local sep    = "|cffffffff | |r"

    local bt = string.upper(tostring(buffType or ""))
    local m  = string.lower(tostring(mode or ""))
    local u  = string.lower(tostring(unit or ""))

    if bt == "ABILITY" then
      local typeColor = "|cff4da6ff"
      local typePart  = typeColor .. "Ability" .. "|r"

      local modeWord
      if m == "oncd" then
        modeWord = "On CD"
      else
        modeWord = "Not on CD"
      end

      local modePart = yellow .. modeWord .. "|r"
      local namePart = white .. (niceName or "") .. "|r"
      return typePart .. " " .. sep .. modePart .. ": " .. namePart

    elseif bt == "TALENT" then
      local isKnown = (m == "known")
      local stateWord = isKnown and "Known" or "Not known"
      local stateColor = isKnown and "|cff00ff00" or "|cffff0000"
      local statePart = stateColor .. stateWord .. "|r"

      local talentPart = yellow .. "Talent" .. "|r"
      local namePart   = white .. (niceName or "") .. "|r"
      return talentPart .. " " .. sep .. statePart .. ": " .. namePart
    elseif bt == "ITEM" then
      local whereWord = (m == "missing") and "Missing" or "In bag/equipped"
      local cdWord = (u == "oncd") and "On CD" or "Not on CD"
      local itemPart = yellow .. "Item" .. "|r"
      local wherePart = yellow .. whereWord .. "|r"

      local prefix = ""
      if stacksEnabled and stacksComp and stacksComp ~= "" and stacksVal and tostring(stacksVal) ~= "" then
        local sym = stacksComp
        if sym == ">=" then sym = "\226\137\165"
        elseif sym == "<=" then sym = "\226\137\164"
        elseif sym == "==" then sym = "="
        end
        prefix = tostring(sym) .. tostring(stacksVal) .. "x"
      end

      local namePart = white .. prefix .. (niceName or "") .. "|r"

      if m == "missing" then
        return itemPart .. " " .. sep .. wherePart .. ": " .. namePart
      end

      local cdPart = yellow .. cdWord .. "|r"
      return itemPart .. " " .. sep .. wherePart .. " " .. sep .. cdPart .. ": " .. namePart
    end

    local isDebuff = (bt == "DEBUFF")
    local typeWord = isDebuff and "Debuff" or "Buff"
    local modeWord = (m == "missing") and "Missing" or "Found"

    local unitWord
    if u == "target" then
      unitWord = "Target"
    else
      unitWord = "Player"
    end

    local typeColor = isDebuff and "|cffff0000" or "|cff00ff00"
    local typePart = typeColor .. typeWord .. "|r"
    local modePart = yellow .. modeWord .. "|r"
    local unitPart = yellow .. unitWord .. "|r"

    local prefix = ""
    if stacksEnabled and stacksComp and stacksComp ~= "" and stacksVal and tostring(stacksVal) ~= "" then
      local sym = stacksComp
      if sym == ">=" then sym = "\226\137\165"
      elseif sym == "<=" then sym = "\226\137\164"
      elseif sym == "==" then sym = "="
      end
      prefix = tostring(sym) .. tostring(stacksVal) .. "x"
    end

    local namePart = white .. prefix .. (niceName or "") .. "|r"
    return typePart .. " " .. sep .. modePart .. " " .. sep .. unitPart .. ": " .. namePart
  end

  local function VfxCond_ParseAuraInput(rawText)
    local text = string.gsub(rawText or "", "^%s*(.-)%s*$", "%1")
    if text == "" then
      return nil
    end

    local sid = tonumber(text)
    if sid and sid > 0 then
      local sidStr = tostring(sid)
      local displayName = sidStr

      if type(GetSpellNameAndRankForId) == "function" then
        local ok, sn = pcall(GetSpellNameAndRankForId, sid)
        if ok and sn and sn ~= "" then
          displayName = tostring(sn)
        end
      end

      return {
        name = displayName,
        spellid = sidStr,
        Addedviaspellid = true,
      }
    end

    if string.sub(text, -1) == "*" then
      local prefix = string.gsub(text, "%*$", "")
      prefix = string.gsub(prefix, "%s+$", "")
      if prefix ~= "" then
        return {
          name = prefix .. "*",
          spellid = nil,
          Addedviaspellid = nil,
        }
      end
    end

    return {
      name = VfxCond_TitleCase(text),
      spellid = nil,
      Addedviaspellid = nil,
    }
  end

  local VfxCond_RowCounter = 0

  local _vfxDDReopenFrame = CreateFrame("Frame", "DoiteEditVfxReopenFrame")
  local _vfxDDReopenRow = nil

  _vfxDDReopenFrame:Hide()
  _vfxDDReopenFrame:SetScript("OnUpdate", function()
    _vfxDDReopenFrame:Hide()
    if not _vfxDDReopenRow or not _vfxDDReopenRow.abilityDD then
      _vfxDDReopenRow = nil
      return
    end
    ToggleDropDownMenu(nil, nil, _vfxDDReopenRow.abilityDD, _vfxDDReopenRow.abilityDD, 0, 0)
    _vfxDDReopenRow = nil
  end)

  local function VfxCond_ReopenDDNextFrame(row)
    _vfxDDReopenRow = row
    _vfxDDReopenFrame:Show()
  end

  local function VfxCond_Len(t)
    if not t then return 0 end
    local n = 0
    while t[n + 1] ~= nil do
      n = n + 1
    end
    return n
  end

  local function VfxCond_BuildAbilitySpellList()
    local spells = {}
    local seen = {}
    local passiveAllow = _G["DA_AbilityDropdownPassiveAllow"] or {}

    local function scanBook(bookType)
      local i = 1
      while true do
        local name, rank = GetSpellName(i, bookType)
        if not name then break end

        local isPassive = false
        if IsPassiveSpell then
          local ok, passive = pcall(IsPassiveSpell, i, bookType)
          if ok and passive then
            isPassive = true
          end
        end
        if (not isPassive) and rank and string.find(rank, "Passive") then
          isPassive = true
        end

        if name and name ~= "" then
          local allowPassive = (passiveAllow[name] == true)
          if ((not isPassive) or allowPassive) and not seen[name] then
            table.insert(spells, name)
            seen[name] = true
          end
        end

        i = i + 1
      end
    end

    scanBook(BOOKTYPE_SPELL)
    scanBook(BOOKTYPE_PET)

    table.sort(spells, function(a, b)
      a = string.lower(a or "")
      b = string.lower(b or "")
      return a < b
    end)

    return spells
  end

  local function VfxCond_InitAbilityDropdown(row)
    if not row or not row.abilityDD then return end

    local spells = VfxCond_BuildAbilitySpellList()
    row._abilitySpells = spells

    local total = table.getn(spells)
    local perPage = 10

    if total == 0 then
      UIDropDownMenu_Initialize(row.abilityDD, function() end)
      if UIDropDownMenu_SetText then
        pcall(UIDropDownMenu_SetText, "No abilities found", row.abilityDD)
      end
      return
    end

    local maxPage = math.max(1, math.ceil(total / perPage))
    local page = row._abilityPage or 1
    if page < 1 then page = 1 end
    if page > maxPage then page = maxPage end
    row._abilityPage = page

    local startIndex = (page - 1) * perPage + 1
    local endIndex = math.min(startIndex + perPage - 1, total)

    UIDropDownMenu_Initialize(row.abilityDD, function(frame, level, menuList)
      local info

      if page > 1 then
        info = {}
        info.text = "|cffffd000<< Previous|r"
        info.value = "PREV"
        info.notCheckable = true
        info.func = function()
          row._abilityPage = page - 1
          VfxCond_InitAbilityDropdown(row)
          VfxCond_ReopenDDNextFrame(row)
        end
        UIDropDownMenu_AddButton(info)
      end

      local idx = startIndex
      while idx <= endIndex do
        local name = spells[idx]
        info = {}
        info.text = name
        info.value = name
        local pickedName = name
        info.func = function(button)
          local val = (button and button.value) or pickedName
          row._spellName = val

          if UIDropDownMenu_SetSelectedValue then
            pcall(UIDropDownMenu_SetSelectedValue, row.abilityDD, val)
          end
          if UIDropDownMenu_SetText then
            pcall(UIDropDownMenu_SetText, val, row.abilityDD)
          end
          if _GoldifyDD then
            _GoldifyDD(row.abilityDD)
          end
        end
        info.checked = (row._spellName == name)
        UIDropDownMenu_AddButton(info)
        idx = idx + 1
      end

      if page < maxPage then
        info = {}
        info.text = "|cffffd000Next >>|r"
        info.value = "NEXT"
        info.notCheckable = true
        info.func = function()
          row._abilityPage = page + 1
          VfxCond_InitAbilityDropdown(row)
          VfxCond_ReopenDDNextFrame(row)
        end
        UIDropDownMenu_AddButton(info)
      end
    end)

    local label = row._spellName or "Select ability"
    if UIDropDownMenu_SetText then
      pcall(UIDropDownMenu_SetText, label, row.abilityDD)
    end
    if _GoldifyDD then
      _GoldifyDD(row.abilityDD)
    end
  end

  local function VfxCond_UpdateStacksUI(row)
    if not row then return end

    local enabled = row._stacksEnabled and true or false

    if row.stacksCompDD then
      if enabled then row.stacksCompDD:Show() else row.stacksCompDD:Hide() end
    end
    if row.stacksVal then
      if enabled then row.stacksVal:Show() else row.stacksVal:Hide() end
    end
    if row.stacksValEnter then
      if enabled then row.stacksValEnter:Show() else row.stacksValEnter:Hide() end
    end

    local ok = true
    if enabled then
      local comp = row._stacksComp
      local val  = row._stacksVal
      comp = string.gsub(tostring(comp or ""), "^%s*(.-)%s*$", "%1")
      val  = string.gsub(tostring(val  or ""), "^%s*(.-)%s*$", "%1")
      if comp == "" or val == "" then
        ok = false
      end
    end
    if row.okBtn and row.okBtn.SetEnabled then
      row.okBtn:SetEnabled(ok and 1 or 0)
    end
  end

  local function VfxCond_SetRowState(row, state)
    row._state = state

    row.btn1:Hide()
    row.btn2:Hide()
    if row.btn3 then row.btn3:Hide() end
    if row.btn4 then row.btn4:Hide() end
    row.closeBtn:Show()
    if row.okBtn then row.okBtn:Hide() end
    row.editBox:Hide()
    row.addButton:Hide()
    row.labelFS:Hide()
    if row.abilityDD then row.abilityDD:Hide() end
    if row.itemDD then row.itemDD:Hide() end
    if row.glowCB then row.glowCB:Hide() end
    if row.greyCB then row.greyCB:Hide() end
    if row.fadeCB then row.fadeCB:Hide() end
    if row.fadeSlider then row.fadeSlider:Hide() end
    if row.fadeSliderPct then row.fadeSliderPct:Hide() end

    if row.stacksLabel then row.stacksLabel:Hide() end
    if row.stacksCB then row.stacksCB:Hide() end
    if row.stacksCompDD then row.stacksCompDD:Hide() end
    if row.stacksVal then row.stacksVal:Hide() end
    if row.stacksValEnter then row.stacksValEnter:Hide() end

    local spacing = row._spacing or 4
    local parentWidth = row._parentWidth or 260
    local closeWidth = row._closeWidth or 20

    if state == "STEP1" then
      row._branch = nil
      local available = parentWidth - closeWidth - spacing * 6
      if available < 80 then available = 80 end
      local w = math.floor(available / 5)

      row.btn1:SetWidth(w)
      row.btn2:SetWidth(w)
      row.addButton:SetWidth(w)
      if row.btn3 then row.btn3:SetWidth(w) end
      if row.btn4 then row.btn4:SetWidth(w) end

      row.btn1:ClearAllPoints()
      row.btn2:ClearAllPoints()
      row.addButton:ClearAllPoints()
      if row.btn3 then row.btn3:ClearAllPoints() end
      if row.btn4 then row.btn4:ClearAllPoints() end

      row.btn1:SetPoint("LEFT", row, "LEFT", 0, 0)
      row.btn2:SetPoint("LEFT", row.btn1, "RIGHT", spacing, 0)
      row.addButton:SetPoint("LEFT", row.btn2, "RIGHT", spacing, 0)
      if row.btn3 then row.btn3:SetPoint("LEFT", row.addButton, "RIGHT", spacing, 0) end
      if row.btn4 then row.btn4:SetPoint("LEFT", row.btn3, "RIGHT", spacing, 0) end

      row.btn1:SetText("Ability")
      row.btn2:SetText("Buff")
      row.addButton:SetText("Debuff")
      if row.btn3 then row.btn3:SetText("Talent") end
      if row.btn4 then row.btn4:SetText("Item") end

      row.btn1:Show()
      row.btn2:Show()
      row.addButton:Show()
      if row.btn3 then row.btn3:Show() end
      if row.btn4 then row.btn4:Show() end

    elseif state == "STEP2" then
      local available = parentWidth - closeWidth - spacing * 3
      if available < 120 then available = 120 end
      local w = math.floor(available / 2)

      row.btn1:SetWidth(w)
      row.btn2:SetWidth(w)

      row.btn1:ClearAllPoints()
      row.btn2:ClearAllPoints()
      row.btn1:SetPoint("LEFT", row, "LEFT", 0, 0)
      row.btn2:SetPoint("LEFT", row.btn1, "RIGHT", spacing, 0)

      if row._branch == "ABILITY" then
        row.btn1:SetText("Not on CD")
        row.btn2:SetText("On CD")
      elseif row._branch == "ITEM" then
        row.btn1:SetText("In bag/equipped")
        row.btn2:SetText("Missing")
      elseif row._branch == "TALENT" then
        row.btn1:SetText("Known")
        row.btn2:SetText("Not known")
      else
        row.btn1:SetText("Found")
        row.btn2:SetText("Missing")
      end

      row.btn1:Show()
      row.btn2:Show()

    elseif state == "STEP3" then
      local available = parentWidth - closeWidth - spacing * 3
      if available < 120 then available = 120 end
      local w = math.floor(available / 2)

      row.btn1:SetWidth(w)
      row.btn2:SetWidth(w)

      row.btn1:ClearAllPoints()
      row.btn2:ClearAllPoints()
      row.btn1:SetPoint("LEFT", row, "LEFT", 0, 0)
      row.btn2:SetPoint("LEFT", row.btn1, "RIGHT", spacing, 0)

      if row._branch == "ITEM" then
        row.btn1:SetText("Not on CD")
        row.btn2:SetText("On CD")
      else
        row.btn1:SetText("On player")
        row.btn2:SetText("On target")
      end
      row.btn1:Show()
      row.btn2:Show()

    elseif state == "STACKS" then
      if row.okBtn then row.okBtn:Show() end

      row.closeBtn:ClearAllPoints()
      if row.okBtn then row.okBtn:ClearAllPoints() end

      row.closeBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
      if row.okBtn then
       row.okBtn:SetPoint("RIGHT", row.closeBtn, "LEFT", -spacing, 0)
      end

      if row.stacksLabel then
        row.stacksLabel:ClearAllPoints()
        row.stacksLabel:SetPoint("LEFT", row, "LEFT", 0, 0)
        if row._branch == "ITEM" then row.stacksLabel:SetText("Quantity?") else row.stacksLabel:SetText("Stacks?") end
        row.stacksLabel:Show()
      end
      if row.stacksCB then
        row.stacksCB:ClearAllPoints()
        row.stacksCB:SetPoint("LEFT", row, "LEFT", 52, 0)
        row.stacksCB:Show()
        row.stacksCB:SetChecked(row._stacksEnabled and true or false)
      end
      if row.stacksCompDD then
        row.stacksCompDD:ClearAllPoints()
        row.stacksCompDD:SetPoint("LEFT", row, "LEFT", 57, -3)
      end
      if row.stacksVal then
        row.stacksVal:ClearAllPoints()
        row.stacksVal:SetPoint("LEFT", row, "LEFT", 142, 0)
      end
      if row.stacksValEnter then
        row.stacksValEnter:ClearAllPoints()
        row.stacksValEnter:SetPoint("LEFT", row.stacksVal, "RIGHT", 4, 0)
      end

      VfxCond_UpdateStacksUI(row)

    elseif state == "INPUT" then
      local addWidth = row.addButton:GetWidth() or 40
      local rightGap = 2
      local totalRight = closeWidth + spacing + addWidth + rightGap

      local editWidth = parentWidth - spacing - totalRight
      if editWidth < 60 then editWidth = 60 end

      row.editBox:ClearAllPoints()
      row.addButton:ClearAllPoints()
      if row.abilityDD then row.abilityDD:ClearAllPoints() end
      if row.itemDD then row.itemDD:ClearAllPoints() end

      row.editBox:SetWidth(editWidth)
      row.editBox:SetPoint("LEFT", row, "LEFT", 10, 0)

      row.addButton:SetPoint("RIGHT", row.closeBtn, "LEFT", -rightGap, 0)
      row.addButton:SetText("Add")

      if row._branch == "ABILITY" then
        if row.abilityDD then
          row.editBox:Hide()
          row.abilityDD:SetPoint("LEFT", row, "LEFT", -15, -3)
          if UIDropDownMenu_SetWidth then
            pcall(UIDropDownMenu_SetWidth, editWidth, row.abilityDD)
          end
          VfxCond_InitAbilityDropdown(row)
          row.abilityDD:Show()
        end
        row.addButton:Show()
      elseif row._branch == "ITEM" then
        if row.itemDD then
          row.editBox:Hide()
          row.itemDD:SetPoint("LEFT", row, "LEFT", -15, -3)
          if UIDropDownMenu_SetWidth then
            pcall(UIDropDownMenu_SetWidth, editWidth, row.itemDD)
          end
          VfxCond_InitItemDropdown(row)
          row.itemDD:Show()
        end
        row.addButton:Show()
      else
        if row.abilityDD then row.abilityDD:Hide() end
        row.editBox:Show()
        row.addButton:Show()
      end

    elseif state == "SAVED" then
      row.labelFS:SetText(row._desc or "")
      row.labelFS:Show()

      if row.glowCB and row.greyCB then
        row.labelFS:ClearAllPoints()
        row.labelFS:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

        row.glowCB:ClearAllPoints()
        row.greyCB:ClearAllPoints()
        row.glowCB:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -14)
        row.greyCB:SetPoint("LEFT", row.glowCB, "RIGHT", 40, 0)
        if row.fadeCB then
          row.fadeCB:ClearAllPoints()
          row.fadeCB:SetPoint("LEFT", row.greyCB, "RIGHT", 40, 0)
        end
        if row.fadeSlider then
          row.fadeSlider:ClearAllPoints()
          row.fadeSlider:SetPoint("LEFT", row.fadeCB, "RIGHT", 45, 0)
          if row.fadeSliderPct then
            row.fadeSliderPct:ClearAllPoints()
            row.fadeSliderPct:SetPoint("LEFT", row.fadeSlider, "RIGHT", 5, 0)
          end
        end

        row.glowCB:Show()
        row.greyCB:Show()
        if row.fadeCB then
          row.fadeCB:Show()
          if row.fadeCB:GetChecked() and row.fadeSlider then
            row.fadeSlider:Show()
            if row.fadeSliderPct then row.fadeSliderPct:Show() end
          end
        end
      end
    end
  end

  local function VfxCond_OnCancelEditing(row)
    row._branch = nil
    row._choiceBuffType = nil
    row._choiceMode = nil
    row._choiceUnit = nil
    row._spellName = nil
    row._itemName = nil
    row._choiceItemCd = nil
    row._abilityPage = 1

    row._stacksEnabled = nil
    row._stacksComp = nil
    row._stacksVal = nil

    if row.stacksCB then
      row.stacksCB:SetChecked(false)
    end
    if row.stacksVal and row.stacksVal.SetText then
      row.stacksVal:SetText("")
    end
    if row.stacksCompDD then
      if UIDropDownMenu_ClearAll then
        pcall(UIDropDownMenu_ClearAll, row.stacksCompDD)
      end
      if UIDropDownMenu_SetText then
        pcall(UIDropDownMenu_SetText, "", row.stacksCompDD)
      end
    end

    if row.editBox and row.editBox.SetText then
      row.editBox:SetText("")
    end

    if row.abilityDD then
      if UIDropDownMenu_ClearAll then
        pcall(UIDropDownMenu_ClearAll, row.abilityDD)
      end
      if UIDropDownMenu_SetText then
        pcall(UIDropDownMenu_SetText, "Select ability", row.abilityDD)
      end
    end

    VfxCond_SetRowState(row, "STEP1")
  end

  local function VfxCond_RebuildFromDB_Internal(typeKey)
    local mgr = VfxCond_Managers and VfxCond_Managers[typeKey]
    if not mgr or not mgr.anchor then return end

    local list = VfxCond_GetListForType(typeKey) or {}
    local count = VfxCond_Len(list)

    if not mgr.savedRows then mgr.savedRows = {} end

    local i
    for i = 1, count do
      local entry = list[i]
      local row = mgr.savedRows[i]
      if not row then
        row = mgr._createRow(mgr, false)
        mgr.savedRows[i] = row
      end
      row._entryIndex = i
      row._choiceBuffType = (entry and entry.buffType) or "BUFF"
      row._choiceMode = (entry and entry.mode) or "found"
      row._choiceUnit = (entry and entry.unit) or "player"
      row._spellName = (entry and entry.name) or ""
      row._itemName = (entry and entry.name) or ""
      row._choiceItemCd = (entry and entry.unit) or "notcd"
      row._stacksEnabled = (entry and entry.stacksEnabled) and true or nil
      row._stacksComp    = (entry and entry.stacksComp) or nil
      row._stacksVal     = (entry and entry.stacksVal) or nil

      row._desc = VfxCond_BuildDescription(
        row._choiceBuffType,
        row._choiceMode,
        row._choiceUnit,
        row._spellName,
        row._stacksEnabled,
        row._stacksComp,
        row._stacksVal
      )

      if row.glowCB then
        row.glowCB:SetChecked(entry and entry.glow)
        row.glowCB:SetScript("OnClick", function()
          local list2 = VfxCond_GetListForType(typeKey)
          if list2 and list2[row._entryIndex] then
            list2[row._entryIndex].glow = this:GetChecked() and true or nil
            _SafeRefresh(); _SafeEvaluate()
            _UpdateCondFrameForKey(_G["DoiteEdit_CurrentKey"])
          end
        end)
      end
      if row.greyCB then
        row.greyCB:SetChecked(entry and entry.grey)
        row.greyCB:SetScript("OnClick", function()
          local list2 = VfxCond_GetListForType(typeKey)
          if list2 and list2[row._entryIndex] then
            list2[row._entryIndex].grey = this:GetChecked() and true or nil
            _SafeRefresh(); _SafeEvaluate()
            _UpdateCondFrameForKey(_G["DoiteEdit_CurrentKey"])
          end
        end)
      end

      if row.fadeCB then
        row.fadeCB:SetChecked(entry and entry.fade)
        row.fadeCB:SetScript("OnClick", function()
          local list2 = VfxCond_GetListForType(typeKey)
          if list2 and list2[row._entryIndex] then
            list2[row._entryIndex].fade = this:GetChecked() and true or nil
            if list2[row._entryIndex].fade and not list2[row._entryIndex].fadeAlpha then
              list2[row._entryIndex].fadeAlpha = 0
            end
            _SafeRefresh(); _SafeEvaluate()
            _UpdateCondFrameForKey(_G["DoiteEdit_CurrentKey"])
          end
        end)
      end
      if row.fadeSlider then
        local fadeAlpha = tonumber(entry and entry.fadeAlpha) or 0
        if fadeAlpha < 0 then fadeAlpha = 0 end
        if fadeAlpha > 1 then fadeAlpha = 1 end
        row.fadeSlider:SetText(tostring(math.floor((fadeAlpha * 100) + 0.5)))
        local function SaveRowFadeAlpha()
          local list2 = VfxCond_GetListForType(typeKey)
          if list2 and list2[row._entryIndex] then
            list2[row._entryIndex].fadeAlpha = _ParseFadeAlpha(row.fadeSlider)
            _NormalizeFade(row.fadeSlider, list2[row._entryIndex].fadeAlpha)
            _SafeRefresh(); _SafeEvaluate()
          end
        end
        row.fadeSlider:SetScript("OnEnterPressed", function() SaveRowFadeAlpha(); this:ClearFocus() end)
        row.fadeSlider:SetScript("OnEditFocusLost", SaveRowFadeAlpha)
        row.fadeSlider:SetScript("OnEscapePressed", function() this:ClearFocus() end)
      end

      VfxCond_SetRowState(row, "SAVED")
      row:Show()
    end

    local nRows = VfxCond_Len(mgr.savedRows)
    for i = count + 1, nRows do
      if mgr.savedRows[i] then
        mgr.savedRows[i]:Hide()
        mgr.savedRows[i]._entryIndex = nil
      end
    end

    if not mgr.editRow then
      mgr.editRow = mgr._createRow(mgr, true)
    end
    VfxCond_OnCancelEditing(mgr.editRow)
    mgr.editRow:Show()

    local y = -42

    i = 1
    while mgr.savedRows and mgr.savedRows[i] do
      local row = mgr.savedRows[i]
      if row:IsShown() then
        row:ClearAllPoints()
        row:SetHeight(36)
        row:SetPoint("TOPLEFT", mgr.anchor, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", mgr.anchor, "TOPRIGHT", 0, y)
        y = y - 38
      end
      i = i + 1
    end

    if mgr.editRow and mgr.editRow:IsShown() then
      mgr.editRow:ClearAllPoints()
      mgr.editRow:SetPoint("TOPLEFT", mgr.anchor, "TOPLEFT", 0, y)
      mgr.editRow:SetPoint("TOPRIGHT", mgr.anchor, "TOPRIGHT", 0, y)
      y = y - 18
    end

    mgr.anchor:SetHeight(-y + 4)
    _Reflow()
  end

  local function VfxCond_OnAdd(row)
    if not _G["DoiteEdit_CurrentKey"] then return end
    local mgr = row._manager
    if not mgr then return end

    local text
    if row._branch == "ABILITY" then
      text = row._spellName or ""
    elseif row._branch == "ITEM" then
      text = row._itemName or ""
    else
      text = row.editBox and row.editBox:GetText() or ""
    end
    local parsedInput = VfxCond_ParseAuraInput(text)
    if not parsedInput then return end

    local buffType = row._choiceBuffType or "BUFF"
    local mode = row._choiceMode or "found"
    local unit

    if row._branch == "ABILITY" then
      unit = nil
      buffType = "ABILITY"
    elseif row._branch == "ITEM" then
      if row._choiceMode == "missing" then
        unit = nil
      else
        unit = row._choiceItemCd or "notcd"
      end
      buffType = "ITEM"
    elseif row._branch == "TALENT" then
      unit = nil
    else
      unit = row._choiceUnit or "player"
    end

    local list = VfxCond_GetListForType(mgr.typeKey)
    if not list then
      return
    end

    local entry = {
      buffType = buffType,
      mode = mode,
      unit = unit,
      name = parsedInput.name,
      spellid = parsedInput.spellid,
      Addedviaspellid = parsedInput.Addedviaspellid,
      fade = nil,
      fadeAlpha = 0,
    }

    if row._branch ~= "ABILITY" and row._branch ~= "TALENT" then
      entry.stacksEnabled = row._stacksEnabled and true or nil
      if entry.stacksEnabled then
        entry.stacksComp = row._stacksComp
        entry.stacksVal  = row._stacksVal
      else
        entry.stacksComp = nil
        entry.stacksVal  = nil
      end
    end

    local n = VfxCond_Len(list)
    list[n + 1] = entry
    list._daDirty = true
    local ck = _G["DoiteEdit_CurrentKey"]
    if ck and DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[ck] then
      DoiteAurasDB.spells[ck]._daHasVfx = true
    end
    VfxCond_RebuildFromDB_Internal(mgr.typeKey)
  end

  local function VfxCond_OnDeleteSaved(row)
    if not _G["DoiteEdit_CurrentKey"] then return end
    local mgr = row._manager
    if not mgr then return end

    local list = VfxCond_GetListForType(mgr.typeKey)
    if not list then return end

    local idx = row._entryIndex or 0
    local n = VfxCond_Len(list)
    if idx < 1 or idx > n then return end

    for j = idx, n - 1 do
      list[j] = list[j + 1]
    end
    list[n] = nil
    list._daDirty = true

    local ck = _G["DoiteEdit_CurrentKey"]
    if ck and DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[ck] then
      DoiteAurasDB.spells[ck]._daHasVfx = nil
    end

    VfxCond_RebuildFromDB_Internal(mgr.typeKey)
  end

  local function VfxCond_InitComparatorDD(ddframe, commitFunc)
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

  local function VfxCond_CreateRow(mgr, isEditing)
    VfxCond_RowCounter = VfxCond_RowCounter + 1

    local parent = mgr.anchor
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(18)

    row._manager = mgr

    local parentWidth = (parent and parent.GetWidth and parent:GetWidth()) or 0
    if parentWidth <= 0 then parentWidth = 260 end
    local closeWidth = 20
    local spacing = 4
    local mainWidth = math.floor((parentWidth - closeWidth - spacing * 3) / 2)

    row._parentWidth = parentWidth
    row._closeWidth = closeWidth
    row._spacing = spacing
    row._mainWidth = mainWidth

    row.btn1 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.btn2 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.btn3 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.btn4 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.closeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.editBox = CreateFrame("EditBox", nil, row)
    row.addButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.labelFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.labelFS:SetJustifyH("LEFT")

    row.editBox:SetAutoFocus(false)
    row.editBox:SetFontObject("GameFontNormalSmall")
    if row.editBox.SetTextInsets then
      row.editBox:SetTextInsets(6, 6, 0, 0)
    end
    if row.editBox.SetBackdrop then
      row.editBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
      })
      row.editBox:SetBackdropColor(0, 0, 0, 0.85)
      row.editBox:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end

    local ddName = "DoiteVfxCond_AbilityDD_" .. tostring(mgr.typeKey or "X") .. "_" .. tostring(VfxCond_RowCounter)
    row.abilityDD = CreateFrame("Frame", ddName, row, "UIDropDownMenuTemplate")
    row.itemDD = CreateFrame("Frame", "DoiteVfxCond_ItemDD_" .. tostring(mgr.typeKey or "X") .. "_" .. tostring(VfxCond_RowCounter), row, "UIDropDownMenuTemplate")
    DoiteEdit_HookDropDownButtonOnClick(row.itemDD, function()
      if row and row._branch == "ITEM" then
        VfxCond_InitItemDropdown(row)
      end
    end)
    row._abilityPage = 1

    row.okBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.okBtn:SetWidth(60)
    row.okBtn:SetHeight(18)
    row.okBtn:SetText("Continue")

    row.stacksLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.stacksLabel:SetText("Stacks?")

    row.stacksCB = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.stacksCB:SetWidth(18); row.stacksCB:SetHeight(18)

    local dd2Name = "DoiteVfxCond_StacksCompDD_" .. tostring(mgr.typeKey or "X") .. "_" .. tostring(VfxCond_RowCounter)
    row.stacksCompDD = CreateFrame("Frame", dd2Name, row, "UIDropDownMenuTemplate")

    row._stacksCompWidth = 45
    if UIDropDownMenu_SetWidth then
      pcall(UIDropDownMenu_SetWidth, row._stacksCompWidth, row.stacksCompDD)
    end

    row.stacksVal = CreateFrame("EditBox", nil, row)
    row.stacksVal:SetWidth(40)
    row.stacksVal:SetHeight(18)
    row.stacksVal:SetAutoFocus(false)
    row.stacksVal:SetFontObject("GameFontNormalSmall")
    if row.stacksVal.SetTextInsets then
      row.stacksVal:SetTextInsets(6, 6, 0, 0)
    end
    if row.stacksVal.SetBackdrop then
      row.stacksVal:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
      })
      row.stacksVal:SetBackdropColor(0, 0, 0, 0.85)
      row.stacksVal:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end

    row.stacksValEnter = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.stacksValEnter:SetText("(#)")

    row.btn1:SetWidth(mainWidth)
    row.btn2:SetWidth(mainWidth)
    row.btn3:SetWidth(mainWidth)
    row.btn4:SetWidth(mainWidth)
    row.btn1:SetHeight(18)
    row.btn2:SetHeight(18)
    row.btn3:SetHeight(18)
    row.btn4:SetHeight(18)

    row.closeBtn:SetWidth(closeWidth)
    row.closeBtn:SetHeight(18)

    local editWidth = parentWidth - closeWidth - spacing * 3 - 40
    if editWidth < 60 then editWidth = 60 end

    row.editBox:SetWidth(editWidth)
    row.editBox:SetHeight(18)
    row.editBox:SetAutoFocus(false)
    row.editBox:SetFontObject("GameFontNormalSmall")

    row.addButton:SetWidth(40)
    row.addButton:SetHeight(18)

    row.btn1:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.btn2:SetPoint("LEFT", row.btn1, "RIGHT", spacing, 0)
    row.closeBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    row.editBox:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.addButton:SetPoint("LEFT", row.editBox, "RIGHT", spacing, 0)

    row.abilityDD:SetPoint("LEFT", row, "LEFT", 0, -2)
    if UIDropDownMenu_SetWidth then
      pcall(UIDropDownMenu_SetWidth, parentWidth - closeWidth - spacing * 3 - 40, row.abilityDD)
    end

    row.labelFS:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.labelFS:SetTextColor(1, 1, 1)
    row.labelFS:SetNonSpaceWrap(false)

    local function CreateMiniCheck(label)
      local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
      cb:SetWidth(18); cb:SetHeight(18)
      cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      cb.text:SetPoint("LEFT", cb, "RIGHT", 0, 0)
      cb.text:SetText(label)
      return cb
    end

    row.glowCB = CreateMiniCheck("Glow")
    row.greyCB = CreateMiniCheck("Grey")
    row.fadeCB = CreateMiniCheck("Fade")
    row.fadeSlider = CreateFrame("EditBox", nil, row)
    row.fadeSlider:SetWidth(40)
    row.fadeSlider:SetHeight(18)
    row.fadeSlider:SetAutoFocus(false)
    row.fadeSlider:SetJustifyH("CENTER")
    row.fadeSlider:SetFontObject("GameFontNormalSmall")
    if row.fadeSlider.SetTextInsets then
      row.fadeSlider:SetTextInsets(6, 6, 0, 0)
    end
    if row.fadeSlider.SetBackdrop then
      row.fadeSlider:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
      })
      row.fadeSlider:SetBackdropColor(0, 0, 0, 0.85)
      row.fadeSlider:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end
    row.fadeSlider:SetNumeric(true)
    row.fadeSliderPct = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.fadeSliderPct:SetText("|cffffd000%|r")

    row.closeBtn:SetText("X")

    DoiteEdit_YellowifyButton(row.btn1)
    DoiteEdit_YellowifyButton(row.btn2)
    DoiteEdit_YellowifyButton(row.btn3)
    DoiteEdit_YellowifyButton(row.btn4)
    DoiteEdit_YellowifyButton(row.addButton)
    DoiteEdit_YellowifyButton(row.closeBtn)
    DoiteEdit_YellowifyButton(row.okBtn)

    row.btn1:SetScript("OnClick", function()
      local state = row._state
      if state == "STEP1" then
        row._branch = "ABILITY"
        row._choiceBuffType = "ABILITY"
        VfxCond_SetRowState(row, "STEP2")
      elseif state == "STEP2" then
        if row._branch == "ABILITY" then
          row._choiceMode = "notcd"
          VfxCond_SetRowState(row, "INPUT")
        elseif row._branch == "ITEM" then
          row._choiceMode = "found"
          VfxCond_SetRowState(row, "STEP3")
        elseif row._branch == "TALENT" then
          row._choiceMode = "Known"
          VfxCond_SetRowState(row, "INPUT")
        else
          row._choiceMode = "found"
          VfxCond_SetRowState(row, "STEP3")
        end
      elseif state == "STEP3" then
        if row._branch == "ITEM" then
          row._choiceItemCd = "notcd"
          if row._choiceMode == "missing" then
            VfxCond_SetRowState(row, "INPUT")
          else
            VfxCond_SetRowState(row, "STACKS")
          end
          return
        end
        row._choiceUnit = "player"
        if row._choiceMode == "missing" then
          VfxCond_SetRowState(row, "INPUT")
        else
          VfxCond_SetRowState(row, "STACKS")
        end
      end
    end)

    row.btn2:SetScript("OnClick", function()
      local state = row._state
      if state == "STEP1" then
        row._branch = "BUFF"
        row._choiceBuffType = "BUFF"
        VfxCond_SetRowState(row, "STEP2")
      elseif state == "STEP2" then
        if row._branch == "ABILITY" then
          row._choiceMode = "oncd"
          VfxCond_SetRowState(row, "INPUT")
        elseif row._branch == "ITEM" then
          row._choiceMode = "missing"
          row._choiceItemCd = nil
          row._stacksEnabled = nil
          row._stacksComp = nil
          row._stacksVal  = nil
          VfxCond_SetRowState(row, "INPUT")
        elseif row._branch == "TALENT" then
          row._choiceMode = "NotKnown"
          VfxCond_SetRowState(row, "INPUT")
        else
          row._choiceMode = "missing"

          row._stacksEnabled = nil
          row._stacksComp = nil
          row._stacksVal  = nil
          if row.stacksCB then
            row.stacksCB:SetChecked(false)
          end
          if row.stacksVal and row.stacksVal.SetText then
            row.stacksVal:SetText("")
          end
          if row.stacksCompDD then
            if UIDropDownMenu_ClearAll then
              pcall(UIDropDownMenu_ClearAll, row.stacksCompDD)
            end
            if UIDropDownMenu_SetText then
              pcall(UIDropDownMenu_SetText, "", row.stacksCompDD)
            end
          end

          VfxCond_SetRowState(row, "STEP3")
        end
      elseif state == "STEP3" then
        if row._branch == "ITEM" then
          row._choiceItemCd = "oncd"
          if row._choiceMode == "missing" then
            VfxCond_SetRowState(row, "INPUT")
          else
            VfxCond_SetRowState(row, "STACKS")
          end
          return
        end
        row._choiceUnit = "target"
        if row._choiceMode == "missing" then
          VfxCond_SetRowState(row, "INPUT")
        else
          VfxCond_SetRowState(row, "STACKS")
        end
      end
    end)

    row.addButton:SetScript("OnClick", function()
      local state = row._state
      if state == "STEP1" then
        row._branch = "DEBUFF"
        row._choiceBuffType = "DEBUFF"
        VfxCond_SetRowState(row, "STEP2")
      elseif state == "INPUT" then
        VfxCond_OnAdd(row)
      end
    end)

    row.btn3:SetScript("OnClick", function()
      if row._state == "STEP1" then
        row._branch = "TALENT"
        row._choiceBuffType = "TALENT"
        VfxCond_SetRowState(row, "STEP2")
      end
    end)

    row.btn4:SetScript("OnClick", function()
      if row._state == "STEP1" then
        row._branch = "ITEM"
        row._choiceBuffType = "ITEM"
        row._choiceMode = nil
        row._choiceUnit = nil
        row._choiceItemCd = nil
        VfxCond_SetRowState(row, "STEP2")
      end
    end)

    row.closeBtn:SetScript("OnClick", function()
      if row._state == "SAVED" then
        VfxCond_OnDeleteSaved(row)
      else
        VfxCond_OnCancelEditing(row)
      end
    end)

    row.editBox:SetScript("OnEnterPressed", function()
      VfxCond_OnAdd(row)
    end)

    VfxCond_InitComparatorDD(row.stacksCompDD, function(val)
      row._stacksComp = val
      if row._state == "STACKS" then
        VfxCond_UpdateStacksUI(row)
      end
    end)

    if UIDropDownMenu_SetText then
      pcall(UIDropDownMenu_SetText, "", row.stacksCompDD)
    end

    row.stacksCB:SetScript("OnClick", function()
      row._stacksEnabled = this:GetChecked() and true or nil
      if not row._stacksEnabled then
        row._stacksComp = nil
        row._stacksVal  = nil
        if row.stacksVal and row.stacksVal.SetText then
          row.stacksVal:SetText("")
        end
        if UIDropDownMenu_ClearAll then
          pcall(UIDropDownMenu_ClearAll, row.stacksCompDD)
        end
        if UIDropDownMenu_SetText then
          pcall(UIDropDownMenu_SetText, "", row.stacksCompDD)
        end
      end
      if row._state == "STACKS" then
        VfxCond_UpdateStacksUI(row)
      end
    end)

    row.stacksVal:SetScript("OnTextChanged", function()
      row._stacksVal = row.stacksVal:GetText()
      if row._state == "STACKS" then
        VfxCond_UpdateStacksUI(row)
      end
    end)

    row.okBtn:SetScript("OnClick", function()
      if not _G["DoiteEdit_CurrentKey"] then return end
      if row._state ~= "STACKS" then return end

      if row._stacksEnabled then
        local comp = string.gsub(tostring(row._stacksComp or ""), "^%s*(.-)%s*$", "%1")
        local val  = string.gsub(tostring(row._stacksVal  or ""), "^%s*(.-)%s*$", "%1")
        if comp == "" or val == "" then
          return
        end
      end

      VfxCond_SetRowState(row, "INPUT")
    end)

    row._state = "SAVED"
    VfxCond_SetRowState(row, "SAVED")

    row:Hide()
    return row
  end

  -- NOTE: VfxCond_Managers / VfxCond_RegisterManager / VfxCond_RefreshFromDB /
  -- VfxCond_ResetEditing are forward-declared at the top of this do-block
  -- so all helpers reference the same upvalues.

  VfxCond_RegisterManager = function(typeKey, anchorFrame)
    if not anchorFrame then return end

    local mgr = VfxCond_Managers[typeKey]
    if not mgr then
      mgr = {}
      VfxCond_Managers[typeKey] = mgr
    end

    mgr.typeKey = typeKey
    mgr.anchor = anchorFrame
    mgr.savedRows = mgr.savedRows or {}
    mgr.editRow = mgr.editRow or nil
    mgr._createRow = VfxCond_CreateRow

    if not mgr.label then
      local label = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      label:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, -15)
      label:SetJustifyH("LEFT")
      label:SetTextColor(1, 0.82, 0)
      label:SetText("Add visual effect conditions for glow/grey/fade:")
      mgr.label = label
    end
    if not mgr.wildcardHint then
      local hint = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      hint:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, -26)
      hint:SetJustifyH("LEFT")
      hint:SetTextColor(0.7, 0.7, 0.7)
      hint:SetText("Add '*' at the end for prefix match (e.g. 'Seal of*').")
      mgr.wildcardHint = hint
    end

    anchorFrame:SetHeight(20)
    anchorFrame:Hide()
  end

  VfxCond_RefreshFromDB = function(typeKey)
    for tk, mgr in pairs(VfxCond_Managers) do
      if mgr.anchor then
        if tk == typeKey then
          mgr.anchor:Show()
        else
          mgr.anchor:Hide()
        end
      end
    end

    if typeKey then
      VfxCond_RebuildFromDB_Internal(typeKey)
    end

    -- Same reason as AuraCond_RefreshFromDB above.
    if DoiteConditions then
      DoiteConditions._flagsDirty = true
    end

    _Reflow()
  end

  VfxCond_ResetEditing = function()
  end

  _G["VfxCond_Managers"]        = VfxCond_Managers
  _G["VfxCond_RegisterManager"] = VfxCond_RegisterManager
  _G["VfxCond_RefreshFromDB"]   = VfxCond_RefreshFromDB
  _G["VfxCond_ResetEditing"]    = VfxCond_ResetEditing
end