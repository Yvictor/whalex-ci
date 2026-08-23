#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: private-source-git.sh checkout <sha> <target> | resolve-main" >&2
  exit 64
}

operation="${1:-}"
shift || true

runner_temp="${RUNNER_TEMP:?RUNNER_TEMP is required}"
key_file="$(mktemp "$runner_temp/whalex-source-key.XXXXXX")"
known_hosts_file="$(mktemp "$runner_temp/whalex-known-hosts.XXXXXX")"

cleanup() {
  if test -f "$key_file"; then
    chmod u+w "$key_file" 2>/dev/null || true
    shred -u "$key_file" 2>/dev/null || rm -f "$key_file"
  fi
  rm -f "$known_hosts_file"
}
trap cleanup EXIT INT TERM

umask 077
cat >"$key_file"
chmod 0600 "$key_file"
grep -q '^-----BEGIN OPENSSH PRIVATE KEY-----$' "$key_file"
grep -q '^-----END OPENSSH PRIVATE KEY-----$' "$key_file"

curl --proto '=https' --tlsv1.2 --fail --silent --show-error \
  https://api.github.com/meta \
  | jq -er '.ssh_keys[]' \
  | sed 's/^/github.com /' >"$known_hosts_file"
test -s "$known_hosts_file"

ssh_command="ssh -i $key_file -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts_file"
repository='git@github.com:Yvictor/whalex.git'

case "$operation" in
  resolve-main)
    GIT_SSH_COMMAND="$ssh_command" git ls-remote "$repository" refs/heads/main \
      | awk 'NR == 1 { print $1 }'
    ;;
  checkout)
    source_sha="${1:-}"
    target="${2:-}"
    [[ "$source_sha" =~ ^[0-9a-f]{40}$ ]] || usage
    test -n "$target" || usage
    test ! -e "$target"
    git init --quiet "$target"
    git -C "$target" remote add origin "$repository"
    GIT_SSH_COMMAND="$ssh_command" git -C "$target" fetch \
      --no-tags --depth=2 origin "$source_sha"
    resolved_sha="$(git -C "$target" rev-parse FETCH_HEAD)"
    test "$resolved_sha" = "$source_sha"
    git -C "$target" checkout --quiet --detach FETCH_HEAD
    git -C "$target" remote remove origin
    test -z "$(git -C "$target" remote)"
    ;;
  *)
    usage
    ;;
esac

cleanup
trap - EXIT INT TERM
