---------------------------------------------------------------
-- DoiteConditionsAuras.lua
-- Aura scanning + tooltip resolution + aura-condition entry check.
-- Extracted from DoiteConditions.lua (Phase 5 of the split).
--
-- Functions in this file:
--   _EnsureTooltip              - lazy-create the shared tooltip
--   _GetAuraName                - name resolution via NP or tooltip
--   _GetAuraName_TooltipOnly    - tooltip-only fallback
--   _MaybeResolveSpellIdForEntry
--   _GetTrackedByName           - auraName -> list<key> cache
--   _ScanTargetUnitAuras        - refresh target buff/debuff snapshot
--   _TargetHasAura              - target buff/debuff presence by name
--   _TargetHasAuraBySpellId     - same, by spellId
--   DoiteConditions._AuraNamePrefix / _PlayerHasAuraPrefix / _TargetHasAuraPrefix
--   _TalentIsKnownByName
--   _ArrayMaxIndex / _CompactArrayInPlace
--   _StacksPasses / _GetAuraStacksOnUnit
--   _TargetHasAnyBuffName
--   _AuraConditions_CheckEntry / _EvaluateAuraConditionsList
--   _EnsureAuraTexture
--
-- Loaded AFTER Icons + Spell + Item modules (uses _NP_SpellNameAndTexture,
-- _GetIconFrame, _GetSpellIndexByName, _EvaluateItemCoreState).
-- Loaded BEFORE DoiteConditions.lua, which consumes these through
-- the exports below.
--
-- Public globals:
--   _G["DoiteConditions_EnsureTooltip"]
--   _G["DoiteConditions_TipLeft"]
--   _G["DoiteConditions_AuraSnapshot"]
--   _G["DoiteConditions_GetAuraName"]
--   _G["DoiteConditions_ScanUnitAuras"]
--   _G["DoiteConditions_TargetHasAura"]
--   _G["DoiteConditions_TargetHasAuraBySpellId"]
--   _G["DoiteConditions_TargetHasAnyBuffName"]
--   _G["DoiteConditions_StacksPasses"]
--   _G["DoiteConditions_GetAuraStacksOnUnit"]
--   _G["DoiteConditions_AuraConditionsCheckEntry"]
--   _G["DoiteConditions_EnsureAuraTexture"]
--   DoiteConditions_EvaluateAuraConditionsList
---------------------------------------------------------------

local DoiteConditions = _G["DoiteConditions"] or {}
_G["DoiteConditions"] = DoiteConditions

local UnitBuff = UnitBuff
local UnitDebuff = UnitDebuff
local UnitExists = UnitExists
local str_find = string.find
local str_gsub = string.gsub

-- Deps from sibling modules.
local _NP_SpellNameAndTexture = _G["DoiteConditions_SpellNameAndTexture"]
local _GetIconFrame           = _G["DoiteConditions_GetIconFrame"]
local _AbilityCooldownByName  = _G["DoiteConditions_GetAbilityCooldown"]
local _EvaluateItemCoreState  = DoiteConditions._EvaluateItemCoreState

-- Icon cache (shared with DoiteAuras.lua).
if not _G["DoiteAurasDB"] then
  _G["DoiteAurasDB"] = {}
end
DoiteAurasDB = _G["DoiteAurasDB"]
DoiteAurasDB.cache = DoiteAurasDB.cache or {}
local IconCache = DoiteAurasDB.cache

-- ============================================================
-- Callback bridge: mark main file's dirty_aura without touching upvalues
-- ============================================================
local _MarkAuraDirty = nil
local _SetHandlers = function(markAuraDirty)
  _MarkAuraDirty = markAuraDirty
end
_G["DoiteConditionsAuras_SetHandlers"] = _SetHandlers

-- ============================================================
-- Tooltip setup
-- ============================================================
local DoiteConditionsTooltip = _G["DoiteConditionsTooltip"]
if not DoiteConditionsTooltip then
  DoiteConditionsTooltip = CreateFrame("GameTooltip", "DoiteConditionsTooltip", nil, "GameTooltipTemplate")
  DoiteConditionsTooltip:SetOwner(UIParent, "ANCHOR_NONE")
end

-- Cache tooltip fontstrings once
local _CondTipLeft = {}
do
  local i = 1
  while i <= 15 do
    _CondTipLeft[i] = _G["DoiteConditionsTooltipTextLeft" .. i]
    i = i + 1
  end
end

local _DoiteCondTipLeft1FS = _G["DoiteConditionsTooltipTextLeft1"]

_G["DoiteConditions_TipLeft"] = _CondTipLeft

-- Create hidden tooltip once; don't re-SetOwner every scan
local function _EnsureTooltip()
  if not DoiteConditionsTooltip then
    DoiteConditionsTooltip = CreateFrame("GameTooltip", "DoiteConditionsTooltip", UIParent, "GameTooltipTemplate")
    DoiteConditionsTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    DoiteConditionsTooltip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    if DoiteConditionsTooltip.SetScript then
      DoiteConditionsTooltip:SetScript("OnTooltipCleared", nil)
      DoiteConditionsTooltip:SetScript("OnHide", nil)
    end
  end
end

_G["DoiteConditions_EnsureTooltip"] = _EnsureTooltip

-- ============================================================
-- Aura name resolution
-- ============================================================
local _AuraNameTipLeft1FS = nil

local function _GetAuraName(unit, index, isDebuff)
  if not unit or not index or index < 1 then
    return nil
  end

  local tex, auraId
  if isDebuff then
    tex, _, _, auraId = UnitDebuff(unit, index)
  else
    tex, _, auraId = UnitBuff(unit, index)
  end
  if not tex then
    return nil
  end

  local name

  if auraId then
    local n = _NP_SpellNameAndTexture(auraId)
    if type(n) == "string" and n ~= "" then
      name = n
    end
  end

  if not name then
    _EnsureTooltip()
    DoiteConditionsTooltip:ClearLines()

    if isDebuff then
      if DoiteConditionsTooltip.SetUnitDebuff then
        DoiteConditionsTooltip:SetUnitDebuff(unit, index)
      elseif DoiteConditionsTooltip.SetUnitBuff then
        DoiteConditionsTooltip:SetUnitBuff(unit, index, "HARMFUL")
      end
    else
      if DoiteConditionsTooltip.SetUnitBuff then
        DoiteConditionsTooltip:SetUnitBuff(unit, index, "HELPFUL")
      end
    end

    if not _AuraNameTipLeft1FS then
      _AuraNameTipLeft1FS = _G["DoiteConditionsTooltipTextLeft1"]
    end
    local fs = _AuraNameTipLeft1FS
    if fs and fs.GetText then
      local t = fs:GetText()
      if t and t ~= "" then
        name = t
      end
    end
  end

  if not name then
    return ""
  end

  return name
end

-- Tooltip-only fallback used by _ScanUnitAuras
local _DoiteCondTipLeft1FS2 = nil
local function _GetAuraName_TooltipOnly(unit, index, isDebuff)
  if not unit or not index or index < 1 then
    return ""
  end

  _EnsureTooltip()
  DoiteConditionsTooltip:ClearLines()

  if isDebuff then
    if DoiteConditionsTooltip.SetUnitDebuff then
      DoiteConditionsTooltip:SetUnitDebuff(unit, index)
    elseif DoiteConditionsTooltip.SetUnitBuff then
      DoiteConditionsTooltip:SetUnitBuff(unit, index, "HARMFUL")
    end
  else
    if DoiteConditionsTooltip.SetUnitBuff then
      DoiteConditionsTooltip:SetUnitBuff(unit, index, "HELPFUL")
    end
  end

  if not _DoiteCondTipLeft1FS2 then
    _DoiteCondTipLeft1FS2 = _G["DoiteConditionsTooltipTextLeft1"]
  end

  local fs = _DoiteCondTipLeft1FS2
  if fs and fs.GetText then
    local t = fs:GetText()
    if t and t ~= "" then
      return t
    end
  end

  return ""
end

_G["DoiteConditions_GetAuraName"] = _GetAuraName

-- ============================================================
-- Aura snapshot
-- ============================================================
local auraSnapshot = {
  target = { buffs = {}, debuffs = {}, buffIds = {}, debuffIds = {} },
}
_G.DoiteConditions_AuraSnapshot = auraSnapshot

-- ============================================================
-- Tracked-by-name cache
-- ============================================================
local function _MaybeResolveSpellIdForEntry(key, data)
  if not data or type(data) ~= "table" then
    return
  end

  local dn = data.displayName
  if not dn or dn == "" then
    return
  end
  if not str_find(dn, "^Spell ID") then
    return
  end

  local sidStr = data.spellid
  if not sidStr or sidStr == "" then
    return
  end
  local sid = tonumber(sidStr)
  if not sid or sid <= 0 then
    return
  end

  local name, tex
  name, tex = _NP_SpellNameAndTexture(sid)

  if not name or name == "" then
    return
  end

  data.displayName = name
  if not data.name or data.name == "" then
    data.name = name
  end

  if tex and tex ~= "" then
    data.iconTexture = tex

    if IconCache then
      IconCache[name] = tex
    end
    if DoiteAurasDB and DoiteAurasDB.cache then
      DoiteAurasDB.cache[name] = tex
    end

    if key then
      local f = _GetIconFrame(key)
      if f and f.icon and f.icon.SetTexture then
        local cur = f.icon:GetTexture()
        if cur ~= tex then
          f.icon:SetTexture(tex)
        end
      end
    end
  end
end

local _trackedByName, _trackedBuiltAt = nil, 0
local _trackedListPool = {}
local _trackedListPoolN = 0

local function _PoolPopList()
  if _trackedListPoolN > 0 then
    local lst = _trackedListPool[_trackedListPoolN]
    _trackedListPool[_trackedListPoolN] = nil
    _trackedListPoolN = _trackedListPoolN - 1
    return lst
  end
  return {}
end

local function _PoolPushList(lst)
  if not lst then
    return
  end
  local j
  for j in pairs(lst) do
    lst[j] = nil
  end
  _trackedListPoolN = _trackedListPoolN + 1
  _trackedListPool[_trackedListPoolN] = lst
end

local function _GetTrackedByName()
  local now = GetTime()

  local ttl
  if _Doite_IsAnyKeyUnderEdit then
    ttl = _Doite_IsAnyKeyUnderEdit() and 0.25 or 15.0
  else
    ttl = 15.0
  end

  local builtAt = _trackedBuiltAt or 0

  -- Fast path: TTL has not expired. Return cached without scanning the
  -- DB. The previous version counted DoiteAurasDB.spells on every call
  -- (even when returning the cache) to detect size changes; that O(n)
  -- pass ran on every UNIT_AURA event. This map only feeds cosmetic
  -- updates (auto-texture / spellid stamping), never condition
  -- visibility, so a short stale window after add/remove is harmless.
  if _trackedByName and (now - builtAt) < ttl then
    return _trackedByName
  end

  local dbSize = 0
  if DoiteAurasDB and DoiteAurasDB.spells then
    for _ in pairs(DoiteAurasDB.spells) do
      dbSize = dbSize + 1
    end
  end

  local t = _trackedByName
  if not t then
    t = {}
  else
    local k, lst
    for k, lst in pairs(t) do
      if type(lst) == "table" then
        _PoolPushList(lst)
      end
      t[k] = nil
    end
  end

  if DoiteAurasDB and DoiteAurasDB.spells then
    local key, data
    for key, data in pairs(DoiteAurasDB.spells) do
      if data and (data.type == "Buff" or data.type == "Debuff") then
        _MaybeResolveSpellIdForEntry(key, data)

        local nm = data.displayName or data.name
        if nm and nm ~= "" then
          local lst = t[nm]
          if not lst then
            lst = _PoolPopList()
            t[nm] = lst
          end
          table.insert(lst, key)
        end
      end
    end
  end

  _trackedByName, _trackedBuiltAt = t, now
  t._dbSize = dbSize
  return t
end

-- ============================================================
-- Target aura scan
-- ============================================================
local function _ScanTargetUnitAuras()
  local unit = "target"

  local trackedByName = _GetTrackedByName()

  local snap = auraSnapshot[unit]
  if not snap then
    return
  end

  local prevBuffs, prevDebuffs = snap.buffCount or 0, snap.debuffCount or 0

  local curBuffTex = UnitBuff(unit, 1)
  local curDebuffTex = UnitDebuff(unit, 1)

  if (not curBuffTex and prevBuffs == 0) and (not curDebuffTex and prevDebuffs == 0) then
    return
  end

  local buffs, debuffs = snap.buffs, snap.debuffs
  local buffIds, debuffIds = snap.buffIds, snap.debuffIds
  if not buffs or not debuffs then
    return
  end

  local buffCount = 0
  local debuffCount = 0

  for k in pairs(buffs) do
    buffs[k] = nil
  end
  for k in pairs(debuffs) do
    debuffs[k] = nil
  end
  if buffIds then
    for k in pairs(buffIds) do
      buffIds[k] = nil
    end
  end
  if debuffIds then
    for k in pairs(debuffIds) do
      debuffIds[k] = nil
    end
  end

  local cache = IconCache

  ----------------------------------------------------------------
  -- BUFFS
  ----------------------------------------------------------------
  local i = 1
  while true do
    local tex, _, auraId = UnitBuff(unit, i)
    if not tex then
      break
    end
    buffCount = buffCount + 1

    local name = nil
    if auraId then
      name = _NP_SpellNameAndTexture(auraId)
    end

    if (not name) or name == "" then
      local n2 = _GetAuraName_TooltipOnly(unit, i, false)
      if n2 and n2 ~= "" then
        name = n2
      end
    end

    if name and name ~= "" then
      buffs[name] = true
      if buffIds and auraId then
        buffIds[auraId] = true
      end

      local list = trackedByName and trackedByName[name]
      if list and type(list) == "table" then
        if tex and cache[name] ~= tex then
          cache[name] = tex
          if DoiteAurasDB and DoiteAurasDB.cache then
            DoiteAurasDB.cache[name] = tex
          end
        end

        local count = table.getn(list)
        local auraIdStr = nil
        for j = 1, count do
          local key = list[j]

          if key and DoiteAurasDB and DoiteAurasDB.spells then
            local s = DoiteAurasDB.spells[key]
            if s then
              if tex and tex ~= "" then
                s.iconTexture = tex
              end
              if auraId and (not s.spellid or s.spellid == "") then
                if not auraIdStr then
                  auraIdStr = tostring(auraId)
                end
                s.spellid = auraIdStr
              end
              if (not s.displayName or s.displayName == "") then
                s.displayName = name
              end
            end
          end

          local f = _GetIconFrame(key)
          if f and f.icon and tex and f.icon.GetTexture and f.icon.SetTexture then
            if f.icon:GetTexture() ~= tex then
              f.icon:SetTexture(tex)
            end
          end
        end
      end
    end

    i = i + 1
  end

  ----------------------------------------------------------------
  -- DEBUFFS
  ----------------------------------------------------------------
  i = 1
  while true do
    local tex, _, _, auraId = UnitDebuff(unit, i)
    if not tex then
      break
    end

    debuffCount = debuffCount + 1

    local name = nil
    if auraId then
      name = _NP_SpellNameAndTexture(auraId)
    end

    if (not name) or name == "" then
      local n2 = _GetAuraName_TooltipOnly(unit, i, true)
      if n2 ~= nil and n2 ~= "" then
        name = n2
      end
    end

    if type(name) == "string" and name ~= "" then
      debuffs[name] = true
      if debuffIds and auraId then
        debuffIds[auraId] = true
      end

      local list = trackedByName and trackedByName[name]
      if list and type(list) == "table" then
        if tex and cache[name] ~= tex then
          cache[name] = tex
          DoiteAurasDB.cache[name] = tex
        end

        local count = table.getn(list)
        local auraIdStr = nil
        for j = 1, count do
          local key = list[j]
          if key and DoiteAurasDB.spells then
            local s = DoiteAurasDB.spells[key]
            if s then
              if tex and tex ~= "" then
                s.iconTexture = tex
              end
              if auraId and (not s.spellid or s.spellid == "") then
                if not auraIdStr then
                  auraIdStr = tostring(auraId)
                end
                s.spellid = auraIdStr
              end
              if (not s.displayName or s.displayName == "") then
                s.displayName = name
              end
            end
          end

          local f = _GetIconFrame(key)
          if f and f.icon and tex and f.icon:GetTexture() ~= tex then
            f.icon:SetTexture(tex)
          end
        end
      end
    end

    i = i + 1
  end

  snap.buffCount = buffCount
  snap.debuffCount = debuffCount
end

_G["DoiteConditions_ScanUnitAuras"] = _ScanTargetUnitAuras

-- ============================================================
-- Target aura presence helpers
-- ============================================================
local function _TargetHasAura(auraName, wantDebuff)
  if not auraName or not UnitExists("target") then
    return false
  end
  if not DoiteTargetAuras then
    return false
  end

  if wantDebuff then
    if DoiteTargetAuras.HasDebuff then
      return DoiteTargetAuras.HasDebuff(auraName)
    end
    return false
  end

  if DoiteTargetAuras.HasBuff then
    return DoiteTargetAuras.HasBuff(auraName)
  end
  return false
end

local function _TargetHasAuraBySpellId(spellId, wantDebuff)
  spellId = tonumber(spellId) or 0
  if spellId <= 0 then
    return false
  end
  if not DoiteTargetAuras then
    return false
  end

  if wantDebuff then
    if DoiteTargetAuras.HasDebuffSpellId then
      return DoiteTargetAuras.HasDebuffSpellId(spellId)
    end
    return false
  end

  if DoiteTargetAuras.HasBuffSpellId then
    return DoiteTargetAuras.HasBuffSpellId(spellId)
  end
  return false
end

_G["DoiteConditions_TargetHasAura"]         = _TargetHasAura
_G["DoiteConditions_TargetHasAuraBySpellId"] = _TargetHasAuraBySpellId

-- ============================================================
-- Prefix (wildcard) aura-name matching
-- ============================================================
function DoiteConditions._AuraNamePrefix(s)
  if not s or s == "" then return nil end
  if string.sub(s, -1) == "*" then
    local p = string.sub(s, 1, -2)
    if p == "" then return nil end
    return p
  end
  return nil
end

function DoiteConditions._PlayerHasAuraPrefix(prefix, wantDebuff)
  if not prefix or prefix == "" then return false end
  local plen = string.len(prefix)
  local i = 1
  while i <= 40 do
    local tex, _, auraId
    if wantDebuff then
      tex, _, _, auraId = UnitDebuff("player", i)
    else
      tex, _, auraId = UnitBuff("player", i)
    end
    if not tex then break end
    if auraId then
      local n = _NP_SpellNameAndTexture(auraId)
      if type(n) == "string" and n ~= "" and string.sub(n, 1, plen) == prefix then
        return true
      end
    end
    i = i + 1
  end
  return false
end

function DoiteConditions._TargetHasAuraPrefix(prefix, wantDebuff)
  if not prefix or prefix == "" then return false end
  if not UnitExists("target") then return false end
  local plen = string.len(prefix)
  local i = 1
  while i <= 40 do
    local tex, _, auraId
    if wantDebuff then
      tex, _, _, auraId = UnitDebuff("target", i)
    else
      tex, _, auraId = UnitBuff("target", i)
    end
    if not tex then break end
    if auraId then
      local n = _NP_SpellNameAndTexture(auraId)
      if type(n) == "string" and n ~= "" and string.sub(n, 1, plen) == prefix then
        return true
      end
    end
    i = i + 1
  end
  return false
end

-- ============================================================
-- Talent lookup
-- ============================================================
local function _TalentIsKnownByName(talentName)
  if not talentName or talentName == "" then
    return false
  end
  if not GetNumTalentTabs or not GetNumTalents or not GetTalentInfo then
    return false
  end

  local numTabs = GetNumTalentTabs()
  if not numTabs or numTabs <= 0 then
    return false
  end

  local tab = 1
  while tab <= numTabs do
    local numTalents = GetNumTalents(tab) or 0
    local idx = 1
    while idx <= numTalents do
      local name, _, _, _, rank = GetTalentInfo(tab, idx)
      if name == talentName then
        return (rank and rank > 0)
      end
      idx = idx + 1
    end
    tab = tab + 1
  end

  return false
end

-- ============================================================
-- Array compaction helpers (prevents auraConditions nil-holes)
-- ============================================================
local function _ArrayMaxIndex(t)
  if not t then
    return 0
  end
  local m = 0
  for k in pairs(t) do
    if type(k) == "number" and k > m then
      m = k
    end
  end
  return m
end

local function _CompactArrayInPlace(t)
  if not t then
    return
  end

  local max = _ArrayMaxIndex(t)
  if max <= 0 then
    return
  end

  local write = 1
  local i = 1
  while i <= max do
    local v = t[i]
    if v ~= nil then
      if write ~= i then
        t[write] = v
        t[i] = nil
      end
      write = write + 1
    end
    i = i + 1
  end

  i = write
  while i <= max do
    t[i] = nil
    i = i + 1
  end
end

-- ============================================================
-- Stacks helpers
-- ============================================================
local _StacksPasses

local function _GetAuraStacksOnUnit(unit, auraName, wantDebuff, auraSpellId, addedViaSpellId)
  if not unit or not auraName then
    return nil
  end

  if unit == "player" then
    if addedViaSpellId == true then
      local sid = tonumber(auraSpellId) or 0
      if sid <= 0 then
        return nil
      end
      if wantDebuff then
        return DoitePlayerAuras.GetDebuffStacksBySpellId(sid)
      else
        return DoitePlayerAuras.GetBuffStacksBySpellId(sid)
      end
    end

    if wantDebuff then
      return DoitePlayerAuras.GetDebuffStacks(auraName)
    else
      return DoitePlayerAuras.GetBuffStacks(auraName)
    end
  end

  if unit == "target" then
    if not DoiteTargetAuras then
      return nil
    end

    if addedViaSpellId == true then
      local sid = tonumber(auraSpellId) or 0
      if sid <= 0 then
        return nil
      end
      if wantDebuff and DoiteTargetAuras.GetDebuffStacksBySpellId then
        return DoiteTargetAuras.GetDebuffStacksBySpellId(sid)
      elseif (not wantDebuff) and DoiteTargetAuras.GetBuffStacksBySpellId then
        return DoiteTargetAuras.GetBuffStacksBySpellId(sid)
      end
      return nil
    end

    if wantDebuff and DoiteTargetAuras.GetDebuffStacks then
      return DoiteTargetAuras.GetDebuffStacks(auraName)
    elseif (not wantDebuff) and DoiteTargetAuras.GetBuffStacks then
      return DoiteTargetAuras.GetBuffStacks(auraName)
    end
    return nil
  end

  ----------------------------------------------------------------
  -- Pet: prefer the event-driven cache maintained by DoitePetAuras
  -- when it is active (means at least one trackpet icon exists and the
  -- class is WARLOCK/HUNTER). Falls through to the generic scan when
  -- the cache is unavailable, so unit="pet" still works without it.
  ----------------------------------------------------------------
  if unit == "pet" then
    local DP = _G["DoitePetAuras"]
    if DP and DP.enabled == true and DP.GetStacks then
      return DP.GetStacks(auraName, wantDebuff, auraSpellId, addedViaSpellId)
    end
    -- fall through to generic scan below
  end

  ----------------------------------------------------------------
  -- Primary scan: normal BUFF / DEBUFF list for non-player units
  ----------------------------------------------------------------
  local i = 1
  while i <= 32 do
    local tex, applications, auraId
    if wantDebuff then
      tex, applications, _, auraId = UnitDebuff(unit, i)
    else
      tex, applications, auraId = UnitBuff(unit, i)
    end
    if not tex then
      break
    end

    local name
    if auraId then
      name = _NP_SpellNameAndTexture(auraId)
    end

    if addedViaSpellId == true then
      if auraId and auraSpellId and tonumber(auraId) == tonumber(auraSpellId) then
        return applications or 1
      end
    elseif name == auraName then
      return applications or 1
    end

    i = i + 1
  end

  -- Overflowed debuff fallback: read from UnitBuff snapshot
  if wantDebuff then
    local snap = auraSnapshot[unit]
    if snap then
      local debCount = snap.debuffCount or 0
      local buffs = snap.buffs

      if debCount >= 16 and buffs and buffs[auraName] then
        local j = 1
        while j <= 32 do
          local tex2, applications2, auraId2 = UnitBuff(unit, j)
          if not tex2 then
            break
          end

          local name2
          if auraId2 then
            name2 = _NP_SpellNameAndTexture(auraId2)
          end

          if name2 == auraName then
            return applications2 or 1
          end

          j = j + 1
        end

        j = 1
        while j <= 32 do
          local n = _GetAuraName(unit, j, false)
          if n == nil then
            break
          end
          if n ~= "" and n == auraName then
            local _, applications3 = UnitBuff(unit, j)
            return applications3 or 1
          end
          j = j + 1
        end
      end
    end
  end

  return nil
end

-- Compare: returns true if 'cnt' satisfies 'comp' vs 'target'
_StacksPasses = function(cnt, comp, target)
  if not cnt or not comp or target == nil then
    return true
  end
  if comp == ">=" then
    return cnt >= target
  elseif comp == "<=" then
    return cnt <= target
  elseif comp == "==" then
    return cnt == target
  end
  return true
end

_G["DoiteConditions_StacksPasses"]        = _StacksPasses
_G["DoiteConditions_GetAuraStacksOnUnit"] = _GetAuraStacksOnUnit

-- ============================================================
-- Buffs-any helpers
-- ============================================================
local function _TargetHasAnyBuffName(names)
  local unit = "target"
  if not unit or not names then
    return false
  end

  if not DoiteTargetAuras or not DoiteTargetAuras.HasBuff then
    return false
  end

  local n = table.getn(names)
  for i = 1, n do
    if DoiteTargetAuras.HasBuff(names[i]) then
      return true
    end
  end
  return false
end

_G["DoiteConditions_TargetHasAnyBuffName"] = _TargetHasAnyBuffName

-- ============================================================
-- Aura condition entry check
-- ============================================================
local function _AuraConditions_CheckEntry(entry)
  if not entry or not entry.buffType or not entry.mode then
    return true
  end
  local name = entry.name
  if not name or name == "" then
    return true
  end

  -- ABILITY branch
  if entry.buffType == "ABILITY" then
    if entry.mode == "notcd" or entry.mode == "oncd" then
      local rem, dur = _AbilityCooldownByName(name)
      if rem == nil then
        return false
      end

      local onCd = false
      if rem and rem > 0 then
        if dur and dur > 1.5 then
          onCd = true
        else
          onCd = false
        end
      end

      if entry.mode == "notcd" then
        return (not onCd)
      else
        return onCd
      end
    else
      return true
    end
  end

  -- ITEM branch
  if entry.buffType == "ITEM" then
    local dataTmp = DoiteConditions._auraCondItemDataTmp
    if not dataTmp then
      dataTmp = {}
      DoiteConditions._auraCondItemDataTmp = dataTmp
    end

    dataTmp.name = name
    dataTmp.displayName = name
    dataTmp.itemName = name
    dataTmp.itemId = entry.itemId or entry.itemID
    dataTmp.itemID = entry.itemID or entry.itemId

    local cTmp = DoiteConditions._auraCondItemCondTmp
    if not cTmp then
      cTmp = {}
      DoiteConditions._auraCondItemCondTmp = cTmp
    end

    cTmp.whereEquipped = (entry.mode ~= "missing") and true or nil
    cTmp.whereBag = (entry.mode ~= "missing") and true or nil
    cTmp.whereMissing = (entry.mode == "missing") and true or nil
    cTmp.inventorySlot = nil
    cTmp.mode = (entry.unit == "oncd") and "oncd" or "notcd"

    local stacksEnabled = (entry.stacksEnabled == true) and (entry.mode ~= "missing")
    cTmp.stacksEnabled = stacksEnabled and true or nil
    cTmp.stacksComp = entry.stacksComp
    cTmp.stacksVal = entry.stacksVal

    local state = _EvaluateItemCoreState(dataTmp, cTmp)

    if entry.mode == "missing" then
      return state and state.isMissing and true or false
    end

    if not (state and state.hasItem and state.passesWhere and state.modeMatches) then
      return false
    end

    if stacksEnabled then
      local comp = cTmp.stacksComp
      local thr = tonumber(cTmp.stacksVal)
      if comp and thr then
        local cnt = state.effectiveCount or 0
        return _StacksPasses(cnt, comp, thr)
      end
    end

    return true
  end

  -- TALENT branch
  if entry.buffType == "TALENT" then
    local cache = DoiteConditions._daTalentModeKeyByRaw
    if not cache then
      cache = {}
      DoiteConditions._daTalentModeKeyByRaw = cache
    end
    local modeRaw = entry.mode or ""
    local modeKey = cache[modeRaw]
    if not modeKey then
      modeKey = string.lower(modeRaw)
      modeKey = str_gsub(modeKey, "%s+", "")
      cache[modeRaw] = modeKey
    end

    local isKnown = _TalentIsKnownByName(name)

    if modeKey == "known" then
      return isKnown
    elseif modeKey == "notknown" then
      return (not isKnown)
    else
      return true
    end
  end

  ----------------------------------------------------------------
  -- BUFF / DEBUFF branch
  ----------------------------------------------------------------
  local wantDebuff = (entry.buffType == "DEBUFF")

  local unit = entry.unit or "player"
  if unit ~= "player" and unit ~= "target" then
    unit = "player"
  end

  if unit == "target" and (not UnitExists("target")) then
    return false
  end

  local stacksEnabled = (entry.stacksEnabled == true) and (entry.mode == "found")
  local stacksComp = nil
  local stacksThr = nil

  if stacksEnabled then
    stacksComp = entry.stacksComp
    if not stacksComp or stacksComp == "" then
      stacksEnabled = false
    else
      local raw = entry.stacksVal
      if raw == nil or raw == "" then
        stacksEnabled = false
      else
        if entry._daStacksValRaw ~= raw then
          entry._daStacksValRaw = raw
          local n = tonumber(raw)
          if n and n >= 0 then
            entry._daStacksValNum = n
          else
            entry._daStacksValNum = nil
          end
        end
        stacksThr = entry._daStacksValNum
        if stacksThr == nil then
          stacksEnabled = false
        end
      end
    end
  end

  local hasAura = false
  local useSpellIdOnly = (entry.Addedviaspellid == true)
  local auraSpellId = tonumber(entry.spellid) or 0
  local namePrefix = DoiteConditions._AuraNamePrefix(name)

  if namePrefix then
    stacksEnabled = false
    if unit == "player" then
      hasAura = DoiteConditions._PlayerHasAuraPrefix(namePrefix, wantDebuff)
    else
      hasAura = DoiteConditions._TargetHasAuraPrefix(namePrefix, wantDebuff)
    end
  elseif unit == "player" then
    if useSpellIdOnly and auraSpellId > 0 then
      if (not wantDebuff) and DoitePlayerAuras.HasBuffSpellId(auraSpellId) then
        hasAura = true
      elseif wantDebuff and DoitePlayerAuras.HasDebuffSpellId(auraSpellId) then
        hasAura = true
      end
    else
      if (not wantDebuff) and DoitePlayerAuras.HasBuff(name) then
        hasAura = true
      elseif wantDebuff and DoitePlayerAuras.HasDebuff(name) then
        hasAura = true
      end
    end
  else
    if useSpellIdOnly and auraSpellId > 0 then
      hasAura = _TargetHasAuraBySpellId(auraSpellId, wantDebuff)
    else
      hasAura = _TargetHasAura(name, wantDebuff)
    end
  end

  if stacksEnabled and hasAura then
    local cnt = _GetAuraStacksOnUnit(unit, name, wantDebuff, auraSpellId, useSpellIdOnly)
    if cnt == nil then
      cnt = 1
    end
    entry._daStacksLast = cnt

    local pass = _StacksPasses(cnt, stacksComp, stacksThr)
    return pass
  end

  if entry.mode == "found" then
    return hasAura
  elseif entry.mode == "missing" then
    return (not hasAura)
  end

  return true
end

local function _EvaluateAuraConditionsList(list)
  if not list then
    return true
  end

  if list._daDirty then
    _CompactArrayInPlace(list)
    list._daDirty = nil
  end

  local n = table.getn(list)
  if n == 0 then
    return true
  end

  local DL = _G["DoiteLogic"]
  if DL and DL.EvaluateAuraList then
    return DL.EvaluateAuraList(list, _AuraConditions_CheckEntry)
  end

  local i = 1
  while i <= n do
    if not _AuraConditions_CheckEntry(list[i]) then
      return false
    end
    i = i + 1
  end
  return true
end

function DoiteConditions_EvaluateAuraConditionsList(list)
  return _EvaluateAuraConditionsList(list)
end

_G["DoiteConditions_AuraConditionsCheckEntry"] = _AuraConditions_CheckEntry

-- ============================================================
-- Aura texture resolver
-- ============================================================
local function _EnsureAuraTexture(frame, data)
  if not frame then
    return
  end
  local icon = frame.icon
  if not icon or not icon.GetTexture or not icon.SetTexture then
    return
  end
  if not data or type(data) ~= "table" then
    return
  end

  local c = data.conditions and data.conditions.aura
  local name = data.displayName or data.name
  if not c or not name or name == "" then
    return
  end

  -- 0) Already stored texture
  if data.iconTexture and data.iconTexture ~= "" then
    local cur = icon:GetTexture()
    if cur ~= data.iconTexture then
      icon:SetTexture(data.iconTexture)
    end

    if IconCache[name] ~= data.iconTexture then
      IconCache[name] = data.iconTexture
      if DoiteAurasDB and DoiteAurasDB.cache then
        DoiteAurasDB.cache[name] = data.iconTexture
      end
    end
    return
  end

  -- 0a) Nampower id -> texture
  if data.spellid then
    local sid = tonumber(data.spellid)
    if sid and sid > 0 then
      local _, tex = _NP_SpellNameAndTexture(sid)
      if tex and tex ~= "" then
        local cur = icon:GetTexture()
        if cur ~= tex then
          icon:SetTexture(tex)
        end

        if IconCache[name] ~= tex then
          IconCache[name] = tex
          if DoiteAurasDB and DoiteAurasDB.cache then
            DoiteAurasDB.cache[name] = tex
          end
        end
        if DoiteAurasDB and DoiteAurasDB.spells and data.key and DoiteAurasDB.spells[data.key] then
          DoiteAurasDB.spells[data.key].iconTexture = tex
        end
        return
      end
    end
  end

  -- 0b) name -> spellId -> texture
  if GetSpellIdForName then
    local sid = GetSpellIdForName(name)
    if sid and sid > 0 then
      local _, tex = _NP_SpellNameAndTexture(sid)
      if tex and tex ~= "" then
        local cur = icon:GetTexture()
        if cur ~= tex then
          icon:SetTexture(tex)
        end

        if IconCache[name] ~= tex then
          IconCache[name] = tex
          if DoiteAurasDB and DoiteAurasDB.cache then
            DoiteAurasDB.cache[name] = tex
          end
        end
        if DoiteAurasDB and DoiteAurasDB.spells and data.key and DoiteAurasDB.spells[data.key] then
          local s = DoiteAurasDB.spells[data.key]
          s.iconTexture = tex
          if not s.spellid then
            s.spellid = tostring(sid)
          end
        end
        return
      end
    end
  end

  -- 1) Existing cache / placeholder logic
  local curTex = icon:GetTexture()
  local cached = IconCache and IconCache[name] or nil
  local isPlaceholder = (curTex == nil)
      or (type(curTex) == "string" and str_find(curTex, "INV_Misc_QuestionMark"))

  if cached and (not curTex or curTex ~= cached) then
    icon:SetTexture(cached)
    return
  end

  if (not isPlaceholder) and curTex then
    return
  end

  -- 2) Live aura scan
  local checkSelf, checkTarget = false, false

  local flagSelf = (c.targetSelf == true)
  local flagHelp = (c.targetHelp == true)
  local flagHarm = (c.targetHarm == true)

  if (not flagSelf) and (not flagHelp) and (not flagHarm) then
    flagSelf = true
  end

  if flagSelf then
    checkSelf = true
  end
  if flagHelp or flagHarm then
    checkTarget = true
  end

  if c.target and type(c.target) == "string" then
    if c.target == "self" then
      checkSelf = true
      checkTarget = false
    elseif c.target == "target" then
      checkSelf = false
      checkTarget = true
    elseif c.target == "both" then
      checkSelf = true
      checkTarget = true
    end
  end

  local function tryUnit(unit)
    local i = 1
    while i <= 40 do
      local n = _GetAuraName(unit, i, false)
      if n == nil then
        break
      end
      if n ~= "" and n == name then
        local tex = UnitBuff(unit, i)
        if tex and (isPlaceholder or curTex ~= tex) then
          icon:SetTexture(tex)
          IconCache[name] = tex
          if DoiteAurasDB and DoiteAurasDB.cache then
            DoiteAurasDB.cache[name] = tex
          end
        end
        return true
      end
      i = i + 1
    end

    i = 1
    while i <= 40 do
      local n = _GetAuraName(unit, i, true)
      if n == nil then
        break
      end
      if n ~= "" and n == name then
        local tex = UnitDebuff(unit, i)
        if tex and (isPlaceholder or curTex ~= tex) then
          icon:SetTexture(tex)
          IconCache[name] = tex
          if DoiteAurasDB and DoiteAurasDB.cache then
            DoiteAurasDB.cache[name] = tex
          end
        end
        return true
      end
      i = i + 1
    end

    return false
  end

  local got = false
  if checkSelf then
    got = tryUnit("player")
  end
  if (not got) and checkTarget and UnitExists("target") then
    got = tryUnit("target")
  end

  if not got then
    local i = 1
    while i <= 200 do
      local s = GetSpellName(i, BOOKTYPE_SPELL)
      if not s then
        break
      end
      if s == name then
        local tex = GetSpellTexture(i, BOOKTYPE_SPELL)
        if tex and (isPlaceholder or curTex ~= tex) then
          icon:SetTexture(tex)
          IconCache[name] = tex
          if DoiteAurasDB and DoiteAurasDB.cache then
            DoiteAurasDB.cache[name] = tex
          end
        end
        break
      end
      i = i + 1
    end
    if _MarkAuraDirty then _MarkAuraDirty() end
    return
  end
end

_G["DoiteConditions_EnsureAuraTexture"] = _EnsureAuraTexture