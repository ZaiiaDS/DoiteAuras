---------------------------------------------------------------
-- DoitePetAuras.lua
-- Lightweight pet aura cache/helpers for trackpet aura mode
-- Please respect license note: Ask permission
-- WoW 1.12 | Lua 5.0
---------------------------------------------------------------

local DoitePetAuras = {
  buffs = {},
  debuffs = {},
  buffIds = {},
  debuffIds = {},
  buffNameToId = {},
  debuffNameToId = {},
  buffExpiresAt = {},
  debuffExpiresAt = {},
  spellDurationCache = {},
  petGuid = nil,
  enabled = false,
  isSupportedClass = false,
  classChecked = false,
  lastUsageScanAt = 0,
  initialized = false,
  hasTrackPetOverlayTicker = false
}

_G["DoitePetAuras"] = DoitePetAuras

local _ResetForPetChange

local function _ClearMap(t)
  for k in pairs(t) do
    t[k] = nil
  end
end

local function _NormalizeDurationSeconds(duration)
  if not duration or duration <= 0 then
    return nil
  end
  if duration > 100 then
    return duration / 1000
  end
  return duration
end

local _petSpellNameCache = {}

local function _GetSpellNameById(spellId)
  local sid = tonumber(spellId) or 0
  if sid <= 0 then
    return nil
  end

  local cached = _petSpellNameCache[sid]
  if cached ~= nil then
    return cached or nil
  end

  local name = nil
  if GetSpellNameAndRankForId then
    local ok, n = pcall(GetSpellNameAndRankForId, sid)
    if ok and type(n) == "string" and n ~= "" then
      name = n
    end
  end

  if not name and GetSpellRecField then
    local ok2, recName = pcall(GetSpellRecField, sid, "name")
    if ok2 and type(recName) == "string" and recName ~= "" then
      name = recName
    end
  end

  _petSpellNameCache[sid] = name or false
  return name
end

local function _IsSupportedClass()
  local _, cls = UnitClass("player")
  cls = cls and string.upper(cls) or ""
  return (cls == "WARLOCK" or cls == "HUNTER") and true or false
end

local function _AnyTrackPetInAuraConditions(list)
  if type(list) ~= "table" then
    return false
  end

  -- auraConditions is a numeric array; a numeric for skips the generic
  -- next() dispatch that pairs() does on every iteration. Called from
  -- _ScanTrackPetUsage, which runs up to once per second per active
  -- trackpet icon, so the cheap path is worth it.
  local i, cond
  local n = table.getn(list)
  for i = 1, n do
    cond = list[i]
    if type(cond) == "table" and cond.trackpet == true then
      return true
    end
  end

  return false
end

local function _AnyTrackPetInIconData(data)
  if type(data) ~= "table" then
    return false, false
  end

  local c = data.conditions
  if type(c) ~= "table" then
    return false, false
  end

  local hasTrackPet = false
  local needsOverlayTicker = false

  if type(c.aura) == "table" and c.aura.trackpet == true then
    hasTrackPet = true
    if c.aura.textTimeRemaining == true or c.aura.textStackCounter == true then
      needsOverlayTicker = true
    end
  end

  if _AnyTrackPetInAuraConditions(c.ability and c.ability.auraConditions) then
    hasTrackPet = true
  end
  if _AnyTrackPetInAuraConditions(c.item and c.item.auraConditions) then
    hasTrackPet = true
  end
  if _AnyTrackPetInAuraConditions(c.aura and c.aura.auraConditions) then
    hasTrackPet = true
  end

  return hasTrackPet, needsOverlayTicker
end

local function _ScanTrackPetUsage()
  local hasTrackPet = false
  local needsOverlayTicker = false

  if DoiteAurasDB and DoiteAurasDB.spells then
    local _, data
    for _, data in pairs(DoiteAurasDB.spells) do
      local hasTP, needTicker = _AnyTrackPetInIconData(data)
      if hasTP then
        hasTrackPet = true
      end
      if needTicker then
        needsOverlayTicker = true
      end
      if hasTrackPet and needsOverlayTicker then
        return true, true
      end
    end
  end

  if DoiteDB and DoiteDB.icons then
    local _, data
    for _, data in pairs(DoiteDB.icons) do
      local hasTP, needTicker = _AnyTrackPetInIconData(data)
      if hasTP then
        hasTrackPet = true
      end
      if needTicker then
        needsOverlayTicker = true
      end
      if hasTrackPet and needsOverlayTicker then
        return true, true
      end
    end
  end

  return hasTrackPet, needsOverlayTicker
end

local function _SetEnabledState(enabled)
  local want = enabled and true or false
  local wasEnabled = DoitePetAuras.enabled == true
  if wasEnabled == want then
    return
  end

  DoitePetAuras.enabled = want
  if want then
    if _ResetForPetChange then
      _ResetForPetChange()
    end
  else
    DoitePetAuras.petGuid = nil
    _ClearMap(DoitePetAuras.buffs)
    _ClearMap(DoitePetAuras.debuffs)
    _ClearMap(DoitePetAuras.buffIds)
    _ClearMap(DoitePetAuras.debuffIds)
    _ClearMap(DoitePetAuras.buffNameToId)
    _ClearMap(DoitePetAuras.debuffNameToId)
    _ClearMap(DoitePetAuras.buffExpiresAt)
    _ClearMap(DoitePetAuras.debuffExpiresAt)
    DoitePetAuras.hasTrackPetOverlayTicker = false
  end
end

local function _RefreshEnabledState(force)
  if DoitePetAuras.classChecked ~= true then
    DoitePetAuras.isSupportedClass = _IsSupportedClass()
    DoitePetAuras.classChecked = true
  end

  if DoitePetAuras.isSupportedClass ~= true then
    _SetEnabledState(false)
    return false
  end

  local now = GetTime and GetTime() or 0
  if force ~= true and DoitePetAuras.lastUsageScanAt and (now - DoitePetAuras.lastUsageScanAt) < 1.0 then
    return DoitePetAuras.enabled
  end

  DoitePetAuras.lastUsageScanAt = now
  local hasTrackPet, needsOverlayTicker = _ScanTrackPetUsage()
  DoitePetAuras.hasTrackPetOverlayTicker = needsOverlayTicker and true or false
  _SetEnabledState(hasTrackPet)
  return DoitePetAuras.enabled
end

local function _GetDurationSecondsBySpellId(spellId)
  local sid = tonumber(spellId) or 0
  if sid <= 0 then
    return nil
  end

  local cached = DoitePetAuras.spellDurationCache[sid]
  if cached ~= nil then
    return cached or nil
  end

  local duration = nil
  if GetSpellDuration then
    duration = _NormalizeDurationSeconds(GetSpellDuration(sid))
  end

  DoitePetAuras.spellDurationCache[sid] = duration or false
  return duration
end

local function _UpdateExpiresBySpellId(spellId, stacks, wantDebuff, treatAsFreshApply)
  local sid = tonumber(spellId) or 0
  if sid <= 0 then
    return
  end

  local expiresMap = wantDebuff and DoitePetAuras.debuffExpiresAt or DoitePetAuras.buffExpiresAt

  if not stacks or stacks <= 0 then
    expiresMap[sid] = nil
    return
  end

  local duration = _GetDurationSecondsBySpellId(sid)
  if not duration then
    expiresMap[sid] = nil
    return
  end

  local now = GetTime and GetTime() or 0
  local current = expiresMap[sid]
  if treatAsFreshApply == true or not current or current <= now then
    expiresMap[sid] = now + duration
  end
end

local function _GetRemainingFromExpiresMap(expiresMap, spellId)
  local sid = tonumber(spellId) or 0
  if sid <= 0 then
    return nil
  end

  local expiresAt = expiresMap[sid]
  if not expiresAt then
    return nil
  end

  local now = GetTime and GetTime() or 0
  local rem = expiresAt - now
  if rem <= 0 then
    expiresMap[sid] = nil
    return nil
  end

  return rem
end

local function _ScanPetAuras()
  _ClearMap(DoitePetAuras.buffs)
  _ClearMap(DoitePetAuras.debuffs)
  _ClearMap(DoitePetAuras.buffIds)
  _ClearMap(DoitePetAuras.debuffIds)
  _ClearMap(DoitePetAuras.buffNameToId)
  _ClearMap(DoitePetAuras.debuffNameToId)

  if not UnitExists("pet") then
    _ClearMap(DoitePetAuras.buffExpiresAt)
    _ClearMap(DoitePetAuras.debuffExpiresAt)
    return
  end

  local i = 1
  while i <= 32 do
    local tex, stacks, spellId = UnitBuff("pet", i)
    if not tex then
      break
    end

    if spellId then
      local sid = tonumber(spellId) or 0
      local stackVal = stacks or 1
      DoitePetAuras.buffIds[sid] = stackVal
      _UpdateExpiresBySpellId(sid, stackVal, false, false)
      local name = _GetSpellNameById(sid)
      if name then
        DoitePetAuras.buffs[name] = stackVal
        DoitePetAuras.buffNameToId[name] = sid
      end
    end

    i = i + 1
  end

  i = 1
  while i <= 32 do
    local tex, stacks, _, spellId = UnitDebuff("pet", i)
    if not tex then
      break
    end

    if spellId then
      local sid = tonumber(spellId) or 0
      local stackVal = stacks or 1
      DoitePetAuras.debuffIds[sid] = stackVal
      _UpdateExpiresBySpellId(sid, stackVal, true, false)
      local name = _GetSpellNameById(sid)
      if name then
        DoitePetAuras.debuffs[name] = stackVal
        DoitePetAuras.debuffNameToId[name] = sid
      end
    end

    i = i + 1
  end
end

local function _SetAuraBySpellId(spellId, stacks, wantDebuff)
  local sid = tonumber(spellId) or 0
  if sid <= 0 then
    return
  end

  local byId = wantDebuff and DoitePetAuras.debuffIds or DoitePetAuras.buffIds
  local byName = wantDebuff and DoitePetAuras.debuffs or DoitePetAuras.buffs
  local byNameToId = wantDebuff and DoitePetAuras.debuffNameToId or DoitePetAuras.buffNameToId

  if stacks and stacks > 0 then
    byId[sid] = stacks
  else
    byId[sid] = nil
  end

  local name = _GetSpellNameById(sid)
  if name then
    if stacks and stacks > 0 then
      byName[name] = stacks
      byNameToId[name] = sid
    else
      byName[name] = nil
      byNameToId[name] = nil
    end
  end

  _UpdateExpiresBySpellId(sid, stacks, wantDebuff, true)
end

_ResetForPetChange = function()
  DoitePetAuras.petGuid = GetUnitGUID and GetUnitGUID("pet") or nil
  _ClearMap(DoitePetAuras.buffExpiresAt)
  _ClearMap(DoitePetAuras.debuffExpiresAt)
  _ScanPetAuras()
end

local _lastRefreshAt = 0

-- Public API: force a full re-scan of pet auras, bypassing the internal
-- throttle. Kept for external modules / slash commands. In-addon updates
-- go through _ResetForPetChange + _SetAuraBySpellId (event path).
function DoitePetAuras.Refresh()
  if not _RefreshEnabledState(true) then
    return
  end

  local now = GetTime and GetTime() or 0
  if (now - _lastRefreshAt) < 0.15 then
    return
  end
  _lastRefreshAt = now

  DoitePetAuras.petGuid = GetUnitGUID and GetUnitGUID("pet") or nil
  _ScanPetAuras()
end

function DoitePetAuras.CanTrack()
  if not _RefreshEnabledState(false) then
    return false
  end
  return UnitExists("pet") and true or false
end

-- Public API: true if the current target is the player's own pet.
-- Exposed for external condition checks. In-addon condition evaluation
-- currently uses targetHelp/targetHarm flags instead, so this is not
-- consumed by DoiteConditions today.
function DoitePetAuras.TargetIsPet()
  if not DoitePetAuras.CanTrack() then
    return false
  end
  return UnitExists("target") and UnitIsUnit("target", "pet") and true or false
end

function DoitePetAuras.HasAura(auraName, auraSpellId, useSpellIdOnly, wantBuff, wantDebuff)
  if not DoitePetAuras.CanTrack() then
    return false
  end

  if useSpellIdOnly == true then
    local sid = tonumber(auraSpellId) or 0
    if sid <= 0 then
      return false
    end
    if wantBuff and DoitePetAuras.buffIds[sid] then
      return true
    end
    if wantDebuff and DoitePetAuras.debuffIds[sid] then
      return true
    end
    return false
  end

  if not auraName or auraName == "" then
    return false
  end

  if wantBuff and DoitePetAuras.buffs[auraName] then
    return true
  end
  if wantDebuff and DoitePetAuras.debuffs[auraName] then
    return true
  end

  return false
end

function DoitePetAuras.GetStacks(auraName, wantDebuff, auraSpellId, useSpellIdOnly)
  if not DoitePetAuras.CanTrack() then
    return nil
  end

  if useSpellIdOnly == true then
    local sid = tonumber(auraSpellId) or 0
    if sid <= 0 then
      return nil
    end
    if wantDebuff then
      return DoitePetAuras.debuffIds[sid]
    end
    return DoitePetAuras.buffIds[sid]
  end

  if not auraName or auraName == "" then
    return nil
  end

  if wantDebuff then
    return DoitePetAuras.debuffs[auraName]
  end
  return DoitePetAuras.buffs[auraName]
end

function DoitePetAuras.GetAuraRemainingSeconds(auraName, auraSpellId, useSpellIdOnly)
  if not DoitePetAuras.CanTrack() then
    return nil
  end

  if useSpellIdOnly == true then
    local sid = tonumber(auraSpellId) or 0
    if sid <= 0 then
      return nil
    end

    local remBuff = _GetRemainingFromExpiresMap(DoitePetAuras.buffExpiresAt, sid)
    if remBuff then
      return remBuff
    end

    return _GetRemainingFromExpiresMap(DoitePetAuras.debuffExpiresAt, sid)
  end

  if not auraName or auraName == "" then
    return nil
  end

  local buffSid = DoitePetAuras.buffNameToId[auraName]
  if buffSid then
    local remBuffByName = _GetRemainingFromExpiresMap(DoitePetAuras.buffExpiresAt, buffSid)
    if remBuffByName then
      return remBuffByName
    end
  end

  local debuffSid = DoitePetAuras.debuffNameToId[auraName]
  if debuffSid then
    local remDebuffByName = _GetRemainingFromExpiresMap(DoitePetAuras.debuffExpiresAt, debuffSid)
    if remDebuffByName then
      return remDebuffByName
    end
  end

  return nil
end

local f = CreateFrame("Frame", "DoitePetAurasEvents")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UNIT_PET_GUID")
f:RegisterEvent("UNIT_PET")
f:RegisterEvent("BUFF_ADDED_OTHER")
f:RegisterEvent("DEBUFF_ADDED_OTHER")
f:RegisterEvent("BUFF_REMOVED_OTHER")
f:RegisterEvent("DEBUFF_REMOVED_OTHER")
f:RegisterEvent("UNIT_DIED")
f:RegisterEvent("PLAYER_DEAD")

f:SetScript("OnEvent", function()
  local evt = event
  -- arg1 carries "player" for UNIT_PET but a GUID for the *OTHER events.
  -- One variable serves both roles.
  local unitOrGuid = arg1
  local spellId = arg3
  local stackCount = tonumber(arg4) or 0
  local needsEval = false

  if evt == "PLAYER_ENTERING_WORLD" then
    DoitePetAuras.isSupportedClass = _IsSupportedClass()
    DoitePetAuras.classChecked = true
    DoitePetAuras.lastUsageScanAt = 0
    if not _RefreshEnabledState(true) then
      return
    end

    _ResetForPetChange()
    needsEval = true
  elseif not _RefreshEnabledState(false) then
    return
  elseif evt == "UNIT_PET_GUID" then
    local isPlayer = arg2
    if isPlayer == 1 and unitOrGuid then
      local currentPetGuid = GetUnitGUID and GetUnitGUID("pet") or nil
      if currentPetGuid ~= DoitePetAuras.petGuid then
        _ResetForPetChange()
        needsEval = true
      end
    end
  elseif evt == "UNIT_PET" then
    if unitOrGuid == "player" then
      _ResetForPetChange()
      needsEval = true
    end
  elseif evt == "BUFF_ADDED_OTHER" or evt == "DEBUFF_ADDED_OTHER" then
    if DoitePetAuras.petGuid and unitOrGuid and unitOrGuid == DoitePetAuras.petGuid then
      if stackCount <= 0 then
        stackCount = 1
      end
      _SetAuraBySpellId(spellId, stackCount, evt == "DEBUFF_ADDED_OTHER")
      needsEval = true
    end
  elseif evt == "BUFF_REMOVED_OTHER" or evt == "DEBUFF_REMOVED_OTHER" then
    if DoitePetAuras.petGuid and unitOrGuid and unitOrGuid == DoitePetAuras.petGuid then
      _SetAuraBySpellId(spellId, stackCount, evt == "DEBUFF_REMOVED_OTHER")
      needsEval = true
    end
  elseif evt == "UNIT_DIED" then
    if DoitePetAuras.petGuid and unitOrGuid and unitOrGuid == DoitePetAuras.petGuid then
      DoitePetAuras.petGuid = nil
      _ClearMap(DoitePetAuras.buffs)
      _ClearMap(DoitePetAuras.debuffs)
      _ClearMap(DoitePetAuras.buffIds)
      _ClearMap(DoitePetAuras.debuffIds)
      _ClearMap(DoitePetAuras.buffNameToId)
      _ClearMap(DoitePetAuras.debuffNameToId)
      _ClearMap(DoitePetAuras.buffExpiresAt)
      _ClearMap(DoitePetAuras.debuffExpiresAt)
      needsEval = true
    end
  elseif evt == "PLAYER_DEAD" then
    DoitePetAuras.petGuid = nil
    _ClearMap(DoitePetAuras.buffs)
    _ClearMap(DoitePetAuras.debuffs)
    _ClearMap(DoitePetAuras.buffIds)
    _ClearMap(DoitePetAuras.debuffIds)
    _ClearMap(DoitePetAuras.buffNameToId)
    _ClearMap(DoitePetAuras.debuffNameToId)
    _ClearMap(DoitePetAuras.buffExpiresAt)
    _ClearMap(DoitePetAuras.debuffExpiresAt)
    needsEval = true
  end

  if needsEval and DoiteConditions and DoiteConditions.EvaluateAll then
    DoiteConditions:EvaluateAll()
  end
end)

local _smoothTextAccum = 0

f:SetScript("OnUpdate", function()
  if DoitePetAuras.enabled ~= true then
    _smoothTextAccum = 0
    return
  end

  if not DoitePetAuras.petGuid or not UnitExists or not UnitExists("pet") then
    _smoothTextAccum = 0
    return
  end

  if DoitePetAuras.hasTrackPetOverlayTicker ~= true then
    _smoothTextAccum = 0
    return
  end

  if (not next(DoitePetAuras.buffIds)) and (not next(DoitePetAuras.debuffIds)) then
    _smoothTextAccum = 0
    return
  end

  _smoothTextAccum = _smoothTextAccum + (arg1 or 0)
  if _smoothTextAccum < 0.25 then
    return
  end
  _smoothTextAccum = 0

  if DoiteConditions_UpdateTimeText then
    DoiteConditions_UpdateTimeText()
  end
end)

DoitePetAuras.initialized = true
DoitePetAuras.isSupportedClass = _IsSupportedClass()
DoitePetAuras.classChecked = true
DoitePetAuras.lastUsageScanAt = 0
if _RefreshEnabledState(true) then
  _ResetForPetChange()
end
