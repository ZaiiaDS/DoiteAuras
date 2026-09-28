---------------------------------------------------------------
-- DoiteEditHelpers.lua
-- Pure UI helpers for DoiteEdit.lua. Extracted from DoiteEdit.lua
-- (Phase 1 of the split).
--
-- Functions in this file:
--   FONT_CHOICES_EDIT / FLAG_CHOICES_EDIT   (tables)
--   SOUND_FILES                             (table)
--   _EditFontLabelForValue / _EditFlagLabelForValue
--   _ParseFadeAlphaFromBox / _NormalizeFadeBox
--   DoiteEdit_SetDropdownInteractive
--   DoiteEdit_HookDropDownButtonOnClick
--   _IsRogueOrDruid / _IsHunterOrWarlock
--   _DA_GetAbilityCooldownDuration / _DA_SetSliderTimeDisplay
--   DoiteEdit_AbilitySupportsProcSound
--   DoiteEdit_YellowifyButton / DoiteEdit_EnableCheck / DoiteEdit_DisableCheck
--   _GoldifyDD / _GreyifyDD / _WhiteifyDDText
--   AuraCond_TitleCase
--   StylePlainEditBox
--   _DA_GetParentDims / _DA_ComputePosSizeRanges
--
-- Loaded BEFORE DoiteEdit.lua (see DoiteAuras.toc).
--
-- All functions that were file-locals in DoiteEdit.lua are exposed
-- with a DoiteEdit_ prefix through _G so the main file can alias
-- them without ambiguity.
---------------------------------------------------------------

---------------------------------------------------------------
-- Font / flag choices (tables)
---------------------------------------------------------------
_G["DoiteEdit_FONT_CHOICES"] = {
    { text = "Default",   value = "" },
    { text = "Frizqt",    value = "Fonts\\FRIZQT__.TTF" },
    { text = "ArialN",    value = "Fonts\\ARIALN.TTF" },
    { text = "Morpheus",  value = "Fonts\\MORPHEUS.TTF" },
    { text = "Skurri",    value = "Fonts\\SKURRI.TTF" },
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

_G["DoiteEdit_FLAG_CHOICES"] = {
    { text = "None",          value = "" },
    { text = "Outline",       value = "OUTLINE" },
    { text = "Thick outline", value = "THICKOUTLINE" },
}

local FONT_CHOICES_EDIT = _G["DoiteEdit_FONT_CHOICES"]
local FLAG_CHOICES_EDIT = _G["DoiteEdit_FLAG_CHOICES"]

local function _EditFontLabelForValue(v)
    local i
    for i = 1, table.getn(FONT_CHOICES_EDIT) do
        if FONT_CHOICES_EDIT[i].value == (v or "") then
            return FONT_CHOICES_EDIT[i].text
        end
    end
    return "Default"
end

local function _EditFlagLabelForValue(v)
    local i
    for i = 1, table.getn(FLAG_CHOICES_EDIT) do
        if FLAG_CHOICES_EDIT[i].value == (v or "") then
            return FLAG_CHOICES_EDIT[i].text
        end
    end
    return "Outline"
end

_G["DoiteEdit_FontLabelForValue"] = _EditFontLabelForValue
_G["DoiteEdit_FlagLabelForValue"] = _EditFlagLabelForValue

---------------------------------------------------------------
-- Sound file list
---------------------------------------------------------------
_G["DoiteEdit_SOUND_FILES"] = {
  "JDO - Dont move, Shackles.ogg", "JDO - Loot banned.ogg", "Trend - Uwu.ogg", "Custom - Poison ammo.ogg", "Custom - Arcane ammo.ogg", "Custom - Explosive ammo.ogg", "Custom - Lock n Load.ogg",
  "MPOWA - Aggro.ogg", "MPOWA - Arrow Swoosh.ogg", "MPOWA - Bam.ogg", "MPOWA - Bigkiss.ogg", "MPOWA - Bite.ogg", "MPOWA - Burp.ogg", "MPOWA - Cat.ogg", "MPOWA - Chant (1).ogg", "MPOWA - Chant (2).ogg", "MPOWA - Chimes.ogg", "MPOWA - Cookie.ogg", "MPOWA - ESpark.ogg", "MPOWA - Fireball.ogg", "MPOWA - Gasp.ogg",
  "MPOWA - Heartbeat.ogg", "MPOWA - Hic.ogg", "MPOWA - Hit (1).ogg", "MPOWA - Hit (2).ogg", "MPOWA - Hit (3).ogg", "MPOWA - Hit (4).ogg", "MPOWA - Hit (5).ogg", "MPOWA - Hit (6).ogg", "MPOWA - Hit (7).ogg", "MPOWA - Hit (8).ogg",
  "MPOWA - Huh.ogg", "MPOWA - Hurricane.ogg", "MPOWA - Hyena.ogg", "MPOWA - Kaching.ogg", "MPOWA - Moan.ogg", "MPOWA - Panther.ogg", "MPOWA - Polarbear.ogg", "MPOWA - Punch.ogg", "MPOWA - Phone.ogg",
  "MPOWA - Rainroof.ogg", "MPOWA - Rocket.ogg", "MPOWA - Shipswhistle.ogg", "MPOWA - Shot.ogg", "MPOWA - Snakeatt.ogg", "MPOWA - Sneeze.ogg", "MPOWA - Sonar.ogg",
  "MPOWA - Splash.ogg", "MPOWA - Squeakypig.ogg", "MPOWA - Swordecho.ogg", "MPOWA - Throwknife.ogg", "MPOWA - Thunder.ogg", "MPOWA - Wilhelm.ogg", "MPOWA - Wickedlaugh (1).ogg",
  "MPOWA - Wickedlaugh (2).ogg", "MPOWA - Wolf.ogg", "MPOWA - Yeehaw.ogg"
}

---------------------------------------------------------------
-- Fade % helpers
---------------------------------------------------------------
local function _ParseFadeAlphaFromBox(box)
  local pct = tonumber(box and box:GetText())
  if not pct then
    return 0
  end
  if pct < 0 then pct = 0 end
  if pct > 100 then pct = 100 end
  return pct / 100
end

local function _NormalizeFadeBox(box, alpha)
  if not box then return end
  local pct = math.floor(((alpha or 0) * 100) + 0.5)
  if pct < 0 then pct = 0 end
  if pct > 100 then pct = 100 end
  box:SetText(tostring(pct))
end

_G["DoiteEdit_ParseFadeAlphaFromBox"] = _ParseFadeAlphaFromBox
_G["DoiteEdit_NormalizeFadeBox"]      = _NormalizeFadeBox

---------------------------------------------------------------
-- Dropdown interactivity + click hook
---------------------------------------------------------------
local function DoiteEdit_SetDropdownInteractive(dd, enabled)
  if not dd then
    return
  end

  local name = dd.GetName and dd:GetName()
  local btn = name and _G[name .. "Button"] or nil

  if enabled then
    if UIDropDownMenu_EnableDropDown then
      pcall(UIDropDownMenu_EnableDropDown, dd)
    end

    if btn and btn.Enable then
      btn:Enable()
    end

    if name then
      local t = _G[name .. "Text"]
      if t and t.SetTextColor then
        t:SetTextColor(1, 1, 1)
      end
    end
  else
    if UIDropDownMenu_DisableDropDown then
      pcall(UIDropDownMenu_DisableDropDown, dd)
    end

    if btn and btn.Disable then
      btn:Disable()
    end

    if name then
      local t = _G[name .. "Text"]
      if t and t.SetTextColor then
        t:SetTextColor(0.6, 0.6, 0.6)
      end
    end
  end
end

local function DoiteEdit_HookDropDownButtonOnClick(dd, fn)
  if not dd or not fn or not dd.GetName then
    return
  end

  local name = dd:GetName()
  if not name then
    return
  end

  local btn = _G[name .. "Button"]
  if not btn or btn._doiteRefreshHooked then
    return
  end
  btn._doiteRefreshHooked = true

  local prev = btn.GetScript and btn:GetScript("OnClick")
  btn:SetScript("OnClick", function()
    fn()
    if prev then
      prev()
    end
  end)
end

_G["DoiteEdit_SetDropdownInteractive"]      = DoiteEdit_SetDropdownInteractive
_G["DoiteEdit_HookDropDownButtonOnClick"]   = DoiteEdit_HookDropDownButtonOnClick

---------------------------------------------------------------
-- Class gates
---------------------------------------------------------------
local function _IsRogueOrDruid()
  local _, c = UnitClass("player")
  c = c and string.upper(c) or ""
  return (c == "ROGUE" or c == "DRUID")
end

local function _IsHunterOrWarlock()
  local _, c = UnitClass("player")
  c = c and string.upper(c) or ""
  return (c == "HUNTER" or c == "WARLOCK")
end

_G["DoiteEdit_IsRogueOrDruid"]    = _IsRogueOrDruid
_G["DoiteEdit_IsHunterOrWarlock"] = _IsHunterOrWarlock

---------------------------------------------------------------
-- Ability full cooldown + slider window display
---------------------------------------------------------------
local function _DA_GetAbilityCooldownDuration(data)
  if not data then return nil end
  local spellName = data.name or data.displayName
  if not spellName or spellName == "" then return nil end

  local getFull = _G["DoiteConditions_GetAbilityFullDuration"]
  if type(getFull) == "function" then
    local v = getFull(spellName)
    if v and v > 0 then
      return v
    end
  end

  local getCD = _G["DoiteConditions_GetAbilityCooldown"]
  if type(getCD) == "function" then
    local _, dur = getCD(spellName)
    if dur and dur > 0 then
      return math.floor(dur + 0.5)
    end
  end

  return nil
end

local function _DA_SetSliderTimeDisplay(box, userValue, data)
  if not box then return end

  if userValue and userValue ~= "" and tonumber(userValue) then
    box._daSettingPlaceholder = true
    box:SetText(tostring(userValue))
    box._daSettingPlaceholder = false
    box._daIsPlaceholder = nil
    box:SetTextColor(1, 0.82, 0)
    return
  end

  local defaultDur = _DA_GetAbilityCooldownDuration(data)

  box._daSettingPlaceholder = true
  if defaultDur then
    box:SetText(tostring(defaultDur))
    box._daIsPlaceholder = true
    box:SetTextColor(0.5, 0.5, 0.5)
  else
    box:SetText("")
    box._daIsPlaceholder = true
    box:SetTextColor(0.5, 0.5, 0.5)
  end
  box._daSettingPlaceholder = false
end

_G["DoiteEdit_GetAbilityCooldownDuration"] = _DA_GetAbilityCooldownDuration
_G["DoiteEdit_SetSliderTimeDisplay"]       = _DA_SetSliderTimeDisplay

---------------------------------------------------------------
-- Proc sound support probe
---------------------------------------------------------------
local function DoiteEdit_AbilitySupportsProcSound(data)
  if not data then
    return false
  end
  local spellName = data.name
  if not spellName or spellName == "" then
    spellName = data.displayName
  end
  if not spellName or spellName == "" then
    return false
  end
  local tbl = _G.DoiteConditions_ProcWindowDurations
  local dur = tbl and tbl[spellName]
  return (type(dur) == "number" and dur > 0) and true or false
end

_G["DoiteEdit_AbilitySupportsProcSound"] = DoiteEdit_AbilitySupportsProcSound

---------------------------------------------------------------
-- Button + CheckButton styling helpers
---------------------------------------------------------------
local function DoiteEdit_YellowifyButton(btn)
  if not btn then
    return
  end
  if btn.SetNormalFontObject then
    btn:SetNormalFontObject("GameFontNormalSmall")
  end
  local fs = btn:GetFontString()
  if fs and fs.SetTextColor then
    fs:SetTextColor(1, 0.82, 0)
  end
end

local function DoiteEdit_EnableCheck(cb)
  if not cb then
    return
  end
  cb:Enable()
  if cb.text and cb.text.SetTextColor then
    cb.text:SetTextColor(1, 0.82, 0)
  end
end

local function DoiteEdit_DisableCheck(cb)
  if not cb then
    return
  end
  cb:Disable()
  if cb.text and cb.text.SetTextColor then
    cb.text:SetTextColor(0.6, 0.6, 0.6)
  end
end

_G["DoiteEdit_YellowifyButton"] = DoiteEdit_YellowifyButton
_G["DoiteEdit_EnableCheck"]     = DoiteEdit_EnableCheck
_G["DoiteEdit_DisableCheck"]    = DoiteEdit_DisableCheck

---------------------------------------------------------------
-- DD text colour helpers (globals in original file already)
---------------------------------------------------------------
function _GoldifyDD(dd)
  if not dd or not dd.GetName then
    return
  end
  local name = dd:GetName()
  if not name then
    return
  end
  local txt = _G[name .. "Text"]
  if txt and txt.SetTextColor then
    txt:SetTextColor(1, 0.82, 0)
  end
end

function _GreyifyDD(dd)
  if not dd or not dd.GetName then
    return
  end
  local name = dd:GetName()
  local txt = _G[name .. "Text"]
  if txt and txt.SetTextColor then
    txt:SetTextColor(0.6, 0.6, 0.6)
  end
end

function _WhiteifyDDText(dd)
  if not dd or not dd.GetName then
    return
  end
  local name = dd:GetName()
  if not name then
    return
  end
  local txt = _G[name .. "Text"]
  if txt and txt.SetTextColor then
    txt:SetTextColor(1, 1, 1)
  end
end

---------------------------------------------------------------
-- Title case
---------------------------------------------------------------
local function AuraCond_TitleCase(str)
  if not str then
    return ""
  end
  str = tostring(str)

  local exceptions = {
    ["of"] = true, ["and"] = true, ["the"] = true, ["for"] = true,
    ["in"] = true, ["on"] = true, ["to"] = true, ["a"] = true,
    ["an"] = true, ["with"] = true, ["by"] = true, ["at"] = true
  }

  local function IsRomanNumeralToken(core)
    if not core or core == "" then
      return false
    end
    local upper = string.upper(core)
    if not string.find(upper, "^[IVXLCDM]+$") then
      return false
    end
    if string.len(upper) > 4 then
      return false
    end
    return true
  end

  local function DotAwareLowerRest(rest)
    if not rest or rest == "" then
      return ""
    end
    rest = string.lower(rest)
    rest = string.gsub(rest, "%.(%a)", function(a)
      return "." .. string.upper(a)
    end)
    return rest
  end

  local result, first = "", true
  local word
  for word in string.gfind(str, "%S+") do
    local startsParen = (string.sub(word, 1, 1) == "(")
    local leading = startsParen and "(" or ""
    local core = startsParen and string.sub(word, 2) or word

    local lowerCore = string.lower(core or "")
    local upperCore = string.upper(core or "")
    local c = string.sub(core or "", 1, 1) or ""
    local rest = string.sub(core or "", 2) or ""

    if IsRomanNumeralToken(core) then
      result = result .. leading .. upperCore .. " "
      first = false
    else
      if first then
        result = result .. leading .. string.upper(c) .. DotAwareLowerRest(rest) .. " "
        first = false
      else
        if startsParen then
          result = result .. leading .. string.upper(c) .. DotAwareLowerRest(rest) .. " "
        elseif exceptions[lowerCore] then
          result = result .. lowerCore .. " "
        else
          result = result .. leading .. string.upper(c) .. DotAwareLowerRest(rest) .. " "
        end
      end
    end
  end

  result = string.gsub(result, "%s+$", "")
  return result
end

_G["DoiteEdit_AuraCond_TitleCase"] = AuraCond_TitleCase

---------------------------------------------------------------
-- EditBox styling
---------------------------------------------------------------
local function StylePlainEditBox(eb, justify)
  if not eb then
    return
  end
  eb:SetAutoFocus(false)
  eb:SetFontObject("GameFontNormalSmall")
  eb:SetJustifyH(justify or "LEFT")
  if eb.SetTextInsets then
    eb:SetTextInsets(6, 6, 0, 0)
  end
  if eb.SetBackdrop then
    eb:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    eb:SetBackdropColor(0, 0, 0, 0.85)
    eb:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  end
end

_G["DoiteEdit_StylePlainEditBox"] = StylePlainEditBox

---------------------------------------------------------------
-- Position / Size slider bounds
---------------------------------------------------------------
local function _DA_GetParentDims()
  local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
  local sw, sh = GetScreenWidth(), GetScreenHeight()
  if sw > uw then uw = sw end
  if sh > uh then uh = sh end
  return uw, uh
end

local function _DA_ComputePosSizeRanges()
  local w, h = _DA_GetParentDims()
  w = math.floor(w + 0.5)
  h = math.floor(h + 0.5)

  local halfW = math.floor(w * 0.5)
  local halfH = math.floor(h * 0.5)

  local minX, maxX = -halfW, halfW
  local minY, maxY = -halfH, halfH

  local minSize = 10
  local maxSize = math.max(100, math.floor(math.min(w, h) * 0.20 + 0.5))

  return minX, maxX, minY, maxY, minSize, maxSize
end

_G["DoiteEdit_GetParentDims"]          = _DA_GetParentDims
_G["DoiteEdit_ComputePosSizeRanges"]   = _DA_ComputePosSizeRanges

---------------------------------------------------------------
-- Grid overlay (was Modules/DoiteEditGrid.lua)
---------------------------------------------------------------
local _DoiteGridFrame = nil
local _DoiteGridLines = {}

local function _CreateGridFrame()
  if _DoiteGridFrame then
    return _DoiteGridFrame
  end

  local grid = CreateFrame("Frame", "DoiteGridOverlay", UIParent)
  grid:SetAllPoints(UIParent)
  grid:SetFrameStrata("BACKGROUND")
  grid:SetFrameLevel(1)
  grid:EnableMouse(false)

  local bg = grid:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(grid)
  bg:SetTexture(0, 0, 0, 0.7)

  grid:Hide()

  local function DrawGrid()
    for _, line in ipairs(_DoiteGridLines) do
      line:Hide()
    end

    local gridSize = 20
    local w, h = UIParent:GetWidth() * 2, UIParent:GetHeight() * 2
    local limitW, limitH = (UIParent:GetWidth() / 2) * 1.5, (UIParent:GetHeight() / 2) * 1.5
    local lineIdx = 0

    local function GetLine()
        lineIdx = lineIdx + 1
        local line = _DoiteGridLines[lineIdx]
        if not line then
            line = grid:CreateTexture(nil, "OVERLAY")
            _DoiteGridLines[lineIdx] = line
        end
        return line
    end

    local v = GetLine()
    v:SetTexture(1, 0, 0, 0.5)
    v:SetWidth(2)
    v:SetHeight(h)
    v:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    v:Show()

    local hz = GetLine()
    hz:SetTexture(1, 0, 0, 0.5)
    hz:SetHeight(2)
    hz:SetWidth(w)
    hz:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    hz:Show()

    local x = gridSize
    while x < limitW do
      local l = GetLine()
      l:SetTexture(1, 1, 1, 0.15)
      l:SetWidth(1)
      l:SetHeight(h)
      l:SetPoint("CENTER", UIParent, "CENTER", x, 0)
      l:Show()
      x = x + gridSize
    end
    x = -gridSize
    while x > -limitW do
      local l = GetLine()
      l:SetTexture(1, 1, 1, 0.15)
      l:SetWidth(1)
      l:SetHeight(h)
      l:SetPoint("CENTER", UIParent, "CENTER", x, 0)
      l:Show()
      x = x - gridSize
    end

    local y = gridSize
    while y < limitH do
      local l = GetLine()
      l:SetTexture(1, 1, 1, 0.15)
      l:SetWidth(w)
      l:SetHeight(1)
      l:SetPoint("CENTER", UIParent, "CENTER", 0, y)
      l:Show()
      y = y + gridSize
    end
    y = -gridSize
    while y > -limitH do
      local l = GetLine()
      l:SetTexture(1, 1, 1, 0.15)
      l:SetWidth(w)
      l:SetHeight(1)
      l:SetPoint("CENTER", UIParent, "CENTER", 0, y)
      l:Show()
      y = y - gridSize
    end

    if not grid.label then
      grid.label = grid:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
      grid.label:SetPoint("TOP", UIParent, "CENTER", 0, -20)
      grid.label:SetTextColor(1, 1, 0)
      grid.label:SetText("CENTER (0,0)")
    end
  end

  grid.DrawGrid = DrawGrid
  _DoiteGridFrame = grid
  return grid
end

function DoiteEdit_ToggleGrid()
  local grid = _CreateGridFrame()
  if grid:IsShown() then
    grid:Hide()
  else
    grid.DrawGrid()
    grid:Show()
  end
  return grid:IsShown()
end
_G["DoiteEdit_ToggleGrid"] = DoiteEdit_ToggleGrid

function DoiteEdit_IsGridShown()
  return _DoiteGridFrame and _DoiteGridFrame:IsShown()
end
_G["DoiteEdit_IsGridShown"] = DoiteEdit_IsGridShown

---------------------------------------------------------------
-- Heavy work throttle (was Modules/DoiteEditThrottle.lua)
---------------------------------------------------------------
_G["DoiteUI_Dragging"] = _G["DoiteUI_Dragging"] or false

local _PendingHeavy = false
local _Accum        = 0
local _ThrottleFrame = CreateFrame("Frame", "DoiteEditThrottle")

local function _ImmediateRefresh()
  if DoiteAuras_RefreshList then
    DoiteAuras_RefreshList()
  end
  if DoiteAuras_RefreshIcons then
    DoiteAuras_RefreshIcons()
  end
end

local function _ImmediateEvaluate()
  if DoiteConditions_RequestEvaluate then
    DoiteConditions_RequestEvaluate()
  elseif DoiteConditions and DoiteConditions.EvaluateAll then
    DoiteConditions:EvaluateAll()
  end
end

local function DoiteEdit_QueueHeavy()
  _PendingHeavy = true
end

local function DoiteEdit_FlushHeavy()
  if not _PendingHeavy then
    return
  end
  _PendingHeavy = false
  _Accum = 0

  _ImmediateRefresh()
  _ImmediateEvaluate()
end

_G["DoiteEdit_QueueHeavy"] = DoiteEdit_QueueHeavy
_G["DoiteEdit_FlushHeavy"] = DoiteEdit_FlushHeavy

_ThrottleFrame:SetScript("OnUpdate", function()
  if not _PendingHeavy then
    return
  end
  if _G["DoiteUI_Dragging"] then
    return
  end
  _Accum = _Accum + (arg1 or 0)
  if _Accum >= 0.08 then
    DoiteEdit_FlushHeavy()
  end
end)