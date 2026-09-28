---------------------------------------------------------------
-- Modules/DoitePop.lua
-- Cast-confirmation pop animation for player abilities.
--
-- When a visible (ready) Ability icon's spell is successfully
-- cast (SPELL_GO_SELF), a duplicate of the icon is drawn on top
-- of it in a DETACHED overlay frame, then scaled up and faded
-- out. The overlay lives on UIParent at the icon's screen
-- position, so it animates independently of the icon frame's
-- own show/hide lifecycle. The original icon is not touched:
-- it hides/stays visible strictly by its own cooldown logic.
--
-- The overlay uses a two-level structure (holder + anim),
-- mirroring pfUI's actionbar animation. The holder is a
-- stationary frame anchored to UIParent at the icon position.
-- The animated child is anchored to the holder at ZERO offset,
-- so SetScale grows it outward from the visual center without
-- drifting. (In 1.12, SetScale on a frame anchored to UIParent
-- with a non-zero offset visibly slides the frame.)
--
-- Loaded BEFORE DoiteConditions.lua (see DoiteAuras.toc).
-- Tunables are plain constants for easy experimentation.
-- WoW 1.12 | Lua 5.0
---------------------------------------------------------------

local DoitePop = _G["DoitePop"] or {}
_G["DoitePop"] = DoitePop

-- === Tunables ================================================
-- Total animation duration in seconds.
DoitePop.DURATION   = 0.35
-- Scale at the end of the animation (starts at 1.0).
DoitePop.PEAK_SCALE = 1.5
-- =============================================================

-- Per-key active animation state.
DoitePop._active = DoitePop._active or {}
-- Per-key overlay frames (holder + anim + texture), reused.
DoitePop._overlays = DoitePop._overlays or {}
-- Scratch for two-pass cleanup (never mutate while pairs()-ing).
DoitePop._doneScratch = DoitePop._doneScratch or {}

-- Create or fetch the overlay for this key. The overlay is NOT
-- parented to the icon frame -- it lives on UIParent so it is
-- unaffected by the icon hiding during its cooldown.
local function _EnsureOverlay(key)
  local ov = DoitePop._overlays[key]
  if ov then return ov end

  ov = {}
  ov.holder = CreateFrame("Frame", nil, UIParent)
  ov.holder:SetWidth(36)
  ov.holder:SetHeight(36)
  ov.holder:Hide()

  ov.anim = CreateFrame("Frame", nil, ov.holder)
  ov.anim:SetPoint("CENTER", ov.holder, "CENTER", 0, 0)
  ov.anim:SetWidth(36)
  ov.anim:SetHeight(36)
  ov.anim.tex = ov.anim:CreateTexture(nil, "OVERLAY")
  ov.anim.tex:SetAllPoints(ov.anim)
  ov.anim:Hide()

  DoitePop._overlays[key] = ov
  return ov
end

-- Position the overlay holder so its visual center matches the
-- icon frame's center. DoiteAuras anchors every icon as
-- SetPoint("CENTER", UIParent, "CENTER", x, y), so we mirror
-- that anchor exactly.
local function _PositionOverlay(ov, frame)
  local w = (frame.GetWidth and frame:GetWidth()) or 36
  local h = (frame.GetHeight and frame:GetHeight()) or 36

  ov.holder:SetWidth(w)
  ov.holder:SetHeight(h)
  ov.anim:SetWidth(w)
  ov.anim:SetHeight(h)

  local a, parent, b, x, y = frame:GetPoint(1)
  ov.holder:ClearAllPoints()
  if a == "CENTER" and parent == UIParent and b == "CENTER" then
    ov.holder:SetPoint("CENTER", UIParent, "CENTER", x or 0, y or 0)
  else
    -- Fallback: use the frame's rendered center.
    local cx, cy = frame:GetCenter()
    ov.holder:SetPoint("CENTER", UIParent, "CENTER", cx or 0, cy or 0)
  end
end

-- Start (or restart) the pop animation for a key.
function DoitePop.Start(key, frame)
  if not key or not frame then return end

  local ov = _EnsureOverlay(key)
  _PositionOverlay(ov, frame)

  -- Copy the live texture, vertex color and texcoords from the
  -- icon. The original icon is NOT touched.
  local src = frame.icon
  if src and src.GetTexture then
    ov.anim.tex:SetTexture(src:GetTexture())
    if src.GetVertexColor then
      local r, g, b = src:GetVertexColor()
      ov.anim.tex:SetVertexColor(r or 1, g or 1, b or 1, 1)
    else
      ov.anim.tex:SetVertexColor(1, 1, 1, 1)
    end
    if src.GetTexCoord and ov.anim.tex.SetTexCoord then
      ov.anim.tex:SetTexCoord(src:GetTexCoord())
    end
  else
    ov.anim.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    ov.anim.tex:SetVertexColor(1, 1, 1, 1)
  end

  ov.anim:SetAlpha(1)
  ov.anim:SetScale(1)
  ov.holder:Show()
  ov.anim:Show()

  local now = (GetTime and GetTime()) or 0
  DoitePop._active[key] = {
    startTime = now,
    dur       = DoitePop.DURATION,
    ov        = ov,
  }

  DoitePop._EnsureTick()
end

-- Cancel the pop animation for a key immediately.
function DoitePop.Stop(key)
  if not key then return end
  local st = DoitePop._active[key]
  if not st then return end
  DoitePop._active[key] = nil
  if st.ov and st.ov.anim then st.ov.anim:Hide() end
end

function DoitePop.IsActive(key)
  return DoitePop._active[key] ~= nil
end

-- Free all overlay state for a key (called when the icon is
-- removed from the DB).
function DoitePop.CleanupKey(key)
  if not key then return end
  DoitePop.Stop(key)
  local ov = DoitePop._overlays[key]
  if ov then
    if ov.anim then ov.anim:Hide() end
    if ov.holder then ov.holder:Hide() end
    DoitePop._overlays[key] = nil
  end
end

-- === Tick frame ==============================================
-- Hidden when idle; 1.12 does not call OnUpdate on hidden frames,
-- so this costs nothing when no pops are running.

local tickFrame = DoitePop._tickFrame
if not tickFrame then
  tickFrame = CreateFrame("Frame", "DoitePopTick")
  DoitePop._tickFrame = tickFrame
end
tickFrame:Hide()

function DoitePop._EnsureTick()
  if not tickFrame:IsShown() then tickFrame:Show() end
end

tickFrame:SetScript("OnUpdate", function()
  local now = (GetTime and GetTime()) or 0
  local anyAlive = false

  local done = DoitePop._doneScratch
  local dn = 1
  while done[dn] ~= nil do
    done[dn] = nil
    dn = dn + 1
  end

  local k, st
  for k, st in pairs(DoitePop._active) do
    local t = (now - st.startTime) / st.dur
    if t >= 1 then
      done[table.getn(done) + 1] = k
    else
      anyAlive = true
      local ov = st.ov
      if ov and ov.anim then
        ov.anim:SetAlpha(1 - t)
        ov.anim:SetScale(1 + (DoitePop.PEAK_SCALE - 1) * t)
      end
    end
  end

  local cnt = table.getn(done)
  local i = 1
  while i <= cnt do
    local key = done[i]
    local stt = DoitePop._active[key]
    if stt and stt.ov and stt.ov.anim then
      stt.ov.anim:Hide()
    end
    DoitePop._active[key] = nil
    done[i] = nil
    i = i + 1
  end

  if not anyAlive then
    tickFrame:Hide()
  end
end)