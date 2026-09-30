#!/usr/bin/env bats
# ↳ Every pinned tool reports the version its Dockerfile ARG/ENV pins (INFIAAS-9587).
#
# Security bumps are only effective if the new binary is the one on PATH. These
# asserts read the pin from the baked-in ENV (not a hard-coded literal), so a
# version bump needs no test edit, but a stale layer, a wrong download URL or a
# PATH shadow fails here.

load 'test_helper/common.bash'

# bats file_tags=versions

@test "go matches GO_VERSION"                 { assert_pinned_version GO_VERSION go version; }
@test "tenv matches TENV_VERSION"             { assert_pinned_version TENV_VERSION tenv --version; }
@test "terraform matches TERRAFORM_VERSION"   { assert_pinned_version TERRAFORM_VERSION terraform -version; }
@test "tofu matches OPENTOFU_VERSION"         { assert_pinned_version OPENTOFU_VERSION tofu -version; }
@test "age matches AGE_VERSION"               { assert_pinned_version AGE_VERSION age --version; }
@test "age-keygen matches AGE_VERSION"        { assert_pinned_version AGE_VERSION age-keygen --version; }
@test "oc matches OC_VERSION"                 { assert_pinned_version OC_VERSION oc version --client; }
@test "trivy matches TRIVY_VERSION"           { assert_pinned_version TRIVY_VERSION trivy version; }
@test "packer matches PACKER_VERSION"         { assert_pinned_version PACKER_VERSION packer --version; }
@test "tflint matches TFLINT_VERSION"         { assert_pinned_version TFLINT_VERSION tflint --version; }
@test "terraform-docs matches TERRAFORM_DOCS_VERSION" { assert_pinned_version TERRAFORM_DOCS_VERSION terraform-docs --version; }
@test "sops matches SOPS_VERSION"             { assert_pinned_version SOPS_VERSION sops --disable-version-check --version; }
@test "helm matches HELM_VERSION"             { assert_pinned_version HELM_VERSION helm version; }
@test "task matches TASK_VERSION"             { assert_pinned_version TASK_VERSION task --version; }
@test "yq matches YQ_VERSION"                 { assert_pinned_version YQ_VERSION yq --version; }
@test "kubectl matches KUBECTL_VERSION"       { assert_pinned_version KUBECTL_VERSION kubectl version --client; }
@test "node matches NODEJS_VERSION"           { assert_pinned_version NODEJS_VERSION node --version; }
@test "npm matches NPM_VERSION"                 { assert_pinned_version NPM_VERSION npm --version; }
@test "cdk matches AWS_CDK_VERSION"           { assert_pinned_version AWS_CDK_VERSION cdk --version; }
@test "python matches PYTHON_VERSION"         { assert_pinned_version PYTHON_VERSION python --version; }
@test "starship matches STARSHIP_VERSION"     { assert_pinned_version STARSHIP_VERSION starship --version; }
@test "zoxide matches ZOXIDE_VERSION"         { assert_pinned_version ZOXIDE_VERSION zoxide --version; }
