-- /lib/pkg/resolve.lua
-- Dependency resolution for SXPM.
-- Checks installed packages against declared dependencies and reports
-- what is missing or version-mismatched before an install is attempted.

local resolve = {}

local manifest_module = dofile("/lib/pkg/manifest.lua")
local database_module = dofile("/lib/pkg/database.lua")

-- Evaluate whether a single dependency declaration is satisfied.
-- dep: parsed dependency table from manifest.parse_dependency()
-- Returns true if satisfied, false + reason string if not.
local function dependency_satisfied(dep)
    local installed = database_module.get(dep.name)
    if not installed then
        return false, dep.name .. " is not installed"
    end

    -- No version constraint: any installed version is fine.
    if not dep.operator or not dep.version then return true end

    local installed_ver = manifest_module.parse_version(installed.version)
    if not installed_ver then
        return false, dep.name .. " has an unparseable version: " .. tostring(installed.version)
    end

    local comparison = manifest_module.compare_versions(installed_ver, dep.version)
    local op = dep.operator

    if op == ">=" and comparison >= 0 then return true end
    if op == ">" and comparison > 0 then return true end
    if op == "<=" and comparison <= 0 then return true end
    if op == "<" and comparison < 0 then return true end
    if op == "==" or op == "=" then
        if comparison == 0 then return true end
    end
    if op == "!=" and comparison ~= 0 then return true end

    return false, dep.name .. " " .. installed.version ..
        " does not satisfy " .. op .. dep.version.raw
end

-- Check all dependencies in a manifest. Returns a list of { dep, reason }
-- for each unsatisfied dependency. Empty list means all satisfied.
function resolve.check_dependencies(pkg_manifest)
    local missing = {}
    for _, dep_str in ipairs(pkg_manifest.dependencies or {}) do
        local dep = manifest_module.parse_dependency(dep_str)
        if dep then
            local ok, reason = dependency_satisfied(dep)
            if not ok then
                table.insert(missing, { dep = dep, reason = reason })
            end
        end
    end
    return missing
end

return resolve
