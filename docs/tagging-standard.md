# Terrarium tagging standard

One versioning scheme, applied consistently across git, container images, and the
downstream internal (Nexus) pipeline. The rule is deliberately **surface-specific**
because each surface has its own convention — but the mapping is deterministic, so
there is exactly one correct tag on each surface for a given release.

## The rule

| Surface | Format | Example |
| --- | --- | --- |
| **Git tag** (this repo) | **`v`-prefixed** semver | `v4.8.1`, `v4.8.0-pre` |
| **Container image** (GHCR) | **v-less** semver + `latest` | `4.8.1`, `4.8.1-linux-amd64`, `latest` |
| **Internal image** (Nexus, `ccg-terrarium`) | **v-less** semver (+ channel suffix) | `4.8.1`, `4.8.1-alpha` |

- Git tags keep the `v` — it is the GitHub Releases / semver-tooling convention,
  and `main.yaml` triggers on `push: tags: ["v*"]`.
- Container/registry tags drop the `v` — the OCI/GHCR convention. The transform is
  a single leading-`v` strip (`${TAG#v}`), which is exactly what
  `docker/metadata-action`'s `type=semver,pattern={{version}}` produces.

## How it is enforced (not just documented)

- **`main.yaml`** — publishes images with `type=semver,pattern={{version}}`
  (v-less) and is triggered by `v*` git tags. No operator input, so it cannot
  drift.
- **`release.yaml`** (manual `workflow_dispatch`) — normalizes deterministically
  regardless of what the operator types in the *Release tag* field:
  - git tag → `TAG="v${TAG#v}"` (always `vX.Y.Z`),
  - images → `IMAGE_TAG="${TAG#v}"` (always v-less) for the per-arch `--tag`, the
    manifest `metadata-action`, and the manifest `sources`.
  So both `v4.8.1` and `4.8.1` inputs yield git `v4.8.1` + image `4.8.1`.
- **`ccg-terrarium` `Jenkinsfile`** — resolves upstream **git** tags with the
  `^v\d+\.\d+\.\d+$` (v-prefixed) pattern, then `replaceFirst(/(?i)^v/, '')` to
  pull the **v-less** base image and push the **v-less** Nexus tag.

## Why the split (and not v-less everywhere)

Git tags without a `v` diverge from the GitHub/semver convention and would require
changing `main.yaml`'s `v*` trigger, `ccg-terrarium`'s lookup regex, and
re-tagging the existing `v*` history. The v-git / v-less-image split is the
industry norm and needs none of that — the whole difference is one deterministic
`v`-strip at publish time.

## Adding a new release

1. Cut the release with a **`v`-prefixed** tag (e.g. `v4.9.0`) — via a `v*` git
   tag push (drives `main.yaml`) or the *Release terrarium (manual)* workflow
   (enter `v4.9.0`; a bare `4.9.0` is normalized to the same result).
2. Verify the published image is **v-less**: `ghcr.io/boehringer-ingelheim/terrarium:4.9.0`
   (+ `latest` for non-pre-releases).
3. `ccg-terrarium` resolves `v4.9.0`, pulls `:4.9.0`, and pushes `bi-terrarium:4.9.0`.
