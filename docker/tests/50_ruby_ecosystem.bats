#!/usr/bin/env bats
load 'test_helper/common.bash'

# bats file_tags=ruby

@test "rbenv lists expected versions" {
  run rbenv versions --bare
  assert_success
}

@test "Default Ruby version" {
  run ruby -e 'print RUBY_VERSION'
  assert_success
}

@test "Bundler present" {
  run bundler --version
  assert_success
}

# bats test_tags=kitchen, slow
@test "Kitchen CLI" { check_binary kitchen; }

# bats test_tags=cinc_auditor, slow
@test "Cinc Auditor CLI" {
  # Fail fast if the binary is missing
  check_binary cinc-auditor

  # Verify that it runs and returns 0
  run cinc-auditor version
  assert_success
}


@test "Kitchen and Cinc Auditor shims are resolvable from PATH (no manual chown needed)" {
  run bash -lc 'command -v kitchen && command -v cinc-auditor'
  assert_success
}

# INFIAAS-11916: gem-vendored CA bundles are symlinks to the system trust store
# (docker/files/bin/link_system_ca_bundle). 15_ca_distrust.bats checks the
# bundles' content; this checks the wiring and that the gems still load.
@test "gem-vendored CA bundles point at the system trust store" {
  local n=0 f
  for f in /opt/bundle/ruby/*/gems/aws-sdk-core-*/ca-bundle.crt \
           /opt/bundle/ruby/*/gems/excon-*/data/cacert.pem \
           /opt/bundle/ruby/*/gems/httpclient-*/lib/httpclient/cacert.pem \
           /opt/bundle/ruby/*/gems/httpclient-*/lib/httpclient/cacert1024.pem \
           /opt/bundle/ruby/*/gems/ms_rest-*/ca-cert.pem; do
    [ -e "$f" ] || fail "missing (unmatched glob): $f"
    [ -L "$f" ] || fail "not a symlink: $f"
    [ "$(readlink "$f")" = /etc/pki/tls/certs/ca-bundle.crt ] || fail "$f -> $(readlink "$f")"
    n=$((n + 1))
  done
  [ "$n" -ge 5 ] || fail "only $n bundles checked"
}

@test "gems with a relinked CA bundle still load (excon, httpclient, aws-sdk-core)" {
  run env BUNDLE_GEMFILE=/opt/terrarium-gems/Gemfile BUNDLE_PATH=/opt/bundle \
    bundle exec ruby -e 'require "excon"; require "httpclient"; require "aws-sdk-core"; HTTPClient.new; puts "ok"'
  assert_success
  assert_output --partial "ok"
}
