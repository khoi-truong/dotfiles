#!/usr/bin/env bash
# Journaling behaviour of the git module under a throwaway HOME.
#
#   bash tests/git.sh              every case_*
#   bash tests/git.sh <case_name>  that case only
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

setup_git() {
  run_module git "$1"
}

attempts() { find "$1/.local/state/dotfiles/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort; }

case_template_dir_backed_up() {
  local h
  h="$(new_home)"
  mkdir -p "$h/.config/git/template"
  echo x >"$h/.config/git/template/x"
  setup_git "$h"
  [ -L "$h/.config/git/template" ] || return 1
  set -- "$h"/.local/state/dotfiles/backups/*/files/*/x
  [ -f "$1" ]
}

case_rerun_writes_no_journal() {
  local h before after
  h="$(new_home)"
  setup_git "$h"
  before="$(attempts "$h")"
  sleep 1
  setup_git "$h"
  after="$(attempts "$h")"
  [ "$before" = "$after" ]
}

# new_repo HOME: a fixture repo on main with a bare origin, in HOME. Signing
# stays off locally; the repo's own git/gitconfig is the global config.
new_repo() (
  h="$1"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null HOME="$h"
  git init -q --template= --bare -b main "$h/origin.git"
  git init -q --template= -b main "$h/repo"
  git -C "$h/repo" config user.name t
  git -C "$h/repo" config user.email t@example.invalid
  git -C "$h/repo" config commit.gpgsign false
  git -C "$h/repo" config tag.gpgsign false
  git -C "$h/repo" remote add origin "$h/origin.git"
  echo 1 >"$h/repo/f"
  git -C "$h/repo" add f
  git -C "$h/repo" commit -q -m one
  git -C "$h/repo" push -q -u origin main
)

# rgit HOME ARGS...: git against HOME's fixture repo with the repo's gitconfig.
rgit() {
  local h="$1"
  shift
  in_home "$h" env GIT_CONFIG_GLOBAL="${DOTFILES}/git/gitconfig" GIT_CONFIG_SYSTEM=/dev/null git -C "$h/repo" "$@"
}

remote_head() { git -C "$1/origin.git" rev-parse "$2"; }

case_amendp_refuses_default_branch() {
  local h before_head before_remote
  h="$(new_home)"
  new_repo "$h"
  git -C "$h/repo" remote set-head origin main
  echo 2 >>"$h/repo/f"
  before_head="$(git -C "$h/repo" rev-parse HEAD)"
  before_remote="$(remote_head "$h" main)"
  if rgit "$h" amendp; then return 1; fi
  grep -q 'amendp: refusing to force-push main' "${WORK}/last.out"
  [ "$(git -C "$h/repo" rev-parse HEAD)" = "$before_head" ]
  [ "$(remote_head "$h" main)" = "$before_remote" ]
}

case_amendp_refuses_without_origin_head() {
  local h before_head before_remote
  h="$(new_home)"
  new_repo "$h"
  git -C "$h/repo" remote set-head origin -d 2>/dev/null || true
  if git -C "$h/repo" symbolic-ref -q refs/remotes/origin/HEAD >/dev/null; then return 1; fi
  echo 2 >>"$h/repo/f"
  before_head="$(git -C "$h/repo" rev-parse HEAD)"
  before_remote="$(remote_head "$h" main)"
  if rgit "$h" amendp; then return 1; fi
  grep -q 'amendp: refusing to force-push main' "${WORK}/last.out"
  [ "$(git -C "$h/repo" rev-parse HEAD)" = "$before_head" ]
  [ "$(remote_head "$h" main)" = "$before_remote" ]
}

case_amendp_refuses_master_when_head_is_main() {
  local h before_head before_remote
  h="$(new_home)"
  new_repo "$h"
  git -C "$h/repo" remote set-head origin main
  git -C "$h/repo" switch -q -c master
  git -C "$h/repo" push -q -u origin master
  echo 2 >>"$h/repo/f"
  before_head="$(git -C "$h/repo" rev-parse HEAD)"
  before_remote="$(remote_head "$h" master)"
  if rgit "$h" amendp; then return 1; fi
  grep -q 'amendp: refusing to force-push master' "${WORK}/last.out"
  [ "$(git -C "$h/repo" rev-parse HEAD)" = "$before_head" ]
  [ "$(remote_head "$h" master)" = "$before_remote" ]
}

case_amendp_pushes_feature_branch() {
  local h
  h="$(new_home)"
  new_repo "$h"
  git -C "$h/repo" remote set-head origin main
  git -C "$h/repo" switch -q -c feat/x
  echo 2 >>"$h/repo/f"
  git -C "$h/repo" commit -q -am two
  git -C "$h/repo" push -q -u origin feat/x
  echo 3 >>"$h/repo/f"
  rgit "$h" amendp
  [ "$(remote_head "$h" feat/x)" = "$(git -C "$h/repo" rev-parse HEAD)" ]
}

case_tag_signing_on() {
  [ "$(git config -f "${DOTFILES}/git/gitconfig" tag.gpgSign)" = true ]
}

run_suite "$@"
