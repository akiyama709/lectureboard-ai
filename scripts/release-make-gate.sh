#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export PATH='/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin'
export LC_ALL=C
unset CDPATH

# MAKEFLAGS, MFLAGS, and GNUMAKEFLAGS can request dry-run or ignored-error
# behavior before any recipe starts.  Release gates call Make only through this
# privileged entry so those inherited controls cannot turn a skipped or failed
# recipe into a successful attestation.
current_user="$(/usr/bin/id -un)" \
  || { /usr/bin/printf 'Release verification user could not be identified.\n' >&2; exit 78; }
trusted_home="$(/usr/bin/id -P "$current_user" \
  | /usr/bin/awk -F: 'NF >= 9 { print $9 }')" \
  || { /usr/bin/printf 'Release verification home could not be identified.\n' >&2; exit 78; }
[[ "$trusted_home" == /* && -d "$trusted_home" && ! -L "$trusted_home" ]] \
  || { /usr/bin/printf 'Release verification home is invalid.\n' >&2; exit 78; }

exec /usr/bin/env -i \
  HOME="$trusted_home" \
  USER="$current_user" \
  LOGNAME="$current_user" \
  TMPDIR=/private/tmp \
  PATH="$PATH" \
  LC_ALL=C \
  /usr/bin/make "$@"
