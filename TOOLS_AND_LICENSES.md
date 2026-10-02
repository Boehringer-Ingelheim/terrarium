# Tools and OSS Licenses

This file lists all tools bundled in the terrarium container image and their
open-source licenses. Consumers of this image should review these licenses for
compliance with their organization's policies.

> **Last updated:** 2026-07-24 (reviewed under INFIAAS-11426; `latest` rows
> reflect tools installed unpinned — pyenv/uv and the
> dnf-repo/installer CLIs — and remain accurate)
> For a machine-readable SBOM, see the BuildKit SBOM attestation attached to
> published images (`--sbom=true`), or generate one locally with
> `make sbom` (requires [Syft](https://github.com/anchore/syft)).
>
> Please also see the [Maintenance](#maintenance) section at the end of this file for instructions on how to keep this inventory up to date when making changes to the Dockerfile or OS packages etc.

---

## Core Languages & Runtimes

| Tool | Version | License | Source |
|------|---------|---------|--------|
| Python | 3.13.15 (via pyenv) | [PSF-2.0](https://docs.python.org/3/license.html) | github.com/pyenv/pyenv → python.org |
| Go | 1.26.8 | [BSD-3-Clause](https://go.dev/LICENSE) | go.dev |
| Node.js | 24.21.0 | [MIT](https://github.com/nodejs/node/blob/main/LICENSE) | nodejs.org |
| npm | 11.20.0 (pinned over the Node-bundled npm) | [Artistic-2.0](https://github.com/npm/cli/blob/latest/LICENSE) | registry.npmjs.org |

## Version Managers

| Tool | Version | License | Source |
|------|---------|---------|--------|
| pyenv | latest (git clone) | [MIT](https://github.com/pyenv/pyenv/blob/master/LICENSE) | github.com/pyenv/pyenv |
| tenv | 4.15.1 | [Apache-2.0](https://github.com/tofuutils/tenv/blob/main/LICENSE) | github.com/tofuutils/tenv |
| uv | latest (install script) | [Apache-2.0](https://github.com/astral-sh/uv/blob/main/LICENSE-APACHE) | astral.sh/uv |

## Infrastructure as Code

| Tool | Version | License | Source |
|------|---------|---------|--------|
| Terraform | 1.16.4 (via tenv; the default — tenv installs any other version on demand) | [BUSL-1.1](https://github.com/hashicorp/terraform/blob/main/LICENSE) | releases.hashicorp.com |
| OpenTofu | 1.13.1 (via tenv) | [MPL-2.0](https://github.com/opentofu/opentofu/blob/main/LICENSE) | opentofu.org |
| Packer | 1.16.1 | [BUSL-1.1](https://github.com/hashicorp/packer/blob/main/LICENSE) | releases.hashicorp.com |
| terraform-docs | v0.24.0 | [MIT](https://github.com/terraform-docs/terraform-docs/blob/master/LICENSE) | github.com/terraform-docs/terraform-docs |
| tflint | 0.64.0 | [MPL-2.0](https://github.com/terraform-linters/tflint/blob/master/LICENSE) | github.com/terraform-linters/tflint |

## Cloud CLIs

| Tool | Version | License | Source |
|------|---------|---------|--------|
| AWS CLI v2 | latest (installer) | [Apache-2.0](https://github.com/aws/aws-cli/blob/v2/LICENSE.txt) | awscli.amazonaws.com |
| AWS SAM CLI | latest (installer/pip) | [Apache-2.0](https://github.com/aws/aws-sam-cli/blob/develop/LICENSE) | github.com/aws/aws-sam-cli |
| AWS CDK | 2.1024.0 (npm) | [Apache-2.0](https://github.com/aws/aws-cdk/blob/main/LICENSE) | npm (aws-cdk) |
| Azure CLI | latest (dnf repo) | [MIT](https://github.com/Azure/azure-cli/blob/dev/LICENSE) | packages.microsoft.com |
| GCP CLI (gcloud) | latest (dnf repo) | [Apache-2.0](https://cloud.google.com/sdk/docs/install) | packages.cloud.google.com |
| OpenStack CLI | 7.1.5 (pip venv) | [Apache-2.0](https://github.com/openstack/python-openstackclient/blob/master/LICENSE) | pypi.org |
| OpenStack Barbican client | 7.3.0 (pip venv) | [Apache-2.0](https://github.com/openstack/python-barbicanclient/blob/master/LICENSE) | pypi.org |

## Kubernetes & Container Tools

| Tool | Version | License | Source |
|------|---------|---------|--------|
| kubectl | 1.35.9 | [Apache-2.0](https://github.com/kubernetes/kubectl/blob/master/LICENSE) | dl.k8s.io |
| Helm | 3.22.0 | [Apache-2.0](https://github.com/helm/helm/blob/main/LICENSE) | get.helm.sh |
| OpenShift CLI (oc) | 4.19.48 | [Apache-2.0](https://github.com/openshift/oc/blob/master/LICENSE) | mirror.openshift.com |

## Security & Secrets

| Tool | Version | License | Source |
|------|---------|---------|--------|
| Trivy | 0.75.0 | [Apache-2.0](https://github.com/aquasecurity/trivy/blob/main/LICENSE) | github.com/aquasecurity/trivy |
| sops | 3.13.3 | [MPL-2.0](https://github.com/getsops/sops/blob/main/LICENSE) | github.com/getsops/sops |
| age | 1.3.2 | [BSD-3-Clause](https://github.com/FiloSottile/age/blob/main/LICENSE) | github.com/FiloSottile/age |

## Shell & Utilities

| Tool | Version | License | Source |
|------|---------|---------|--------|
| Starship | 1.24.2 | [ISC](https://github.com/starship/starship/blob/master/LICENSE) | starship.rs |
| zoxide | 0.9.9 | [MIT](https://github.com/ajeetdsouza/zoxide/blob/main/LICENSE) | github.com/ajeetdsouza/zoxide |
| yq | 4.54.1 | [MIT](https://github.com/mikefarah/yq/blob/master/LICENSE) | github.com/mikefarah/yq |
| Task (go-task) | 3.54.0 | [MIT](https://github.com/go-task/task/blob/main/LICENSE) | taskfile.dev |
| jq | dnf | [MIT](https://github.com/jqlang/jq/blob/master/COPYING) | dnf (EPEL) |
| GNU Parallel | dnf | [GPL-3.0-or-later](https://www.gnu.org/software/parallel/) | dnf (EPEL) |
| nano | dnf (default `EDITOR`; replaces vi/vim-minimal) | [GPL-3.0-or-later](https://www.nano-editor.org/) | dnf (UBI 9) |
| xorriso | buildlang stage | [GPL-2.0-or-later](https://www.gnu.org/software/xorriso/) | dnf (Rocky Linux CRB) |

## Testing Frameworks

| Tool | Version | License | Source |
|------|---------|---------|--------|
| bats-core | 1.13.0 | [MIT](https://github.com/bats-core/bats-core/blob/master/LICENSE.md) | github.com/bats-core/bats-core |

## Python Packages (via uv)

The following packages are installed via `pyproject.toml` / `uv.lock`:

| Package | License | Source |
|---------|---------|--------|
| boto3 / botocore (~> 1.39) | Apache-2.0 | pypi.org |
| pre-commit (~> 4.2) | MIT | pypi.org |
| requests (~> 2.32) | Apache-2.0 | pypi.org |
| python-hcl2 (~> 2.0) | MIT | pypi.org |
| pipenv (~> 2024.0) | MIT | pypi.org |
| pycodestyle (~> 2.14) | MIT | pypi.org |
| simplejson (~> 3.19) | MIT / Academic Free License | pypi.org |
| virtualenv (~> 20.32) | MIT | pypi.org |

> For the complete list of transitive Python dependencies and their licenses,
> inspect `docker/uv.lock` or run `uv pip list --format columns` inside the container.

## Base Image & OS Packages

| Component | Details |
|-----------|---------|
| Base image | `registry.access.redhat.com/ubi9/ubi:9.8` (Red Hat Universal Base Image 9) |
| Build stage | `docker.io/rockylinux/rockylinux:9.8` (Rocky Linux 9 — RHEL-compatible, BSD-licensed) |
| OS packages | Installed via `dnf` — RPM packages follow their individual upstream licenses (primarily GPL-2.0, LGPL, MIT, BSD) |
| EPEL | Fedora Extra Packages for Enterprise Linux 9 |

---

## Verification Status

All binary-downloaded tools are cryptographically verified unless noted:

| Tool | Verification | Notes |
|------|-------------|-------|
| Terraform, Packer | GPG-signed SHA256SUMS | HashiCorp PGP key pinned |
| AWS CLI v2 | GPG detached signature | AWS release key pinned |
| Node.js | GPG-signed SHASUMS256.txt | nodejs/release-keys keyring |
| Go | SHA256 checksum | go.dev checksums / JSON index |
| kubectl | SHA256 checksum file | dl.k8s.io |
| Helm | SHA256 checksum file | get.helm.sh |
| Starship | Per-file .sha256 | GitHub releases |
| tflint | SHA256 checksums.txt | GitHub releases |
| Trivy | SHA256 checksums.txt | GitHub releases |
| age | SHA256 checksums (multi-strategy) | GitHub releases |
| Azure CLI | RPM GPG key | Microsoft repo signing key |
| GCP CLI | RPM GPG key | Google Cloud repo signing key |
| sops | RPM package | GitHub releases |
| tenv | SHA256 checksums.txt | GitHub releases (RPM) |
| zoxide | **Not verified** | Upstream publishes no checksums |
| yq | **Not verified** | Direct binary download |
| terraform-docs | **Not verified** | Direct binary download |
| Task (go-task) | **Not verified** | Install script |
| OpenShift CLI (oc) | **Not verified** | mirror.openshift.com tarball (the mirror publishes `sha256sum.txt`; follow-up) |

---

## License Summary

| License | Count | Tools |
|---------|-------|-------|
| Apache-2.0 | 12+ | AWS CLI, AWS CDK, AWS SAM, Azure CLI (repo), GCP CLI, kubectl, Helm, oc, Trivy, tenv, uv, OpenStack |
| MIT | 9+ | Node.js, pyenv, terraform-docs, yq, zoxide, Task, bats-core, jq, Starship (ISC ≈ MIT) |
| MPL-2.0 | 3 | OpenTofu, tflint, sops |
| BUSL-1.1 | 2 | Terraform, Packer |
| BSD-3-Clause | 2 | Go, age |
| PSF-2.0 | 1 | Python |
| GPL-2.0+ / GPL-3.0+ | 3 | xorriso, GNU Parallel, nano |
| ISC | 1 | Starship |

> **Note on BUSL-1.1 (Business Source License):** Terraform and Packer use the
> HashiCorp Business Source License. This license permits most non-production and
> production use but restricts offering a competing hosted service. Review the
> [BUSL-1.1 FAQ](https://www.hashicorp.com/license-faq) for your use case.
> OpenTofu (MPL-2.0) is available as a permissively-licensed alternative.

---

## Maintenance

This file should be updated whenever tools are added, removed, or upgraded in
`docker/Dockerfile.terrarium`. Use the following prompt with an AI coding
assistant (e.g. Claude Code) to regenerate or verify the inventory:

<details>
<summary>Update prompt</summary>

```text
Read docker/Dockerfile.terrarium and TOOLS_AND_LICENSES.md. For every tool
installed in the Dockerfile (via ARG/ENV versions, dnf, binary download, pip,
npm, or git clone):

1. Check it appears in TOOLS_AND_LICENSES.md with the correct version.
2. Verify the SPDX license identifier is accurate (check the tool's repo).
3. Check the Verification Status table matches how the tool is actually
   verified in the Dockerfile (GPG, SHA256, RPM key, or not verified).
4. Update the License Summary counts.
5. If a tool was removed from the Dockerfile, remove it from this file.
6. If a tool was added to the Dockerfile, add it to the appropriate section.

Also cross-reference docker/pyproject.toml for Python package changes.

Output a diff of any changes needed, or confirm the file is up to date.
```

</details>

For a machine-readable cross-check, run `make sbom` (requires
[Syft](https://github.com/anchore/syft)) and compare the output against this
file. Syft reliably detects OS/language packages but misses most
binary-downloaded tools — this file is the authoritative source for those.
