---------------------------------------------------------------
-- DoiteGlow.lua
-- Compatible glow effect, driven by DoiteAurasDB.glow settings.
-- Please respect license note: Ask permission
-- WoW 1.12 | Lua 5.0
---------------------------------------------------------------

local DG = {}
_G["DoiteGlow"] = DG

-- Frame-by-frame animation data for the ants texture (22 frames on a
-- 5x5 grid). Same coords as the original DoiteGlow.lua.
local texCoords = {
  { 0.0078, 0.1796, 0.0039, 0.1757 }, { 0.1953, 0.3671, 0.0039, 0.1757 }, { 0.3828, 0.5546, 0.0039, 0.1757 }, { 0.5703, 0.7421, 0.0039, 0.1757 }, { 0.7578, 0.9296, 0.0039, 0.1757 },
  { 0.0078, 0.1796, 0.1914, 0.3632 }, { 0.1953, 0.3671, 0.1914, 0.3632 }, { 0.3828, 0.5546, 0.1914, 0.3632 }, { 0.5703, 0.7421, 0.1914, 0.3632 }, { 0.7578, 0.9296, 0.1914, 0.3632 },
  { 0.0078, 0.1796, 0.3789, 0.5507 }, { 0.1953, 0.3671, 0.3789, 0.5507 }, { 0.3828, 0.5546, 0.3789, 0.5507 }, { 0.5703, 0.7421, 0.3789, 0.5507 }, { 0.7578, 0.9296, 0.3789, 0.5507 },
  { 0.0078, 0.1796, 0.5664, 0.7382 }, { 0.1953, 0.3671, 0.5664, 0.7382 }, { 0.3828, 0.5546, 0.5664, 0.7382 }, { 0.5703, 0.7421, 0.5664, 0.7382 }, { 0.7578, 0.9296, 0.5664, 0.7382 },
  { 0.0078, 0.1796, 0.7539, 0.9257 }, { 0.1953, 0.3671, 0.7539, 0.9257 }, { 0.3828, 0.5546, 0.7539, 0.9257 }, { 0.5703, 0.7421, 0.7539, 0.9257 }, { 0.7578, 0.9296, 0.7539, 0.9257 }
}

local ANTS_TEX  = "Interface\\AddOns\\DoiteAuras\\Textures\\IconAlertAnts"
local ALERT_TEX = "Interface\\AddOns\\DoiteAuras\\Textures\\IconAlert"

-- Doite Glow: compound preset drawn exactly like the original
-- DoiteGlow.lua -- static IconAlert background (BLEND) plus animated
-- 22-frame IconAlertAnts on top (ADD). Tinted white by default.
--
-- Action button border: single Blizzard border, tc-cropped to trim the
-- tga's transparent padding, drawn ADD (the tga carries a dark interior
-- that only reads correctly additively), with a soft alpha pulse.
-- Blend mode is fixed per texture -- no user setting.
local DOITE_GLOW_ID = "DOITE_GLOW"

-- Action button border: the tga carries ~35% transparent padding on
-- each side, so drawing the raw file made "scale 200%" look like the
-- old "scale 100%". tc = { 0.18, 0.82, 0.18, 0.82 } trims that
-- padding while leaving a little breathing room around the visible
-- edge; scale now maps roughly 1:1 to icon size.
--
-- star4 is a sprite sheet of 8 cooldown-flash frames laid out
-- horizontally in the top half of the tga. We draw only the first
-- frame (top-left 1/8 slice); if you want it animated, we would need
-- to add a frame array like the ants texture.
--
-- All other entries are drawn whole (0..1 texcoords) with ADD blend.
DG.Textures = {
  { text = "Doite Glow",           value = DOITE_GLOW_ID, isPreset = true },
  { text = "Action button border", value = "Interface\\Buttons\\UI-ActionButton-Border",
    tc = { 0.18, 0.82, 0.18, 0.82 } },

  { text = "Cooldown star",        value = "Interface\\Cooldown\\star4" },
  { text = "Cast bar spark",       value = "Interface\\CastingBar\\UI-CastingBar-Spark" },
  { text = "Minimize highlight",   value = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight" },
  { text = "Quickslot halo",       value = "Interface\\Buttons\\UI-Quickslot2",
    tc = { 0.2, 0.8, 0.2, 0.8 } },
}

-- MPOWA texture family (Textures\MPOWA\AuraN, N = 1..246). No
-- directory-enumeration API in 1.12, so the count is hardcoded. A
-- value with this prefix and a numeric suffix within range is a
-- valid glow texture, exactly like the entries in DG.Textures.
DG.MPOWA_PREFIX = "Interface\\AddOns\\DoiteAuras\\Textures\\MPOWA\\Aura"
DG.MPOWA_COUNT  = 246

function DG.IsMPOWATexture(v)
  if type(v) ~= "string" or v == "" then return false end
  local prefix = DG.MPOWA_PREFIX
  if string.sub(v, 1, string.len(prefix)) ~= prefix then return false end
  local rest = string.sub(v, string.len(prefix) + 1)
  if string.find(rest, "^%d+$") == nil then return false end
  local n = tonumber(rest)
  if not n or n < 1 or n > DG.MPOWA_COUNT then return false end
  return true
end

-- Human-readable label for a texture value. Handles both the static
-- DG.Textures list and the MPOWA family. Falls back to "?" for
-- unknown values.
function DG.GetTextureLabelForValue(v)
  if DG.IsMPOWATexture(v) then
    local n = tonumber(string.sub(v, string.len(DG.MPOWA_PREFIX) + 1))
    return "MPOWA - Aura" .. tostring(n)
  end
  local list = DG.Textures
  if type(list) == "table" then
    local i
    for i = 1, table.getn(list) do
      if list[i].value == v then return list[i].text end
    end
  end
  return "?"
end

-- Build the entry list the generic picker consumes: every static
-- DG.Textures entry (client textures + compound Doite Glow), then the
-- MPOWA family Aura1..AuraN.
--
-- The compound Doite Glow entry has no file path of its own, so its
-- thumbnail shows frame 1 of the Ants sprite (same texcoord the
-- runtime uses).
function DG.GetPickerEntries()
  local entries = {}

  local list = DG.Textures
  if type(list) == "table" then
    local i
    for i = 1, table.getn(list) do
      local e = list[i]
      if e.value == DOITE_GLOW_ID then
        entries[table.getn(entries) + 1] = {
          value      = e.value,
          label      = e.text,
          previewTex = ANTS_TEX,
          tc         = { 0.0078, 0.1796, 0.0039, 0.1757 },
        }
      else
        entries[table.getn(entries) + 1] = {
          value = e.value,
          label = e.text,
          tc    = e.tc,
        }
      end
    end
  end

  local prefix = DG.MPOWA_PREFIX
  local n      = DG.MPOWA_COUNT or 0
  local i
  for i = 1, n do
    entries[table.getn(entries) + 1] = {
      value = prefix .. tostring(i),
      label = "MPOWA - Aura" .. tostring(i),
    }
  end

  return entries
end

local DEFAULTS = {
  behind   = false,
  scale    = 1.0,
  alpha    = 1.0,
  r = 1, g = 1, b = 1,
  speed    = 0.04,
  texture  = DOITE_GLOW_ID,
  rotation = 0,           -- degrees, 0..360; converted to radians on apply
}

function DG.GetSettings()
  DoiteAurasDB = DoiteAurasDB or {}
  DoiteAurasDB.glow = DoiteAurasDB.glow or {}
  local s = DoiteAurasDB.glow
  if s.behind  == nil then s.behind  = DEFAULTS.behind  end
  if s.scale   == nil then s.scale   = DEFAULTS.scale   end
  if s.alpha   == nil then s.alpha   = DEFAULTS.alpha   end
  if s.r       == nil then s.r       = DEFAULTS.r       end
  if s.g       == nil then s.g       = DEFAULTS.g       end
  if s.b       == nil then s.b       = DEFAULTS.b       end
  if s.speed    == nil then s.speed    = DEFAULTS.speed    end
  if s.texture  == nil then s.texture  = DEFAULTS.texture  end
  if s.rotation == nil then s.rotation = DEFAULTS.rotation end

  -- Migrate legacy saved values (older builds stored raw texture paths).
  if s.texture == ANTS_TEX or s.texture == ALERT_TEX then
    s.texture = DOITE_GLOW_ID
  end

  -- Reject anything not currently offered. MPOWA textures are also
  -- valid even though they are not listed in DG.Textures (246 entries;
  -- not worth materializing just to validate one string).
  local valid = false
  local i
  for i = 1, table.getn(DG.Textures) do
    if DG.Textures[i].value == s.texture then valid = true; break end
  end
  if (not valid) and DG.IsMPOWATexture(s.texture) then
    valid = true
  end
  if not valid then s.texture = DEFAULTS.texture end

  -- Obsolete field from earlier experiments.
  s.blend = nil

  return s
end

local function GetTextureEntry(tex)
  if type(DG.Textures) ~= "table" then return nil end
  local i
  for i = 1, table.getn(DG.Textures) do
    local e = DG.Textures[i]
    if e.value == tex then return e end
  end
  return nil
end

local function NextIndex(i)
  if i >= 22 then return 1 else return i + 1 end
end

local pool = {}
local numOverlays = 0

local function GetOverlay()
  local overlay = tremove(pool)
  if not overlay then
    numOverlays = numOverlays + 1
    overlay = CreateFrame("Frame", "DoiteGlowOverlay" .. numOverlays)
    overlay:SetFrameStrata("TOOLTIP")

    overlay.bg = overlay:CreateTexture(nil, "ARTWORK")
    overlay.glow = overlay:CreateTexture(nil, "OVERLAY")
    overlay.glow:SetBlendMode("ADD")
  end
  return overlay
end

local function ApplyShape(overlay, frame, s)
  local size  = (frame and frame.GetWidth and frame:GetWidth()) or 36
  local scale = tonumber(s.scale) or 1.0
  if scale < 0.1 then scale = 0.1 end
  if scale > 4.0 then scale = 4.0 end

  local frameLevel = (frame.GetFrameLevel and frame:GetFrameLevel()) or 1
  if s.behind then
    overlay:SetParent(UIParent)
    local ps = (frame.GetFrameStrata and frame:GetFrameStrata()) or "MEDIUM"
    overlay:SetFrameStrata(ps)
    local lvl = frameLevel - 1
    if lvl < 0 then lvl = 0 end
    overlay:SetFrameLevel(lvl)
  else
    overlay:SetParent(frame)
    overlay:SetFrameStrata("TOOLTIP")
    overlay:SetFrameLevel(frameLevel + 50)
  end

  overlay:ClearAllPoints()
  overlay:SetPoint("CENTER", frame, "CENTER", 0, 0)
  overlay:SetWidth(size * scale)
  overlay:SetHeight(size * scale)

  local tex = s.texture or DOITE_GLOW_ID

  if tex == DOITE_GLOW_ID then
    -- Compound Doite Glow (original two-layer look).
    overlay.bg:SetTexture(ALERT_TEX)
    overlay.bg:SetTexCoord(0.0546, 0.4609, 0.3007, 0.5039)
    overlay.bg:SetAllPoints(overlay)
    overlay.bg:SetVertexColor(s.r or 1, s.g or 1, s.b or 1, s.alpha or 1)
    overlay.bg:SetBlendMode("BLEND")
    overlay.bg:Show()

    overlay.glow:SetTexture(ANTS_TEX)
    overlay.glow:SetTexCoord(texCoords[1][1], texCoords[1][2], texCoords[1][3], texCoords[1][4])
    overlay.glow:SetAllPoints(overlay)
    overlay.glow:SetVertexColor(s.r or 1, s.g or 1, s.b or 1, s.alpha or 1)
    overlay.glow:SetBlendMode("ADD")
    overlay._mode = "ants"
  else
    -- Blizzard border (or any other registered texture).
    overlay.bg:Hide()

    local entry = GetTextureEntry(tex)

    overlay.glow:SetTexture(tex)
    if entry and entry.tc then
      overlay.glow:SetTexCoord(entry.tc[1], entry.tc[2], entry.tc[3], entry.tc[4])
    else
      overlay.glow:SetTexCoord(0, 1, 0, 1)
    end
    overlay.glow:SetAllPoints(overlay)
    overlay.glow:SetVertexColor(s.r or 1, s.g or 1, s.b or 1, s.alpha or 1)
    overlay.glow:SetBlendMode("ADD")
    overlay._mode = "border"
  end

  -- Texture rotation. Stored in degrees; SetRotation wants radians.
  -- Applied to both layers of the compound Doite Glow so the static
  -- background and the animated ants stay aligned.
  do
    local rotDeg = tonumber(s.rotation) or 0
    local rotRad = math.rad(rotDeg)
    if overlay.glow.SetRotation then overlay.glow:SetRotation(rotRad) end
    if overlay.bg and overlay.bg.SetRotation then
      overlay.bg:SetRotation(rotRad)
    end
  end

  overlay.index        = 1
  overlay.lastUpdated  = 0
  overlay._pulsePhase  = 0
  overlay._settingsRef = s
end

function DG.Start(frame)
  if not frame then return end

  local version = _G["DoiteGlow_Version"] or 0
  if frame.glow and frame._daGlowVersion == version then
    return
  end

  if frame.glow then
    local old = frame.glow
    old:SetScript("OnUpdate", nil)
    old:Hide()
    old:SetParent(UIParent)
    frame.glow = nil
    tinsert(pool, old)
  end

  local s = DG.GetSettings()
  local overlay = GetOverlay()
  ApplyShape(overlay, frame, s)

  frame.glow = overlay
  frame._daGlowVersion = version
  overlay:Show()

  overlay:SetScript("OnUpdate", function()
    -- Live-apply r/g/b/alpha every frame for both modes. This is what
    -- makes the ColorPicker's sliders update the glow while the user
    -- drags them: the picker only mutates DoiteAurasDB.glow (== s), and
    -- we pick the new values up here. Cheap (a handful of floats).
    local r = s.r or 1
    local g = s.g or 1
    local b = s.b or 1
    local a = s.alpha or 1

    local speedMs = math.floor((tonumber(s.speed) or 0.04) * 1000 + 0.5)
    if speedMs < 10  then speedMs = 10  end
    if speedMs > 500 then speedMs = 500 end

    if overlay._mode == "ants" then
      -- Doite Glow sprite animation.
      --
      -- Endpoints:
      --   slider 10 ms (left)   -> 0.50 s / frame (slow)
      --   slider 500 ms (right) -> 0.0025 s / frame (fast)
      --
      -- Exponential map, remapped so slider 1.0 corresponds to what
      -- slider 5.0 used to produce. Slider pos (1.0..10.0) maps
      -- linearly to t in (0.5..1.0):
      --   pos 1.0 -> interval ~= 0.055 s/frame (slowest)
      --   pos 10.0-> interval ~= 0.006 s/frame (fastest)
      -- (ms runs 10..500 in DB; t = (ms-10)/490 goes 0..1 in raw
      -- slider terms, then we compress to 0.5..1.0.)
      local raw = (speedMs - 10) / 490
      if raw < 0 then raw = 0 end
      if raw > 1 then raw = 1 end
      local t = 0.5 + 0.5 * raw
      local intervalSec = 0.5 * math.pow(0.012, t)

      -- Advance the frame index by however many whole intervals have
      -- elapsed since the last tick. This is what actually makes high
      -- slider values visibly faster: OnUpdate still fires at the
      -- client's frame rate, but each call can advance the sprite by
      -- multiple frames, so the animation is not capped at 30-60 fps.
      local elapsed = (overlay.lastUpdated or 0) + arg1
      local advanced = false
      if elapsed >= intervalSec then
        local steps = math.floor(elapsed / intervalSec)
        if steps > 100 then steps = 100 end
        local i
        for i = 1, steps do
          overlay.index = NextIndex(overlay.index)
        end
        overlay.lastUpdated = elapsed - steps * intervalSec
        advanced = true
      else
        overlay.lastUpdated = elapsed
      end

      if advanced then
        local tc = texCoords[overlay.index]
        overlay.glow:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
      end

      -- Ants layer keeps ADD; tint every frame so picker drags show up
      -- immediately.
      overlay.glow:SetVertexColor(r, g, b, a)
      if overlay.bg and overlay.bg.SetVertexColor then
        overlay.bg:SetVertexColor(r, g, b, a)
      end

    elseif overlay._mode == "border" then
      -- Blizzard border alpha pulse. Slider semantics:
      --   leftmost (10 ms)  -> pulse disabled (static tint)
      --   right    (500 ms) -> fast pulse (~1.5 cycles/s)
      if speedMs <= 10 then
        overlay.glow:SetVertexColor(r, g, b, a)
        return
      end

      overlay.lastUpdated = overlay.lastUpdated + arg1
      local tick = 0.03
      if overlay.lastUpdated < tick then
        -- Still enforce live tint during the wait between ticks, so
        -- slider drags in the color picker are instantly reflected.
        overlay.glow:SetVertexColor(r, g, b, a * (overlay._lastPulse or 1))
        return
      end
      local elapsed = overlay.lastUpdated
      overlay.lastUpdated = 0

      local rate = ((speedMs - 10) / 490) * 2 * math.pi * 1.5
      overlay._pulsePhase = (overlay._pulsePhase or 0) + rate * elapsed

      local pulse = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(overlay._pulsePhase))
      overlay._lastPulse = pulse
      overlay.glow:SetVertexColor(r, g, b, a * pulse)
    end
  end)
end

function DG.Stop(frame)
  if not frame or not frame.glow then return end
  local overlay = frame.glow
  overlay:SetScript("OnUpdate", nil)
  overlay:Hide()
  overlay:SetParent(UIParent)
  frame.glow = nil
  frame._daGlowVersion = nil
  tinsert(pool, overlay)
end

function DG.BumpVersion()
  _G["DoiteGlow_Version"] = (_G["DoiteGlow_Version"] or 0) + 1
  if DoiteConditions_RequestEvaluate then
    DoiteConditions_RequestEvaluate()
  end
end

-- =================================================================
-- Presets.
--
-- DoiteAurasDB.glowPresets[name] = { <snapshot of editable fields> }
-- DoiteAurasDB.glowActivePreset = name | nil
--
-- A preset is a snapshot of every user-editable glow field, including
-- `texture` (which can be a static DG.Textures value, the compound
-- DOITE_GLOW_ID, or an MPOWA path). Runtime / migration fields
-- (`blend`, `_version`-style markers, DoiteGlow_Version) are NOT
-- part of a preset.
--
-- Manual edits to the Glow controls keep writing straight into
-- DoiteAurasDB.glow (as they always did) and do NOT retarget the
-- active preset. On the next /reload the active preset is re-applied,
-- discarding any unsaved tweaks -- that is the contract the UI hint
-- spells out.
-- =================================================================
local PRESET_FIELDS = {
  "behind", "scale", "alpha",
  "r", "g", "b",
  "speed", "texture",
  "rotation",
}

function DG.GetPresetSnapshot()
  local s = DG.GetSettings()
  local snap = {}
  local i
  for i = 1, table.getn(PRESET_FIELDS) do
    local k = PRESET_FIELDS[i]
    snap[k] = s[k]
  end
  return snap
end

-- Copy a snapshot into the live glow settings. by default this bumps
-- the version so every active overlay rebuilds; pass a truthy `noBump`
-- to skip (used on load, where there is nothing cached to invalidate).
function DG.ApplyPresetSnapshot(t, noBump)
  if type(t) ~= "table" then return end
  local s = DG.GetSettings()
  local i
  for i = 1, table.getn(PRESET_FIELDS) do
    local k = PRESET_FIELDS[i]
    if t[k] ~= nil then
      s[k] = t[k]
    end
  end
  if not noBump then
    DG.BumpVersion()
  end
end

-- glow01, glow02, ... first free slot. Falls back to a random suffix
-- if the sequence is somehow exhausted (paranoia).
function DG.GenerateNewPresetName()
  DoiteAurasDB = DoiteAurasDB or {}
  local presets = DoiteAurasDB.glowPresets or {}
  local n = 1
  while n < 1000 do
    local name = string.format("glow%02d", n)
    if presets[name] == nil then
      return name
    end
    n = n + 1
  end
  return "glow" .. tostring(math.random(1000, 9999))
end

-- Snapshot current glow into a freshly-named preset, mark it active,
-- return the chosen name.
function DG.SaveCurrentAsPreset()
  DoiteAurasDB = DoiteAurasDB or {}
  DoiteAurasDB.glowPresets = DoiteAurasDB.glowPresets or {}
  local name = DG.GenerateNewPresetName()
  DoiteAurasDB.glowPresets[name] = DG.GetPresetSnapshot()
  DoiteAurasDB.glowActivePreset = name
  return name
end

-- Delete a preset by name. If it was the active one, clear the
-- active ref so the next load does not re-apply a vanished snapshot.
function DG.DeletePreset(name)
  local db = _G["DoiteAurasDB"]
  if not db or not db.glowPresets or not name then return false end
  if not db.glowPresets[name] then return false end
  db.glowPresets[name] = nil
  if db.glowActivePreset == name then
    db.glowActivePreset = nil
  end
  return true
end

-- Rename a preset, preserving its snapshot. No-op if `from` is
-- missing or `to` is empty / already taken. If the renamed preset was
-- active, the active ref follows the new name.
function DG.RenamePreset(from, to)
  local db = _G["DoiteAurasDB"]
  if not db or not db.glowPresets then return false end
  if not from or not to or to == "" then return false end
  local p = db.glowPresets[from]
  if not p then return false end
  if from == to then return true end
  if db.glowPresets[to] then return false end
  db.glowPresets[to] = p
  db.glowPresets[from] = nil
  if db.glowActivePreset == from then
    db.glowActivePreset = to
  end
  return true
end

-- Sorted list of preset names (ascending). Empty table when none.
function DG.ListPresets()
  local db = _G["DoiteAurasDB"]
  if not db or not db.glowPresets then return {} end
  local out = {}
  local k
  for k in pairs(db.glowPresets) do
    table.insert(out, k)
  end
  table.sort(out)
  return out
end

-- One-shot on addon load: if a preset was selected before the last
-- reload, re-apply it over the raw SavedVariables glow. Runs at the
-- bottom of this file, AFTER all functions above are defined and
-- AFTER WoW has already populated DoiteAurasDB.
--
-- noBump = true: there are no active overlays yet, no point in
-- invalidating a version counter that nobody is caching against.
function DG.ApplyActivePresetOnLoad()
  if DG._activePresetApplied == true then return end
  DG._activePresetApplied = true

  local db = _G["DoiteAurasDB"]
  if not db then return end
  local name = db.glowActivePreset
  if not name or name == "" then return end
  local presets = db.glowPresets
  if not presets then return end
  local p = presets[name]
  if not p then
    -- Active name points at a preset that no longer exists (manual
    -- SavedVariables surgery, older version). Drop the dangling ref.
    db.glowActivePreset = nil
    return
  end
  DG.ApplyPresetSnapshot(p, true)
end

-- Defer to ADDON_LOADED: on this client the per-character
-- SavedVariables are NOT populated when the .lua chunk runs, so a
-- file-scope call would see an empty DoiteAurasDB and skip. The
-- event fires after SV load, so the preset seeding lands in the
-- right place. Same pattern as DoitePop.lua.
do
  local f = CreateFrame("Frame")
  f:RegisterEvent("ADDON_LOADED")
  f:SetScript("OnEvent", function()
    if arg1 == "DoiteAuras" then
      DG.ApplyActivePresetOnLoad()
      f:UnregisterEvent("ADDON_LOADED")
    end
  end)
end