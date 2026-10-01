---------------------------------------------------------------
-- Modules/DoiteTexturePicker.lua
-- Generic grid texture picker (scroll + thumbnails).
--
-- Any module can call:
--   DoiteTexturePicker.Open(entries, getCurrent, onPick, title)
--
--   entries    : array of { value=string, label=string,
--                           tc={u0,u1,v0,v1} (optional),
--                           previewTex=string (optional) }
--   getCurrent : function() -> currently selected value (for highlight)
--   onPick     : function(value)  called after the frame closes
--   title      : optional header text
--
-- Singleton frame with a cached button pool. Reopened across the
-- session for free; all render is released on Hide, and the pick
-- callback is dropped so no closure is pinned by a hidden frame.
-- Call Destroy() to force-release the cache (next Open rebuilds).
--
-- Missing texture files are harmless: in 1.12 SetTexture on a
-- non-existent path is a silent no-op (the button just renders
-- blank, no error). Argument types are checked at the call site,
-- not pcall-guarded.
--
-- Loaded AFTER DoiteGlow.lua (uses nothing from it directly, but the
-- canonical caller builds its entries there).
--
-- WoW 1.12 | Lua 5.0
---------------------------------------------------------------

local P = {}
_G["DoiteTexturePicker"] = P

-- Grid layout. 8 columns of 36x36 buttons.
local COLS     = 8
local BTN_SIZE = 36
local COL_W    = 40
local ROW_H    = 40
local PAD_X    = 16
local PAD_TOP  = 6

local FRAME_W  = 400
local FRAME_H  = 480
local HEADER_H = 46
local SCROLL_W = FRAME_W - 50
local SCROLL_H = FRAME_H - HEADER_H - 16

P._frame    = nil
P._buttons  = nil
P._entries  = nil
P._getCur   = nil
P._onPick   = nil

local function _CreateButton(parent, idx)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(BTN_SIZE)
  b:SetHeight(BTN_SIZE)

  -- edgeSize 14 makes the UI-Tooltip-Border art draw a visibly thick
  -- frame; the default 8 was too thin to read on the dark backdrop.
  b:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  b:SetBackdropBorderColor(1, 1, 1, 0)

  -- Classic CheckButtonHilight overlay, ADD-blended. Gives the
  -- selected tile a bright cyan glow that reads on any texture, on
  -- top of the border above.
  b.highlight = b:CreateTexture(nil, "OVERLAY")
  b.highlight:SetAllPoints(b)
  b.highlight:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  b.highlight:SetBlendMode("ADD")
  b.highlight:SetVertexColor(0.2, 0.9, 1, 0)

  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetPoint("TOPLEFT",     b, "TOPLEFT",      2,  -2)
  b.tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2,   2)

  b._idx = idx

  b:SetScript("OnClick", function()
    local entry = P._entries and P._entries[this._idx]
    if not entry then return end
    local cb = P._onPick
    -- Close first; a callback that opens other UI runs on a clean
    -- stack, and the hide path has already dropped _onPick.
    P.Close()
    if cb then cb(entry.value) end
  end)

  b:SetScript("OnEnter", function()
    local entry = P._entries and P._entries[this._idx]
    if not entry then return end
    if GameTooltip then
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:AddLine(entry.label or entry.value or "?")
      GameTooltip:Show()
    end
    -- Hover wins over selection: yellow border, hide the cyan glow.
    this:SetBackdropBorderColor(1, 0.82, 0, 1)
    this.highlight:SetVertexColor(0.2, 0.9, 1, 0)
  end)

  b:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
    P.RefreshSelection()
  end)

  return b
end

local function _EnsureFrame()
  if P._frame then return P._frame end

  local f = CreateFrame("Frame", "DoiteTexturePickerFrame", UIParent)
  P._frame = f

  f:SetWidth(FRAME_W)
  f:SetHeight(FRAME_H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  if f.SetToplevel then f:SetToplevel(true) end
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop",  function() this:StopMovingOrSizing() end)
  f:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  f:SetBackdropColor(0, 0, 0, 1)
  f:SetBackdropBorderColor(1, 1, 1, 1)
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  f:Hide()

  if UISpecialFrames then
    table.insert(UISpecialFrames, "DoiteTexturePickerFrame")
  end

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -14)
  title:SetText("|cff6FA8DCTexture|r")
  f._title = title

  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  if hint.SetTextColor then hint:SetTextColor(0.7, 0.7, 0.7) end
  hint:SetText("Click a texture to apply. Esc closes.")
  f._hint = hint

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

  local scroll = CreateFrame("ScrollFrame", "DoiteTexturePickerScroll",
                             f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -HEADER_H)
  scroll:SetWidth(SCROLL_W)
  scroll:SetHeight(SCROLL_H)
  f._scroll = scroll

  local content = CreateFrame("Frame", "DoiteTexturePickerContent", scroll)
  content:SetWidth(SCROLL_W)
  scroll:SetScrollChild(content)
  f._content = content

  f:SetScript("OnHide", function()
    -- Drop both closures so a hidden frame does not pin the caller's
    -- state (e.g. a Settings dialog ref).
    P._onPick = nil
    P._getCur = nil
    if GameTooltip then GameTooltip:Hide() end
  end)

  return f
end

local function _ApplyPreview(b, entry)
  if not b or not b.tex then return end
  local tex = entry.previewTex or entry.value
  if type(tex) ~= "string" or tex == "" then return end
  local u0, u1, v0, v1 = 0, 1, 0, 1
  if entry.tc then
    u0, u1, v0, v1 = entry.tc[1], entry.tc[2], entry.tc[3], entry.tc[4]
  end
  b.tex:SetTexture(tex)
  b.tex:SetTexCoord(u0, u1, v0, v1)
end

-- Public: open with a fresh entry list. If already open, replaces
-- entries and repaints. Frame and button pool are reused.
function P.Open(entries, getCurrent, onPick, title)
  if type(entries) ~= "table" then return end

  local f = _EnsureFrame()

  P._entries = entries
  P._getCur  = getCurrent
  P._onPick  = onPick

  if title and f._title then
    f._title:SetText("|cff6FA8DC" .. tostring(title) .. "|r")
  end

  local n    = table.getn(entries)
  local rows = math.ceil(n / COLS)
  f._content:SetHeight(rows * ROW_H + PAD_TOP + 10)

  P._buttons = P._buttons or {}
  local buttons = P._buttons

  local i
  for i = 1, n do
    local b = buttons[i]
    if not b then
      b = _CreateButton(f._content, i)
      buttons[i] = b
    end
    b._idx = i

    local idx0 = i - 1
    local col  = idx0 % COLS
    local row  = math.floor(idx0 / COLS)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f._content, "TOPLEFT",
               PAD_X + col * COL_W,
               -(PAD_TOP + row * ROW_H))

    _ApplyPreview(b, entries[i])
    b:Show()
  end

  -- Hide any surplus buttons from a previous, longer entry list.
  local total = table.getn(buttons)
  i = n + 1
  while i <= total do
    buttons[i]:Hide()
    i = i + 1
  end

  P.RefreshSelection()

  f:Show()
  if f.SetToplevel then f:SetToplevel(true) end
  if f.Raise then f:Raise() end
end

-- Repaint the selection highlight against the current getCurrent()
-- value. Called from Open, and after OnLeave so hover always ends
-- back at the canonical selection state.
--
-- No pcall: the callback is our own closure on the caller side, and
-- an error there is a bug worth seeing rather than swallowing.
function P.RefreshSelection()
  if not P._buttons or not P._entries then return end

  local cur = nil
  if type(P._getCur) == "function" then
    cur = P._getCur()
  end

  local i
  for i = 1, table.getn(P._entries) do
    local b = P._buttons[i]
    if b then
      if cur ~= nil and P._entries[i].value == cur then
        b:SetBackdropBorderColor(0.2, 0.9, 1, 1)
        if b.highlight then b.highlight:SetVertexColor(0.2, 0.9, 1, 0.7) end
      else
        b:SetBackdropBorderColor(1, 1, 1, 0)
        if b.highlight then b.highlight:SetVertexColor(0.2, 0.9, 1, 0) end
      end
    end
  end
end

function P.Close()
  if P._frame then P._frame:Hide() end
end

function P.IsShown()
  return P._frame and P._frame:IsShown()
end

-- Force-release the singleton frame + button pool. Normal usage never
-- needs this (Hide releases all render, and callbacks are dropped in
-- OnHide). Use it from /run if you want the memory back mid-session;
-- next Open rebuilds everything from scratch.
function P.Destroy()
  if not P._frame then return end
  P._frame:Hide()
  P._frame:SetParent(nil)
  P._frame   = nil
  P._buttons = nil
  P._entries = nil
  P._onPick  = nil
  P._getCur  = nil
end