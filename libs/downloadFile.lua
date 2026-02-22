local files = require("libs/files")
local downloadFile = {}

--- Downloads a file from a URL and saves it to a local path.
-- @param url string The URL to download from.
-- @param path string The local file path to save to.
-- @param onComplete function? (optional) Callback function(success, message) called after download finishes.
function downloadFile.download(url, path, onComplete)
    if not (http and http.get_async_with_headers_callback) then
        if onComplete then onComplete(false, "HTTP library not available") end
        return
    end

    -- Ensure directory exists (handles both / and \ separators)
    local dirPath = path:match("(.*)[/\\]")
    if dirPath and dirPath ~= "" then
        local dir = luajava.newInstance("java.io.File", dirPath)
        if not dir:exists() then dir:mkdirs() end
    end

    local headers = { ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) HypixelCry/1.0" }
    
    http.get_async_with_headers_callback(url, headers, function(response, error)
        if response and not error then
            -- Force overwrite logic
            files.deleteFile(path)
            
            local ok = files.writeBinaryFile(path, response)
            if ok then
                if onComplete then onComplete(true, path) end
            else
                if onComplete then onComplete(false, "Failed to write file to disk") end
            end
        else
            if onComplete then onComplete(false, "Download failed: " .. tostring(error)) end
        end
    end)
end

return downloadFile
