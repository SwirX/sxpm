# sxpm

SXOS Package Manager for [ComputerCraft: Tweaked](https://tweaked.cc/).

---

## Installation

### On SXOS

`sxpm` is **pre-installed** on SXOS. No manual setup is required.

To upgrade sxpm itself after an update:

```
sxpm upgrade sxpm
```

### On CraftOS or any other CC:Tweaked OS

Run the one-line installer from the CraftOS prompt:

```
wget run https://raw.githubusercontent.com/SwirX/sxpm/stable/install.lua
```

The installer will:

1. Download all required `sxpm` files (`/usr/bin/sxpm.lua` + `/lib/pkg/*.lua`)
2. Create the necessary directories (`/var/cache/sxpm`, `/var/lib/sxpm`, `/etc/sxpm`)
3. Detect if you accidentally run it on SXOS and bail gracefully

> **Why not just `wget run sxpm.lua`?**  
> `sxpm` depends on several library modules (`archive.lua`, `database.lua`, `manifest.lua`, `resolve.lua`) that need to be present at `/lib/pkg/`. Running just the binary without them will crash immediately. The installer fetches everything in one shot.

After the installer completes:

```
sxpm sync              -- fetch the latest package index
sxpm install sxos-core -- install a package
```

---

## Commands

| Command | Description |
|---------|-------------|
| `sxpm install <pkg>` | Install a package |
| `sxpm remove <pkg>` | Remove a package |
| `sxpm upgrade` | Upgrade all installed packages |
| `sxpm search <query>` | Search indexed packages |
| `sxpm list` | List installed packages |
| `sxpm info <pkg>` | Show installed package details |
| `sxpm sync` / `sxpm update` | Refresh the repository index cache |
| `sxpm build <manifest>` | Build a `.sxpkg` from a manifest |
| `sxpm publish` | Interactive wizard for publishing |
| `sxpm repo add/remove/list` | Manage repo sources |
| `sxpm doctor` | Check system for broken packages |
| `sxpm autoremove` | Remove orphaned dependencies |
| `sxpm reinstall <pkg>` | Reinstall a package |

---

## Package Format (.sxpkg)

A `.sxpkg` is a streamable binary archive in the `SXP1` format containing:

- `manifest.lua` - package metadata and file mapping
- source files at paths matching each `files[].source` entry
- `scripts/` - optional lifecycle hooks (`post_install.lua`, etc.)

```lua
-- manifest.lua example
return {
    format = "sxpkg-1",

    meta = {
        name        = "myapp",
        version     = "1.0.0",
        author      = "You",
        channel     = "stable",
        description = "My application.",
    },

    dependencies = { "sxui" },

    files = {
        { path = "/usr/bin/myapp.lua", source = "bin/myapp.lua", executable = true },
        { path = "/lib/myapp/core.lua", source = "lib/core.lua" },
    },

    lifecycle = {
        post_install = "scripts/post_install.lua",
    },
}
```

Build and publish:

```
sxpm build manifest.lua     -- creates myapp-1.0.0.sxpkg in cwd
sxpm publish                -- interactive: bundles + prints index.json snippet
```

---

## Repository Index Format

The index is a flat JSON file fetched by `sxpm sync`. Default location:

```
https://raw.githubusercontent.com/SwirX/sxpm-repo/stable/index.json
```

```json
{
  "pkg-name": {
    "latest": "1.0.0",
    "versions": {
      "1.0.0": {
        "url": "https://raw.githubusercontent.com/SwirX/sxpm-repo/stable/packages/pkg-name/pkg-name-1.0.0.sxpkg",
        "sha256": "abc123...",
        "size": 12345
      }
    }
  }
}
```

Add a custom repository:

```
sxpm repo add myrepo https://raw.githubusercontent.com/you/my-repo/main/index.json
```

---

## Available Packages

| Package | Description |
|---------|-------------|
| `sxos-core` | SXOS core operating system |
| `sxui` | SX-UI framework (UI library) |
| `sxmusic` | SX-Music networked audio player |

---

## Project Layout

```
sxpm/
  install.lua               Standalone installer for CraftOS
  src/
    bin/sxpm.lua            Main CLI entry point
    lib/pkg/
      archive.lua           SXP1 archive builder/extractor
      manifest.lua          Manifest parser and validator
      database.lua          Installed package database
      resolve.lua           Dependency resolver
```
