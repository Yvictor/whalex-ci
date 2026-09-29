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
meta_file="$(mktemp "$runner_temp/whalex-github-meta.XXXXXX")"
# Optional workflow token for the public GitHub /meta request only. Keep it in
# a shell variable and drop it from the environment so git/ssh never see it.
meta_token="${GITHUB_API_TOKEN:-}"
unset GITHUB_API_TOKEN

cleanup() {
  if test -f "$key_file"; then
    chmod u+w "$key_file" 2>/dev/null || true
    shred -u "$key_file" 2>/dev/null || rm -f "$key_file"
  fi
  rm -f "$known_hosts_file" "$meta_file"
  meta_token=""
}
trap cleanup EXIT INT TERM

umask 077
cat >"$key_file"
# GitHub Actions secrets do not preserve a trailing newline. OpenSSH's PEM
# parser requires one, so normalize it before the key is used.
printf '\n' >>"$key_file"
chmod 0600 "$key_file"
grep -q '^-----BEGIN OPENSSH PRIVATE KEY-----$' "$key_file"
grep -q '^-----END OPENSSH PRIVATE KEY-----$' "$key_file"

# GitHub's SSH host keys come from the public /meta endpoint. Anonymous calls
# from hosted runners share a per-IP rate limit and intermittently get 403/429,
# so send the workflow token when the step provides one (only to
# api.github.com, via a curl config on a pipe rather than argv) and retry
# transient failures with bounded backoff.
meta_curl() {
  curl --proto '=https' --tlsv1.2 --silent --show-error --max-time 30 \
    --header 'Accept: application/vnd.github+json' \
    --output "$meta_file" --write-out '%{http_code}' \
    "$@" https://api.github.com/meta
}

fetch_github_meta() {
  if test -n "$meta_token"; then
    printf 'header = "Authorization: Bearer %s"\n' "$meta_token" \
      | meta_curl --config -
  else
    meta_curl </dev/null
  fi
}

meta_delays=(5 10 20)
meta_attempt=1
while :; do
  meta_status="$(fetch_github_meta)" || meta_status=000
  test "$meta_status" = 200 && break
  if test "$meta_status" = 401 && test -n "$meta_token"; then
    # A rejected token must not block a public request; continue anonymously.
    echo "GitHub meta request rejected the workflow token; retrying anonymously" >&2
    meta_token=""
    continue
  fi
  case "$meta_status" in
    000 | 403 | 429 | 5??) ;;
    *)
      echo "GitHub meta request failed with HTTP $meta_status" >&2
      exit 1
      ;;
  esac
  if test "$meta_attempt" -gt "${#meta_delays[@]}"; then
    echo "GitHub meta request failed with HTTP $meta_status after $meta_attempt attempts" >&2
    exit 1
  fi
  meta_delay="${meta_delays[$((meta_attempt - 1))]}"
  echo "GitHub meta request returned HTTP $meta_status (attempt $meta_attempt); retrying in ${meta_delay}s" >&2
  sleep "$meta_delay"
  meta_attempt=$((meta_attempt + 1))
done
meta_token=""

jq -er '.ssh_keys[]' "$meta_file" \
  | sed 's/^/github.com /' >"$known_hosts_file"
test -s "$known_hosts_file"
rm -f "$meta_file"

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
