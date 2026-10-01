---------------------------------------------------------------
-- DoiteConditionsOverlay.lua
-- Overlay text rendering for DoiteAuras icons.
--
-- Functions in this file:
--   _DA_NumToStr                            - number -> string cache
--   _DA_ResolveFont                         - font pick (override vs global)
--   _FmtRem                                 - remaining-time formatter (h/m/s/tenths)
--   DoiteConditions._UpdateOverlayForFrame  - render remaining time + stacks
--
-- Loaded AFTER DoiteConditions.lua (see DoiteAuras.toc).
-- Uses helper functions exported via _G from DoiteConditions.lua.
---------------------------------------------------------------

local DoiteConditions = _G["DoiteConditions"] or {}
_G["DoiteConditions"] = DoiteConditions

-- Aliases for functions exported from DoiteConditions.lua
local _DA_GetTargetFacts              = _G["DoiteConditions_GetTargetFacts"]
local _PlayerAuraRemainingSeconds     = _G["DoiteConditions_PlayerAuraRemainingSeconds"]
local _DoiteTrackAuraRemainingSeconds = _G["DoiteConditions_DoiteTrackAuraRemainingSeconds"]
local _ResolvePlayerAuraTextOverride  = _G["DoiteConditions_ResolvePlayerAuraTextOverride"]
local _GetCanonicalSpellNameFromData  = _G["DoiteConditions_GetCanonicalSpellNameFromData"]
local _ProcWindowDuration             = _G["DoiteConditions_ProcWindowDuration"]
local _ProcWindowRemaining            = _G["DoiteConditions_ProcWindowRemaining"]
local _GetAuraStacksOnUnit            = _G["DoiteConditions_GetAuraStacksOnUnit"]
local _AbilityCooldownByName          = _G["DoiteConditions_GetAbilityCooldown"]
local _EvaluateItemCoreState          = DoiteConditions._EvaluateItemCoreState

-- Globals used below
local DoitePetAuras    = _G["DoitePetAuras"]

-- ====== Number -> string cache ======
local _DA_NumStrCache = {}
local function _DA_NumToStr(n)
  if not n then
    return ""
  end
  local s = _DA_NumStrCache[n]
  if not s then
    s = tostring(n)
    _DA_NumStrCache[n] = s
  end
  return s
end

-- ====== Font resolution ======
local function _DA_ResolveFont(iconVal, globalVal)
  if iconVal ~= nil then return iconVal end
  return globalVal
end

-- ====== Remaining-time formatting ======
local function _FmtRem(remSec)
  if not remSec or remSec <= 0 then
    return nil
  end

  local MIN = 60
  local HOUR = 3600
  local HOUR_CUTOVER = HOUR - MIN

  if remSec >= HOUR_CUTOVER then
    return (math.floor((remSec / HOUR) * 2 + 0.5) / 2) .. "h"
  elseif remSec >= MIN then
    return (math.floor((remSec / MIN) * 2 + 0.5) / 2) .. "m"
  elseif remSec < 1.6 then
    local t10 = math.floor(remSec * 10)
    local whole = math.floor(t10 / 10)
    local dec = t10 - (whole * 10)
    return whole .. "." .. dec
  else
    return math.floor(remSec)
  end
end

---------------------------------------------------------------
-- DoiteConditions._UpdateOverlayForFrame
-- Central overlay-text updater: remaining time + stacks.
-- Called from ApplyVisuals and DoiteConditions_UpdateTimeText.
---------------------------------------------------------------
function DoiteConditions._UpdateOverlayForFrame(frame, key, dataTbl, slideActive)
  if not frame or not dataTbl then
    return
  end

  -- Ensure a dedicated top layer so text always renders above any glow frames
  if not frame._daTextLayer then
    local tl = CreateFrame("Frame", nil, frame)
    frame._daTextLayer = tl
    tl:SetAllPoints(frame)
  end

  -- Keep this child well above siblings (incl. typical glow frames)
  do
    local baseLevel = frame:GetFrameLevel() or 0
    frame._daTextLayer:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
    frame._daTextLayer:SetFrameLevel(baseLevel + 50)
  end

  -- Lazy-create fontstrings parented to the text layer
  if not frame._daTextRem then
    local fs = frame._daTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    frame._daTextRem = fs
  end
  if not frame._daTextStacks then
    local fs2 = frame._daTextLayer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs2:SetJustifyH("RIGHT")
    fs2:SetJustifyV("BOTTOM")
    frame._daTextStacks = fs2
  end

  -- === Font resolution ===
  local fdb = DoiteAurasDB or {}
  local fontVer = _G["DoiteAuras_FontVersion"] or 0

  local w = frame:GetWidth() or 36
  local wInt = math.floor(w)
  local sizeChanged = (frame._daFontLastWidth ~= wInt)

  if frame._daFontVersion ~= fontVer or sizeChanged then
    frame._daFontVersion   = fontVer
    frame._daFontLastWidth = wInt

    local remUserPath   = _DA_ResolveFont(dataTbl.timerFontPath,   fdb.timerFontPath)
    local stackUserPath = _DA_ResolveFont(dataTbl.stackFontPath,   fdb.stackFontPath)
    local remUserFlagsRaw   = _DA_ResolveFont(dataTbl.timerFontFlags, fdb.timerFontFlags)
    local stackUserFlagsRaw = _DA_ResolveFont(dataTbl.stackFontFlags, fdb.stackFontFlags)
    local remUserSize    = tonumber(_DA_ResolveFont(dataTbl.timerFontSize, fdb.timerFontSize))
    local stackUserSize  = tonumber(_DA_ResolveFont(dataTbl.stackFontSize, fdb.stackFontSize))

    local remUserFlags   = (remUserFlagsRaw   ~= nil) and remUserFlagsRaw   or "OUTLINE"
    local stackUserFlags = (stackUserFlagsRaw ~= nil) and stackUserFlagsRaw or "OUTLINE"

    local remPath = (remUserPath and remUserPath ~= "") and remUserPath
                    or (GameFontHighlight:GetFont() or "Fonts\\FRIZQT__.TTF")
    local stackPath = (stackUserPath and stackUserPath ~= "") and stackUserPath
                    or (GameFontNormalSmall:GetFont() or "Fonts\\FRIZQT__.TTF")

    local remSize   = remUserSize   or 15
    local stackSize = stackUserSize or 10

    frame._daRemSize      = remSize
    frame._daStackSize    = stackSize
    frame._daRemPath      = remPath
    frame._daStackPath    = stackPath
    frame._daRemFlags     = remUserFlags
    frame._daStackFlags   = stackUserFlags
    frame._daRemUserSet   = (remUserSize ~= nil)
    frame._daStackUserSet = (stackUserSize ~= nil)

    frame._daTextRem:SetFont(remPath, remSize, remUserFlags)
    frame._daTextStacks:SetFont(stackPath, stackSize, stackUserFlags)
    frame._daCurrentStackFontSize = nil
  end

  -- Anchor (cached once)
  if not frame._daOverlayAnchored then
    frame._daOverlayAnchored = true
    frame._daTextRem:ClearAllPoints()
    frame._daTextRem:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame._daTextStacks:ClearAllPoints()
    frame._daTextStacks:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
  end

  -- Defaults hidden
  frame._daTextRem:Hide()
  frame._daTextStacks:Hide()

  frame._daSortRem = nil
  -- Reset every call: _daRemIsProc is only assigned inside the Ability
  -- branch. Without this, a frame reused from the pool for a different
  -- icon type would keep a stale 'true' and tint non-proc timer text green.
  frame._daRemIsProc = false

  -- ========== Remaining Time ==========
  local wantRem = false
  local remText = nil
  local itemState = nil

  local function _ShowAbilityTime(ca, rem, dur, slide)
    if not rem or rem <= 0 then
      return false
    end
    dur = dur or 0

    local TH = DoiteConditions._GCD_THRESHOLD

    if ca.mode == "oncd" or ca.mode == "usableoncd" or ca.mode == "nocdoncd" then
      return (dur > TH)
    end

    if (ca.mode == "usable" or ca.mode == "notcd") and ca.slider == true then
      if slide then
        return true
      end
      local sliderTime = tonumber(ca.sliderTime) or 0
      if sliderTime > 0 then
        return rem <= sliderTime and (dur > TH)
      end
      return (dur > TH)
    end

    local maxWindow = math.min(3.0, (dur or 0) * 0.6)
    return (dur > TH) and (rem <= maxWindow)
  end

  if dataTbl then
    ----------------------------------------------------------------
    -- Ability remaining-time text
    ----------------------------------------------------------------
    if dataTbl.type == "Ability"
        and dataTbl.conditions
        and dataTbl.conditions.ability then

      local ca = dataTbl.conditions.ability

      local spellName = _GetCanonicalSpellNameFromData(dataTbl)
      local remCD, durCD = _AbilityCooldownByName(spellName)
      local remShown, durShown = nil, nil
      local remIsProc = false

      -- Both the real cooldown timer and the proc-window timer live under
      -- the "Icon text: Time remaining" flag. Without this gate a proc
      -- (Overpower / Revenge / Riposte / etc.) would show its timer even
      -- when the user never enabled text on that icon.
      if ca.textTimeRemaining == true then
        if remCD and remCD > 0 and _ShowAbilityTime(ca, remCD, durCD, slideActive) then
          remShown = remCD
          durShown = durCD
        end

        if (not remShown) and spellName
            and (ca.mode == "usable" or ca.mode == "notcd" or ca.mode == "nocdoncd") then
          local procDur = _ProcWindowDuration(spellName)
          if procDur then
            local realCd = false
            if remCD and remCD > 0 and durCD and durCD > 1.6 then
              realCd = true
            end

            if not realCd then
              local remProc = _ProcWindowRemaining(spellName)
              if remProc and remProc > 0 then
                remShown = remProc
                durShown = procDur
                remIsProc = true
              end
            end
          end
        end
      end

      if remShown and remShown > 0 then
        remText = _FmtRem(remShown)
        wantRem = (remText ~= nil)
        frame._daSortRem = remShown
        frame._daRemIsProc = remIsProc and true or false
      else
        frame._daRemIsProc = false
      end

    ----------------------------------------------------------------
    -- Item remaining-time text
    ----------------------------------------------------------------
    elseif (dataTbl.type == "Item")
        and dataTbl.conditions
        and dataTbl.conditions.item then

      local ci = dataTbl.conditions.item

      if ci.textTimeRemaining == true then
        local ovName, ovSpellId, ovUseSpellId = _ResolvePlayerAuraTextOverride(ci.remOverride, nil, 0, false)
        if ci.remOverride and (ovName or (ovUseSpellId and ovSpellId and ovSpellId > 0)) then
          local remOverride = _PlayerAuraRemainingSeconds(ovName, ovSpellId, ovUseSpellId)
          if remOverride and remOverride > 0 then
            remText = _FmtRem(remOverride)
            wantRem = (remText ~= nil)
            frame._daSortRem = remOverride
          end
        end

        if not wantRem then
          itemState = _EvaluateItemCoreState(dataTbl, ci)

          if (ci.mode == "notcd" or ci.mode == "both")
              and (dataTbl.displayName == "---EQUIPPED WEAPON SLOTS---")
              and (ci.inventorySlot == "MAINHAND" or ci.inventorySlot == "OFFHAND") then

            local remTE = itemState and itemState.teRem or 0
            if remTE and remTE > 0 then
              remText = _FmtRem(remTE)
              wantRem = (remText ~= nil)
              frame._daSortRem = remTE
            end

          else
            local remItem = itemState and itemState.rem or nil
            local durItem = itemState and itemState.dur or 0

            if remItem and remItem > 0 and durItem and durItem > 1.5 then
              remText = _FmtRem(remItem)
              wantRem = (remText ~= nil)
              frame._daSortRem = remItem
            end
          end
        end
      end

    ----------------------------------------------------------------
    -- Aura remaining-time text
    ----------------------------------------------------------------
    elseif (dataTbl.type == "Buff" or dataTbl.type == "Debuff")
        and dataTbl.conditions
        and dataTbl.conditions.aura then

      local ca = dataTbl.conditions.aura

      if ca.textTimeRemaining == true then
        local auraName = dataTbl.displayName or dataTbl.name
        local useSpellIdOnly = (dataTbl.Addedviaspellid == true)
        local auraSpellId = tonumber(dataTbl.spellid) or 0
        auraName, auraSpellId, useSpellIdOnly = _ResolvePlayerAuraTextOverride(ca.remOverride, auraName, auraSpellId, useSpellIdOnly)

        local allowHelp = (ca.targetHelp == true)
        local allowHarm = (ca.targetHarm == true)
        local allowSelf = (ca.targetSelf == true)

        if (not allowHelp) and (not allowHarm) and (not allowSelf) then
          allowSelf = true
        end

        local targetSelf = true
        if not allowSelf and (allowHelp or allowHarm) then
          local tf = _DA_GetTargetFacts()
          if tf and tf.exists then
            local isFriend = tf.isFriend
            local canAttack = tf.canAttack

            if (allowHelp and isFriend) or (allowHarm and canAttack and not isFriend) then
              targetSelf = false
            end
          end
        end

        local remAura = nil

        if ca.trackpet == true and DoitePetAuras and DoitePetAuras.GetAuraRemainingSeconds then
          remAura = DoitePetAuras.GetAuraRemainingSeconds(auraName, auraSpellId, useSpellIdOnly)
        elseif targetSelf then
          remAura = _PlayerAuraRemainingSeconds(auraName, auraSpellId, useSpellIdOnly)
        else
          remAura = _DoiteTrackAuraRemainingSeconds(useSpellIdOnly and auraSpellId or auraName, "target", useSpellIdOnly)
        end

        if remAura and remAura > 0 then
          remText = _FmtRem(remAura)
          wantRem = (remText ~= nil)
          frame._daSortRem = remAura
        end
      end

    ----------------------------------------------------------------
    -- Custom remaining-time text
    ----------------------------------------------------------------
    elseif dataTbl.type == "Custom" then
      local remCustom = tonumber(dataTbl._daCustomRemaining)
      if remCustom and remCustom > 0 then
        remText = _FmtRem(remCustom)
        wantRem = (remText ~= nil)
        frame._daSortRem = remCustom
      end
    end
  end

  if wantRem and remText then
    if remText ~= frame._daLastRemText then
      frame._daLastRemText = remText
      frame._daTextRem:SetText(remText)
    end
    local remIsProcNow = (frame._daRemIsProc == true)
    if remIsProcNow ~= frame._daLastRemProcState then
      frame._daLastRemProcState = remIsProcNow
      if remIsProcNow then
        frame._daTextRem:SetTextColor(0.2, 1, 0.2, 1)
      else
        frame._daTextRem:SetTextColor(1, 1, 1, 1)
      end
    end
    frame._daTextRem:Show()
  end

  -- ========== Stack Counter (auras only) ==========
  if dataTbl
      and (dataTbl.type == "Buff" or dataTbl.type == "Debuff")
      and dataTbl.conditions
      and dataTbl.conditions.aura then

    local ca = dataTbl.conditions.aura
    if ca.textStackCounter == true then
      local auraName = dataTbl.displayName or dataTbl.name
      local useSpellIdOnly = (dataTbl.Addedviaspellid == true)
      local auraSpellId = tonumber(dataTbl.spellid) or 0
      local wantDebuff = (dataTbl.type == "Debuff")
      auraName, auraSpellId, useSpellIdOnly = _ResolvePlayerAuraTextOverride(ca.stackOverride, auraName, auraSpellId, useSpellIdOnly)

      local unitToCheck = nil
      local allowHelp = (ca.targetHelp == true)
      local allowHarm = (ca.targetHarm == true)
      local allowSelf = (ca.targetSelf == true)

      if (not allowHelp) and (not allowHarm) and (not allowSelf) then
        allowSelf = true
      end

      if allowSelf then
        unitToCheck = "player"
      elseif (allowHelp or allowHarm) then
        local tf = _DA_GetTargetFacts()
        if tf.exists then
          if allowHelp and tf.isFriend then
            unitToCheck = "target"
          elseif allowHarm and tf.canAttack and (not tf.isFriend) then
            unitToCheck = "target"
          end
        end
      end

      if ca.trackpet == true then
        unitToCheck = "pet"
      end
      if unitToCheck then
        local cnt = _GetAuraStacksOnUnit(unitToCheck, auraName, wantDebuff, auraSpellId, useSpellIdOnly)
        if cnt and cnt >= 1 then
          local s = _DA_NumToStr(cnt)
          if s ~= frame._daLastStacksText then
            frame._daLastStacksText = s
            frame._daTextStacks:SetText(s)
            frame._daTextStacks:SetTextColor(1, 1, 1, 1)
          end

          local sizeToUse = frame._daStackSize
          if sizeToUse and sizeToUse ~= frame._daCurrentStackFontSize then
            frame._daCurrentStackFontSize = sizeToUse
            frame._daTextStacks:SetFont(
              frame._daStackPath or "Fonts\\FRIZQT__.TTF",
              sizeToUse,
              frame._daStackFlags or ""
            )
          end

          frame._daTextStacks:Show()
        end
      end
    end
  end

  -- ========== Stack Counter (custom) ==========
  if dataTbl and dataTbl.type == "Custom" then
    local cnt = tonumber(dataTbl._daCustomStacks)
    if cnt then
      local rounded = math.floor(cnt + 0.5)
      local s = _DA_NumToStr(rounded)
      if s ~= frame._daLastStacksText then
        frame._daLastStacksText = s
        frame._daTextStacks:SetText(s)
        frame._daTextStacks:SetTextColor(1, 1, 1, 1)
      end

      local sizeToUse = frame._daStackSize
      if sizeToUse and sizeToUse ~= frame._daCurrentStackFontSize then
        frame._daCurrentStackFontSize = sizeToUse
        frame._daTextStacks:SetFont(
          frame._daStackPath or "Fonts\\FRIZQT__.TTF",
          sizeToUse,
          frame._daStackFlags or ""
        )
      end

      frame._daTextStacks:Show()
    end
  end

  -- ========== Stack Counter (items: total amount) ==========
  if dataTbl
      and dataTbl.type == "Item"
      and dataTbl.conditions
      and dataTbl.conditions.item then

    local ci = dataTbl.conditions.item
    if ci.textStackCounter == true then
      local state = itemState
      if not state then
        state = _EvaluateItemCoreState(dataTbl, ci)
      end

      local cnt = state and state.effectiveCount or nil

      if (dataTbl.displayName == "---EQUIPPED WEAPON SLOTS---")
          and (ci.inventorySlot == "MAINHAND" or ci.inventorySlot == "OFFHAND") then

        if not cnt then
          cnt = 0
        end
        if cnt < 0 then
          cnt = 0
        end

        local s = _DA_NumToStr(cnt)
        if s ~= frame._daLastStacksText then
          frame._daLastStacksText = s
          frame._daTextStacks:SetText(s)
          frame._daTextStacks:SetTextColor(1, 1, 1, 1)
        end

        local sizeToUse = frame._daStackSize
        if sizeToUse and sizeToUse ~= frame._daCurrentStackFontSize then
          frame._daCurrentStackFontSize = sizeToUse
          frame._daTextStacks:SetFont(
            frame._daStackPath or "Fonts\\FRIZQT__.TTF",
            sizeToUse,
            frame._daStackFlags or ""
          )
        end

        frame._daTextStacks:Show()

      elseif cnt and cnt >= 1 then
        local s = _DA_NumToStr(cnt)
        if s ~= frame._daLastStacksText then
          frame._daLastStacksText = s
          frame._daTextStacks:SetText(s)
          frame._daTextStacks:SetTextColor(1, 1, 1, 1)
        end

        local sizeToUse = frame._daStackSize
        if sizeToUse and sizeToUse ~= frame._daCurrentStackFontSize then
          frame._daCurrentStackFontSize = sizeToUse
          frame._daTextStacks:SetFont(
            frame._daStackPath or "Fonts\\FRIZQT__.TTF",
            sizeToUse,
            frame._daStackFlags or ""
          )
        end

        frame._daTextStacks:Show()
      end
    end
  end
end