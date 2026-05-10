-- /lib/pkg/manifest.lua
-- Package manifest parsing and validation for SXPM.
-- A manifest is a Lua file that returns a structured table describing
-- a package: name, version, dependencies, binaries, install location.
--
-- Canonical manifest format:
--
--   return {
--       name         = "music",
--       version      = "1.2.0",
--       description  = "SX-Music player",
--       author       = "SwirX",
--       license      = "MIT",
--       channel      = "stable",    -- "stable" | "testing" | "nightly"
--       dependencies = {
--           "sxui >=1.0.0"
--       },
--       files        = {
--           { path = "/usr/bin/music.lua", source = "music/bin.lua", executable = true },
--           { path = "/usr/lib/music/core.lua", source = "music/core.lua" }
--       },
--   }

local manifest = {}

-- Parse a version string "major.minor.patch" into comparable components.
function manifest.parse_version(version_str)
    if type(version_str) ~= "string" then return nil end
    local major, minor, patch = string.match(version_str, "^(%d+)%.(%d+)%.?(%d*)")
    if not major then return nil end
    return {
        major = tonumber(major) or 0,
        minor = tonumber(minor) or 0,
        patch = tonumber(patch) or 0,
        raw   = version_str,
    }
end

-- Compare two parsed version tables. Returns -1, 0, or 1.
function manifest.compare_versions(version_a, version_b)
    for _, field in ipairs({ "major", "minor", "patch" }) do
        if version_a[field] < version_b[field] then return -1 end
        if version_a[field] > version_b[field] then return 1 end
    end
    return 0
end

-- Parse a dependency declaration like "sxui >=1.0.0" into a table.
-- Returns { name, operator, version } or nil on bad format.
function manifest.parse_dependency(dep_str)
    local name, operator, version_str = string.match(dep_str, "^(%S+)%s*([><=!]+)%s*(%S+)$")
    if not name then
        -- Bare name with no version constraint.
        name = string.match(dep_str, "^(%S+)$")
        if not name then return nil end
        return { name = name, operator = nil, version = nil }
    end
    return {
        name     = name,
        operator = operator,
        version  = manifest.parse_version(version_str),
    }
end

function manifest.validate(pkg)
    if type(pkg) ~= "table" then return false, "manifest must be a table" end
    if type(pkg.name) ~= "string" or #pkg.name == 0 then
        return false, "manifest.name is required"
    end
    if type(pkg.version) ~= "string" then
        return false, "manifest.version is required"
    end
    if not manifest.parse_version(pkg.version) then
        return false, "manifest.version is not valid semver: " .. pkg.version
    end

    local p_type = pkg.package_type
    local valid_types = { system = true, library = true, application = true, service = true, theme = true, meta = true }
    if type(p_type) ~= "string" or not valid_types[p_type] then
        return false, "manifest.package_type must be explicit (system, library, application, service, theme, meta)"
    end

    return true
end

-- Load and parse a manifest file from disk.
-- Returns the manifest table or nil + error string.
function manifest.load_file(path)
    if not fs.exists(path) then
        return nil, "manifest not found: " .. path
    end
    local ok, result = pcall(dofile, path)
    if not ok then
        return nil, "manifest load error: " .. tostring(result)
    end
    if type(result) ~= "table" then
        return nil, "manifest did not return a table"
    end
    local valid, err = manifest.validate(result)
    if not valid then return nil, err end
    return result
end

return manifest
