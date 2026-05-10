-- /lib/pkg/lifecycle.lua
local lifecycle = {}

local function run_hook(pkg_dir, hook_cmd)
    if not hook_cmd then return true end
    local full_path = fs.combine(pkg_dir, hook_cmd)
    if fs.exists(full_path) then
        print("Running hook " .. hook_cmd .. "...")
        local ok, err = pcall(dofile, full_path)
        if not ok then
            printError("Hook error: " .. tostring(err))
            return false
        end
    end
    return true
end

function lifecycle.pre_install(pkg, extract_dir) return run_hook(extract_dir, pkg.lifecycle and pkg.lifecycle
    .pre_install) end

function lifecycle.post_install(pkg, extract_dir) return run_hook(extract_dir,
        pkg.lifecycle and pkg.lifecycle.post_install) end

function lifecycle.pre_upgrade(pkg, extract_dir) return run_hook(extract_dir, pkg.lifecycle and pkg.lifecycle
    .pre_upgrade) end

function lifecycle.post_upgrade(pkg, extract_dir) return run_hook(extract_dir,
        pkg.lifecycle and pkg.lifecycle.post_upgrade) end

function lifecycle.pre_remove(pkg, extract_dir) return run_hook(extract_dir, pkg.lifecycle and pkg.lifecycle.pre_remove) end

function lifecycle.post_remove(pkg, extract_dir) return run_hook(extract_dir, pkg.lifecycle and pkg.lifecycle
    .post_remove) end

return lifecycle
