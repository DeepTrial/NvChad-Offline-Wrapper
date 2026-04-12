#!/bin/bash
# NvChad Offline Package Builder
# Run this script in an online environment to create the offline package

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE_DIR="${SCRIPT_DIR}/nvchad-offline"

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

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --treesitter [parsers]  Build Treesitter parsers (comma-separated)"
    echo "                          Default: lua,vim,vimdoc,python,javascript,typescript,json,html,css,bash"
    echo "  --mason [packages]      Build Mason LSP servers (comma-separated)"
    echo "                          Default: lua_ls"
    echo "  --all                   Build both Treesitter and Mason with defaults"
    echo "  --help                  Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Download plugins only"
    echo "  $0 --treesitter                       # Download + build default parsers"
    echo "  $0 --treesitter lua,vim,python        # Download + build specific parsers"
    echo "  $0 --mason lua_ls,pylsp               # Download + build specific LSP"
    echo "  $0 --all                              # Download + build everything"
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
        --help|-h)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

echo -e "${GREEN}=== NvChad Offline Package Builder ===${NC}"
echo ""

# Create directory structure
mkdir -p "$OFFLINE_DIR"/{lazy-plugins,starter,base-config}

# ============================================
# 1. Download lazy.nvim plugin manager
# ============================================
echo -e "${YELLOW}[1/4] Downloading lazy.nvim...${NC}"
git clone --depth 1 https://github.com/folke/lazy.nvim "$OFFLINE_DIR/lazy-plugins/lazy.nvim"
rm -rf "$OFFLINE_DIR/lazy-plugins/lazy.nvim/.git"

# ============================================
# 2. Download NvChad configs
# ============================================
echo -e "${YELLOW}[2/4] Downloading NvChad configs...${NC}"
git clone --depth 1 https://github.com/nvchad/starter "$OFFLINE_DIR/starter"
rm -rf "$OFFLINE_DIR/starter/.git"

git clone --depth 1 --branch v2.5 https://github.com/NvChad/NvChad "$OFFLINE_DIR/base-config/NvChad"
rm -rf "$OFFLINE_DIR/base-config/NvChad/.git"

# ============================================
# 3. Download plugins
# ============================================
echo -e "${YELLOW}[3/4] Downloading plugins...${NC}"

declare -A PLUGINS=(
    ["nvim-lua/plenary.nvim"]="plenary.nvim"
    ["NvChad/base46"]="base46"
    ["NvChad/ui"]="ui"
    ["nvzone/volt"]="volt"
    ["nvzone/menu"]="menu"
    ["nvzone/minty"]="minty"
    ["nvim-tree/nvim-web-devicons"]="nvim-web-devicons"
    ["lukas-reineke/indent-blankline.nvim"]="indent-blankline.nvim"
    ["nvim-tree/nvim-tree.lua"]="nvim-tree.lua"
    ["folke/which-key.nvim"]="which-key.nvim"
    ["stevearc/conform.nvim"]="conform.nvim"
    ["lewis6991/gitsigns.nvim"]="gitsigns.nvim"
    ["mason-org/mason.nvim"]="mason.nvim"
    ["neovim/nvim-lspconfig"]="nvim-lspconfig"
    ["hrsh7th/nvim-cmp"]="nvim-cmp"
    ["L3MON4D3/LuaSnip"]="LuaSnip"
    ["rafamadriz/friendly-snippets"]="friendly-snippets"
    ["windwp/nvim-autopairs"]="nvim-autopairs"
    ["saadparwaiz1/cmp_luasnip"]="cmp_luasnip"
    ["hrsh7th/cmp-nvim-lua"]="cmp-nvim-lua"
    ["hrsh7th/cmp-nvim-lsp"]="cmp-nvim-lsp"
    ["hrsh7th/cmp-buffer"]="cmp-buffer"
    ["nvim-telescope/telescope.nvim"]="telescope.nvim"
    ["nvim-treesitter/nvim-treesitter"]="nvim-treesitter"
)

for repo in "${!PLUGINS[@]}"; do
    dir="${PLUGINS[$repo]}"
    printf "  %-25s " "$dir"
    git clone --depth 1 "https://github.com/$repo" "$OFFLINE_DIR/lazy-plugins/$dir" 2>/dev/null
    rm -rf "$OFFLINE_DIR/lazy-plugins/$dir/.git"
    echo "OK"
done

# cmp-async-path from codeberg
printf "  %-25s " "cmp-async-path"
git clone --depth 1 https://codeberg.org/FelipeLema/cmp-async-path "$OFFLINE_DIR/lazy-plugins/cmp-async-path" 2>/dev/null
rm -rf "$OFFLINE_DIR/lazy-plugins/cmp-async-path/.git"
echo "OK"

# ============================================
# 4. Build Treesitter parsers
# ============================================
echo ""
echo -e "${YELLOW}[4/4] Building components...${NC}"

if [ "$BUILD_TREESITTER" = true ]; then
    echo ""
    echo -e "${GREEN}Building Treesitter parsers...${NC}"

    if ! command -v nvim &> /dev/null; then
        echo -e "${RED}Error: Neovim not found. Cannot build Treesitter parsers.${NC}"
        echo "Install Neovim or use GitHub Actions instead."
        exit 1
    fi

    PARSER_DIR="$OFFLINE_DIR/treesitter/linux-x64"
    mkdir -p "$PARSER_DIR"

    # Use a simple approach: install parsers with standard nvim config
    # Create a minimal config directory
    BUILD_CONFIG=$(mktemp -d)

    # Copy treesitter to a location it expects
    mkdir -p "$BUILD_CONFIG/pack/nvim-treesitter/start"
    cp -r "$OFFLINE_DIR/lazy-plugins/nvim-treesitter" "$BUILD_CONFIG/pack/nvim-treesitter/start/"

    cat > "$BUILD_CONFIG/init.lua" << 'LUAEOF'
-- Set parser install directory
vim.opt.runtimepath:prepend(vim.fn.stdpath("config") .. "/pack/nvim-treesitter/start/nvim-treesitter")

-- Configure treesitter to install parsers to a known location
local parser_dir = vim.fn.stdpath("data") .. "/parser"
vim.fn.mkdir(parser_dir, "p")

require("nvim-treesitter.configs").setup({
    parser_install_dir = parser_dir,
    sync_install = true,
    auto_install = false,
})
LUAEOF

    echo "  Installing parsers: ${PARSERS//,/, }"

    # Install each parser one at a time for better error visibility
    for parser in ${PARSERS//,/ }; do
        parser=$(echo "$parser" | tr -d ' ')
        echo "    Building: $parser"
        NVIM_APPNAME="nvchad-ts-build" XDG_CONFIG_HOME="$BUILD_CONFIG" \
            nvim --headless \
            "+TSInstall! $parser" \
            "+sleep 10" \
            "+q" 2>&1 || true
    done

    # Find and copy parsers
    PARSER_SRC="$HOME/.local/share/nvimchad-ts-build/parser"
    if [ -d "$PARSER_SRC" ]; then
        cp -v "$PARSER_SRC"/*.so "$PARSER_DIR/" 2>/dev/null || true
    fi

    # Also check standard location
    STD_PARSER="$BUILD_CONFIG/pack/nvim-treesitter/start/nvim-treesitter/parser"
    if [ -d "$STD_PARSER" ]; then
        cp -v "$STD_PARSER"/*.so "$PARSER_DIR/" 2>/dev/null || true
    fi

    # Count final parsers
    FINAL_COUNT=$(ls -1 "$PARSER_DIR"/*.so 2>/dev/null | wc -l)
    if [ "$FINAL_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}Built $FINAL_COUNT parsers${NC}"
        ls "$PARSER_DIR"/*.so | xargs -n1 basename
    else
        echo -e "  ${RED}Error: No parsers were built${NC}"
        echo "  This might be a gcc/tree-sitter-cli issue"
    fi

    rm -rf "$BUILD_CONFIG"
fi

# ============================================
# 5. Build Mason LSP servers
# ============================================

if [ "$BUILD_MASON" = true ]; then
    echo ""
    echo -e "${GREEN}Building Mason LSP servers...${NC}"

    if ! command -v nvim &> /dev/null; then
        echo -e "${RED}Error: Neovim not found. Cannot build Mason packages.${NC}"
        exit 1
    fi

    MASON_DIR="$OFFLINE_DIR/mason"
    mkdir -p "$MASON_DIR"

    TMP_NVIM=$(mktemp -d)
    cp -r "$OFFLINE_DIR/lazy-plugins/lazy.nvim" "$TMP_NVIM/"
    cp -r "$OFFLINE_DIR/lazy-plugins/mason.nvim" "$TMP_NVIM/"

    cat > "$TMP_NVIM/init.lua" << EOF
local lazypath = "$TMP_NVIM/lazy.nvim"
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    { "mason-org/mason.nvim", dir = "$TMP_NVIM/mason.nvim" },
}, {
    install = { missing = false },
    dev = { path = "$TMP_NVIM" }
})
require("mason").setup()
EOF

    echo "  Installing LSP: ${LSP_SERVERS//,/, }"
    NVIM_APPNAME="nvchad-build" timeout 300 nvim --headless \
        "+MasonInstall ${LSP_SERVERS//,/ }" \
        "+sleep 30" "+q" 2>&1 || true

    # Copy Mason packages
    BUILT_MASON="$HOME/.local/share/nvimchad-build/mason"
    if [ -d "$BUILT_MASON" ]; then
        cp -rv "$BUILT_MASON" "$OFFLINE_DIR/" || true
        echo -e "  ${GREEN}Mason packages installed${NC}"
    fi

    rm -rf "$TMP_NVIM"
fi

# ============================================
# Create archive
# ============================================
echo ""
echo -e "${GREEN}Creating archive...${NC}"

# Copy install.sh into the package
cp "$SCRIPT_DIR/install.sh" "$OFFLINE_DIR/"

cd "$SCRIPT_DIR"
tar -czvf nvchad-offline.tar.gz nvchad-offline/

SIZE=$(du -h nvchad-offline.tar.gz | cut -f1)

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Build complete!${NC}"
echo ""
echo "  Output: $SCRIPT_DIR/nvchad-offline.tar.gz"
echo "  Size: $SIZE"
echo ""
echo "Transfer to offline machine and run:"
echo "  ./install.sh"
echo -e "${GREEN}============================================${NC}"