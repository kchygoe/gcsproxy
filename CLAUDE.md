# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A reverse proxy for Google Cloud Storage, written as a single Go file (`main.go`). It fetches GCS objects through the storage client API and serves them over HTTP, so objects can stay private while an upstream (e.g. nginx) enforces access control (IP allowlist, basic auth). See `README.md` for the intended nginx/systemd deployment topology.

The whole service is one process built around a `Server` struct (holds the storage client plus all flag-derived config). A `gorilla/mux` router maps `GET|HEAD /{bucket}/{object...}` (or `/{object...}` in fixed-bucket mode) to `Server.proxy`, plus a `/_health` endpoint. `proxy` streams the object body and forwards GCS object attributes as HTTP headers (`Content-Type`, `Last-Modified`, `Cache-Control`, etc.). Notable behaviors:

- Honors `If-Modified-Since` (304) and passes through gzip via `ReadCompressed` when the client sends `Accept-Encoding: gzip`.
- Serves single-range requests (`Range:` → 206 / `Content-Range`), falling back to a full 200 for gzip-stored objects (GCS transcodes them) or unparseable ranges.
- Static-site helpers: default index file (`-i`, with optional `-walk-up-index`), SPA fallback (`-spa`), and custom not-found object (`-not-found`).
- Structured logging through `log/slog` (`-log-format` text/json, `-log-level`), optional CORS (`-cors-origin`), and an optional `Content-Length` header (`-content-length`, otherwise chunked).

This is a fork of [daichirata/gcsproxy](https://github.com/daichirata/gcsproxy) that adds the Bazel build. `main.go` / `main_test.go` are kept in sync with upstream; prefer porting upstream changes verbatim over local rewrites so future re-syncs stay trivial.

## Build & run

Two parallel build systems are kept in sync — changes to imports must be reflected in both.

```bash
# Plain Go
go build -o gcsproxy .
go run . -v                 # run with access logging

# Bazel (bzlmod — the canonical CI build)
bazel build //:gcsproxy
bazel run //:gcsproxy

# Tests (table-driven, backed by fsouza/fake-gcs-server)
bazel test //:gcsproxy_test

# Container image (rules_oci — replaces the old Dockerfile)
bazel build //:image          # OCI image: static linux/amd64 on distroless/static
bazel run //:load             # load into local Docker as gcsproxy:latest
```

The image is built entirely by Bazel via `rules_oci` + `rules_pkg` — there is no Dockerfile. `//:gcsproxy_linux_amd64` is the cross-compiled static binary (`pure = "on"`), packaged into a layer at `/gcsproxy` and assembled onto `gcr.io/distroless/static-debian13` (pinned by digest in `MODULE.bazel`; entrypoint `/gcsproxy`, default CMD `-b 0.0.0.0:80`).

Runtime flags: `-b` bind address (default `127.0.0.1:8080`), `-c` GCP keyfile path (falls back to Application Default Credentials), `-v` access logging, `-bucket` fixed bucket (disables path-based bucket extraction), `-i` default index file, `-walk-up-index`, `-spa` SPA fallback, `-not-found` custom 404 object, `-cors-origin`, `-content-length`, `-log-format` (text|json), `-log-level` (debug|info|warn|error).

There is **no Makefile** and **no Dockerfile**. Tests live in `main_test.go` and run via `bazel test //:gcsproxy_test`; the container image is the `//:image` Bazel target.

## Bazel dependency management

- Dependencies are wired through bzlmod (`MODULE.bazel`) reading from `go.mod` via gazelle's `go_deps` extension. There is no `WORKSPACE` / `WORKSPACE.bzlmod` and no `third_party/` — everything is bzlmod.
- After changing imports in `main.go`/`main_test.go` or editing `go.mod`, regenerate Bazel files rather than editing `BUILD.bazel` deps by hand:
  ```bash
  go mod tidy
  bazel mod tidy          # reconcile MODULE.bazel use_repo(...) with go.mod
  bazel run //:gazelle    # regenerate go_library / go_test deps
  ```
  Caveat: the `go_library` is named `lib` (not gazelle's default `gcsproxy_lib`), so after gazelle regenerates the `go_test` target, re-point its `embed` from `:gcsproxy_lib` to `:lib`.
- `go.mod` and `MODULE.bazel` (`go_sdk.download`) both pin the same Go version (`1.25.8`); keep them aligned when bumping.

## Conventions

- All edits to the proxy live in `main.go`. Keep imports minimal and mirror any new dependency into the Bazel graph (above).
- Object attributes are read once (`obj.Attrs`) before opening the reader; errors map through `handleError`, which translates `storage.ErrObjectNotExist` to 404 and everything else to 500.
- Dependency bumps land via Renovate (`.github/renovate.json`, `.github/workflows/renovate.yaml`) — most history is automated `chore(deps)` PRs.
