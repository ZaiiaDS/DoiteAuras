---------------------------------------------------------------
-- DoiteConditionsIcons.lua
-- Icon-frame lookup, Nampower spell name/texture cache, sound
-- helpers, and synthetic texture resolvers for Ability / Item.
-- Extracted from DoiteConditions.lua (Phase 4 of the split).
--
-- Functions in this file:
--   _NP_SpellNameAndTexture  - spellId -> (name, texturePath), cached
--   _GetIconFrame            - key -> DoiteIcon_<key> frame, cached
--   _ForgetIconFrame         - drop a stale frame ref for a key
--   _DoitePlayConfiguredSound - play a sound file by name (guarded)
--   _DoiteHandleEdgeSound    - rising-edge sound trigger per state key
--   _EnsureAbilityTexture    - fill icon texture for Ability if missing
--   _EnsureItemTexture       - fill icon texture for synthetic Item slots
--
-- Loaded AFTER Spell and Item modules (uses _GetSpellIndexByName,
-- _SlotIndexForName, _TrinketFirstMemory, _GetInventorySlotState).
-- Loaded BEFORE DoiteConditions.lua, which consumes all of the above
-- via the exports below.
--
-- Public globals:
--   _G["DoiteConditions_SpellNameAndTexture"]
--   _G["DoiteConditions_GetIconFrame"]
--   _G["DoiteConditions_ForgetIconFrame"]
--   _G["DoiteConditions_HandleEdgeSound"]
--   _G["DoiteConditions_EnsureAbilityTexture"]
--   _G["DoiteConditions_EnsureItemTexture"]
--   _G["DoiteConditions_SoundStateByKey"]    (table; per-key cleaned via CleanupKey)
---------------------------------------------------------------

local DoiteConditions = _G["DoiteConditions"] or {}
_G["DoiteConditions"] = DoiteConditions

-- Deps from sibling modules.
local _GetSpellIndexByName   = _G["DoiteConditions_GetSpellIndexByName"]
local _SlotIndexForName      = DoiteConditions._SlotIndexForName
local _TrinketFirstMemory    = DoiteConditions._TrinketFirstMemory
local _GetInventorySlotState = DoiteConditions._GetInventorySlotState

-- Icon cache table (shared with DoiteAuras.lua).
if not _G["DoiteAurasDB"] then
  _G["DoiteAurasDB"] = {}
end
DoiteAurasDB = _G["DoiteAurasDB"]
DoiteAurasDB.cache = DoiteAurasDB.cache or {}
local IconCache = DoiteAurasDB.cache

-- Weapon-slot constants used by _EnsureItemTexture for TRINKET_* paths.
local INV_SLOT_TRINKET1 = 13
local INV_SLOT_TRINKET2 = 14

-- =================================================================
-- Nampower spell name + texture cache
-- =================================================================
local _NP_SpellNameTexCache = {}
local _NP_SpellNameTexCacheN = 0

local function _NP_SpellNameAndTexture(spellId)
  local sid = tonumber(spellId) or 0
  if sid <= 0 then
    return nil, nil
  end

  local c = _NP_SpellNameTexCache[sid]
  if c then
    return c[1], c[2]
  end

  local name = nil
  if type(GetSpellNameAndRankForId) == "function" then
    local okName, n = pcall(GetSpellNameAndRankForId, sid)
    if okName and type(n) == "string" and n ~= "" then
      name = n
    end
  end

  local tex = nil
  if type(GetSpellRecField) == "function" and type(GetSpellIconTexture) == "function" then
    local okIconId, iconId = pcall(GetSpellRecField, sid, "spellIconID")
    if okIconId and iconId and iconId > 0 then
      local okTex, t = pcall(GetSpellIconTexture, iconId)
      if okTex and type(t) == "string" and t ~= "" then
        tex = t
      end
    end
  end

  if name or tex then
    _NP_SpellNameTexCache[sid] = { name, tex }
    _NP_SpellNameTexCacheN = _NP_SpellNameTexCacheN + 1
    if _NP_SpellNameTexCacheN > 1024 then
      for k in pairs(_NP_SpellNameTexCache) do
        _NP_SpellNameTexCache[k] = nil
      end
      _NP_SpellNameTexCacheN = 0
    end
  end

  return name, tex
end

-- =================================================================
-- Icon frame getter (hot path: ApplyVisuals / aura scans / time text)
-- =================================================================
local _GIF_Cached   -- lazy-resolved reference to DoiteAuras_GetIconFrame

local function _GetIconFrame(k)
  if not k then
    return nil
  end

  if not _GIF_Cached then
    _GIF_Cached = DoiteAuras_GetIconFrame
  end
  if _GIF_Cached then
    local f = _GIF_Cached(k)
    if f then
      return f
    end
  end

  local byKey = DoiteConditions._iconFrameByKey
  if byKey and byKey[k] then
    return byKey[k]
  end

  local f = _G["DoiteIcon_" .. k]
  if f then
    if not byKey then
      byKey = {}
      DoiteConditions._iconFrameByKey = byKey
      DoiteConditions._iconFrameNameByKey = {}
    end
    byKey[k] = f

    -- Periodic prune: if the cache grew well beyond the current DB size,
    -- drop entries that no longer correspond to a live DB key. Prevents
    -- unbounded growth across long sessions with add/remove churn.
    DoiteConditions._iconFramePruneTick = (DoiteConditions._iconFramePruneTick or 0) + 1
    if DoiteConditions._iconFramePruneTick >= 256 then
      DoiteConditions._iconFramePruneTick = 0

      local n = 0
      local kk
      for kk in pairs(byKey) do
        n = n + 1
        if n > 128 then
          break
        end
      end

      if n > 128 then
        local db = DoiteAurasDB and DoiteAurasDB.spells
        for kk, ff in pairs(byKey) do
          if (not ff) or (db and not db[kk]) then
            byKey[kk] = nil
          end
        end
      end
    end
  end
  return f
end

local function _ForgetIconFrame(k)
  if DoiteConditions and DoiteConditions._iconFrameByKey then
    DoiteConditions._iconFrameByKey[k] = nil
  end
end

-- =================================================================
-- Sound helpers (rising-edge detection per state key)
-- =================================================================
local _SoundStateByKey = {}

local function _DoitePlayConfiguredSound(fileName)
  if not fileName or fileName == "" then
    return
  end
  if not PlaySoundFile then
    return
  end
  local path = "Interface\\AddOns\\DoiteAuras\\Sounds\\" .. fileName
  pcall(PlaySoundFile, path)
end

local function _DoiteHandleEdgeSound(key, stateKey, nowActive, enabledFlag, fileName)
  if not key or not stateKey then
    return
  end
  local st = _SoundStateByKey[key]
  if not st then
    st = {}
    _SoundStateByKey[key] = st
  end

  local prev = st[stateKey]
  st[stateKey] = nowActive and true or false

  if prev == nil then
    return
  end
  if (not prev) and nowActive and enabledFlag and fileName and fileName ~= "" then
    _DoitePlayConfiguredSound(fileName)
  end
end

-- =================================================================
-- Texture resolvers
-- =================================================================

local function _EnsureAbilityTexture(frame, data)
  if not frame or not frame.icon or not data then
    return
  end
  if frame.icon:GetTexture() then
    return
  end

  local spellName = data.displayName or data.name
  if not spellName then
    return
  end

  local idx = _GetSpellIndexByName(spellName)
  local bt = _G.DoiteConditions_SpellBookTypeCache[spellName]
  if idx then
    local tex = GetSpellTexture(idx, bt or BOOKTYPE_SPELL)
    if tex then
      frame.icon:SetTexture(tex)
      IconCache[spellName] = tex -- persist
    end
  end
end

-- Ensure a synthetic Item slot icon (equipped trinkets / weapons) has a real texture
local function _EnsureItemTexture(frame, data)
  if not frame or not frame.icon or not data then
    return
  end
  if not data.conditions or not data.conditions.item then
    return
  end

  local c = data.conditions.item
  local invSlotName = c.inventorySlot
  if not invSlotName or invSlotName == "" then
    return
  end

  local nameKey = data.displayName or data.name
  if not nameKey or nameKey == "" then
    return
  end

  local slot = nil

  if invSlotName == "TRINKET1" or invSlotName == "TRINKET2"
      or invSlotName == "MAINHAND" or invSlotName == "OFFHAND"
      or invSlotName == "RANGED" or invSlotName == "AMMO" then

    slot = _SlotIndexForName(invSlotName)

  elseif invSlotName == "TRINKET_FIRST" then
    -- Prefer the remembered winner for this key if exist
    if data.key and _TrinketFirstMemory[data.key]
        and _TrinketFirstMemory[data.key].slot then
      slot = _TrinketFirstMemory[data.key].slot
    else
      -- Fallback: whichever trinket slot currently has an item (1, then 2)
      local has1 = GetInventoryItemLink("player", INV_SLOT_TRINKET1) ~= nil
      local has2 = GetInventoryItemLink("player", INV_SLOT_TRINKET2) ~= nil
      if has1 then
        slot = INV_SLOT_TRINKET1
      elseif has2 then
        slot = INV_SLOT_TRINKET2
      end
    end

  elseif invSlotName == "TRINKET_BOTH" then
    -- Prefer the usable trinket's texture.
    -- If BOTH are usable, prefer slot 1.
    -- If neither is usable (no "Use:" effect), fall back cosmetically: slot 1 if present else slot 2.
    local has1, on1, rem1, dur1, isUse1 = _GetInventorySlotState(INV_SLOT_TRINKET1)
    local has2, on2, rem2, dur2, isUse2 = _GetInventorySlotState(INV_SLOT_TRINKET2)

    local use1 = has1 and isUse1
    local use2 = has2 and isUse2

    if use1 and use2 then
      slot = INV_SLOT_TRINKET1
    elseif use1 then
      slot = INV_SLOT_TRINKET1
    elseif use2 then
      slot = INV_SLOT_TRINKET2
    else
      local link1 = GetInventoryItemLink("player", INV_SLOT_TRINKET1)
      local link2 = GetInventoryItemLink("player", INV_SLOT_TRINKET2)
      if link1 then
        slot = INV_SLOT_TRINKET1
      elseif link2 then
        slot = INV_SLOT_TRINKET2
      end
    end
  end

  if not slot then
    return
  end

  local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", slot)
  if not tex then
    return
  end

  local curTex = frame.icon:GetTexture()
  if curTex ~= tex then
    frame.icon:SetTexture(tex)
  end

  IconCache[nameKey] = tex
  DoiteAurasDB.cache[nameKey] = tex
  if DoiteAurasDB.spells and data.key and DoiteAurasDB.spells[data.key] then
    DoiteAurasDB.spells[data.key].iconTexture = tex
  end
end

-- =================================================================
-- Exports
-- =================================================================
_G["DoiteConditions_SpellNameAndTexture"]  = _NP_SpellNameAndTexture
_G["DoiteConditions_GetIconFrame"]         = _GetIconFrame
_G["DoiteConditions_ForgetIconFrame"]      = _ForgetIconFrame
_G["DoiteConditions_HandleEdgeSound"]      = _DoiteHandleEdgeSound
_G["DoiteConditions_EnsureAbilityTexture"] = _EnsureAbilityTexture
_G["DoiteConditions_EnsureItemTexture"]    = _EnsureItemTexture
_G["DoiteConditions_SoundStateByKey"]      = _SoundStateByKey