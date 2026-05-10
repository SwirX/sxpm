-- manifest.lua
return {
    format = "sxpkg-1",
    meta = {
        name        = "sxpm",
        version     = "1.0.0",
        author      = "SwirX",
        description = "SXOS Package Manager",
        channel     = "stable",
    },
    dependencies = { "sxos-core" },
    files = {
        { path = "/bin/sxpm.lua",         source = "src/bin/sxpm.lua",        executable = true },
        { path = "/lib/pkg/archive.lua",  source = "src/lib/pkg/archive.lua" },
        { path = "/lib/pkg/database.lua", source = "src/lib/pkg/database.lua" },
        { path = "/lib/pkg/manifest.lua", source = "src/lib/pkg/manifest.lua" },
        { path = "/lib/pkg/resolve.lua",  source = "src/lib/pkg/resolve.lua" },
    },
    integrity = {
        sha256 = "FILL_ME",
    },
}
