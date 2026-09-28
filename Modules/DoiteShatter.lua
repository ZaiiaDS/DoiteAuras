---------------------------------------------------------------
-- Modules/DoiteShatter.lua
-- "Shatter assemble" effect: instead of sliding in from the side,
-- the icon reassembles from scattered pieces with a small cloud
-- of sparks flying in alongside them.
--
-- Per-icon toggle: ca.sliderEffect = "shatter" (vs default "slide").
--
-- Loaded BEFORE DoiteConditions.lua (see DoiteAuras.toc).
-- Requires PizzaSauce (loaded before this file).
--
-- Tunables are edited via /dshatter (see help in chat).
--
-- Please respect license note: Ask permission
-- WoW 1.12 | Lua 5.0
---------------------------------------------------------------

local DoiteShatter = {}
_G["DoiteShatter"] = DoiteShatter

local function _Sauce()
  return _G["PizzaSauce"]
end

-- ---------------------------------------------------------------
-- Tunables: stored in DoiteAurasDB.shatter, edited via /dshatter or
-- DoiteShatter.SetParam/GetParam. Fall back to DEFAULTS when a field
-- is nil so old SavedVariables load cleanly.
-- ---------------------------------------------------------------
local PARTICLE_TEX_CHOICES = {
  -- Short keys are what /dshatter expects as argument.
  --   spark -- soft cast-bar spark (default)
  --   gold  -- Blizzard minimize-button sparkle, gold-tinted
  --   white -- pure white pixel; renders as square of any vertex tint
  spark     = "Interface\\CastingBar\\UI-CastingBar-Spark",
  gold      = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight",
  white     = "Interface\\Buttons\\WHITE8X8",
}

local DEFAULTS = {
  grid          = 5,
  scatterMin    = 400,
  scatterMax    = 400,
  stagger       = 0.25,
  waveAmp       = 20,
  waveFreqMin   = 1.5,
  waveFreqMax   = 3.0,
  pieceStart    = 1 / 3,
  dirCone       = 60,             -- degrees; half-angle of scatter cone

  pTex          = "spark",        -- key into PARTICLE_TEX_CHOICES
  pCount        = 50,
  pSizeMin      = 4,
  pSizeMax      = 14,
  pDistMin      = 300,
  pDistMax      = 400,
  pDelay        = 0.30,
  pFlight       = 0.70,
  pAlphaMin     = 0.30,
  pAlphaMax     = 0.80,
}

-- Bounds used by SetParam for validation. Ranges are generous; they
-- exist to stop typos, not to enforce taste.
local PARAM_BOUNDS = {
  grid        = { 3,  8,  "int" },
  scatterMin  = { 0,  3000, "num" },
  scatterMax  = { 0,  3000, "num" },
  stagger     = { 0,  1,    "num" },
  waveAmp     = { 0,  200,  "num" },
  waveFreqMin = { 0,  20,   "num" },
  waveFreqMax = { 0,  20,   "num" },
  pieceStart  = { 0.05, 1,  "num" },
  dirCone     = { 5,  180,  "num" },

  pTex        = { 0,  0,    "enum" },  -- validated against the choices table
  pCount      = { 0,  200,  "int" },
  pSizeMin    = { 1,  64,   "num" },
  pSizeMax    = { 1,  64,   "num" },
  pDistMin    = { 0,  3000, "num" },
  pDistMax    = { 0,  3000, "num" },
  pDelay      = { 0,  1,    "num" },
  pFlight     = { 0.05, 1,  "num" },
  pAlphaMin   = { 0,  1,    "num" },
  pAlphaMax   = { 0,  1,    "num" },
}

-- Human-readable order for /dshatter list. Also the positional order
-- used by export/import strings (see DoiteShatter.ExportPreset).
local PARAM_ORDER = {
  "grid", "scatterMin", "scatterMax", "stagger", "waveAmp",
  "waveFreqMin", "waveFreqMax", "pieceStart", "dirCone",
  "pTex", "pCount", "pSizeMin", "pSizeMax", "pDistMin", "pDistMax",
  "pDelay", "pFlight", "pAlphaMin", "pAlphaMax",
}

-- Single source of truth for the shatter config. Reads from
-- DoiteAurasDB.shatter, fills any missing key from DEFAULTS on the fly
-- (so old saves are safe).
function DoiteShatter.GetCfg()
  local db = _G["DoiteAurasDB"]
  if not db then return DEFAULTS end
  db.shatter = db.shatter or {}
  local s = db.shatter

  -- Migration v1 -> v2: pTex keys were renamed.
  --   old "default" (CastingBar-Spark)         -> new "spark"
  --   old "spark"   (MinimizeButton-Highlight) -> new "gold"
  --   old "white"                               -> unchanged
  -- Version marker stored on the shatter table so the pass runs once
  -- per save, not on every access.
  if (s._version or 1) < 2 then
    if s.pTex == "default" then
      s.pTex = "spark"
    elseif s.pTex == "spark" then
      s.pTex = "gold"
    end
    s._version = 2
  end

  local k, v
  for k, v in pairs(DEFAULTS) do
    if s[k] == nil then s[k] = v end
  end
  return s
end

-- Set a single parameter, validating against PARAM_BOUNDS.
-- Returns true on success, or (false, errMessage) on failure.
function DoiteShatter.SetParam(key, rawValue)
  local bounds = PARAM_BOUNDS[key]
  if not bounds then
    return false, "unknown key '" .. tostring(key) .. "'"
  end

  local db = _G["DoiteAurasDB"]
  if not db then return false, "DB not ready" end
  db.shatter = db.shatter or {}
  local s = db.shatter

  if bounds[3] == "enum" then
    if not PARTICLE_TEX_CHOICES[rawValue] then
      local keys = {}
      local k
      for k in pairs(PARTICLE_TEX_CHOICES) do
        table.insert(keys, k)
      end
      return false, "expected one of: " .. table.concat(keys, ", ")
    end
    s[key] = rawValue
    return true
  end

  local n = tonumber(rawValue)
  if not n then return false, "expected a number" end
  local lo, hi, kind = bounds[1], bounds[2], bounds[3]
  if n < lo or n > hi then
    return false, "out of range [" .. lo .. ".." .. hi .. "]"
  end
  if kind == "int" then n = math.floor(n + 0.5) end
  s[key] = n
  return true
end

function DoiteShatter.GetParam(key)
  local cfg = DoiteShatter.GetCfg()
  return cfg[key]
end

function DoiteShatter.ResetParam(key)
  local db = _G["DoiteAurasDB"]
  if not db or not db.shatter then return end
  if key == nil then
    db.shatter = { _version = 2 }
    return
  end
  if DEFAULTS[key] ~= nil then
    db.shatter[key] = nil
  end
end

-- ---------------------------------------------------------------
-- Presets. Stored in DoiteAurasDB.shatterPresets[name] as a plain
-- snapshot of every tunable key (see DEFAULTS). _version and any
-- other metadata are NOT part of a preset.
-- ---------------------------------------------------------------

function DoiteShatter.SavePreset(name)
  if not name or name == "" then return false, "name required" end
  local db = _G["DoiteAurasDB"]
  if not db then return false, "DB not ready" end
  db.shatterPresets = db.shatterPresets or {}
  local cfg = DoiteShatter.GetCfg()
  local snap = {}
  local k
  for k in pairs(DEFAULTS) do
    snap[k] = cfg[k]
  end
  db.shatterPresets[name] = snap
  return true
end

function DoiteShatter.LoadPreset(name)
  local db = _G["DoiteAurasDB"]
  if not db or not db.shatterPresets then return false, "no presets saved" end
  local p = db.shatterPresets[name]
  if not p then return false, "no preset named '" .. tostring(name) .. "'" end
  db.shatter = db.shatter or {}
  local v = db.shatter._version or 2
  local k
  for k in pairs(DEFAULTS) do
    if p[k] ~= nil then
      db.shatter[k] = p[k]
    end
  end
  db.shatter._version = v
  return true
end

function DoiteShatter.DeletePreset(name)
  local db = _G["DoiteAurasDB"]
  if not db or not db.shatterPresets then return false end
  if not db.shatterPresets[name] then return false end
  db.shatterPresets[name] = nil
  return true
end

function DoiteShatter.ListPresets()
  local db = _G["DoiteAurasDB"]
  if not db or not db.shatterPresets then return {} end
  local out = {}
  local k
  for k in pairs(db.shatterPresets) do
    table.insert(out, k)
  end
  table.sort(out)
  return out
end

-- ---------------------------------------------------------------
-- Import / export as a compact string.
--
-- Format:
--     DSH1;<v1>,<v2>,...,<vN>
-- where v1..vN are the values of PARAM_ORDER keys, in that exact
-- order. Version marker at the front lets future additions to
-- PARAM_ORDER be detected and handled.
--
-- Compact CSV is used instead of key=value because the whole
-- command has to fit in WoW's chat input box; the k=v form does
-- not, once all 19 parameters are serialized.
--
-- New parameters must be APPENDED to PARAM_ORDER and trigger a
-- version bump (DSH2 etc.), because positional order is what makes
-- the format work.
-- ---------------------------------------------------------------

local EXPORT_VERSION = "DSH1"

-- Format a single value for export. Numbers are trimmed to 4
-- significant digits so 1/3 does not become "0.33333333333333".
local function _DS_Fmt(v)
  if type(v) == "number" then
    return string.format("%.4g", v)
  end
  return tostring(v)
end

-- Public: current settings as an export string.
function DoiteShatter.ExportPreset()
  local cfg = DoiteShatter.GetCfg()
  local vals = {}
  local i
  for i = 1, table.getn(PARAM_ORDER) do
    local v = cfg[PARAM_ORDER[i]]
    if v == nil then v = DEFAULTS[PARAM_ORDER[i]] end
    table.insert(vals, _DS_Fmt(v))
  end
  return EXPORT_VERSION .. ";" .. table.concat(vals, ",")
end

-- Public: a named preset as an export string, or nil if not found.
function DoiteShatter.ExportNamedPreset(name)
  local db = _G["DoiteAurasDB"]
  if not db or not db.shatterPresets then return nil end
  local p = db.shatterPresets[name]
  if not p then return nil end
  local vals = {}
  local i
  for i = 1, table.getn(PARAM_ORDER) do
    local k = PARAM_ORDER[i]
    local v = p[k]
    if v == nil then v = DEFAULTS[k] end
    table.insert(vals, _DS_Fmt(v))
  end
  return EXPORT_VERSION .. ";" .. table.concat(vals, ",")
end

-- Public: apply an export string to the current settings.
-- Values in the string overwrite matching keys; keys not present in
-- the string keep their current values. That makes partial strings
-- (with some values blank) safe to import.
--
-- Returns true, appliedCount, skippedCount on success, or
-- false, errorString on a hard parse failure.
function DoiteShatter.ImportPreset(str)
  if type(str) ~= "string" or str == "" then
    return false, "empty string"
  end

  local sep = string.find(str, ";", 1, true)
  if not sep then
    return false, "missing ';' separator after version marker"
  end
  local ver = string.sub(str, 1, sep - 1)
  if ver ~= EXPORT_VERSION then
    return false, "unsupported version '" .. ver .. "' (expected " .. EXPORT_VERSION .. ")"
  end

  local body = string.sub(str, sep + 1)

  -- Split by comma (including an empty trailing token, so we can
  -- detect an incorrectly truncated string).
  local parts = {}
  local tok = ""
  local i = 1
  local n = string.len(body)
  while i <= n + 1 do
    local c = string.sub(body, i, i)
    if c == "," or c == "" then
      table.insert(parts, tok)
      tok = ""
    else
      tok = tok .. c
    end
    i = i + 1
  end

  local expected = table.getn(PARAM_ORDER)
  local got = table.getn(parts)
  if got ~= expected then
    return false, "expected " .. expected .. " values, got " .. got
  end

  local applied, skipped = 0, 0
  for i = 1, expected do
    local k = PARAM_ORDER[i]
    local v = parts[i]
    if v ~= nil and v ~= "" then
      local ok = DoiteShatter.SetParam(k, v)
      if ok then
        applied = applied + 1
      else
        skipped = skipped + 1
      end
    else
      skipped = skipped + 1
    end
  end

  return true, applied, skipped
end

-- ---------------------------------------------------------------
-- Hard limits that are not tunable.
-- ---------------------------------------------------------------
local MAX_DURATION   = 20.0
local DEFAULT_DUR    = 0.7

local TWO_PI = math.pi * 2

-- ---------------------------------------------------------------
-- Manager
-- ---------------------------------------------------------------
local ShatterMgr = {
  active = {},
  _fired = {},
}
_G["DoiteShatter_Mgr"] = ShatterMgr
DoiteShatter.ShatterMgr = ShatterMgr

local _MarkDirtyAbility = nil
function DoiteShatter.SetMarkDirtyHandler(fn)
  _MarkDirtyAbility = fn
end

-- ---------------------------------------------------------------
-- Shared setters (one function for all pieces / particles).
-- State lives on the target texture (tgt._shatterPiece / _shatterParticle)
-- to avoid per-piece closures.
--
-- ClearAllPoints is REQUIRED on this client: SetPoint appends anchors in
-- 1.12 (unlike later clients), so calling SetPoint without clearing
-- accumulates dozens of anchors per animation and drifts / stutters.
-- ---------------------------------------------------------------

local function _PieceSetter(tgt, t)
  local ps = tgt._shatterPiece
  if not ps or not ps.shatter then return end
  if ShatterMgr.active[ps.key] ~= ps.shatter then return end

  local x = ps.sx + (ps.ex - ps.sx) * t
  local y = ps.sy + (ps.ey - ps.sy) * t

  local wave = math.sin(t * ps.freq * TWO_PI + ps.phase) * ps.waveAmp * (1 - t)
  x = x + ps.perpX * wave
  y = y + ps.perpY * wave

  tgt:ClearAllPoints()
  tgt:SetPoint("CENTER", ps.frame, "CENTER", x, y)

  local pStart = ps.pieceStart
  local s = pStart + (1 - pStart) * t
  tgt:SetWidth(ps.pieceW * s)
  tgt:SetHeight(ps.pieceH * s)

  if ps.fade then
    tgt:SetVertexColor(1, 1, 1, t)
  end
end

local function _ParticleSetter(tgt, t)
  local ps = tgt._shatterParticle
  if not ps or not ps.shatter then return end
  if ShatterMgr.active[ps.key] ~= ps.shatter then return end

  local x = ps.sx + (ps.ex - ps.sx) * t
  local y = ps.sy + (ps.ey - ps.sy) * t
  tgt:ClearAllPoints()
  tgt:SetPoint("CENTER", ps.frame, "CENTER", x, y)

  -- Constant size; no SetWidth/Height here. Only alpha animates, and
  -- only when fade is on. In non-fade mode the per-particle base alpha
  -- is set once in StartOrUpdate and stays put.
  if ps.fade then
    tgt:SetVertexColor(1, 1, 1, t * ps.aBase)
  end
end

-- ---------------------------------------------------------------
-- Pools
-- ---------------------------------------------------------------
local _piecePool = {}
local function _AcquirePiece(Sauce)
  local p = table.remove(_piecePool)
  if p then return p end
  p = UIParent:CreateTexture(nil, "OVERLAY")
  p:SetBlendMode("BLEND")
  p._shatterPiece = {}
  p._shatterTween = Sauce:Tween(p, {
    type     = "custom",
    from     = 0, to = 1,
    duration = 1,
    easing   = "linear",
    setter   = _PieceSetter,
    defer    = true,
  })
  return p
end
local function _ReleasePiece(p)
  p:Hide()
  p:ClearAllPoints()
  p:SetParent(UIParent)
  local ps = p._shatterPiece
  if ps then
    ps.key     = nil
    ps.shatter = nil
  end
  table.insert(_piecePool, p)
end

local _particlePool = {}
local function _AcquireParticle(Sauce)
  local q = table.remove(_particlePool)
  if q then
    -- Texture may have been changed via /dshatter since this particle
    -- was pooled. Re-apply the current one so the change takes effect
    -- on the next shatter without rebuilding the pool.
    local texKey = DoiteShatter.GetCfg().pTex
    local tex    = PARTICLE_TEX_CHOICES[texKey] or PARTICLE_TEX_CHOICES["spark"]
    if q:GetTexture() ~= tex then q:SetTexture(tex) end
    return q
  end
  q = UIParent:CreateTexture(nil, "OVERLAY")
  q:SetBlendMode("ADD")
  q:SetTexture(PARTICLE_TEX_CHOICES[DoiteShatter.GetCfg().pTex]
               or PARTICLE_TEX_CHOICES["spark"])
  q._shatterParticle = {}
  q._shatterTween = Sauce:Tween(q, {
    type     = "custom",
    from     = 0, to = 1,
    duration = 1,
    easing   = "linear",
    setter   = _ParticleSetter,
    defer    = true,
  })
  return q
end
local function _ReleaseParticle(q)
  q:Hide()
  q:ClearAllPoints()
  q:SetParent(UIParent)
  local ps = q._shatterParticle
  if ps then
    ps.key     = nil
    ps.shatter = nil
  end
  table.insert(_particlePool, q)
end

-- ---------------------------------------------------------------
-- Backstop tick
-- ---------------------------------------------------------------
local _tick = CreateFrame("Frame", "DoiteShatterTick")
_tick:Hide()
_tick:SetScript("OnUpdate", function()
  local now = GetTime()
  local anyActive = false
  for key, st in pairs(ShatterMgr.active) do
    if now >= st.endTime then
      ShatterMgr:_Finish(key)
    else
      anyActive = true
    end
  end
  if anyActive then
    if _MarkDirtyAbility then _MarkDirtyAbility() end
  else
    this:Hide()
  end
end)

function ShatterMgr:IsActive(key)
  return self.active[key] ~= nil
end

-- ---------------------------------------------------------------
-- Start / Finish / Stop
-- ---------------------------------------------------------------
--   dir         : optional "left" / "right" / "up" / "down"; when set,
--                 pieces/particles enter from that side of their slot
--                 inside a narrow cone. nil = full 360 scatter.
--   grey        : when true, pieces are rendered desaturated (SetDesaturated).
--                 Applied once at start; pooled pieces are reset to normal
--                 on the next shatter that does not use grey.
function ShatterMgr:StartOrUpdate(key, frame, iconTexture, duration, fade, dir, grey)
  if not key or not frame then return end
  local Sauce = _Sauce()
  if not Sauce then return end
  if self.active[key] then return end

  local cfg = DoiteShatter.GetCfg()
  local GRID      = cfg.grid
  local SCATTER_MIN = cfg.scatterMin
  local SCATTER_MAX = cfg.scatterMax
  local MAX_STAGGER_K = cfg.stagger
  local WAVE_AMP      = cfg.waveAmp
  local WAVE_FREQ_MIN = cfg.waveFreqMin
  local WAVE_FREQ_MAX = cfg.waveFreqMax
  local PIECE_START_SCALE = cfg.pieceStart
  local DIR_CONE_HALF = math.rad(cfg.dirCone)

  local PARTICLE_COUNT      = cfg.pCount
  local PARTICLE_SIZE_MIN   = cfg.pSizeMin
  local PARTICLE_SIZE_MAX   = cfg.pSizeMax
  local PARTICLE_DIST_MIN   = cfg.pDistMin
  local PARTICLE_DIST_MAX   = cfg.pDistMax
  local PARTICLE_DELAY_K    = cfg.pDelay
  local PARTICLE_FLIGHT_K   = cfg.pFlight
  local PARTICLE_ALPHA_MIN  = cfg.pAlphaMin
  local PARTICLE_ALPHA_MAX  = cfg.pAlphaMax

  duration = tonumber(duration) or DEFAULT_DUR
  if duration > MAX_DURATION then duration = MAX_DURATION end
  if duration < 0.1 then duration = 0.1 end
  fade = (fade == true)

  local W = (frame.GetWidth and frame:GetWidth()) or 36
  local H = (frame.GetHeight and frame:GetHeight()) or 36

  local tcL, tcR, tcT, tcB = 0, 1, 0, 1
  if frame.icon and frame.icon.GetTexCoord then
    local tcs = { frame.icon:GetTexCoord() }
    local n = table.getn(tcs)
    if n >= 8 then
      local ULx, ULy, LLx, LLy, URx = tcs[1], tcs[2], tcs[3], tcs[4], tcs[5]
      if ULx and ULy and LLx and LLy and URx then
        tcL, tcT, tcR, tcB = ULx, ULy, URx, LLy
      end
    elseif n >= 4 then
      local a, b, c, d = tcs[1], tcs[2], tcs[3], tcs[4]
      if a and b and c and d then
        tcL, tcR, tcT, tcB = a, b, c, d
      end
    end
  end
  if (tcR - tcL) < 0.1 or (tcB - tcT) < 0.1
      or (tcR - tcL) > 1.01 or (tcB - tcT) > 1.01 then
    tcL, tcR, tcT, tcB = 0, 1, 0, 1
  end

  local ofsX, ofsY = 0, 0
  if frame.icon and frame.icon.GetCenter and frame.GetCenter then
    local fx, fy = frame:GetCenter()
    local ix, iy = frame.icon:GetCenter()
    if fx and ix and fy and iy then
      ofsX = ix - fx
      ofsY = iy - fy
    end
  end

  local pieceW = W / GRID
  local pieceH = H / GRID

  local tex = iconTexture
  if type(tex) ~= "string" or tex == "" then
    tex = "Interface\\Icons\\INV_Misc_QuestionMark"
  end

  local hidBackdrop = false
  if frame.icon and frame.icon.Hide then
    frame.icon:Hide()
  end
  if frame.backdrop and frame.backdrop.Hide and frame.backdrop:IsShown() then
    frame.backdrop:Hide()
    hidBackdrop = true
  end

  local maxStagger = MAX_STAGGER_K * duration
  local now = GetTime()

  local st = {
    frame       = frame,
    pieces      = {},
    particles   = {},
    endTime     = now + duration + 0.05,
    hidBackdrop = hidBackdrop,
  }
  self.active[key] = st

  local halfW = W * 0.5
  local halfH = H * 0.5

  local baseAngle = nil
  if dir == "left" then
    baseAngle = math.pi
  elseif dir == "right" then
    baseAngle = 0
  elseif dir == "up" then
    baseAngle = math.pi / 2
  elseif dir == "down" then
    baseAngle = -math.pi / 2
  end

  ----------------------------------------------------------
  -- Pieces
  ----------------------------------------------------------
  local idx = 0
  local r, c
  for r = 1, GRID do
    for c = 1, GRID do
      idx = idx + 1

      local p = _AcquirePiece(Sauce)
      p:SetParent(frame)
      p:SetDrawLayer("OVERLAY", 7)
      p:SetWidth(pieceW * PIECE_START_SCALE)
      p:SetHeight(pieceH * PIECE_START_SCALE)
      p:SetTexture(tex)
      local u0 = tcL + (tcR - tcL) * (c - 1) / GRID
      local u1 = tcL + (tcR - tcL) * c / GRID
      local v0 = tcT + (tcB - tcT) * (r - 1) / GRID
      local v1 = tcT + (tcB - tcT) * r / GRID
      p:SetTexCoord(u0, u1, v0, v1)
      p:SetVertexColor(1, 1, 1, 1)
      -- Grey mode: one-shot desaturation; no per-frame cost.
      -- Pieces come from a shared pool, so reset the flag when grey is off.
      if p.SetDesaturated then
        if grey then
          p:SetDesaturated(1)
        else
          p:SetDesaturated(nil)
        end
      end

      local ex = (c - 0.5) * pieceW - halfW + ofsX
      local ey = halfH - (r - 0.5) * pieceH + ofsY

      local ang
      if baseAngle then
        ang = baseAngle + (math.random() - 0.5) * DIR_CONE_HALF
      else
        ang = math.random() * TWO_PI
      end

      local dist = SCATTER_MIN + math.random() * (SCATTER_MAX - SCATTER_MIN)
      local sx = ex + math.cos(ang) * dist
      local sy = ey + math.sin(ang) * dist

      local d = math.random() * maxStagger
      local pdur = duration - d
      if pdur < 0.1 then pdur = 0.1 end

      local pieceFreq  = WAVE_FREQ_MIN + math.random() * (WAVE_FREQ_MAX - WAVE_FREQ_MIN)
      local piecePhase = math.random() * TWO_PI

      local dxp = ex - sx
      local dyp = ey - sy
      local perpX = -dyp
      local perpY =  dxp
      local plen = math.sqrt(perpX * perpX + perpY * perpY)
      if plen > 0.001 then
        perpX = perpX / plen
        perpY = perpY / plen
      else
        perpX, perpY = 0, 0
      end

      local ps = p._shatterPiece
      ps.key        = key
      ps.shatter    = st
      ps.sx, ps.sy  = sx, sy
      ps.ex, ps.ey  = ex, ey
      ps.perpX, ps.perpY = perpX, perpY
      ps.freq       = pieceFreq
      ps.phase      = piecePhase
      ps.waveAmp    = WAVE_AMP
      ps.pieceStart = PIECE_START_SCALE
      ps.pieceW     = pieceW
      ps.pieceH     = pieceH
      ps.frame      = frame
      ps.fade       = fade

      p:ClearAllPoints()
      p:SetPoint("CENTER", frame, "CENTER", sx, sy)
      if fade then
        p:SetVertexColor(1, 1, 1, 0)
      else
        p:SetVertexColor(1, 1, 1, 1)
      end
      p:Show()

      st.pieces[idx] = p

      local tw = p._shatterTween
      tw:SetDuration(pdur)
      tw:SetDelay(d)
      tw._easing = "outCubic"
      tw:Play()
    end
  end

  ----------------------------------------------------------
  -- Particles
  ----------------------------------------------------------
  local pidx
  for pidx = 1, PARTICLE_COUNT do
    local q = _AcquireParticle(Sauce)
    q:SetParent(frame)
    q:SetDrawLayer("OVERLAY", 7)

    local aBase = PARTICLE_ALPHA_MIN
                + math.random() * (PARTICLE_ALPHA_MAX - PARTICLE_ALPHA_MIN)
    local size  = PARTICLE_SIZE_MIN
                + math.random() * (PARTICLE_SIZE_MAX - PARTICLE_SIZE_MIN)
    q:SetWidth(size)
    q:SetHeight(size)

    local pang
    if baseAngle then
      pang = baseAngle + (math.random() - 0.5) * DIR_CONE_HALF
    else
      pang = math.random() * TWO_PI
    end

    local dist = PARTICLE_DIST_MIN
               + math.random() * (PARTICLE_DIST_MAX - PARTICLE_DIST_MIN)
    local sx = math.cos(pang) * dist + ofsX
    local sy = math.sin(pang) * dist + ofsY

    local ex = ofsX + (math.random() - 0.5) * (W * 0.3)
    local ey = ofsY + (math.random() - 0.5) * (H * 0.3)

    local dly  = math.random() * (PARTICLE_DELAY_K * duration)
    local pdur = PARTICLE_FLIGHT_K * duration
    if pdur < 0.15 then pdur = 0.15 end

    local ps = q._shatterParticle
    ps.key     = key
    ps.shatter = st
    ps.sx, ps.sy = sx, sy
    ps.ex, ps.ey = ex, ey
    ps.aBase   = aBase
    ps.frame   = frame
    ps.fade    = fade

    q:ClearAllPoints()
    q:SetPoint("CENTER", frame, "CENTER", sx, sy)
    if fade then
      q:SetVertexColor(1, 1, 1, 0)
    else
      q:SetVertexColor(1, 1, 1, aBase)
    end
    q:Show()

    st.particles[pidx] = q

    local tw = q._shatterTween
    tw:SetDuration(pdur)
    tw:SetDelay(dly)
    tw._easing = "outQuad"
    tw:Play()
  end

  _tick:Show()
end

function ShatterMgr:_Finish(key)
  local st = self.active[key]
  if not st then return end
  self.active[key] = nil

  local frame = st.frame
  if frame and frame.icon and frame.icon.Show then
    pcall(frame.icon.Show, frame.icon)
  end
  if st.hidBackdrop and frame and frame.backdrop and frame.backdrop.Show then
    pcall(frame.backdrop.Show, frame.backdrop)
  end

  local Sauce = _Sauce()

  local i
  local nPieces = table.getn(st.pieces)
  for i = 1, nPieces do
    local p = st.pieces[i]
    if p then
      if Sauce and Sauce.Stop then
        pcall(Sauce.Stop, Sauce, p)
      end
      _ReleasePiece(p)
      st.pieces[i] = nil
    end
  end

  local nParts = table.getn(st.particles)
  for i = 1, nParts do
    local q = st.particles[i]
    if q then
      if Sauce and Sauce.Stop then
        pcall(Sauce.Stop, Sauce, q)
      end
      _ReleaseParticle(q)
      st.particles[i] = nil
    end
  end
end

function ShatterMgr:Stop(key)
  if not self.active[key] then return end
  self:_Finish(key)
end

-- =================================================================
-- /dshatter -- command-line tuner for shatter + particles.
--
--   /dshatter                       list every parameter and its value
--   /dshatter <key> <value>         set one parameter (see list)
--   /dshatter reset [<key>]         reset one parameter (or all)
--   /dshatter preset save <name>    snapshot current settings
--   /dshatter preset load <name>    apply a saved snapshot
--   /dshatter preset delete <name>  remove a preset
--   /dshatter preset list           show all presets
--   /dshatter export [<name>]       print export string
--   /dshatter import <string>       apply from an export string
--   /dshatter help                  print usage
--
-- Programmatic API (same code path):
--   DoiteShatter.SetParam("grid", 4)
--   DoiteShatter.GetParam("waveAmp")
--   DoiteShatter.ResetParam("pCount")
--   DoiteShatter.SavePreset("wide")
--   DoiteShatter.LoadPreset("wide")
--   DoiteShatter.ExportPreset()        -- -> "DSH1;..."
--   DoiteShatter.ImportPreset(str)     -- -> ok, applied, skipped
--   DoiteShatter.ExportNamedPreset("wide")
--
-- Changes take effect on the NEXT shatter. Active shatters keep the
-- values they were started with, so the effect stays consistent within
-- a single animation.
-- =================================================================

local function _DS_Split(msg)
  local args = {}
  if not msg or msg == "" then return args end
  local tok = ""
  local i = 1
  local n = string.len(msg)
  while i <= n + 1 do
    local c = string.sub(msg, i, i)
    if c == " " or c == "\t" or c == "" then
      if tok ~= "" then
        table.insert(args, tok)
        tok = ""
      end
    else
      tok = tok .. c
    end
    i = i + 1
  end
  return args
end

local function _DS_PrintUsage()
  DEFAULT_CHAT_FRAME:AddMessage("|cff6FA8DC/dshatter|r -- tuner for shatter effect")
  DEFAULT_CHAT_FRAME:AddMessage("  /dshatter                      -- list current values")
  DEFAULT_CHAT_FRAME:AddMessage("  /dshatter <key> <value>        -- set a parameter")
  DEFAULT_CHAT_FRAME:AddMessage("  /dshatter reset [<key>]        -- reset one/all to defaults")
  DEFAULT_CHAT_FRAME:AddMessage("  /dshatter preset save <name>   -- save current config")
  DEFAULT_CHAT_FRAME:AddMessage("  /dshatter preset load <name>   -- apply a saved config")
  DEFAULT_CHAT_FRAME:AddMessage("  /dshatter preset delete <name> -- remove a preset")
  DEFAULT_CHAT_FRAME:AddMessage("  /dshatter preset list          -- show all presets")
  DEFAULT_CHAT_FRAME:AddMessage("  /dshatter export [<name>]      -- print export string (current/preset)")
  DEFAULT_CHAT_FRAME:AddMessage("  /dshatter import <string>      -- apply from an export string")
  DEFAULT_CHAT_FRAME:AddMessage("  /dshatter help                 -- this message")
  DEFAULT_CHAT_FRAME:AddMessage("Examples:")
  DEFAULT_CHAT_FRAME:AddMessage("  /dshatter grid 6")
  DEFAULT_CHAT_FRAME:AddMessage("  /dshatter pTex white")
  DEFAULT_CHAT_FRAME:AddMessage("  /dshatter export")
  DEFAULT_CHAT_FRAME:AddMessage("  /dshatter import DSH1;5,400,400,0.25,20,1.5,3,0.3333,60,spark,50,4,14,300,400,0.3,0.7,0.3,0.8")
end

local function _DS_PrintList()
  local cfg = DoiteShatter.GetCfg()
  DEFAULT_CHAT_FRAME:AddMessage("|cff6FA8DC/dshatter values|r:")
  local i
  for i = 1, table.getn(PARAM_ORDER) do
    local k = PARAM_ORDER[i]
    local v = cfg[k]
    local def = DEFAULTS[k]
    local mark = (v == def) and "" or "  |cffffd000(modified)|r"
    DEFAULT_CHAT_FRAME:AddMessage("  " .. k .. " = " .. tostring(v) .. mark)
  end
  DEFAULT_CHAT_FRAME:AddMessage("|cff6FA8DCpTex values:|r spark | gold | white")
end

local function _DS_HandleCommand(msg)
  local args = _DS_Split(msg)

  if table.getn(args) == 0 then
    _DS_PrintList()
    return
  end

  local cmd = string.lower(args[1])

  if cmd == "help" then
    _DS_PrintUsage()
    return
  end

  if cmd == "reset" then
    if table.getn(args) >= 2 then
      local k = args[2]
      if DEFAULTS[k] == nil then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040/dshatter:|r unknown key '" .. k .. "'")
        return
      end
      DoiteShatter.ResetParam(k)
      DEFAULT_CHAT_FRAME:AddMessage("|cff6FA8DC/dshatter:|r reset " .. k)
    else
      DoiteShatter.ResetParam(nil)
      DEFAULT_CHAT_FRAME:AddMessage("|cff6FA8DC/dshatter:|r all parameters reset to defaults")
    end
    return
  end

  if cmd == "export" then
    local name = args[2]
    if name then
      local str = DoiteShatter.ExportNamedPreset(name)
      if not str then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040/dshatter:|r no preset named '" .. name .. "'")
        return
      end
      DEFAULT_CHAT_FRAME:AddMessage("|cff6FA8DC/dshatter export '" .. name .. "':|r")
      DEFAULT_CHAT_FRAME:AddMessage(str)
    else
      local str = DoiteShatter.ExportPreset()
      DEFAULT_CHAT_FRAME:AddMessage("|cff6FA8DC/dshatter export (current):|r")
      DEFAULT_CHAT_FRAME:AddMessage(str)
    end
    return
  end

  if cmd == "import" then
    if table.getn(args) < 2 then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff4040/dshatter:|r usage: /dshatter import <string>")
      return
    end
    -- Rejoin in case the client split the string on whitespace
    -- (our format has none, but a stray space from copy-paste would
    -- otherwise silently drop the tail).
    local str = args[2]
    local i
    for i = 3, table.getn(args) do
      str = str .. args[i]
    end
    local ok, applied, skipped = DoiteShatter.ImportPreset(str)
    if not ok then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff4040/dshatter:|r import failed: " .. tostring(applied))
      return
    end
    DEFAULT_CHAT_FRAME:AddMessage(
      "|cff6FA8DC/dshatter:|r imported " .. tostring(applied) ..
      " values, skipped " .. tostring(skipped))
    return
  end

  if cmd == "preset" then
    local sub = args[2] and string.lower(args[2]) or ""

    if sub == "" or sub == "list" then
      local names = DoiteShatter.ListPresets()
      if table.getn(names) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff6FA8DC/dshatter:|r no presets saved")
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cff6FA8DC/dshatter presets:|r " .. table.concat(names, ", "))
      end
      return
    end

    if sub == "save" then
      local name = args[3]
      if not name then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040/dshatter:|r usage: /dshatter preset save <name>")
        return
      end
      local ok, err = DoiteShatter.SavePreset(name)
      if not ok then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040/dshatter:|r " .. err)
        return
      end
      DEFAULT_CHAT_FRAME:AddMessage("|cff6FA8DC/dshatter:|r preset '" .. name .. "' saved")
      return
    end

    if sub == "load" then
      local name = args[3]
      if not name then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040/dshatter:|r usage: /dshatter preset load <name>")
        return
      end
      local ok, err = DoiteShatter.LoadPreset(name)
      if not ok then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040/dshatter:|r " .. err)
        return
      end
      DEFAULT_CHAT_FRAME:AddMessage("|cff6FA8DC/dshatter:|r preset '" .. name .. "' loaded")
      return
    end

    if sub == "delete" or sub == "del" then
      local name = args[3]
      if not name then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040/dshatter:|r usage: /dshatter preset delete <name>")
        return
      end
      local ok = DoiteShatter.DeletePreset(name)
      if not ok then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040/dshatter:|r no preset named '" .. name .. "'")
        return
      end
      DEFAULT_CHAT_FRAME:AddMessage("|cff6FA8DC/dshatter:|r preset '" .. name .. "' deleted")
      return
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cffff4040/dshatter:|r usage: /dshatter preset [save|load|delete|list] <name>")
    return
  end

  -- set form: /dshatter <key> <value>
  if table.getn(args) >= 3 then
    local k = args[1]
    local v = args[2]
    if not PARAM_BOUNDS[k] then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff4040/dshatter:|r unknown key '" .. k .. "'")
      return
    end
    local ok, err = DoiteShatter.SetParam(k, v)
    if not ok then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff4040/dshatter:|r " .. err)
      return
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff6FA8DC/dshatter:|r " .. k .. " = " .. tostring(DoiteShatter.GetParam(k)))
    return
  end

  _DS_PrintUsage()
end

SLASH_DSHATTER1 = "/dshatter"
SLASH_DSHATTER2 = "/dsh"
SlashCmdList["DSHATTER"] = _DS_HandleCommand