---------------------------------------------------------------
-- Modules/DoiteSlide.lua
-- Slide manager extracted from DoiteConditions.lua:
--   * SlideMgr table (active slides by key)
--   * per-frame ticker that prunes expired slides and keeps the
--     main OnUpdate repainting while any slide is active
--
-- Loaded BEFORE DoiteConditions.lua (see DoiteAuras.toc).
--
-- Please respect license note: Ask permission
-- WoW 1.12 | Lua 5.0
---------------------------------------------------------------

local DoiteSlide = {}
_G["DoiteSlide"] = DoiteSlide

local GetTime = GetTime

local SlideMgr = {
  active = {},
}
-- Same global name external code already relies on.
_G.DoiteConditions_SlideMgr = SlideMgr
DoiteSlide.SlideMgr = SlideMgr

-- Bridge: DoiteConditions.lua installs a callback here at load time
-- so that SlideTick can flip its file-local `dirty_ability` without
-- us having to reach into it via _G on every frame.
local _MarkDirtyAbility = nil
function DoiteSlide.SetMarkDirtyHandler(fn)
  _MarkDirtyAbility = fn
end

local _slideTick = CreateFrame("Frame", "DoiteSlideTick")
_slideTick:Hide()
_slideTick:SetScript("OnUpdate", function()
  local now = GetTime()
  local anyActive = false

  for key, s in pairs(SlideMgr.active) do
    if now >= s.endTime then
      SlideMgr.active[key] = nil
    else
      anyActive = true
    end
  end

  -- While sliding, force abilities to re-paint frequently so positions update smoothly.
  if anyActive then
    if _MarkDirtyAbility then
      _MarkDirtyAbility()
    end
  else
    this:Hide()
  end
end)

-- Begin or refresh an animation for 'key'
-- endTime = GetTime() + remaining  (cap remaining inside caller)
function SlideMgr:StartOrUpdate(key, dir, baseX, baseY, endTime, fade)
  local st = self.active[key]
  local now = GetTime()

  if not endTime then
    endTime = now
  end

  if not st then
    st = {
      dir = dir or "center",
      baseX = baseX or 0,
      baseY = baseY or 0,
      endTime = endTime,
      fade = (fade == true) and true or false,
    }

    -- Capture the length of this slide window once so that
    -- t runs cleanly from 1 → 0 and center alpha from 0 → 1.
    local total = st.endTime - now
    if not total or total <= 0 then
      total = 0.01
    end
    st.total = total

    self.active[key] = st
  else
    st.dir = dir or st.dir
    st.baseX = baseX or st.baseX
    st.baseY = baseY or st.baseY
    st.fade = (fade == true) and true or false

    local curEnd = st.endTime or now
    local newEnd = endTime

    local curRem = curEnd - now
    local newRem = newEnd - now
    if curRem < 0 then
      curRem = 0
    end
    if newRem < 0 then
      newRem = 0
    end

    -- Anti-jitter:
    if (newRem > 0.10) and (newRem <= 1.60) and (curRem > 1.60) then
      newEnd = curEnd
      newRem = curRem
    else
      -- Ignore tiny backwards jitter (micro refresh noise)
      if (newEnd < curEnd) and ((curEnd - newEnd) < 0.20) then
        newEnd = curEnd
        newRem = curRem
      end
    end

    -- Hard cap: while sliding, the caller should NOT extend the slide
    local total = st.total or 0
    if total and total > 0 then
      local maxEnd = now + total
      if newEnd > maxEnd then
        newEnd = maxEnd
      end
    end

    if newEnd > curEnd then
      local grow = newEnd - now
      if grow > (st.total or 0) and grow <= 3.05 then
        st.total = grow
      end
    end

    st.endTime = newEnd
    -- NOTE: st.total is intentionally stable (except the small "grow" fix above)
  end

  _slideTick:Show()
end

function SlideMgr:Stop(key)
  self.active[key] = nil
end

-- Query current offsets/alpha. Returns:
-- active:boolean, dx:number, dy:number, alpha:number, suppressGlow:boolean, suppressGrey:boolean
function SlideMgr:Get(key)
  local st = self.active[key]
  if not st then
    return false, 0, 0, 1, false, false
  end

  local now = GetTime()
  local total = st.total or 3.0
  if total <= 0 then
    total = 0.01
  end

  local remaining = (st.endTime or now) - now
  if remaining < 0 then
    remaining = 0
  end

  -- if endTime drifted beyond the slide window, pull it back.
  if remaining > total then
    if remaining > (total + 0.25) then
      st.endTime = now + total
    end
    remaining = total
  end

  -- t goes from 1 → 0 over the slide window
  local t = remaining / total
  if t < 0 then
    t = 0
  elseif t > 1 then
    t = 1
  end

  local farX, farY = 0, 0
  if st.dir == "left" then
    farX, farY = -80, 0
  elseif st.dir == "right" then
    farX, farY = 80, 0
  elseif st.dir == "up" then
    farX, farY = 0, 80
  elseif st.dir == "down" then
    farX, farY = 0, -80
  else
    farX, farY = 0, 0
  end

  local dx = farX * t
  local dy = farY * t

  -- Fade in from invisible to fully visible while sliding.
  -- Always for center direction (default behavior); only when the
  -- Fading option is on for left/right/up/down.
  local alpha
  if st.fade or st.dir == "center" then
    alpha = 1.0 - t
  else
    alpha = 1.0
  end
  if alpha < 0 then
    alpha = 0
  elseif alpha > 1 then
    alpha = 1
  end

  return true, dx, dy, alpha, true, true
end

-- For ApplyVisuals to get latest base anchoring while sliding
function SlideMgr:UpdateBase(key, baseX, baseY)
  local st = self.active[key]
  if st then
    st.baseX = baseX or st.baseX
    st.baseY = baseY or st.baseY
  end
end

-- For ApplyVisuals to read current base (even if not sliding)
function SlideMgr:GetBase(key)
  local st = self.active[key]
  if st then
    return st.baseX or 0, st.baseY or 0
  end
  return 0, 0
end