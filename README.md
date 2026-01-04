# quick-cleanup

[![Test Quick Cleanup](https://github.com/palmsoftware/quick-cleanup/actions/workflows/pre-main.yml/badge.svg)](https://github.com/palmsoftware/quick-cleanup/actions/workflows/pre-main.yml)

Intelligent disk space optimization for GitHub Actions runners with automatic Docker relocation.

## Why quick-cleanup?

**TL;DR**: Run this BEFORE resource-intensive operations (builds, K8s clusters, large downloads) to maximize available space with minimal overhead.

### The Problem

GitHub Actions free-tier Ubuntu runners have limited disk space (~14GB free on root partition). Building containers, running Kubernetes, or large test suites can quickly exhaust this space, causing mysterious failures.

### The Solution

quick-cleanup intelligently frees disk space and relocates Docker storage to the larger `/mnt` partition in a single, fast step.

### vs. Third-Party Actions

**jlumbroso/free-disk-space**:
- ✅ Comprehensive cleanup (can free ~34GB)
- ❌ Slow (4-5 minutes even for minimal cleanup)
- ❌ All-or-nothing approach (can't skip cleanup if space sufficient)
- ❌ Doesn't relocate Docker storage
- ✅ Best for: Maximum space recovery when time isn't critical

**quick-cleanup**:
- ✅ Fast (<1 minute for light mode, <3 minutes aggressive)
- ✅ Adaptive (auto-detects available space, skips work if unnecessary)
- ✅ Relocates Docker to /mnt automatically (unique feature)
- ✅ Pre-operation focused (runs BEFORE builds, not after)
- ✅ Best for: CI pipelines needing quick, intelligent cleanup

## Quick Start

### Zero-config usage (recommended)

```yaml
- name: Optimize disk space
  uses: palmsoftware/quick-cleanup@v0
```

This will:
1. Relocate Docker storage to /mnt partition (~11GB+ more space)
2. Auto-detect disk space and clean accordingly
3. Complete in 1-3 minutes

### Custom configuration

```yaml
- name: Aggressive cleanup
  uses: palmsoftware/quick-cleanup@v0
  with:
    cleanup-mode: aggressive
    minimum-free-space: 20
```

## How It Works

### Adaptive Cleanup (auto mode)

1. **Check available space**
   - >20GB available: Light cleanup (cache, snap, Android, Docker)
   - ≤20GB available: Aggressive cleanup (+ removes dotnet, powershell, chromium, node_modules, ghc)

2. **Relocate Docker storage**
   - Moves Docker data-root from `/` (14GB) to `/mnt` (50GB+)
   - Configures containerd to use new location
   - Validates services after restart

3. **Validate and report**
   - Shows space freed
   - Validates minimum space requirement (if set)
   - Fails fast if insufficient space after cleanup

### What Gets Cleaned

**Light mode**:
- Package cache (apt-get clean, autoremove)
- Snap packages (disabled revisions)
- Android SDK (~8GB)
- Docker images/containers/volumes
- Log files and temporary files

**Aggressive mode** (everything above plus):
- /usr/share/dotnet (~3GB)
- /usr/local/share/powershell (~1GB)
- /usr/local/share/chromium (~1GB)
- /usr/local/lib/node_modules (~1GB)
- /opt/ghc, /usr/local/.ghcup (~2GB)
- Large packages: MySQL, PostgreSQL, Firefox, Azure CLI, Google Cloud SDK

## Use Cases

### Before building Docker images

```yaml
- name: Prepare runner
  uses: palmsoftware/quick-cleanup@v0

- name: Build large image
  run: docker build -t myapp:latest .
```

### Before Kubernetes cluster setup

```yaml
- name: Optimize disk
  uses: palmsoftware/quick-cleanup@v0
  with:
    minimum-free-space: 15

- name: Create K8s cluster
  uses: palmsoftware/quick-k8s@v0
```

### Before large test suites

```yaml
- name: Free space for test artifacts
  uses: palmsoftware/quick-cleanup@v0
  with:
    cleanup-mode: light  # Fast cleanup for quick tests
```

### With OpenShift Local

```yaml
- name: Prepare for OCP
  uses: palmsoftware/quick-cleanup@v0
  with:
    cleanup-mode: aggressive
    minimum-free-space: 25

- name: Deploy OpenShift
  uses: palmsoftware/quick-ocp@v0
```

## Configuration Reference

### Inputs

| Input | Description | Default | Options |
|-------|-------------|---------|---------|
| `cleanup-mode` | Cleanup intensity | `auto` | `auto`, `light`, `aggressive`, `skip` |
| `relocate-docker` | Docker relocation strategy | `always` | `always`, `auto`, `never` |
| `docker-storage-path` | Custom Docker data-root | `/mnt/docker-storage` | Any absolute path |
| `minimum-free-space` | Required free space (GB) | `0` | Number (0 = no validation) |
| `cleanup-threshold` | Threshold for auto mode (GB) | `20` | Number |
| `remove-android` | Remove Android SDK | `true` | `true`, `false` |
| `remove-large-packages` | Remove databases, browsers, CLIs | `true` | `true`, `false` |
| `remove-docker-images` | Prune Docker images | `true` | `true`, `false` |

### Examples

**Minimal cleanup (Docker relocation only)**:
```yaml
- uses: palmsoftware/quick-cleanup@v0
  with:
    cleanup-mode: skip
```

**Custom threshold**:
```yaml
- uses: palmsoftware/quick-cleanup@v0
  with:
    cleanup-threshold: 15  # Aggressive if <15GB
```

**Enforce minimum space**:
```yaml
- uses: palmsoftware/quick-cleanup@v0
  with:
    minimum-free-space: 25  # Fail if <25GB after cleanup
```

**Conservative cleanup**:
```yaml
- uses: palmsoftware/quick-cleanup@v0
  with:
    cleanup-mode: light
    remove-android: false
    remove-large-packages: false
```

## Performance Benchmarks

Tested on ubuntu-22.04 runners:

| Mode | Time | Space Freed | Final Free Space |
|------|------|-------------|------------------|
| skip (Docker only) | ~30s | +11GB (relocation) | ~25GB |
| light | ~1m | ~15GB | ~29GB |
| aggressive | ~2.5m | ~22GB | ~36GB |

*Note: Results may vary based on runner image version and pre-installed packages*

## Platform Support

- ✅ Ubuntu 22.04 (fully tested)
- ✅ Ubuntu 24.04 (fully tested)
- ⚠️ Other Linux: May work, not tested
- ❌ macOS: Not supported (different disk layout)
- ❌ Windows: Not supported

## Limitations

- **Ubuntu-only**: Relies on apt, systemd, standard GitHub Actions runner layout
- **Root partition focus**: Optimized for standard runner disk layout (/, /mnt)
- **No undo**: Cleanup is permanent, cannot restore removed packages
- **Sudo required**: All operations require sudo access

## Best Practices

1. **Run early**: Execute as one of the first steps in your workflow
2. **Use auto mode**: Let the action decide cleanup intensity
3. **Set minimum-free-space**: For critical workflows, validate space requirements
4. **Combine with quick-k8s/quick-ocp**: Designed to work seamlessly together
5. **Monitor timing**: If cleanup is slow, consider if you need aggressive mode

## Troubleshooting

### "Docker not relocated" error

**Cause**: Target partition (/mnt) not available or has insufficient space

**Solution**:
```yaml
- uses: palmsoftware/quick-cleanup@v0
  with:
    relocate-docker: auto  # Only relocate if beneficial
```

### "Insufficient disk space" error

**Cause**: Cleanup didn't free enough space to meet minimum requirement

**Solutions**:
1. Try aggressive mode: `cleanup-mode: aggressive`
2. Reduce minimum requirement: `minimum-free-space: 10`
3. Use external cleanup action first: `jlumbroso/free-disk-space`

### apt lock errors

**Cause**: Another process is using apt (e.g., unattended-upgrades)

**Resolution**: quick-cleanup uses best-effort approach and will continue despite apt locks. Check logs for warnings but action should still succeed.

### Docker service fails to start

**Cause**: Docker relocation encountered an error

**Resolution**: quick-cleanup automatically rolls back configuration on failure. Check action logs for specific error. Set `relocate-docker: never` to skip relocation.

## Contributing

Contributions welcome! Please:
1. Run `make lint` before submitting
2. Test on ubuntu-22.04 and ubuntu-24.04
3. Update README if adding inputs
4. Add integration test for new features

## License

[Apache License 2.0](LICENSE)

## Related Projects

- [quick-k8s](https://github.com/palmsoftware/quick-k8s) - Kubernetes cluster deployment for GitHub Actions
- [quick-ocp](https://github.com/palmsoftware/quick-ocp) - OpenShift Local deployment for GitHub Actions
- [jlumbroso/free-disk-space](https://github.com/jlumbroso/free-disk-space) - Comprehensive cleanup (slower, more thorough)

## Acknowledgments

This action extracts and generalizes proven cleanup strategies from [quick-k8s](https://github.com/palmsoftware/quick-k8s) and [quick-ocp](https://github.com/palmsoftware/quick-ocp), making them available for any GitHub Actions workflow.
