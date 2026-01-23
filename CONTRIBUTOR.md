---
id: CONTRIBUTOR
aliases: []
tags: []
---
# Contributing to kubectl.nvim

This guide covers local development setup and debugging tools including telemetry with Jaeger and tokio-console.

## Prerequisites

### Rust (Nightly)

Rust nightly toolchain is required for building from source:

```bash
rustup install nightly
rustup default nightly
```

### Go

Go 1.24.0 or higher is required for the FFI bridge:

```bash
# Check your version
go version

# Install via https://go.dev/dl/ or your package manager
```

### Lua Tools (Optional)

For linting and formatting Lua code:

```bash
# Install luacheck
luarocks install luacheck

# Install stylua (Rust-based formatter)
cargo install stylua

# Install lua-language-server for type checking
# See: https://github.com/LuaLS/lua-language-server
```

## Building

### Build Commands

| Command | Description | Telemetry |
|---------|-------------|-----------|
| `make build_dev` | Debug build with telemetry | Yes |
| `make clean` | Remove build artifacts | N/A |

This enables:
- Debug symbols
- OpenTelemetry tracing to Jaeger
- tokio-console integration

### Code Quality

Run all Lua checks before committing:

```bash
make check
```

Individual checks:
```bash
make llscheck   # Type checking
make luacheck   # Linting
make stylua     # Format checking
```

## Telemetry Setup

The telemetry build (`build_dev` or `build_release`) includes:
- **OpenTelemetry**: Distributed tracing with OTLP export
- **tokio-console**: Async runtime introspection
- **File logging**: Detailed logs to `kubectl.log`

### Jaeger Setup

Jaeger collects and visualizes distributed traces.

**1. Start Jaeger with Docker:**

```bash
docker run -d --name jaeger \
  -p 16686:16686 \
  -p 4317:4317 \
  jaegertracing/all-in-one:latest
```

Port mappings:
- `16686`: Jaeger UI

**2. Build with telemetry:**

```bash
make build_dev
```

**3. Start Neovim and use the plugin normally.**

**4. View traces:**

Open http://localhost:16686 and select service `kubectl.nvim`.

### tokio-console Setup

tokio-console provides real-time insight into Tokio async tasks and resources.

**1. Install tokio-console:**

```bash
cargo install tokio-console
```

**2. Build with telemetry:**

```bash
make build_dev
```

**3. Start the console subscriber:**

When the plugin initializes with a telemetry build, it starts a console server on port `6669`.

**4. Connect tokio-console:**

```bash
tokio-console http://127.0.0.1:6669
```

You'll see:
- Active async tasks
- Task poll times and waker counts
- Resource utilization (timers, I/O)
- Task history and state transitions

**Environment Variables:**

tokio-console respects `TOKIO_CONSOLE_*` environment variables:

```bash
# Custom port
TOKIO_CONSOLE_BIND=127.0.0.1:9999 nvim
```

### Log Files

Logs are written to Neovim's log directory:

```bash
# Find your log directory
nvim --headless -c 'echo stdpath("log")' -c 'q'

# Typical locations:
# macOS: ~/.local/state/nvim/
# Linux: ~/.local/state/nvim/

# View logs
tail -f ~/.local/state/nvim/kubectl.log
```

## Local Development

After cloning the repo, build and use the plugin with your normal Neovim config:

```bash
git clone https://github.com/Ramilito/kubectl.nvim.git
cd kubectl.nvim
make build_dev
```

Your plugin manager should point to the local path. Changes take effect after rebuilding.

## Testing

No automated test suite. For minimal reproduction testing (to verify no conflicts with other plugins):

```bash
nvim -u repro.lua
```

The `repro.lua` file provides a clean Neovim environment with only kubectl.nvim loaded. Use this when isolating issues, not for regular development.

## Workflow

1. Make changes
2. Build: `make build_dev`
3. Test with your normal Neovim config
4. Check code quality: `make check`
5. View traces in Jaeger if debugging async behavior
6. Use tokio-console for runtime introspection

## Troubleshooting

### Port already in use (tokio-console)

If you see errors about port 6669, a previous Neovim instance may not have shut down cleanly:

```bash
# Find the process
lsof -i :6669

### No traces in Jaeger

1. Verify Jaeger is running: `docker ps | grep jaeger`
2. Verify you built with telemetry: `make build_dev`
3. Check the OTLP endpoint is reachable: `curl -v http://localhost:4317`

### Build failures

```bash
# Clean and rebuild
make clean
make build_dev

# Ensure nightly toolchain
rustup default nightly

# Check Go version
go version  # Should be 1.24.0+
```
