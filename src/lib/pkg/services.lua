-- /lib/pkg/services.lua
local services = {}

function services.register(pkg)
    if not pkg.services then return end
    if not fs.exists("/etc/sxpm/services") then fs.makeDir("/etc/sxpm/services") end
    for _, s in ipairs(pkg.services) do
        local f = fs.open("/etc/sxpm/services/" .. s.name .. ".json", "w")
        if f then
            f.write(textutils.serializeJSON(s))
            f.close()
        end
    end
end

function services.unregister(pkg_manifest)
    if not pkg_manifest or not pkg_manifest.services then return end
    for _, s in ipairs(pkg_manifest.services) do
        local path = "/etc/sxpm/services/" .. s.name .. ".json"
        if fs.exists(path) then
            fs.delete(path)
        end
    end
end

return services
