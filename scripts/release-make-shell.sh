#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export PATH='/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin'
export LC_ALL=C
unset CDPATH

# GNU Make 3.81 on macOS records `.SHELLFLAGS` but does not reliably protect
# its initial recipe-shell startup from BASH_ENV. This fixed shebang boundary
# is therefore the Make SHELL executable; it then starts the requested recipe
# in a fresh privileged Bash process.
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
  /bin/bash -p "$@"
