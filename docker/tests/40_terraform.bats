#!/usr/bin/env bats
load 'test_helper/common.bash'

# bats file_tags=terraform

@test "Terraform via tenv works" {
  run tenv tf list
  assert_success
}

@test "TFLint Installed" { check_binary tflint; }

@test "terraform-docs Installed" { check_binary terraform-docs; }

@test "terraform-config-inspect Installed" {
  run terraform-config-inspect --json
  assert_success
}

@test "OpenTofu via tenv works" {
  run tenv tofu list
  assert_success
}

@test "tofu version runs" {
  run tofu -version
  assert_success
}


@test "tenv login profile is installed, parses, and keeps tenv's PATH entries (INFIAAS-11916)" {
  run bash -n /etc/profile.d/tenv.sh
  assert_success
  run bash -lc 'command -v terraform && command -v tofu'
  assert_success
}
