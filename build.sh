#!/bin/bash
# LazyVim Offline Wrapper - Builder
# Run this script in an online environment to create the offline package

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE_DIR="${SCRIPT_DIR}/lazyvim-offline"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse arguments
BUILD_TREESITTER=false
BUILD_MASON=false
PARSERS=""
LSP_SERVERS=""
BUILD_NEOVIM=true

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --treesitter [parsers]  Build Treesitter parsers (comma-separated)"
    echo "                          Default: lua,vim,vimdoc,python,javascript,typescript,json,html,css,bash"
    echo "  --mason [packages]      Build Mason LSP servers (comma-separated)"
    echo "                          Default: lua_ls"
    echo "  --all                   Build both Treesitter and Mason with defaults"
    echo "  --no-neovim             Skip building neovim (use system neovim)"
    echo "  --help                  Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Build neovim + download plugins only"
    echo "  $0 --treesitter                       # Build + default parsers"
    echo "  $0 --treesitter lua,vim,python        # Build + specific parsers"
    echo "  $0 --mason lua_ls,pylsp               # Build + specific LSP"
    echo "  $0 --all                              # Build everything"
    exit 0
}

# Default parsers
DEFAULT_PARSERS="lua,vim,vimdoc,python,javascript,typescript,json,html,css,bash,c,cpp"
DEFAULT_LSP="lua_ls"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --treesitter)
            BUILD_TREESITTER=true
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                PARSERS="$2"
                shift
            else
                PARSERS="$DEFAULT_PARSERS"
            fi
            shift
            ;;
        --mason)
            BUILD_MASON=true
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                LSP_SERVERS="$2"
                shift
            else
                LSP_SERVERS="$DEFAULT_LSP"
            fi
            shift
            ;;
        --all)
            BUILD_TREESITTER=true
            BUILD_MASON=true
            PARSERS="$DEFAULT_PARSERS"
            LSP_SERVERS="$DEFAULT_LSP"
            shift
            ;;
        --no-neovim)
            BUILD_NEOVIM=false
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

echo -e "${GREEN}=== LazyVim Offline Package Builder ===${NC}"
echo ""

# Clean and create directory structure
rm -rf "$OFFLINE_DIR"
mkdir -p "$OFFLINE_DIR"/{lazy-plugins,lazyvim-starter,nvim/linux-x64}

NVIM_BIN="nvim"

# ============================================
# 1. Build Neovim from source (Ubuntu 20.04 compatible)
# ============================================
if [ "$BUILD_NEOVIM" = true ]; then
    echo -e "${YELLOW}[1/5] Building Neovim from source...${NC}"

    if ! command -v cmake &> /dev/null; then
        echo -e "${RED}Error: cmake not found. Cannot build neovim.${NC}"
        exit 1
    fi

    BUILD_ROOT=$(mktemp -d)
    cd "$BUILD_ROOT"

    git clone --depth 1 --branch stable https://github.com/neovim/neovim.git
    cd neovim

    # Build with Release mode, install to local prefix
    make CMAKE_BUILD_TYPE=Release CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX=$BUILD_ROOT/neovim-install"
    make install

    # Copy neovim binaries and runtime
    mkdir -p "$OFFLINE_DIR/nvim/linux-x64"
    cp -r "$BUILD_ROOT/neovim-install"/* "$OFFLINE_DIR/nvim/linux-x64/"

    # Set path to our built nvim
    NVIM_BIN="$OFFLINE_DIR/nvim/linux-x64/bin/nvim"

    echo -e "${GREEN}Neovim built successfully${NC}"
    "$NVIM_BIN" --version | head -3

    cd "$SCRIPT_DIR"
    rm -rf "$BUILD_ROOT"
else
    echo -e "${YELLOW}[1/5] Using system neovim...${NC}"
    if ! command -v nvim &> /dev/null; then
        echo -e "${RED}Error: neovim not found${NC}"
        exit 1
    fi
    NVIM_BIN="$(which nvim)"
    echo "Using: $NVIM_BIN"
    "$NVIM_BIN" --version | head -1
fi

# ============================================
# 2. Download LazyVim starter template
# ============================================
echo ""
echo -e "${YELLOW}[2/5] Downloading LazyVim starter template...${NC}"

git clone --depth 1 https://github.com/LazyVim/starter "$OFFLINE_DIR/lazyvim-starter"
rm -rf "$OFFLINE_DIR/lazyvim-starter/.git"

# ============================================
# 3. Pre-download all plugins using lazy.nvim
# ============================================
echo ""
echo -e "${YELLOW}[3/5] Pre-downloading all plugins...${NC}"

# Create isolated build environment
BUILD_ROOT=$(mktemp -d)
BUILD_CONFIG="$BUILD_ROOT/config/nvim"
BUILD_DATA="$BUILD_ROOT/data"
BUILD_STATE="$BUILD_ROOT/state"
BUILD_CACHE="$BUILD_ROOT/cache"

mkdir -p "$BUILD_CONFIG" "$BUILD_DATA" "$BUILD_STATE" "$BUILD_CACHE"

# Copy starter config to build config
cp -r "$OFFLINE_DIR/lazyvim-starter/"* "$BUILD_CONFIG/"

# Create a custom init.lua that forces offline mode and disables update checks
cat > "$BUILD_CONFIG/init.lua" << 'INITEOF'
-- Bootstrap lazy.nvim (will use local copy if available)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    -- Try to use local copy from offline package
    local offline_lazy = os.getenv("OFFLINE_LAZY_PATH")
    if offline_lazy and vim.loop.fs_stat(offline_lazy) then
        vim.fn.mkdir(vim.fn.fnamemodify(lazypath, ":h"), "p")
        vim.fn.system({"cp", "-r", offline_lazy, lazypath})
    else
        -- Fallback: clone (should not happen in build)
        vim.fn.system({
            "git",
            "clone",
            "--filter=blob:none",
            "https://github.com/folke/lazy.nvim.git",
            "--branch=stable",
            lazypath,
        })
    end
end
vim.opt.rtp:prepend(lazypath)

-- Load LazyVim configuration
require("lazyvim.config").init()

-- Setup lazy.nvim with offline configuration
require("lazy").setup({
    spec = {
        { "LazyVim/LazyVim", import = "lazyvim.plugins" },
        { import = "plugins" },
    },
    defaults = {
        lazy = false,
        version = false, -- always use latest git commit
    },
    install = {
        missing = true,
        colorscheme = { "tokyonight", "habamax" },
    },
    checker = { enabled = false }, -- disable update checker
    change_detection = { enabled = false },
    performance = {
        rtp = {
            disabled_plugins = {
                "gzip",
                "matchit",
                "matchparen",
                "netrwPlugin",
                "tarPlugin",
                "tohtml",
                "tutor",
                "zipPlugin",
            },
        },
    },
})

-- Load settings
require("config.options")
require("config.keymaps")
require("config.autocmds")
INITEOF

# Export environment variables for the build
export XDG_CONFIG_HOME="$BUILD_ROOT/config"
export XDG_DATA_HOME="$BUILD_ROOT/data"
export XDG_STATE_HOME="$BUILD_ROOT/state"
export XDG_CACHE_HOME="$BUILD_ROOT/cache"

# First, download lazy.nvim itself
echo "  Downloading lazy.nvim..."
git clone --depth 1 --branch stable https://github.com/folke/lazy.nvim "$BUILD_DATA/nvim/lazy/lazy.nvim"

# Set offline path for init.lua
export OFFLINE_LAZY_PATH="$BUILD_DATA/nvim/lazy/lazy.nvim"

# Run nvim to download all plugins
echo "  Starting Neovim to download all plugins..."
echo "  (This may take several minutes...)"

# Create a script to wait for lazy sync and then quit
cat > "$BUILD_ROOT/sync.lua" << 'SYNCEOF'
-- Wait for lazy to finish installing
local function wait_for_install()
    local lazy = require("lazy")
    local start_time = vim.loop.now()
    local timeout = 300000 -- 5 minutes timeout

    while true do
        local stats = lazy.stats()
        -- Check if all plugins are installed
        if stats.loaded > 0 and stats.loaded == stats.count then
            print("All plugins loaded: " .. stats.loaded .. "/" .. stats.count)
            break
        end

        -- Check timeout
        if vim.loop.now() - start_time > timeout then
            print("Timeout waiting for plugins")
            break
        end

        vim.loop.sleep(1000)
        vim.cmd("redraw")
        print("Waiting for plugins... " .. (stats.loaded or 0) .. "/" .. (stats.count or "?"))
    end

    -- Wait a bit more for any final operations
    vim.defer_fn(function()
        vim.cmd("qa!")
    end, 3000)
end

-- Schedule the wait function
vim.schedule(function()
    -- First ensure all plugins are installed
    require("lazy").sync({ wait = true })
    wait_for_install()
end)
SYNCEOF

# Run neovim to sync plugins
"$NVIM_BIN" --headless -u "$BUILD_CONFIG/init.lua" -c "luafile $BUILD_ROOT/sync.lua" 2>&1 || true

# Give extra time for any remaining downloads
sleep 10

# Check what was downloaded
echo ""
echo "  Plugins downloaded:"
if [ -d "$BUILD_DATA/nvim/lazy" ]; then
    ls "$BUILD_DATA/nvim/lazy/" | wc -l | xargs echo "    Count:"

    # Copy all plugins to offline directory
    for plugin_dir in "$BUILD_DATA/nvim/lazy"/*/; do
        if [ -d "$plugin_dir" ]; then
            plugin_name=$(basename "$plugin_dir")
            cp -r "$plugin_dir" "$OFFLINE_DIR/lazy-plugins/"
            # Remove .git to save space
            rm -rf "$OFFLINE_DIR/lazy-plugins/$plugin_name/.git"
            echo "    $plugin_name"
        fi
    done
else
    echo -e "${RED}    Warning: No plugins directory found${NC}"
fi

# Copy LazyVim core if it was downloaded separately
if [ -d "$BUILD_DATA/nvim/lazy/LazyVim" ]; then
    echo "  LazyVim core copied"
fi

# Cleanup
rm -rf "$BUILD_ROOT"

# ============================================
# 4. Build Treesitter parsers (optional)
# ============================================
echo ""
echo -e "${YELLOW}[4/5] Building components...${NC}"

if [ "$BUILD_TREESITTER" = true ]; then
    echo ""
    echo -e "${GREEN}Building Treesitter parsers...${NC}"

    PARSER_DIR="$OFFLINE_DIR/treesitter/linux-x64"
    mkdir -p "$PARSER_DIR"

    # Ensure tree-sitter CLI is available
    if ! command -v tree-sitter &> /dev/null; then
        echo "  Installing tree-sitter CLI..."
        if ! command -v cargo &> /dev/null; then
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable 2>&1
            export PATH="$HOME/.cargo/bin:$PATH"
        fi
        # libclang is required by tree-sitter-cli's bindgen dependency
        if ! dpkg -s libclang-dev &> /dev/null 2>&1; then
            apt-get update && apt-get install -y libclang-dev 2>&1 || true
        fi
        cargo install tree-sitter-cli 2>&1
        echo "  $(tree-sitter --version)"
    fi

    # Create build environment
    BUILD_ROOT=$(mktemp -d)
    BUILD_CONFIG="$BUILD_ROOT/config/nvim"
    BUILD_DATA="$BUILD_ROOT/data"

    mkdir -p "$BUILD_CONFIG" "$BUILD_DATA/nvim/site/pack/dist/start"

    # Copy nvim-treesitter plugin
    if [ -d "$OFFLINE_DIR/lazy-plugins/nvim-treesitter" ]; then
        cp -r "$OFFLINE_DIR/lazy-plugins/nvim-treesitter" "$BUILD_DATA/nvim/site/pack/dist/start/"
    fi

    # Create init.lua for treesitter build
    cat > "$BUILD_CONFIG/init.lua" << 'TSEOF'
local ts_dir = vim.env.TS_PLUGIN_DIR
if ts_dir and ts_dir ~= "" then
    vim.opt.rtp:prepend(ts_dir)
end

local parser_str = vim.env.PARSERS_TO_INSTALL or ""
local parsers = {}
for parser in string.gmatch(parser_str, "([^,]+)") do
    table.insert(parsers, vim.trim(parser))
end

vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
        for _, parser in ipairs(parsers) do
            print("Installing: " .. parser)
            local ok, err = pcall(vim.cmd, "TSInstall " .. parser)
            if not ok then
                print("  Error: " .. tostring(err))
            end
        end

        vim.defer_fn(function()
            print("Install wait complete, exiting.")
            vim.cmd("q!")
        end, 120000)
    end,
})
TSEOF

    echo "  Installing parsers: ${PARSERS//,/, }"

    XDG_CONFIG_HOME="$BUILD_ROOT/config" \
    XDG_DATA_HOME="$BUILD_ROOT/data" \
    PARSERS_TO_INSTALL="$PARSERS" \
    TS_PLUGIN_DIR="$BUILD_DATA/nvim/site/pack/dist/start/nvim-treesitter" \
    "$NVIM_BIN" --headless 2>&1 || true

    # Find and copy compiled parsers
    find "$BUILD_ROOT" -name "*.so" -type f | while read -r sofile; do
        cp "$sofile" "$PARSER_DIR/" 2>/dev/null || true
    done

    FINAL_COUNT=$(ls -1 "$PARSER_DIR"/*.so 2>/dev/null | wc -l)
    if [ "$FINAL_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}Built $FINAL_COUNT parsers${NC}"
    else
        echo -e "  ${YELLOW}Warning: No parsers were built${NC}"
    fi

    rm -rf "$BUILD_ROOT"
fi

# ============================================
# 5. Build Mason LSP servers (optional)
# ============================================

if [ "$BUILD_MASON" = true ]; then
    echo ""
    echo -e "${GREEN}Building Mason LSP servers...${NC}"

    MASON_DIR="$OFFLINE_DIR/mason"
    mkdir -p "$MASON_DIR"

    BUILD_ROOT=$(mktemp -d)
    BUILD_CONFIG="$BUILD_ROOT/config/nvim"
    BUILD_DATA="$BUILD_ROOT/data"

    mkdir -p "$BUILD_CONFIG" "$BUILD_DATA/nvim/site/pack/dist/start"

    # Copy mason plugin
    if [ -d "$OFFLINE_DIR/lazy-plugins/mason.nvim" ]; then
        cp -r "$OFFLINE_DIR/lazy-plugins/mason.nvim" "$BUILD_DATA/nvim/site/pack/dist/start/"
    fi

    cat > "$BUILD_CONFIG/init.lua" << 'MASONEOF'
require("mason").setup()

local function install_lsp()
    local lsp_str = vim.env.LSP_TO_INSTALL or ""
    for lsp in string.gmatch(lsp_str, "([^,]+)") do
        lsp = vim.trim(lsp)
        print("Installing: " .. lsp)
        vim.cmd("MasonInstall " .. lsp)
    end
end

vim.defer_fn(function()
    install_lsp()
    vim.defer_fn(function()
        vim.cmd("q!")
    end, 120000)
end, 1000)
MASONEOF

    echo "  Installing LSP: ${LSP_SERVERS//,/, }"

    XDG_CONFIG_HOME="$BUILD_ROOT/config" \
    XDG_DATA_HOME="$BUILD_ROOT/data" \
    LSP_TO_INSTALL="$LSP_SERVERS" \
    "$NVIM_BIN" --headless 2>&1 || true

    if [ -d "$BUILD_DATA/nvim/mason" ]; then
        cp -rv "$BUILD_DATA/nvim/mason" "$OFFLINE_DIR/"
        echo -e "  ${GREEN}Mason LSP servers installed${NC}"
    fi

    rm -rf "$BUILD_ROOT"
fi

# ============================================
# Create archive
# ============================================
echo ""
echo -e "${YELLOW}[5/5] Creating archive...${NC}"

# Copy install.sh into the package
cp "$SCRIPT_DIR/install.sh" "$OFFLINE_DIR/"

cd "$SCRIPT_DIR"
tar -czvf lazyvim-offline.tar.gz lazyvim-offline/

SIZE=$(du -h lazyvim-offline.tar.gz | cut -f1)

# Summary
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Build complete!${NC}"
echo ""
echo "  Output: $SCRIPT_DIR/lazyvim-offline.tar.gz"
echo "  Size: $SIZE"
echo ""
echo "  Contents:"
echo "    - Neovim binary ($(ls "$OFFLINE_DIR/nvim/linux-x64/bin/" 2>/dev/null | head -1 || echo 'N/A'))"
echo "    - LazyVim starter config"
echo "    - $(ls -1 "$OFFLINE_DIR/lazy-plugins" 2>/dev/null | wc -l) plugins"
if [ -d "$OFFLINE_DIR/treesitter" ]; then
    echo "    - $(ls -1 "$OFFLINE_DIR/treesitter/linux-x64"/*.so 2>/dev/null | wc -l) Treesitter parsers"
fi
if [ -d "$OFFLINE_DIR/mason" ]; then
    echo "    - Mason LSP servers"
fi
echo ""
echo "Transfer to offline machine and run:"
echo "  tar -xzf lazyvim-offline.tar.gz"
echo "  cd lazyvim-offline"
echo "  ./install.sh"
echo -e "${GREEN}============================================${NC}"
