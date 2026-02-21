-- =============================================================================
-- CryVigilance/index.lua  -  Lua port of the CryVigilance config library
-- Renders a settings GUI via ImGui and persists values to a TOML file.
-- =============================================================================
local luajava_ok, File = pcall(function() return luajava.bindClass("java.io.File") end)

local CryVigilance = {}
CryVigilance.__index = CryVigilance

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
    end)
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
    -- Use inputInt as the confirmed integer input widget (sliderInt may not exist)
    elseif prop.type == T.SLIDER then
        local cur = math.floor(val or prop.min)
        local label = prop.name .. " [" .. prop.min .. "-" .. prop.max .. "]" .. "##sl_" .. key
        local changed, newVal = imgui.inputInt(label, cur, prop.increment, prop.increment * 5)
        if changed then
            newVal = math.max(prop.min, math.min(prop.max, newVal))
            _setValue(self, key, newVal)
        end

    -- ── DECIMAL SLIDER ────────────────────────────────────────────────────── 
    elseif prop.type == T.DECIMAL_SLIDER then
        local cur = val or prop.minF
        local fmt = "%." .. prop.decimalPlaces .. "f"
        local label = prop.name .. " [" .. string.format(fmt, prop.minF) .. "-" .. string.format(fmt, prop.maxF) .. "]##dsl_" .. key
        local changed, newVal = imgui.inputFloat(label, cur, 0.1, 1.0, fmt)
        if changed then
            newVal = math.max(prop.minF, math.min(prop.maxF, newVal))
            _setValue(self, key, newVal)
        end

    -- ── PERCENT SLIDER ────────────────────────────────────────────────────── 
    elseif prop.type == T.PERCENT_SLIDER then
        local cur = val or 0.0
        -- display as 0-100, store as 0.0-1.0
        local displayPct = cur * 100
        local changed, newPct = imgui.inputFloat(prop.name .. " [0-100%%]##psl_" .. key, displayPct, 1.0, 10.0, "%.1f%%")
        if changed then
            local clamped = math.max(0.0, math.min(100.0, newPct))
            _setValue(self, key, clamped / 100.0)
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

    -- Find the first COLOR property and use it to tint the window title bar.
    local themeR, themeG, themeB = nil, nil, nil
    for _, prop in ipairs(self._props) do
        if prop.type == CryVigilance.TYPES.COLOR then
            local c = self._values[prop.key] or {255, 255, 255, 255}  -- {A,R,G,B}
            themeR = c[2] / 255
            themeG = c[3] / 255
            themeB = c[4] / 255
            break
        end
    end

    -- Push style colors to tint the window to match the chosen HUD colour.
    -- ImGuiCol constants (standard Dear ImGui ordinals):
    --   TitleBg=5, TitleBgActive=6, TitleBgCollapsed=7, Header=21
    local stylesPushed = 0
    if themeR and type(imgui.pushStyleColor) == "function" then
        local function push(col, r, g, b, a)
            local ok = pcall(imgui.pushStyleColor, col, r, g, b, a)
            if ok then stylesPushed = stylesPushed + 1 end
        end
        push(6,  themeR,       themeG,       themeB,       1.0)  -- TitleBgActive
        push(5,  themeR * 0.7, themeG * 0.7, themeB * 0.7, 1.0)  -- TitleBg
        push(7,  themeR * 0.5, themeG * 0.5, themeB * 0.5, 0.9)  -- TitleBgCollapsed
        push(21, themeR * 0.4, themeG * 0.4, themeB * 0.4, 0.6)  -- Header (category selected)
        push(22, themeR * 0.6, themeG * 0.6, themeB * 0.6, 0.7)  -- HeaderHovered
    end

    imgui.setNextWindowSize(560, 460, 2)   -- 2 = FirstUseEver
    if imgui.begin(self.guiTitle) then

        -- Safety wrapper for the internal render logic.
        -- If this fails, we still call endBegin() to avoid crashing the game.
        local status, err = pcall(function()
            imgui.text("RSHIFT to close   |   " .. self.guiTitle)
            imgui.separator()

            -- auto-select first category
            if not self._activeCategory and #self._categories > 0 then
                self._activeCategory = self._categories[1]
            end

            -- Left panel: category list
            imgui.beginChild("##cats", 130, 0, true)
            for _, cat in ipairs(self._categories) do
                local sel = (self._activeCategory == cat)
                if imgui.selectable(cat .. "##cat_" .. cat, sel) then
                    self._activeCategory = cat
                end
            end

            -- Reset button at bottom of sidebar
            imgui.spacing()
            imgui.separator()
            imgui.spacing()
            if imgui.button("Reset All##global_reset", -1) then
                self:resetToDefaults()
            end

            imgui.endChild()

            imgui.sameLine()

            -- Right panel: properties
            imgui.beginChild("##props", 0, 0, false)
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
                            -- Individual property render is also pcall-wrapped in _renderProperty
                            _renderProperty(self, prop)
                        end
                    end
                end
                if type(imgui.spacing) == "function" then imgui.spacing() end
            end

            imgui.endChild()
        end)

        if not status then
            imgui.textColored(255, 50, 50, 255, "GUI Render Error: " .. tostring(err))
        end

        imgui.endBegin()
    end

    -- Pop any style colors we pushed
    if stylesPushed > 0 and type(imgui.popStyleColor) == "function" then
        pcall(imgui.popStyleColor, stylesPushed)
    end
end

-- ============================================================================
return CryVigilance
