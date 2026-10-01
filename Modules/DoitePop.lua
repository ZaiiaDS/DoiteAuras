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
-- A soft additive glow grows along with the icon and fades with
-- it, so the icon appears to dissolve into light at the peak.
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
-- Tunables live in DoiteAurasDB.pop and are edited from the
-- "CAST POPUP" section of the Settings window; the module snapshots
-- them per pop in Start(), so mid-flight changes take effect on the
-- next cast.
-- WoW 1.12 | Lua 5.0
---------------------------------------------------------------

local DoitePop = _G["DoitePop"] or {}
_G["DoitePop"] = DoitePop

-- === Settings ================================================
-- Editable from DoiteSettings (Cast Popup section). Stored in
-- DoiteAurasDB.pop and normalized by GetSettings() so old saves
-- without these fields load cleanly.
-- =============================================================

-- NOTE: the `glow*` fields below are the additive flash drawn *by
-- this pop animation*. They are unrelated to DoiteAurasDB.glow,
-- which drives the persistent icon glow effect managed by
-- DoiteGlow.lua. Two different systems, two different DB tables.
DoitePop.DEFAULTS = {
  duration       = 0.35,   -- total animation length, seconds
  peakScale      = 1.5,    -- scale of the icon copy at the end
  glowAlpha      = 0.3,    -- peak alpha of the additive flash
  glowScaleExtra = 3.0,    -- extra scale on top of 1.0 at the end
  glowTexture    = "Interface\\Cooldown\\star4",
  glowR          = 1,
  glowG          = 1,
  glowB          = 1,
}

-- Static textures offered in the dropdown. Add more entries here if
-- you want them selectable from Settings.
DoitePop.TEXTURE_CHOICES = {
  { text = "Cooldown star",      value = "Interface\\Cooldown\\star4" },
  { text = "Cast bar spark",     value = "Interface\\CastingBar\\UI-CastingBar-Spark" },
  { text = "Minimize highlight", value = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight" },
}

function DoitePop.GetSettings()
  DoiteAurasDB = DoiteAurasDB or {}
  DoiteAurasDB.pop = DoiteAurasDB.pop or {}
  local s = DoiteAurasDB.pop
  local k, v
  for k, v in pairs(DoitePop.DEFAULTS) do
    if s[k] == nil then s[k] = v end
  end
  return s
end

-- =================================================================
-- MPOWA texture family. Same values as DoiteGlow, but declared here
-- so Pop does not depend on DoiteGlow's load order.
-- =================================================================
DoitePop.MPOWA_PREFIX = "Interface\\AddOns\\DoiteAuras\\Textures\\MPOWA\\Aura"
DoitePop.MPOWA_COUNT  = 246

-- Human-readable label for the current glow texture. Handles the
-- static TEXTURE_CHOICES list and the MPOWA family; falls back to "?".
function DoitePop.GetTextureLabelForValue(v)
  if type(v) ~= "string" or v == "" then return "?" end

  local prefix = DoitePop.MPOWA_PREFIX
  if string.sub(v, 1, string.len(prefix)) == prefix then
    local rest = string.sub(v, string.len(prefix) + 1)
    if string.find(rest, "^%d+$") then
      return "MPOWA - Aura" .. rest
    end
  end

  local list = DoitePop.TEXTURE_CHOICES
  if type(list) == "table" then
    local i
    for i = 1, table.getn(list) do
      if list[i].value == v then return list[i].text end
    end
  end

  return "?"
end

-- Entry list for the generic DoiteTexturePicker grid: static client
-- textures first, then MPOWA. No `tc` on any of them -- they are
-- drawn whole.
function DoitePop.GetPickerEntries()
  local entries = {}

  local list = DoitePop.TEXTURE_CHOICES
  if type(list) == "table" then
    local i
    for i = 1, table.getn(list) do
      local e = list[i]
      entries[table.getn(entries) + 1] = {
        value = e.value,
        label = e.text,
      }
    end
  end

  local prefix = DoitePop.MPOWA_PREFIX
  local n      = DoitePop.MPOWA_COUNT or 0
  local i
  for i = 1, n do
    entries[table.getn(entries) + 1] = {
      value = prefix .. tostring(i),
      label = "MPOWA - Aura" .. tostring(i),
    }
  end

  return entries
end

-- =================================================================
-- Presets.
--
-- DoiteAurasDB.popPresets[name] = { snapshot of editable fields }
-- DoiteAurasDB.popActivePreset = name | nil
--
-- A special "default" preset is always present, seeded on load from
-- the file's DEFAULTS, and cannot be deleted or renamed.
-- =================================================================
DoitePop.DEFAULT_PRESET_NAME = "default"

local POP_PRESET_FIELDS = {
  "duration", "peakScale", "glowAlpha", "glowScaleExtra",
  "glowTexture",
  "glowR", "glowG", "glowB",
}

function DoitePop.IsDefaultPreset(name)
  return name == DoitePop.DEFAULT_PRESET_NAME
end

function DoitePop.GetPresetSnapshot()
  local s = DoitePop.GetSettings()
  local snap = {}
  local i
  for i = 1, table.getn(POP_PRESET_FIELDS) do
    local k = POP_PRESET_FIELDS[i]
    snap[k] = s[k]
  end
  return snap
end

function DoitePop.ApplyPresetSnapshot(t)
  if type(t) ~= "table" then return end
  local s = DoitePop.GetSettings()
  local i
  for i = 1, table.getn(POP_PRESET_FIELDS) do
    local k = POP_PRESET_FIELDS[i]
    if t[k] ~= nil then s[k] = t[k] end
  end
end

function DoitePop.GenerateNewPresetName()
  DoiteAurasDB = DoiteAurasDB or {}
  local presets = DoiteAurasDB.popPresets or {}
  local n = 1
  while n < 1000 do
    local name = string.format("pop%02d", n)
    if presets[name] == nil then return name end
    n = n + 1
  end
  return "pop" .. tostring(math.random(1000, 9999))
end

function DoitePop.SaveCurrentAsPreset()
  DoitePop._EnsureDefaultPreset()
  DoiteAurasDB = DoiteAurasDB or {}
  DoiteAurasDB.popPresets = DoiteAurasDB.popPresets or {}
  local name = DoitePop.GenerateNewPresetName()
  DoiteAurasDB.popPresets[name] = DoitePop.GetPresetSnapshot()
  DoiteAurasDB.popActivePreset = name
  return name
end

function DoitePop.DeletePreset(name)
  DoitePop._EnsureDefaultPreset()
  if DoitePop.IsDefaultPreset(name) then return false end
  local db = _G["DoiteAurasDB"]
  if not db or not db.popPresets or not name then return false end
  if not db.popPresets[name] then return false end
  db.popPresets[name] = nil
  if db.popActivePreset == name then
    db.popActivePreset = nil
  end
  return true
end

function DoitePop.RenamePreset(from, to)
  DoitePop._EnsureDefaultPreset()
  if DoitePop.IsDefaultPreset(from) then return false end
  if DoitePop.IsDefaultPreset(to) then return false end
  local db = _G["DoiteAurasDB"]
  if not db or not db.popPresets then return false end
  if not from or not to or to == "" then return false end
  local p = db.popPresets[from]
  if not p then return false end
  if from == to then return true end
  if db.popPresets[to] then return false end
  db.popPresets[to] = p
  db.popPresets[from] = nil
  if db.popActivePreset == from then
    db.popActivePreset = to
  end
  return true
end

-- Sorted list of preset names, "default" pinned first.
function DoitePop.ListPresets()
  DoitePop._EnsureDefaultPreset()
  local db = _G["DoiteAurasDB"]
  if not db or not db.popPresets then return {} end
  local out = {}
  local k
  for k in pairs(db.popPresets) do
    table.insert(out, k)
  end
  table.sort(out)

  local defIdx = nil
  local i
  for i = 1, table.getn(out) do
    if DoitePop.IsDefaultPreset(out[i]) then
      defIdx = i
      break
    end
  end
  if defIdx and defIdx > 1 then
    local d = out[defIdx]
    table.remove(out, defIdx)
    table.insert(out, 1, d)
  end
  return out
end

function DoitePop._EnsureDefaultPreset()
  DoiteAurasDB = DoiteAurasDB or {}
  DoiteAurasDB.popPresets = DoiteAurasDB.popPresets or {}
  local def = DoiteAurasDB.popPresets[DoitePop.DEFAULT_PRESET_NAME]
  if def == nil then
    def = {}
    local k, v
    for k, v in pairs(DoitePop.DEFAULTS) do
      def[k] = v
    end
    DoiteAurasDB.popPresets[DoitePop.DEFAULT_PRESET_NAME] = def
  end
end

function DoitePop.ApplyActivePresetOnLoad()
  -- Guard is a runtime-only flag on DoitePop. It must NOT live on
  -- DoiteAurasDB: that table is written to disk, so a persisted flag
  -- would skip re-application on every later login (the preset would
  -- only ever apply on the very first session, then silently stop).
  if DoitePop._activePresetApplied == true then return end
  DoitePop._activePresetApplied = true

  DoitePop._EnsureDefaultPreset()

  local db = _G["DoiteAurasDB"]
  if not db then return end
  local name = db.popActivePreset
  if not name or name == "" then return end
  local presets = db.popPresets
  if not presets then return end
  local p = presets[name]
  if not p then
    db.popActivePreset = nil
    return
  end
  DoitePop.ApplyPresetSnapshot(p)
end

-- Defer ApplyActivePresetOnLoad to ADDON_LOADED: on this client the
-- per-character SavedVariables are NOT populated when the .lua chunk
-- runs, so a file-scope call would seed a temporary table that WoW
-- then replaces. ADDON_LOADED fires after DoiteAurasDB has its real
-- contents, so the preset seeding lands in the right place.
do
  local f = CreateFrame("Frame")
  f:RegisterEvent("ADDON_LOADED")
  f:SetScript("OnEvent", function()
    if arg1 == "DoiteAuras" then
      DoitePop.ApplyActivePresetOnLoad()
      f:UnregisterEvent("ADDON_LOADED")
    end
  end)
end

-- Per-key active animation state.
DoitePop._active = DoitePop._active or {}
-- Per-key overlay frames (holder + anim + glow), reused.
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

  -- Glow: a sibling of ov.anim inside the same holder. Also
  -- anchored at zero offset so its own SetScale grows outward
  -- from the visual center without drifting.
  ov.glow = CreateFrame("Frame", nil, ov.holder)
  ov.glow:SetPoint("CENTER", ov.holder, "CENTER", 0, 0)
  ov.glow:SetWidth(36)
  ov.glow:SetHeight(36)
  ov.glow.tex = ov.glow:CreateTexture(nil, "OVERLAY")
  ov.glow.tex:SetAllPoints(ov.glow)
  ov.glow.tex:SetBlendMode("ADD")
  -- Texture is set on every Start() so a change in Settings takes
  -- effect on the next pop without rebuilding the overlay.
  ov.glow:Hide()

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
  ov.glow:SetWidth(w)
  ov.glow:SetHeight(h)

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
--
-- Every tunable is read fresh from DoiteAurasDB.pop at Start and
-- snapshotted into the per-key state, so mid-flight changes from
-- the Settings window take effect on the NEXT pop, not on the one
-- already running. The tick reads the snapshot, not the DB.
function DoitePop.Start(key, frame)
  if not key or not frame then return end

  local ov = _EnsureOverlay(key)
  _PositionOverlay(ov, frame)

  local s = DoitePop.GetSettings()

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

  -- Glow: texture + starting state (transparent, no extra scale).
  ov.glow.tex:SetTexture(s.glowTexture)
  ov.glow.tex:SetVertexColor(s.glowR, s.glowG, s.glowB, 0)
  ov.glow:SetScale(1)

  ov.holder:Show()
  ov.anim:Show()
  ov.glow:Show()

  local now = (GetTime and GetTime()) or 0
  DoitePop._active[key] = {
    startTime      = now,
    dur            = s.duration,
    peakScale      = s.peakScale,
    glowAlpha      = s.glowAlpha,
    glowScaleExtra = s.glowScaleExtra,
    glowR          = s.glowR,
    glowG          = s.glowG,
    glowB          = s.glowB,
    ov             = ov,
  }

  DoitePop._EnsureTick()
end

-- Cancel the pop animation for a key immediately.
function DoitePop.Stop(key)
  if not key then return end
  local st = DoitePop._active[key]
  if not st then return end
  DoitePop._active[key] = nil
  if st.ov then
    if st.ov.anim then st.ov.anim:Hide() end
    if st.ov.glow then st.ov.glow:Hide() end
  end
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
    if ov.glow then ov.glow:Hide() end
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
        ov.anim:SetScale(1 + (st.peakScale - 1) * t)
      end
      if ov and ov.glow then
        -- Glow alpha follows a half-sine: 0 at start, peak at
        -- mid-point, 0 at end. Peak alpha is st.glowAlpha.
        local gAlpha = math.sin(t * math.pi) * st.glowAlpha
        ov.glow.tex:SetVertexColor(
          st.glowR, st.glowG, st.glowB, gAlpha
        )
        ov.glow:SetScale(1 + st.glowScaleExtra * t)
      end
    end
  end

  local cnt = table.getn(done)
  local i = 1
  while i <= cnt do
    local key = done[i]
    local stt = DoitePop._active[key]
    if stt and stt.ov then
      if stt.ov.anim then stt.ov.anim:Hide() end
      if stt.ov.glow then stt.ov.glow:Hide() end
    end
    DoitePop._active[key] = nil
    done[i] = nil
    i = i + 1
  end

  if not anyAlive then
    tickFrame:Hide()
  end
end)