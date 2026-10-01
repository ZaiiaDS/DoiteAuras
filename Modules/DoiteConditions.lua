---------------------------------------------------------------
-- DoiteConditions.lua
-- Evaluates ability and aura conditions to show/hide/update icons
-- Please respect license note: Ask permission
-- WoW 1.12 | Lua 5.0
---------------------------------------------------------------

-- Reuse the table already created by sibling modules loaded before this
-- file (Target, Item, Slide, Proc, Spell, Icons, Auras). Overwriting
-- it here would drop every helper those modules registered.
local DoiteConditions = _G["DoiteConditions"] or {}
_G["DoiteConditions"] = DoiteConditions

-- GCD threshold used by slider / timer-text logic.
-- Durations shorter than this are treated as pure GCD blips and ignored.
-- Stored on DoiteConditions (not a file-local) because this file is at
-- Lua 5.0's 200-local limit.
DoiteConditions._GCD_THRESHOLD = 1.6

-- Runtime-only per-key custom-function state (the table user code writes
-- into). Never persisted, because user code can store frames, userdata
-- and functions inside.
DoiteConditions._customStateByKey = DoiteConditions._customStateByKey or {}

-- Per-key rate-limit timestamp for the shatter wait path. See
-- _HandleAbilityShatter: RequestImmediateEval is a FULL EvaluateAll, and
-- without a limit it fires every frame while a shatter is armed. 10 Hz
-- is plenty for detecting the entry into the window.
DoiteConditions._shatterWaitAt = DoiteConditions._shatterWaitAt or {}

-- Two-pass cleanup: collect keys whose value isn't a table, then delete
-- them. Never mutate a table during pairs() — that's UB in Lua 5.0.
-- Stored on DoiteConditions (not a file-local) because of the local limit.
function DoiteConditions._PruneBadEntries(t)
  if not t then return end

  local scratch = _G["DoiteConditions_PruneScratch"]
  if not scratch then
    scratch = {}
    _G["DoiteConditions_PruneScratch"] = scratch
  end

  -- wipe scratch (contiguous 1..N; safe in place)
  local n = 1
  while scratch[n] ~= nil do
    scratch[n] = nil
    n = n + 1
  end

  local cnt = 0
  local k, v
  for k, v in pairs(t) do
    if type(v) ~= "table" then
      cnt = cnt + 1
      scratch[cnt] = k
    end
  end

  if cnt == 0 then
    return
  end

  local i = 1
  while i <= cnt do
    t[scratch[i]] = nil
    scratch[i] = nil
    i = i + 1
  end
end

if not _G["DoiteAurasDB"] then
  _G["DoiteAurasDB"] = {}
end

DoiteAurasDB = _G["DoiteAurasDB"]
DoiteAurasDB.cache = DoiteAurasDB.cache or {}
DoiteAurasCacheDB = DoiteAurasDB.cache
local IconCache = DoiteAurasDB.cache

local GetTime = GetTime
local UnitBuff = UnitBuff
local UnitDebuff = UnitDebuff
local UnitExists = UnitExists
local UnitIsFriend = UnitIsFriend
local UnitCanAttack = UnitCanAttack
local UnitIsUnit = UnitIsUnit
local UnitClass = UnitClass
local UnitMana = UnitMana
local GetNumTalents = GetNumTalents
local GetTalentInfo = GetTalentInfo
local str_find = string.find
local str_gsub = string.gsub

-- Sound helpers + spell-name/texture cache + icon-frame getter moved to
-- Modules/DoiteConditionsIcons.lua. Local aliases added at the top of this file.

-- Defined in Modules/DoiteConditionsTarget.lua (loaded before this file).
-- Cached as a file-local to keep call sites cheap.
local _NormalizeTargetField = _G["DoiteConditions_NormalizeTargetField"]

-- Defined in Modules/DoiteConditionsItem.lua (loaded before this file).
-- Cached as file-locals so call sites stay cheap.
local _SlotIndexForName       = DoiteConditions._SlotIndexForName
local _TrinketFirstMemory     = DoiteConditions._TrinketFirstMemory
local _GetInventorySlotState  = DoiteConditions._GetInventorySlotState
local _EvaluateItemCoreState  = DoiteConditions._EvaluateItemCoreState

-- Defined in Modules/DoiteSlide.lua (loaded before this file).
-- Cached as a file-local for hot-path access in _HandleAbilitySlider
-- and ApplyVisuals.
local SlideMgr = _G["DoiteConditions_SlideMgr"]

-- Weapon-slot constants (used by _EnsureItemTexture + event handlers).
-- Kept as locals here even though the item module also has them: they
-- are just numbers and duplicating them avoids a table lookup on every
-- inventory event.
local INV_SLOT_TRINKET1 = 13
local INV_SLOT_TRINKET2 = 14
local INV_SLOT_MAINHAND = 16
local INV_SLOT_OFFHAND  = 17
local INV_SLOT_RANGED   = 18

-- Spell/cooldown helpers moved to Modules/DoiteConditionsSpell.lua.
-- Local aliases for hot-path use below.
local _GetSpellIndexByName     = _G["DoiteConditions_GetSpellIndexByName"]
local _AbilityRemainingSeconds = _G["DoiteConditions_AbilityRemainingSeconds"]
local _AbilityCooldownByName   = _G["DoiteConditions_GetAbilityCooldown"]
local _IsSpellOnCooldown       = _G["DoiteConditions_IsSpellOnCooldown"]
local _SafeSpellUsable         = _G["DoiteConditions_SafeSpellUsable"]

-- Icon-frame + texture + sound helpers moved to Modules/DoiteConditionsIcons.lua.
-- Local aliases for hot-path use below.
local _GetIconFrame            = _G["DoiteConditions_GetIconFrame"]
local _ForgetIconFrame         = _G["DoiteConditions_ForgetIconFrame"]
local _DoiteHandleEdgeSound    = _G["DoiteConditions_HandleEdgeSound"]
local _EnsureAbilityTexture    = _G["DoiteConditions_EnsureAbilityTexture"]
local _EnsureItemTexture       = _G["DoiteConditions_EnsureItemTexture"]

-- Aura-scanning + entry-check helpers moved to Modules/DoiteConditionsAuras.lua.
-- Local aliases for hot-path use below.
local _ScanTargetUnitAuras     = _G["DoiteConditions_ScanUnitAuras"]
local _TargetHasAura           = _G["DoiteConditions_TargetHasAura"]
local _TargetHasAuraBySpellId  = _G["DoiteConditions_TargetHasAuraBySpellId"]
local _TargetHasAnyBuffName    = _G["DoiteConditions_TargetHasAnyBuffName"]
local _StacksPasses            = _G["DoiteConditions_StacksPasses"]
local _GetAuraStacksOnUnit     = _G["DoiteConditions_GetAuraStacksOnUnit"]
local _AuraConditions_CheckEntry = _G["DoiteConditions_AuraConditionsCheckEntry"]
local _EnsureAuraTexture       = _G["DoiteConditions_EnsureAuraTexture"]
local _SoundStateByKey         = _G["DoiteConditions_SoundStateByKey"]

-- Dirty flags used by the central update loop
local dirty_ability = false
local dirty_aura = false
local dirty_target = false
local dirty_power = false
local dirty_ability_time = false

-- Coalesced aura scans (set in events; consumed in OnUpdate)
DoiteConditions._pendingAuraScanTarget = false

----------------------------------------------------------------
-- One-shot repaint next frame (avoids re-entrancy inside events)
----------------------------------------------------------------

-- Forward declare so functions defined above can capture it as an upvalue
local _RequestImmediateEval

local _DoiteImmediateEval = CreateFrame("Frame", "DoiteImmediateEval")
_DoiteImmediateEval:Hide()
_DoiteImmediateEval._pending = false
_DoiteImmediateEval:SetScript("OnUpdate", function()
  this:Hide()
  this._pending = false

  dirty_ability = true
  dirty_aura = true
  dirty_target = true
  dirty_power = true
  dirty_ability_time = true

  if DoiteConditions and DoiteConditions.EvaluateAll then
    DoiteConditions:EvaluateAll()
  end

  if DoiteGroup then
    _G["DoiteGroup_NeedReflow"] = true
  end
end)

_RequestImmediateEval = function()
  if _DoiteImmediateEval._pending then
    return
  end
  _DoiteImmediateEval._pending = true
  _DoiteImmediateEval:Show()
end

_G.DoiteConditions_RequestImmediateEval = _RequestImmediateEval

-- Install handlers for DoiteConditionsProc.lua so it can mark our
-- file-local dirty flags without reaching into upvalues.
do
  local proc = _G["DoiteConditionsProc"]
  if proc and proc.SetHandlers then
    proc.SetHandlers(function()
      dirty_ability = true
      dirty_ability_time = true
    end, _RequestImmediateEval)
  end
end

-- Install handler for DoiteConditionsAuras.lua (_EnsureAuraTexture fallback).
do
  local setup = _G["DoiteConditionsAuras_SetHandlers"]
  if setup then
    setup(function()
      dirty_aura = true
    end)
  end
end

local DG = _G["DoiteGlow"]

-- NOTE: DoiteConditions.lua is at Lua 5.0's 200-file-local limit.
-- New helpers must be declared as table methods, not file-scope locals.
DoiteConditions._RefreshEditStateCache = function()
  local testAll = (_G["DoiteAuras_TestAll"] == true)
  if testAll then
    _G.DoiteConditions_EditOpen = true
    _G.DoiteConditions_EditKey  = nil
    DoiteConditions._editOpenCached = true
    DoiteConditions._editKeyCached  = nil
    return
  end

  local cur = _G["DoiteEdit_CurrentKey"]
  if not cur then
    _G.DoiteConditions_EditOpen = false
    _G.DoiteConditions_EditKey  = nil
    DoiteConditions._editOpenCached = false
    DoiteConditions._editKeyCached  = nil
    return
  end

  local f = _G["DoiteEdit_Frame"] or _G["DoiteEditMain"] or _G["DoiteEdit"]
  local open = true
  if f and f.IsShown then
    open = (f:IsShown() == 1)
  end
  _G.DoiteConditions_EditOpen = open and true or false
  _G.DoiteConditions_EditKey  = open and cur or nil
  DoiteConditions._editOpenCached = open and true or false
  DoiteConditions._editKeyCached  = open and cur or nil
end

-- NOTE: DoiteConditions.lua is at Lua 5.0's 200-file-local limit.
-- The two helpers below are declared as globals to avoid burning
-- local slots. Their values are cached by _RefreshEditStateCache
-- so per-icon, per-tick code never has to touch _G.
DoiteConditions._editOpenCached = false
DoiteConditions._editKeyCached  = nil

function _Doite_IsKeyUnderEdit(k)
  if not k then return false end
  return DoiteConditions._editOpenCached == true
     and DoiteConditions._editKeyCached == k
end

function _Doite_IsAnyKeyUnderEdit()
  return DoiteConditions._editOpenCached == true
end

----------------------------------------------------------------
-- Edit-mode heartbeat: force frequent refresh while editor is open (prevents 0.5s delay / "needs a target" when idle)
----------------------------------------------------------------
local _editTick = CreateFrame("Frame", "DoiteEditTick")
local _editAccum = 0

-- Tuning: 0.10 feels instant but is still cheap.
local DOITE_EDIT_TICK = 0.10

_editTick:SetScript("OnUpdate", function()
  if not _Doite_IsAnyKeyUnderEdit() then
    _editAccum = 0
    return
  end

  -- Skip refresh while user is dragging icons or frames (prevents update loop)
  if _G["DoiteUI_Dragging"] then
    return
  end

  _editAccum = _editAccum + (arg1 or 0)
  if _editAccum < DOITE_EDIT_TICK then
    return
  end
  _editAccum = 0

  -- skip if editor hidden or zero visible icons
  local f = _G["DoiteEdit_Frame"]
  if not (f and f:IsShown()) then
    return
  end
  _editAccum = 0

  -- Force the normal pipeline to run even when the player is idle.
  dirty_ability = true
  dirty_aura = true
  dirty_target = true
  dirty_power = true
  dirty_ability_time = true
end)

---------------------------------------------------------------
-- Local helpers
---------------------------------------------------------------

local function InCombat()
  return UnitAffectingCombat("player") == 1
end

local function InRaid()
  return (GetNumRaidMembers() or 0) > 0
end

local function InPartyOnly()
  -- party, but not raid
  return (GetNumPartyMembers() or 0) > 0 and not InRaid()
end

local function InGroup()
  return InRaid() or (GetNumPartyMembers() or 0) > 0
end

-- Power percent (0..100)
local function GetPowerPercent()
  local max = UnitManaMax("player")
  if not max or max <= 0 then
    return 0
  end
  local cur = UnitMana("player")
  return (cur * 100) / max
end

-- === Remaining-time helpers ===

-- Compare helper: returns true if rem (seconds) passes comp vs target (seconds)
local function _RemainingPasses(rem, comp, target)
  if not rem or not comp or target == nil then
    return true
  end
  if comp == ">=" then
    return rem >= target
  elseif comp == "<=" then
    return rem <= target
  elseif comp == "==" then
    return rem == target
  end
  return true
end

-- === Item helpers (inventory / bag lookup & cooldown) =======================
-- All item helpers have been moved to Modules/DoiteConditionsItem.lua.
-- Public entry points used below:
--   DoiteConditions._EvaluateItemCoreState  (aliased at the top of this file)
--   DoiteConditions._GetInventorySlotState  (aliased at the top of this file)
--   DoiteConditions._SlotIndexForName       (aliased at the top of this file)
--   DoiteConditions._TrinketFirstMemory     (aliased at the top of this file)
--   DoiteConditions.INV_SLOT_*              (constants, redeclared locally)
--   DoiteConditions.DOITE_ITEM_CD_IGNORE    (constant, used only inside module)

-- Called from DoiteAuras.lua when an icon is removed from the DB.
-- Prevents _SoundStateByKey / _TrinketFirstMemory / _ProcLastShowByKey
-- from growing without bound across add/remove cycles.
_G.DoiteConditions_CleanupKey = function(key)
  if not key then return end
  local ss = _G.DoiteConditions_SoundStateByKey
  if ss then ss[key] = nil end
  _TrinketFirstMemory[key] = nil
  if _G.DoiteConditions_ProcLastShowByKey then
    _G.DoiteConditions_ProcLastShowByKey[key] = nil
  end
  if DoiteConditions and DoiteConditions._customStateByKey then
    DoiteConditions._customStateByKey[key] = nil
  end
  -- Compiled custom functions live in a runtime-only map (not SV);
  -- drop the entry so the map cannot accumulate functions for keys
  -- that no longer exist.
  if DoiteConditions and DoiteConditions._customCompiledByKey then
    DoiteConditions._customCompiledByKey[key] = nil
  end
  -- Shatter manager may still have pieces and a hidden icon texture
  -- attached to this key; release them so they are not orphaned.
  local SM = _G["DoiteShatter_Mgr"]
  if SM then
    if SM:IsActive(key) then SM:Stop(key) end
    SM._fired[key] = nil
  end
  -- Drop the wait-path rate-limit timestamp too; otherwise it lingers
  -- for the lifetime of the session on every removed key.
  if DoiteConditions._shatterWaitAt then
    DoiteConditions._shatterWaitAt[key] = nil
  end
  -- Release any pop overlay state for this key.
  local DP = _G["DoitePop"]
  if DP and DP.CleanupKey then
    DP.CleanupKey(key)
  end
end

-- =================================================================
-- Slider check
-- =================================================================

-- For slider gating: which spells have we actually seen cast?
_G["Doite_SliderSeen"] = _G["Doite_SliderSeen"] or {}

local function _MarkSliderSeen(spellName)
  if not spellName or spellName == "" then
    return
  end
  Doite_SliderSeen[spellName] = GetTime() or 0
end

-- =================================================================
-- Shared-category cooldown tracking.
--
-- Vanilla's GetSpellCooldown returns 0/0 for ability A while ability B
-- (same spell `category` from GetSpellRec) is on cooldown from a
-- recent cast. We track shared CDs ourselves: on SPELL_GO_SELF we look
-- up the spell's record via GetSpellRec, read its `category` and
-- `categoryRecoveryTime`, and remember when that category last went
-- on CD. Later, _IsSpellOnCooldown / _AbilityRemainingSeconds /
-- _AbilityCooldownByName consult this record when the client tells
-- them "not on cooldown".
--
-- Works for any class/ability pair the client itself groups together
-- (Paladin Holy/Crusader Strike, Warrior shared CDs, Hunter shot
-- recovery, etc.). Nothing hardcoded per spell.
-- =================================================================

-- spellName -> { cat = N, dur = seconds } | false (looked up, no shared CD)
DoiteConditions._abilityCategoryCache = DoiteConditions._abilityCategoryCache or {}
-- category -> { startTime = GetTime(), dur = seconds }
DoiteConditions._sharedCDByCategory = DoiteConditions._sharedCDByCategory or {}

-- Public helper used by DoiteConditionsSpell.lua.
function DoiteConditions._GetAbilityCategoryInfo(spellName)
  if not spellName or spellName == "" then
    return nil, nil
  end
  local cached = DoiteConditions._abilityCategoryCache[spellName]
  if cached ~= nil then
    if cached == false then return nil, nil end
    return cached.cat, cached.dur
  end

  if type(GetSpellIdForName) ~= "function" then
    DoiteConditions._abilityCategoryCache[spellName] = false
    return nil, nil
  end

  local okId, id = pcall(GetSpellIdForName, spellName)
  local sid = okId and tonumber(id) or 0
  if sid <= 0 then
    DoiteConditions._abilityCategoryCache[spellName] = false
    return nil, nil
  end

  local cat, durMs = nil, nil

  -- Path A (preferred): GetSpellRec returns the whole spell record as
  -- a table on TurtleWoW / Nampower clients. One call, all fields, no
  -- "Unknown field name" surprises. Field names as exposed on this
  -- client: `category`, `categoryRecoveryTime` (milliseconds).
  if type(GetSpellRec) == "function" then
    local okRec, rec = pcall(GetSpellRec, sid)
    if okRec and type(rec) == "table" then
      local c = tonumber(rec.category) or 0
      local d = tonumber(rec.categoryRecoveryTime) or 0
      if c > 0 and d > 0 then
        cat = c
        durMs = d
      end
    end
  end

  -- Path B (fallback): per-field lookup via GetSpellRecField. Only
  -- reached if GetSpellRec is missing or lacks the fields. On clients
  -- where GetSpellRecField rejects these names, this returns nil and
  -- we degrade gracefully (shared-CD fallback just stays off).
  if not cat and type(GetSpellRecField) == "function" then
    local function _readField(nameA, nameB)
      local okA, vA = pcall(GetSpellRecField, sid, nameA)
      if okA and vA ~= nil then return tonumber(vA) end
      if nameB then
        local okB, vB = pcall(GetSpellRecField, sid, nameB)
        if okB and vB ~= nil then return tonumber(vB) end
      end
      return nil
    end

    local c = _readField("category", "Category")
              or _readField("spellCategory", "SpellCategory")
              or 0
    local d = _readField("categoryRecoveryTime", "CategoryRecoveryTime") or 0
    if c > 0 and d > 0 then
      cat = c
      durMs = d
    end
  end

  if not cat or not durMs or cat <= 0 or durMs <= 0 then
    DoiteConditions._abilityCategoryCache[spellName] = false
    return nil, nil
  end

  local info = { cat = cat, dur = durMs / 1000 }
  DoiteConditions._abilityCategoryCache[spellName] = info
  return info.cat, info.dur
end

-- Public: remaining seconds (and full duration) on the shared category
-- cooldown for this spell, or nil if none active. Used as fallback by
-- _IsSpellOnCooldown / _AbilityRemainingSeconds / _AbilityCooldownByName.
function DoiteConditions._GetSharedCDRemaining(spellName)
  local cat = DoiteConditions._GetAbilityCategoryInfo(spellName)
  if not cat then return nil, nil end

  local rec = DoiteConditions._sharedCDByCategory[cat]
  if not rec then return nil, nil end

  local now = (GetTime and GetTime()) or 0
  local rem = (rec.startTime + rec.dur) - now
  if rem <= 0 then
    DoiteConditions._sharedCDByCategory[cat] = nil
    return nil, nil
  end
  return rem, rec.dur
end

-- Proc-window helpers + class procs moved to Modules/DoiteConditionsProc.lua.
-- Local aliases for hot-path use below.
local _ProcWindowDuration  = _G["DoiteConditions_ProcWindowDuration"]
local _ProcWindowSet       = _G["DoiteConditions_ProcWindowSet"]
local _ProcWindowRemaining = _G["DoiteConditions_ProcWindowRemaining"]
local _Warrior_Overpower_OK = _G["DoiteConditions_WarriorOverpowerOK"]
local _Warrior_Revenge_OK   = _G["DoiteConditions_WarriorRevengeOK"]
-- Canonical ability name resolver (spellbook name preferred)
local function _GetCanonicalSpellNameFromData(data)
  if not data or type(data) ~= "table" then
    return nil
  end
  if data.name and data.name ~= "" then
    -- This is the canonical spellbook name (what GetSpellName sees)
    return data.name
  end
  if data.displayName and data.displayName ~= "" then
    return data.displayName
  end
  return nil
end

-- Start the cast-confirmation pop animation for every currently
-- visible Ability icon whose spell matches spellName. Only icons
-- whose frame is already shown (ready) pop, matching the "cast on
-- a ready icon" visual. Items / auras are ignored by design.
function DoiteConditions._StartPopForSpellName(spellName)
  if not spellName or spellName == "" then return end
  local DP = _G["DoitePop"]
  if not DP or not DP.Start then return end
  local live = DoiteAurasDB and DoiteAurasDB.spells
  if not live then return end

  local key, data
  for key, data in pairs(live) do
    if type(data) == "table"
       and data.type == "Ability"
       and _GetCanonicalSpellNameFromData(data) == spellName then

      local frame = _GetIconFrame(key)
      if frame
         and frame._daLastShown == true
         and (not DP.IsActive(key)) then
        DP.Start(key, frame)
      end
    end
  end
end

-- =================================================================
-- Nampower: SPELL_GO_SELF -> cooldown ownership (PLAYER ONLY)
-- Only used to gate "soon off CD" sliders so shared-CD abilities
-- don't show sliders unless the player actually cast them.
-- =================================================================

-- Nampower gates these events behind NP_EnableSpellGoEvents (default 0).
-- Enable if available; harmless if CVars are missing.
do
  if GetCVar and SetCVar then
    local ok, v = pcall(GetCVar, "NP_EnableSpellGoEvents")
    if ok and v and tostring(v) == "0" then
      pcall(SetCVar, "NP_EnableSpellGoEvents", "1")
    end
  end
end

local _daCast = CreateFrame("Frame", "DoiteCast")
_daCast:RegisterEvent("SPELL_GO_SELF")
_daCast:SetScript("OnEvent", function()
  -- SPELL_GO_SELF params (Nampower):
  -- arg1=itemId (0 if not item-triggered)
  -- arg2=spellId
  local itemId = arg1
  local spellId = arg2

  -- Only track real spell casts for slider ownership (ignore item-triggered)
  if itemId and itemId ~= 0 then
    return
  end
  if not spellId then
    return
  end

  -- Nampower id->name mapping
  local name = nil
  if GetSpellNameAndRankForId then
    local n = GetSpellNameAndRankForId(spellId)
    if type(n) == "string" and n ~= "" then
      name = n
    end
  end

  if not name or name == "" then
    return
  end

  -- debug: last GO_SELF seen
  Doite_LastGoSelfId = spellId
  Doite_LastGoSelfName = name

  _MarkSliderSeen(name)

  -- Cast-confirmation pop: overlay on every visible Ability icon
  -- whose spell matches. Runs before the shared-CD bookkeeping so
  -- a spell without a DBC category still pops.
  DoiteConditions._StartPopForSpellName(name)

  -- Record shared-category cooldown so sibling abilities see it too.
  -- See DoiteConditions._GetAbilityCategoryInfo for the record lookup.
  local cat, cdDur = DoiteConditions._GetAbilityCategoryInfo(name)
  if cat and cdDur and cdDur > 0 then
    DoiteConditions._sharedCDByCategory[cat] = {
      startTime = (GetTime and GetTime()) or 0,
      dur = cdDur,
    }

    -- Mark every sibling (same DBC category) as "seen for this CD".
    -- _HandleAbilitySlider requires Doite_SliderSeen[spellName] to be
    -- recent before allowing a slide, to avoid showing slides for
    -- unrelated cooldowns. Without this loop, casting HS would leave
    -- CS's slide dormant because CS itself was never cast.
    if type(GetNumSpellTabs) == "function"
        and type(GetSpellTabInfo) == "function"
        and type(GetSpellName) == "function" then
      local tab = 1
      local numTabs = GetNumSpellTabs() or 0
      while tab <= numTabs do
        local _, _, offset, num = GetSpellTabInfo(tab)
        if num and num > 0 then
          local i = 1
          while i <= num do
            local idx = offset + i
            local nm = GetSpellName(idx, BOOKTYPE_SPELL)
            if nm and nm ~= "" and nm ~= name then
              local sc = DoiteConditions._GetAbilityCategoryInfo(nm)
              if sc == cat then
                _MarkSliderSeen(nm)
              end
            end
            i = i + 1
          end
        end
        tab = tab + 1
      end
    end
  end

  -- Force immediate re-evaluation of every icon. Without this, a
  -- sibling whose client-side GetSpellCooldown stays at 0/0 would
  -- only refresh on SPELL_UPDATE_COOLDOWN (may not fire for a
  -- foreign spell) or on the 0.5s heartbeat (up to half a second
  -- of stale "ready" display after the cast).
  dirty_ability = true
end)

----------------------------------------------------------------
-- DoiteAuras Slide Manager
-- Moved to Modules/DoiteSlide.lua (loaded before this file).
-- The table is aliased locally at the top of this file as `SlideMgr`.
----------------------------------------------------------------

-- Bridge: DoiteSlide.lua calls back into us when slides are active, so
-- its per-frame tick can keep our file-local `dirty_ability` flipped
-- without reaching into this file's upvalues directly.
do
  local mod = _G["DoiteSlide"]
  if mod and mod.SetMarkDirtyHandler then
    mod.SetMarkDirtyHandler(function()
      dirty_ability = true
    end)
  end
end

-- Same bridge for the shatter effect (DoiteShatter.lua).
do
  local mod = _G["DoiteShatter"]
  if mod and mod.SetMarkDirtyHandler then
    mod.SetMarkDirtyHandler(function()
      dirty_ability = true
    end)
  end
end

-- Read the baseline (saved) XY for an icon (matches CreateOrUpdateIcon layout precedence)
local function _GetBaseXY(key, dataTbl)
  -- defaults
  local x, y = 0, 0

  -- primary source: DoiteAurasDB.spells
  if DoiteAurasDB and DoiteAurasDB.spells and key and DoiteAurasDB.spells[key] then
    local s = DoiteAurasDB.spells[key]
    x = s.offsetX or s.x or x
    y = s.offsetY or s.y or y
  end

  -- optional override: legacy DoiteDB.icons layout (if present)
  if DoiteDB and DoiteDB.icons and key and DoiteDB.icons[key] then
    local L = DoiteDB.icons[key]
    x = (L.posX or L.offsetX or x)
    y = (L.posY or L.offsetY or y)
  end

  return x, y
end

-- Player-only aura remaining (seconds); nil if not timed / not found.
local function _PlayerAuraRemainingSeconds(auraName, auraSpellId, addedViaSpellId)
  local useSpellIdOnly = (addedViaSpellId == true)
  local playerAuraSlot = nil

  if useSpellIdOnly then
    local sid = tonumber(auraSpellId) or 0
    if sid > 0 then
      playerAuraSlot = DoitePlayerAuras.GetActiveAuraSlotBySpellId(sid)
    end
  else
    if not auraName then
      return nil
    end
    playerAuraSlot = DoitePlayerAuras.GetActiveAuraSlot(auraName)
  end

  if playerAuraSlot then
    local _, remainingMs, _ = GetPlayerAuraDuration(playerAuraSlot)
    if remainingMs and remainingMs > 0 then
      return remainingMs / 1000
    end
  end

  if not useSpellIdOnly then
    local remaining = DoitePlayerAuras.GetHiddenBuffRemaining(auraName)
    if remaining and remaining > 0 then
      return remaining
    end
  end

  return nil
end

local function _ResolvePlayerAuraTextOverride(overrideValue, fallbackName, fallbackSpellId, fallbackUseSpellId)
  local v = overrideValue
  if type(v) == "string" then
    v = str_gsub(v, "^%s*(.-)%s*$", "%1")
    if v == "" then
      v = nil
    end
  else
    v = nil
  end

  if not v then
    return fallbackName, fallbackSpellId, fallbackUseSpellId
  end

  local sid = tonumber(v)
  if sid and sid > 0 then
    return fallbackName, sid, true
  end

  return v, 0, false
end

local function _DoiteTrackAuraOwnership(spellKey, unit, useSpellId)
  if not DoiteTrack or not spellKey or not unit then
    return nil, false, nil, false, false, false
  end

  -- Hard dependency on the consolidated helper
  local rem, recording, sid, isMine, isOther, ownerKnown

  if useSpellId == true then
    if not DoiteTrack.GetAuraOwnershipBySpellId then
      return nil, false, nil, false, false, false
    end
    rem, recording, sid, isMine, isOther, ownerKnown = DoiteTrack:GetAuraOwnershipBySpellId(spellKey, unit)
  else
    if not DoiteTrack.GetAuraOwnershipByName then
      return nil, false, nil, false, false, false
    end
    rem, recording, sid, isMine, isOther, ownerKnown = DoiteTrack:GetAuraOwnershipByName(spellKey, unit)
  end

  -- Normalize booleans
  isMine = (isMine == true)
  isOther = (isOther == true)

  local known = (ownerKnown == true) or isMine or isOther

  -- Normalise remaining time
  if rem ~= nil and rem <= 0 then
    rem = nil
  end

  -- For non-player units, if ownership is known and it's NOT mine, don't expose remaining
  if known and unit ~= "player" and (not isMine) then
    rem = nil
    recording = false
  end

  return rem, recording, sid, isMine, isOther, known
end

-- Unified remaining-time provider used by existing call sites (DoiteTrack only).
local function _DoiteTrackAuraRemainingSeconds(spellKey, unit, useSpellId)
  if not DoiteTrack or not spellKey or not unit then
    return nil
  end

  if useSpellId == true and DoiteTrack.GetAuraRemainingSecondsBySpellId then
    local rem = DoiteTrack:GetAuraRemainingSecondsBySpellId(spellKey, unit)
    if rem and rem > 0 then
      return rem
    end
  elseif DoiteTrack.GetAuraRemainingSecondsByName then
    local rem = DoiteTrack:GetAuraRemainingSecondsByName(spellKey, unit)
    if rem and rem > 0 then
      return rem
    end
  end

  if DoiteTrack.GetAuraRemainingOrRecordingByName then
    local rem2 = DoiteTrack:GetAuraRemainingOrRecordingByName(spellKey, unit)
    if rem2 and rem2 > 0 then
      return rem2
    end
  end

  return nil
end


-- Use DoiteTrack to evaluate a remaining-time comparison on a unit.
local function _DoiteTrackRemainingPass(spellKey, unit, comp, threshold, useSpellId)
  if not DoiteTrack or not spellKey or not unit or not comp or threshold == nil then
    return nil
  end

  if useSpellId == true and DoiteTrack.RemainingPassesBySpellId then
    return DoiteTrack:RemainingPassesBySpellId(spellKey, unit, comp, threshold)
  elseif DoiteTrack.RemainingPassesByName then
    -- Add-on helper handles comparison internally
    return DoiteTrack:RemainingPassesByName(spellKey, unit, comp, threshold)
  end

  -- Fallback within DoiteTrack: if no helper, compare using numeric remaining
  local rem = _DoiteTrackAuraRemainingSeconds(spellKey, unit, useSpellId)
  if rem and rem > 0 then
    return _RemainingPasses(rem, comp, threshold)
  end

  return nil
end

-- _EvaluateAuraConditionsList moved to Modules/DoiteConditionsAuras.lua.
-- The public wrapper DoiteConditions_EvaluateAuraConditionsList is still global.

-- === Health / Combo Points / Formatting helpers ===

-- Percent HP (0..100) for unit; returns nil if unit invalid or no maxhp
local function _HPPercent(unit)
  if not unit or not UnitExists(unit) then
    return nil
  end
  local cur = UnitHealth(unit)
  local max = UnitHealthMax(unit)
  if not cur or not max or max <= 0 then
    return nil
  end
  return (cur * 100) / max
end

-- Compare helper: returns true if 'val' satisfies 'comp' vs 'target'
local function _ValuePasses(val, comp, target)
  if val == nil or comp == nil or target == nil then
    return true
  end
  if comp == ">=" then
    return val >= target
  elseif comp == "<=" then
    return val <= target
  elseif comp == "==" then
    return val == target
  end
  return true
end

-- Combo points reader
local function _GetComboPointsSafe()
  if not UnitExists("target") then
    return 0
  end
  local cp = GetComboPoints("player", "target")
  if not cp then
    return 0
  end
  return cp
end

-- Class that uses combo points
local function _PlayerUsesComboPoints()
  local _, cls = UnitClass("player")
  cls = cls and string.upper(cls) or ""
  return (cls == "ROGUE" or cls == "DRUID")
end

-- Target / distance / weapon / form helpers live in
-- Modules/DoiteConditionsTarget.lua (public DoiteConditions_* names).
-- Texture resolvers live in Icons / Auras modules.

-- === Time-logic helpers (for heartbeat pruning) =================

-- Does an Ability icon use any time-based features?
local function _IconHasTimeLogic_Ability(data)
  if not data or not data.conditions or not data.conditions.ability then
    return false
  end
  local c = data.conditions.ability

  -- Existing reasons
  if c.textTimeRemaining == true then
    return true
  end
  if c.remainingEnabled == true then
    return true
  end

  -- Slider / shatter needs the 0.5 s heartbeat to detect the moment a
  -- cooldown crosses into its slide window even when nothing else is
  -- dirty. We always register when a slider is enabled (slide uses it
  -- too). Cheap: only affects icons that opted in.
  if c.slider == true then
    return true
  end

  -- proc-window spells should tick (ONLY when mode == "usable")
  if c.mode == "usable" then
    local spellName = _GetCanonicalSpellNameFromData(data)
    if spellName and _ProcWindowDuration(spellName) then
      return true
    end
  end

  return false
end


-- Does an Item icon use any time-based features?
local function _IconHasTimeLogic_Item(data)
  if not data or not data.conditions or not data.conditions.item then
    return false
  end
  local c = data.conditions.item

  if c.mode == "oncd" or c.mode == "notcd" or c.mode == "both" then
    return true
  end

  if c.textTimeRemaining == true then
    return true
  end
  if c.remainingEnabled == true then
    return true
  end
  return false
end

-- Does a Buff/Debuff icon use any time-based features?
local function _IconHasTimeLogic_Aura(data)
  if not data or not data.conditions or not data.conditions.aura then
    return false
  end
  local c = data.conditions.aura
  if c.textTimeRemaining == true then
    return true
  end
  if c.remainingEnabled == true then
    return true
  end
  return false
end

-- Global flag: have ANY ability/item icons that need the 0.5s heartbeat?
local _hasAnyAbilityTimeLogic = false
-- Global flag: have ANY aura icons that need the 0.5s heartbeat?
local _hasAnyAuraTimeLogic = false
-- Global flag: do we have ANY reason to track target auras at all?
local _hasAnyTargetAuraUsage = true

-- ------------------------------------------------------------
-- Coalesced aura scan + timer rebuild (reduces UNIT_AURA bursts)
-- Stored as DoiteConditions methods to avoid adding more file-scope locals.
-- ------------------------------------------------------------

function DoiteConditions:_ClearTargetAuraSnapshot()
  local snap = _G["DoiteConditions_AuraSnapshot"]
  local s = snap and snap.target
  if s then
    local b, d = s.buffs, s.debuffs
    if b then
      for k in pairs(b) do
        b[k] = nil
      end
    end
    if d then
      for k in pairs(d) do
        d[k] = nil
      end
    end
    local bi, di = s.buffIds, s.debuffIds
    if bi then
      for k in pairs(bi) do
        bi[k] = nil
      end
    end
    if di then
      for k in pairs(di) do
        di[k] = nil
      end
    end
  end
end

function DoiteConditions:ProcessPendingAuraScans()
  -- Player aura scanning removed - now handled by DoitePlayerAuras event-driven tracking

  -- Target: scan if (and only if) target aura tracking is in use; else keep snapshot empty.
  if self._pendingAuraScanTarget then
    self._pendingAuraScanTarget = false

    if _hasAnyTargetAuraUsage and UnitExists and UnitExists("target") then
      _ScanTargetUnitAuras()
    else
      self:_ClearTargetAuraSnapshot()
    end
  end
end

-- Target facts cache
local _DA_TargetFacts = { exists = false, isSelf = false, isFriend = false, canAttack = false }

local function _DA_GetTargetFacts()
  local tf = _DA_TargetFacts
  local exists = UnitExists("target")
  tf.exists = exists and true or false

  if exists then
    tf.isSelf = UnitIsUnit("player", "target") and true or false
    tf.isFriend = UnitIsFriend("player", "target") and true or false
    tf.canAttack = UnitCanAttack("player", "target") and true or false
  else
    tf.isSelf, tf.isFriend, tf.canAttack = false, false, false
  end

  return tf
end

-- Expose internal helpers for modules loaded after this file
-- (DoiteConditionsOverlay, DoiteAuras.lua, etc.).
_G["DoiteConditions_GetIconFrame"]                  = _GetIconFrame
_G["DoiteConditions_GetTargetFacts"]                = _DA_GetTargetFacts
_G["DoiteConditions_PlayerAuraRemainingSeconds"]    = _PlayerAuraRemainingSeconds
_G["DoiteConditions_DoiteTrackAuraRemainingSeconds"] = _DoiteTrackAuraRemainingSeconds
_G["DoiteConditions_ResolvePlayerAuraTextOverride"] = _ResolvePlayerAuraTextOverride
_G["DoiteConditions_GetCanonicalSpellNameFromData"] = _GetCanonicalSpellNameFromData
_G["DoiteConditions_ProcWindowDuration"]            = _ProcWindowDuration
_G["DoiteConditions_ProcWindowRemaining"]           = _ProcWindowRemaining
_G["DoiteConditions_GetAuraStacksOnUnit"]           = _GetAuraStacksOnUnit

-- Cached key lists (rebuilt via *_Rebuild*HeartbeatFlag / DoiteConditions_RequestEvaluate).
-- Purpose: avoid scanning every icon table on the 0.5s heartbeat and avoid per-call closure allocations.
-- NOTE: These are runtime-only caches (not saved vars).
local _timeKeysAbilityItem_live = {}
local _timeKeysAbilityItem_edit = {}
local _timeKeysAura_live = {}
local _timeKeysAura_edit = {}
local _DA_EMPTY_TABLE = {}

local function _WipeArray(t)
  local n = table.getn(t)
  while n > 0 do
    t[n] = nil
    n = n - 1
  end
end

local function _RebuildAbilityTimeHeartbeatFlag()
  _hasAnyAbilityTimeLogic = false

  -- Rebuild runtime-only key lists so 0.5s heartbeat passes don't scan every icon.
  _WipeArray(_timeKeysAbilityItem_live)
  _WipeArray(_timeKeysAbilityItem_edit)

  -- 1) Runtime icons
  if DoiteAurasDB and DoiteAurasDB.spells then
    local key, data
    for key, data in pairs(DoiteAurasDB.spells) do
      if type(data) == "table" and data.type then
        if data.type == "Ability" then
          if _IconHasTimeLogic_Ability(data) then
            _hasAnyAbilityTimeLogic = true
            table.insert(_timeKeysAbilityItem_live, key)
          end
        elseif data.type == "Item" then
          if _IconHasTimeLogic_Item(data) then
            _hasAnyAbilityTimeLogic = true
            table.insert(_timeKeysAbilityItem_live, key)
          end
        end
      end
    end
  end

  -- 2) Editor icons (may overlap live keys; evaluation loops will skip live keys when needed)
  if DoiteDB and DoiteDB.icons then
    local key, data
    for key, data in pairs(DoiteDB.icons) do
      if type(data) == "table" and data.type then
        if data.type == "Ability" then
          if _IconHasTimeLogic_Ability(data) then
            _hasAnyAbilityTimeLogic = true
            table.insert(_timeKeysAbilityItem_edit, key)
          end
        elseif data.type == "Item" then
          if _IconHasTimeLogic_Item(data) then
            _hasAnyAbilityTimeLogic = true
            table.insert(_timeKeysAbilityItem_edit, key)
          end
        end
      end
    end
  end
end

local function _RebuildAuraTimeHeartbeatFlag()
  _hasAnyAuraTimeLogic = false

  -- Rebuild runtime-only key lists so 0.5s text/remaining updates don't scan every icon.
  _WipeArray(_timeKeysAura_live)
  _WipeArray(_timeKeysAura_edit)

  -- 1) Runtime icons
  if DoiteAurasDB and DoiteAurasDB.spells then
    local key, data
    for key, data in pairs(DoiteAurasDB.spells) do
      if type(data) == "table" and (data.type == "Buff" or data.type == "Debuff") then
        if _IconHasTimeLogic_Aura(data) then
          _hasAnyAuraTimeLogic = true
          table.insert(_timeKeysAura_live, key)
        end
      end
    end
  end

  -- 2) Editor icons (may overlap live keys; UpdateTimeText already skips live keys for editor set)
  if DoiteDB and DoiteDB.icons then
    local key, data
    for key, data in pairs(DoiteDB.icons) do
      if type(data) == "table" and (data.type == "Buff" or data.type == "Debuff") then
        if _IconHasTimeLogic_Aura(data) then
          _hasAnyAuraTimeLogic = true
          table.insert(_timeKeysAura_edit, key)
        end
      end
    end
  end
end

-- Helper on the table (not a file-local — Lua 5.0's 200-local budget):
-- does an auraConditions list contain any entry that reads a target unit?
-- Such entries pull textures/spellids from target-aura scans even when
-- the parent icon is self-only.
DoiteConditions._AuraListHasTargetEntry = function(list)
  if type(list) ~= "table" then return false end
  local n = table.getn(list)
  local i = 1
  while i <= n do
    local e = list[i]
    if type(e) == "table" and e.unit == "target" then
      return true
    end
    i = i + 1
  end
  return false
end

local function _RebuildAuraUsageFlags()
  _hasAnyTargetAuraUsage = false

  -- 1) Live icons
  if DoiteAurasDB and DoiteAurasDB.spells then
    local key, data
    for key, data in pairs(DoiteAurasDB.spells) do
      if type(data) == "table" then
        -- Any explicit Buff/Debuff icon that can ever point at target?
        if data.type == "Buff" or data.type == "Debuff" then
          local c = data.conditions and data.conditions.aura
          if c and (c.targetHarm or c.targetHelp) then
            _hasAnyTargetAuraUsage = true
            return
          end
        end

        -- Any extra aura condition on this ability that reads a target unit?
        local ca = data.conditions and data.conditions.ability
        if ca and ca.auraConditions and DoiteConditions._AuraListHasTargetEntry(ca.auraConditions) then
          _hasAnyTargetAuraUsage = true
          return
        end

        local ci = data.conditions and data.conditions.item
        if ci and ci.auraConditions and DoiteConditions._AuraListHasTargetEntry(ci.auraConditions) then
          _hasAnyTargetAuraUsage = true
          return
        end

        local cu = data.conditions and data.conditions.aura
        if cu and cu.auraConditions and DoiteConditions._AuraListHasTargetEntry(cu.auraConditions) then
          _hasAnyTargetAuraUsage = true
          return
        end
      end
    end
  end

  -- 2) Editor-only icons
  if DoiteDB and DoiteDB.icons then
    local key, data
    for key, data in pairs(DoiteDB.icons) do
      if type(data) == "table" then
        if data.type == "Buff" or data.type == "Debuff" then
          local c = data.conditions and data.conditions.aura
          if c and (c.targetHarm or c.targetHelp) then
            _hasAnyTargetAuraUsage = true
            return
          end
        end

        local ca = data.conditions and data.conditions.ability
        if ca and ca.auraConditions and DoiteConditions._AuraListHasTargetEntry(ca.auraConditions) then
          _hasAnyTargetAuraUsage = true
          return
        end

        local ci = data.conditions and data.conditions.item
        if ci and ci.auraConditions and DoiteConditions._AuraListHasTargetEntry(ci.auraConditions) then
          _hasAnyTargetAuraUsage = true
          return
        end

        local cu = data.conditions and data.conditions.aura
        if cu and cu.auraConditions and DoiteConditions._AuraListHasTargetEntry(cu.auraConditions) then
          _hasAnyTargetAuraUsage = true
          return
        end
      end
    end
  end
end

-- Global flags: do we have ANY icons that use targetDistance / targetUnitType?
local _hasAnyTargetMods_Ability = false
local _hasAnyTargetMods_Aura = false
local _hasAnyCustomLogic = false

-- Single source of truth: does this icon read targetDistance / targetUnitType?
-- bucketA is tried first; bucketB is an optional fallback (Ability and Item
-- historically shared the same flag, and old saves may carry both buckets).
local function _IconHasTargetMods(data, bucketA, bucketB)
  if not data or not data.conditions then
    return false
  end
  local c = data.conditions[bucketA]
  if not c and bucketB then
    c = data.conditions[bucketB]
  end
  if not c then
    return false
  end
  local td = _NormalizeTargetField(c.targetDistance)
  local tu = _NormalizeTargetField(c.targetUnitType)
  return (td ~= nil) or (tu ~= nil)
end

local function _RebuildTargetModsFlags()
  _hasAnyTargetMods_Ability = false
  _hasAnyTargetMods_Aura = false
  _hasAnyCustomLogic = false
  if DoiteConditions then
    DoiteConditions._hasAnyItemLogic = false
  end

  -- 1) Live icons
  if DoiteAurasDB and DoiteAurasDB.spells then
    for key, data in pairs(DoiteAurasDB.spells) do
      if type(data) == "table" and data.type then
        local hasItemLogic = false
        if data.type == "Custom" then
          _hasAnyCustomLogic = true
        end

        if data.type == "Item" then
          hasItemLogic = true
        else
          local bucketNames = { "ability", "aura", "item" }
          local b = 1
          while b <= table.getn(bucketNames) do
            local bucket = data.conditions and data.conditions[bucketNames[b]]
            if bucket then
              local auraList = bucket.auraConditions
              local vfxList = bucket.vfxConditions
              local i, entry

              if auraList and table.getn(auraList) > 0 then
                for i = 1, table.getn(auraList) do
                  entry = auraList[i]
                  if entry and entry.buffType == "ITEM" then
                    hasItemLogic = true
                    break
                  end
                end
              end

              if (not hasItemLogic) and vfxList and table.getn(vfxList) > 0 then
                for i = 1, table.getn(vfxList) do
                  entry = vfxList[i]
                  if entry and entry.buffType == "ITEM" then
                    hasItemLogic = true
                    break
                  end
                end
              end
            end

            if hasItemLogic then
              break
            end
            b = b + 1
          end
        end

        if hasItemLogic and DoiteConditions then
          DoiteConditions._hasAnyItemLogic = true
        end

        if (data.type == "Ability" or data.type == "Item")
            and _IconHasTargetMods(data, "ability", "item") then
          _hasAnyTargetMods_Ability = true
        end
        if (data.type == "Buff" or data.type == "Debuff")
            and _IconHasTargetMods(data, "aura") then
          _hasAnyTargetMods_Aura = true
        end
        if _hasAnyTargetMods_Ability and _hasAnyTargetMods_Aura and DoiteConditions and DoiteConditions._hasAnyItemLogic then
          return
        end
      end
    end
  end

  -- 2) Editor-only icons
  if DoiteDB and DoiteDB.icons then
    for key, data in pairs(DoiteDB.icons) do
      if type(data) == "table" and data.type then
        local hasItemLogic = false
        if data.type == "Custom" then
          _hasAnyCustomLogic = true
        end

        if data.type == "Item" then
          hasItemLogic = true
        else
          local bucketNames = { "ability", "aura", "item" }
          local b = 1
          while b <= table.getn(bucketNames) do
            local bucket = data.conditions and data.conditions[bucketNames[b]]
            if bucket then
              local auraList = bucket.auraConditions
              local vfxList = bucket.vfxConditions
              local i, entry

              if auraList and table.getn(auraList) > 0 then
                for i = 1, table.getn(auraList) do
                  entry = auraList[i]
                  if entry and entry.buffType == "ITEM" then
                    hasItemLogic = true
                    break
                  end
                end
              end

              if (not hasItemLogic) and vfxList and table.getn(vfxList) > 0 then
                for i = 1, table.getn(vfxList) do
                  entry = vfxList[i]
                  if entry and entry.buffType == "ITEM" then
                    hasItemLogic = true
                    break
                  end
                end
              end
            end

            if hasItemLogic then
              break
            end
            b = b + 1
          end
        end

        if hasItemLogic and DoiteConditions then
          DoiteConditions._hasAnyItemLogic = true
        end

        if (data.type == "Ability" or data.type == "Item")
            and _IconHasTargetMods(data, "ability", "item") then
          _hasAnyTargetMods_Ability = true
        end
        if (data.type == "Buff" or data.type == "Debuff")
            and _IconHasTargetMods(data, "aura") then
          _hasAnyTargetMods_Aura = true
        end
        if _hasAnyTargetMods_Ability and _hasAnyTargetMods_Aura and DoiteConditions and DoiteConditions._hasAnyItemLogic then
          return
        end
      end
    end
  end
end

local _DA_SWIFTMEND_NEEDS = { "Rejuvenation", "Regrowth" }

local function _ClampFadeAlpha(v)
  local n = tonumber(v)
  if not n then
    return 0
  end
  if n < 0 then
    return 0
  end
  if n > 1 then
    return 1
  end
  return n
end

local function _EvaluateVfxConditions(data)
  if not data or not data.conditions then
    return false, false, false, 0
  end

  -- Fast path: skip when the icon has no VFX conditions at all.
  -- _daHasVfx is set when vfxConditions are added; nil means "not yet
  -- computed". Both buckets are checked to avoid a false skip.
  if data._daHasVfx == nil then
    local hasVfx = false
    local ab = data.conditions.ability
    local au = data.conditions.aura
    local it = data.conditions.item
    if ab and ab.vfxConditions and table.getn(ab.vfxConditions) > 0 then hasVfx = true end
    if (not hasVfx) and au and au.vfxConditions and table.getn(au.vfxConditions) > 0 then hasVfx = true end
    if (not hasVfx) and it and it.vfxConditions and table.getn(it.vfxConditions) > 0 then hasVfx = true end
    data._daHasVfx = hasVfx or false
    if not hasVfx then
      return false, false, false, 0
    end
  elseif data._daHasVfx == false then
    return false, false, false, 0
  end

  local glowOut, greyOut = false, false
  local fadeOut, fadeAlphaOut = false, 0

  local tIdx, typeKey
  for tIdx = 1, 3 do
    if tIdx == 1 then
      typeKey = "ability"
    elseif tIdx == 2 then
      typeKey = "aura"
    else
      typeKey = "item"
    end

    local bucket = data.conditions[typeKey]
    local list = bucket and bucket.vfxConditions
    if list and table.getn(list) > 0 then
      local i, entry
      for i = 1, table.getn(list) do
        entry = list[i]
        if _AuraConditions_CheckEntry(entry) then
          if entry.glow then glowOut = true end
          if entry.grey then greyOut = true end
          if entry.fade then
            fadeOut = true
            local entryFadeAlpha = _ClampFadeAlpha(entry.fadeAlpha)
            if entryFadeAlpha > fadeAlphaOut then
              fadeAlphaOut = entryFadeAlpha
            end
          end
        end
      end
    end
  end

  return glowOut, greyOut, fadeOut, fadeAlphaOut
end

-- ============================================================
-- Ability condition evaluation
-- ============================================================
local function CheckAbilityConditions(data)
  if not data or not data.conditions or not data.conditions.ability then
    return true, false, false, false, 0 -- if no conditions, always show
  end
  local c = data.conditions.ability
  -- Consolidated context table: keeps local count lower while avoiding per-eval allocations.
  local ctx = data._daCtx
  if not ctx then
    ctx = {}
    data._daCtx = ctx
  end
  ctx.allowHelp = (c.targetHelp == true)
  ctx.allowHarm = (c.targetHarm == true)
  ctx.allowSelf = (c.targetSelf == true)
  ctx.spellName = _GetCanonicalSpellNameFromData(data)
  ctx.spellIndex = _GetSpellIndexByName(ctx.spellName)
  ctx.spellBookType = _G.DoiteConditions_SpellBookTypeCache[ctx.spellName]
  ctx.tf = nil

  -- While editing this key, force conditions to pass (always show).
  if _Doite_IsKeyUnderEdit(data.key) then
    local glow = (c.glow and true) or false
    local grey = (c.greyscale and true) or false
    local fade = (c.fade and true) or false
    local fadeAlpha = fade and _ClampFadeAlpha(c.fadeAlpha) or 0
    return true, glow, grey, fade, fadeAlpha
  end

  -- "show" now represents ALL NON-MODE conditions.
  local show = true
  data._daModeOk = true
  data._daSoundGate = nil

  -- === Slider guard for cooldown slider preview ========================
  data._daSliderGuard = nil

  -- Reuse a per-icon temp table; cannot use _daSliderGuard since it's later set to boolean.
  local _sg = data._daSliderGuardTmp
  if not _sg then
    _sg = {}
    data._daSliderGuardTmp = _sg
  end
  _sg.form, _sg.weapon, _sg.aura = nil, nil, nil

  if c.slider == true and (c.mode == "usable" or c.mode == "notcd") then
    local okSlider = true

    if c.form and c.form ~= "All" then
      _sg.form = DoiteConditions_PassesFormRequirement(c.form) and true or false
      if not _sg.form then
        okSlider = false
      end
    end

    if okSlider and c.weaponFilter and c.weaponFilter ~= "" then
      _sg.weapon = DoiteConditions_PassesWeaponFilter(c) and true or false
      if not _sg.weapon then
        okSlider = false
      end
    end

    if okSlider and c.auraConditions and table.getn(c.auraConditions) > 0 then
      _sg.aura = DoiteConditions_EvaluateAuraConditionsList(c.auraConditions) and true or false
      if not _sg.aura then
        okSlider = false
      end
    end

    data._daSliderGuard = okSlider and true or false
  end

  -- === 1. Cooldown / usability (MODE-ONLY) ===
  local spellName = ctx.spellName
  local spellIndex = ctx.spellIndex
  local bookType = ctx.spellBookType or BOOKTYPE_SPELL
  local onCdNow = false

  if not spellIndex then
    -- Not in book: no icon, no sound.
    data._daModeOk = false
    data._daSoundGate = false
    return false
  end

  onCdNow = _IsSpellOnCooldown(spellIndex, bookType, spellName) and true or false

  local mode = c.mode or "notcd"
  local usablePass = nil

  if mode == "usable" or mode == "usableoncd" then
    usablePass = true

    local _, cls = UnitClass("player")
    cls = cls and string.upper(cls) or ""

    if cls == "WARRIOR" and (spellName == "Overpower" or spellName == "Revenge") then
      if onCdNow then
        usablePass = false
      else
        local rage = UnitMana("player") or 0
        if rage < 5 then
          usablePass = false
        else
          if spellName == "Overpower" then
            usablePass = _Warrior_Overpower_OK() and true or false
          else
            usablePass = _Warrior_Revenge_OK() and true or false
          end
        end
      end
    else
      local usable, noMana = _SafeSpellUsable(spellName, spellIndex, bookType)
      if (usable ~= 1) or (noMana == 1) or onCdNow then
        usablePass = false
      else
        if cls == "DRUID" and spellName == "Swiftmend" then
          local needs = _DA_SWIFTMEND_NEEDS
          local ok = false

          if ctx.allowHelp and not ctx.allowSelf then
            if UnitExists("target")
                and UnitIsFriend("player", "target")
                and (not UnitIsUnit("player", "target")) then
              ok = _TargetHasAnyBuffName(needs)
            else
              ok = false
            end

          elseif ctx.allowSelf and not (ctx.allowHelp or ctx.allowHarm) then
            ok = false
            for _, name in pairs(needs) do
              if DoitePlayerAuras.IsActive(name) then
                ok = true
                break
              end
            end
          else
            if UnitExists("target") then
              if UnitIsUnit("player", "target") then
                ok = false
                for _, name in pairs(needs) do
                  if DoitePlayerAuras.IsActive(name) then
                    ok = true
                    break
                  end
                end
              elseif UnitIsFriend("player", "target") then
                ok = _TargetHasAnyBuffName(needs)
              else
                ok = false
              end
            else
              ok = false
            end
          end

          if not ok then
            usablePass = false
          end
        end
      end
    end
  end

  if mode == "usable" then
    data._daModeOk = usablePass and true or false
  elseif mode == "notcd" then
    data._daModeOk = (not onCdNow) and true or false
  elseif mode == "oncd" then
    data._daModeOk = onCdNow and true or false
  elseif mode == "usableoncd" then
    data._daModeOk = ((usablePass == true) or onCdNow) and true or false
  elseif mode == "nocdoncd" then
    -- NotCD OR OnCD is always true once the ability exists in spellbook.
    data._daModeOk = true
  end

  -- === Combat state (NON-MODE) ===
  local inCombatFlag = (c.inCombat == true)
  local outCombatFlag = (c.outCombat == true)

  if not (inCombatFlag and outCombatFlag) then
    if inCombatFlag and not InCombat() then
      show = false
    end
    if outCombatFlag and InCombat() then
      show = false
    end
  end

  -- === Grouping mode (NON-MODE) ===
  local grouping = c.grouping
  if grouping ~= nil and grouping ~= "any" then
    local groupOk = true
    if grouping == "nogroup" then
      groupOk = not InGroup()
    elseif grouping == "party" then
      groupOk = InPartyOnly()
    elseif grouping == "raid" then
      groupOk = InRaid()
    elseif grouping == "partyraid" then
      groupOk = InGroup()
    else
      groupOk = false
    end
    if not groupOk then
      show = false
    end
  end

  -- Cache target facts once per evaluation
  ctx.tf = _DA_GetTargetFacts()
  local tf = ctx.tf

  -- Target gating (NON-MODE)
  local ok = true
  if ctx.allowHelp or ctx.allowHarm or ctx.allowSelf then
    ok = false
    if ctx.allowSelf and tf.exists and tf.isSelf then
      ok = true
    end
    if (not ok) and ctx.allowHelp and tf.exists and tf.isFriend and (not tf.isSelf) then
      ok = true
    end
    if (not ok) and ctx.allowHarm and tf.exists and tf.canAttack and (not tf.isFriend) then
      ok = true
    end
  end
  if not ok then
    show = false
  end

  -- Target status / Distance / UnitType (NON-MODE)
  if show and (c.targetDistance or c.targetUnitType or c.targetAlive or c.targetDead) then
    local unitForTarget = nil
    if tf.exists then
      unitForTarget = "target"
    end
    if unitForTarget then
      if not DoiteConditions_PassesTargetStatus(c, unitForTarget) then
        show = false
      elseif not DoiteConditions_PassesTargetDistance(c, unitForTarget, spellName) then
        show = false
      elseif not DoiteConditions_PassesTargetUnitType(c, unitForTarget) then
        show = false
      end
    end
  end

  -- Form / stance (NON-MODE)
  if show and c.form and c.form ~= "All" then
    if _sg.form ~= nil then
      if not _sg.form then
        show = false
      end
    else
      if not DoiteConditions_PassesFormRequirement(c.form) then
        show = false
      end
    end
  end

  -- Weapon filter (NON-MODE)
  if show and c.weaponFilter and c.weaponFilter ~= "" then
    if _sg.weapon ~= nil then
      if not _sg.weapon then
        show = false
      end
    else
      if not DoiteConditions_PassesWeaponFilter(c) then
        show = false
      end
    end
  end

  -- HP (NON-MODE)
  if show and c.hpComp and c.hpVal and c.hpMode and c.hpMode ~= "" then
    local hpTarget = nil
    if c.hpMode == "my" then
      hpTarget = "player"
    elseif c.hpMode == "target" then
      if tf.exists then
        if (ctx.allowHelp or ctx.allowHarm or ctx.allowSelf) then
          local okHP = true
          if ctx.allowSelf then
            okHP = tf.isSelf
          elseif ctx.allowHelp then
            okHP = tf.isFriend and (not tf.isSelf)
          elseif ctx.allowHarm then
            okHP = tf.canAttack and (not tf.isFriend)
          end
          if okHP then
            hpTarget = "target"
          else
            hpTarget = nil
          end
        else
          hpTarget = "target"
        end
      end
    end

    if hpTarget then
      local pct = _HPPercent(hpTarget)
      local thr = tonumber(c.hpVal)
      if thr and not _ValuePasses(pct, c.hpComp, thr) then
        show = false
      end
    end
  end

  -- Combo points (NON-MODE)
  if show and c.cpEnabled == true and _PlayerUsesComboPoints() then
    local cp = _GetComboPointsSafe()
    local thr = tonumber(c.cpVal)
    if thr and c.cpComp and c.cpComp ~= "" then
      if not _ValuePasses(cp, c.cpComp, thr) then
        show = false
      end
    end
  end

  -- Power (NON-MODE)
  if show and c.powerEnabled
      and c.powerComp ~= nil and c.powerComp ~= ""
      and c.powerVal ~= nil and c.powerVal ~= "" then

    local valPct = GetPowerPercent()
    local targetPct = tonumber(c.powerVal) or 0
    local comp = c.powerComp

    local pass = true
    if comp == ">=" then
      pass = (valPct >= targetPct)
    elseif comp == "<=" then
      pass = (valPct <= targetPct)
    elseif comp == "==" then
      pass = (valPct == targetPct)
    end

    if not pass then
      show = false
    end
  end

  -- Remaining (NON-MODE)
  if show and c.remainingEnabled
      and c.remainingComp and c.remainingComp ~= ""
      and c.remainingVal ~= nil and c.remainingVal ~= "" then

    local threshold = tonumber(c.remainingVal)
    if threshold then
      local rem = _AbilityRemainingSeconds(spellIndex, bookType, spellName)
      if rem and rem > 0 then
        if not _RemainingPasses(rem, c.remainingComp, threshold) then
          show = false
        end
      end
    end
  end

  -- Aura conditions (NON-MODE)
  if show and c.auraConditions and table.getn(c.auraConditions) > 0 then
    if _sg.aura ~= nil then
      if not _sg.aura then
        show = false
      end
    else
      if not DoiteConditions_EvaluateAuraConditionsList(c.auraConditions) then
        show = false
      end
    end
  end

  -- Sound gate = all NON-MODE conditions
  data._daSoundGate = (show == true) and true or false

  -- Final visibility includes MODE
  if data._daModeOk == false then
    show = false
  end

  _DoiteHandleEdgeSound(
      data.key,
      "abilityOnCd",
      onCdNow,
      (data._daSoundGate and c.soundOnCDEnabled == true),
      c.soundOnCD)
  _DoiteHandleEdgeSound(
      data.key,
      "abilityOffCd",
      (not onCdNow),
      (data._daSoundGate and c.soundOffCDEnabled == true),
      c.soundOffCD)
  _DoiteHandleEdgeSound(
      data.key,
      "abilityOnProc",
      (_ProcWindowDuration(spellName) and _ProcWindowRemaining(spellName) and true or false),
      (data._daSoundGate and c.soundOnProcEnabled == true),
      c.soundOnProc)

  local vGlow, vGrey, vFade, vFadeAlpha = _EvaluateVfxConditions(data)
  local glow = (c.glow or vGlow) and true or false
  local grey = (c.greyscale or vGrey) and true or false
  local fade = (c.fade or vFade) and true or false
  local fadeAlpha = 0
  if c.fade then
    fadeAlpha = _ClampFadeAlpha(c.fadeAlpha)
  end
  if vFade and vFadeAlpha > fadeAlpha then
    fadeAlpha = vFadeAlpha
  end

  if not show then
    glow = false
    grey = false
    fade = false
    fadeAlpha = 0
  end

  return show, glow, grey, fade, fadeAlpha
end

-- ============================================================
-- Item condition evaluation
-- ============================================================
local function CheckItemConditions(data)
  if not data or not data.conditions or not data.conditions.item then
    return true, false, false, false, 0
  end
  local c = data.conditions.item

  if _Doite_IsKeyUnderEdit(data.key) then
    local glow = (c.glow and true) or false
    local grey = (c.greyscale and true) or false
    local fade = (c.fade and true) or false
    local fadeAlpha = fade and _ClampFadeAlpha(c.fadeAlpha) or 0
    return true, glow, grey, fade, fadeAlpha
  end

  local show = true
  data._daModeOk = true
  data._daSoundGate = nil

  local allowHelp = (c.targetHelp == true)
  local allowHarm = (c.targetHarm == true)
  local allowSelf = (c.targetSelf == true)

  local tf = _DA_GetTargetFacts()

  local state = _EvaluateItemCoreState(data, c)
  local itemOnCdNow = (state and state.hasItem and state.rem and state.rem > 0) and true or false

  if not state.passesWhere then
    data._daModeOk = false
    data._daSoundGate = false
    local glow = c.glow and true or false
    local grey = c.greyscale and true or false
    local fade = c.fade and true or false
    local fadeAlpha = fade and _ClampFadeAlpha(c.fadeAlpha) or 0
    return false, glow, grey, fade, fadeAlpha
  end

  if state.modeMatches == false then
    data._daModeOk = false
  end

  if c.enchant ~= nil then
    local dn = data.displayName or data.name
    if dn == "---EQUIPPED WEAPON SLOTS---" then
      local hasEnchant = (state and state.teRem and state.teRem > 0) and true or false
      if c.enchant == true then
        if not hasEnchant then
          show = false
        end
      else
        if hasEnchant then
          show = false
        end
      end
    end
  end

  local inCombatFlag = (c.inCombat == true)
  local outCombatFlag = (c.outCombat == true)
  if not (inCombatFlag and outCombatFlag) then
    if inCombatFlag and not InCombat() then
      show = false
    end
    if outCombatFlag and InCombat() then
      show = false
    end
  end

  local grouping = c.grouping
  if grouping ~= nil and grouping ~= "any" then
    local groupOk = true
    if grouping == "nogroup" then
      groupOk = not InGroup()
    elseif grouping == "party" then
      groupOk = InPartyOnly()
    elseif grouping == "raid" then
      groupOk = InRaid()
    elseif grouping == "partyraid" then
      groupOk = InGroup()
    else
      groupOk = false
    end
    if not groupOk then
      show = false
    end
  end

  if show and (allowHelp or allowHarm or allowSelf) then
    local ok = false
    if allowSelf and tf.exists and tf.isSelf then
      ok = true
    end
    if (not ok) and allowHelp and tf.exists and tf.isFriend and (not tf.isSelf) then
      ok = true
    end
    if (not ok) and allowHarm and tf.exists and tf.canAttack and (not tf.isFriend) then
      ok = true
    end
    if not ok then
      show = false
    end
  end

  if show and (c.targetDistance or c.targetUnitType or c.targetAlive or c.targetDead) then
    local unitForTarget = nil
    if tf.exists then
      unitForTarget = "target"
    end
    if unitForTarget then
      if not DoiteConditions_PassesTargetStatus(c, unitForTarget) then
        show = false
      elseif not DoiteConditions_PassesTargetDistance(c, unitForTarget, nil) then
        show = false
      elseif not DoiteConditions_PassesTargetUnitType(c, unitForTarget) then
        show = false
      end
    end
  end

  if show and c.weaponFilter and c.weaponFilter ~= "" then
    if not DoiteConditions_PassesWeaponFilter(c) then
      show = false
    end
  end

  if show and c.form and c.form ~= "All" then
    if not DoiteConditions_PassesFormRequirement(c.form) then
      show = false
    end
  end

  if show and c.hpComp and c.hpVal and c.hpMode and c.hpMode ~= "" then
    local hpTarget = nil
    if c.hpMode == "my" then
      hpTarget = "player"
    elseif c.hpMode == "target" then
      if tf.exists then
        if allowSelf then
          if tf.isSelf then
            hpTarget = "target"
          end
        elseif allowHelp and allowHarm then
          if not tf.isSelf then
            hpTarget = "target"
          end
        elseif allowHelp then
          if tf.isFriend and (not tf.isSelf) then
            hpTarget = "target"
          end
        elseif allowHarm then
          if tf.canAttack and (not tf.isFriend) then
            hpTarget = "target"
          end
        else
          hpTarget = "target"
        end
      end
    end

    if hpTarget then
      local pct = _HPPercent(hpTarget)
      local thr = tonumber(c.hpVal)
      if thr and not _ValuePasses(pct, c.hpComp, thr) then
        show = false
      end
    end
  end

  if show and c.cpEnabled == true and _PlayerUsesComboPoints() then
    local cp = _GetComboPointsSafe()
    local thr = tonumber(c.cpVal)
    if thr and c.cpComp and c.cpComp ~= "" then
      if not _ValuePasses(cp, c.cpComp, thr) then
        show = false
      end
    end
  end

  if show and c.powerEnabled
      and c.powerComp ~= nil and c.powerComp ~= ""
      and c.powerVal ~= nil and c.powerVal ~= "" then
    local valPct = GetPowerPercent()
    local targetPct = tonumber(c.powerVal) or 0
    if not _ValuePasses(valPct, c.powerComp, targetPct) then
      show = false
    end
  end

  if show and c.stacksEnabled
      and c.stacksComp and c.stacksComp ~= ""
      and c.stacksVal ~= nil and c.stacksVal ~= "" then
    local threshold = tonumber(c.stacksVal)
    if threshold and state then
      local cnt = state.effectiveCount or 0
      if not _StacksPasses(cnt, c.stacksComp, threshold) then
        show = false
      end
    end
  end

  if show and c.remainingEnabled
      and c.remainingComp and c.remainingComp ~= ""
      and c.remainingVal ~= nil and c.remainingVal ~= "" then
    local threshold = tonumber(c.remainingVal)
    if threshold then
      if (c.mode == "notcd" or c.mode == "both")
          and (data.displayName == "---EQUIPPED WEAPON SLOTS---")
          and (c.inventorySlot == "MAINHAND" or c.inventorySlot == "OFFHAND") then
        if (not state) or (not state.teRem) or state.teRem <= 0 then
          show = false
        else
          if not _RemainingPasses(state.teRem, c.remainingComp, threshold) then
            show = false
          end
        end
      else
        if state.rem and state.rem > 0 then
          if not _RemainingPasses(state.rem, c.remainingComp, threshold) then
            show = false
          end
        end
      end
    end
  end

  if show and c.auraConditions and table.getn(c.auraConditions) > 0 then
    if not DoiteConditions_EvaluateAuraConditionsList(c.auraConditions) then
      show = false
    end
  end

  data._daSoundGate = (show == true) and true or false
  if data._daModeOk == false then
    show = false
  end

  _DoiteHandleEdgeSound(
      data.key,
      "itemOnCd",
      itemOnCdNow,
      (data._daSoundGate and c.soundOnCDEnabled == true),
      c.soundOnCD)
  _DoiteHandleEdgeSound(
      data.key,
      "itemOffCd",
      (not itemOnCdNow),
      (data._daSoundGate and c.soundOffCDEnabled == true),
      c.soundOffCD)

  local vGlow, vGrey, vFade, vFadeAlpha = _EvaluateVfxConditions(data)
  local glow = (c.glow or vGlow) and true or false
  local grey = (c.greyscale or vGrey) and true or false
  local fade = (c.fade or vFade) and true or false
  local fadeAlpha = 0
  if c.fade then
    fadeAlpha = _ClampFadeAlpha(c.fadeAlpha)
  end
  if vFade and vFadeAlpha > fadeAlpha then
    fadeAlpha = vFadeAlpha
  end

  if not show then
    glow = false
    grey = false
    fade = false
    fadeAlpha = 0
  end

  return show, glow, grey, fade, fadeAlpha
end

-- ============================================================
-- Aura condition evaluation
-- ============================================================
local function CheckAuraConditions(data)
  if not data or not data.conditions or not data.conditions.aura then
    return true, false, false, false, 0
  end
  local c = data.conditions.aura

  if _Doite_IsKeyUnderEdit(data.key) then
    local glow = (c.glow and true) or false
    local grey = (c.greyscale and true) or false
    local fade = (c.fade and true) or false
    local fadeAlpha = fade and _ClampFadeAlpha(c.fadeAlpha) or 0
    return true, glow, grey, fade, fadeAlpha
  end

  local name = data.displayName or data.name
  local useSpellIdOnly = (data.Addedviaspellid == true)
  local auraSpellId = tonumber(data.spellid) or 0

  if useSpellIdOnly and auraSpellId <= 0 then
    data._daSoundGate = false
    return false, false, false, false, 0
  end

  if (not useSpellIdOnly) and (not name) then
    data._daSoundGate = false
    return false, false, false, false, 0
  end

  local wantBuff = (data.type == "Buff")
  local wantDebuff = (data.type == "Debuff")
  if not wantBuff and not wantDebuff then
    wantBuff, wantDebuff = true, true
  end

  local allowHelp = (c.targetHelp == true)
  local allowHarm = (c.targetHarm == true)
  local allowSelf = (c.targetSelf == true)

  if (not allowHelp) and (not allowHarm) and (not allowSelf) then
    allowSelf = true
  end
  if allowSelf then
    allowHelp, allowHarm = false, false
  end

  local show = true
  data._daModeOk = true
  data._daSoundGate = nil

  local tf = _DA_GetTargetFacts()

  local ownerFilter = nil
  local wantMine = (c.onlyMine == true)
  local wantOthers = (c.onlyOthers == true)

  if wantMine and not wantOthers then
    ownerFilter = "mine"
  elseif wantOthers and not wantMine then
    ownerFilter = "others"
  else
    ownerFilter = nil
  end

  local requiresTarget = (allowHelp or allowHarm) and (not allowSelf)
  if requiresTarget then
    if not tf.exists then
      show = false
    else
      local isFriend = tf.isFriend
      local canAttack = tf.canAttack
      local matchesAny = false
      if allowHelp and isFriend then
        matchesAny = true
      end
      if (not matchesAny) and allowHarm and canAttack and (not isFriend) then
        matchesAny = true
      end
      if not matchesAny then
        show = false
      end
    end
  end


  local found = false

  if show and allowSelf then
    local hit = false
    if c.trackpet == true and DoitePetAuras and DoitePetAuras.HasAura then
      hit = DoitePetAuras.HasAura(name, auraSpellId, useSpellIdOnly, wantBuff, wantDebuff)
    elseif useSpellIdOnly and auraSpellId > 0 then
      if wantBuff then
        hit = DoitePlayerAuras.HasBuffSpellId(auraSpellId)
      end
      if (not hit) and wantDebuff then
        hit = DoitePlayerAuras.HasDebuffSpellId(auraSpellId)
      end
    else
      if wantBuff then
        hit = DoitePlayerAuras.HasBuff(name)
      end
      if (not hit) and wantDebuff then
        hit = DoitePlayerAuras.HasDebuff(name)
      end
    end
    if hit then
      found = true
    end
  end

  if show and (not found) and allowHelp then
    if c.trackpet == true and DoitePetAuras and DoitePetAuras.HasAura then
      if DoitePetAuras.HasAura(name, auraSpellId, useSpellIdOnly, wantBuff, wantDebuff) then
        found = true
      end
    else
      local hit = false
      if useSpellIdOnly and auraSpellId > 0 then
        if wantBuff and _TargetHasAuraBySpellId(auraSpellId, false) then
          hit = true
        elseif wantDebuff and _TargetHasAuraBySpellId(auraSpellId, true) then
          hit = true
        end
      else
        if wantBuff and _TargetHasAura(name, false) then
          hit = true
        elseif wantDebuff and _TargetHasAura(name, true) then
          hit = true
        end
      end
      if hit then
        found = true
      end
    end
  end

  if show and (not found) and allowHarm then
    if c.trackpet == true and DoitePetAuras and DoitePetAuras.HasAura then
      if DoitePetAuras.HasAura(name, auraSpellId, useSpellIdOnly, wantBuff, wantDebuff) then
        found = true
      end
    else
      local hit = false
      if useSpellIdOnly and auraSpellId > 0 then
        if wantBuff and _TargetHasAuraBySpellId(auraSpellId, false) then
          hit = true
        elseif wantDebuff and _TargetHasAuraBySpellId(auraSpellId, true) then
          hit = true
        end
      else
        if wantBuff and _TargetHasAura(name, false) then
          hit = true
        elseif wantDebuff and _TargetHasAura(name, true) then
          hit = true
        end
      end
      if hit then
        found = true
      end
    end
  end

  if show and found and ownerFilter and DoiteTrack then
    local ownerUnit = nil
    if allowSelf then
      ownerUnit = "player"
    elseif (allowHelp or allowHarm) and UnitExists("target") then
      ownerUnit = "target"
    end
    if ownerUnit then
      local _, _, _, isMine, isOther, mineKnown = _DoiteTrackAuraOwnership(useSpellIdOnly and auraSpellId or name, (c.trackpet == true and "pet") or ownerUnit, useSpellIdOnly)
      if mineKnown then
        if ownerFilter == "mine" and not isMine then
          found = false
        elseif ownerFilter == "others" and not isOther then
          found = false
        end
      end
    end
  end

  -- MODE-ONLY visibility
  if c.mode == "missing" then
    data._daModeOk = (not found) and true or false
  elseif c.mode == "both" then
    data._daModeOk = true
  else
    data._daModeOk = found and true or false
  end

  local inCombatFlag = (c.inCombat == true)
  local outCombatFlag = (c.outCombat == true)
  if not (inCombatFlag and outCombatFlag) then
    if inCombatFlag and not InCombat() then
      show = false
    end
    if outCombatFlag and InCombat() then
      show = false
    end
  end

  local grouping = c.grouping
  if grouping ~= nil and grouping ~= "any" then
    local groupOk = true
    if grouping == "nogroup" then
      groupOk = not InGroup()
    elseif grouping == "party" then
      groupOk = InPartyOnly()
    elseif grouping == "raid" then
      groupOk = InRaid()
    elseif grouping == "partyraid" then
      groupOk = InGroup()
    else
      groupOk = false
    end
    if not groupOk then
      show = false
    end
  end

  if show and c.form and c.form ~= "All" then
    if not DoiteConditions_PassesFormRequirement(c.form) then
      show = false
    end
  end

  if show and c.weaponFilter and c.weaponFilter ~= "" then
    if not DoiteConditions_PassesWeaponFilter(c) then
      show = false
    end
  end

  if show and c.powerEnabled
      and c.powerComp and c.powerComp ~= ""
      and c.powerVal and c.powerVal ~= "" then
    local valPct = GetPowerPercent()
    local targetPct = tonumber(c.powerVal) or 0
    local comp = c.powerComp
    local pass = true
    if comp == ">=" then
      pass = (valPct >= targetPct)
    elseif comp == "<=" then
      pass = (valPct <= targetPct)
    elseif comp == "==" then
      pass = (valPct == targetPct)
    end
    if not pass then
      show = false
    end
  end

  if show and c.hpComp and c.hpVal and c.hpMode and c.hpMode ~= "" then
    local hpTarget = nil
    if c.hpMode == "my" then
      hpTarget = "player"
    elseif c.hpMode == "target" then
      if UnitExists("target") then
        if allowSelf then
          hpTarget = "target"
        elseif allowHelp and allowHarm then
          if not UnitIsUnit("player", "target") then
            hpTarget = "target"
          end
        elseif allowHelp then
          if UnitIsFriend("player", "target")
              and (not UnitIsUnit("player", "target")) then
            hpTarget = "target"
          end
        elseif allowHarm then
          if UnitCanAttack("player", "target")
              and (not UnitIsFriend("player", "target")) then
            hpTarget = "target"
          end
        else
          hpTarget = "target"
        end
      end
    end
    if hpTarget then
      local pct = _HPPercent(hpTarget)
      local thr = tonumber(c.hpVal)
      if thr and not _ValuePasses(pct, c.hpComp, thr) then
        show = false
      end
    end
  end

  if show and c.cpEnabled == true and _PlayerUsesComboPoints() then
    local cp = _GetComboPointsSafe()
    local thr = tonumber(c.cpVal)
    if thr and c.cpComp and c.cpComp ~= "" then
      if not _ValuePasses(cp, c.cpComp, thr) then
        show = false
      end
    end
  end

  -- Keep these with existing guards (editor semantics)
  if c.remainingEnabled
      and c.remainingComp and c.remainingComp ~= ""
      and c.remainingVal ~= nil and c.remainingVal ~= "" then
    if c.mode ~= "missing" and show then
      local targetSelf = true
      if not allowSelf and UnitExists("target") and (allowHelp or allowHarm) then
        local isFriend = UnitIsFriend("player", "target")
        local canAttack = UnitCanAttack("player", "target")
        if (allowHelp and allowHarm and not UnitIsUnit("player", "target")) or
            (allowHelp and isFriend and not UnitIsUnit("player", "target")) or
            (allowHarm and canAttack and not isFriend) then
          targetSelf = false
        end
      end

      local threshold = tonumber(c.remainingVal)
      if threshold then
        local comp = c.remainingComp
        local pass = true
        if targetSelf then
          local rem = nil
          if c.trackpet == true and DoitePetAuras and DoitePetAuras.GetAuraRemainingSeconds then
            rem = DoitePetAuras.GetAuraRemainingSeconds(name, auraSpellId, useSpellIdOnly)
          else
            rem = _PlayerAuraRemainingSeconds(name, auraSpellId, useSpellIdOnly)
          end
          if rem and rem > 0 then
            pass = _RemainingPasses(rem, comp, threshold)
          else
            pass = false
          end
        else
          if ownerFilter == "mine" and DoiteTrack then
            local rpass = _DoiteTrackRemainingPass(useSpellIdOnly and auraSpellId or name, (c.trackpet == true and "pet") or "target", comp, threshold, useSpellIdOnly)
            if rpass == nil then
              pass = false
            else
              pass = rpass
            end
          else
            pass = true
          end
        end
        if not pass then
          show = false
        end
      end
    end
  end

  if c.stacksEnabled
      and c.stacksComp and c.stacksComp ~= ""
      and c.stacksVal ~= nil and c.stacksVal ~= ""
      and c.mode ~= "missing"
      and show then
    local threshold = tonumber(c.stacksVal)
    if threshold then
      local unitToCheck = nil
      if allowSelf then
        unitToCheck = "player"
      elseif tf and tf.exists and (allowHelp or allowHarm) then
        local isFriend = tf.isFriend
        local canAttack = tf.canAttack
        if allowHelp and isFriend then
          unitToCheck = "target"
        elseif allowHarm and canAttack and (not isFriend) then
          unitToCheck = "target"
        end
      end
      if c.trackpet == true then
        unitToCheck = "pet"
      end
      if unitToCheck then
        local cnt = _GetAuraStacksOnUnit(unitToCheck, name, wantDebuff, auraSpellId, useSpellIdOnly)
        if cnt and (not _StacksPasses(cnt, c.stacksComp, threshold)) then
          show = false
        end
      end
    end
  end

  if show and (c.targetDistance or c.targetUnitType or c.targetAlive or c.targetDead) then
    local unitForTargetMods = nil
    if tf and tf.exists and (allowHelp or allowHarm) then
      unitForTargetMods = "target"
    end
    if unitForTargetMods then
      if not DoiteConditions_PassesTargetStatus(c, unitForTargetMods) then
        show = false
      elseif not DoiteConditions_PassesTargetDistance(c, unitForTargetMods, nil) then
        show = false
      elseif not DoiteConditions_PassesTargetUnitType(c, unitForTargetMods) then
        show = false
      end
    end
  end

  if show and c.auraConditions and table.getn(c.auraConditions) > 0 then
    if not DoiteConditions_EvaluateAuraConditionsList(c.auraConditions) then
      show = false
    end
  end

  data._daSoundGate = (show == true) and true or false
  if data._daModeOk == false then
    show = false
  end

  do
    local key = data.key
    local st = key and _SoundStateByKey[key]
  
    local isTargetAura = ((allowHelp or allowHarm) and (not allowSelf)) and true or false
  
    local curTargetName = nil
    if isTargetAura and tf and tf.exists then
      curTargetName = UnitName("target")
    end
  
    if isTargetAura then
      if not st then
        st = {}
        _SoundStateByKey[key] = st
      end
  
      local prevTargetName = st._daTargetName

    -- If target identity changed, suppress sound edges this evaluation, and seed the edge states to the CURRENT values so we don't get a delayed false edge.
      if prevTargetName ~= curTargetName then
        st._daTargetName = curTargetName
  
        -- Seed both edge states to current truth (this is what _DoiteHandleEdgeSound would store)
        st["auraFound"] = found and true or false
        st["auraMissing"] = (not found) and true or false

        -- Do NOT play sounds on target change.
      else
        -- Same target: normal edge sound behavior
        _DoiteHandleEdgeSound(
            key,
            "auraFound",
            found,
            (data._daSoundGate and c.soundOnGainEnabled == true),
            c.soundOnGain)
        _DoiteHandleEdgeSound(
            key,
            "auraMissing",
            (not found),
            (data._daSoundGate and c.soundOnFadeEnabled == true),
            c.soundOnFade)
      end
  
    else
      -- Self-based aura icons: normal behavior (player aura tracking is stable)
      _DoiteHandleEdgeSound(
          key,
          "auraFound",
          found,
          (data._daSoundGate and c.soundOnGainEnabled == true),
          c.soundOnGain)
      _DoiteHandleEdgeSound(
          key,
          "auraMissing",
          (not found),
          (data._daSoundGate and c.soundOnFadeEnabled == true),
          c.soundOnFade)
    end
  end

  local vGlow, vGrey, vFade, vFadeAlpha = _EvaluateVfxConditions(data)
  local glow = (c.glow or vGlow) and true or false
  local grey = (c.greyscale or vGrey) and true or false
  local fade = (c.fade or vFade) and true or false
  local fadeAlpha = 0
  if c.fade then
    fadeAlpha = _ClampFadeAlpha(c.fadeAlpha)
  end
  if vFade and vFadeAlpha > fadeAlpha then
    fadeAlpha = vFadeAlpha
  end

  if not show then
    glow = false
    grey = false
    fade = false
    fadeAlpha = 0
  end

  return show, glow, grey, fade, fadeAlpha
end

---------------------------------------------------------------
-- Main update
---------------------------------------------------------------
function DoiteConditions:EvaluateAll()
  local live = DoiteAurasDB and DoiteAurasDB.spells
  local edit = DoiteDB and DoiteDB.icons
  if not live and not edit then
    return
  end

  local key, data

  -- 1) Live icons (runtime set)
  if live then
    -- First pass: drop corrupted entries (two-pass; no mutation during pairs).
    DoiteConditions._PruneBadEntries(live)

    for key, data in pairs(live) do
      if data.type then
        data.key = key

        if data.type == "Ability" or data.type == "Item" then
          local show, glow, grey, fade, fadeAlpha
          if data.type == "Ability" then
            show, glow, grey, fade, fadeAlpha = CheckAbilityConditions(data)
          else
            show, glow, grey, fade, fadeAlpha = CheckItemConditions(data)
          end
          DoiteConditions:ApplyVisuals(key, show, glow, grey, fade, fadeAlpha)

        elseif data.type == "Buff" or data.type == "Debuff" then
          local show, glow, grey, fade, fadeAlpha = CheckAuraConditions(data)
          DoiteConditions:ApplyVisuals(key, show, glow, grey, fade, fadeAlpha)
        end
      end
    end
  end

  -- 2) Any extra editor-only icons (keys not in live)
  if edit then
    DoiteConditions._PruneBadEntries(edit)

    for key, data in pairs(edit) do
      if (not live) or (not live[key]) then
        if data.type then
          data.key = key

          if data.type == "Ability" or data.type == "Item" then
            local show, glow, grey, fade, fadeAlpha
            if data.type == "Ability" then
              show, glow, grey, fade, fadeAlpha = CheckAbilityConditions(data)
            else
              show, glow, grey, fade, fadeAlpha = CheckItemConditions(data)
            end
            DoiteConditions:ApplyVisuals(key, show, glow, grey, fade, fadeAlpha)

          elseif data.type == "Buff" or data.type == "Debuff" then
            local show, glow, grey, fade, fadeAlpha = CheckAuraConditions(data)
            DoiteConditions:ApplyVisuals(key, show, glow, grey, fade, fadeAlpha)
          end
        end
      end
    end
  end
end

local function _SetTextureVertexAlpha(tex, alpha)
  if not tex or not tex.SetVertexColor then
    return
  end
  local r, g, b = 1, 1, 1
  if tex.GetVertexColor then
    local tr, tg, tb = tex:GetVertexColor()
    if tr then r = tr end
    if tg then g = tg end
    if tb then b = tb end
  end
  tex:SetVertexColor(r, g, b, alpha)
end

local function _ApplyFadeAlphaToBackdrop(frame, alpha)
  if not frame or not frame.backdrop then
    return
  end

  local bd = frame.backdrop

  -- pfUI backdrops are usually texture regions parented to frame.backdrop.
  if bd.GetRegions then
    local regions = { bd:GetRegions() }
    local i, reg
    for i, reg in ipairs(regions) do
      if reg and reg.SetVertexColor then
        _SetTextureVertexAlpha(reg, alpha)
      end
    end
  end

  -- Defensive: some backdrops expose direct texture handles.
  _SetTextureVertexAlpha(bd.bg, alpha)
  _SetTextureVertexAlpha(bd.border, alpha)
  _SetTextureVertexAlpha(bd.backdrop, alpha)
  _SetTextureVertexAlpha(bd.Top, alpha)
  _SetTextureVertexAlpha(bd.Bottom, alpha)
  _SetTextureVertexAlpha(bd.Left, alpha)
  _SetTextureVertexAlpha(bd.Right, alpha)
  _SetTextureVertexAlpha(bd.top, alpha)
  _SetTextureVertexAlpha(bd.bottom, alpha)
  _SetTextureVertexAlpha(bd.left, alpha)
  _SetTextureVertexAlpha(bd.right, alpha)
end

-- =================================================================
-- Shatter effect (alternative to slide-in, per icon).
-- Routed from _HandleAbilitySlider when ca.sliderEffect == "shatter".
-- Defined as table methods because DoiteConditions.lua is at Lua 5.0's
-- 200-local limit.
-- =================================================================

function DoiteConditions._ResolveShatterTexture(frame, dataTbl)
  local tex = nil
  if frame and frame.icon and frame.icon.GetTexture then
    local t = frame.icon:GetTexture()
    if type(t) == "string" and t ~= "" then tex = t end
  end
  if not tex and dataTbl then
    tex = dataTbl.iconTexture
  end
  if type(tex) ~= "string" or tex == "" then
    tex = "Interface\\Icons\\INV_Misc_QuestionMark"
  end
  return tex
end

function DoiteConditions._HandleAbilityShatter(key, ca, dataTbl, sliderGuardOk)
  local ShatterMgr = _G["DoiteShatter_Mgr"]
  if not ShatterMgr then
    return false, false, false, 0, 0, 1
  end

  -- While slider is on and shatter has not fired yet, keep the ability
  -- pipeline hot. Without this, in combat with a stationary target there
  -- may be no dirty_ability source at all and the entry into the slide
  -- window is never observed.
  --
  -- Rate-limit to 10 Hz: RequestImmediateEval runs a FULL EvaluateAll
  -- over every icon. Firing it every frame for the whole armed window
  -- (which can be the entire cooldown) was the largest CPU cost while a
  -- shatter was pending. 10 Hz still detects the window within ~100 ms,
  -- well below the shatter's own animation duration.
  if ca.slider and not ShatterMgr._fired[key] and not ShatterMgr:IsActive(key) then
    local now = GetTime()
    local last = DoiteConditions._shatterWaitAt[key] or 0
    if now - last >= 0.1 then
      DoiteConditions._shatterWaitAt[key] = now
      DoiteConditions_RequestImmediateEval()
    end
  end

  -- Fundamental enable check. Slider off / wrong mode = hard stop.
  if not (ca.slider and (ca.mode == "usable" or ca.mode == "notcd")) then
    if ShatterMgr:IsActive(key) then ShatterMgr:Stop(key) end
    ShatterMgr._fired[key] = nil
    return false, false, false, 0, 0, 1
  end

  -- Form / weapon / aura / target guard. Checked BEFORE the
  -- already-running short-circuit so losing a NON-MODE condition
  -- (target, distance, HP, power, etc.) stops the assembly mid-
  -- flight, not only at start. Stop is idempotent and returns its
  -- pieces / particles to the pool.
  if sliderGuardOk == false then
    if ShatterMgr:IsActive(key) then
      ShatterMgr:Stop(key)
      ShatterMgr._fired[key] = nil
      return false, true, false, 0, 0, 1
    end
    return false, false, false, 0, 0, 1
  end

  -- Already-running short-circuit. Reached only when the guard is OK;
  -- the branch above handles the "should stop now" case.
  if ShatterMgr:IsActive(key) then
    ShatterMgr._fired[key] = true
    return false, false, false, 0, 0, 1
  end

  local spellName = _GetCanonicalSpellNameFromData(dataTbl)
  local rem, dur  = _AbilityCooldownByName(spellName)

  local sliderTime = tonumber(ca.sliderTime) or 0
  local maxWindow
  if sliderTime > 0 then
    maxWindow = sliderTime
  else
    maxWindow = dur or 999999
  end

  -- Same "is this our CD" test as slide.
  local lastSeen = spellName and Doite_SliderSeen and Doite_SliderSeen[spellName] or nil
  local hasSeenForThisCD = false
  if lastSeen and rem and dur and dur > 0 then
    local now   = GetTime()
    local start = now + rem - dur
    if lastSeen + 0.35 >= start then
      hasSeenForThisCD = true
    end
  end

  local inWindow = hasSeenForThisCD and rem and rem > 0 and rem <= maxWindow

  if not inWindow then
    -- Left the "soon off CD" window; arm the next cycle.
    ShatterMgr._fired[key] = nil
    if ShatterMgr:IsActive(key) then
      ShatterMgr:Stop(key)
      return false, true, false, 0, 0, 1
    end
    return false, false, false, 0, 0, 1
  end

  if ShatterMgr._fired[key] then
    -- Already fired for this cooldown cycle; nothing to do.
    return false, false, false, 0, 0, 1
  end

  -- Resolve frame first: if the icon is not currently realized
  -- (frame == nil), we must NOT mark _fired, or this CD cycle loses its
  -- shatter entirely and will not retry.
  local frame = _GetIconFrame(key)
  if not frame then
    return false, false, false, 0, 0, 1
  end

  ShatterMgr._fired[key] = true
  local tex = DoiteConditions._ResolveShatterTexture(frame, dataTbl)
  -- Duration is the REMAINING cooldown, so the assembly finishes the
  -- exact moment the ability comes off CD. sliderTime controls only
  -- WHEN this fires (window size); it must not shorten the animation,
  -- otherwise pieces land early and the icon sits dark until the CD
  -- really ends.
  local sDur = rem or 0.7
  -- Belt-and-suspenders against unexpectedly long CDs -- DoiteShatter
  -- will clamp again to its own MAX_DURATION.
  if sDur > 20 then sDur = 20 end
  if sDur < 0.1 then sDur = 0.1 end
  ShatterMgr:StartOrUpdate(key, frame, tex, sDur, ca.sliderFade == true, ca.sliderDir, ca.sliderGrey == true)
  return true, false, false, 0, 0, 1
end

-- Ability cooldown slider helper (reduces upvalues in ApplyVisuals)
local function _HandleAbilitySlider(key, ca, dataTbl, sliderGuardOk)
  -- Only for Ability icons in usable/notcd mode with slider enabled
  if not (key and ca and dataTbl) then
    if SlideMgr.active and SlideMgr.active[key] then
      SlideMgr:Stop(key)
    end
    if key then
      local SM = _G["DoiteShatter_Mgr"]
      if SM and SM:IsActive(key) then SM:Stop(key) end
    end
    return false, false, false, 0, 0, 1
  end

  -- Route to shatter handler when this icon uses the shatter effect.
  if ca.sliderEffect == "shatter" then
    return DoiteConditions._HandleAbilityShatter(key, ca, dataTbl, sliderGuardOk)
  end

  -- Not shatter: clean up any leftover shatter state for this key.
  do
    local SM = _G["DoiteShatter_Mgr"]
    if SM then
      if SM:IsActive(key) then SM:Stop(key) end
      SM._fired[key] = nil
    end
  end

  if not (ca.slider and (ca.mode == "usable" or ca.mode == "notcd")) then
    -- Slider disabled for this icon: make sure it's stopped
    local had = SlideMgr.active and SlideMgr.active[key]
    if had then
      SlideMgr:Stop(key)
      return false, true, false, 0, 0, 1
    end
    SlideMgr:Stop(key)
    return false, false, false, 0, 0, 1
  end

  -- Slider guard (form / weaponFilter / auraConditions) computed in CheckAbilityConditions
  if sliderGuardOk == false then
    local had = SlideMgr.active and SlideMgr.active[key]
    if had then
      SlideMgr:Stop(key)
      return false, true, false, 0, 0, 1
    end
    SlideMgr:Stop(key)
    return false, false, false, 0, 0, 1
  end

  local spellName = _GetCanonicalSpellNameFromData(dataTbl)
  local rem, dur = _AbilityCooldownByName(spellName)
  local wasSliding = SlideMgr.active and SlideMgr.active[key]

  -- sliderTime - user-defined slide window in seconds.
  --   > 0   -> slide only during the last N seconds of the cooldown
  --   nil/0 -> no time limit: slide runs for the whole cooldown (default)
  local sliderTime = tonumber(ca.sliderTime) or 0
  local maxWindow
  if sliderTime > 0 then
    maxWindow = sliderTime
  else
    maxWindow = dur or 999999
  end

  -- Last time *this* spell was actually seen cast (SPELL_GO_SELF -> _MarkSliderSeen)
  local lastSeen = spellName and Doite_SliderSeen and Doite_SliderSeen[spellName] or nil

  local hasSeenForThisCD = false

  -- With SPELL_GO_SELF, only show sliders for cooldowns that began at (or immediately after) an observed cast of THIS spell.
  if lastSeen and rem and dur and dur > 0 then
    local now = GetTime()
    -- reconstruct approximate cooldown start from (now, rem, dur)
    local start = now + rem - dur
    -- allow a small epsilon for event timing / rounding
    if lastSeen + 0.35 >= start then
      hasSeenForThisCD = true
    end
  end


  -- Start only when this cooldown really belongs to this spell, but allow short CDs (GCD-only) as long as they're from this spell.
  local shouldStart = hasSeenForThisCD and rem and dur and rem > 0 and rem <= maxWindow

  -- Once sliding, ONLY keep the slide alive while within the slide window.
  -- Small sampling jitter allowance.
  local contLimit = maxWindow + 0.15

  local shouldContinue = wasSliding and rem and rem > 0 and rem <= contLimit

  local startedSlide, stoppedSlide = false, false

  if shouldStart or shouldContinue then
    local baseX, baseY = 0, 0
    if _GetBaseXY then
      baseX, baseY = _GetBaseXY(key, dataTbl)
    end

    SlideMgr:StartOrUpdate(
        key,
        (ca.sliderDir or "center"),
        baseX,
        baseY,
        GetTime() + (rem or 0),
        (ca.sliderFade == true)
    )

    if not wasSliding then
      startedSlide = true
    end
  else
    if wasSliding then
      stoppedSlide = true
    end
    SlideMgr:Stop(key)
  end

  local active, dx, dy, alpha = SlideMgr:Get(key)
  if not active then
    return startedSlide, stoppedSlide, false, 0, 0, 1
  end
  return startedSlide, stoppedSlide, true, dx or 0, dy or 0, alpha or 1
end

---------------------------------------------------------------
-- Apply visuals to icons
---------------------------------------------------------------
function DoiteConditions:ApplyVisuals(key, show, glow, grey, fade, fadeAlpha)
  local frame = _GetIconFrame(key)
  if not frame then
    -- If icons rebuilt, forget any stale cached ref for this key and retry.
    _ForgetIconFrame(key)
    if DoiteAuras_RefreshIcons then
      DoiteAuras_RefreshIcons()
    end
    frame = _GetIconFrame(key)
    if not frame then
      return
    end
  end

  local dataTbl = (DoiteDB and DoiteDB.icons and DoiteDB.icons[key])
      or (DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[key])

  -- Compute editing FIRST (needed by proc-window guard + texture preload)
  local editing = _Doite_IsKeyUnderEdit(key)

  if (not editing) and dataTbl and dataTbl.type == "Ability"
      and dataTbl.conditions and dataTbl.conditions.ability then

    local ca = dataTbl.conditions.ability
    if ca and ca.mode == "usable" then
      local spellName = _GetCanonicalSpellNameFromData(dataTbl)
      local dur = _ProcWindowDuration(spellName)

      if dur then
        local prev = (_G.DoiteConditions_ProcLastShowByKey[key] == true)

        if show and (not prev) then
          local now = GetTime()
          local curUntil = _G.DoiteConditions_ProcUntil[spellName] or 0
          if curUntil < now then
            _ProcWindowSet(spellName, now + dur)
          end
        end

        _G.DoiteConditions_ProcLastShowByKey[key] = (show == true) and true or false
      end
    end
  end

  if show or editing then
    if frame.icon and dataTbl and (dataTbl.displayName or dataTbl.name) then
      local nameKey = dataTbl.displayName or dataTbl.name

      -- Sanitize: reject non-string iconTexture. Some clients store an
      -- icon-id number here, which SetTexture() renders as Solid Texture.
      -- Try a one-time conversion via client APIs; else drop from the DB.
      local stored = dataTbl.iconTexture
      if stored ~= nil and type(stored) ~= "string" then
        local converted = nil
        if type(stored) == "number" and stored > 0 then
          local conv = { "GetItemIconTexture", "GetItemIcon" }
          local i = 1
          while i <= table.getn(conv) do
            local fn = _G[conv[i]]
            if type(fn) == "function" then
              local ok, path = pcall(fn, stored)
              if ok and type(path) == "string" and path ~= "" then
                converted = path
                break
              end
            end
            i = i + 1
          end
        end
        dataTbl.iconTexture = converted
      end

      -- Prefer per-entry stored texture, then cache, then fallback.
      local tex = nil
      if type(dataTbl.iconTexture) == "string" and dataTbl.iconTexture ~= "" then
        tex = dataTbl.iconTexture
      elseif IconCache and nameKey and type(IconCache[nameKey]) == "string" then
        tex = IconCache[nameKey]
      end

      if tex and tex ~= "" then
        if frame.icon:GetTexture() ~= tex then
          frame.icon:SetTexture(tex)
        end
      else
        -- No usable path: show the question-mark placeholder instead of
        -- the Solid Texture / red square that SetTexture(number) produces.
        if frame.icon:GetTexture() ~= "Interface\\Icons\\INV_Misc_QuestionMark" then
          frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
      end
    end

    if dataTbl then
      if dataTbl.type == "Ability" then
        _EnsureAbilityTexture(frame, dataTbl)
      elseif dataTbl.type == "Buff" or dataTbl.type == "Debuff" then
        _EnsureAuraTexture(frame, dataTbl)
      elseif dataTbl.type == "Item" then
        _EnsureItemTexture(frame, dataTbl)
      elseif dataTbl.type == "Custom" then
        local tex = dataTbl._daCustomTexture or dataTbl.iconTexture or "Interface\\Icons\\INV_Misc_QuestionMark"
        if frame.icon then
          frame.icon:SetTexture(tex)
        end
        -- Hide or restore the backdrop (pfUI border / background)
        local wantHideBG = (dataTbl._daCustomHideBG == true)
        if wantHideBG then
          if frame.backdrop and frame.backdrop.Hide then
            frame.backdrop:Hide()
          end
          if frame.icon and frame.icon.SetTexCoord then
            frame.icon:SetTexCoord(0, 1, 0, 1)
          end
        else
          if frame.backdrop and frame.backdrop.Show then
            frame.backdrop:Show()
          end
        end
      end
    end
  end

  ------------------------------------------------------------
  -- Slider (driven by SlideMgr; ignores GCD; super smooth)
  ------------------------------------------------------------
  local slideActive, dx, dy, slideAlpha = false, 0, 0, 1

  if dataTbl and dataTbl.type == "Ability"
      and dataTbl.conditions
      and dataTbl.conditions.ability then

    local ca = dataTbl.conditions.ability
    local startedSlide, stoppedSlide

    -- Slider / shatter must obey every NON-MODE condition, not just
    -- form / weapon / aura. _daSoundGate is set in CheckAbilityConditions
    -- right before mode is applied, so it is true both while the icon
    -- is on cooldown and while it is ready -- which is exactly what
    -- lets the slider run during CD -- but it flips false whenever any
    -- OTHER condition fails (target, distance, HP, power, form, etc.).
    -- Combining it with _daSliderGuard suppresses the animation in
    -- those cases.
    local sliderGate = dataTbl._daSliderGuard
    if sliderGate ~= false and dataTbl._daSoundGate == false then
      sliderGate = false
    end

    -- Lightweight wrapper: heavy logic lives in _HandleAbilitySlider
    startedSlide, stoppedSlide, slideActive, dx, dy, slideAlpha = _HandleAbilitySlider(key, ca, dataTbl, sliderGate)

    -- === immediate group reflow on slide start/stop ===
    if (startedSlide or stoppedSlide) and DoiteGroup and DoiteGroup.ApplyGroupLayout then
      if type(DoiteAuras) == "table"
          and type(DoiteAuras.GetAllCandidates) == "function" then
        _G["DoiteGroup_NeedReflow"] = true
      end
    end
  else
    -- Non-ability icons never slide
    if SlideMgr.active and SlideMgr.active[key] then
      SlideMgr:Stop(key)
    end
  end

  -- Pull the current slide offset/alpha (if sliding)
  local allowSlideShow = false
  do


    -- ==== Effective flags with OLD-behavior defaults ====
    -- 1) Always allow showing during slide (preview), like OLD code.
    allowSlideShow = false
    if slideActive and dataTbl and dataTbl.conditions and dataTbl.conditions.ability then
      local ca = dataTbl.conditions.ability
      if ca.slider == true and (dataTbl._daSliderGuard ~= false) then
        allowSlideShow = true
      end
    end

    -- Shatter pieces are parented to the icon frame. While CS is on CD
    -- (mode=notcd), the frame would otherwise be hidden and the whole
    -- assembly would play invisibly. Mirror the slide behaviour: keep
    -- the frame shown for as long as the shatter animation runs.
    if (not allowSlideShow) and dataTbl then
      local SM = _G["DoiteShatter_Mgr"]
      if SM and SM:IsActive(key) then
        allowSlideShow = true
      end
    end

    -- 2) Default suppression during slide UNLESS slider is explicitly enabled.
    local isSliderEnabled = false
    local sliderGlowFlag = false
    local sliderGreyFlag = false

    if dataTbl and dataTbl.type == "Ability" and dataTbl.conditions and dataTbl.conditions.ability then
      local ca = dataTbl.conditions.ability
      if ca.slider == true then
        isSliderEnabled = true
        sliderGlowFlag = (ca.sliderGlow == true)
        sliderGreyFlag = (ca.sliderGrey == true)
      end
    end

    local useGlow, useGrey
    if slideActive then
      if isSliderEnabled then
        useGlow = sliderGlowFlag
        useGrey = sliderGreyFlag
      else
        useGlow = false
        useGrey = false
      end
    else
      useGlow = (glow == true)
      useGrey = (grey == true)
    end

    -- Flags for other systems / change detector
    frame._daSliding = slideActive and true or false
    frame._daShouldShow = ((show == true) or editing) and true or false
    frame._daUseGlow = useGlow and true or false
    frame._daUseGreyscale = useGrey and true or false
    frame._daUseFade = (fade == true) and true or false
    frame._daFadeAlpha = _ClampFadeAlpha(fadeAlpha)
    -- Sync with DoiteAuras.lua expectation
    frame._daGreyscale = frame._daUseGreyscale
  end

  -- Determine baseline anchoring
  local baseX, baseY = 0, 0
  if _GetBaseXY and dataTbl then
    baseX, baseY = _GetBaseXY(key, dataTbl)
  end

  -- If this icon belongs to a group, prefer the latest computed position (for leaders AND followers)
  local isGrouped = (dataTbl and dataTbl.group and dataTbl.group ~= "" and dataTbl.group ~= "no")
  local hasGroupPos = false
  if isGrouped and _G["DoiteGroup_Computed"] and _G["DoiteGroup_Computed"][dataTbl.group] then
    local arr = _G["DoiteGroup_Computed"][dataTbl.group]
    local n = table.getn(arr)
    for idx = 1, n do
      local e = arr[idx]
      if e and e.key == key and e._computedPos then
        baseX = e._computedPos.x
        baseY = e._computedPos.y
        hasGroupPos = true
        break
      end
    end
  end

  if slideActive then
    SlideMgr:UpdateBase(key, baseX, baseY)
  end

  -- Show during slide preview even if main conditions would hide
  local showForSlide = (show or allowSlideShow)

  -- If this is the key currently being edited, force it visible regardless of conditions/group caps
  if editing then
    showForSlide = true
  end

  -- Group capacity may block this icon unless editing this very key
  if frame._daBlockedByGroup and (not editing) then
    showForSlide = false
  end

  -- Apply position and alpha (no stutter: set exact coordinates each paint)
  do
    local isGrouped = (dataTbl and dataTbl.group and dataTbl.group ~= "" and dataTbl.group ~= "no")
    local isLeader = (dataTbl and dataTbl.isLeader == true)

    -- Do not force position if user is dragging this frame
    if not frame._daDragging then
        -- When sliding: apply transient movement to everyone (leaders + followers)
        if slideActive then
          frame:ClearAllPoints()
          frame:SetPoint("CENTER", UIParent, "CENTER", baseX + dx, baseY + dy)
          frame:SetAlpha(slideAlpha)
        else
          -- When not sliding: do NOT force followers' points here.
          if not (isGrouped and not isLeader) then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", baseX, baseY)
            frame:SetAlpha((dataTbl and dataTbl.alpha) or 1)
          else
            -- Followers:
            -- Only re-anchor having a computed group position for this key.
            if hasGroupPos then
              frame:ClearAllPoints()
              frame:SetPoint("CENTER", UIParent, "CENTER", baseX, baseY)
            end
            -- If !hasGroupPos: do not touch points this tick; avoid snapping back to original x/y.
            frame:SetAlpha((dataTbl and dataTbl.alpha) or 1)
          end
        end
    end
    -- === Overlay Text: cooldown remaining + stacks (forced above glow) ===
    DoiteConditions._UpdateOverlayForFrame(frame, key, dataTbl, slideActive)
  end

  -- === Apply EFFECTS with change detection (don’t restart animations every frame) ===
  do
    -- Decide final show flag (editing & group gating preserved)
    local showForSlide = (show or allowSlideShow)
    if editing then
      showForSlide = true
    end

    -- Never suppress the edited icon because of group capacity while editing
    if frame._daBlockedByGroup and (not editing) then
      showForSlide = false
    end

    -- Apply visibility only on change
    if frame._daLastShown ~= showForSlide then
      frame._daLastShown = showForSlide
      if showForSlide then
        frame:Show()

        if not slideActive then
          frame:SetAlpha(1)
        end
      else
        frame:Hide()
      end
    end

    -- FADE (SetVertexColor alpha path for icon + border/backdrop)
    do
      local wantFade = (frame._daUseFade == true) and showForSlide
      local wantedAlpha = 1
      if wantFade then
        wantedAlpha = 1 - (frame._daFadeAlpha or 0)
        if wantedAlpha < 0 then wantedAlpha = 0 end
        if wantedAlpha > 1 then wantedAlpha = 1 end
      end
      if frame._daLastFadeAlpha ~= wantedAlpha then
        frame._daLastFadeAlpha = wantedAlpha
        _SetTextureVertexAlpha(frame.icon, wantedAlpha)
        _ApplyFadeAlphaToBackdrop(frame, wantedAlpha)
      end
    end

    -- GREYSCALE — only flip when it changes
    if frame.icon then
      local wantGrey = (frame._daGreyscale == true) and showForSlide
      if frame._daLastGrey ~= wantGrey then
        frame._daLastGrey = wantGrey
        if wantGrey then
          frame.icon:SetDesaturated(1)
        else
          frame.icon:SetDesaturated(nil)
        end
        
        -- Fix: Update clickability for Items when grey state changes
        -- REMOVED: DoiteAuras.lua handles all clickability/mouse-enable logic centrally now.
        -- We no longer disable mouse just because an item is grey/cooldown.
      end
    end

    -- GLOW — only start/stop when it changes (preserve animation).
    -- Second condition: when the global glow-settings version bumps
    -- (DG.BumpVersion from the Settings UI), every currently-glowing
    -- icon must rebuild its overlay so shape/color/texture updates
    -- take effect. Without this, _daLastGlow stays true forever and
    -- DG.Start is never called again after the first glow.
    if DG then
      local wantGlow = (frame._daUseGlow == true) and showForSlide
      local glowVersion = _G["DoiteGlow_Version"] or 0
      local versionChanged = wantGlow and (frame._daGlowVersion ~= glowVersion)
      if frame._daLastGlow ~= wantGlow or versionChanged then
        frame._daLastGlow = wantGlow
        if wantGlow then
          DG.Start(frame)
        else
          DG.Stop(frame)
        end
      end
    end
  end


  ----------------------------------------------------------------
  -- Reflow groups when this icon’s logical visibility flips.
  -- This covers Buff/Debuff-only groups (no abilities involved).
  ----------------------------------------------------------------
  if DoiteGroup and DoiteGroup.ApplyGroupLayout then
    if frame._lastShowState ~= show then
      frame._lastShowState = show
      if type(DoiteAuras) == "table" and type(DoiteAuras.GetAllCandidates) == "function" then
        _G["DoiteGroup_NeedReflow"] = true
      end
    end
  end
end

function DoiteConditions_RequestEvaluate()
  -- Just mark dirty; actual flag rebuild is coalesced into the next OnUpdate.
  -- This avoids 4× full DB scans per call.
  DoiteConditions._flagsDirty = true
  dirty_ability, dirty_aura, dirty_target, dirty_power = true, true, true, true

  -- Proc-tracking set may have changed (icon add/remove); drop its cache.
  local proc = _G["DoiteConditionsProc"]
  if proc and proc.InvalidateTrackedCache then
    proc.InvalidateTrackedCache()
  end
end

local function _DoiteConditions_FlushDirtyFlags()
  if not DoiteConditions._flagsDirty then return end
  DoiteConditions._flagsDirty = nil

  if _RebuildAbilityTimeHeartbeatFlag then _RebuildAbilityTimeHeartbeatFlag() end
  if _RebuildAuraTimeHeartbeatFlag    then _RebuildAuraTimeHeartbeatFlag()    end
  if _RebuildAuraUsageFlags           then _RebuildAuraUsageFlags()           end
  if _RebuildTargetModsFlags          then _RebuildTargetModsFlags()          end
end

function DoiteConditions:EvaluateAbilities(doLogic, doTime)
  if _G["DoiteTrack"] then
    _G["DoiteTrack"]._frameStamp = math.floor(((GetTime and GetTime()) or 0) * 20)
  end
  -- Default behaviour (no args): full logic + time, as before.
  if doLogic == nil and doTime == nil then
    doLogic, doTime = true, true
  else
    if doLogic == nil then
      doLogic = true
    end
    if doTime == nil then
      doTime = false
    end
  end

  local live = DoiteAurasDB and DoiteAurasDB.spells
  local edit = DoiteDB and DoiteDB.icons
  if not live and not edit then
    return
  end

  -- Prune corrupted (non-table) entries, matching EvaluateAll / EvaluateAuras.
  -- Without this, a number/string value in the DB would crash data.type
  -- below, and the fast-path would also skip the guard entirely.
  if live then
    DoiteConditions._PruneBadEntries(live)
  end
  if edit then
    DoiteConditions._PruneBadEntries(edit)
  end

  local key, data

  -- Fast path: time-heartbeat only (avoid scanning every icon each 0.5s)
  if doLogic == false and doTime == true then
    -- 1) Live keys that actually have time logic
    if live then
      local keys = _timeKeysAbilityItem_live
      if keys then
        local i, n = 1, table.getn(keys)
        while i <= n do
          key = keys[i]
          data = key and live[key]
          if data and (data.type == "Ability" or data.type == "Item") then
            data.key = key
            local show, glow, grey, fade, fadeAlpha
            if data.type == "Ability" then
              show, glow, grey, fade, fadeAlpha = CheckAbilityConditions(data)
            else
              show, glow, grey, fade, fadeAlpha = CheckItemConditions(data)
            end
            DoiteConditions:ApplyVisuals(key, show, glow, grey, fade, fadeAlpha)
          end
          i = i + 1
        end
      end
    end

    -- 2) Editor keys (skip any that exist in live, same as original)
    if edit then
      local keys = _timeKeysAbilityItem_edit
      if keys then
        local i, n = 1, table.getn(keys)
        while i <= n do
          key = keys[i]
          if key and ((not live) or (not live[key])) then
            data = edit[key]
            if data and (data.type == "Ability" or data.type == "Item") then
              data.key = key
              local show, glow, grey, fade, fadeAlpha
              if data.type == "Ability" then
                show, glow, grey, fade, fadeAlpha = CheckAbilityConditions(data)
              else
                show, glow, grey, fade, fadeAlpha = CheckItemConditions(data)
              end
              DoiteConditions:ApplyVisuals(key, show, glow, grey, fade, fadeAlpha)
            end
          end
          i = i + 1
        end
      end
    end

    return
  end

  -- 1) Live icons (runtime set)
  if live then
    for key, data in pairs(live) do
      if data and (data.type == "Ability" or data.type == "Item") then
        -- Decide whether this icon should be touched in this pass
        local wantsTime = false
        if doTime then
          if data.type == "Ability" then
            wantsTime = _IconHasTimeLogic_Ability(data)
          else
            -- "Item"
            wantsTime = _IconHasTimeLogic_Item(data)
          end
        end

        local wantsLogic = doLogic

        if wantsLogic or wantsTime then
          data.key = key
          local show, glow, grey, fade, fadeAlpha
          if data.type == "Ability" then
            show, glow, grey, fade, fadeAlpha = CheckAbilityConditions(data)
          else
            show, glow, grey, fade, fadeAlpha = CheckItemConditions(data)
          end
          DoiteConditions:ApplyVisuals(key, show, glow, grey, fade, fadeAlpha)
        end
      end
    end
  end

  -- 2) Any extra editor-only icons (keys not in live)
  if edit then
    for key, data in pairs(edit) do
      if (not live) or (not live[key]) then
        if data and (data.type == "Ability" or data.type == "Item") then
          local wantsTime = false
          if doTime then
            if data.type == "Ability" then
              wantsTime = _IconHasTimeLogic_Ability(data)
            else
              wantsTime = _IconHasTimeLogic_Item(data)
            end
          end

          local wantsLogic = doLogic

          if wantsLogic or wantsTime then
            data.key = key
            local show, glow, grey, fade, fadeAlpha
            if data.type == "Ability" then
              show, glow, grey, fade, fadeAlpha = CheckAbilityConditions(data)
            else
              show, glow, grey, fade, fadeAlpha = CheckItemConditions(data)
            end
            DoiteConditions:ApplyVisuals(key, show, glow, grey, fade, fadeAlpha)
          end
        end
      end
    end
  end
end

function DoiteConditions:EvaluateAuras()
  if _G["DoiteTrack"] then
    _G["DoiteTrack"]._frameStamp = math.floor(((GetTime and GetTime()) or 0) * 20)
  end
  local live = DoiteAurasDB and DoiteAurasDB.spells
  local edit = DoiteDB and DoiteDB.icons
  if not live and not edit then
    return
  end

  local key, data

  -- 1) Live icons (runtime set)
  if live then
    DoiteConditions._PruneBadEntries(live)

    for key, data in pairs(live) do
      if data.type == "Buff" or data.type == "Debuff" then
        data.key = key

        local show, glow, grey, fade, fadeAlpha = CheckAuraConditions(data)
        DoiteConditions:ApplyVisuals(key, show, glow, grey, fade, fadeAlpha)
      end
    end
  end

  -- 2) Any extra editor-only icons (keys not in live)
  --    Only bother when at least one key is under edit, same as before.
  if edit then
    DoiteConditions._PruneBadEntries(edit)

    for key, data in pairs(edit) do
      if (not live) or (not live[key]) then
        if data.type == "Buff" or data.type == "Debuff" then
          data.key = key

          local show, glow, grey, fade, fadeAlpha = CheckAuraConditions(data)
          DoiteConditions:ApplyVisuals(key, show, glow, grey, fade, fadeAlpha)
        end
      end
    end
  end
end

-- Lightweight pass that ONLY refreshes remaining-time text / stacks.
-- No condition logic, no aura scanning – uses existing cached data.
function DoiteConditions_UpdateTimeText()
  local live = DoiteAurasDB and DoiteAurasDB.spells
  local edit = DoiteDB and DoiteDB.icons
  if not live and not edit then
    return
  end

  -- Runtime icons (live set)
  if live then
    -- Ability/Item keys with time logic
    do
      local keys = _timeKeysAbilityItem_live
      local i, n = 1, table.getn(keys)
      while i <= n do
        local key = keys[i]
        local data = key and live[key]
        if type(data) == "table" and data.type then
          local frame = _GetIconFrame(key)
          if frame and frame.IsShown and frame:IsShown() then
            local dataTbl = (DoiteDB and DoiteDB.icons and DoiteDB.icons[key])
                or
                (DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[key])
            if dataTbl then
              DoiteConditions._UpdateOverlayForFrame(frame, key, dataTbl, frame._daSliding == true)
            end
          end
        end
        i = i + 1
      end
    end

    -- Aura keys with time logic
    do
      local keys = _timeKeysAura_live
      local i, n = 1, table.getn(keys)
      while i <= n do
        local key = keys[i]
        local data = key and live[key]
        if type(data) == "table" and data.type then
          local frame = _GetIconFrame(key)
          if frame and frame.IsShown and frame:IsShown() then
            local dataTbl = (DoiteDB and DoiteDB.icons and DoiteDB.icons[key])
                or
                (DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[key])
            if dataTbl then
              DoiteConditions._UpdateOverlayForFrame(frame, key, dataTbl, frame._daSliding == true)
            end
          end
        end
        i = i + 1
      end
    end
  end

  -- Editor-only icons (keys not in live)
  if edit then
    local skipKeys = live or _DA_EMPTY_TABLE

    -- Ability/Item keys with time logic
    do
      local keys = _timeKeysAbilityItem_edit
      local i, n = 1, table.getn(keys)
      while i <= n do
        local key = keys[i]
        if key and (not skipKeys[key]) then
          local data = edit[key]
          if type(data) == "table" and data.type then
            local frame = _GetIconFrame(key)
            if frame and frame.IsShown and frame:IsShown() then
              local dataTbl = (DoiteDB and DoiteDB.icons and DoiteDB.icons[key])
                  or
                  (DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[key])
              if dataTbl then
                DoiteConditions._UpdateOverlayForFrame(frame, key, dataTbl, frame._daSliding == true)
              end
            end
          end
        end
        i = i + 1
      end
    end

    -- Aura keys with time logic
    do
      local keys = _timeKeysAura_edit
      local i, n = 1, table.getn(keys)
      while i <= n do
        local key = keys[i]
        if key and (not skipKeys[key]) then
          local data = edit[key]
          if type(data) == "table" and data.type then
            local frame = _GetIconFrame(key)
            if frame and frame.IsShown and frame:IsShown() then
              local dataTbl = (DoiteDB and DoiteDB.icons and DoiteDB.icons[key])
                  or
                  (DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[key])
              if dataTbl then
                DoiteConditions._UpdateOverlayForFrame(frame, key, dataTbl, frame._daSliding == true)
              end
            end
          end
        end
        i = i + 1
      end
    end
  end
end

local _tick = CreateFrame("Frame", "DoiteConditionsTick")

-- Keep these as globals so the OnUpdate script doesn't capture them as upvalues
_acc = 0
_textAccum = 0
_distAccum = 0
_timeEvalAccum = 0

-- Weapon temp-enchant: start ticking ONLY when remaining <= 60s
_teFastAccum = 0
_teFastActive = false

-- Lift the body into a real function
function DoiteConditions_OnUpdate(dt)
  _acc = _acc + dt
  _textAccum = _textAccum + dt

  DoiteConditions._RefreshEditStateCache()

  -- Coalesce any pending flag rebuilds (from RequestEvaluate) into one pass.
  _DoiteConditions_FlushDirtyFlags()

  -- 0.5s heartbeat for ability/item time-based logic (cooldown end
  -- needs reevaluation). Temp weapon enchant near expiry uses its own
  -- fast tick block below instead of this heartbeat.
  _timeEvalAccum = _timeEvalAccum + dt
  if _timeEvalAccum >= 0.5 then
    _timeEvalAccum = 0

    if _hasAnyAbilityTimeLogic then
      dirty_ability_time = true
    end
  end

  -- Weapon temp-enchant fast tick:
  -- Above 60s: event-driven only (no ticking).
  -- <=60s: tick at 0.10s to keep hide/show + remaining accurate near expiry.
  do
    local dc = _G.DoiteConditions
    local te = dc and dc._daTempEnchantCache
    local hasTE = false

    if te then
      local now = GetTime()
      local mh = te[INV_SLOT_MAINHAND]
      local oh = te[INV_SLOT_OFFHAND]
      local rg = te[INV_SLOT_RANGED]

      _teFastActive = false

      if mh and mh.endTime then
        local rem = mh.endTime - now
        if rem > 0 then hasTE = true; if rem <= 60 then _teFastActive = true end end
      end
      if (not _teFastActive) and oh and oh.endTime then
        local rem = oh.endTime - now
        if rem > 0 then hasTE = true; if rem <= 60 then _teFastActive = true end end
      end
      if (not _teFastActive) and rg and rg.endTime then
        local rem = rg.endTime - now
        if rem > 0 then hasTE = true; if rem <= 60 then _teFastActive = true end end
      end
    end

    if not hasTE then
      _teFastActive = false
    end

    if _teFastActive then
      _teFastAccum = _teFastAccum + dt
      if _teFastAccum >= 0.10 then
        _teFastAccum = 0
        dirty_ability_time = true
      end
    else
      _teFastAccum = 0
    end
  end

  -- Keep warrior Overpower/Revenge procs in sync even if no other events fire.
  -- Proc module installs this global; guard so a load-order mishap does not
  -- take down the whole OnUpdate pipeline.
  if DoiteConditions_WarriorProcTick then
    DoiteConditions_WarriorProcTick()
  end

  -- Coalesce aura events: scan/rebuild at most once per frame, before any rendering/eval.
  DoiteConditions:ProcessPendingAuraScans()

  -- Smooth remaining-time text (abilities/items/auras) on a cheap path
  if _textAccum >= 0.1 then
    _textAccum = 0

    if _hasAnyAbilityTimeLogic or _hasAnyAuraTimeLogic or _teFastActive then
      DoiteConditions_UpdateTimeText()
    end
  end

  -- Lightweight distance heartbeat: keep target distance checks responsive.
  _distAccum = _distAccum + dt
  if _distAccum >= 0.15 then
    _distAccum = 0

    if UnitExists and UnitExists("target") then
      -- Only mark dirty if configs actually use these options
      if _hasAnyTargetMods_Ability then
        dirty_ability = true
      end
      if _hasAnyTargetMods_Aura then
        dirty_aura = true
      end
    end
  end

  -- Render faster while sliding; else ~30fps
  local thresh = (next(DoiteConditions_SlideMgr.active) ~= nil) and 0.03 or 0.10
  if _acc < thresh then
    return
  end
  _acc = 0

  local needAbilityLogic = dirty_ability or dirty_power
  local needAbilityTime = dirty_ability_time
  local needAura = dirty_aura or dirty_target or dirty_power
  local didCustom = false

  if needAbilityLogic or needAbilityTime then
    DoiteConditions:EvaluateAbilities(needAbilityLogic, needAbilityTime)
  end
  if needAura then
    DoiteConditions:EvaluateAuras()
  end

  -- Custom functions run here near the end of OnUpdate.
  if _hasAnyCustomLogic then
    didCustom = DoiteConditions:EvaluateCustom() and true or false
  end

  if needAbilityLogic or needAbilityTime or needAura or didCustom then
    dirty_aura, dirty_target, dirty_power = false, false, false
    dirty_ability_time = false
    -- While sliding, ability icons updating each frame
    dirty_ability = next(DoiteConditions_SlideMgr.active) and true or false
  end
end

-- Avoid per-frame pcall (allocation/overhead). Enable it only when debugging.
local function _DoiteConditions_OnUpdateWrapper()
  local dt = arg1 or 0
  if _G["DoiteAuras_DebugPcallOnUpdate"] == true then
    local ok, err = pcall(DoiteConditions_OnUpdate, dt)
    if not ok and DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage(
          "|cffff0000[DoiteAuras] OnUpdate error:|r " .. tostring(err)
      )
    end
  else
    DoiteConditions_OnUpdate(dt)
  end
end

_tick:SetScript("OnUpdate", _DoiteConditions_OnUpdateWrapper)

-- Prime aura snapshot and trigger initial evaluation
if _G.UnitExists and _G.UnitExists("target") then
  DoiteConditions_ScanUnitAuras("target")
end
DoiteConditions._daItemSnapshotDirty = true
dirty_ability, dirty_aura, dirty_target, dirty_power = true, true, true, true

-- Rebuild flag caches on next tick (needed so that _hasAnyItemLogic,
-- _hasAnyTargetAuraUsage, etc. are correct before the first RequestEvaluate
-- call from user interaction).
DoiteConditions._flagsDirty = true

---------------------------------------------------------------
-- Event handling + smoother updates
---------------------------------------------------------------
-- NOTE: DoiteConditions.lua is at Lua 5.0's 200-file-local limit.
-- No new local for the event frame; CreateFrame with a name
-- installs it as a global automatically.
CreateFrame("Frame", "DoiteConditionsEventFrame")
DoiteConditionsEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
DoiteConditionsEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
DoiteConditionsEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
DoiteConditionsEventFrame:RegisterEvent("UNIT_AURA")
DoiteConditionsEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
DoiteConditionsEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
DoiteConditionsEventFrame:RegisterEvent("UNIT_MANA")
DoiteConditionsEventFrame:RegisterEvent("UNIT_ENERGY")
DoiteConditionsEventFrame:RegisterEvent("UNIT_RAGE")
DoiteConditionsEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
DoiteConditionsEventFrame:RegisterEvent("SPELLS_CHANGED")
DoiteConditionsEventFrame:RegisterEvent("UNIT_HEALTH")
DoiteConditionsEventFrame:RegisterEvent("PLAYER_COMBO_POINTS")
DoiteConditionsEventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED_GUID")
DoiteConditionsEventFrame:RegisterEvent("BAG_UPDATE")
DoiteConditionsEventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
DoiteConditionsEventFrame:RegisterEvent("RAID_ROSTER_UPDATE")

-- Debug helper for the "Slide window" placeholder.
-- Run in chat:  /run DQ_SpellRecProbe("Fireball")
-- (replace "Fireball" with the ability you're editing)
_G["DQ_SpellRecProbe"] = function(spellName)
  if type(GetSpellIdForName) ~= "function" or type(GetSpellRecField) ~= "function" then
    print("NP APIs missing")
    return
  end
  local ok, id = pcall(GetSpellIdForName, spellName)
  local sid = ok and tonumber(id) or nil
  if not sid or sid <= 0 then
    print("spell not found: " .. tostring(spellName))
    return
  end
  print("spell " .. spellName .. " id=" .. tostring(sid))
  local probes = {
    "recoveryTime", "RecoveryTime",
    "startRecoveryTime", "StartRecoveryTime",
    "categoryRecoveryTime", "CategoryRecoveryTime",
    "startRecoveryCategory", "StartRecoveryCategory",
    "spellCategory", "SpellCategory",
    "cooldown", "Cooldown",
    "baseCooldown", "BaseCooldown",
    "cooldownTime", "CooldownTime",
    "spellCooldown", "SpellCooldown",
    "recovery", "Recovery",
    "manaCost", "stackAmount", "spellIconID",
  }
  local i = 1
  while i <= table.getn(probes) do
    local okV, v = pcall(GetSpellRecField, sid, probes[i])
    if okV and v ~= nil then
      print(string.format("  %-20s = %s (%s)", probes[i], tostring(v), type(v)))
    end
    i = i + 1
  end
end

DoiteConditionsEventFrame:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then
    -- Initial aura scan
    if _G.UnitExists and _G.UnitExists("target") then
      DoiteConditions_ScanUnitAuras("target")
    end
    dirty_ability, dirty_aura, dirty_target, dirty_power = true, true, true, true
    DoiteConditions._daItemSnapshotDirty = true

    -- Prime time-heartbeat flags
    if _RebuildAbilityTimeHeartbeatFlag then
      _RebuildAbilityTimeHeartbeatFlag()
    end
    if _RebuildAuraTimeHeartbeatFlag then
      _RebuildAuraTimeHeartbeatFlag()
    end
    if _RebuildAuraUsageFlags then
      _RebuildAuraUsageFlags()
    end
    if _RebuildTargetModsFlags then
      _RebuildTargetModsFlags()
    end
  elseif event == "UNIT_AURA" then
    if arg1 == "player" then
      dirty_aura = true
      dirty_ability = true

    elseif arg1 == "target" then
      -- Only bother if *any* config ever looks at target auras.
      if _hasAnyTargetAuraUsage then
        -- Coalesce scan/clear into OnUpdate (once per frame)
        DoiteConditions._pendingAuraScanTarget = true
        dirty_aura = true
        dirty_ability = true
      end
    end

  elseif event == "SPELLS_CHANGED" then
    local cache = _G.DoiteConditions_SpellIndexCache
    if cache then
      for k in pairs(cache) do
        cache[k] = nil
      end
    end
    local btCache = _G.DoiteConditions_SpellBookTypeCache
    if btCache then
      for k in pairs(btCache) do
        btCache[k] = nil
      end
    end
    -- Shared-category CD: spell book changed, category mapping may have
    -- shifted (respec, book reshuffle). Drop the lookup cache; live
    -- cooldown records in _sharedCDByCategory self-expire on read.
    if DoiteConditions._abilityCategoryCache then
      for k in pairs(DoiteConditions._abilityCategoryCache) do
        DoiteConditions._abilityCategoryCache[k] = nil
      end
    end
    -- NOTE: the spell-id cache lives in DoiteConditionsTarget.lua as a
    -- file-local; it cannot be reached or cleared from here. That
    -- module rebuilds its cache lazily on its own. Nothing to do here.
    dirty_ability = true

  elseif event == "PLAYER_TARGET_CHANGED" then
    -- If target aura tracking is used anywhere, scan/clear once in OnUpdate. Otherwise, keep snapshot empty so no stale target aura data can ever match.
    if _hasAnyTargetAuraUsage then
      DoiteConditions._pendingAuraScanTarget = true
    else
      -- Reuse the shared cleanup: the previous inline code only wiped
      -- buffs/debuffs and left buffIds/debuffIds populated, so a target
      -- swap with tracking off could still match stale spellIds. The
      -- helper covers all four tables (see _ClearTargetAuraSnapshot).
      DoiteConditions:_ClearTargetAuraSnapshot()
    end

    dirty_target, dirty_aura = true, true
    dirty_ability = true

  elseif event == "SPELL_UPDATE_COOLDOWN"
      or event == "UPDATE_SHAPESHIFT_FORM" then

    dirty_ability = true
    if DoiteConditions and DoiteConditions._hasAnyItemLogic then
      dirty_aura = true
    end

  elseif event == "UNIT_HEALTH" then
    if arg1 == "player" or arg1 == "target" then
      dirty_ability = true
      dirty_aura = true
    end

  elseif event == "PLAYER_COMBO_POINTS" then
    dirty_ability = true
    dirty_aura = true

  elseif event == "UNIT_MANA" or event == "UNIT_RAGE" or event == "UNIT_ENERGY" then
    if arg1 == "player" then
      dirty_power = true
    end

  elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    dirty_ability, dirty_aura = true, true

  elseif event == "UNIT_INVENTORY_CHANGED_GUID" then
    if DoiteConditions and DoiteConditions._hasAnyItemLogic then
      DoiteConditions._daLastItemDirtyAt = GetTime()
      DoiteConditions._weaponStateCache = nil
      if _G.DoiteConditions_ClearTrinketFirstMemory then
        _G.DoiteConditions_ClearTrinketFirstMemory()
      end
      DoiteConditions._daItemSnapshotDirty = true

      -- Temp enchant tracking: force a refresh on next evaluation
      local te = DoiteConditions._daTempEnchantCache
      if te then
        if te[INV_SLOT_MAINHAND] then
          te[INV_SLOT_MAINHAND].t = 0
        end
        if te[INV_SLOT_OFFHAND] then
          te[INV_SLOT_OFFHAND].t = 0
        end
        if te[INV_SLOT_RANGED] then
          te[INV_SLOT_RANGED].t = 0
        end
      end

      dirty_ability = true
    end
  elseif event == "BAG_UPDATE" then
    if DoiteConditions and DoiteConditions._hasAnyItemLogic then
      local now = GetTime()
      local lastDirty = DoiteConditions._daLastItemDirtyAt or 0
      if (now - lastDirty) < 0.05 then
        return
      end
      DoiteConditions._daLastItemDirtyAt = now
      DoiteConditions._daItemSnapshotDirty = true
      dirty_ability = true
    end

  elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
    -- Re-evaluate all conditions when party/raid membership changes
    dirty_ability, dirty_aura = true, true
  end
end)