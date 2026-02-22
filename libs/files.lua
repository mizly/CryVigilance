local File = luajava.bindClass("java.io.File")
local Files = luajava.bindClass("java.nio.file.Files")
local Array = luajava.bindClass("java.lang.reflect.Array")
local StandardCharsets = luajava.bindClass("java.nio.charset.StandardCharsets")
local Paths = luajava.bindClass("java.nio.file.Paths")
local files = {}

function files.getFiles(directory)
	local filesList = {}
	local dir = luajava.newInstance("java.io.File", directory)

	if dir:exists() and dir:isDirectory() then
		local filesArray = dir:listFiles()
		
		if filesArray ~= nil then
			local length = Array:getLength(filesArray)
			for i = 0, length - 1 do
				local file = Array:get(filesArray, i)
				table.insert(filesList, file:getName())
			end
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
                    table.insert(dirList, file:getName())
                end
            end
        end
    end
    return dirList
end

function files.readFile(file)
    local f = io.open(file, "r")
    if not f then
        print("Error opening file: " .. (err or "unknown"))
        return nil
    end
    local content = f:read("*a")
    f:close()
    return content
end

--- Writes plain text to a file using "w" mode.
function files.writeFile(file, text)
    local f, err = io.open(file, "w")
    if not f then
        print("Error opening file for writing: " .. (err or "unknown"))
        return false
    end
    f:write(text)
    f:close()
    return true
end

--- Writes binary data to a file using "wb" mode.
-- Handles both Lua strings and tables (byte arrays).
function files.writeBinaryFile(file, data)
    local f, err = io.open(file, "wb")
    if not f then
        print("Error opening file for binary writing: " .. (err or "unknown"))
        return false
    end

    if type(data) == "table" then
        -- Handle byte array (table of numbers)
        local parts = {}
        for i = 1, #data do
            local b = data[i]
            -- Convert signed byte (-128 to 127) to unsigned (0-255) if necessary
            if type(b) == "number" then
                if b < 0 then b = b + 256 end
                table.insert(parts, string.char(b))
            end
            
            -- Write in chunks of 4096 bytes to be memory efficient
            if i % 4096 == 0 then
                f:write(table.concat(parts))
                parts = {}
            end
        end
        f:write(table.concat(parts))
    else
        -- Handle string data
        f:write(data)
    end

    f:close()
    return true
end

function files.deleteFile(filePath)
    local file = luajava.newInstance("java.io.File", filePath)
    if file:exists() and file:isFile() then
        return file:delete()
    else
        print("File does not exist or is not a file: " .. filePath)
        return false
    end
end

function files.deleteDirectory(filePath)
    local file = luajava.newInstance("java.io.File", filePath)
    if file:exists() and file:isDirectory() then
        return file:delete()
    else
        print("Directory does not exist or is not a directory: " .. filePath)
        return false
    end
end

function files.deleteDirectoryRecursive(directoryPath)
    local dir = luajava.newInstance("java.io.File", directoryPath)
    if not dir:exists() then
        print("Directory does not exist: " .. directoryPath)
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

return files