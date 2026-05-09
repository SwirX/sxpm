-- /lib/pkg/archive.lua
-- SXOS simple archive format (SXP1) processor.
-- This module streams the unpacking and construction of .sxpkg files.
-- Format:
-- SXP1\n
-- <filename>\n
-- <size_in_bytes>\n
-- <raw binary data>
-- ...

local archive = {}

-- Create an archive stream from a table of { path = filepath_string }
function archive.build(output_file, files, base_dir)
    local f_out = fs.open(output_file, "wb")
    if not f_out then return false, "Cannot open output file" end

    -- Write magic header
    f_out.write("SXP1\n")

    -- Add files
    for entry_path, local_filename in pairs(files) do
        local f_in = fs.open(fs.combine(base_dir, local_filename), "rb")
        if f_in then
            local data = f_in.readAll() or ""
            f_in.close()
            -- write metadata
            f_out.write(entry_path .. "\n")
            f_out.write(tostring(#data) .. "\n")
            -- write content directly
            for i = 1, #data do
                f_out.write(string.byte(string.sub(data, i, i)))
            end
        else
            f_out.close()
            return false, "Could not read local file " .. local_filename
        end
    end

    f_out.close()
    return true
end

-- Read line from binary stream
local function read_line(f_in)
    local chars = {}
    while true do
        local b = f_in.read()
        if not b then
            if #chars > 0 then break else return nil end
        end
        local char = string.char(b)
        if char == "\n" then break end
        table.insert(chars, char)
    end
    return table.concat(chars)
end

-- Extract an archive. Calls callback(filename, data) for every file.
function archive.extract(input_file, callback)
    local f_in = fs.open(input_file, "rb")
    if not f_in then return false, "Cannot open archive: " .. input_file end

    local magic = read_line(f_in)
    if magic ~= "SXP1" then
        f_in.close()
        return false, "Invalid archive format"
    end

    while true do
        local filename = read_line(f_in)
        if not filename or filename == "" then break end
        local size_str = read_line(f_in)
        if not size_str then break end
        local size = tonumber(size_str)
        if not size then
            f_in.close()
            return false, "Archive corrupted: size invalid"
        end

        -- read 'size' bytes
        local buf = {}
        for i = 1, size do
            local b = f_in.read()
            if not b then
                f_in.close()
                return false, "Archive corrupted: unexpected EOF"
            end
            table.insert(buf, string.char(b))
        end
        local data = table.concat(buf)

        local ok, err = pcall(callback, filename, data)
        if not ok then
            f_in.close()
            return false, "Extraction callback err: " .. tostring(err)
        end
    end

    f_in.close()
    return true
end

return archive
