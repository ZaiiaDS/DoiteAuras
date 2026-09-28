---------------------------------------------------------------
-- DoiteConditionsProc.lua
-- Proc-window timers + class-specific reactive procs.
-- Extracted from DoiteConditions.lua (Phase 2 of the split).
--
-- Functions in this file:
--   _ProcWindowDuration         - get proc window duration for a spell
--   _ProcWindowSet              - register proc window (absolute endTime)
--   _ProcWindowRemaining        - remaining seconds for active proc
--   _HasTrackedProcSpell        - is this spell tracked as Ability in DB
--   _Warrior_Overpower_OK       - warrior proc gate for Overpower
--   _Warrior_Revenge_OK         - warrior proc gate for Revenge
--   _WarriorProcTick            - heartbeat that expires warrior procs
--   Class event frames (WARRIOR / ROGUE / MAGE / HUNTER)
--
-- Loaded BEFORE DoiteConditions.lua. Main file installs callback
-- handlers via DoiteConditionsProc.SetHandlers(...) so we can mark
-- its file-local dirty flags without reaching into its upvalues.
--
-- Public globals (read by DoiteConditions.lua and Overlay):
--   _G["DoiteConditions_ProcWindowDurations"]    (table)
--   _G["DoiteConditions_ProcUntil"]              (table)
--   _G["DoiteConditions_ProcLastShowByKey"]      (table)
--   _G["DoiteConditions_ProcWindowDuration"]
--   _G["DoiteConditions_ProcWindowSet"]
--   _G["DoiteConditions_ProcWindowRemaining"]
--   _G["DoiteConditions_WarriorOverpowerOK"]
--   _G["DoiteConditions_WarriorRevengeOK"]
--   _G["DoiteConditions_WarriorProcTick"]
---------------------------------------------------------------

local DoiteConditionsProc = {}
_G["DoiteConditionsProc"] = DoiteConditionsProc

local str_find = string.find
local str_gsub = string.gsub

-- ============================================================
-- Callback bridge
-- ============================================================
local _MarkDirty = nil
local _RequestEval = nil

-- markDirty() - flip both dirty_ability and dirty_ability_time in main file
-- requestEval() - schedule an immediate eval on next frame
-- Idempotent: once handlers are set, ignore repeated calls so a duplicate
-- load of DoiteConditions.lua cannot silently nil-out the callbacks and
-- break proc updates. Passing nil twice is a no-op.
function DoiteConditionsProc.SetHandlers(markDirty, requestEval)
  if markDirty ~= nil then
    _MarkDirty = markDirty
  end
  if requestEval ~= nil then
    _RequestEval = requestEval
  end
end

local function _FireMarkDirty()
  if _MarkDirty then _MarkDirty() end
end

local function _FireRequestEval()
  if _RequestEval then _RequestEval() end
end

local function _Now()
  return (GetTime and GetTime()) or 0
end

-- ============================================================
-- Proc-window timers (NOT cooldown timers)
-- ============================================================
_G.DoiteConditions_ProcWindowDurations = _G.DoiteConditions_ProcWindowDurations or {
  ["Overpower"] = 4.0,
  ["Revenge"] = 4.0,
  ["Surprise Attack"] = 4.0,
  ["Riposte"] = 4.0,
  ["Arcane Surge"] = 4.0,
  ["Lacerate"] = 4.0,
}

-- SpellName -> absolute endTime (GetTime() + duration)
_G.DoiteConditions_ProcUntil = _G.DoiteConditions_ProcUntil or {}
-- Per-icon rising-edge detector for "usable proc" icons
_G.DoiteConditions_ProcLastShowByKey = _G.DoiteConditions_ProcLastShowByKey or {}

local function _ProcWindowDuration(spellName)
  if not spellName then
    return nil
  end
  local d = _G.DoiteConditions_ProcWindowDurations and _G.DoiteConditions_ProcWindowDurations[spellName]
  if type(d) == "number" and d > 0 then
    return d
  end
  return nil
end

local function _ProcWindowSet(spellName, endTime)
  if not spellName or not endTime then
    return
  end
  _G.DoiteConditions_ProcUntil[spellName] = endTime

  _FireMarkDirty()
  _FireRequestEval()
end

local function _ProcWindowRemaining(spellName)
  if not spellName then
    return nil
  end
  local untilT = _G.DoiteConditions_ProcUntil and _G.DoiteConditions_ProcUntil[spellName]
  if untilT then
    local rem = untilT - (_Now() or 0)
    if rem and rem > 0 then
      return rem
    end
  end
  return nil
end

_G["DoiteConditions_ProcWindowDuration"]  = _ProcWindowDuration
_G["DoiteConditions_ProcWindowSet"]       = _ProcWindowSet
_G["DoiteConditions_ProcWindowRemaining"] = _ProcWindowRemaining

-- ============================================================
-- Class-specific reactive procs
-- ============================================================

-- Keep warrior-specific state for target-matching
local _WarriorProc = { OP_until = 0, OP_target = nil, REV_until = 0 }

-- Cache: spellName -> true/false. Rebuilt lazily; invalidated by
-- DoiteConditions_RequestEvaluate via DoiteConditionsProc.InvalidateTrackedCache().
local _trackedProcSpellCache = {}
_G["DoiteConditionsProc_trackedCache"] = _trackedProcSpellCache

function DoiteConditionsProc.InvalidateTrackedCache()
  local c = _G["DoiteConditionsProc_trackedCache"]
  if c then
    for k in pairs(c) do
      c[k] = nil
    end
  end
end

local function _HasTrackedProcSpell(spellName)
  if not spellName or spellName == "" then
    return false
  end

  local cache = _G["DoiteConditionsProc_trackedCache"]
  if cache and cache[spellName] ~= nil then
    return cache[spellName]
  end

  local db = DoiteAurasDB and DoiteAurasDB.spells
  if not db then
    if cache then cache[spellName] = false end
    return false
  end

  local found = false
  local _, data
  for _, data in pairs(db) do
    if type(data) == "table" and data.type == "Ability" then
      local nm = data.name or data.displayName
      if nm == spellName then
        found = true
        break
      end
    end
  end

  if cache then
    cache[spellName] = found and true or false
  end
  return found
end

local _daClassCL = CreateFrame("Frame", "DoiteClassCL")
local _daClassCL2 = CreateFrame("Frame", "DoiteClassCL2")

do
  local _, cls = UnitClass("player")
  cls = cls and string.upper(cls) or ""

  if cls == "WARRIOR" then
    -- Overpower: needs dodge detection
    _daClassCL:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
    _daClassCL:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")

    _daClassCL:SetScript("OnEvent", function()
      if not _HasTrackedProcSpell("Overpower") then
        return
      end

      local line = arg1
      if not line or line == "" then
        return
      end

      -- Overpower: target dodged you
      local tgt
      local _, _, t1 = str_find(line, "You attack%.%s+(.+)%s+dodges")
      if t1 then
        tgt = t1
      else
        local _, _, t2 = str_find(line, "Your%s+.+%s+was%s+dodged%s+by%s+(.+)")
        tgt = t2
      end

      if tgt then
        tgt = str_gsub(tgt, "%s*[%.!%?]+%s*$", "")
        _WarriorProc.OP_target = tgt

        local now = _Now()
        local dur = _ProcWindowDuration("Overpower") or 4.0
        _WarriorProc.OP_until = now + dur
        _ProcWindowSet("Overpower", _WarriorProc.OP_until)
      end
    end)

    -- Revenge: needs incoming hits/blocks/parries/dodges
    _daClassCL2:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
    _daClassCL2:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")

    _daClassCL2:SetScript("OnEvent", function()
      if not _HasTrackedProcSpell("Revenge") then
        return
      end

      local line = arg1
      if not line or line == "" then
        return
      end

      -- Revenge: you dodged/parried/blocked
      if str_find(line, "You dodge")
          or str_find(line, "You parry")
          or str_find(line, "You block")
          or ((str_find(line, " hits you for ") or str_find(line, " crits you for "))
          and str_find(line, " blocked)")) then

        local now = _Now()
        local dur = _ProcWindowDuration("Revenge") or 4.0
        _WarriorProc.REV_until = now + dur
        _ProcWindowSet("Revenge", _WarriorProc.REV_until)
      end
    end)

  elseif cls == "ROGUE" then
    -- Surprise Attack: needs dodge detection
    _daClassCL:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
    _daClassCL:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")

    _daClassCL:SetScript("OnEvent", function()
      if not _HasTrackedProcSpell("Surprise Attack") then
        return
      end

      local line = arg1
      if not line or line == "" then
        return
      end

      local dodged = false
      local _, _, t1 = str_find(line, "You attack%.%s+(.+)%s+dodges")
      if t1 then
        dodged = true
      else
        local _, _, t2 = str_find(line, "Your%s+.+%s+was%s+dodged%s+by%s+(.+)")
        if t2 then
          dodged = true
        end
      end

      if dodged then
        local dur = _ProcWindowDuration("Surprise Attack")
        if dur then
          local now = _Now()
          _ProcWindowSet("Surprise Attack", now + dur)
        end
      end
    end)

    -- Riposte: procs on YOUR parry (not target-bound)
    _daClassCL2:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
    _daClassCL2:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")

    _daClassCL2:SetScript("OnEvent", function()
      if not _HasTrackedProcSpell("Riposte") then
        return
      end

      local line = arg1
      if not line or line == "" then
        return
      end

      if str_find(line, "You parry") then
        local dur = _ProcWindowDuration("Riposte") or 4.0
        local now = _Now()
        _ProcWindowSet("Riposte", now + dur)
      end
    end)

  elseif cls == "MAGE" then
    -- Arcane Surge: needs resist detection
    _daClassCL:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")

    _daClassCL:SetScript("OnEvent", function()
      if not _HasTrackedProcSpell("Arcane Surge") then
        return
      end

      local line = arg1
      if not line or line == "" then
        return
      end

      if str_find(line, " was resisted")
          or str_find(line, " resisted%)")
          or str_find(line, " resisted by")
          or str_find(line, " resists your ") then

        local dur = _ProcWindowDuration("Arcane Surge")
        if dur then
          local now = _Now()
          _ProcWindowSet("Arcane Surge", now + dur)
        end
      end
    end)

  elseif cls == "HUNTER" then
    -- Lacerate: procs on any player crit, not target-bound.
    _daClassCL:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
    _daClassCL:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")

    _daClassCL:SetScript("OnEvent", function()
      if not _HasTrackedProcSpell("Lacerate") then
        return
      end

      local line = arg1
      if not line or line == "" then
        return
      end

      if str_find(line, "^You%s+crit%s+.+%s+for%s+")
          or str_find(line, "^Your%s+.+%s+crits%s+.+%s+for%s+") then
        local dur = _ProcWindowDuration("Lacerate")
        if dur then
          local now = _Now()
          _ProcWindowSet("Lacerate", now + dur)
        end
      end
    end)
  end
end

-- Warrior proc gates consumed by ability-usable override
local function _Warrior_Overpower_OK()
  if (_Now() > _WarriorProc.OP_until) then
    return false
  end
  if not UnitExists("target") then
    return false
  end
  local tname = UnitName("target")
  return (tname ~= nil and _WarriorProc.OP_target ~= nil and tname == _WarriorProc.OP_target)
end

local function _Warrior_Revenge_OK()
  return _Now() <= _WarriorProc.REV_until
end

_G["DoiteConditions_WarriorOverpowerOK"] = _Warrior_Overpower_OK
_G["DoiteConditions_WarriorRevengeOK"]   = _Warrior_Revenge_OK

-- ============================================================
-- Warrior proc tick (called from main file's OnUpdate)
-- ============================================================
local _isWarrior = false
do
  local _, cls = UnitClass("player")
  cls = cls and string.upper(cls) or ""
  _isWarrior = (cls == "WARRIOR")
end

local function _WarriorProcTick()
  if not _isWarrior then
    return
  end
  if _WarriorProc.REV_until <= 0 and _WarriorProc.OP_until <= 0 then
    return
  end

  local nowAbs = GetTime()

  if _WarriorProc.REV_until > 0 and nowAbs > _WarriorProc.REV_until then
    _WarriorProc.REV_until = 0
    _FireMarkDirty()
  end

  if _WarriorProc.OP_until > 0 and nowAbs > _WarriorProc.OP_until then
    _WarriorProc.OP_until = 0
    _FireMarkDirty()
  end
end

_G["DoiteConditions_WarriorProcTick"] = _WarriorProcTick