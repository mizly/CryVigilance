-- =============================================================================
-- CryVigilance/index.lua  -  Lua port of the CryVigilance config library
-- Renders a settings GUI via ImGui and persists values to a TOML file.
-- =============================================================================

local luajava_ok, File = pcall(function() return luajava.bindClass("java.io.File") end)

local CryVigilance = {}
CryVigilance.__index = CryVigilance

-- ── Signal directory for cross-script communication ──────────────────────
local SIGNAL_DIR = "config/hypixelcry/scripts/config/.crygui_signals/"

-- ── Property type constants ────────────────────────────────────────────────── 
CryVigilance.TYPES = {
    SWITCH         = "switch",
    CHECKBOX       = "checkbox",
    TEXT           = "text",
    PARAGRAPH      = "paragraph",
    SLIDER         = "slider",
    DECIMAL_SLIDER = "decimal_slider",
    PERCENT_SLIDER = "percent_slider",
    NUMBER         = "number",
    COLOR          = "color",
    SELECTOR       = "selector",
    BUTTON         = "button",
    V_SLIDER       = "v_slider",
    ANGLE_SLIDER   = "angle_slider",
    IMAGE          = "image",
}

-- ============================================================================
-- TOML helpers
-- ============================================================================

local function toTomlValue(v, propType)
    if propType == CryVigilance.TYPES.COLOR then
        return string.format('"%d,%d,%d,%d"', v[1], v[2], v[3], v[4])
    elseif type(v) == "boolean" then
        return tostring(v)
    elseif type(v) == "number" then
        if propType == CryVigilance.TYPES.DECIMAL_SLIDER or propType == CryVigilance.TYPES.PERCENT_SLIDER then
            return string.format("%.6f", v)
        end
        return tostring(math.floor(v + 0.5))
    elseif type(v) == "string" then
        local escaped = v:gsub("\\", "\\\\"):gsub('"', '\\"')
        return '"' .. escaped .. '"'
    end
    return '"' .. tostring(v) .. '"'
end

local function fromTomlValue(s, propType)
    s = s:match("^%s*(.-)%s*$")
    if propType == CryVigilance.TYPES.COLOR then
        local raw = s:match('^"(.*)"$') or s
        local a, r, g, b = raw:match("(%d+),(%d+),(%d+),(%d+)")
        if a then return { tonumber(a), tonumber(r), tonumber(g), tonumber(b) } end
        return nil
    elseif s == "true" then
        return true
    elseif s == "false" then
        return false
    elseif s:match('^"(.*)"$') then
        local inner = s:match('^"(.*)"$')
        inner = inner:gsub('\\"', '"'):gsub("\\\\", "\\")
        return inner
    elseif s:match("^%-?%d+%.%d+$") then
        return tonumber(s)
    elseif s:match("^%-?%d+$") then
        return tonumber(s)
    end
    return s
end

local function saveToml(path, data)
    local lines = {}
    for cat, subs in pairs(data) do
        table.insert(lines, "")
        table.insert(lines, "[" .. cat .. "]")
        for sub, keys in pairs(subs) do
            table.insert(lines, "")
            table.insert(lines, "\t[" .. cat .. "." .. sub .. "]")
            for k, entry in pairs(keys) do
                local val = toTomlValue(entry.value, entry.propType)
                table.insert(lines, "\t\t" .. k .. " = " .. val)
            end
        end
    end
    local f, err = io.open(path, "w")
    if not f then
        print("[CryVigilance] Could not write config: " .. tostring(err))
        return
    end
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end

local function loadToml(path, propList)
    local keyTypes = {}
    for _, prop in ipairs(propList) do
        keyTypes[prop.key] = prop.type
    end
    local values = {}
    local f = io.open(path, "r")
    if not f then return values end
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.+)$")
        if k and v then
            local pt = keyTypes[k]
            local parsed = fromTomlValue(v, pt)
            if parsed ~= nil then
                values[k] = parsed
            end
        end
    end
    f:close()
    return values
end

local function _ensureDirectory(path)
    if not luajava_ok or not File then return end
    -- extract directory from path (e.g. "config/hypixelcry/scripts/config/test.toml" -> "config/hypixelcry/scripts/config/")
    local dirPath = path:match("(.*[/\\])")
    if dirPath then
        local f = luajava.newInstance("java.io.File", dirPath)
        if not f:exists() then
            f:mkdirs()
        end
    end
end

-- ============================================================================
-- Constructor
-- ============================================================================

--- Create a new CryVigilance config instance.
-- @param moduleName  string  module name
-- @param guiTitle    string  ImGui window title
-- @param configPath  string  path to .toml file (relative to MC working dir)
-- @param openKey     number  GLFW key to toggle GUI (default 344 = RSHIFT)
function CryVigilance.new(moduleName, guiTitle, configPath, openKey)
    local self = setmetatable({}, CryVigilance)
    self.moduleName      = moduleName or "CryVigilance"
    self.guiTitle        = guiTitle   or (moduleName .. " Settings")
    self.configPath      = configPath or ("config/hypixelcry/scripts/config/" .. moduleName .. ".toml")
    self.openKey         = openKey    or 344  -- RSHIFT

    self._props          = {}   -- ordered list of property descriptors
    self._values         = {}   -- key -> current value
    self._listeners      = {}   -- key -> function(newValue)
    self._depends        = {}   -- key -> dependency key
    self._categories     = {}   -- ordered list of unique category names
    self._open           = false
    self._dirty          = false
    self._activeCategory = nil

    return self
end

-- ============================================================================
-- Property registration
-- ============================================================================

--- Register a property.
-- Required fields: type, key, name, category
-- Optional: subcategory, description, default, min, max, minF, maxF,
--           decimalPlaces, options, allowAlpha, placeholder, protected, action
function CryVigilance:addProperty(p)
    assert(p.type,     "[CryVigilance] property missing 'type'")
    assert(p.key,      "[CryVigilance] property missing 'key'")
    assert(p.name,     "[CryVigilance] property missing 'name'")
    assert(p.category, "[CryVigilance] property missing 'category'")

    p.subcategory   = p.subcategory   or ""
    p.description   = p.description   or ""
    p.allowAlpha    = (p.allowAlpha   ~= false)
    p.options       = p.options       or {}
    p.min           = p.min           or 0
    p.max           = p.max           or 100
    p.minF          = p.minF          or 0.0
    p.maxF          = p.maxF          or 1.0
    p.decimalPlaces = p.decimalPlaces or 2
    p.increment     = p.increment     or 1
    p.protected     = p.protected     or false
    p.placeholder   = p.placeholder   or ""
    p.hidden        = p.hidden        or false

    if p.default == nil then
        local T = CryVigilance.TYPES
        if     p.type == T.SWITCH         then p.default = false
        elseif p.type == T.CHECKBOX       then p.default = false
        elseif p.type == T.TEXT           then p.default = ""
        elseif p.type == T.PARAGRAPH      then p.default = ""
        elseif p.type == T.SLIDER         then p.default = p.min
        elseif p.type == T.DECIMAL_SLIDER then p.default = p.minF
        elseif p.type == T.PERCENT_SLIDER then p.default = 0.0
        elseif p.type == T.NUMBER         then p.default = p.min
        elseif p.type == T.COLOR          then p.default = {255, 255, 255, 255}  -- {A,R,G,B}
        elseif p.type == T.SELECTOR       then p.default = 1
        elseif p.type == T.BUTTON         then p.default = nil
        elseif p.type == T.V_SLIDER       then p.default = p.minF or p.min or 0
        elseif p.type == T.ANGLE_SLIDER   then p.default = 0
        elseif p.type == T.IMAGE          then p.default = nil
        end
    end

    table.insert(self._props, p)

    local found = false
    for _, c in ipairs(self._categories) do
        if c == p.category then found = true; break end
    end
    if not found then table.insert(self._categories, p.category) end

    return self
end

-- ============================================================================
-- Listeners & dependencies
-- ============================================================================

function CryVigilance:onChanged(key, fn)
    self._listeners[key] = fn
    return self
end

function CryVigilance:addDependency(dependentKey, dependencyKey)
    self._depends[dependentKey] = dependencyKey
    return self
end

function CryVigilance:hideProperty(key)
    for _, p in ipairs(self._props) do
        if p.key == key then p.hidden = true; break end
    end
    return self
end



-- ============================================================================
-- Value accessors
-- ============================================================================

function CryVigilance:get(key)   return self._values[key] end
function CryVigilance:set(key, v) self._values[key] = v; self._dirty = true end

--- Programmatically open this config GUI.
function CryVigilance:open()   self._open = true  end
--- Programmatically close this config GUI.
function CryVigilance:close()  self._open = false end
--- Toggle this config GUI open/closed.
function CryVigilance:toggle() self._open = not self._open end

--- Write a signal file to request opening a config GUI by moduleName.
-- This is the cross-script communication mechanism: CryGUI writes a signal,
-- the target CryVigilance instance picks it up on the next tick.
function CryVigilance.requestOpen(moduleName)
    _ensureDirectory(SIGNAL_DIR .. "dummy")
    local f = io.open(SIGNAL_DIR .. moduleName .. ".open", "w")
    if f then
        f:write("open")
        f:close()
    end
end

-- ============================================================================
-- Internal helpers
-- ============================================================================

local function _isVisible(self, prop)
    if prop.hidden then return false end
    local dep = self._depends[prop.key]
    if dep then
        local dv = self._values[dep]
        if dv == false or dv == nil then return false end
    end
    return true
end

local function _fireListener(self, key, newValue)
    local fn = self._listeners[key]
    if fn then
        local ok, err = pcall(fn, newValue)
        if not ok then
            print("[CryVigilance] listener error for '" .. key .. "': " .. tostring(err))
        end
    end
end

local function _setValue(self, key, newValue)
    if self._values[key] ~= newValue then
        self._values[key] = newValue
        self._dirty = true
        _fireListener(self, key, newValue)
    end
end

function CryVigilance:resetToDefaults()
    for _, prop in ipairs(self._props) do
        if prop.type ~= CryVigilance.TYPES.BUTTON then
            _setValue(self, prop.key, prop.default)
        end
    end
end

-- ============================================================================
-- initialize
-- ============================================================================

function CryVigilance:initialize()
    _ensureDirectory(self.configPath)

    -- Write a registry file so CryGUI can discover this module
    _ensureDirectory(SIGNAL_DIR .. "dummy")
    local regFile = io.open(SIGNAL_DIR .. self.moduleName .. ".registered", "w")
    if regFile then
        regFile:write(self.moduleName)
        regFile:close()
    end

    local saved = loadToml(self.configPath, self._props)

    for _, prop in ipairs(self._props) do
        local v = saved[prop.key]
        self._values[prop.key] = (v ~= nil) and v or prop.default

        if prop.triggerActionOnInitialization ~= false and prop.type ~= CryVigilance.TYPES.BUTTON then
            _fireListener(self, prop.key, self._values[prop.key])
        end
    end

    local self_ref = self

    registerKeyEvent(function(key, action)
        if key == self_ref.openKey and action == "Press" then
            self_ref._open = not self_ref._open
        end
    end)

    registerImGuiRenderEvent(function()
        self_ref:_render()
    end)

    registerClientTickPost(function()
        if self_ref._dirty then
            self_ref:save()
            self_ref._dirty = false
        end

        -- Check for an open signal from CryGUI
        local signalPath = SIGNAL_DIR .. self_ref.moduleName .. ".open"
        local sf = io.open(signalPath, "r")
        if sf then
            sf:close()
            -- Delete the signal file and open the GUI
            os.remove(signalPath)
            self_ref._open = true
        end
    end)
end

--- Clean up resources (call this in your registerUnloadCallback).
function CryVigilance:destroy()
    -- Remove registry and signal files
    pcall(os.remove, SIGNAL_DIR .. self.moduleName .. ".registered")
    pcall(os.remove, SIGNAL_DIR .. self.moduleName .. ".open")

    if self._imageObjects then
        for _, entry in pairs(self._imageObjects) do
            if entry.handle then
                pcall(function() entry.handle.release() end)
            end
        end
        self._imageObjects = {}
    end
end

-- ============================================================================
-- Save
-- ============================================================================

function CryVigilance:save()
    local data = {}
    for _, prop in ipairs(self._props) do
        if prop.type ~= CryVigilance.TYPES.BUTTON then
            local cat = prop.category:lower():gsub("%s+", "_")
            local sub = (prop.subcategory == "" and cat or prop.subcategory:lower():gsub("%s+", "_"))
            data[cat] = data[cat] or {}
            data[cat][sub] = data[cat][sub] or {}
            data[cat][sub][prop.key] = { value = self._values[prop.key], propType = prop.type }
        end
    end
    saveToml(self.configPath, data)
end

-- ============================================================================
-- ImGui property rendering
-- Using confirmed API signatures from farming.lua / multiscript.lua:
--   imgui.inputText(label, value)                -> (changed, newValue)
--   imgui.inputInt(label, value, step, fast)     -> (changed, newValue)
--   imgui.inputFloat(label, value, step, f, fmt) -> (changed, newValue)
--   imgui.checkbox(label, value)                 -> (changed, newValue)
--   imgui.listBox(label, value, options)         -> newValue  (always, no bool)
-- ============================================================================

local function _renderProperty(self, prop)
    local key = prop.key
    local val = self._values[key]
    local T   = CryVigilance.TYPES

    -- ── SWITCH ────────────────────────────────────────────────────────────── 
    if prop.type == T.SWITCH then
        local changed, newVal = imgui.checkbox("##sw_" .. key, val or false)
        if changed then _setValue(self, key, newVal) end
        imgui.sameLine()
        imgui.text(prop.name)

    -- ── CHECKBOX ──────────────────────────────────────────────────────────── 
    elseif prop.type == T.CHECKBOX then
        local changed, newVal = imgui.checkbox(prop.name .. "##cb_" .. key, val or false)
        if changed then _setValue(self, key, newVal) end

    -- ── TEXT ──────────────────────────────────────────────────────────────── 
    elseif prop.type == T.TEXT then
        local curVal = tostring(val or "")
        
        if prop.protected then
            -- Initialise secret visibility state on the instance
            if not self._showSecrets then self._showSecrets = {} end
            local show = self._showSecrets[key] or false
            
            -- [Show/Hide] toggle button
            local btnLabel = (show and "Hide##btn_" or "Show##btn_") .. key
            if imgui.button(btnLabel) then
                show = not show
                self._showSecrets[key] = show
            end
            imgui.sameLine()
            
            if show then
                -- REVEALED: Normal editable input field
                local changed, newVal = imgui.inputText(prop.name .. "##txt_" .. key, curVal)
                if changed then _setValue(self, key, newVal) end
            else
                -- HIDDEN: Masked display only (secure and compatible)
                local masked = curVal:gsub(".", "•")
                if masked == "" then masked = "(empty)" end
                imgui.text(prop.name .. ": " .. masked)
            end
        else
            -- Regular unprotected text field
            local changed, newVal = imgui.inputText(prop.name .. "##txt_" .. key, curVal)
            if changed then _setValue(self, key, newVal) end
        end

    -- ── PARAGRAPH ─────────────────────────────────────────────────────────── 
    -- Try inputTextMultiline for true multi-line editing (Enter = newline).
    -- Falls back to plain inputText if the function is not in this binding.
    elseif prop.type == T.PARAGRAPH then
        imgui.text(prop.name .. ":")
        local curVal = tostring(val or "")
        if type(imgui.inputTextMultiline) == "function" then
            -- inputTextMultiline(label, value, width, height) -> (changed, newValue)
            -- width -1 = fill available horizontal space, height 120 = ~6 lines
            local ok, changed, newVal = pcall(imgui.inputTextMultiline, "##para_" .. key, curVal, -1, 120)
            if ok and changed and newVal ~= nil then _setValue(self, key, newVal) end
            if not ok then
                -- function exists but signature differs; try without size args
                local ok2, changed2, newVal2 = pcall(imgui.inputTextMultiline, "##para_" .. key, curVal)
                if ok2 and changed2 and newVal2 ~= nil then _setValue(self, key, newVal2) end
            end
        else
            local changed, newVal = imgui.inputText("##para_" .. key, curVal)
            if changed then _setValue(self, key, newVal) end
        end

    -- ── SLIDER (integer) ──────────────────────────────────────────────────── 
    -- Now using the actual imgui.sliderInt method
    elseif prop.type == T.SLIDER then
        local cur = math.floor(val or prop.min)
        local label = prop.name .. "##sl_" .. key
        
        local changed, newVal
        if type(imgui.sliderInt) == "function" then
            changed, newVal = imgui.sliderInt(label, cur, prop.min, prop.max)
        else
            -- Fallback to inputInt if sliderInt isn't available
            changed, newVal = imgui.inputInt(label .. " [" .. prop.min .. "-" .. prop.max .. "]", cur, prop.increment, prop.increment * 5)
        end
        
        if changed then
            newVal = math.max(prop.min, math.min(prop.max, newVal))
            _setValue(self, key, newVal)
        end

    -- ── DECIMAL SLIDER ────────────────────────────────────────────────────── 
    -- Now using the actual imgui.sliderFloat method
    elseif prop.type == T.DECIMAL_SLIDER then
        local cur = val or prop.minF
        local fmt = "%." .. prop.decimalPlaces .. "f"
        local label = prop.name .. "##dsl_" .. key
        
        local changed, newVal
        if type(imgui.sliderFloat) == "function" then
            changed, newVal = imgui.sliderFloat(label, cur, prop.minF, prop.maxF)
        else
            -- Fallback to inputFloat
            changed, newVal = imgui.inputFloat(label .. " [" .. string.format(fmt, prop.minF) .. "-" .. string.format(fmt, prop.maxF) .. "]", cur, 0.1, 1.0, fmt)
        end
        
        if changed then
            newVal = math.max(prop.minF, math.min(prop.maxF, newVal))
            _setValue(self, key, newVal)
        end

    -- ── PERCENT SLIDER ────────────────────────────────────────────────────── 
    -- Now using sliderFloat for a better UI experience
    elseif prop.type == T.PERCENT_SLIDER then
        local cur = val or 0.0
        -- Stored as 0.0-1.0
        local label = prop.name .. "##psl_" .. key
        
        local changed, newVal
        if type(imgui.sliderFloat) == "function" then
            -- Note: ImGui often allows a format string in sliderFloat, e.g. "%.0f%%"
            -- We'll assume the basic (label, value, min, max) for now based on your list
            changed, newVal = imgui.sliderFloat(label, cur, 0.0, 1.0)
        else
            -- Fallback: display as 0-100, store as 0.0-1.0
            local displayPct = cur * 100
            local chPct, newPct = imgui.inputFloat(prop.name .. " [0-100%%]##psl_" .. key, displayPct, 1.0, 10.0, "%.1f%%")
            if chPct then
                changed = true
                newVal = math.max(0.0, math.min(100.0, newPct)) / 100.0
            end
        end
        
        if changed then
            _setValue(self, key, newVal)
        end

    -- ── NUMBER ────────────────────────────────────────────────────────────── 
    elseif prop.type == T.NUMBER then
        local cur = math.floor(val or prop.min)
        local changed, newVal = imgui.inputInt(prop.name .. "##num_" .. key, cur, prop.increment, prop.increment * 5)
        if changed then
            newVal = math.max(prop.min, math.min(prop.max, newVal))
            _setValue(self, key, newVal)
        end

    -- ── COLOR ─────────────────────────────────────────────────────────────── 
    -- Store as {A,R,G,B} 0-255. Show as 3 stacked inputInt rows: R, G, B.
    elseif prop.type == T.COLOR then
        local c    = val or {255, 255, 255, 255}   -- {A,R,G,B}
        local newC = {c[1], c[2], c[3], c[4]}
        local anyChanged = false

        imgui.text(prop.name .. ":")

        local chR, nvR = imgui.inputInt("R##col_r_" .. key, newC[2], 1, 10)
        if chR then newC[2] = math.max(0, math.min(255, nvR)); anyChanged = true end

        local chG, nvG = imgui.inputInt("G##col_g_" .. key, newC[3], 1, 10)
        if chG then newC[3] = math.max(0, math.min(255, nvG)); anyChanged = true end

        local chB, nvB = imgui.inputInt("B##col_b_" .. key, newC[4], 1, 10)
        if chB then newC[4] = math.max(0, math.min(255, nvB)); anyChanged = true end

        if prop.allowAlpha then
            local chA, nvA = imgui.inputInt("A##col_a_" .. key, newC[1], 1, 10)
            if chA then newC[1] = math.max(0, math.min(255, nvA)); anyChanged = true end
        end

        if anyChanged then _setValue(self, key, newC) end

    -- ── VERTICAL SLIDER ───────────────────────────────────────────────────── 
    elseif prop.type == T.V_SLIDER then
        local cur = val or prop.min or 0
        local w = prop.width or 18
        local h = prop.height or 100
        
        local changed, newVal
        if type(cur) == "number" and cur % 1 == 0 then
            -- Assume integer if current value is whole number
            if type(imgui.vSliderInt) == "function" then
                changed, newVal = imgui.vSliderInt(prop.name .. "##vsl_" .. key, w, h, cur, prop.min or 0, prop.max or 100)
            end
        else
            if type(imgui.vSliderFloat) == "function" then
                changed, newVal = imgui.vSliderFloat(prop.name .. "##vsl_" .. key, w, h, cur, prop.minF or 0.0, prop.maxF or 1.0)
            end
        end
        
        if changed then _setValue(self, key, newVal) end

    -- ── ANGLE SLIDER ──────────────────────────────────────────────────────── 
    elseif prop.type == T.ANGLE_SLIDER then
        local cur = val or 0  -- radians
        if type(imgui.sliderAngle) == "function" then
            local changed, newVal = imgui.sliderAngle(prop.name .. "##ang_" .. key, cur, prop.minDeg or -360, prop.maxDeg or 360)
            if changed then _setValue(self, key, newVal) end
        else
            -- fallback
            local changed, newVal = imgui.inputFloat(prop.name .. " (rad)##ang_" .. key, cur, 0.1, 1.0, "%.3f")
            if changed then _setValue(self, key, newVal) end
        end

    -- ── IMAGE ───────────────────────────────────────────────────────────────
    elseif prop.type == T.IMAGE then
        local path = val or prop.path or ""
        
        if path ~= "" then
            -- Initialise image object cache on the instance
            if not self._imageObjects then self._imageObjects = {} end
            
            local entry = self._imageObjects[key]
            
            -- If path changed or not loaded, create/reload
            if not entry or entry.path ~= path then
                if entry and entry.handle then
                    pcall(function() entry.handle.release() end)
                end
                
                -- Verify file existence safely
                local exists = false
                local fCheck = pcall(function()
                    local f = luajava.newInstance("java.io.File", path)
                    exists = f:exists() and f:isFile()
                end)

                if exists then
                    local fObj = luajava.newInstance("java.io.File", path)
                    local size = fObj:length()
                    
                    local success, newObj = pcall(imgui.createImageObject)
                    if success and newObj then
                        local ok, err = pcall(function() newObj.loadImage(path) end)
                        if ok then
                            self._imageObjects[key] = { handle = newObj, path = path }
                            entry = self._imageObjects[key]
                            if player and player.addMessage then 
                                player.addMessage("§a[CryVigilance] Texture created! ID: " .. tostring(newObj.getId()))
                                player.addMessage("§7Size: " .. tostring(size) .. " bytes") 
                            end
                        else
                            imgui.textColored(255, 50, 50, 255, "Load Error: " .. tostring(err))
                            if player and player.addMessage then player.addMessage("§c[CryVigilance] loadImage failed: " .. tostring(err)) end
                        end
                    else
                        imgui.textColored(255, 50, 50, 255, "Image API Error")
                        if player and player.addMessage then player.addMessage("§c[CryVigilance] createImageObject failed") end
                    end
                else
                    imgui.textDisabled("[Image not found on disk]")
                    if type(imgui.textDisabled) == "function" then
                        imgui.textDisabled("  Path: " .. path)
                    end
                    if player and player.addMessage then player.addMessage("§e[CryVigilance] Image not found: " .. tostring(path)) end
                end
            end
            
            if entry and entry.handle then
                local w = prop.width or 100
                local h = prop.height or 100
                -- Draw a small label above to confirm we are attempting to render
                imgui.textDisabled("(Image: " .. key .. " " .. w .. "x" .. h .. ")")
                
                local drawOk, drawErr = pcall(imgui.image, entry.handle.getId(), w, h, 0, 0, 1, 1)
                if not drawOk then
                    imgui.textColored(255, 50, 50, 255, "Render Error: " .. tostring(drawErr))
                end
            end
        else
            imgui.textDisabled("[No image path set]")
        end

    -- ── SELECTOR ──────────────────────────────────────────────────────────── 
    -- imgui.listBox confirmed signature (farming.lua):
    --   listBox(label, currentValue, options) -> newValue
    -- "currentValue" with the string overload works in farming.lua, but the
    -- error "number expected, got string" shows the numeric-index overload is
    -- needed here.  We pass a 0-based index and convert the return back.
    elseif prop.type == T.SELECTOR then
        local opts    = prop.options
        local cur1    = val or 1                   -- 1-based (what we store)
        local cur0    = cur1 - 1                   -- 0-based (what listBox wants)

        imgui.text(prop.name .. ":")
        -- listBox(label, 0basedIndex, optionsTable) -> new 0basedIndex
        local new0 = imgui.listBox("##lbx_" .. key, cur0, opts)
        -- new0 may be a number (0-based index) or a string depending on binding version
        if type(new0) == "number" then
            local new1 = new0 + 1
            if new1 ~= cur1 then _setValue(self, key, new1) end
        elseif type(new0) == "string" and new0 ~= opts[cur1] then
            for i, opt in ipairs(opts) do
                if opt == new0 then _setValue(self, key, i); break end
            end
        end

    -- ── BUTTON ────────────────────────────────────────────────────────────── 
    elseif prop.type == T.BUTTON then
        if imgui.button(prop.name .. "##btn_" .. key) then
            if prop.action then
                local ok, err = pcall(prop.action)
                if not ok then
                    print("[CryVigilance] button error '" .. key .. "': " .. tostring(err))
                end
            end
        end
    end

    -- Inline button: render a small button on the same line after the widget
    if prop.inlineButton then
        imgui.sameLine()
        if imgui.button(prop.inlineButton.name .. "##ib_" .. key) then
            if prop.inlineButton.action then
                local ok, err = pcall(prop.inlineButton.action)
                if not ok then
                    print("[CryVigilance] inline button error '" .. key .. "': " .. tostring(err))
                end
            end
        end
    end

    -- Description shown as a dimmed line beneath the widget
    if prop.description and prop.description ~= "" then
        if type(imgui.textDisabled) == "function" then
            imgui.textDisabled("  " .. prop.description)
        end
    end
end

-- ============================================================================
-- Main render
-- ============================================================================

function CryVigilance:_render()
    if not self._open then return end

    -- Find color settings for theme and text elements
    local themeR, themeG, themeB = nil, nil, nil
    local textR, textG, textB, textA = nil, nil, nil, nil
    
    for _, prop in ipairs(self._props) do
        if prop.key == "hud_color" or prop.key == "theme_color" then
            local c = self._values[prop.key] or {255, 255, 255, 255}
            themeR, themeG, themeB = c[2]/255, c[3]/255, c[4]/255
        elseif prop.key == "text_color" then
            local c = self._values[prop.key] or {255, 255, 255, 255}
            textA, textR, textG, textB = c[1]/255, c[2]/255, c[3]/255, c[4]/255
        end
    end
    
    -- Fallback theme search (find the first color property if specific ones aren't present)
    if not themeR then
        for _, prop in ipairs(self._props) do
            if prop.type == CryVigilance.TYPES.COLOR then
                local c = self._values[prop.key] or {255, 255, 255, 255}
                themeR, themeG, themeB = c[2]/255, c[3]/255, c[4]/255
                break
            end
        end
    end

    -- Push style colors to tint the window to match the chosen colour settings.
    local stylesPushed = 0
    if type(imgui.pushStyleColor) == "function" then
        local function push(col, r, g, b, a)
            local ok = pcall(imgui.pushStyleColor, col, r, g, b, a)
            if ok then stylesPushed = stylesPushed + 1 end
        end
        
        -- Window Elements (using theme color)
        if themeR then
            push(imgui.Col_TitleBgActive or 6,    themeR,       themeG,       themeB,       1.0)
            push(imgui.Col_TitleBg or 5,          themeR * 0.7, themeG * 0.7, themeB * 0.7, 1.0)
            push(imgui.Col_TitleBgCollapsed or 7, themeR * 0.5, themeG * 0.5, themeB * 0.5, 0.9)
            push(imgui.Col_Header or 21,          themeR * 0.4, themeG * 0.4, themeB * 0.4, 0.6)
            push(imgui.Col_HeaderHovered or 22,   themeR * 0.6, themeG * 0.6, themeB * 0.6, 0.7)
        end
        
        -- Text Elements (using text color)
        if textR then
            push(imgui.Col_Text or 0, textR, textG, textB, textA or 1.0)
        end
    end

    imgui.setNextWindowSize(560, 460, 2)   -- 2 = FirstUseEver
    if imgui.begin(self.guiTitle) then
        local keyName = "RSHIFT"
        if self.openKey == 345 then keyName = "RCTRL"
        elseif self.openKey == 344 then keyName = "RSHIFT"
        elseif self.openKey == 340 then keyName = "LSHIFT"
        elseif self.openKey == 341 then keyName = "LCTRL"
        end

        -- Align text vertically with the button we are about to draw
        if type(imgui.alignTextToFramePadding) == "function" then
            imgui.alignTextToFramePadding()
        end
        
        imgui.text(keyName .. " to close   |   " .. self.guiTitle)
        
        -- Right align the close button
        if type(imgui.getWindowWidth) == "function" then
            local windowWidth = imgui.getWindowWidth()
            local buttonWidth = 40 -- Estimated width for "Close"
            local padding = 15
            imgui.sameLine(windowWidth - buttonWidth - padding)
        else
            imgui.sameLine()
        end

        if imgui.button("Close##cv_close") then
            self._open = false
        end
        imgui.separator()

        -- auto-select first category
        if not self._activeCategory and #self._categories > 0 then
            self._activeCategory = self._categories[1]
        end

        -- Left panel: category list
        local leftOk = pcall(imgui.beginChild, "##cats", 130, 0, true)
        if leftOk then
            for _, cat in ipairs(self._categories) do
                local sel = (self._activeCategory == cat)
                if imgui.selectable(cat .. "##cat_" .. cat, sel) then
                    self._activeCategory = cat
                end
            end
            imgui.spacing()
            imgui.separator()
            imgui.spacing()
            if imgui.button("Reset All##global_reset", -1) then
                self:resetToDefaults()
            end
            imgui.endChild()
        end

        imgui.sameLine()

        -- Right panel: properties
        local rightOk = pcall(imgui.beginChild, "##props", 0, 0, false)
        if rightOk then
            local currentCat = self._activeCategory
            local subOrder = {}
            local subSeen  = {}
            for _, prop in ipairs(self._props) do
                if prop.category == currentCat then
                    local sub = prop.subcategory
                    if not subSeen[sub] then
                        subSeen[sub] = true
                        table.insert(subOrder, sub)
                    end
                end
            end

            for _, sub in ipairs(subOrder) do
                if sub ~= "" then
                    if type(imgui.textDisabled) == "function" then
                        imgui.textDisabled("-- " .. sub .. " --")
                    else
                        imgui.text("-- " .. sub .. " --")
                    end
                    imgui.separator()
                end
                for _, prop in ipairs(self._props) do
                    if prop.category == currentCat and prop.subcategory == sub then
                        if _isVisible(self, prop) then
                            -- Individual property render is pcall-wrapped in _renderProperty
                            local status, err = pcall(_renderProperty, self, prop)
                            if not status then
                                imgui.textColored(255, 50, 50, 255, "Error: " .. tostring(err))
                            end
                        end
                    end
                end
                if type(imgui.spacing) == "function" then imgui.spacing() end
            end
            imgui.endChild()
        end
    end
    imgui.endBegin()

    -- Pop any style colors we pushed
    if stylesPushed > 0 and type(imgui.popStyleColor) == "function" then
        pcall(imgui.popStyleColor, stylesPushed)
    end
end

-- ============================================================================
return CryVigilance
