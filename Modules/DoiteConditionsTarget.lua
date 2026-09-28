---------------------------------------------------------------
-- Modules/DoiteConditionsTarget.lua
-- Target-condition helpers extracted from DoiteConditions.lua:
--   * target distance / status / unit type
--   * weapon filter (2H / Shield / DW)
--   * form / stance / paladin aura
--
-- Loaded BEFORE DoiteConditions.lua (see DoiteAuras.toc).
-- All public entry points stay as `DoiteConditions_*` globals so
-- existing call sites in DoiteConditions.lua work unchanged.
--
-- Please respect license note: Ask permission
-- WoW 1.12 | Lua 5.0
---------------------------------------------------------------

-- Ensure the DoiteConditions table exists. This module loads BEFORE
-- DoiteConditions.lua, so the table may not exist yet.
local DoiteConditions = _G["DoiteConditions"] or {}
_G["DoiteConditions"] = DoiteConditions

-- Local API aliases (this is a separate Lua chunk).
local str_find      = string.find
local str_gsub      = string.gsub
local UnitExists    = UnitExists
local UnitIsFriend  = UnitIsFriend
local UnitCanAttack = UnitCanAttack
local UnitClass     = UnitClass

-- Equipment slots needed by the weapon filter.
local INV_SLOT_MAINHAND = 16
local INV_SLOT_OFFHAND  = 17

---------------------------------------------------------------
-- Target distance / unit type
---------------------------------------------------------------
-- Mapping used by the editor labels ("1. Humanoid", "Multi: 1+2", etc.)
local UNIT_TYPE_INDEX_MAP = {
  [1] = "Humanoid",
  [2] = "Beast",
  [3] = "Dragonkin",
  [4] = "Undead",
  [5] = "Demon",
  [6] = "Giant",
  [7] = "Mechanical",
  [8] = "Elemental",
}

-- Normalizes "Any"/nil/"" -> nil (meaning "no restriction")
local function _NormalizeTargetField(val)
  if not val or val == "" or val == "Any" then
    return nil
  end
  if val == "Melee range" then
    return "In range"
  end
  return val
end
-- Exported: DoiteConditions.lua uses it in _RebuildTargetModsFlags
-- and _IconHasTargetMods_AbilityOrItem / _IconHasTargetMods_Aura.
_G["DoiteConditions_NormalizeTargetField"] = _NormalizeTargetField

-- Resurrection spells that are allowed to do distance checks on dead friendly targets.
local _ResurrectionSpellByName = {
  ["Rebirth"]          = true, -- Druid
  ["Redemption"]       = true, -- Paladin
  ["Resurrection"]     = true, -- Priest
  ["Ancestral Spirit"] = true, -- Shaman
}

local function _IsResurrectionSpell(spellName)
  if not spellName then
    return false
  end
  return _ResurrectionSpellByName[spellName] == true
end

-- Nampower-safe IsSpellInRange wrapper; returns true/false or nil if unknown.
local _SpellIdByNameCache = {}
local function _GetSpellIdCached(spellName)
  if not spellName then return nil end
  local sid = _SpellIdByNameCache[spellName]
  if sid ~= nil then return sid or nil end
  if GetSpellIdForName then
    sid = GetSpellIdForName(spellName)
    _SpellIdByNameCache[spellName] = sid or false
    return sid
  end
  _SpellIdByNameCache[spellName] = false
  return nil
end

local function _IsSpellInRangeSafe(spellName, unit)
  if not spellName or not unit then
    return nil
  end

  -- Nampower fast path: IsSpellInRange accepts spellId directly.
  local sid = _GetSpellIdCached(spellName)

  if sid and sid ~= 0 and type(IsSpellInRange) == "function" then
    local ok, res = pcall(IsSpellInRange, sid, unit)
    if ok then
      if res == 1 then
        return true
      elseif res == 0 then
        return false
      end
    end
  end

  -- Fallback: legacy name-based call.
  if type(IsSpellInRange) == "function" then
    local ok, res = pcall(IsSpellInRange, spellName, unit)
    if ok then
      if res == 1 then
        return true
      elseif res == 0 then
        return false
      end
    end
  end

  return nil
end

-- Main "targetDistance" eval
local function _PassesTargetDistance(condTbl, unit, spellName)
  if not condTbl or not unit then
    return true
  end

  local val = _NormalizeTargetField(condTbl.targetDistance)
  if not val then
    return true
  end
  if not UnitExists or not UnitExists(unit) then
    return true
  end

  local isDead     = UnitIsDead and UnitIsDead(unit) == 1
  local isFriend   = UnitIsFriend and UnitIsFriend("player", unit)
  local canAttack  = UnitCanAttack and UnitCanAttack("player", unit)
  local isHostile  = canAttack and (not isFriend)
  local hasUnitXP  = (type(UnitXP) == "function")

  -- Combined positional+range modes
  local wantPos = nil  -- "behind" / "front" / nil
  if val == "Behind & in range" then
    wantPos = "behind"
    val = "In range"
  elseif val == "In front & in range" then
    wantPos = "front"
    val = "In range"
  end

  -- UnitXP unavailable fallback behavior for imported/saved configs:
  --  - Behind / In front => treated as Any
  --  - Behind & in range / In front & in range => treated as In range
  if not hasUnitXP then
    if val == "Behind" or val == "In front" then
      return true
    end
    wantPos = nil
  end

  -- Positional checks first (also supports the combined modes above)
  local posOK = true

  if val == "Behind" or wantPos == "behind" then
    if hasUnitXP then
      local ok, behind = pcall(UnitXP, "behind", "player", unit)
      if ok then
        posOK = (behind == true)
      else
        posOK = true
      end
    else
      posOK = true
    end

    if val == "Behind" then
      return posOK
    end

  elseif val == "In front" or wantPos == "front" then
    if hasUnitXP then
      local okB, behind  = pcall(UnitXP, "behind",  "player", unit)
      local okS, inSight = pcall(UnitXP, "inSight", "player", unit)
      if not okB then behind  = false end
      if not okS then inSight = true  end
      posOK = (not behind) and (inSight ~= false)
    else
      posOK = true
    end

    if val == "In front" then
      return posOK
    end
  end

  -- Dead-target guard for range-based checks
  if val == "In range" or val == "Not in range" then
    if isDead then
      local allowRes = false
      if spellName and isFriend and (not isHostile) then
        if _IsResurrectionSpell(spellName) then
          allowRes = true
        end
      end

      -- Harmful dead or friendly dead with non-res spell:
      -- distance condition should simply NOT pass.
      if not allowRes then
        return false
      end
    end
  end

  ----------------------------------------------------------------
  -- Range-based checks ("In range", "Not in range")
  ----------------------------------------------------------------
  local inRange = _IsSpellInRangeSafe(spellName, unit)
  if inRange == nil then
    -- Keep legacy behavior: don't hide the icon if range cannot be resolved.
    inRange = true
  end

  if val == "In range" then
    if wantPos ~= nil then
      return (posOK and inRange)
    end
    return inRange
  elseif val == "Not in range" then
    return (not inRange)
  end

  return true
end

-- Global wrapper to reduce upvalues in big condition functions
function DoiteConditions_PassesTargetDistance(condTbl, unit, spellName)
  return _PassesTargetDistance(condTbl, unit, spellName)
end

-- Simple "target alive / dead" helper
local function _PassesTargetStatus(condTbl, unit)
  if not condTbl or not unit then
    return true
  end

  local wantAlive = (condTbl.targetAlive == true)
  local wantDead  = (condTbl.targetDead  == true)

  -- If neither flag is set, do not gate.
  if not wantAlive and not wantDead then
    return true
  end

  if not UnitExists or not UnitExists(unit) then
    -- No real target: don't kill the icon purely on this.
    return true
  end

  local isDead = (UnitIsDead and UnitIsDead(unit) == 1) and true or false

  -- UI should keep these mutually exclusive, but be robust anyway.
  if wantAlive and wantDead then
    return true
  elseif wantAlive then
    return (not isDead)
  elseif wantDead then
    return isDead
  end

  return true
end

-- Global wrapper to reduce upvalues in big condition functions
function DoiteConditions_PassesTargetStatus(condTbl, unit)
  return _PassesTargetStatus(condTbl, unit)
end

-- Parse "Multi: 1+2+3" -> { "Humanoid","Beast","Dragonkin" }
local function _ParseMultiUnitTypes(val)
  local wanted, seen = {}, {}
  local d
  for d in string.gfind(val, "(%d)") do
    local idx = tonumber(d)
    local name = idx and UNIT_TYPE_INDEX_MAP[idx] or nil
    if name and not seen[name] then
      table.insert(wanted, name)
      seen[name] = true
    end
  end
  return wanted
end

-- Main "targetUnitType" eval
local function _PassesTargetUnitType(condTbl, unit)
  if not condTbl or not unit then
    return true
  end

  local val = _NormalizeTargetField(condTbl.targetUnitType)
  if not val then
    return true
  end
  if not UnitExists or not UnitExists(unit) then
    return true
  end

  if val == "Players" then
    if UnitIsPlayer and UnitIsPlayer(unit) then
      return true
    end
    return false

  elseif val == "NPC" then
    if UnitIsPlayer and UnitIsPlayer(unit) then
      return false
    end
    return true

  elseif val == "Boss" then
    -- UnitClassification(unit) returns: "worldboss", "rareelite", "elite", "rare" or "normal"
    local cls = UnitClassification and UnitClassification(unit) or nil
    if not cls or cls == "" then
      -- No classification info; don't kill the icon
      return true
    end
    return (cls == "worldboss")

  elseif val == "Not a boss" then
    local cls = UnitClassification and UnitClassification(unit) or nil
    if not cls or cls == "" then
      return true
    end
    return (cls ~= "worldboss")
  end

  local creatureType = UnitCreatureType and UnitCreatureType(unit) or nil
  if not creatureType or creatureType == "" then
    -- No type info; don't kill the icon
    return true
  end

  -- Single type "1. Humanoid"
  local _, _, num, label = str_find(val, "^(%d+)%s*%.%s*(.+)$")
  if num and label and label ~= "" then
    return (creatureType == label)
  end

  -- Multi: "Multi: 1+2+3"
  if string.find(val, "Multi:") then
    local wanted = _ParseMultiUnitTypes(val)
    if table.getn(wanted) == 0 then
      return true
    end
    local i
    for i = 1, table.getn(wanted) do
      if creatureType == wanted[i] then
        return true
      end
    end
    return false
  end

  -- Fallback: allow exact string match if someone typed the raw type
  if creatureType == val then
    return true
  end

  -- Default: don't fail on unknown label
  return true
end

-- Global wrapper to reduce upvalues in big condition functions
function DoiteConditions_PassesTargetUnitType(condTbl, unit)
  return _PassesTargetUnitType(condTbl, unit)
end

---------------------------------------------------------------
-- Weapon filter helpers (Two-Hand / Shield / Dual-Wield)
---------------------------------------------------------------

local function _ClassifyEquippedSlot(slot)
  if not slot or not GetInventoryItemLink or type(GetItemInfo) ~= "function" then
    return nil
  end

  local link = GetInventoryItemLink("player", slot)
  if not link then
    return nil
  end

  local itemId
  local _, _, idStr = str_find(link, "item:(%d+)")
  if idStr then
    itemId = tonumber(idStr)
  end
  if not itemId then
    return { hasItem = true }
  end

  -- xp3-style GetItemInfo: name, link, quality, level, itemType, itemSubType, stack
  local _, _, _, _, itemType, itemSubType = GetItemInfo(itemId)
  if not itemType or itemType == "" then
    -- ItemInfo not cached yet; treat as "unknown weapon state"
    return { hasItem = true }
  end

  local isShield = false
  local isTwoHand = false
  local isWeapon = false

  -- Shields are Armor / Shields
  if itemType == "Armor" and itemSubType == "Shields" then
    isShield = true
  end

  -- All actual weapons share itemType == "Weapon"
  if itemType == "Weapon" then
    isWeapon = true

    if itemSubType then
      -- "Two-Handed Maces", "Two-Handed Swords", etc.
      if str_find(itemSubType, "Two%-Handed") then
        isTwoHand = true
        -- 2H melee families that don't carry the "Two-Handed" prefix
      elseif itemSubType == "Staves"
          or itemSubType == "Polearms"
          or itemSubType == "Fishing Poles" then
        isTwoHand = true
      end
    end
  end

  return {
    hasItem   = true,
    isShield  = isShield,
    isTwoHand = isTwoHand,
    isWeapon  = isWeapon,
  }
end

local function _GetEquippedWeaponState()
  -- Returns hasTwoHand, hasShieldOffhand, isDualWield; nil,nil,nil if cannot inspect inventory at all.
  if not GetInventoryItemLink or type(GetItemInfo) ~= "function" then
    return nil, nil, nil
  end

  -- Cache for 0.5s: many icons call this per eval pass.
  local now = GetTime and GetTime() or 0
  local cached = DoiteConditions._weaponStateCache
  if cached and (now - cached.at) < 0.5 then
    return cached.two, cached.sh, cached.dual
  end

  local main = _ClassifyEquippedSlot(INV_SLOT_MAINHAND)
  local off  = _ClassifyEquippedSlot(INV_SLOT_OFFHAND)

  if not main and not off then
    DoiteConditions._weaponStateCache = { at = now, two = nil, sh = nil, dual = nil }
    return nil, nil, nil
  end

  local hasTwoHand = false
  local hasShield  = false
  local isDual     = false

  if main and main.isTwoHand then
    hasTwoHand = true
  end

  if off and off.isShield then
    hasShield = true
  end

  if main and main.isWeapon and off and off.isWeapon and not off.isShield then
    isDual = true
  end

  DoiteConditions._weaponStateCache = { at = now, two = hasTwoHand, sh = hasShield, dual = isDual }
  return hasTwoHand, hasShield, isDual
end

-- Cache weapon filter normalization by raw string to avoid repeated lower/gsub allocations
local _DA_WeaponFilterNormByRaw = {}
local function _NormalizeWeaponFilter(mode)
  if not mode or mode == "" then
    return nil
  end

  local cached = _DA_WeaponFilterNormByRaw[mode]
  if cached ~= nil then
    if cached == false then
      return nil
    end
    return cached
  end

  local s = string.lower(mode)
  s = string.gsub(s, "%s+", "")
  s = string.gsub(s, "%-", "")

  local out = nil
  -- Accept "Two-Hand", "Two hand", "2 hand", "2H", etc.
  if s == "twohand" or s == "2hand" or s == "2h" then
    out = "2H"
    -- Accept "Shield", "shield"
  elseif s == "shield" or s == "sh" then
    out = "SH"
    -- Accept "Dual-Wield", "Dual wield", "DW", etc.
  elseif s == "dualwield" or s == "dual" or s == "dw" then
    out = "DW"
  end

  if out then
    _DA_WeaponFilterNormByRaw[mode] = out
    return out
  end
  _DA_WeaponFilterNormByRaw[mode] = false
  return nil
end

local function _PassesWeaponFilter(condTbl)
  if not condTbl then
    return true
  end

  local norm = _NormalizeWeaponFilter(condTbl.weaponFilter)
  if not norm then
    -- No filter configured or unknown label -> don't gate
    return true
  end

  -- Only meaningful for Warrior / Paladin / Shaman
  local _, cls = UnitClass("player")
  cls = cls and string.upper(cls) or ""
  if cls ~= "WARRIOR" and cls ~= "PALADIN" and cls ~= "SHAMAN" then
    return true
  end

  local hasTwoHand, hasShield, isDual = _GetEquippedWeaponState()
  if hasTwoHand == nil and hasShield == nil and isDual == nil then
    -- Inventory APIs unavailable; don't kill icons
    return true
  end

  if norm == "2H" then
    return hasTwoHand
  elseif norm == "SH" then
    return hasShield
  elseif norm == "DW" then
    return isDual
  end

  return true
end

-- Global wrapper to reduce upvalues in big condition functions
function DoiteConditions_PassesWeaponFilter(condTbl)
  return _PassesWeaponFilter(condTbl)
end

---------------------------------------------------------------
-- Form / Stance evaluation (no fallbacks)
---------------------------------------------------------------
local function _ActiveFormMap()
  local map = DoiteConditions._activeFormMap
  if not map then
    map = {}
    DoiteConditions._activeFormMap = map
  end

  -- Cache form map for 0.1s: many icons call this per eval pass.
  local now = GetTime and GetTime() or 0
  if DoiteConditions._activeFormMapAt and (now - DoiteConditions._activeFormMapAt) < 0.1 then
    return map
  end
  DoiteConditions._activeFormMapAt = now

  for k in pairs(map) do
    map[k] = nil
  end

  for i = 1, 10 do
    local _, name, active = GetShapeshiftFormInfo(i)
    if not name then
      break
    end
    map[name] = (active and active == 1) and true or false
  end
  return map
end

local function _AnyActive(map, names)
  for _, n in ipairs(names) do
    if map[n] then
      return true
    end
  end
  return false
end

local function _DruidNoForm(map)
  -- No Bear/Cat/Aquatic/Travel/Swift Travel/Moonkin/Tree is active
  local any = _AnyActive(map, {
    "Dire Bear Form", "Bear Form", "Cat Form", "Aquatic Form",
    "Travel Form", "Swift Travel Form", "Moonkin Form", "Tree of Life Form"
  })
  return not any
end

local function _DruidStealth()
  return DoitePlayerAuras.HasBuff("Prowl")
end

local function _PriestShadowform()
  return DoitePlayerAuras.HasBuff("Shadowform")
end

-- Normalize editor labels so logic is robust to wording differences
local function _NormalizeFormLabel(s)
  if not s or s == "" then
    return "All"
  end
  s = str_gsub(s, "^%s+", "")
  s = str_gsub(s, "%s+$", "")
  -- unify "All ..." variants (editor may say "All Auras", "All stances", etc.)
  if s == "All" or s == "All forms" or s == "All stances" or s == "All Auras" then
    return "All"
  end
  -- unify the druid "no form(s)" label
  if s == "0. No form" or s == "0. No forms" then
    return "0. No form"
  end
  return s
end

-- Paladin: no aura selected in the shapeshift bar
local function _PaladinNoAura(map)
  return not _AnyActive(map, {
    "Devotion Aura", "Retribution Aura", "Concentration Aura",
    "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura", "Sanctity Aura"
  })
end

local function _PassesFormRequirement(formStr)
  formStr = _NormalizeFormLabel(formStr)
  if not formStr or formStr == "All" then
    return true
  end

  local _, cls = UnitClass("player")
  cls = cls and string.upper(cls) or ""
  local map = _ActiveFormMap()

  -- WARRIOR
  if cls == "WARRIOR" then
    if formStr == "1. Battle" then
      return map["Battle Stance"] == true
    end
    if formStr == "2. Defensive" then
      return map["Defensive Stance"] == true
    end
    if formStr == "3. Berserker" then
      return map["Berserker Stance"] == true
    end
    if formStr == "Multi: 1+2" then
      return (map["Battle Stance"] == true) or (map["Defensive Stance"] == true)
    end
    if formStr == "Multi: 1+3" then
      return (map["Battle Stance"] == true) or (map["Berserker Stance"] == true)
    end
    if formStr == "Multi: 2+3" then
      return (map["Defensive Stance"] == true) or (map["Berserker Stance"] == true)
    end
    return true
  end

  -- ROGUE
  if cls == "ROGUE" then
    if formStr == "1. Stealth" then
      return map["Stealth"] == true
    end
    if formStr == "0. No Stealth" then
      return map["Stealth"] ~= true
    end
    return true
  end

  -- PRIEST
  if cls == "PRIEST" then
    if formStr == "1. Shadowform" then
      return _PriestShadowform()
    end
    if formStr == "0. No form" then
      return not _PriestShadowform()
    end
    return true
  end

  -- DRUID  (accepts both "0. No form" and "0. No forms")
  if cls == "DRUID" then
    if formStr == "0. No form" then
      return _DruidNoForm(map)
    end
    if formStr == "1. Bear" then
      return _AnyActive(map, { "Dire Bear Form", "Bear Form" })
    end
    if formStr == "2. Aquatic" then
      return map["Aquatic Form"] == true
    end
    if formStr == "3. Cat" then
      return map["Cat Form"] == true
    end
    if formStr == "4. Travel" then
      return _AnyActive(map, { "Travel Form", "Swift Travel Form" })
    end
    if formStr == "5. Moonkin" then
      return map["Moonkin Form"] == true
    end
    if formStr == "6. Tree" then
      return map["Tree of Life Form"] == true
    end
    -- stealth variants use aura state
    if formStr == "7. Stealth" then
      return _DruidStealth()
    end
    if formStr == "8. No Stealth" then
      return not _DruidStealth()
    end
    -- multis
    if formStr == "Multi: 0+5" then
      return _DruidNoForm(map) or (map["Moonkin Form"] == true)
    end
    if formStr == "Multi: 0+6" then
      return _DruidNoForm(map) or (map["Tree of Life Form"] == true)
    end
    if formStr == "Multi: 1+3" then
      return _AnyActive(map, { "Dire Bear Form", "Bear Form", "Cat Form" })
    end
    if formStr == "Multi: 3+7" then
      return (map["Cat Form"] == true) or _DruidStealth()
    end
    if formStr == "Multi: 3+8" then
      return (map["Cat Form"] == true) and (not _DruidStealth())
    end
    if formStr == "Multi: 5+6" then
      return _AnyActive(map, { "Moonkin Form", "Tree of Life Form" })
    end
    if formStr == "Multi: 0+5+6" then
      return _DruidNoForm(map) or _AnyActive(map, { "Moonkin Form", "Tree of Life Form" })
    end
    if formStr == "Multi: 1+3+8" then
      return _AnyActive(map, { "Dire Bear Form", "Bear Form", "Cat Form" }) and (not _DruidStealth())
    end
    return true
  end

  -- PALADIN (treat auras as shapeshift forms via GetShapeshiftFormInfo)
  if cls == "PALADIN" then
    if formStr == "No Aura" then
      return _PaladinNoAura(map)
    end
    if formStr == "1. Devotion" then
      return map["Devotion Aura"] == true
    end
    if formStr == "2. Retribution" then
      return map["Retribution Aura"] == true
    end
    if formStr == "3. Concentration" then
      return map["Concentration Aura"] == true
    end
    if formStr == "4. Shadow Resistance" then
      return map["Shadow Resistance Aura"] == true
    end
    if formStr == "5. Frost Resistance" then
      return map["Frost Resistance Aura"] == true
    end
    if formStr == "6. Fire Resistance" then
      return map["Fire Resistance Aura"] == true
    end
    if formStr == "7. Sanctity" then
      return map["Sanctity Aura"] == true
    end

    -- multis (logical OR among the listed auras)
    if formStr == "Multi: 1+2" then
      return _AnyActive(map, { "Devotion Aura", "Retribution Aura" })
    end
    if formStr == "Multi: 1+3" then
      return _AnyActive(map, { "Devotion Aura", "Concentration Aura" })
    end
    if formStr == "Multi: 1+4+5+6" then
      return _AnyActive(map, { "Devotion Aura", "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura" })
    end
    if formStr == "Multi: 1+7" then
      return _AnyActive(map, { "Devotion Aura", "Sanctity Aura" })
    end
    if formStr == "Multi: 1+2+3" then
      return _AnyActive(map, { "Devotion Aura", "Retribution Aura", "Concentration Aura" })
    end
    if formStr == "Multi: 1+2+3+4+5+6" then
      return _AnyActive(map, { "Devotion Aura", "Retribution Aura", "Concentration Aura", "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura" })
    end
    if formStr == "Multi: 2+3" then
      return _AnyActive(map, { "Retribution Aura", "Concentration Aura" })
    end
    if formStr == "Multi: 2+4+5+6" then
      return _AnyActive(map, { "Retribution Aura", "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura" })
    end
    if formStr == "Multi: 2+7" then
      return _AnyActive(map, { "Retribution Aura", "Sanctity Aura" })
    end
    if formStr == "Multi: 2+3+4+5+6" then
      return _AnyActive(map, { "Retribution Aura", "Concentration Aura", "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura" })
    end
    if formStr == "Multi: 3+4+5+6" then
      return _AnyActive(map, { "Concentration Aura", "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura" })
    end
    if formStr == "Multi: 3+7" then
      return _AnyActive(map, { "Concentration Aura", "Sanctity Aura" })
    end
    if formStr == "Multi: 4+5+6+7" then
      return _AnyActive(map, { "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura", "Sanctity Aura" })
    end

    return true
  end

  return true
end

-- Global wrapper to reduce upvalues in big condition functions
function DoiteConditions_PassesFormRequirement(formStr)
  return _PassesFormRequirement(formStr)
end