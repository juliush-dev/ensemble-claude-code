#!/usr/bin/env bash
# run-fixture.sh: the fixture for tools/herenow.sh, the Operator's here.now kit.
#
# ASCII-ONLY, LF line endings, like everything else in this deploy set.
#
# Run it by hand, from anywhere:   bash run-fixture.sh
# Exit 0 PASS, exit 1 FAIL. It writes nothing outside a temp directory it
# removes on the way out, never touches a deployed home or the host's own
# here.now skill, key or state, and never calls the network. On Windows run it
# from Git Bash: a bare 'bash' typed in PowerShell may start WSL's bash.
#
# Each case runs the kit once under env -i, so nothing of the caller's
# environment reaches it but what the case sets: HOME is a scratch home the
# fixture builds (so the key file the kit tests is a scratch one),
# CLAUDE_CONFIG_DIR a scratch config home or unset, the key variable a fixture
# value or unset, and PATH two scratch folders: wrappers for the text tools the
# kit uses, and stub curl, file and jq that answer --version and nothing else.
# The real curl is never on the kit's PATH. The skill is a stub folder whose
# scripts/publish.sh records its working directory and arguments and prints a
# URL and a publish_result line; it opens no connection. A case asserts the
# kit's exit code, the fragments its output must carry, one it must not, that
# no key value is ever printed, and, for publish, what the stub recorded or
# that the stub never ran.
#
# The cases: check with the skill in each of its three places (the config home
# also in its C:/ form), absent, and without scripts/publish.sh; the version
# line present and missing; jq off PATH, and the skill's own bin/jq taking its
# place; no key, the key in the environment (winning over a file), a key file
# made 600 and one made 644, an empty one, and one holding only whitespace (the
# kit's named residual: it counts as a key); a stray argument. manifest on a
# folder, a single file, a relative path, the TARGET line's spelling, a
# .DS_Store; refused: a folder holding .git, a nested .env*, a *.pem key in any
# case, a credentials file, a target inside a .git folder, a file named .env, a
# missing path, an empty folder, a symbolic link, the wrong argument count.
# publish: a new site run from inside the target (the stub still records HOME
# as its working directory) and an update with all three options, each checked
# against the stub's record; no key (5), the skill absent (3), jq missing (4),
# the host script failing (6), an anonymous publish despite a key file (the
# warning); refused before the skill is looked for: a folder holding .git,
# every excluded option, the value refusals, no path; an unknown subcommand and
# none.
#
# Host notes. Under Git Bash, chmod 600 changes neither stat nor the NTFS ACL,
# so the two key-file cases assert that KEYFILE-MODE reports what stat reads
# for the file: 644 for both there, exactly 600 and 644 where chmod takes
# effect. Git Bash's ln -s copies instead of linking unless symbolic links are
# enabled; the symbolic-link case is then skipped and named as skipped, and so
# is the C:/ case on a host without cygpath.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$HERE/../../tools/herenow.sh"
[ -f "$KIT" ] || { echo "FAIL (setup): kit not found at $KIT"; exit 1; }

PASSED=0
FAILED=0
SKIPPED=0
FAILED_NAMES=""
SKIPPED_NAMES=""

TMPBASE="$(mktemp -d 2>/dev/null)" || { echo "FAIL (setup): mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMPBASE"' EXIT
T="$(cd "$TMPBASE" && pwd -P)"   # resolved, as the kit resolves its target

fail_setup() { echo "FAIL (setup): $1"; exit 1; }
mkdir -p "$T/tmp" "$T/sysbin" "$T/stubs" "$T/stubs-nojq" || fail_setup "mkdir"

# --- the kit's PATH: wrappers for the text tools, stubs for curl, file and jq ------------
for tool in tr grep sed head stat find sort wc mktemp dirname basename rm cygpath; do
  p="$(command -v "$tool" 2>/dev/null)" || p=""
  case "$p" in
    /*) printf '#!/bin/sh\nexec "%s" "$@"\n' "$p" > "$T/sysbin/$tool" && chmod +x "$T/sysbin/$tool" ;;
    *)  [ "$tool" = cygpath ] || fail_setup "no $tool on PATH" ;;
  esac
done
write_stub() { printf '#!/bin/sh\n%s\n' "$2" > "$1" && chmod +x "$1"; }
write_stub "$T/stubs/curl" 'case "$1" in --version) echo "curl 8.9.1 (fixture stub)" ;; *) echo "fixture stub: curl takes no call here" >&2; exit 97 ;; esac'
write_stub "$T/stubs/file" 'case "$1" in --version) echo "file-5.45"; echo "magic file from the fixture stub" ;; --brief) echo "application/octet-stream" ;; *) exit 97 ;; esac'
write_stub "$T/stubs/jq"   'case "$1" in --version) echo "jq-1.7.1" ;; *) exit 97 ;; esac'
cp "$T/stubs/curl" "$T/stubs/file" "$T/stubs-nojq/" || fail_setup "stub copy"
P_ALL="$T/stubs:$T/sysbin"
P_NOJQ="$T/stubs-nojq:$T/sysbin"

# --- stub skills, config homes and homes ------------------------------------------------------
# make_skill <folder> [yes|no]: a skill folder with a version line (or none) and a
# stub scripts/publish.sh that records and answers, never connects.
make_skill() {
  mkdir -p "$1/scripts" || fail_setup "mkdir $1"
  if [ "${2:-yes}" = yes ]; then
    printf -- '---\nname: here-now\n---\n\n**Skill version: 1.29.0**\n' > "$1/SKILL.md"
  else
    printf -- '---\nname: here-now\n---\n\nNo version line.\n' > "$1/SKILL.md"
  fi
  cat > "$1/scripts/publish.sh" <<'STUB'
{ printf 'PWD=%s\n' "$(pwd -P)"; for a in "$@"; do printf 'ARG=%s\n' "$a"; done; } > "$STUB_LOG"
case "${STUB_MODE:-ok}" in
  fail) echo "fixture stub: the upload failed" >&2; exit 7 ;;
  anon) echo "https://stub-site.example/"; echo "publish_result.auth_mode=anonymous" ;;
  *)    echo "https://stub-site.example/"; echo "publish_result.auth_mode=authenticated" ;;
esac
STUB
}
CFG_OK="$T/cfg-ok";       make_skill "$CFG_OK/skills/here-now"
CFG_NOVER="$T/cfg-nover"; make_skill "$CFG_NOVER/skills/here-now" no
CFG_NOPUB="$T/cfg-nopub"; mkdir -p "$CFG_NOPUB/skills/here-now" && cp "$CFG_OK/skills/here-now/SKILL.md" "$CFG_NOPUB/skills/here-now/" || fail_setup "cfg-nopub"
CFG_BINJQ="$T/cfg-binjq"; make_skill "$CFG_BINJQ/skills/here-now"; mkdir -p "$CFG_BINJQ/skills/here-now/bin"
write_stub "$CFG_BINJQ/skills/here-now/bin/jq" 'case "$1" in --version) echo "jq-1.8.2" ;; *) exit 97 ;; esac'
CFG_EMPTY="$T/cfg-empty"; mkdir -p "$CFG_EMPTY"

KEYE='fixture-env-key-not-real'
KEYF='fixture-file-key-not-real'
keyhome() { mkdir -p "$1/.herenow" && printf '%s' "$2" > "$1/.herenow/credentials" || fail_setup "key home $1"; }
H_BARE="$T/home-bare";     mkdir -p "$H_BARE"
H_CLAUDE="$T/home-claude"; make_skill "$H_CLAUDE/.claude/skills/here-now"
H_AGENTS="$T/home-agents"; make_skill "$H_AGENTS/.agents/skills/here-now"
H_K600="$T/home-k600";     keyhome "$H_K600" "$KEYF"; chmod 600 "$H_K600/.herenow/credentials"
H_K644="$T/home-k644";     keyhome "$H_K644" "$KEYF"; chmod 644 "$H_K644/.herenow/credentials"
H_KEMPTY="$T/home-kempty"; keyhome "$H_KEMPTY" ""
H_KWS="$T/home-kws";       keyhome "$H_KWS" "   "
mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null; }
M600="$(mode_of "$H_K600/.herenow/credentials")"
M644="$(mode_of "$H_K644/.herenow/credentials")"
[ -n "$M600" ] && [ -n "$M644" ] || fail_setup "stat cannot read a key file's mode"

# --- publish targets ------------------------------------------------------------------------------
S="$T/sites"
mkdir -p "$S/plain/notes" "$S/withgit/.git" "$S/withenv/sub" "$S/withpem/deploy" "$S/withcred" \
         "$S/empty" "$S/ds" "$S/repo/.git/info" || fail_setup "sites"
printf 'hello' > "$S/plain/index.html"; printf 'notes' > "$S/plain/notes/readme.txt"
printf 'x' > "$S/withgit/index.html";  printf 'ref' > "$S/withgit/.git/HEAD"
printf 'x' > "$S/withenv/index.html";  printf 'A=1' > "$S/withenv/sub/.env.local"
printf 'x' > "$S/withpem/index.html";  printf 'k' > "$S/withpem/deploy/Server.PEM"
printf 'x' > "$S/withcred/index.html"; printf 'k' > "$S/withcred/credentials"
printf 'x' > "$S/ds/index.html";       printf 'x' > "$S/ds/.DS_Store"
printf 'x' > "$S/repo/.git/info/page.html"
printf 'A=1' > "$S/.env"

have_cygpath=0
command -v cygpath >/dev/null 2>&1 && have_cygpath=1
# The host's own spelling of a path, as the kit prints it.
native() { if [ "$have_cygpath" -eq 1 ]; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

# --- the runner ---------------------------------------------------------------------------------------
LOG="$T/stub-record.txt"
reset_env() { C_HOME="$H_BARE"; C_CFG="$CFG_OK"; C_KEY="$KEYE"; C_PATH="$P_ALL"; C_MODE=ok; C_CWD="$T"; }

OUT=""
RC=0
run_kit() {
  local envs=(HOME="$C_HOME" PATH="$C_PATH" TMPDIR="$T/tmp" STUB_LOG="$LOG" STUB_MODE="$C_MODE")
  [ -n "${SYSTEMROOT:-}" ] && envs+=(SYSTEMROOT="$SYSTEMROOT")
  [ -n "$C_CFG" ] && envs+=(CLAUDE_CONFIG_DIR="$C_CFG")
  [ -n "$C_KEY" ] && envs+=(HERENOW_API_KEY="$C_KEY")
  rm -f "$LOG"
  OUT="$(cd "$C_CWD" && env -i "${envs[@]}" "$BASH" "$KIT" "$@" 2>&1)"
  RC=$?
}

# has_all <text> <fragments joined by |>: 0 when the text carries every fragment.
has_all() {
  local f oldifs="$IFS" rc=0
  IFS='|'; set -f
  for f in $2; do printf '%s' "$1" | grep -qF -- "$f" || { rc=1; MISSING_FRAG="$f"; break; }; done
  set +f; IFS="$oldifs"
  return "$rc"
}

verdict() {
  if [ -n "$2" ]; then
    echo "FAIL ($1): $2"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$1"
  else
    echo "PASS ($1)."; PASSED=$((PASSED + 1))
  fi
}
skip() { echo "SKIP ($1): $2."; SKIPPED=$((SKIPPED + 1)); SKIPPED_NAMES="$SKIPPED_NAMES|$1"; }

# t <name> <exit> <must carry, | joined, or -> <must not carry or -> <stub record: -, none, or lines joined by |> <kit args...>
t() {
  local name="$1" want="$2" frag="$3" absent="$4" rec="$5" why="" line oldifs
  shift 5
  run_kit "$@"
  MISSING_FRAG=""
  if [ "$RC" -ne "$want" ]; then why="expected exit $want, got $RC"
  elif [ "$frag" != "-" ] && ! has_all "$OUT" "$frag"; then why="the output does not carry '$MISSING_FRAG'"
  elif [ "$absent" != "-" ] && printf '%s' "$OUT" | grep -qF -- "$absent"; then why="the output carries '$absent', which it must not"
  elif printf '%s' "$OUT" | grep -qF -e "$KEYE" -e "$KEYF"; then why="the output carries a key value"
  elif [ "$rec" = none ] && [ -e "$LOG" ]; then why="the stub publish ran; it must not have"
  elif [ "$rec" != "-" ] && [ "$rec" != none ]; then
    if [ ! -f "$LOG" ]; then why="the stub publish never ran"
    else
      oldifs="$IFS"; IFS='|'; set -f
      for line in $rec; do
        grep -qxF -- "$line" "$LOG" || { why="the stub's record lacks the line '$line'"; break; }
      done
      set +f; IFS="$oldifs"
    fi
  fi
  [ -z "$why" ] || why="$why. Output: ${OUT:-<none>}"
  verdict "$name" "$why"
}

# --- check ----------------------------------------------------------------------------------------------
reset_env
t "check: ready, skill in the config home" 0 \
  "SKILL: $(native "$CFG_OK/skills/here-now")|VERSION: 1.29.0|BINARY: curl 8.9.1|BINARY: file 5.45|BINARY: jq 1.7.1|KEY: env" \
  "KEYFILE-MODE" none check
reset_env; C_CFG=""; C_HOME="$H_CLAUDE"
t "check: skill in ~/.claude/skills, no config home" 0 "SKILL: $(native "$H_CLAUDE/.claude/skills/here-now")" - none check
reset_env; C_CFG="$CFG_EMPTY"; C_HOME="$H_AGENTS"
t "check: skill in ~/.agents/skills, config home empty" 0 "SKILL: $(native "$H_AGENTS/.agents/skills/here-now")" - none check
reset_env; C_CFG="$CFG_EMPTY"
t "check: skill absent, the three places named" 3 \
  "SKILL: NOT FOUND (looked in $(native "$CFG_EMPTY/skills/here-now"), $(native "$H_BARE/.claude/skills/here-now"), $(native "$H_BARE/.agents/skills/here-now"))|KEY: env" \
  "VERSION:" none check
reset_env; C_CFG="$CFG_NOPUB"
t "check: skill folder without scripts/publish.sh" 3 "SKILL: NOT FOUND" - none check
reset_env; C_CFG="$CFG_NOVER"
t "check: no version line" 0 "VERSION: unknown" - none check
if [ "$have_cygpath" -eq 1 ]; then
  reset_env; C_CFG="$(cygpath -m "$CFG_OK")"
  t "check: config home in C:/ form" 0 "SKILL: $(native "$CFG_OK/skills/here-now")" - none check
else
  skip "check: config home in C:/ form" "no cygpath on this host"
fi
reset_env; C_PATH="$P_NOJQ"
t "check: jq off PATH" 4 "MISSING: jq|BINARY: curl 8.9.1" "BINARY: jq" none check
reset_env; C_PATH="$P_NOJQ"; C_CFG="$CFG_BINJQ"
t "check: the skill's own bin/jq, jq off PATH" 0 "BINARY: jq 1.8.2 (the skill's bin/jq)" "MISSING" none check
reset_env; C_KEY=""
t "check: no key" 4 "KEY: NONE" "KEYFILE-MODE" none check
reset_env; C_KEY=""; C_HOME="$H_K600"
t "check: key file made 600" 0 "KEY: credentials-file|KEYFILE-MODE: $M600" - none check
reset_env; C_KEY=""; C_HOME="$H_K644"
t "check: key file made 644" 0 "KEY: credentials-file|KEYFILE-MODE: $M644" - none check
reset_env; C_HOME="$H_K600"
t "check: the variable wins over the file" 0 "KEY: env|KEYFILE-MODE: $M600" - none check
reset_env; C_KEY=""; C_HOME="$H_KEMPTY"
t "check: empty key file" 4 "KEY: NONE|KEYFILE-MODE:" - none check
reset_env; C_KEY=""; C_HOME="$H_KWS"
t "check: whitespace-only key file counts (residual)" 0 "KEY: credentials-file" - none check
reset_env
t "check: a stray argument" 2 "Usage: herenow.sh check" "SKILL:" none check extra

# --- manifest ------------------------------------------------------------------------------------------
reset_env
t "manifest: folder" 0 \
  "TARGET: $(native "$S/plain")|FILE: index.html (5 bytes, text/html; charset=utf-8)|FILE: notes/readme.txt (5 bytes, text/plain; charset=utf-8)|FILES: 2 (10 bytes)" \
  - none manifest "$S/plain"
t "manifest: single file" 0 "FILE: index.html (5 bytes, text/html; charset=utf-8)|FILES: 1 (5 bytes)" - none manifest "$S/plain/index.html"
reset_env; C_CWD="$S"
t "manifest: relative path, TARGET absolute" 0 "TARGET: $(native "$S/plain")" - none manifest plain
reset_env
if [ "$have_cygpath" -eq 1 ]; then
  t "manifest: TARGET in backslash form for a forward-slash path" 0 "TARGET: $(cygpath -w "$S/plain")" \
    "TARGET: $(cygpath -m "$S/plain")" none manifest "$(cygpath -m "$S/plain")"
else
  t "manifest: TARGET as the resolved path" 0 "TARGET: $S/plain" - none manifest "$S/plain"
fi
t "manifest: .DS_Store skipped" 0 "FILES: 1 (1 bytes)|SKIPPED: 1 .DS_Store" - none manifest "$S/ds"
t "manifest: folder holding .git" 2 "REFUSED: the folder holds .git," "FILES:" none manifest "$S/withgit"
t "manifest: nested .env.local" 2 "REFUSED: the folder holds sub/.env.local," - none manifest "$S/withenv"
t "manifest: a *.pem key, any case" 2 "REFUSED: the folder holds deploy/Server.PEM," - none manifest "$S/withpem"
t "manifest: a credentials file" 2 "REFUSED: the folder holds credentials," - none manifest "$S/withcred"
t "manifest: target inside a .git folder" 2 "REFUSED: the path runs through a .git folder" - none manifest "$S/repo/.git/info"
t "manifest: a file named .env" 2 "REFUSED: the file's name (.env)" - none manifest "$S/.env"
t "manifest: missing path" 2 "REFUSED: the path does not exist" - none manifest "$S/nothing-here"
t "manifest: empty folder" 2 "REFUSED: the folder holds no file a publish would upload" - none manifest "$S/empty"
ln -s "$S/plain" "$S/link" 2>/dev/null
if [ -L "$S/link" ]; then
  t "manifest: a symbolic link" 2 "REFUSED: the path is a symbolic link" - none manifest "$S/link"
else
  skip "manifest: a symbolic link" "ln -s made no link on this host"
fi
t "manifest: no path" 2 "Usage:" "TARGET:" none manifest
t "manifest: two paths" 2 "Usage:" "TARGET:" none manifest "$S/plain" "$S/ds"

# --- publish -------------------------------------------------------------------------------------------
reset_env; C_CWD="$S/plain"
t "publish: a new site, run from inside the target, state at HOME" 0 \
  "ACT: a new site|KEY: env|https://stub-site.example/|publish_result.auth_mode=authenticated" "WARNING" \
  "PWD=$H_BARE|ARG=$S/plain|ARG=--client|ARG=claude-code/ensemble" publish "$S/plain"
reset_env
t "publish: an update with all three options" 0 "ACT: update of the site my-site" - \
  "ARG=$S/plain|ARG=--client|ARG=claude-code/ensemble|ARG=--slug|ARG=my-site|ARG=--title|ARG=Fixture title|ARG=--description|ARG=one line" \
  publish "$S/plain" --slug my-site --title "Fixture title" --description "one line"
reset_env; C_KEY=""
t "publish: no key" 5 "NO KEY:|Nothing was published." - none publish "$S/plain"
reset_env; C_CFG="$CFG_EMPTY"
t "publish: skill absent" 3 "SKILL: NOT FOUND" - none publish "$S/plain"
reset_env; C_PATH="$P_NOJQ"
t "publish: jq missing" 4 "MISSING: jq|INCOMPLETE:" - none publish "$S/plain"
reset_env; C_MODE=fail
t "publish: the host script fails" 6 "PUBLISH FAILED: the host's publish script exited 7" - "ARG=$S/plain" publish "$S/plain"
reset_env; C_KEY=""; C_HOME="$H_KWS"; C_MODE=anon
t "publish: anonymous despite a key file, warned" 0 "KEY: credentials-file|WARNING: the host script published ANONYMOUSLY" - \
  "PWD=$H_KWS" publish "$S/plain"
reset_env
t "publish: folder holding .git, refused before the skill" 2 "REFUSED: the folder holds .git," "SKILL:" none publish "$S/withgit"

reset_env
why=""
for spec in "--api-key x" "--api-key=x" "--base-url https://x.example" "--allow-nonherenow-base-url" \
            "--claim-token t" "--overwrite" "--workspace w" "--ttl 60" "--from-drive d" "--version 1" \
            "--spa" "--client c" "--bogus"; do
  set -f; set -- $spec; set +f
  run_kit publish "$S/plain" "$@"
  if [ "$RC" -ne 2 ] || ! printf '%s' "$OUT" | grep -qF -- "REFUSED: ${1%%=*}" || [ -e "$LOG" ]; then
    why="'$spec' gave exit $RC. Output: ${OUT:-<none>}"; break
  fi
done
verdict "publish: every excluded option refused by name, the stub never run (13 forms)" "$why"

why=""
check_val() {   # check_val <fragment> <publish arguments after the path...>
  [ -z "$why" ] || return 0
  run_kit publish "$S/plain" "${@:2}"
  if [ "$RC" -ne 2 ] || ! printf '%s' "$OUT" | grep -qF -- "$1" || [ -e "$LOG" ]; then
    why="'${*:2}' gave exit $RC, expected a refusal carrying '$1'. Output: ${OUT:-<none>}"
  fi
}
check_val "carries a character outside a-z 0-9 -" --slug Bad_Slug
check_val "--slug given twice" --slug a --slug b
check_val "--title given twice" --title a --title b
check_val "the value of --title is empty" --title ""
check_val "the value of --description carries a double quote" --description 'say "hi"'
check_val "--title needs a value" --title
check_val "one path per publish" "$S/ds"
verdict "publish: value refusals (bad slug, repeats, empty, a double quote, no value, a second path)" "$why"

t "publish: no path" 2 "Usage:" - none publish
t "publish: options but no path" 2 "Usage:" - none publish --slug abc

# --- the subcommand -----------------------------------------------------------------------------------
t "an unknown subcommand" 2 "Usage:" - none deploy
t "no subcommand" 2 "Usage:" - none

echo ""
if [ "$FAILED" -gt 0 ]; then
  echo "FAIL: $FAILED failed, $PASSED passed (${FAILED_NAMES#|})."
  exit 1
fi
if [ "$SKIPPED" -gt 0 ]; then
  echo "PASS: all $PASSED cases run; $SKIPPED skipped on this host (${SKIPPED_NAMES#|})."
else
  echo "PASS: all $PASSED cases."
fi
exit 0
