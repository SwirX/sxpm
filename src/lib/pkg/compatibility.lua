-- /lib/pkg/compatibility.lua
local compatibility = {}
local manifest = dofile("/lib/pkg/manifest.lua")

function compatibility.check_platform(pkg)
    if not pkg.platform then return true end
    local errors = {}

    local os_version = "2.0.2"
    if fs.exists("/etc/os-release") then
        local f = fs.open("/etc/os-release", "r")
        if f then
            for line in f.readLine do
                if string.match(line, "^VERSION=\"?(.-)\"?$") then
                    os_version = string.match(line, "^VERSION=\"?(.-)\"?$")
                end
            end
            f.close()
        end
    end

    if pkg.platform.sxos then
        local req = manifest.parse_version(string.match(pkg.platform.sxos, "[%d%.]+"))
        local current = manifest.parse_version(os_version)
        if req and current and manifest.compare_versions(current, req) < 0 then
            table.insert(errors, "Requires SXOS >= " .. string.match(pkg.platform.sxos, "[%d%.]+"))
        end
    end

    if pkg.platform.cc then
        local req = manifest.parse_version(string.match(pkg.platform.cc, "[%d%.]+"))
        local current = manifest.parse_version("1.109.0") -- Approximation
        if req and current and manifest.compare_versions(current, req) < 0 then
            table.insert(errors, "Requires ComputerCraft >= " .. string.match(pkg.platform.cc, "[%d%.]+"))
        end
    end

    if #errors > 0 then return false, errors end
    return true
end

return compatibility
