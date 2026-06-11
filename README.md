# gcsproxy

Reverse proxy for Google Cloud Storage.

This is a fork of [daichirata/gcsproxy](https://github.com/daichirata/gcsproxy)
that adds a [Bazel](https://bazel.build/) (bzlmod) build and a Bazel-native
container image. `main.go` / `main_test.go` are kept in sync with upstream.

## Description

A reverse proxy for Google Cloud Storage that performs limited disclosure (IP
allowlists, basic auth, etc.) in front of private buckets. It fetches objects
through the GCS storage API and streams them over HTTP, so objects can stay
private while an upstream (e.g. nginx) enforces access control.

```
 +---------------------------------------+
 |                Nginx                  |
 |    access control (basic auth/ip)     |
 +-----+---------------------------------+
       |
-----------------------------------------+
       |
       |
+------v-----+          +---------------+
|            |          |               |
|  gcsproxy  | +------> | Google Cloud  |
|            |          |    Storage    |
+------------+          +---------------+
```

See the [upstream README](https://github.com/daichirata/gcsproxy#readme) for the
full feature set and behavior; the proxy code is kept in sync with it.

## Build

Two build systems are kept in sync; Bazel is the canonical CI build.

```bash
# Plain Go
go build -o gcsproxy .

# Bazel (bzlmod)
bazel build //:gcsproxy
bazel run //:gcsproxy
```

Run the tests with:

```bash
bazel test //:gcsproxy_test
```

## Container image

The image is built entirely by Bazel via
[`rules_oci`](https://github.com/bazel-contrib/rules_oci) — there is no
Dockerfile. A static `linux/amd64` binary is layered onto
`gcr.io/distroless/static-debian13` (pinned by digest in `MODULE.bazel`), with
entrypoint `/gcsproxy` and default `CMD ["-b", "0.0.0.0:80"]`.

```bash
bazel build //:image     # build the OCI image
bazel run //:load        # load it into the local Docker daemon as gcsproxy:latest

docker run --rm -p 8080:80 \
  -v /path/to/keyfile.json:/keyfile.json:ro \
  gcsproxy:latest -c /keyfile.json
```

## Usage

```
Usage of gcsproxy:
  -b string              Bind address (default "127.0.0.1:8080")
  -bucket string         Fixed bucket name; disables bucket extraction from the path
  -c string              Path to a service-account key file (defaults to Application Default Credentials)
  -content-length        Send the Content-Length header (disables chunked transfer)
  -cors-origin string    Value for the Access-Control-Allow-Origin header
  -i string              Default index file to serve
  -log-format string     Log output format: text or json (default "json")
  -log-level string      Minimum log level: debug, info, warn, or error (default "info")
  -not-found string      Object served with HTTP 404 for unmatched routes
  -spa                   SPA fallback: serve -i from the bucket root with HTTP 200 for unmatched routes
  -v                     Show access log
  -walk-up-index         When -i lookup misses, retry parent directories before not-found handling
```

Routes are `GET|HEAD /{bucket}/{object...}` by default, or `GET|HEAD /{object...}`
when `-bucket` is set.
