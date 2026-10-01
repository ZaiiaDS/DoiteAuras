---------------------------------------------------------------
-- Modules/DoiteConditionsItem.lua
-- Item-related helpers extracted from DoiteConditions.lua:
--   * inventory / bag scanning
--   * trinket synthetic entries (TRINKET1/2/FIRST/BOTH)
--   * weapon-slot synthetic entries (temp enchant tracking)
--   * core item state used by both condition checks and text overlays
--
-- Loaded BEFORE DoiteConditions.lua (see DoiteAuras.toc).
--
-- Please respect license note: Ask permission
-- WoW 1.12 | Lua 5.0
---------------------------------------------------------------

-- Ensure the DoiteConditions table exists. This module loads BEFORE
-- DoiteConditions.lua, so the table may not exist yet.
local DoiteConditions = _G["DoiteConditions"] or {}
_G["DoiteConditions"] = DoiteConditions

local str_find = string.find

-- Tooltip helpers live in DoiteConditions.lua (loaded after this file).
-- Resolve lazily at call time — used only on slow paths.
local function _EnsureTooltip()
  local fn = _G["DoiteConditions_EnsureTooltip"]
  if fn then fn() end
end

local function _GetTipLeft()
  return _G["DoiteConditions_TipLeft"]
end

---------------------------------------------------------------
-- Inventory slot constants
---------------------------------------------------------------
local INV_SLOT_TRINKET1 = 13
local INV_SLOT_TRINKET2 = 14
local INV_SLOT_MAINHAND = 16
local INV_SLOT_OFFHAND  = 17
local INV_SLOT_RANGED   = 18
local INV_SLOT_AMMO     = (GetInventorySlotInfo and GetInventorySlotInfo("AmmoSlot")) or 0

local DOITE_ITEM_CD_IGNORE = 5.0

-- Expose for DoiteConditions.lua (used by _EnsureItemTexture + event handlers)
DoiteConditions.INV_SLOT_TRINKET1 = INV_SLOT_TRINKET1
DoiteConditions.INV_SLOT_TRINKET2 = INV_SLOT_TRINKET2
DoiteConditions.INV_SLOT_MAINHAND = INV_SLOT_MAINHAND
DoiteConditions.INV_SLOT_OFFHAND  = INV_SLOT_OFFHAND
DoiteConditions.INV_SLOT_RANGED   = INV_SLOT_RANGED
DoiteConditions.INV_SLOT_AMMO     = INV_SLOT_AMMO
DoiteConditions.DOITE_ITEM_CD_IGNORE = DOITE_ITEM_CD_IGNORE

local function _SlotIndexForName(name)
  if name == "TRINKET1" then return INV_SLOT_TRINKET1 end
  if name == "TRINKET2" then return INV_SLOT_TRINKET2 end
  if name == "MAINHAND" then return INV_SLOT_MAINHAND end
  if name == "OFFHAND"  then return INV_SLOT_OFFHAND  end
  if name == "RANGED"   then return INV_SLOT_RANGED   end
  if name == "AMMO"     then return INV_SLOT_AMMO     end
  return nil
end
DoiteConditions._SlotIndexForName = _SlotIndexForName

---------------------------------------------------------------
-- Per-key memory for TRINKET_FIRST: "first ready wins" and stays the winner
---------------------------------------------------------------
local _TrinketFirstMemory = {}
DoiteConditions._TrinketFirstMemory = _TrinketFirstMemory

local function _ClearTrinketFirstMemory()
  for k in pairs(_TrinketFirstMemory) do
    _TrinketFirstMemory[k] = nil
  end
end
_G.DoiteConditions_ClearTrinketFirstMemory = _ClearTrinketFirstMemory

---------------------------------------------------------------
-- Item scan cache (inventory + bags)
---------------------------------------------------------------
local _ItemScanCache = {}
local _ItemScanGen = 0
local _ItemScanCacheSize = 0

local function _InvalidateItemScanCache()
  _ItemScanGen = _ItemScanGen + 1

  -- Keep gen bounded (paranoid)
  if _ItemScanGen > 1000000 then
    _ItemScanGen = 1
    for k in pairs(_ItemScanCache) do
      _ItemScanCache[k] = nil
    end
    _ItemScanCacheSize = 0
  end

  -- Hard cap on cached entries to prevent unbounded growth in long sessions.
  if _ItemScanCacheSize > 512 then
    for k in pairs(_ItemScanCache) do
      _ItemScanCache[k] = nil
    end
    _ItemScanCacheSize = 0
  end
end

local _RefreshPlayerItemSnapshot

local function _GetPlayerItemSnapshot()
  local snap = DoiteConditions._daPlayerItemSnapshot
  if not snap then
    snap = {}
    DoiteConditions._daPlayerItemSnapshot = snap
  end
  if DoiteConditions._daItemSnapshotDirty and _RefreshPlayerItemSnapshot then
    _RefreshPlayerItemSnapshot()
  end
  return snap
end

_RefreshPlayerItemSnapshot = function()
  local snap = DoiteConditions._daPlayerItemSnapshot
  if not snap then
    snap = {}
    DoiteConditions._daPlayerItemSnapshot = snap
  end
  if not (UnitExists and UnitExists("player")) then
    DoiteConditions._daItemSnapshotDirty = true
    return
  end
  if not snap.eq then
    snap.eq = {}
  end
  local eq = snap.eq
  local s = 1
  while s <= 19 do
    local info = GetEquippedItem and GetEquippedItem("player", s) or nil
    eq[s] = info
    s = s + 1
  end
  snap.bags = GetBagItems and GetBagItems() or nil
  if GetAmmo then
    local ammoId, ammoCount = GetAmmo()
    snap.ammoId = ammoId
    snap.ammoCount = ammoCount
  else
    snap.ammoId = nil
    snap.ammoCount = 0
  end
  DoiteConditions._daItemSnapshotDirty = false
  _InvalidateItemScanCache()
end

local function _ScanPlayerItemInstances(data)
  if not data then
    return false, false, nil, nil, 0, 0
  end

  local expectedId = data.itemId or data.itemID
  if expectedId then
    expectedId = tonumber(expectedId)
  end
  local expectedName = data.itemName or data.displayName or data.name

  -- Cache key
  local cacheKey = nil
  if expectedId then
    if data._daItemScanCacheKeyType ~= "id" or data._daItemScanCacheKeyId ~= expectedId then
      if data._daItemScanCacheKey then
        if _ItemScanCache[data._daItemScanCacheKey] ~= nil then
          _ItemScanCacheSize = _ItemScanCacheSize - 1
        end
        _ItemScanCache[data._daItemScanCacheKey] = nil
      end
      data._daItemScanCacheKey = "id:" .. expectedId
      data._daItemScanCacheKeyType = "id"
      data._daItemScanCacheKeyId = expectedId
      data._daItemScanCacheKeyName = nil
    end
    cacheKey = data._daItemScanCacheKey
  elseif expectedName and expectedName ~= "" then
    if data._daItemScanCacheKeyType ~= "name" or data._daItemScanCacheKeyName ~= expectedName then
      if data._daItemScanCacheKey then
        if _ItemScanCache[data._daItemScanCacheKey] ~= nil then
          _ItemScanCacheSize = _ItemScanCacheSize - 1
        end
        _ItemScanCache[data._daItemScanCacheKey] = nil
      end
      data._daItemScanCacheKey = "name:" .. expectedName
      data._daItemScanCacheKeyType = "name"
      data._daItemScanCacheKeyName = expectedName
      data._daItemScanCacheKeyId = nil
    end
    cacheKey = data._daItemScanCacheKey
  else
    if data._daItemScanCacheKey then
      if _ItemScanCache[data._daItemScanCacheKey] ~= nil then
        _ItemScanCacheSize = _ItemScanCacheSize - 1
      end
      _ItemScanCache[data._daItemScanCacheKey] = nil
    end
    data._daItemScanCacheKey = nil
    data._daItemScanCacheKeyType = nil
    data._daItemScanCacheKeyId = nil
    data._daItemScanCacheKeyName = nil
  end

  if cacheKey then
    local c = _ItemScanCache[cacheKey]
    if c then
      if (c.gen == _ItemScanGen) then
        return c.hasEquipped, c.hasBag, c.eqSlot, c.bagLoc, c.eqCount, c.bagCount
      end
    end
  end

  local hasEquipped, hasBag = false, false
  local firstEquippedSlot = nil
  local firstBagBag = nil
  local firstBagSlot = nil
  local eqCount, bagCount = 0, 0
  local nameCache = DoiteConditions._itemNameByIdCache
  if not nameCache then
    nameCache = {}
    DoiteConditions._itemNameByIdCache = nameCache
  end

  local bag, slot = nil, nil
  if FindPlayerItemSlot then
    if expectedId then
      bag, slot = FindPlayerItemSlot(expectedId)
    elseif expectedName and expectedName ~= "" then
      bag, slot = FindPlayerItemSlot(expectedName)
    end
  end
  if slot then
    if bag == nil then
      hasEquipped = true
      firstEquippedSlot = slot
    elseif bag >= 0 and bag <= 4 then
      hasBag = true
      firstBagBag = bag
      firstBagSlot = slot
    end
  end

  local snap = _GetPlayerItemSnapshot()
  local eq = snap.eq
  if eq then
    local eslot, itemInfo
    for eslot, itemInfo in pairs(eq) do
      local itemId = itemInfo and itemInfo.itemId
      local match = false
      if itemId then
        if expectedId then
          match = (itemId == expectedId)
        elseif expectedName and expectedName ~= "" then
          local nm = nameCache[itemId]
          if nm == nil then
            nm = GetItemInfo and GetItemInfo(itemId) or nil
            if nm then
              nameCache[itemId] = nm
            end
          end
          match = (nm and nm == expectedName) and true or false
        end
      end
      if match then
        hasEquipped = true
        if not firstEquippedSlot then
          firstEquippedSlot = eslot
        end
        local ccount = tonumber(itemInfo.stackCount) or 1
        if ccount <= 0 then
          ccount = 1
        end
        eqCount = eqCount + ccount
      end
    end
  end

  local bags = snap.bags
  if not bags and GetBagItems then
    bags = GetBagItems()
    snap.bags = bags
  end
  if bags then
    local b = 0
    while b <= 4 do
      local bagData = bags[b]
      if bagData then
        local bslot, itemInfo
        for bslot, itemInfo in pairs(bagData) do
          local itemId = itemInfo and itemInfo.itemId
          local match = false
          if itemId then
            if expectedId then
              match = (itemId == expectedId)
            elseif expectedName and expectedName ~= "" then
              local nm = nameCache[itemId]
              if nm == nil then
                nm = GetItemInfo and GetItemInfo(itemId) or nil
                if nm then
                  nameCache[itemId] = nm
                end
              end
              match = (nm and nm == expectedName) and true or false
            end
          end
          if match then
            hasBag = true
            if firstBagBag == nil then
              firstBagBag = b
              firstBagSlot = bslot
            end
            local ccount = tonumber(itemInfo.stackCount) or 1
            if ccount <= 0 then
              ccount = 1
            end
            bagCount = bagCount + ccount
          end
        end
      end
      b = b + 1
    end
  end

  -- Store in cache (reusing bagLoc table)
  if cacheKey then
    local c = _ItemScanCache[cacheKey]
    if not c then
      c = {}
      _ItemScanCache[cacheKey] = c
      _ItemScanCacheSize = _ItemScanCacheSize + 1
    end

    c.gen = _ItemScanGen
    c.hasEquipped = hasEquipped
    c.hasBag = hasBag
    c.eqSlot = firstEquippedSlot
    c.eqCount = eqCount
    c.bagCount = bagCount

    if firstBagBag ~= nil then
      if not c.bagLoc then
        c.bagLoc = {}
      end
      c.bagLoc.bag = firstBagBag
      c.bagLoc.slot = firstBagSlot
    else
      c.bagLoc = nil
    end

    return c.hasEquipped, c.hasBag, c.eqSlot, c.bagLoc, c.eqCount, c.bagCount
  end

  if firstBagBag ~= nil then
    data._daItemScanBagLoc = data._daItemScanBagLoc or {}
    data._daItemScanBagLoc.bag = firstBagBag
    data._daItemScanBagLoc.slot = firstBagSlot
    return hasEquipped, hasBag, firstEquippedSlot, data._daItemScanBagLoc, eqCount, bagCount
  end

  return hasEquipped, hasBag, firstEquippedSlot, nil, eqCount, bagCount
end

-- Single inventory slot: does it have an item and is that item on cooldown?
-- Returns: hasItem, onCooldown, rem, dur, isUseItem
local function _GetInventorySlotState(slot)
  if not slot then
    return false, false, 0, 0, false
  end
  local link = GetInventoryItemLink and GetInventoryItemLink("player", slot) or nil
  local snap = _GetPlayerItemSnapshot()
  local eq = snap.eq
  local info = eq and eq[slot] or nil
  if (not info) and GetEquippedItem then
    info = GetEquippedItem("player", slot)
  end
  local itemId = info and info.itemId
  if (not itemId) and link then
    local _, _, idStr = str_find(link, "item:(%d+)")
    if idStr then
      itemId = tonumber(idStr)
    end
  end
  if not itemId then
    return false, false, 0, 0, false
  end

  local start, dur, enable = GetInventoryItemCooldown("player", slot)
  local rem, onCd = 0, false
  if start and dur and start > 0 and dur > DOITE_ITEM_CD_IGNORE then
    rem = (start + dur) - GetTime()
    if rem < 0 then
      rem = 0
    end
    onCd = (rem > 0)
  else
    dur = dur or 0
  end

  -- Detect usable / on-use items with API-first checks, then slot-tooltip fallback.
  local useCache = DoiteConditions._itemUseCache
  if not useCache then
    useCache = {}
    DoiteConditions._itemUseCache = useCache
    DoiteConditions._itemUseCacheN = 0
  end

  local cacheKey = itemId

  local isUse = (useCache[cacheKey] == true)
  if not isUse then
    if onCd then
      isUse = true
    end

    if (not isUse) and info then
      if info.hasUseSpell == true or info.hasUseEffect == true then
        isUse = true
      else
        local useSpellId = tonumber(info.useSpellId) or 0
        if useSpellId > 0 then
          isUse = true
        else
          local spellId = tonumber(info.spellId) or 0
          if spellId > 0 then
            isUse = true
          end
        end
      end
    end

    if (not isUse) and GetItemSpell then
      local spellName = GetItemSpell(itemId)
      if spellName and spellName ~= "" then
        isUse = true
      end
    end

    -- Last-resort tooltip parse (uses helpers from DoiteConditions.lua)
    if (not isUse) and DoiteConditionsTooltip and DoiteConditionsTooltip.SetInventoryItem then
      _EnsureTooltip()
      DoiteConditionsTooltip:ClearLines()
      DoiteConditionsTooltip:SetInventoryItem("player", slot)

      local tipLeft = _GetTipLeft()
      if tipLeft then
        local i = 1
        while i <= 15 do
          local fs = tipLeft[i]
          if not fs or not fs.GetText then
            break
          end
          local txt = fs:GetText()
          if txt and txt ~= "" then
            local lower = string.lower(txt)
            if str_find(lower, "use:") or str_find(lower, "use ")
                or str_find(lower, "consume") then
              isUse = true
              break
            end
          end
          i = i + 1
        end
      end
    end

    if isUse then
      useCache[cacheKey] = true

      DoiteConditions._itemUseCacheN = (DoiteConditions._itemUseCacheN or 0) + 1
      if DoiteConditions._itemUseCacheN > 256 then
        for k in pairs(useCache) do
          useCache[k] = nil
        end
        DoiteConditions._itemUseCacheN = 0
      end
    end
  end

  return true, onCd, rem, dur or 0, isUse
end
DoiteConditions._GetInventorySlotState = _GetInventorySlotState

-- Core item state used by both condition checks and text overlays
local _ItemStateScratch = {
  hasItem = false,
  isMissing = false,
  passesWhere = true,
  modeMatches = true,
  rem = nil,
  dur = nil,

  teRem = nil,
  teCharges = nil,
  teItemId = nil,
  teEnchantId = nil,

  eqCount = 0,
  bagCount = 0,
  totalCount = 0,
  effectiveCount = 0,
}

local function _ResetItemState(state)
  state.hasItem = false
  state.isMissing = false
  state.passesWhere = true
  state.modeMatches = true
  state.rem = nil
  state.dur = nil

  state.teRem = nil
  state.teCharges = nil
  state.teItemId = nil
  state.teEnchantId = nil

  state.eqCount = 0
  state.bagCount = 0
  state.totalCount = 0
  state.effectiveCount = 0
end

local function _EvaluateItemCoreState(data, c)
  local state = _ItemStateScratch
  _ResetItemState(state)

  if not data or not c then
    return state
  end

  local invSlotName = c.inventorySlot

  -- --------------------------------------------------------------------
  -- 1) Synthetic inventory-slot entries (equipped trinkets / weapons)
  -- --------------------------------------------------------------------
  if invSlotName and invSlotName ~= "" then
    local mode = c.mode or ""
    local key = data and data.key

    if invSlotName == "TRINKET1" or invSlotName == "TRINKET2"
        or invSlotName == "MAINHAND" or invSlotName == "OFFHAND"
        or invSlotName == "RANGED" or invSlotName == "AMMO" then

      local idx = _SlotIndexForName(invSlotName)
      local hasItem, onCd, rem, dur
      if invSlotName == "AMMO" then
        local snap = _GetPlayerItemSnapshot()
        local ammoId = tonumber(snap.ammoId) or 0
        hasItem = (ammoId > 0)
        onCd = false
        rem = 0
        dur = 0
      else
        hasItem, onCd, rem, dur = _GetInventorySlotState(idx)
      end
      state.hasItem = hasItem
      state.isMissing = not hasItem
      state.rem = rem
      state.dur = dur

      if mode == "oncd" then
        state.modeMatches = (hasItem and onCd)
      elseif mode == "notcd" then
        state.modeMatches = (hasItem and (not onCd))
      elseif mode == "both" then
        state.modeMatches = hasItem
      else
        state.modeMatches = true
      end

      ----------------------------------------------------------------
      -- Temp enchant tracking for weapon-slot synthetic entries
      ----------------------------------------------------------------
      if (invSlotName == "MAINHAND" or invSlotName == "OFFHAND")
          and data.displayName == "---EQUIPPED WEAPON SLOTS---" then

        local needTE = false
        if ((mode == "notcd" or mode == "both")
              and (c.textTimeRemaining == true or c.remainingEnabled == true or c.enchant ~= nil))
            or (c.textStackCounter == true)
            or (c.stacksEnabled == true) then
          needTE = true
        end

        if needTE then
          local now = GetTime()

          local te = DoiteConditions._daTempEnchantCache
          if not te then
            te = {}
            DoiteConditions._daTempEnchantCache = te
          end

          local slotC = te[idx]
          if not slotC then
            slotC = {}
            te[idx] = slotC
          end

          if slotC.endTime and slotC.endTime <= now then
            slotC.endTime = nil
            slotC.tempEnchantId = nil
            slotC.charges = 0
          end

          local lastT = slotC.t or 0
          if (now - lastT) > 0.15 then
            slotC.t = now

            if GetEquippedItem then
              local info = GetEquippedItem("player", idx)

              if info and info.itemId then
                slotC.itemId = info.itemId
              else
                slotC.itemId = nil
              end

              local teId = info and info.tempEnchantId or nil
              local msLeft = info and info.tempEnchantmentTimeLeftMs or nil

              if info and teId and teId > 0 then
                local memE = slotC._e
                if not memE then
                  memE = {}
                  slotC._e = memE
                end
                local memC = slotC._c
                if not memC then
                  memC = {}
                  slotC._c = memC
                end

                -- Composite key for the enchant-charge/expiry memories.
                -- Named teKey (not key) so it does not shadow the outer
                -- `local key = data and data.key` used for
                -- _TrinketFirstMemory above.
                local teKey = tostring(slotC.itemId or 0) .. ":" .. tostring(teId)

                local prevTeId = slotC.tempEnchantId
                if prevTeId ~= teId then
                  slotC.endTime = nil
                  slotC._msLeft = nil
                end
                slotC.tempEnchantId = teId

                if msLeft and msLeft > 0 then
                  local prevMs = slotC._msLeft

                  if (not slotC.endTime) or (not prevMs) then
                    slotC.endTime = now + (msLeft / 1000)
                  else
                    if msLeft > (prevMs + 2000) then
                      slotC.endTime = now + (msLeft / 1000)
                    elseif msLeft < (prevMs - 10000) then
                      slotC.endTime = now + (msLeft / 1000)
                    end
                  end

                  slotC._msLeft = msLeft
                  memE[teKey] = slotC.endTime
                else
                  slotC._msLeft = nil

                  if (not slotC.endTime) or (slotC.endTime <= now) then
                    local endT = memE[teKey]
                    if endT and endT > now then
                      slotC.endTime = endT
                    else
                      slotC.endTime = nil
                    end
                  end
                end

                if info.tempEnchantmentCharges ~= nil then
                  local ch = tonumber(info.tempEnchantmentCharges) or 0
                  if ch < 0 then ch = 0 end
                  slotC.charges = ch
                  memC[teKey] = ch
                else
                  local ch = memC[teKey]
                  if ch == nil then ch = 0 end
                  slotC.charges = ch
                end

              else
                slotC.endTime = nil
                slotC.tempEnchantId = nil
                slotC.charges = 0
              end
            end
          end

          local remSec = 0
          if slotC.endTime then
            remSec = slotC.endTime - now
            if remSec < 0 then remSec = 0 end
          end

          if remSec <= 0 then
            slotC.charges = 0
          end

          state.teRem = remSec
          state.teCharges = slotC.charges or 0
          state.teItemId = slotC.itemId
          state.teEnchantId = slotC.tempEnchantId

          if (mode == "notcd" or mode == "both") then
            if c and (c.textTimeRemaining == true or c.remainingEnabled == true) then
              state.rem = remSec or 0
              state.dur = 0
            end
          end
        end
      end

    elseif invSlotName == "TRINKET_FIRST" or invSlotName == "TRINKET_BOTH" then
      local has1, on1, rem1, dur1, isUse1 = _GetInventorySlotState(INV_SLOT_TRINKET1)
      local has2, on2, rem2, dur2, isUse2 = _GetInventorySlotState(INV_SLOT_TRINKET2)

      local use1 = has1 and isUse1
      local use2 = has2 and isUse2

      if not use1 and not use2 then
        state.hasItem = false
        state.isMissing = true
        state.modeMatches = false
        state.passesWhere = true

        state.eqCount = 0
        state.bagCount = 0
        state.totalCount = 0
        state.effectiveCount = 0

        return state
      end

      state.hasItem = (use1 or use2)
      state.isMissing = not state.hasItem

      if invSlotName == "TRINKET_FIRST" then
        local prevSlot = key
            and _TrinketFirstMemory[key]
            and _TrinketFirstMemory[key].slot
            or nil
        local winner = prevSlot

        if mode == "notcd" then
          local function slotReady(useFlag, onCdFlag)
            return useFlag and (not onCdFlag)
          end

          if winner == INV_SLOT_TRINKET1 and not slotReady(use1, on1) then
            winner = nil
          elseif winner == INV_SLOT_TRINKET2 and not slotReady(use2, on2) then
            winner = nil
          end

          if not winner then
            if slotReady(use1, on1) then
              winner = INV_SLOT_TRINKET1
            elseif slotReady(use2, on2) then
              winner = INV_SLOT_TRINKET2
            end
          end

          if winner == INV_SLOT_TRINKET1 then
            state.modeMatches = slotReady(use1, on1)
            state.rem = rem1
            state.dur = dur1
          elseif winner == INV_SLOT_TRINKET2 then
            state.modeMatches = slotReady(use2, on2)
            state.rem = rem2
            state.dur = dur2
          else
            state.modeMatches = false
          end

          if key then
            if winner then
              _TrinketFirstMemory[key] = _TrinketFirstMemory[key] or {}
              _TrinketFirstMemory[key].slot = winner
            else
              _TrinketFirstMemory[key] = nil
            end
          end

        elseif mode == "both" then
          state.modeMatches = (use1 or use2)

          local found, bestRem, bestDur = false, nil, nil

          if use1 and on1 then
            found = true
            bestRem = rem1
            bestDur = dur1
            winner = INV_SLOT_TRINKET1
          end
          if use2 and on2 then
            if (not found) or (rem2 < bestRem) then
              found = true
              bestRem = rem2
              bestDur = dur2
              winner = INV_SLOT_TRINKET2
            end
          end

          if found then
            state.rem = bestRem
            state.dur = bestDur
          else
            local function slotReady(useFlag, onCdFlag)
              return useFlag and (not onCdFlag)
            end

            if winner == INV_SLOT_TRINKET1 and not slotReady(use1, on1) then
              winner = nil
            elseif winner == INV_SLOT_TRINKET2 and not slotReady(use2, on2) then
              winner = nil
            end

            if not winner then
              if slotReady(use1, on1) then
                winner = INV_SLOT_TRINKET1
              elseif slotReady(use2, on2) then
                winner = INV_SLOT_TRINKET2
              end
            end

            if winner == INV_SLOT_TRINKET1 then
              state.rem = rem1
              state.dur = dur1
            elseif winner == INV_SLOT_TRINKET2 then
              state.rem = rem2
              state.dur = dur2
            else
              state.rem = 0
              state.dur = dur1 or dur2
            end
          end

          if key then
            if winner then
              _TrinketFirstMemory[key] = _TrinketFirstMemory[key] or {}
              _TrinketFirstMemory[key].slot = winner
            else
              _TrinketFirstMemory[key] = nil
            end
          end

        elseif mode == "oncd" then
          local found, bestRem, bestDur = false, nil, nil

          if use1 and on1 then
            found = true
            bestRem = rem1
            bestDur = dur1
            winner = INV_SLOT_TRINKET1
          end
          if use2 and on2 then
            if (not found) or (rem2 < bestRem) then
              found = true
              bestRem = rem2
              bestDur = dur2
              winner = INV_SLOT_TRINKET2
            end
          end

          state.modeMatches = found
          state.rem = bestRem
          state.dur = bestDur

          if key then
            if winner then
              _TrinketFirstMemory[key] = _TrinketFirstMemory[key] or {}
              _TrinketFirstMemory[key].slot = winner
            else
              _TrinketFirstMemory[key] = nil
            end
          end

        else
          state.modeMatches = (use1 or use2)
          state.rem = nil
          state.dur = nil
        end

      else
        -- TRINKET_BOTH
        if mode == "oncd" then
          local ok = true
          if use1 and not on1 then ok = false end
          if use2 and not on2 then ok = false end
          state.modeMatches = ok
          if ok then
            local r1 = (use1 and rem1) or 0
            local r2 = (use2 and rem2) or 0
            state.rem = (r1 > r2) and r1 or r2
            state.dur = dur1 or dur2
          end

        elseif mode == "both" then
          local any = (use1 or use2)
          state.modeMatches = any
          if any then
            local r1 = (use1 and on1 and rem1) or 0
            local r2 = (use2 and on2 and rem2) or 0
            state.rem = (r1 > r2) and r1 or r2
            state.dur = dur1 or dur2
          end

        elseif mode == "notcd" then
          local ok = true
          if use1 and on1 then ok = false end
          if use2 and on2 then ok = false end
          state.modeMatches = ok
          if ok then
            state.rem = 0
            state.dur = dur1 or dur2
          end
        else
          state.modeMatches = true
        end
      end
    end

    state.passesWhere = true

    if state.hasItem then
      if (invSlotName == "MAINHAND" or invSlotName == "OFFHAND")
          and data.displayName == "---EQUIPPED WEAPON SLOTS---"
          and (mode == "notcd" or mode == "both")
          and (c.textStackCounter == true or c.stacksEnabled == true) then

        local ch = state.teCharges
        if ch == nil then ch = 0 end
        if ch < 0 then ch = 0 end

        state.eqCount = ch
        state.bagCount = 0
        state.totalCount = ch
        state.effectiveCount = ch
      else
        local slotCount
        if invSlotName == "AMMO" then
          local snap = _GetPlayerItemSnapshot()
          local cnt = snap.ammoCount or 0
          slotCount = tonumber(cnt) or 0
          if slotCount < 0 then slotCount = 0 end
        else
          slotCount = 0
          if idx ~= nil then
            local snap = _GetPlayerItemSnapshot()
            local eq = snap.eq
            local info = eq and eq[idx] or nil
            if info and info.stackCount ~= nil then
              slotCount = tonumber(info.stackCount) or 0
            end
          end
          if slotCount <= 0 then slotCount = 1 end
        end
        state.eqCount = slotCount
        state.bagCount = 0
        state.totalCount = slotCount
        state.effectiveCount = slotCount
      end
    else
      state.eqCount = 0
      state.bagCount = 0
      state.totalCount = 0
      state.effectiveCount = 0
    end

    return state
  end

  -- --------------------------------------------------------------------
  -- 2) Normal items (Whereabouts: equipped / bag / missing)
  -- --------------------------------------------------------------------
  local hasEquipped, hasBag, eqSlot, bagLoc, eqCount, bagCount = _ScanPlayerItemInstances(data)
  local missing = (not hasEquipped and not hasBag)

  state.hasItem = not missing
  state.isMissing = missing

  state.eqCount = eqCount or 0
  state.bagCount = bagCount or 0
  state.totalCount = (state.eqCount or 0) + (state.bagCount or 0)

  local passWhere = false
  if c.whereEquipped and hasEquipped then passWhere = true end
  if c.whereBag and hasBag then passWhere = true end
  if c.whereMissing and missing then passWhere = true end
  state.passesWhere = passWhere

  local eff = 0
  if c.whereEquipped and state.eqCount and state.eqCount > 0 then
    eff = eff + state.eqCount
  end
  if c.whereBag and state.bagCount and state.bagCount > 0 then
    eff = eff + state.bagCount
  end
  state.effectiveCount = eff

  if not passWhere then
    return state
  end

  local kind, loc = nil, nil
  if eqSlot then
    kind = "inv"
    loc = eqSlot
  elseif bagLoc then
    kind = "bag"
    loc = bagLoc
  end

  if kind and loc then
    local hasItem, onCd, rem, dur
    local snap = _GetPlayerItemSnapshot()
    if kind == "inv" then
      local eq = snap.eq
      local eqInfo = eq and eq[loc] or nil
      if (not eqInfo) and GetEquippedItem then
        eqInfo = GetEquippedItem("player", loc)
      end
      hasItem = (eqInfo and eqInfo.itemId) and true or false
      local start, dur0, enable = GetInventoryItemCooldown("player", loc)
      if start and dur0 and start > 0 and dur0 > DOITE_ITEM_CD_IGNORE then
        rem = (start + dur0) - GetTime()
        if rem < 0 then rem = 0 end
        onCd = (rem > 0)
        dur = dur0
      else
        onCd = false
        rem = 0
        dur = dur0 or 0
      end
    else
      local bags = snap.bags
      local bagData = bags and bags[loc.bag] or nil
      local bInfo = bagData and bagData[loc.slot] or nil
      if (not bInfo) and GetBagItem then
        bInfo = GetBagItem(loc.bag, loc.slot)
      end
      hasItem = (bInfo and bInfo.itemId) and true or false
      local start, dur0, enable = GetContainerItemCooldown(loc.bag, loc.slot)
      if start and dur0 and start > 0 and dur0 > DOITE_ITEM_CD_IGNORE then
        rem = (start + dur0) - GetTime()
        if rem < 0 then rem = 0 end
        onCd = (rem > 0)
        dur = dur0
      else
        onCd = false
        rem = 0
        dur = dur0 or 0
      end
    end

    if not state.hasItem and hasItem then
      state.hasItem = true
      state.isMissing = false
    end

    state.rem = rem
    state.dur = dur

    local mode = c.mode or ""
    if mode == "oncd" then
      state.modeMatches = (hasItem and onCd)
    elseif mode == "notcd" then
      state.modeMatches = (hasItem and (not onCd))
    elseif mode == "both" then
      state.modeMatches = hasItem
    else
      state.modeMatches = true
    end
  else
    if missing and c.whereMissing then
      state.modeMatches = true
      state.rem = 0
      state.dur = 0
    else
      local mode = c.mode or ""
      if mode == "oncd" or mode == "notcd" then
        state.modeMatches = false
      end
    end
  end

  return state
end
DoiteConditions._EvaluateItemCoreState = _EvaluateItemCoreState