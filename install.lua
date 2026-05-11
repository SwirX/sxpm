-- sxpm/install.lua
-- Standalone installer for sxpm on CraftOS or any CC:Tweaked OS.
-- Usage: wget run https://raw.githubusercontent.com/SwirX/sxpm/stable/install.lua
--
-- On SXOS, sxpm is already bundled; this installer will detect that and exit early.

local BRANCH   = "stable"
local RAW_BASE = "https://raw.githubusercontent.com/SwirX/sxpm/" .. BRANCH

local FILES    = {
    { src = "src/bin/sxpm.lua",         dst = "/usr/bin/sxpm.lua" },
    { src = "src/lib/pkg/archive.lua",  dst = "/lib/pkg/archive.lua" },
    { src = "src/lib/pkg/database.lua", dst = "/lib/pkg/database.lua" },
    { src = "src/lib/pkg/manifest.lua", dst = "/lib/pkg/manifest.lua" },
    { src = "src/lib/pkg/resolve.lua",  dst = "/lib/pkg/resolve.lua" },
}

-- ── helpers ──────────────────────────────────────────────────────────────────

local function ok(msg) print("[  OK  ] " .. msg) end
local function err(msg) printError("[ FAIL ] " .. msg) end
local function info(msg) print("[  --  ] " .. msg) end

local function mkdir(path)
    local parts = {}
    local cur   = ""
    for segment in string.gmatch(path, "[^/]+") do
        cur = cur .. "/" .. segment
        table.insert(parts, cur)
    end
    for _, p in ipairs(parts) do
        if not fs.exists(p) then fs.makeDir(p) end
    end
end

local function download(url, dest)
    write("  " .. dest .. " ... ")
    local res = http.get(url)
    if not res then
        print("FAILED")
        return false
    end
    local data = res.readAll()
    res.close()
    mkdir(fs.getDir(dest))
    local f = fs.open(dest, "w")
    if not f then
        print("FAILED (write)"); return false
    end
    f.write(data)
    f.close()
    print("ok")
    return true
end

-- ── SXOS detection ───────────────────────────────────────────────────────────

local function is_sxos()
    -- SXOS sets /etc/os-release and ships sxpm at /usr/bin/sxpm.lua
    return fs.exists("/etc/os-release") or fs.exists("/sys/kernel.lua")
end

-- ── main ─────────────────────────────────────────────────────────────────────

print("╔══════════════════════════════════╗")
print("║      sxpm  -  SXOS pkg mgr      ║")
print("║          standalone installer    ║")
print("╚══════════════════════════════════╝")
print("")

if is_sxos() then
    print("Detected SXOS environment.")
    print("sxpm is already bundled with SXOS - no manual installation needed.")
    print("")
    print("To upgrade sxpm itself, run:")
    print("  sxpm upgrade sxpm")
    return
end

info("Installing sxpm from branch: " .. BRANCH)
print("")

local failed = 0
if not is_sxos() then
    FILES[1].dst = "/sxpm.lua"
end
for _, entry in ipairs(FILES) do
    local url = RAW_BASE .. "/" .. entry.src
    if not download(url, entry.dst) then
        failed = failed + 1
    end
end

-- Create a shell alias so `sxpm` works without the .lua extension
if is_sxos() then
    local alias_path = "/usr/bin/sxpm"
    if not fs.exists(alias_path) then
        local af = fs.open(alias_path, "w")
        if af then
            -- CraftOS shell strips .lua when resolving /usr/bin, so a plain
            -- redirect script is the safest portable approach.
            af.write("shell.run(\"/usr/bin/sxpm.lua\", ...)\n")
            af.close()
        end
    end
end

-- Ensure /var/cache/sxpm and /var/lib/sxpm exist so first `sync` works
for _, d in ipairs({ "/var/cache/sxpm", "/var/lib/sxpm", "/etc/sxpm" }) do
    mkdir(d)
end

print("")
if failed == 0 then
    ok("sxpm installed successfully!")
    print("")
    print("To get started, run:")
    print("  sxpm sync               -- refresh the package index")
    print("  sxpm search sxos-core   -- find a package")
    print("  sxpm install sxos-core  -- install a package")
else
    err(failed .. " file(s) failed to download.")
    print("Check your internet connection and try again.")
    print("You can re-run this installer safely at any time.")
end
