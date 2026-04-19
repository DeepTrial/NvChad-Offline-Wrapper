# LazyVim Offline Wrapper

Bundle LazyVim + Neovim binary + all plugins for completely offline installation on Ubuntu 20.04/22.04.

No network access required after the package is built.

## Quick Start

### Option 1: GitHub Actions (Recommended)

1. Go to Actions → Build LazyVim Offline Package → Run workflow
2. Download `lazyvim-offline-ubuntu.tar.gz` from the release
3. Transfer to offline machine
4. Install:
   ```bash
   tar -xzf lazyvim-offline.tar.gz
   cd lazyvim-offline
   ./install.sh
   export PATH="$HOME/.local/bin:$PATH"
   nvim
   ```

### Option 2: Local Build

```bash
# Build neovim + download all plugins
./build.sh

# With Treesitter parsers
./build.sh --treesitter

# With Treesitter + Mason LSP
./build.sh --all

# Custom selection
./build.sh --treesitter lua,vim,python --mason lua_ls,pylsp

# Use system neovim instead of building from source
./build.sh --no-neovim
```

## What's Included

| Component | Description |
|-----------|-------------|
| Neovim binary | Built from source on Ubuntu 20.04 for compatibility |
| LazyVim starter | Official LazyVim configuration template |
| All plugins | Pre-downloaded, no network needed |
| Treesitter | Syntax highlighting parsers (optional) |
| Mason LSP | Language servers (optional) |

## Files

```
├── build.sh              # Build script (run online)
├── install.sh            # Install script (run offline)
└── .github/workflows/    # GitHub Actions
```

## glibc Compatibility

Built on Ubuntu 20.04 (glibc 2.31), compatible with:
- Ubuntu 20.04
- Ubuntu 22.04 (glibc 2.35)

## Default Components

| Component | Default |
|-----------|---------|
| Treesitter | lua, vim, vimdoc, python, javascript, typescript, json, html, css, bash, c, cpp |
| Mason LSP | lua_ls |

## Requirements (Offline Machine)

- Ubuntu 20.04 or 22.04
- No Neovim installation required (included in package)

## Requirements (Build Machine)

- Ubuntu (for local build)
- Or use GitHub Actions (recommended)
