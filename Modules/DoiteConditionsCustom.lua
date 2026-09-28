---------------------------------------------------------------
-- DoiteConditionsCustom.lua
-- Custom (user-provided Lua) icon support.
-- Extracted from DoiteConditions.lua (Phase 1 of the split).
--
-- Functions in this file:
--   _DoiteCustomCompileForData    - compile "return function(data) ... end"
--   _DoiteCustomPrintOnce         - dedup error printing to chat
--   _DoiteCustomClearError        - clear per-icon last-error marker
--   _DoiteCustomEvaluateOne       - run compiled logic for a single icon
--   DoiteConditions:EvaluateCustom - iterate all Custom icons in DB
--
-- Loaded AFTER DoiteConditions.lua:
--   * uses DoiteConditions:ApplyVisuals (defined there)
--   * uses DoiteConditions._PruneBadEntries (defined there)
--   * reads _G["DOITE_DEFAULT_CUSTOM_FUNCTION_SOURCE"] (set by DoiteEdit.lua)
---------------------------------------------------------------

local DoiteConditions = _G["DoiteConditions"] or {}
_G["DoiteConditions"] = DoiteConditions

local function _DoiteCustomCompileForData(key, data)
  if type(data) ~= "table" then
    return nil, "Invalid custom data entry."
  end

  local src = data.customFunctionSource
  if type(src) ~= "string" or src == "" then
    src = _G["DOITE_DEFAULT_CUSTOM_FUNCTION_SOURCE"]
    data.customFunctionSource = src
  end

  if data._daCustomCompiled and data._daCustomCompiledSrc == src then
    return data._daCustomCompiled, nil
  end

  local wrapped = "return function(data)\n" .. src .. "\nend"
  local chunk, err = loadstring(wrapped)
  if not chunk then
    return nil, err
  end

  local ok, fn = pcall(chunk)
  if not ok then
    return nil, fn
  end
  if type(fn) ~= "function" then
    return nil, "Compiled custom source is not callable."
  end

  data._daCustomCompiled = fn
  data._daCustomCompiledSrc = src
  data._daCustomCompileError = nil
  return fn, nil
end

local function _DoiteCustomPrintOnce(data, key, prefix, msg)
  if type(data) ~= "table" then
    return
  end
  local sig = tostring(prefix or "Custom") .. ": " .. tostring(msg or "?")
  if data._daCustomLastError == sig then
    return
  end
  data._daCustomLastError = sig

  local cf = DEFAULT_CHAT_FRAME or ChatFrame1
  if cf and cf.AddMessage then
    cf:AddMessage("|cffff4040DoiteAuras custom [" .. tostring(key or "?") .. "] " .. tostring(prefix or "error") .. ":|r " .. tostring(msg))
  end
end

local function _DoiteCustomClearError(data)
  if type(data) == "table" then
    data._daCustomLastError = nil
  end
end

local function _DoiteCustomEvaluateOne(key, data)
  if type(data) ~= "table" then
    return false
  end

  local fn, compileErr = _DoiteCustomCompileForData(key, data)
  if not fn then
    _DoiteCustomPrintOnce(data, key, "compile error", compileErr)
    data._daCustomShow = false
    data._daCustomTexture = nil
    data._daCustomHideBG = false
    data._daCustomRemaining = nil
    data._daCustomStacks = nil
    DoiteConditions:ApplyVisuals(key, false, false, false, false, 0)
    return true
  end

  local DC = _G["DoiteConditions"]
  local state = DC and DC._customStateByKey and DC._customStateByKey[key]
  if type(state) ~= "table" then
    state = {}
    if DC then
      DC._customStateByKey = DC._customStateByKey or {}
      DC._customStateByKey[key] = state
    end
  end

  local ok, show, texture, hideBackground, remaining, stacks = pcall(fn, state)
  if not ok then
    _DoiteCustomPrintOnce(data, key, "runtime error", show)
    data._daCustomShow = false
    data._daCustomTexture = nil
    data._daCustomHideBG = false
    data._daCustomRemaining = nil
    data._daCustomStacks = nil
    DoiteConditions:ApplyVisuals(key, false, false, false, false, 0)
    return true
  end

  _DoiteCustomClearError(data)
  data._daCustomShow = (show == true or show == 1)
  data._daCustomTexture = (type(texture) == "string" and texture ~= "") and texture or nil
  data._daCustomHideBG = (hideBackground == true)
  data._daCustomRemaining = (type(remaining) == "number") and remaining or nil
  data._daCustomStacks = (type(stacks) == "number") and stacks or nil

  DoiteConditions:ApplyVisuals(key, data._daCustomShow, false, false, false, 0)
  return true
end

function DoiteConditions:EvaluateCustom()
  local live = DoiteAurasDB and DoiteAurasDB.spells
  local edit = DoiteDB and DoiteDB.icons
  local touched = false

  if live then
    DoiteConditions._PruneBadEntries(live)

    for key, data in pairs(live) do
      if data.type == "Custom" then
        data.key = key
        if _DoiteCustomEvaluateOne(key, data) then
          touched = true
        end
      end
    end
  end

  if edit then
    DoiteConditions._PruneBadEntries(edit)

    for key, data in pairs(edit) do
      if (not live) or (not live[key]) then
        if data.type == "Custom" then
          data.key = key
          if _DoiteCustomEvaluateOne(key, data) then
            touched = true
          end
        end
      end
    end
  end

  return touched
end