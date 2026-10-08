# Hyphanet Docker Container

[![Build and publish image](https://github.com/fermuch/hyphanet-docker/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/fermuch/hyphanet-docker/actions/workflows/docker-publish.yml)
![GitHub License](https://img.shields.io/github/license/fermuch/hyphanet-docker)

Secure containerized deployment of Hyphanet (Freenet fork) with automatic configuration and data isolation.

## Overview

A ready-to-use Docker image for Hyphanet that:
- Automatically configures FProxy access
- Isolates all user data in persistent volumes
- Runs with non-root privileges
- Maintains secure defaults

## Features

- 🔒 Automatic security hardening
- 💾 Persistent data storage
- 🚫 Non-root operation
- 🔄 Automatic configuration
- 📦 Single-container deployment

## Getting Started

### Quick Start
```bash
docker run -d \
  --name hyphanet \
  -p 8123:8123 \
  -v hyphanet_data:/data \
  ghcr.io/fermuch/hyphanet-docker:latest
```

### Available Tags
Images are published to GitHub Container Registry by the [`Build and publish image`](.github/workflows/docker-publish.yml) workflow on every push to `main` and on `v*` tags, for `linux/amd64` and `linux/arm64`:

| Tag                 | Meaning                                          |
|---------------------|--------------------------------------------------|
| `latest`            | Latest build from `main`                         |
| `build0NNNNN`       | Pinned to a Hyphanet build (e.g. `build01507`)   |
| `sha-<short-sha>`   | Pinned to a commit                               |
| `X.Y.Z`             | Created from a `vX.Y.Z` git tag                  |

> [!NOTE]
> New GHCR packages are **private by default**. To allow anonymous pulls, set the package visibility to public in the repository's *Packages* settings.

### Accessing Hyphanet
1. Wait 2-3 minutes for initial setup
2. Open in your browser:
   ```
   http://localhost:8123
   ```

## Data Persistence
All sensitive data is stored in the Docker volume:
```bash
# List volumes
docker volume ls

# Inspect data
docker exec -it hyphanet ls /data
```

This includes `freenet.ini` (node configuration, wizard completion), `master.keys`, and the node datastore (`/data/datastore`, sized via `node.storeSize` in `freenet.ini`).

## Security Notes
- 🔐 FProxy bound to container network only by default
- 🛡️ All sensitive files stored in isolated volume
- 📜 Automatic log rotation
- ⚠️ Never expose port 8123 publicly without authentication

## Disclaimer
This project is provided as-is. The maintainer:
- ❌ Does not monitor network activity
- 🔒 Cannot access node data
- ⚖️ Bears no responsibility for content transmitted through nodes

```diff
+ Ethical Reminder: Censorship resistance requires responsible usage.
```

## Development
```bash
# Build image (Hyphanet version is defined by ARG HYPHANET_VERSION in the Dockerfile)
docker build -t hyphanet-node .

# Build a specific Hyphanet build
docker build --build-arg HYPHANET_VERSION=1507 -t hyphanet-node .

# Test locally
docker run -it --rm -p 8123:8123 hyphanet-node

# Contributing
PRs welcome at https://github.com/fermuch/hyphanet-docker
```

## Support
If you find this useful, please:
⭐ Star this repo | 🐳 Use our Docker image | 💬 Open issues for help