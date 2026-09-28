---------------------------------------------------------------
-- DoiteConditionsSpell.lua
-- Spellbook index + cooldown + usability helpers.
-- Extracted from DoiteConditions.lua (Phase 3 of the split).
--
-- Functions in this file:
--   _GetSpellIndexByName         - spellName -> spellbook index (cached)
--   _AbilityRemainingSeconds     - remaining CD for a spellbook index
--   _AbilityRemainingByName      - same, but resolves index by name
--   _AbilityCooldownByName       - (rem, dur) for a spell (cached last dur)
--   _AbilityFullDurationByName   - full base CD, prefers live -> NP -> DBC
--   _IsSpellOnCooldown           - true if on real CD (GCD excluded)
--   _SafeSpellUsable             - IsSpellUsable wrapper with fallbacks
--
-- Loaded BEFORE DoiteConditions.lua.
--
-- Public globals:
--   _G["DoiteConditions_SpellIndexCache"]                 (table, cleared on SPELLS_CHANGED)
--   _G["DoiteConditions_SpellBookTypeCache"]              (table)
--   _G["DoiteConditions_GetSpellIndexByName"]
--   _G["DoiteConditions_AbilityRemainingSeconds"]
--   _G["DoiteConditions_AbilityRemainingByName"]
--   _G["DoiteConditions_GetAbilityCooldown"]
--   _G["DoiteConditions_GetAbilityFullDuration"]
--   _G["DoiteConditions_IsSpellOnCooldown"]
--   _G["DoiteConditions_SafeSpellUsable"]
--   DoiteConditions._daAbilityLastDurByName               (table)
--   DoiteConditions._daLastRecoveryField                  (string, debug)
---------------------------------------------------------------

local DoiteConditions = _G["DoiteConditions"] or {}
_G["DoiteConditions"] = DoiteConditions

-- Ensure GCD threshold exists even if DoiteConditions.lua hasn't run yet.
-- DoiteConditions.lua sets the same value later; idempotent.
if not DoiteConditions._GCD_THRESHOLD then
  DoiteConditions._GCD_THRESHOLD = 1.6
end

-- =================================================================
-- Spell index cache
-- =================================================================
local SpellIndexCache = {}
_G.DoiteConditions_SpellIndexCache = SpellIndexCache
_G.DoiteConditions_SpellBookTypeCache = _G.DoiteConditions_SpellBookTypeCache or {}

local function _GetSpellIndexByName(spellName)
  if not spellName then
    return nil
  end

  local cached = SpellIndexCache[spellName]
  if cached ~= nil then
    return (cached ~= false) and cached or nil
  end

  -- Nampower fast path - GetSpellSlotTypeIdForName(spellName)
  if GetSpellSlotTypeIdForName then
    local slot, bookType = GetSpellSlotTypeIdForName(spellName)
    if slot and slot > 0 and (bookType == "spell" or bookType == "pet") then
      SpellIndexCache[spellName] = slot
      _G.DoiteConditions_SpellBookTypeCache[spellName] = (bookType == "pet") and BOOKTYPE_PET or BOOKTYPE_SPELL
      return slot
    end
  end

  -- Scan fallback
  local i = 1
  while i <= 200 do
    local s = GetSpellName(i, BOOKTYPE_SPELL)
    if not s then
      break
    end
    if s == spellName then
      SpellIndexCache[spellName] = i
      _G.DoiteConditions_SpellBookTypeCache[spellName] = BOOKTYPE_SPELL
      return i
    end
    i = i + 1
  end

  -- pet spellbook fallback
  i = 1
  while i <= 200 do
    local s = GetSpellName(i, BOOKTYPE_PET)
    if not s then
      break
    end
    if s == spellName then
      SpellIndexCache[spellName] = i
      _G.DoiteConditions_SpellBookTypeCache[spellName] = BOOKTYPE_PET
      return i
    end
    i = i + 1
  end

  SpellIndexCache[spellName] = false
  _G.DoiteConditions_SpellBookTypeCache[spellName] = false
  return nil
end

_G["DoiteConditions_GetSpellIndexByName"] = _GetSpellIndexByName

-- =================================================================
-- Cooldown / remaining helpers
-- =================================================================

-- Ability cooldown remaining for a spellbook index; nil if not on CD.
local function _AbilityRemainingSeconds(spellIndex, bookType, spellName)
  if not spellIndex then
    return nil
  end
  local start, dur, enable = GetSpellCooldown(spellIndex, bookType or BOOKTYPE_SPELL)
  if start and dur and start > 0 and dur > 0 then
    local rem = (start + dur) - GetTime()
    if rem and rem > 0 then
      return rem
    end
  end
  -- Shared-category fallback (see _IsSpellOnCooldown and
  -- DoiteConditions._GetSharedCDRemaining).
  if spellName and DoiteConditions._GetSharedCDRemaining then
    local srem = DoiteConditions._GetSharedCDRemaining(spellName)
    if srem and srem > 0 then
      return srem
    end
  end
  return nil
end

-- Remaining time by spell *name* (resolves index, then calls above).
local function _AbilityRemainingByName(spellName)
  if not spellName then
    return nil
  end
  local idx = _GetSpellIndexByName(spellName)
  local bt = _G.DoiteConditions_SpellBookTypeCache[spellName]
  return _AbilityRemainingSeconds(idx, bt or BOOKTYPE_SPELL, spellName)
end

-- Cache: last-seen full cooldown per spell name.
local _AbilityLastDurByName = {}
DoiteConditions._daAbilityLastDurByName = _AbilityLastDurByName

-- (rem, dur) for a spell by name. On ready returns (0, cachedDur).
local function _AbilityCooldownByName(spellName)
  if not spellName then
    return nil, nil
  end
  local idx = _GetSpellIndexByName(spellName)
  local bt = _G.DoiteConditions_SpellBookTypeCache[spellName]
  if not idx then
    return nil, nil
  end

  local start, dur = GetSpellCooldown(idx, bt or BOOKTYPE_SPELL)
  if start and dur and start > 0 and dur > 0 then
    if dur > DoiteConditions._GCD_THRESHOLD then
      _AbilityLastDurByName[spellName] = dur
    end
    local rem = (start + dur) - GetTime()
    if rem < 0 then
      rem = 0
    end
    return rem, dur
  end

  -- Shared-category fallback (see _IsSpellOnCooldown).
  if DoiteConditions._GetSharedCDRemaining then
    local srem, sdur = DoiteConditions._GetSharedCDRemaining(spellName)
    if srem and srem > 0 then
      if sdur and sdur > DoiteConditions._GCD_THRESHOLD then
        _AbilityLastDurByName[spellName] = sdur
      end
      return srem, sdur
    end
  end

  local cached = _AbilityLastDurByName[spellName]
  if cached and cached <= DoiteConditions._GCD_THRESHOLD then
    cached = nil
  end
  return 0, cached or (dur or 0)
end

-- Resolve the ability's full base cooldown for placeholder display.
-- Prefers: last-seen live duration -> Nampower static spell data.
local function _AbilityFullDurationByName(spellName)
  if not spellName then
    return nil
  end

  local cached = _AbilityLastDurByName[spellName]
  if cached and cached <= DoiteConditions._GCD_THRESHOLD then
    cached = nil
  end

  if type(GetSpellIdForName) == "function" then
    local okId, id = pcall(GetSpellIdForName, spellName)
    local sid = okId and tonumber(id) or nil
    if sid and sid > 0 then
      -- Path A (preferred): GetSpellRec returns the whole record as a
      -- table on TurtleWoW / Nampower clients. Covers recoveryTime,
      -- categoryRecoveryTime, and their capitalized variants in one
      -- call, without touching GetSpellRecField (whose field whitelist
      -- rejects those names on this client).
      local best = 0
      if type(GetSpellRec) == "function" then
        local okRec, rec = pcall(GetSpellRec, sid)
        if okRec and type(rec) == "table" then
          local rt  = tonumber(rec.recoveryTime) or 0
          local crt = tonumber(rec.categoryRecoveryTime) or 0
          local rtC  = tonumber(rec.RecoveryTime) or 0
          local crtC = tonumber(rec.CategoryRecoveryTime) or 0
          if rt  > best then best = rt  end
          if crt > best then best = crt end
          if rtC > best then best = rtC end
          if crtC > best then best = crtC end
        end
      end

      -- Path B (fallback): per-field lookups, only if GetSpellRec did
      -- not yield a duration. Retained for clients where the record
      -- table is unavailable but GetSpellRecField supports the names.
      if best <= 0 and type(GetSpellRecField) == "function" then
        local fields = {
          "recoveryTime", "RecoveryTime",
          "categoryRecoveryTime", "CategoryRecoveryTime",
        }
        local i = 1
        while i <= table.getn(fields) do
          local okV, ms = pcall(GetSpellRecField, sid, fields[i])
          if okV and tonumber(ms) and tonumber(ms) > best then
            best = tonumber(ms)
            DoiteConditions._daLastRecoveryField = fields[i]
          end
          i = i + 1
        end
      end

      if best > 0 then
        local fromDBC = math.floor(best / 1000 + 0.5)
        if cached and cached > 0 then
          local fromCache = math.floor(cached + 0.5)
          if fromCache > fromDBC then
            return fromCache
          end
        end
        return fromDBC
      end
    end
  end

  if cached and cached > 0 then
    return math.floor(cached + 0.5)
  end

  return nil
end

-- Expose for DoiteEdit.lua (Slide window placeholder).
_G["DoiteConditions_GetAbilityCooldown"]     = _AbilityCooldownByName
_G["DoiteConditions_GetAbilityFullDuration"] = _AbilityFullDurationByName

-- Spell on cooldown check (ignores pure GCD).
local function _IsSpellOnCooldown(spellIndex, bookType, spellName)
  if not spellIndex then
    return false
  end
  local start, dur = GetSpellCooldown(spellIndex, bookType or BOOKTYPE_SPELL)
  local threshold = DoiteConditions._GCD_THRESHOLD or 1.6
  if start and start > 0 and dur and dur > threshold then
    return true
  end
  -- Shared-category fallback (see DoiteConditions._GetSharedCDRemaining).
  -- Some clients return 0/0 for a spell whose only active cooldown is
  -- the one shared with a sibling via the DBC `category` field; the
  -- GetSpellRec-driven tracking in DoiteConditions.lua covers that case.
  if spellName and DoiteConditions._GetSharedCDRemaining then
    local srem = DoiteConditions._GetSharedCDRemaining(spellName)
    if srem and srem > 0 then
      return true
    end
  end
  return false
end

-- =================================================================
-- Nampower-safe IsSpellUsable wrapper
-- =================================================================
local SpellUsableArgCache = {}
local SpellUsableIdCache  = {}

local function _SafeSpellUsable(spellNameBase, spellIndex, bookType)
  if not IsSpellUsable or not spellNameBase then
    return 1, 0
  end

  -- 1) Nampower fast path: spellId + IsSpellUsable(id)
  if GetSpellIdForName then
    local sid = SpellUsableIdCache[spellNameBase]

    if sid == nil then
      sid = GetSpellIdForName(spellNameBase)
      SpellUsableIdCache[spellNameBase] = sid or false
    end

    if sid and sid ~= 0 then
      local ok, u, noMana = pcall(IsSpellUsable, sid)
      if ok and u ~= nil then
        return u, noMana
      end
    end
  end

  -- 2) Legacy fallback (rarely used)
  local bt = bookType or BOOKTYPE_SPELL
  local arg = spellNameBase

  if GetSpellName and spellIndex then
    local cached = SpellUsableArgCache[spellIndex]
    if cached and cached.base == spellNameBase then
      arg = cached.arg
    else
      local idxForRank = spellIndex
      local i = spellIndex + 1
      while i <= 200 do
        local n = GetSpellName(i, bt)
        if not n or n ~= spellNameBase then
          break
        end
        idxForRank = i
        i = i + 1
      end

      local n, r = GetSpellName(idxForRank, bt)
      if n and r and r ~= "" then
        arg = n .. "(" .. r .. ")"
      else
        arg = spellNameBase
      end

      SpellUsableArgCache[spellIndex] = { base = spellNameBase, arg = arg }
    end
  end

  local ok, u, noMana = pcall(IsSpellUsable, arg)
  if ok and u ~= nil then
    return u, noMana
  end

  ok, u, noMana = pcall(IsSpellUsable, spellNameBase)
  if ok and u ~= nil then
    return u, noMana
  end

  return 1, 0
end

_G["DoiteConditions_IsSpellOnCooldown"] = _IsSpellOnCooldown
_G["DoiteConditions_SafeSpellUsable"]   = _SafeSpellUsable
_G["DoiteConditions_AbilityRemainingSeconds"] = _AbilityRemainingSeconds
_G["DoiteConditions_AbilityRemainingByName"]  = _AbilityRemainingByName