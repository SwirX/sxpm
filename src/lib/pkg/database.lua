-- /lib/pkg/database.lua
-- Local package database for SXPM.
-- Tracks which packages are installed, their versions, and install paths.
-- Stored in /var/lib/sxpm/installed.db as a serialized Lua table.

local database = {}

local DB_PATH = "/var/lib/sxpm/installed.db"
local REPO_CONFIG_PATH = "/etc/sxpm/repos.lua"

local db_cache = nil

local function ensure_dirs()
    for _, dir in ipairs({ "/var/lib/sxpm", "/var/cache/sxpm", "/etc/sxpm" }) do
        if not fs.exists(dir) then fs.makeDir(dir) end
    end
end

local function load_db()
    if db_cache then return db_cache end
    ensure_dirs()
    if fs.exists(DB_PATH) then
        local handle = fs.open(DB_PATH, "r")
        if handle then
            local raw = handle.readAll()
            handle.close()
            local parsed = textutils.unserialize(raw)
            db_cache = type(parsed) == "table" and parsed or {}
            return db_cache
        end
    end
    db_cache = {}
    return db_cache
end

local function save_db()
    ensure_dirs()
    local handle = fs.open(DB_PATH, "w")
    if handle then
        handle.write(textutils.serialize(db_cache))
        handle.close()
    end
end

-- Record a newly installed package.
-- pkg_manifest: the validated manifest table from manifest.lua
function database.record_install(pkg_manifest)
    local db = load_db()
    db[pkg_manifest.name] = {
        name         = pkg_manifest.name,
        version      = pkg_manifest.version,
        package_type = pkg_manifest.package_type or "application",
        files        = pkg_manifest.files or {},
        binaries     = pkg_manifest.binaries or {},
        provides     = pkg_manifest.provides or {},
        dependencies = pkg_manifest.dependencies or {},
        services     = pkg_manifest.services or {},
        channel      = pkg_manifest.channel or "stable",
        installed_at = os.time(),
    }
    save_db()
end

-- Remove a package record from the database.
function database.record_remove(package_name)
    local db = load_db()
    db[package_name] = nil
    save_db()
end

-- Check if a package is installed. Returns the record or nil.
function database.get(package_name)
    return load_db()[package_name]
end

-- Find a package that matches exactly or provides the given capability.
function database.find_provider(dep_name)
    local db = load_db()
    if db[dep_name] then return db[dep_name] end
    for name, record in pairs(db) do
        if record.provides then
            for _, prov in ipairs(record.provides) do
                if prov == dep_name then return record end
            end
        end
    end
    return nil
end

-- Get packages that depend on the given package.
function database.get_reverse_dependencies(package_name)
    local db = load_db()
    local rev = {}
    for name, record in pairs(db) do
        for _, dep_decl in ipairs(record.dependencies or {}) do
            local dep_name = string.match(dep_decl, "^([%S]+)")
            if dep_name == package_name then
                table.insert(rev, name)
            end
        end
    end
    return rev
end

-- Return all installed package records.
function database.list_all()
    return load_db()
end

-- Load repository list from /etc/sxpm/repos.lua.
-- Returns a list of { name, url, channel } tables.
function database.load_repos()
    if not fs.exists(REPO_CONFIG_PATH) then
        return {
            { name = "stable", url = "https://raw.githubusercontent.com/SwirX/sxpm-repo/stable/index.json", channel = "stable" }
        }
    end
    local ok, result = pcall(dofile, REPO_CONFIG_PATH)
    if ok and type(result) == "table" then return result end
    return {}
end

function database.save_repos(repos)
    ensure_dirs()
    local f = fs.open(REPO_CONFIG_PATH, "w")
    if f then
        f.write("return " .. textutils.serialize(repos))
        f.close()
    end
end

return database
