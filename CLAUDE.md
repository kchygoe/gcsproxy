# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A reverse proxy for Google Cloud Storage, written as a single Go file (`main.go`). It fetches GCS objects through the storage client API and serves them over HTTP, so objects can stay private while an upstream (e.g. nginx) enforces access control (IP allowlist, basic auth). See `README.md` for the intended nginx/systemd deployment topology.

The whole service is one process: a chi router maps `GET|HEAD /{bucket}/{object...}` to the `proxy` handler, which streams the object body and forwards GCS object attributes as HTTP headers (`Content-Type`, `Last-Modified`, `Cache-Control`, etc.). It honors `If-Modified-Since` (304) and passes through gzip via `ReadCompressed` when the client sends `Accept-Encoding: gzip`.

## Build & run

Two parallel build systems are kept in sync — changes to imports must be reflected in both.

```bash
# Plain Go
go build -o gcsproxy .
go run . -v                 # run with access logging

# Bazel (bzlmod — the canonical CI build)
bazel build //:gcsproxy
bazel build //:gcsproxy_linux_amd64    # cross-compiled release binary
bazel run //:gcsproxy
```

Runtime flags: `-b` bind address (default `127.0.0.1:8080`), `-c` path to a GCP keyfile (falls back to Application Default Credentials), `-v` access logging.

There are currently **no tests** in this repo (`go test ./...` finds none) and **no Makefile**.

## Bazel dependency management

- Dependencies are wired through bzlmod (`MODULE.bazel`) reading from `go.mod` via gazelle's `go_deps` extension. `third_party/go_deps.bzl` is a large generated `go_repository` list — do not hand-edit it.
- After changing imports in `main.go` or editing `go.mod`, regenerate Bazel files with gazelle rather than editing `BUILD.bazel` deps by hand:
  ```bash
  bazel run //:gazelle        # if a gazelle target exists; otherwise run the gazelle binary
  go mod tidy
  ```
- `MODULE.bazel` pins `gazelle:proto disable` for `gax-go/v2` (workaround for rules_go #3625) and `WORKSPACE.bzlmod` carries `gazelle:resolve` directives for googleapis protos. Preserve these when touching Bazel config.
- Note a deliberate version split: `go.mod` declares `go 1.19` while `MODULE.bazel` downloads Go SDK `1.20.13`. Keep both in mind when a build behaves differently between `go build` and `bazel build`.

## Conventions

- All edits to the proxy live in `main.go`. Keep imports minimal and mirror any new dependency into the Bazel graph (above).
- Object attributes are read once (`obj.Attrs`) before opening the reader; errors map through `handleError`, which translates `storage.ErrObjectNotExist` to 404 and everything else to 500.
- Dependency bumps land via Renovate (`.github/renovate.json`, `.github/workflows/renovate.yaml`) — most history is automated `chore(deps)` PRs.
