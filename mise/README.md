# mise Configuration

**mise** is a polyglot version manager (like asdf, but faster and written in Rust).

## What it does

- Manages tool versions per-project (node, python, rust, go, etc.)
- Replaces nvm, pyenv, rbenv, gvm, etc. with one tool
- Supports `.tool-versions` (asdf-compatible) and `.mise.toml`
- Fast activation (~10ms vs asdf's ~100ms)
- Environment variable management per-project

## Installation

Installed via Homebrew. Shell integration added to `.zshrc`.

## Configuration Locations

- **Global config**: `~/.config/mise/config.toml` (symlinked from `~/src/dotconfig/mise/config.toml`)
- **Project config**: `.mise.toml` or `.tool-versions` in project root

## Usage

### Setting global tool versions

```bash
# Install and set global version
mise use -g node@lts
mise use -g python@3.12
mise use -g rust@stable

# List installed tools
mise list

# List available versions
mise ls-remote node
mise ls-remote python
```

### Per-project tool versions

```bash
# In your project directory
cd ~/projects/my-app

# Set project-local versions (creates .mise.toml)
mise use node@20.11.0
mise use python@3.11

# Or create .tool-versions manually (asdf-compatible)
echo "node 20.11.0" >> .tool-versions
echo "python 3.11.7" >> .tool-versions

# Install tools for project
mise install
```

### Environment variables

```bash
# Set per-project env vars in .mise.toml
mise set NODE_ENV=development
mise set DATABASE_URL=postgres://localhost/mydb

# Or edit .mise.toml directly:
[env]
NODE_ENV = "development"
DATABASE_URL = "postgres://localhost/mydb"
```

### Other commands

```bash
# Show current tool versions
mise current

# Show all config
mise config

# Update mise itself
mise self-update

# Upgrade all tools to latest
mise upgrade

# Check for problems
mise doctor

# Prune unused versions
mise prune
```

## Supported backends

mise supports multiple backends for installing tools:

- **core** - Built-in fast implementations (node, python, etc.)
- **asdf** - Compatible with asdf plugins
- **cargo** - Rust crates
- **npm** - Node packages
- **go** - Go modules
- **pipx** - Python applications
- **aqua** - Declarative tool management
- **github** - Install from GitHub releases

## Example: Replacing nvm with mise

```bash
# Old (nvm):
nvm install 20
nvm use 20

# New (mise):
mise use -g node@20

# Projects with .nvmrc still work:
# mise automatically reads .nvmrc files
```

## Tips

1. **Trust prompt**: First time you `cd` into a project with `.mise.toml`, you'll be asked to trust it. Run:
   ```bash
   mise trust
   ```

2. **Legacy files**: mise reads `.node-version`, `.ruby-version`, `.python-version`, etc.

3. **Performance**: mise activates in ~10ms. If shell startup feels slow, it's not mise.

4. **Tasks**: mise can also run project tasks (like `npm run` or `make`):
   ```toml
   [tasks.dev]
   run = "npm run dev"
   
   [tasks.test]
   run = "pytest tests/"
   ```
   Then: `mise run dev` or `mise run test`

## Migration from nvm/pyenv/etc

```bash
# Node (from nvm)
mise use -g node@$(node -v | sed 's/v//')

# Python (from pyenv)
mise use -g python@$(python --version | awk '{print $2}')

# Rust (from rustup)
mise use -g rust@stable

# Then optionally uninstall old version managers
```

## Symlink Global Config

To use this dotconfig version globally:

```bash
mkdir -p ~/.config/mise
ln -sf ~/src/dotconfig/mise/config.toml ~/.config/mise/config.toml
```

## Documentation

- Official docs: https://mise.jdx.dev
- GitHub: https://github.com/jdx/mise
- Comparison to asdf: https://mise.jdx.dev/comparison-to-asdf.html
