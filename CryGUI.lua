-- =============================================================================
-- CryGUI.lua  -  Script Manager
-- Rewritten to use the CryVigilance library.
-- Supports mouse interaction and checkbox-based script toggling.
-- RCTRL to toggle GUI.
-- =============================================================================

local CryVigilance = require("CryVigilance/index")

local cfg = CryVigilance.new(
    "CryGUI",
    "CryGUI - Script Manager",
    "config/hypixelcry/scripts/config/CryGUI.toml",
    345  -- RCTRL (GLFW_KEY_RIGHT_CONTROL)
)

local File = luajava.bindClass("java.io.File")
local Files = luajava.bindClass("java.nio.file.Files")
local Array = luajava.bindClass("java.lang.reflect.Array")
local StandardCharsets = luajava.bindClass("java.nio.charset.StandardCharsets")
local Paths = luajava.bindClass("java.nio.file.Paths")

local files = {}

-- ── File Utilities (Retained for backwards compatibility) ───────────────────

function files.getFiles(directory, silent)
    local filesList = {}
    local dir = luajava.newInstance("java.io.File", directory)

    if dir:exists() and dir:isDirectory() then
        local filesArray = dir:listFiles()
        
        if filesArray ~= nil then
            local length = Array:getLength(filesArray)
            for i = 0, length - 1 do
                local file = Array:get(filesArray, i)
                if not file:isDirectory() then
                    local name = file:getName()
                    table.insert(filesList, name)
                    if not silent then
                        player.addMessage(name)
                    end
                end
            end
        end
    else
        if not silent then
            player.addMessage("Directory does not exist or is not a directory: " .. directory)
        end
    end

    return filesList
end

function files.getDirectories(directory)
    local dirList = {}
    local dir = luajava.newInstance("java.io.File", directory)
    if dir:exists() and dir:isDirectory() then
        local filesArray = dir:listFiles()
        if filesArray ~= nil then
            local length = Array:getLength(filesArray)
            for i = 0, length - 1 do
                local file = Array:get(filesArray, i)
                if file:isDirectory() then
                    local name = file:getName()
                    table.insert(dirList, name)
                    player.addMessage(name)
                end
            end
        end
    else
        player.addMessage("Directory does not exist or is not a directory: " .. directory)
    end
    return dirList
end

function files.readFile(file)
    local f = io.open(file, "r")
    if not f then
        player.addMessage("Error opening file: " .. (err or "unknown"))
        return nil
    end
    local content = f:read("*a")
    f:close()
    return content
end

function files.writeFile(file, text)
    local f, err = io.open(file, "w")
    if not f then
        player.addMessage("Error opening file for writing: " .. (err or "unknown"))
        return false
    end
    f:write(text)
    f:close()
    return true
end

function files.deleteFile(filePath)
    local file = luajava.newInstance("java.io.File", filePath)
    if file:exists() and file:isFile() then
        return file:delete()
    else
        player.addMessage("File does not exist or is not a file: " .. filePath)
        return false
    end
end

function files.deleteDirectory(filePath)
    local file = luajava.newInstance("java.io.File", filePath)
    if file:exists() and file:isDirectory() then
        return file:delete()
    else
        player.addMessage("Directory does not exist or is not a directory: " .. filePath)
        return false
    end
end

function files.deleteDirectoryRecursive(directoryPath)
    local dir = luajava.newInstance("java.io.File", directoryPath)
    if not dir:exists() then
        player.addMessage("Directory does not exist: " .. directoryPath)
        return false
    end

    local function deleteRecursively(fileObj)
        if fileObj:isDirectory() then
            local filesArray = fileObj:listFiles()
            if filesArray ~= nil then
                local length = Array:getLength(filesArray)
                for i = 0, length - 1 do
                    local childFile = Array:get(filesArray, i)
                    if not deleteRecursively(childFile) then
                        return false
                    end
                end
            end
        end
        return fileObj:delete()
    end

    return deleteRecursively(dir)
end

-- Scan for scripts and register them as checkboxes
local scriptsPath = "config/hypixelcry/scripts"
local scriptsDir = luajava.newInstance("java.io.File", scriptsPath)

-- Helper: check if a script file contains a CryVigilance require
local function scriptUsesCryVigilance(filePath)
    local f = io.open(filePath, "r")
    if not f then return false end
    local content = f:read("*a")
    f:close()
    return content and content:find('require%s*%(%s*"CryVigilance/index"%s*%)') ~= nil
end

-- Helper: open the CryVigilance config for a given script ID via file signal
local signalDir = "config/hypixelcry/scripts/config/.crygui_signals/"

local function openVigilanceConfig(scriptId)
    -- Scan the signal directory for .registered files to find the matching module
    local dir = luajava.newInstance("java.io.File", signalDir)
    if dir:exists() and dir:isDirectory() then
        local filesArray = dir:listFiles()
        if filesArray then
            local len = Array:getLength(filesArray)
            for i = 0, len - 1 do
                local file = Array:get(filesArray, i)
                local fname = file:getName()
                if fname:match("%.registered$") then
                    local modName = fname:gsub("%.registered$", "")
                    local modLower = modName:lower()
                    local idLower  = scriptId:lower()
                    if modLower == idLower 
                       or modLower:find(idLower, 1, true) 
                       or idLower:find(modLower, 1, true) then
                        -- Write the open signal
                        CryVigilance.requestOpen(modName)
                        player.addMessage("§a[CryGUI] Opening config for: " .. modName)
                        return
                    end
                end
            end
        end
    end
    player.addMessage("§c[CryGUI] No active config found for '" .. scriptId .. "'. Make sure the script is loaded first!")
end

if scriptsDir:exists() and scriptsDir:isDirectory() then
    local contents = scriptsDir:listFiles()
    if contents then
        local len = Array:getLength(contents)
        for i = 0, len - 1 do
            local file = Array:get(contents, i)
            local name = file:getName()
            
            local scriptId = name:gsub("%.lua$", "")
            
            -- Add every .lua file except self
            if not file:isDirectory() and name:match("%.lua$") 
               and scriptId ~= currentScriptName then
                
                -- Check if the script file uses CryVigilance
                local fullPath = scriptsPath .. "/" .. name
                local hasVigilance = scriptUsesCryVigilance(fullPath)
                
                local propDef = {
                    type        = CryVigilance.TYPES.CHECKBOX,
                    key         = "run_" .. scriptId,
                    name        = name,
                    description = "Toggle loading of " .. name,
                    category    = "Scripts",
                    default     = false
                }
                
                -- If script uses CryVigilance, add an inline configure button
                if hasVigilance then
                    propDef.inlineButton = {
                        name   = "Configure",
                        action = (function(id)
                            return function() openVigilanceConfig(id) end
                        end)(scriptId)
                    }
                end
                
                cfg:addProperty(propDef)
                
                -- When checked, send the load/unload command
                cfg:onChanged("run_" .. scriptId, function(enabled)
                    if enabled then
                        player.sendCommand("/lua load " .. scriptId)
                    else
                        player.sendCommand("/lua unload " .. scriptId)
                    end
                end)
            end
        end
    end
end

-- Initialize the GUI (handles events, loading, and rendering)
cfg:initialize()

-- Return the files utility table for other scripts
return files