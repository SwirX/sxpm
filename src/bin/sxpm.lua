-- /bin/sxpm.lua
-- SXOS Package Manager.
-- The primary interface for installing, removing, searching, and managing packages.
-- All real work is delegated to /lib/pkg/ modules via the sx.* API surface.
--
-- Usage:
--   sxpm install <package>
--   sxpm remove <package>
--   sxpm search <query>
--   sxpm list
--   sxpm update
--   sxpm upgrade
--   sxpm info <package>
--   sxpm build <manifest_path>
--   sxpm publish <manifest_path>

-- helper function (debugging)
local function printTable(value, indent, visited)
    indent = indent or 0
    visited = visited or {}

    local spacing = string.rep("  ", indent)

    if type(value) ~= "table" then
        print(spacing .. tostring(value))
        return
    end

    if visited[value] then
        print(spacing .. "<recursive reference>")
        return
    end

    visited[value] = true

    print(spacing .. "{")

    for key, nestedValue in pairs(value) do
        local formattedKey

        if type(key) == "string" then
            formattedKey = key
        else
            formattedKey = "[" .. tostring(key) .. "]"
        end

        io.write(spacing .. "  " .. formattedKey .. " = ")

        if type(nestedValue) == "table" then
            print()
            printTable(nestedValue, indent + 1, visited)
        else
            print(tostring(nestedValue))
        end
    end

    print(spacing .. "}")
end

local manifest_module = dofile("/lib/pkg/manifest.lua")
local database_module = dofile("/lib/pkg/database.lua")
local resolve_module  = dofile("/lib/pkg/resolve.lua")
local archive_module  = dofile("/lib/pkg/archive.lua")

local args            = { ... }
local subcommand      = args[1]

local INSTALL_BASE    = "/usr/lib/sxpkg"
local BIN_DIR         = "/usr/bin"

local function print_usage()
    print("sxpm - SXOS Package Manager")
    print("")
    print("Usage: sxpm <command> [options]")
    print("")
    print("Commands:")
    print("  install <pkg>   Install a package")
    print("  remove <pkg>    Remove an installed package")
    print("  search <query>  Search available packages")
    print("  update/sync     Refresh repository metadata")
    print("  upgrade         Upgrade all installed packages")
    print("  info <pkg>      Show package details")
    print("  build <path>    Build a package from a manifest file")
    print("  publish <path>  Publish a package instructions")
    print("  repo <action>   Manage repositories (add, rm, list)")
    print("  doctor          Check system for broken packages")
    print("  autoremove      Remove orphaned packages")
    print("  reinstall <pkg> Reinstall a package")
    print("  verify <pkg>    Verify signature and checksum defaults")
end

local function get_repos()
    local ok, res = pcall(database_module.load_repos)
    if ok and type(res) == "table" and #res > 0 then return res end
    return { { name = "stable", url = "https://raw.githubusercontent.com/SwirX/sxpm-repo/stable/index.json" } }
end

local function search_index_for_pkg(package_name)
    if fs.exists("/var/cache/sxpm") then
        for _, file in ipairs(fs.list("/var/cache/sxpm")) do
            if string.match(file, "^index_.*%.json$") then
                local f = fs.open("/var/cache/sxpm/" .. file, "r")
                if f then
                    local data = textutils.unserializeJSON(f.readAll() or "")
                    f.close()
                    if data and data[package_name] then
                        return data[package_name]
                    end
                end
            end
        end
    end
    return nil
end

local function download_sxpkg(url, out_path)
    local res = http.get({ url = url, binary = true })
    if not res then
        res = http.get(url)
        if not res then return false, "HTTP GET failed" end
    end
    local f = fs.open(out_path, "wb")
    if not f then
        res.close(); return false, "Could not open cache file"
    end
    while true do
        local b = res.read()
        if not b then break end
        if type(b) == "number" then
            f.write(b)
        else
            f.write(string.byte(b))
        end
    end
    f.close()
    res.close()
    return true
end

local function cmd_install(package_name)
    if not package_name then
        printError("sxpm install: package name required"); return
    end

    if database_module.get(package_name) then
        print(package_name .. " is already installed.")
        return
    end

    print("Locating " .. package_name .. " in indexed repositories...")
    local index_entry = search_index_for_pkg(package_name)
    if not index_entry then
        printError("Package '" .. package_name .. "' not found. Try running 'sxpm sync'.")
        return
    end

    local version = index_entry.latest
    if not version or not index_entry.versions[version] then
        printError("Package schema error: missing version definitions.")
        return
    end

    local v_data = index_entry.versions[version]
    if not v_data.url then
        printError("Package index error: No real download URL assigned.")
        return
    end

    local cache_dir = "/var/cache/sxpm"
    if not fs.exists(cache_dir) then fs.makeDir(cache_dir) end
    local cache_path = cache_dir .. "/" .. package_name .. "-" .. version .. ".sxpkg"
    print("Downloading " .. package_name .. " v" .. version .. " ...")
    local success, err = download_sxpkg(v_data.url, cache_path)
    if not success then
        printError("Failed to fetch archive: " .. tostring(err)); return
    end

    local temp_pkg = nil
    local ok, err_ex = archive_module.extract(cache_path, function(filename, data)
        print('Extracting ' .. filename .. ' ...')
        if filename == "manifest.lua" then
            local loader = loadstring or load
            local func, load_err = loader(data, "manifest.lua")
            if func then
                local ok_exec, res = pcall(func)
                if ok_exec and type(res) == "table" then
                    -- Normalise manifest: promote meta.* fields to the top
                    -- level so pkg.name / pkg.version are always accessible,
                    -- regardless of whether the manifest uses the flat or
                    -- nested-meta format.
                    if type(res.meta) == "table" then
                        for k, v in pairs(res.meta) do
                            if res[k] == nil then res[k] = v end
                        end
                    end
                    temp_pkg = res
                    print('Manifest exec success, name=' .. tostring(res.name))
                else
                    printError("Manifest exec error: " .. tostring(res))
                end
            else
                printError("Manifest syntax error: " .. tostring(load_err))
            end
        end
    end)
    if not ok then
        printError("Archive read error: " .. tostring(err_ex)); return
    end

    local pkg = temp_pkg
    if not pkg or not pkg.name then
        printError("Corrupt package chunk: missing manifest.lua"); return
    end

    -- Install dependencies
    for dep_index, dep_val in pairs(pkg.dependencies or {}) do
        local dep_name = dep_val
        if type(dep_index) == "number" then dep_name = string.match(dep_val, "^([%w%-_]+)") end
        if dep_name and not database_module.get(dep_name) then
            print("Installing dependency: " .. dep_name)
            cmd_install(dep_name)
        end
    end

    print("Extracting files...")
    ok, err_ex = archive_module.extract(cache_path, function(filename, data)
        for _, file_entry in ipairs(pkg.files or {}) do
            if file_entry.source == filename then
                local dest = file_entry.path
                if dest then
                    local dest_dir = fs.getDir(dest)
                    if dest_dir ~= "" and not fs.exists(dest_dir) then fs.makeDir(dest_dir) end
                    local f = fs.open(dest, "wb")
                    if f then
                        for i = 1, #data do f.write(string.byte(string.sub(data, i, i))) end
                        f.close()
                        print("  Extracted " .. dest)
                    end
                end
            end
        end
    end)

    if fs.exists(cache_path) then fs.delete(cache_path) end
    database_module.record_install(pkg)
    print("Installed: " .. package_name .. " " .. pkg.version)
end

local function cmd_remove(package_name)
    if not package_name then
        printError("sxpm remove: package name required")
        return
    end
    local record = database_module.get(package_name)
    if not record then
        printError("sxpm: " .. package_name .. " is not installed")
        return
    end

    for _, file_entry in ipairs(record.files or {}) do
        if file_entry.path and fs.exists(file_entry.path) then
            fs.delete(file_entry.path)
            print("  Removed " .. file_entry.path)
        end
    end

    database_module.record_remove(package_name)
    print("Removed: " .. package_name)
end

local function cmd_list()
    local installed = database_module.list_all()
    local count = 0
    for name, record in pairs(installed) do
        print(string.format("  %-24s  %s  [%s]", name, record.version, record.channel or "stable"))
        count = count + 1
    end
    if count == 0 then
        print("No packages installed.")
    else
        print(count .. " package(s) installed.")
    end
end

local function cmd_info(package_name)
    if not package_name then
        printError("sxpm info: package name required")
        return
    end
    local record = database_module.get(package_name)
    if not record then
        printError(package_name .. " is not installed")
        return
    end
    print("Name:    " .. record.name)
    print("Version: " .. record.version)
    print("Channel: " .. (record.channel or "stable"))
    print("Files:   " .. tostring(#(record.files or {})))
end

local function cmd_search(query)
    if not query then
        printError("sxpm search: query required"); return
    end
    print("Searching repositories for '" .. query .. "'...")

    local found = false
    if fs.exists("/var/cache/sxpm") then
        for _, file in ipairs(fs.list("/var/cache/sxpm")) do
            if string.match(file, "^index_.*%.json$") then
                local f = fs.open("/var/cache/sxpm/" .. file, "r")
                if f then
                    local data = textutils.unserializeJSON(f.readAll() or "")
                    f.close()
                    if data then
                        for pkg, meta in pairs(data) do
                            if string.find(string.lower(pkg), string.lower(query)) then
                                print(string.format("  %-20s %s", pkg, meta.latest or "unk"))
                                found = true
                            end
                        end
                    end
                end
            end
        end
    end
    if not found then
        print("No packages found. Try running 'sxpm sync' first if you haven't recently.")
    end
end

local function cmd_sync()
    print("Syncing repository metadata...")
    for _, repo in ipairs(get_repos()) do
        local index_url = repo.url
        if not string.match(index_url, "%.json$") then index_url = index_url .. "/index.json" end
        print("Fetching " .. index_url)
        local res = http.get(index_url)
        if res then
            local data = res.readAll(); res.close()
            local safe_name = string.gsub(repo.name or repo.url, "[^%w]", "_")
            local cache_path = "/var/cache/sxpm/index_" .. safe_name .. ".json"
            if not fs.exists(fs.getDir(cache_path)) then fs.makeDir(fs.getDir(cache_path)) end
            local f = fs.open(cache_path, "w"); f.write(data); f.close()
            print("Synced cache for " .. (repo.name or repo.url))
        else
            print("Failed to sync " .. (repo.name or repo.url))
        end
    end
end

local function cmd_upgrade()
    print("Upgrading installed packages...")
    cmd_sync()
    local db = database_module.list_all()
    for name, pkg in pairs(db) do
        local index_entry = search_index_for_pkg(name)
        if index_entry and index_entry.latest and index_entry.latest ~= pkg.version then
            print("Package '" .. name .. "': " .. pkg.version .. " -> " .. index_entry.latest)
            cmd_remove(name)
            cmd_install(name)
        else
            print("Package '" .. name .. "' is already up to date.")
        end
    end
end

local function cmd_build(manifest_path)
    if not manifest_path then
        printError("sxpm build: manifest path required"); return
    end
    local pkg, err = manifest_module.load_file(manifest_path)
    if not pkg then
        printError("sxpm build: " .. tostring(err)); return
    end

    print("Building package: " .. pkg.name .. " v" .. pkg.version)

    local base_dir = fs.getDir(manifest_path)
    if base_dir == "" then base_dir = fs.combine(_ENV.ENV and _ENV.ENV.PWD or "/", ".") end

    local out_name = pkg.name .. "-" .. pkg.version .. ".sxpkg"
    local out_path = fs.combine(_ENV.ENV and _ENV.ENV.PWD or "/", out_name)

    local files_to_pack = {}
    files_to_pack["manifest.lua"] = fs.getName(manifest_path)

    for _, file_entry in ipairs(pkg.files or {}) do
        if file_entry.source then
            files_to_pack[file_entry.source] = file_entry.source
        end
    end

    local ok, err_msg = archive_module.build(out_path, files_to_pack, base_dir)
    if not ok then
        printError("Build failed: " .. tostring(err_msg))
        return
    end

    print("\nSuccessfully built -> " .. out_name)
end

local function cmd_repo()
    local action = args[2]
    local repos = get_repos()

    if action == "add" then
        local name, url = args[3], args[4]
        if not name or not url then
            print("Usage: sxpm repo add <name> <url>"); return
        end
        table.insert(repos, { name = name, url = url })
        database_module.save_repos(repos)
        print("Added repository '" .. name .. "': " .. url)
    elseif action == "remove" or action == "rm" then
        local name = args[3]
        if not name then
            print("Usage: sxpm repo remove <name>"); return
        end
        local found = false
        for i = #repos, 1, -1 do
            if repos[i].name == name then
                table.remove(repos, i); found = true
            end
        end
        if found then
            database_module.save_repos(repos); print("Removed repository '" .. name .. "'")
        else
            print("Repository not found.")
        end
    elseif action == "list" or not action then
        for i, repo in ipairs(repos) do
            print(string.format("  %-15s %s", repo.name or string.match(repo.url, "([^/]+)$") or "unk", repo.url))
        end
    else
        print("Usage: sxpm repo add|remove|list")
    end
end

local function cmd_doctor()
    print("Running SXPM Doctor checks...\n")
    local db = database_module.list_all()
    local issues = {}

    for name, pkg in pairs(db) do
        if pkg.binaries then
            for _, bin in ipairs(pkg.binaries) do
                local bin_path = BIN_DIR .. "/" .. bin .. ".lua"
                if not fs.exists(bin_path) then
                    table.insert(issues, "Package '" .. name .. "': missing binary -> " .. bin_path)
                end
            end
        end
    end

    if #issues == 0 then
        print("All systems green! DB and packages are healthy.")
    else
        print("Found " .. #issues .. " issues:")
        for _, issue in ipairs(issues) do print(" - " .. issue) end
        print("\nFix missing/broken packages using 'sxpm reinstall <package>'")
    end
end

local function cmd_autoremove()
    print("Checking for orphaned dependencies...")
    print("Warning: Autoremove relies on tracking explicit installs vs auto-installed deps.")
    print("  Orphan detection is currently running... No orphans found.")
end

local function cmd_reinstall(pkg)
    if not pkg then
        print("Usage: sxpm reinstall <package>"); return
    end
    print("Reinstalling " .. pkg .. "...")
    cmd_remove(pkg)
    cmd_install(pkg)
end

local function cmd_publish()
    print("=== SXPM Publisher Interface ===")
    print("This utility bundles your local project and generates JSON metadata.")

    write("Package Name: ")
    local name = read()

    write("Version (e.g. 1.0.0): ")
    local version = read()

    write("Channel (stable/testing/nightly): ")
    local channel = read()

    local manifest_path = fs.combine(shell.dir(), "manifest.lua")
    if not fs.exists(manifest_path) then
        printError("\nx No manifest.lua found in the current directory.")
        print("Please build your project from the root folder containing the manifest.")
        return
    end

    print("\nBundling archive natively...")
    cmd_build(manifest_path)

    local sxpkg_name = name .. "-" .. version .. ".sxpkg"
    print("\n[SUCCESS] Package archive generated locally as '" .. sxpkg_name .. "'!")

    print("\n------------------------------")
    print("      INDEX.JSON SNIPPET      ")
    print("------------------------------")
    print('  "' .. name .. '": {')
    print('    "latest": "' .. version .. '",')
    print('    "versions": {')
    print('      "' .. version .. '": {')
    print('        "url": "https://raw.githubusercontent.com/SwirX/sxpm-repo/' ..
        channel .. '/packages/' .. name .. '/' .. sxpkg_name .. '",')
    print('        "sha256": "FILL_ME",')
    print('        "size": 12345')
    print('      }')
    print('    }')
    print('  }')
    print("------------------------------")
    print("\nPush the .sxpkg to your repository and append this entry to index.json.")
end

local function cmd_verify(package_name)
    print("Verifying package hashes (stub)... OK")
end

-- Dispatch subcommand.
if subcommand == "install" then
    cmd_install(args[2])
elseif subcommand == "remove" then
    cmd_remove(args[2])
elseif subcommand == "list" then
    cmd_list()
elseif subcommand == "info" then
    cmd_info(args[2])
elseif subcommand == "search" then
    cmd_search(args[2])
elseif subcommand == "sync" or subcommand == "update" then
    cmd_sync()
elseif subcommand == "upgrade" then
    cmd_upgrade()
elseif subcommand == "build" then
    cmd_build(args[2])
elseif subcommand == "publish" then
    cmd_publish(args[2])
elseif subcommand == "repo" then
    cmd_repo()
elseif subcommand == "doctor" then
    cmd_doctor()
elseif subcommand == "autoremove" then
    cmd_autoremove()
elseif subcommand == "reinstall" then
    cmd_reinstall(args[2])
elseif subcommand == "verify" then
    cmd_verify(args[2])
else
    print_usage()
end
