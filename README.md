# sxpm

SXOS Package Manager for [ComputerCraft: Tweaked](https://tweaked.cc/).

## Bootstrap

`sxpm` is distributed via `sxos/install.lua` automatically, or you can install it standalone:

```lua
wget run https://raw.githubusercontent.com/SwirX/sxpm/stable/src/bin/sxpm.lua
```

## Commands

| Command | Description |
|---------|-------------|
| `sxpm install <pkg>` | Install a package |
| `sxpm remove <pkg>` | Remove a package |
| `sxpm upgrade` | Upgrade all installed packages |
| `sxpm search <query>` | Search indexed packages |
| `sxpm list` | List installed packages |
| `sxpm info <pkg>` | Show installed package details |
| `sxpm sync` | Refresh the repository index cache |
| `sxpm build <manifest>` | Build a `.sxpkg` from a manifest |
| `sxpm publish` | Interactive wizard for publishing |
| `sxpm repo add/remove/list` | Manage repo sources |
| `sxpm doctor` | Check system for broken packages |

## Package Format (.sxpkg)

A `.sxpkg` is a streamable binary archive in the `SXP1` format containing:

- `manifest.lua` - package metadata and file mapping
- `files/` - package file tree
- `scripts/` - lifecycle hooks (`pre_install.lua`, `post_install.lua`)

```lua
-- manifest.lua example
return {
    format = "sxpkg-1",
    meta   = { name = "myapp", version = "1.0.0", author = "You", channel = "stable" },
    dependencies = { "sxui >=1.0.0" },
    files  = {
        { path = "/usr/bin/myapp.lua", source = "bin/myapp.lua", executable = true },
    },
    lifecycle = { post_install = "scripts/post_install.lua" },
}
```

## Repository Index Format

```json
{
  "pkg-name": {
    "latest": "1.0.0",
    "versions": {
      "1.0.0": {
        "url": "https://...pkg-name-1.0.0.sxpkg",
        "sha256": "...",
        "size": 12345
      }
    }
  }
}
```

## Project Layout

```
sxpm/
  src/
    bin/sxpm.lua          Main CLI entry point
    lib/pkg/
      archive.lua         SXP1 archive builder/extractor
      manifest.lua        Manifest parser and validator
      database.lua        Installed package database
      resolve.lua         Dependency resolver
```
