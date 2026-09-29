# Security Policy

This project builds a **developer container** (Dev Container / Docker image) with a curated toolchain (e.g., Terraform, cloud CLIs, Packer, sops/age, Ruby, kubectl/helm). It is **not a production service**. Please report vulnerabilities privately and follow coordinated disclosure so users have time to update.

## Reporting a Vulnerability

**Preferred:** Use GitHub’s “Report a vulnerability” (Security → Report a vulnerability) so we can triage and discuss privately.

When you report, please include:

- Affected version(s): commit SHA, tag, and if applicable the **container image tag & digest**.
- Environment: host OS, Docker/Podman version, Dev Container/VS Code version.
- Repro steps or PoC and expected vs. actual behavior.
- Impact assessment (what can an attacker do?) and suggested severity (CVSS if you have one).
- Any logs or `docker inspect` details that help us reproduce safely.

We’ll acknowledge your report within **3 business days**, provide a triage decision within **7 days**, and share fix/mitigation timelines (see below). If your report is out of scope (see “Scope”), we’ll try to point you to the right place.

## Coordinated Disclosure

We follow responsible/coordinated disclosure:

- We’ll collaborate with you privately to validate, fix, and test.
- We’ll publish a **GitHub Security Advisory** and CHANGELOG notes when a fix or mitigation is available.
- **Disclosure window:** up to **90 days** from triage, or earlier if a fix/workaround is released. For actively exploited issues, we may publish mitigations earlier.

If you need a public credit, let us know your preferred attribution.

## Scope

**In scope**

- This repository’s source (Dockerfiles, scripts, CI).
- Any container images published by this repository (if/when published).
- Configuration in `.devcontainer` examples.

**Out of scope**

- Vulnerabilities that only affect **upstream** projects or base images (please report to those projects).
- Purely informational scanner output without a concrete exploit or impact.
- Denial‑of‑service that requires unrealistic resources, social engineering, or physical access.
- Issues that require already‑compromised developer credentials or host root access.
- Typos, UX nits, or non‑security bugs.

## Supported Versions

- We support the **default branch** and the **most recent tagged release** (if tags are used).
- Security fixes are generally only backported to the most recent minor release.
- Users should prefer the **latest image/tag** and verify by **digest**.

## How We Build & Verify

- Images are built via CI and include fast, deterministic smoke tests (Bats) to confirm key tools are present and runnable.
- We pin or constrain critical tool versions where practical and track changes in `CHANGELOG.md`.
- When applicable, we will publish a GitHub Security Advisory and, if warranted, request a CVE.

- Every published per-arch image (`master-*`, `<version>-linux-<arch>`, and the
  per-arch entries of `<version>`/`latest`) has a **signed SPDX SBOM** — see below.
- CI builds with a **pinned, digest-locked BuildKit** (`setup-buildx-action`
  `driver-opts`), enforced by `make guardrails`, so a builder change is always a
  reviewed diff.

> Roadmap (not a promise): container image signing (cosign) and SLSA build provenance.

## SBOM (Software Bill of Materials)

Each per-arch image gets a full [Syft](https://github.com/anchore/syft) SPDX
JSON SBOM, generated after push by `scripts/publish-sbom.sh` (INFIAAS-11804):

- **Attached in GHCR** to the `linux/<arch>` image digest as an OCI artifact
  (`artifactType: application/spdx+json`), via `oras attach`. GHCR has no OCI
  Referrers API, so it is stored under the referrers tag schema
  (`sha256-<digest>` tag) — `oras discover` handles this transparently.
- **Signed** keyless with cosign (GitHub OIDC, public Sigstore). Only the SBOM's
  digest is recorded in the Rekor transparency log, so SBOM size is not limited.
- **Also** uploaded as the `sbom-<arch>` workflow artifact, and attached to the
  GitHub Release as `sbom-<arch>.spdx.json` / `.txt` when a Release exists.

The SBOM is **not** a BuildKit attestation (`--sbom=true` is off: that path is
size-capped and unsigned), so `docker buildx imagetools inspect --format
'{{json .SBOM}}'` returns nothing. It never was an image layer, so image size is
unaffected either way.

Fetch and verify (needs `docker`, `jq`, [`oras`](https://oras.land), [`cosign`](https://docs.sigstore.dev)):

```bash
IMG=ghcr.io/boehringer-ingelheim/terrarium
# 1. the linux/amd64 image digest behind a tag
d=$(docker buildx imagetools inspect "$IMG:4.9.0" --raw \
      | jq -r '.manifests[] | select(.platform.os=="linux" and .platform.architecture=="amd64") | .digest')
# 2. the SBOM attached to it
s=$(oras discover --format json --artifact-type application/spdx+json "$IMG@$d" | jq -r '.referrers[0].digest')
# 3. verify the SBOM was signed by this repo's release/main workflow
cosign verify "$IMG@$s" \
  --certificate-identity-regexp '^https://github\.com/Boehringer-Ingelheim/terrarium/\.github/workflows/(main|release)\.yaml@refs/(heads|tags)/.+$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
# 4. download it
oras pull "$IMG@$s" -o sbom/
```

## Guidance for Users

This is a **developer workstation** image. To use it safely:

- **Don’t run as privileged** or with `--cap-add=SYS_ADMIN`. Avoid mounting the Docker socket into the container.
- **Use non‑root** where possible (default user if provided), and prefer **read‑only** mounts for source code.
- **Keep secrets out of images**. Mount credentials at runtime (`~/.aws`, `~/.gitconfig`, etc.) and prefer short‑lived tokens.
- **Network hygiene:** treat the container as untrusted on the network; don’t expose ports unnecessarily.
- **Update regularly:** pull the latest tag/digest, and watch releases/advisories for fixes.
- If you find a vulnerability in a **preinstalled tool** (e.g., Terraform, kubectl, sops), please also report it upstream.

## Triage & SLAs (Guidance)

- **Critical** (e.g., RCE within default workflow, credential exfiltration): hotfix ASAP; aim ≤ 7–14 days.
- **High** (priv‑esc, auth bypass with realistic preconditions): fix in ≤ 30 days.
- **Medium** (info leak, unsafe defaults with mitigations): fix in ≤ 90 days.
- **Low** (hard‑to‑exploit, minor misconfig): next routine update.

We may adjust based on exploitability and user impact.

## Hall of Fame

We’re happy to credit reporters in advisories (opt‑in). If you prefer anonymity, say so.

---

**Thank you** for helping keep developers safe. If anything here is unclear, please open a discussion or contact us privately.
