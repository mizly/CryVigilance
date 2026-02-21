-- =============================================================================
-- CryVigilance example.lua  –  shows every supported input type
-- Open/close the GUI with RSHIFT (configurable via the 4th arg to CryVigilance.new)
-- =============================================================================

local CryVigilance = require("CryVigilance/index")

-- ── Create a config instance ────────────────────────────────────────────────
-- CryVigilance.new(moduleName, windowTitle, tomlPath, openKey)
local cfg = CryVigilance.new(
    "ExampleModule",                                                          -- module name
    "CryVigilance - Example Settings",                                                       -- ImGui window title
    nil,                                                                      -- Use default path (scripts/config/)
    344                                                                       -- RSHIFT to open (GLFW key 344)
)

-- ── SWITCH ──────────────────────────────────────────────────────────────────
-- A toggleable on/off switch rendered as a checkbox with a label to its right.
cfg:addProperty({
    type        = CryVigilance.TYPES.SWITCH,
    key         = "enabled",
    name        = "Enable Module",
    description = "Master toggle for the entire module.",
    category    = "General",
    subcategory = "Main",
    default     = false,
})

-- ── CHECKBOX ────────────────────────────────────────────────────────────────
-- Functionally identical to SWITCH but the label is rendered inline (left side).
-- Note: Checkbox will be hidden when 'enabled' is false (dependency demo below).
cfg:addProperty({
    type        = CryVigilance.TYPES.CHECKBOX,
    key         = "show_debug",
    name        = "Show Debug Info",
    description = "Print debug messages to chat.",
    category    = "General",
    subcategory = "Main",
    default     = false,
})

-- ── TEXT ────────────────────────────────────────────────────────────────────
-- Single-line text input.
cfg:addProperty({
    type        = CryVigilance.TYPES.TEXT,
    key         = "welcome_msg",
    name        = "Welcome Message",
    description = "Text displayed on login.",
    category    = "General",
    subcategory = "Messages",
    default     = "Hello, world!",
    placeholder = "Enter message...",
    -- triggerActionOnInitialization = false  -- uncomment to skip listener on load
})

-- ── TEXT (protected / password) ─────────────────────────────────────────────
-- Same as TEXT but input is masked with dots.
cfg:addProperty({
    type        = CryVigilance.TYPES.TEXT,
    key         = "api_key",
    name        = "API Key",
    description = "Your secret key (hidden while typing).",
    category    = "General",
    subcategory = "Messages",
    default     = "",
    protected   = true,
})

-- ── PARAGRAPH ───────────────────────────────────────────────────────────────
-- Multiline text input box.
cfg:addProperty({
    type        = CryVigilance.TYPES.PARAGRAPH,
    key         = "notes",
    name        = "Notes",
    description = "Freeform multiline notes.",
    category    = "General",
    subcategory = "Messages",
    default     = "Line 1\nLine 2",
})

-- ── SLIDER (integer) ────────────────────────────────────────────────────────
-- Drag-bar that yields an integer in [min, max].
cfg:addProperty({
    type        = CryVigilance.TYPES.SLIDER,
    key         = "delay_ticks",
    name        = "Delay (ticks)",
    description = "How many ticks to wait before acting.",
    category    = "Timing",
    subcategory = "Thresholds",
    default     = 5,
    min         = 1,
    max         = 100,
})

-- ── DECIMAL SLIDER ──────────────────────────────────────────────────────────
-- Slider that yields a float.  decimalPlaces controls the display format.
cfg:addProperty({
    type          = CryVigilance.TYPES.DECIMAL_SLIDER,
    key           = "speed_mult",
    name          = "Speed Multiplier",
    description   = "Floating-point speed factor.",
    category      = "Timing",
    subcategory   = "Thresholds",
    default       = 1.0,
    minF          = 0.1,
    maxF          = 5.0,
    decimalPlaces = 2,
})

-- ── PERCENT SLIDER ──────────────────────────────────────────────────────────
-- Slider fixed to 0.0 – 1.0, displayed as 0 % – 100 %.
cfg:addProperty({
    type        = CryVigilance.TYPES.PERCENT_SLIDER,
    key         = "volume",
    name        = "Volume",
    description = "Audio volume as a percentage.",
    category    = "Timing",
    subcategory = "Thresholds",
    default     = 0.75,
})

-- ── NUMBER (integer input box) ───────────────────────────────────────────────
-- Numeric text field with optional up/down arrows; clamped to [min, max].
cfg:addProperty({
    type        = CryVigilance.TYPES.NUMBER,
    key         = "max_retries",
    name        = "Max Retries",
    description = "Maximum number of retry attempts.",
    category    = "Timing",
    subcategory = "Limits",
    default     = 3,
    min         = 0,
    max         = 20,
})

-- ── COLOR ────────────────────────────────────────────────────────────────────
-- RGBA colour picker (stored as { A, R, G, B } 0-255 integers).
-- Set allowAlpha = false to hide the alpha channel.
cfg:addProperty({
    type        = CryVigilance.TYPES.COLOR,
    key         = "hud_color",
    name        = "HUD Colour",
    description = "Primary colour used for the on-screen display.",
    category    = "Appearance",
    subcategory = "Colours",
    default     = { 255, 29, 162, 219 },   -- { A, R, G, B }
    allowAlpha  = true,
})

cfg:addProperty({
    type        = CryVigilance.TYPES.COLOR,
    key         = "highlight_color",
    name        = "Highlight Colour",
    description = "No alpha channel exposed.",
    category    = "Appearance",
    subcategory = "Colours",
    default     = { 255, 255, 30, 30 },
    allowAlpha  = false,
})

-- ── SELECTOR (dropdown / combo) ─────────────────────────────────────────────
-- Stores a 1-based integer index into the options list.
cfg:addProperty({
    type        = CryVigilance.TYPES.SELECTOR,
    key         = "mode",
    name        = "Mode",
    description = "Select the operating mode.",
    category    = "Appearance",
    subcategory = "Style",
    default     = 1,   -- index 1 = "Auto"
    options     = { "Auto", "Manual", "Off" },
})

-- ── BUTTON ──────────────────────────────────────────────────────────────────
-- Clickable button that fires `action` when pressed (no value is stored).
cfg:addProperty({
    type        = CryVigilance.TYPES.BUTTON,
    key         = "reset_btn",
    name        = "Reset to Defaults",
    description = "Resets all settings to their default values.",
    category    = "Appearance",
    subcategory = "Style",
    action      = function()
        -- manually reset a couple of values as a demo
        cfg:set("delay_ticks", 5)
        cfg:set("volume", 0.75)
        player.addMessage("§a[Example] Settings reset to defaults.")
    end,
})

-- ── Dependency example ───────────────────────────────────────────────────────
-- 'show_debug' will only be visible when 'enabled' is ON.
cfg:addDependency("show_debug", "enabled")

-- ── Listener examples ────────────────────────────────────────────────────────
cfg:onChanged("enabled", function(newValue)
    player.addMessage("§b[Example] Module enabled: " .. tostring(newValue))
end)

cfg:onChanged("welcome_msg", function(newValue)
    player.addMessage("§b[Example] Welcome message changed to: " .. tostring(newValue))
end)

cfg:onChanged("mode", function(newIdx)
    local opts = { "Auto", "Manual", "Off" }
    player.addMessage("§b[Example] Mode changed to: " .. (opts[newIdx] or "?"))
end)

-- ── Initialize ───────────────────────────────────────────────────────────────
-- Must be called after all addProperty() / onChanged() / addDependency() calls.
-- Loads saved values from TOML, registers ImGui + key event hooks.
cfg:initialize()

-- ── Accessing values from other scripts ─────────────────────────────────────
-- After initialize(), you can read values anywhere with cfg:get(key).
-- Example (in another script that requires this file):
--
--   local Settings = require("CryVigilance/example")
--   if Settings:get("enabled") then
--       -- module is toggled on
--   end
--   local color = Settings:get("hud_color")  -- { A, R, G, B } table
return cfg
