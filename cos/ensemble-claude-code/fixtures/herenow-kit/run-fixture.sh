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
# fixture builds (so the key file the kit reads is a scratch one),
# CLAUDE_CONFIG_DIR a scratch config home or unset, the key variable a fixture
# value or unset, and PATH two scratch folders: wrappers for the text tools the
# kit uses, and stubs. The stub curl records its arguments, whether the key
# arrived on its standard input and whether any key value sits in its
# environment, and answers by method and URL from the case's scenario
# variables (ACC_GETS and ACC_PATCHES, comma lists read call by call, the last
# repeating); the stub jq answers --version itself and hands everything else
# to the real jq, which must be on the fixture's PATH; the stub file answers
# --version. The real curl is never on the kit's PATH. The skill is a stub
# folder whose scripts/publish.sh and scripts/drive.sh record their working
# directory, arguments and environment facts and answer; they open no
# connection. One event log records the order of publish, access and Drive
# calls across the stubs.
#
# Every case asserts the kit's exit code, the fragments its output must carry,
# one it must not, that no key value is ever printed, and the standing rules:
# each curl call carries the key on its standard input and none in its
# environment or arguments, every URL starts with https://here.now/api/v1/, a
# key read from the file never reaches a host script's environment, and check
# and manifest never call curl (K25). A case may also assert the publish
# stub's record, the event sequence, that curl never ran, or the drive stub's
# record.
#
# The cases, first the 45 that predate Drive and Sites (adjusted where the
# owner-only flow changed what they observe; the old anonymous-despite-a-key
# residual is closed by K12, and its case now covers the --public warning):
# check with the skill in each of its three places (the config home also in
# its C:/ form), absent, and without scripts/publish.sh; the version line
# present and missing; jq off PATH, and the skill's own bin/jq taking its
# place; no key, the key in the environment (winning over a file), a key file
# made 600 and one made 644, an empty one, and one holding only whitespace
# (check counts it; publish refuses it); a stray argument. manifest on a
# folder, a single file, a relative path, the TARGET line's spelling, a
# .DS_Store; refused: a folder holding .git, a nested .env*, a *.pem key in any
# case, a credentials file, a target inside a .git folder, a file named .env, a
# missing path, an empty folder, a symbolic link, the wrong argument count.
# publish: a new site run from inside the target, an update with all three
# options, no key (5), the skill absent (3), jq missing (4), the host script
# failing (6), the --public anonymous warning; refused before the skill is
# looked for: a folder holding .git, every excluded option, the value
# refusals, no path; an unknown subcommand and none. Then K1 to K25 of the
# 2026-10-13 build spec, and the extra secret names (F3).
#
# Host notes. Under Git Bash, chmod 600 changes neither stat nor the NTFS ACL,
# so the two key-file cases assert that KEYFILE-MODE reports what stat reads
# for the file: 644 for both there, exactly 600 and 644 where chmod takes
# effect. Git Bash's ln -s copies instead of linking unless symbolic links are
# enabled; the symbolic-link cases are then skipped and named as skipped, and
# so is the C:/ case on a host without cygpath.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$HERE/../../tools/herenow.sh"
[ -f "$KIT" ] || { echo "FAIL (setup): kit not found at $KIT"; exit 1; }

PASSED=0
FAILED=0
SKIPPED=0
FAILED_NAMES=""
SKIPPED_NAMES=""

fail_setup() { echo "FAIL (setup): $1"; exit 1; }
# The belt: the only recursive delete this fixture makes is of its own temp
# base, and of $T/state beneath it, never of an empty, root or relative path.
TMPBASE="$(mktemp -d 2>/dev/null)" || { echo "FAIL (setup): mktemp -d failed"; exit 1; }
trap 'case "${TMPBASE:-}" in ""|/|.) ;; *) rm -rf -- "$TMPBASE";; esac' EXIT
T="$(cd "$TMPBASE" && pwd -P)"   # resolved, as the kit resolves its target
case "$T" in ""|/|.) fail_setup "temp base resolved to '$T'";; esac

mkdir -p "$T/tmp" "$T/sysbin" "$T/stubs" "$T/stubs-nojq" "$T/state" || fail_setup "mkdir"

REAL_JQ="$(command -v jq 2>/dev/null)" || REAL_JQ=""
[ -n "$REAL_JQ" ] || fail_setup "no jq on PATH; the kit's API paths parse with the real jq"

# --- the kit's PATH: wrappers for the text tools, stubs for curl, file and jq ------------
for tool in tr grep sed head stat find sort wc mktemp dirname basename rm cygpath env date cat cp; do
  p="$(command -v "$tool" 2>/dev/null)" || p=""
  case "$p" in
    /*) printf '#!/bin/sh\nexec "%s" "$@"\n' "$p" > "$T/sysbin/$tool" && chmod +x "$T/sysbin/$tool" ;;
    *)  [ "$tool" = cygpath ] || fail_setup "no $tool on PATH" ;;
  esac
done
write_stub() { printf '#!/bin/sh\n%s\n' "$2" > "$1" && chmod +x "$1"; }
write_stub "$T/stubs/file" 'case "$1" in --version) echo "file-5.45"; echo "magic file from the fixture stub" ;; --brief) echo "application/octet-stream" ;; *) exit 97 ;; esac'
write_stub "$T/stubs/jq"   "case \"\$1\" in --version) echo \"jq-1.7.1\" ;; *) exec \"$REAL_JQ\" \"\$@\" ;; esac"

# The stub curl: records, then answers by method and URL.
{ printf '#!%s\n' "$BASH"; cat <<'STUB'
case "${1:-}" in --version) echo "curl 8.9.1 (fixture stub)"; exit 0 ;; esac
log="$STUB_CURL_LOG"
{ printf 'ARGV'; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "$log.argv"
method=GET; url=""; out=""; wfmt=""; hstdin=0; maxfs=""; data=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -o) out="$2"; shift 2 ;;
    -w) wfmt="$2"; shift 2 ;;
    -H) [ "$2" = "@-" ] && hstdin=1; shift 2 ;;
    --data-raw|-d) data="$2"; shift 2 ;;
    --max-filesize) maxfs="$2"; shift 2 ;;
    --proto|--max-time) shift 2 ;;
    https://*|http://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
hdr=none
if [ "$hstdin" -eq 1 ]; then
  line="$(cat)"
  hdr=other
  while IFS= read -r k; do
    [ -n "$k" ] && [ "$line" = "authorization: Bearer $k" ] && hdr=ok
  done < "$STUB_KEYS"
fi
envkey=no
env | grep -qF -f "$STUB_KEYS" && envkey=yes
rel="${url#https://here.now/api/v1/}"
kind=other
case "$method $rel" in
  "GET publishes") kind=acc_list ;;
  "GET publish/"*/access) kind=acc_get ;;
  "PATCH publish/"*/access) kind=acc_patch ;;
  "GET publish/"*/files) kind=files ;;
  "GET publish/"*/files/*) kind=file ;;
esac
[ "$url" = "https://here.now/api/v1/$rel" ] || kind=other
n=$(( $(cat "$STUB_STATE/$kind" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$STUB_STATE/$kind"
echo "CALL $method $url hdr=$hdr envkey=$envkey data=$data maxfs=$maxfs" >> "$log"
echo "$method $kind" >> "$STUB_EVENTS"
pick() {
  local IFS=, i=0 it last=""
  for it in $1; do i=$((i + 1)); last="$it"; [ "$i" -eq "$2" ] && { echo "$it"; return; }; done
  echo "$last"
}
OWN='{"access":{"mode":"restricted","accessPolicyVersion":2,"allowedEmails":[],"allowedDomains":[]}}'
ERR500='{"error":"fixture internal error","code":"internal_error","message":"x"}'
code=200; body=""; special=""
case "$kind" in
  acc_list) body='{"publishes":[{"slug":"alpha-1","siteUrl":"https://alpha-1.here.now/","updatedAt":"2026-10-01T00:00:00Z","status":"active"},{"slug":"beta-2","siteUrl":"https://beta-2.here.now/","updatedAt":"2026-10-02T00:00:00Z","status":"active\u001b[31m"}]}' ;;
  acc_get)
    case "$(pick "${ACC_GETS:-own}" "$n")" in
      own)   body="$OWN" ;;
      open)  body='{"access":{"mode":"anyone_with_link","accessPolicyVersion":1,"allowedEmails":[],"allowedDomains":[]}}' ;;
      email) body='{"access":{"mode":"restricted","accessPolicyVersion":3,"allowedEmails":["someone@example.com"],"allowedDomains":[]}}' ;;
      pw)    body='{"access":{"mode":"password","accessPolicyVersion":4,"allowedEmails":[],"allowedDomains":[]}}' ;;
      *)     code=500; body="$ERR500" ;;
    esac ;;
  acc_patch)
    code="$(pick "${ACC_PATCHES:-200}" "$n")"
    case "$code" in
      2*)  body="$OWN" ;;
      409) body='{"error":"Cannot update access on an unfinalized site. Finalize the site first.","code":"conflict","message":"unfinalized"}' ;;
      *)   body="$ERR500" ;;
    esac ;;
  files) body='{"slug":"alpha-1","currentVersionId":"ver_fixture_1","files":[{"path":"index.html","size":5,"contentType":"text/html; charset=utf-8","hash":null,"url":"https://evil.example/steal/index.html"},{"path":"big.txt","size":300000,"contentType":"text/plain","hash":null,"url":"https://evil.example/big"},{"path":"lies.txt","size":10,"contentType":"text/plain","hash":null,"url":"https://evil.example/lies"},{"path":"huge.txt","size":10,"contentType":"text/plain","hash":null,"url":"https://evil.example/huge"},{"path":"bin.dat","size":4,"contentType":"application/octet-stream","hash":null,"url":"https://evil.example/bin"},{"path":"dir/a b.txt","size":3,"contentType":"text/plain","hash":null,"url":"https://evil.example/ab"}]}' ;;
  file)
    case "$rel" in
      */files/index.html)     body='hello' ;;
      */files/lies.txt)       special=lies ;;
      */files/huge.txt)       [ -n "$maxfs" ] && exit 63; special=lies ;;
      */files/bin.dat)        special=bin ;;
      */files/dir/a%20b.txt)  body='abc' ;;
      *) code=404; body='{"error":"no such file","code":"not_found","message":"x"}' ;;
    esac ;;
  *) code=404; body='{"error":"no such route in the fixture","code":"not_found","message":"x"}' ;;
esac
if [ -n "$out" ]; then
  case "$special" in
    lies) head -c 300000 /dev/zero | tr '\0' 'z' > "$out" ;;
    bin)  printf 'a\000bc' > "$out" ;;
    *)    printf '%s' "$body" > "$out" ;;
  esac
fi
case "$wfmt" in *http_code*) printf '%s' "$code" ;; esac
exit 0
STUB
} > "$T/stubs/curl" && chmod +x "$T/stubs/curl" || fail_setup "stub curl"
cp "$T/stubs/curl" "$T/stubs/file" "$T/stubs-nojq/" || fail_setup "stub copy"
P_ALL="$T/stubs:$T/sysbin"
P_NOJQ="$T/stubs-nojq:$T/sysbin"

# --- stub skills, config homes and homes ------------------------------------------------------
# make_skill <folder> [yes|no]: a skill folder with a version line (or none) and
# stub scripts/publish.sh and scripts/drive.sh that record and answer, never
# connect.
make_skill() {
  mkdir -p "$1/scripts" || fail_setup "mkdir $1"
  if [ "${2:-yes}" = yes ]; then
    printf -- '---\nname: here-now\n---\n\n**Skill version: 1.29.0**\n' > "$1/SKILL.md"
  else
    printf -- '---\nname: here-now\n---\n\nNo version line.\n' > "$1/SKILL.md"
  fi
  cat > "$1/scripts/publish.sh" <<'STUB'
{ echo "RUN"; printf 'PWD=%s\n' "$(pwd -P)"; for a in "$@"; do printf 'ARG=%s\n' "$a"; done
  if env | grep -qF -f "$STUB_KEYS"; then echo "ENVKEY=yes"; else echo "ENVKEY=no"; fi; } >> "$STUB_LOG"
slug=""; prev=""
for a in "$@"; do [ "$prev" = --slug ] && slug="$a"; prev="$a"; done
if [ -n "$slug" ]; then echo "publish slug" >> "$STUB_EVENTS"; else echo "publish new" >> "$STUB_EVENTS"; fi
case "${STUB_MODE:-ok}" in
  fail) echo "fixture stub: the upload failed" >&2; exit 7 ;;
  failcontent) [ -n "$slug" ] && { echo "fixture stub: the upload failed" >&2; exit 7; } ;;
esac
[ -n "$slug" ] || slug=stub-site-1
auth=authenticated
[ "${STUB_MODE:-ok}" = anon ] && auth=anonymous
echo "https://stub-site.example/"
echo "publish_result.slug=$slug" >&2
echo "publish_result.auth_mode=$auth" >&2
STUB
  cat > "$1/scripts/drive.sh" <<'STUB'
{ echo "DRIVE-RUN"; printf 'PWD=%s\n' "$(pwd -P)"; for a in "$@"; do printf 'DARG=%s\n' "$a"; done
  if [ -n "${HERENOW_DRIVE_TOKEN+x}" ]; then echo "TOKEN=present"; else echo "TOKEN=absent"; fi; } >> "$STUB_DRIVE_LOG"
case "${1:-}" in
  ls)
    if [ "$#" -eq 1 ]; then echo '{"drives":[{"id":"drv_fixture","name":"My Drive"}]}'
    else
      case "${DRIVE_LS:-empty}" in
        has)  printf '{"files":[{"path":"%s","etag":"\\"e1\\"","size":42,"contentType":"text/plain","versionId":null,"sha256":"x","updatedAt":"2026-10-01T00:00:00Z"}],"nextCursor":null}\n' "$3" ;;
        more) echo '{"files":[{"path":"other.md","etag":"x","size":1}],"nextCursor":"c2"}' ;;
        big)  head -c 300000 /dev/zero | tr '\0' 'x' ;;
        fail) echo "error: HTTP 404: drive not found" >&2; exit 1 ;;
        *)    echo '{"files":[],"nextCursor":null}' ;;
      esac
    fi ;;
  cat)
    case "${DRIVE_CAT:-small}" in
      big) head -c 300000 /dev/zero | tr '\0' 'y' ;;
      bin) printf 'a\000b' ;;
      *)   printf 'drive text\n' ;;
    esac ;;
  put) echo "drive put" >> "$STUB_EVENTS"; printf '{"file":{"path":"%s","etag":"\\"e2\\""}}\n' "$3" ;;
  *) echo "error: unknown command: $1" >&2; exit 1 ;;
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
KEYS="$T/keys.txt"
printf '%s\n%s\n' "$KEYE" "$KEYF" > "$KEYS"
keyhome() { mkdir -p "$1/.herenow" && printf '%s' "$2" > "$1/.herenow/credentials" || fail_setup "key home $1"; }
H_BARE="$T/home-bare";     mkdir -p "$H_BARE"
H_CLAUDE="$T/home-claude"; make_skill "$H_CLAUDE/.claude/skills/here-now"
H_AGENTS="$T/home-agents"; make_skill "$H_AGENTS/.agents/skills/here-now"
H_K600="$T/home-k600";     keyhome "$H_K600" "$KEYF"; chmod 600 "$H_K600/.herenow/credentials"
H_K644="$T/home-k644";     keyhome "$H_K644" "$KEYF"; chmod 644 "$H_K644/.herenow/credentials"
H_KEMPTY="$T/home-kempty"; keyhome "$H_KEMPTY" ""
H_KWS="$T/home-kws";       keyhome "$H_KWS" "   "
H_KNL="$T/home-knl";       keyhome "$H_KNL" "  $KEYF
"
mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null; }
M600="$(mode_of "$H_K600/.herenow/credentials")"
M644="$(mode_of "$H_K644/.herenow/credentials")"
[ -n "$M600" ] && [ -n "$M644" ] || fail_setup "stat cannot read a key file's mode"

# --- publish targets and upload sources -------------------------------------------------------
S="$T/sites"
mkdir -p "$S/plain/notes" "$S/withgit/.git" "$S/withenv/sub" "$S/withpem/deploy" "$S/withcred" \
         "$S/empty" "$S/ds" "$S/repo/.git/info" "$S/withssh/keys" "$S/withnetrc" "$S/withp12" || fail_setup "sites"
printf 'hello' > "$S/plain/index.html"; printf 'notes' > "$S/plain/notes/readme.txt"
printf 'x' > "$S/withgit/index.html";  printf 'ref' > "$S/withgit/.git/HEAD"
printf 'x' > "$S/withenv/index.html";  printf 'A=1' > "$S/withenv/sub/.env.local"
printf 'x' > "$S/withpem/index.html";  printf 'k' > "$S/withpem/deploy/Server.PEM"
printf 'x' > "$S/withcred/index.html"; printf 'k' > "$S/withcred/credentials"
printf 'x' > "$S/ds/index.html";       printf 'x' > "$S/ds/.DS_Store"
printf 'x' > "$S/repo/.git/info/page.html"
printf 'x' > "$S/withssh/index.html";  printf 'k' > "$S/withssh/keys/id_ed25519"
printf 'x' > "$S/withnetrc/index.html"; printf 'k' > "$S/withnetrc/.netrc"
printf 'x' > "$S/withp12/index.html";  printf 'k' > "$S/withp12/Client.P12"
printf 'A=1' > "$S/.env"
mkdir -p "$S/rules" && printf '# check reality\n' > "$S/rules/check-reality.md"
printf 'k' > "$S/id_ecdsa"

have_cygpath=0
command -v cygpath >/dev/null 2>&1 && have_cygpath=1
# The host's own spelling of a path, as the kit prints it.
native() { if [ "$have_cygpath" -eq 1 ]; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

# --- the runner ---------------------------------------------------------------------------------------
LOG="$T/stub-record.txt"
CLOG="$T/curl-record.txt"
EVENTS="$T/events.txt"
DLOG="$T/drive-record.txt"
reset_env() {
  C_HOME="$H_BARE"; C_CFG="$CFG_OK"; C_KEY="$KEYE"; C_PATH="$P_ALL"; C_MODE=ok; C_CWD="$T"
  C_GETS=own; C_PATCHES=200; C_DLS=empty; C_DCAT=small; C_DTOK=""
  X_EVENTS="-"; X_NOCURL=0; X_DRIVE="-"
}

OUT=""
RC=0
run_kit() {
  local envs=(HOME="$C_HOME" PATH="$C_PATH" TMPDIR="$T/tmp" STUB_LOG="$LOG" STUB_MODE="$C_MODE"
              STUB_CURL_LOG="$CLOG" STUB_STATE="$T/state" STUB_EVENTS="$EVENTS" STUB_KEYS="$KEYS"
              STUB_DRIVE_LOG="$DLOG" ACC_GETS="$C_GETS" ACC_PATCHES="$C_PATCHES"
              DRIVE_LS="$C_DLS" DRIVE_CAT="$C_DCAT")
  [ -n "${SYSTEMROOT:-}" ] && envs+=(SYSTEMROOT="$SYSTEMROOT")
  [ -n "$C_CFG" ] && envs+=(CLAUDE_CONFIG_DIR="$C_CFG")
  [ -n "$C_KEY" ] && envs+=(HERENOW_API_KEY="$C_KEY")
  [ -n "$C_DTOK" ] && envs+=(HERENOW_DRIVE_TOKEN="$C_DTOK")
  rm -f "$LOG" "$CLOG" "$CLOG.argv" "$EVENTS" "$DLOG"
  rm -rf -- "$T/state"; mkdir -p "$T/state"
  KIT_SUB="${1:-}"
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
events() { [ -f "$EVENTS" ] && paste -sd'|' "$EVENTS"; }

# standing: the rules every run keeps; prints the first one broken.
standing() {
  if [ -f "$CLOG" ]; then
    if grep -v ' hdr=ok envkey=no ' "$CLOG" | grep -q .; then
      echo "a curl call without the key on its standard input, or with a key in its environment: $(grep -v ' hdr=ok envkey=no ' "$CLOG" | head -n 1)"; return
    fi
    if grep -v '^CALL [A-Z]* https://here\.now/api/v1/' "$CLOG" | grep -q .; then
      echo "a curl call to a URL not built from https://here.now/api/v1/: $(grep -v '^CALL [A-Z]* https://here\.now/api/v1/' "$CLOG" | head -n 1)"; return
    fi
    if grep -qF -e "$KEYE" -e "$KEYF" "$CLOG.argv"; then echo "a key on curl's command line"; return; fi
  fi
  if [ -z "$C_KEY" ] && [ -f "$LOG" ] && grep -qx 'ENVKEY=yes' "$LOG"; then
    echo "the key the kit read from the file reached the host script's environment"; return
  fi
  case "$KIT_SUB" in
    check|manifest) [ -e "$CLOG" ] && { echo "check or manifest called curl (K25)"; return; } ;;
  esac
}

verdict() {
  if [ -n "$2" ]; then
    echo "FAIL ($1): $2"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$1"
  else
    echo "PASS ($1)."; PASSED=$((PASSED + 1))
  fi
}
skip() { echo "SKIP ($1): $2."; SKIPPED=$((SKIPPED + 1)); SKIPPED_NAMES="$SKIPPED_NAMES|$1"; }

# check_record <file> <lines joined by |>: sets why when a line is absent.
check_record() {
  local line oldifs
  [ -f "$1" ] || { why="the stub's record $1 does not exist"; return; }
  oldifs="$IFS"; IFS='|'; set -f
  for line in $2; do
    grep -qxF -- "$line" "$1" || { why="the record lacks the line '$line'"; break; }
  done
  set +f; IFS="$oldifs"
}

# t <name> <exit> <must carry, | joined, or -> <must not carry or -> <publish stub record: -, none, or lines joined by |> <kit args...>
# Per case, set after reset_env: X_EVENTS (the exact event sequence, | joined, or none), X_NOCURL=1, X_DRIVE (drive stub record lines, | joined, or none).
t() {
  local name="$1" want="$2" frag="$3" absent="$4" rec="$5" why="" ev
  shift 5
  run_kit "$@"
  MISSING_FRAG=""
  if [ "$RC" -ne "$want" ]; then why="expected exit $want, got $RC"
  elif [ "$frag" != "-" ] && ! has_all "$OUT" "$frag"; then why="the output does not carry '$MISSING_FRAG'"
  elif [ "$absent" != "-" ] && printf '%s' "$OUT" | grep -qF -- "$absent"; then why="the output carries '$absent', which it must not"
  elif printf '%s' "$OUT" | grep -qF -e "$KEYE" -e "$KEYF"; then why="the output carries a key value"
  elif [ "$rec" = none ] && [ -e "$LOG" ]; then why="the stub publish ran; it must not have"
  elif [ "$X_NOCURL" = 1 ] && [ -e "$CLOG" ]; then why="curl ran; it must not have"
  elif [ "$X_DRIVE" = none ] && [ -e "$DLOG" ]; then why="the stub drive script ran; it must not have"
  else
    why="$(standing)"
  fi
  if [ -z "$why" ] && [ "$rec" != "-" ] && [ "$rec" != none ]; then check_record "$LOG" "$rec"; fi
  if [ -z "$why" ] && [ "$X_DRIVE" != "-" ] && [ "$X_DRIVE" != none ]; then check_record "$DLOG" "$X_DRIVE"; fi
  if [ -z "$why" ] && [ "$X_EVENTS" != "-" ]; then
    ev="$(events)"; [ -n "$ev" ] || ev=none
    [ "$ev" = "$X_EVENTS" ] || why="the events ran '$ev', expected '$X_EVENTS'"
  fi
  [ -z "$why" ] || why="$why. Output: ${OUT:-<none>}"
  verdict "$name" "$why"
}

# --- check ----------------------------------------------------------------------------------------------
reset_env
t "check: ready, skill in the config home" 0 \
  "SKILL: $(native "$CFG_OK/skills/here-now")|VERSION: 1.29.0|BINARY: curl 8.9.1|BINARY: file 5.45|BINARY: jq 1.7.1|KEY: env|DRIVE-TOKEN: unset" \
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
t "check: whitespace-only key file counts as a carrier (publish refuses it, K12)" 0 "KEY: credentials-file" - none check
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
t "publish: the host script fails (an update, so the target ran)" 6 "PUBLISH FAILED: the host's publish script exited 7" - "ARG=$S/plain" \
  publish "$S/plain" --slug my-site
reset_env; C_MODE=anon; C_GETS=open
t "publish --public: anonymous despite a key, warned" 0 "KEY: env|WARNING: the host script published ANONYMOUSLY|ACCESS: anyone_with_link (not owner-only)" - \
  "PWD=$H_BARE" publish "$S/plain" --public
reset_env
t "publish: folder holding .git, refused before the skill" 2 "REFUSED: the folder holds .git," "SKILL:" none publish "$S/withgit"

reset_env
why=""
for spec in "--api-key x" "--api-key=x" "--token t" "--base-url https://x.example" "--allow-nonherenow-base-url" \
            "--claim-token t" "--overwrite" "--workspace w" "--ttl 60" "--from-drive d" "--version 1" \
            "--spa" "--client c" "--bogus"; do
  set -f; set -- $spec; set +f
  run_kit publish "$S/plain" "$@"
  if [ "$RC" -ne 2 ] || ! printf '%s' "$OUT" | grep -qF -- "REFUSED: ${1%%=*}" || [ -e "$LOG" ] || [ -e "$CLOG" ]; then
    why="'$spec' gave exit $RC. Output: ${OUT:-<none>}"; break
  fi
done
verdict "publish: every excluded option refused by name, nothing run (14 forms)" "$why"

why=""
check_val() {   # check_val <fragment> <publish arguments after the path...>
  [ -z "$why" ] || return 0
  run_kit publish "$S/plain" "${@:2}"
  if [ "$RC" -ne 2 ] || ! printf '%s' "$OUT" | grep -qF -- "$1" || [ -e "$LOG" ] || [ -e "$CLOG" ]; then
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

# === K1 to K25: the owner-only publish, the site reads, Drive =========================================
# --- publish, owner-only -------------------------------------------------------------------------------
reset_env; X_EVENTS="publish new|PATCH acc_patch|GET acc_get|publish slug|GET acc_get"
t "K1 new --ordered: placeholder, lock, verify, content, verify" 0 \
  "ORDERED: yes|ACCESS: owner-only, verified before content|ACCESS: owner-only, verified after content|WINDOW: the placeholder was reachable|https://stub-site.example/|ACT: a new site, owner-only (placeholder first)" \
  "EXPOSED" "ARG=$S/plain|ARG=--slug|ARG=stub-site-1|ARG=--title|ARG=K1 title" \
  publish "$S/plain" --title "K1 title" --ordered
why=""
[ "$(grep -c '^RUN$' "$LOG")" = 2 ] || why="the host script ran $(grep -c '^RUN$' "$LOG") times, not twice"
[ -z "$why" ] && [ "$(grep -c '^ARG=--title$' "$LOG")" != 1 ] && why="the placeholder run carried the title"
[ -z "$why" ] && grep -q 'data={"mode":"restricted","allowedEmails":\[\],"allowedDomains":\[\]}' "$CLOG" || { [ -n "$why" ] || why="the PATCH body is not owner-only"; }
[ -z "$why" ] && [ -n "$(ls -A "$T/tmp" 2>/dev/null)" ] && why="the placeholder folder was left in TMPDIR: $(ls -A "$T/tmp")"
verdict "K1 detail: two host runs, the title on the content only, the owner-only PATCH body, the placeholder removed" "$why"

reset_env; C_PATCHES=409; X_EVENTS="publish new|PATCH acc_patch"
t "K2 the lock PATCH answers 409" 7 "STOPPED: the placeholder site stub-site-1 is live and not verified owner-only|HTTP 409: Cannot update access|nothing of the target was uploaded" - - \
  publish "$S/plain" --ordered
reset_env; C_GETS=open; X_EVENTS="publish new|PATCH acc_patch|GET acc_get"
t "K3 the verify reads anyone_with_link" 7 "STOPPED:|reads back as anyone_with_link" "ACCESS: owner-only" - publish "$S/plain" --ordered
reset_env; C_GETS=email; X_EVENTS="publish new|PATCH acc_patch|GET acc_get"
t "K4 the verify reads restricted with one email" 7 "STOPPED:|reads back as restricted (1 emails, 0 domains)" - - publish "$S/plain"
reset_env; C_GETS=own,open,own; X_EVENTS="publish new|PATCH acc_patch|GET acc_get|publish slug|GET acc_get|PATCH acc_patch|GET acc_get"
t "K5 not owner-only after the content: re-locked, EXPOSED" 8 \
  "EXPOSED: the site was anyone_with_link after the content update; re-locked and verified at|https://stub-site.example/" "verified after content" - \
  publish "$S/plain" --ordered
reset_env; C_GETS=own,open; C_PATCHES=200,500; X_EVENTS="publish new|PATCH acc_patch|GET acc_get|publish slug|GET acc_get|PATCH acc_patch"
t "K6 the re-lock fails" 9 "EXPOSED, NOT RE-LOCKED: the site was anyone_with_link" - - publish "$S/plain" --ordered
reset_env; X_EVENTS="GET acc_get|publish slug|GET acc_get"
t "K7 ordered update of an owner-only site: no PATCH" 0 \
  "ACCESS: owner-only, verified before content|ACCESS: owner-only, verified after content|ACT: update of the site my-site, owner-only" "WINDOW" \
  "ARG=--slug|ARG=my-site" publish "$S/plain" --slug my-site --ordered
reset_env; C_GETS=open; X_EVENTS="GET acc_get"
t "K8 ordered update of an anyone_with_link site: refused, nothing uploaded" 2 \
  "an update without --public goes only to an owner-only site, and my-site is anyone_with_link" - none publish "$S/plain" --slug my-site --ordered
reset_env; C_GETS=pw; X_EVENTS="GET acc_get"
t "K9 unflagged update of a password site: refused" 2 "my-site is password" - none publish "$S/plain" --slug my-site
reset_env; C_GETS=open; X_EVENTS="publish new|GET acc_get"
t "K10 --public new site: no PATCH, the access printed" 0 \
  "ACCESS: anyone_with_link (not owner-only)|ACT: a new site, PUBLIC (--public)" "ORDERED" "ARG=$S/plain" publish "$S/plain" --public
reset_env; X_NOCURL=1
t "K11 --ordered with --public" 2 "REFUSED: --ordered with --public" - none publish "$S/plain" --ordered --public
reset_env; X_NOCURL=1
why=""
for spec in "--ordered --ordered" "--public --public"; do
  set -f; set -- $spec; set +f
  run_kit publish "$S/plain" "$@"
  if [ "$RC" -ne 2 ] || ! printf '%s' "$OUT" | grep -qF -- "given twice" || [ -e "$LOG" ] || [ -e "$CLOG" ]; then why="'$spec' gave exit $RC. Output: $OUT"; break; fi
done
verdict "K11 each flag twice refused" "$why"
reset_env; C_KEY=""; C_HOME="$H_KWS"; X_NOCURL=1
t "K12 whitespace-only key file: exit 5 before any call" 5 "NO KEY: the key file ~/.herenow/credentials holds no key" - none publish "$S/plain" --ordered
reset_env; C_KEY="two words"; X_NOCURL=1
t "K12 a key with whitespace inside: exit 5 before any call" 5 "NO KEY: the key carrier's value holds whitespace" "two words" none publish "$S/plain"
reset_env; C_KEY=""; C_HOME="$H_KEMPTY"; X_NOCURL=1
t "K12 site reads with an empty key file: exit 5" 5 "NO KEY:" - none site-ls
reset_env
t "K13 key from the environment: on curl's stdin only" 0 "ACCESS: owner-only, verified after content" - - publish "$S/plain" --ordered
why=""; grep -q ' hdr=ok ' "$CLOG" 2>/dev/null || why="no curl call carried the key on its standard input"
verdict "K13 detail: the environment key reached curl on stdin" "$why"
reset_env; C_KEY=""; C_HOME="$H_KNL"
t "K13 key from the file (whitespace around it stripped): not in argv, output or any child environment" 0 \
  "KEY: credentials-file|ACCESS: owner-only, verified after content" - "ENVKEY=no" publish "$S/plain" --ordered
why=""; grep -q ' hdr=ok ' "$CLOG" 2>/dev/null || why="no curl call carried the file key on its standard input"
verdict "K13 detail: the file key reached curl on stdin" "$why"
reset_env; C_MODE=anon; X_EVENTS="publish new"
t "K14 an anonymous placeholder: stopped, no PATCH" 7 "STOPPED: the placeholder went up without publish_result.auth_mode=authenticated" - - publish "$S/plain" --ordered
reset_env; C_MODE=fail; X_EVENTS="publish new"
t "publish: the placeholder upload fails" 6 "on the placeholder|nothing of the target was uploaded" - - publish "$S/plain" --ordered
reset_env; C_MODE=failcontent; X_EVENTS="publish new|PATCH acc_patch|GET acc_get|publish slug"
t "publish: the content upload fails after the lock" 6 "on the content|stays owner-only" - - publish "$S/plain" --ordered

# --- the site reads ------------------------------------------------------------------------------------
reset_env; C_GETS=own,open; X_EVENTS="GET acc_list|GET acc_get|GET acc_get"
t "K15 site-ls, two sites with their access" 0 \
  "SITE: alpha-1 | https://alpha-1.here.now/ | access owner-only | updated 2026-10-01T00:00:00Z | status active|SITE: beta-2 | https://beta-2.here.now/ | access anyone_with_link | updated 2026-10-02T00:00:00Z | status active?[31m|SITES: 2" \
  - none site-ls
reset_env; C_GETS=own,e500
t "site-ls: one access read fails" 10 "access not read (HTTP 500: fixture internal error)|SITES: 2|READ FAILED" - none site-ls
reset_env; X_EVENTS="GET files|GET file"
t "K16 site-cat under the cap prints" 0 "hello" - none site-cat alpha-1 index.html
reset_env; X_EVENTS="GET files"
t "K16 site-cat over the cap by the listing: refused, no fetch" 2 "REFUSED: big.txt is 300000 bytes, above the kit's 204800-byte cap" - none site-cat alpha-1 big.txt
reset_env; X_EVENTS="GET files|GET file"
t "K16 site-cat over the cap by the body: refused, nothing shown" 2 "REFUSED: lies.txt came back as 300000 bytes" "zzzz" none site-cat alpha-1 lies.txt
reset_env; X_EVENTS="GET files|GET file"
t "K16 site-cat cut by curl's --max-filesize: refused" 2 "REFUSED: huge.txt ran past the kit's 204800-byte cap" - none site-cat alpha-1 huge.txt
why=""; grep -q 'maxfs=204800' "$CLOG" || why="the fetch did not carry --max-filesize 204800"
verdict "K16 detail: the fetch carries --max-filesize 204800" "$why"
reset_env
t "site-cat: binary content" 0 "BINARY: 4 bytes, not shown" - none site-cat alpha-1 bin.dat
reset_env
t "site-cat: a path with a space, encoded segment by segment" 0 "abc" - none site-cat alpha-1 "dir/a b.txt"
why=""; grep -qF 'https://here.now/api/v1/publish/alpha-1/files/dir/a%20b.txt' "$CLOG" || why="the URL was not encoded segment by segment: $(cat "$CLOG")"
verdict "site-cat detail: dir/a%20b.txt" "$why"
reset_env
t "site-cat: a path not in the site" 10 "NOT FOUND: nope.txt" - none site-cat alpha-1 nope.txt
reset_env; X_NOCURL=1
why=""
check_ref() {   # check_ref <fragment> <kit arguments...>
  [ -z "$why" ] || return 0
  run_kit "${@:2}"
  if [ "$RC" -ne 2 ] || ! printf '%s' "$OUT" | grep -qF -- "$1" || [ -e "$CLOG" ] || [ -e "$DLOG" ] || [ -e "$LOG" ]; then
    why="'${*:2}' gave exit $RC, expected a refusal carrying '$1' and nothing run. Output: ${OUT:-<none>}"
  fi
}
check_ref "carries a .. segment" site-cat alpha-1 "../secret"
check_ref "carries a .. segment" site-cat alpha-1 "a/../../b"
check_ref "starts with a slash" site-cat alpha-1 "/etc/passwd"
check_ref "carries a backslash" site-cat alpha-1 'a\b'
check_ref "carries a control character" site-cat alpha-1 "$(printf 'a\tb')"
check_ref "outside a-z 0-9 -" site-files Bad_Slug
check_ref "outside a-z 0-9 -" site-cat "x/../y" index.html
check_ref "Usage:" site-files
check_ref "Usage:" site-ls extra
verdict "K17 site paths and slugs refused before any call (.., a leading slash, a backslash, a control character, a bad slug, the argument count)" "$why"
reset_env; X_EVENTS="GET files"
t "K18 site-files: the listing's url fields never fetched" 0 \
  "FILE: index.html (5 bytes, text/html; charset=utf-8)|FILE: dir/a b.txt (3 bytes, text/plain)|FILES: 6|VERSION: ver_fixture_1" "evil.example" none site-files alpha-1
why=""; grep -q 'evil\.example' "$CLOG" "$CLOG.argv" && why="a URL from the response was called"
verdict "K18 detail: only https://here.now/api/v1/ URLs recorded" "$why"

# --- Drive -----------------------------------------------------------------------------------------------
reset_env; C_DTOK="drv_live_fixture_token"
t "K19 drive-ls: the drives, no Drive token passed" 0 '"name":"My Drive"' - none drive-ls
why=""; check_record "$DLOG" "DRIVE-RUN|PWD=$H_BARE|DARG=ls|TOKEN=absent"
verdict "K19 detail: drive-ls ran ls at HOME without HERENOW_DRIVE_TOKEN" "$why"
reset_env; C_DTOK="drv_live_fixture_token"; X_DRIVE="DARG=ls|DARG=My Drive|TOKEN=absent"
t "K19 drive-ls with a drive" 0 '"files"' - none drive-ls "My Drive"
reset_env; C_DTOK="drv_live_fixture_token"; X_DRIVE="DARG=ls|DARG=My Drive|DARG=notes/|TOKEN=absent"
t "K19 drive-ls with a drive and a prefix" 0 '"files"' - none drive-ls "My Drive" "notes/"
reset_env; C_DLS=big
t "drive-ls: a listing past the cap is cut" 0 "TRUNCATED: the listing ran to 300000 bytes" - none drive-ls "My Drive" "notes/"
reset_env; C_DLS=fail
t "drive-ls: the drive script fails" 10 "error: HTTP 404: drive not found|READ FAILED" - none drive-ls "No Drive"
reset_env; C_DTOK="drv_live_fixture_token"; X_DRIVE="DARG=cat|DARG=My Drive|DARG=rules/check-reality.md|TOKEN=absent"
t "K20 drive-cat under the cap" 0 "drive text" - none drive-cat "My Drive" "rules/check-reality.md"
reset_env; C_DCAT=big
t "K20 drive-cat over the cap: refused, nothing printed" 2 "REFUSED: big.txt runs past the kit's 204800-byte cap" "yyyy" none drive-cat "My Drive" big.txt
reset_env; C_DCAT=bin
t "K20 drive-cat binary" 0 "BINARY: 3 bytes, not shown" - none drive-cat "My Drive" bin.dat
reset_env; X_EVENTS="drive put"; X_DRIVE="DARG=put|DARG=My Drive|DARG=rules/check-reality.md|DARG=--from|DARG=$S/rules/check-reality.md|TOKEN=absent"
t "K21 drive-put new (case A, ordered)" 0 \
  "FROM: $(native "$S/rules/check-reality.md") (16 bytes|TO: drive My Drive, path rules/check-reality.md|ORDERED: yes|ACT: new" "ACT: replaces" none \
  drive-put "My Drive" "rules/check-reality.md" --from "$S/rules/check-reality.md" --ordered
reset_env; C_DLS=has; X_EVENTS="drive put"
t "K21 drive-put replaces, with size and etag" 0 'ACT: replaces 42 bytes, etag "e1"' "ORDERED" none \
  drive-put "My Drive" "rules/check-reality.md" --from "$S/rules/check-reality.md"
reset_env; C_DLS=more
t "K21 drive-put: the listing runs past one page" 0 "ACT: new, or replaces a file the first listing page did not show" - none \
  drive-put "My Drive" "rules/check-reality.md" --from "$S/rules/check-reality.md"
reset_env; C_DLS=fail; X_EVENTS="none"
t "drive-put: the listing before the upload fails, nothing uploaded" 10 "nothing was uploaded" - none \
  drive-put "My Drive" "rules/check-reality.md" --from "$S/rules/check-reality.md"
reset_env
why=""
check_ref "does not exist" drive-put "My Drive" "a.md" --from "$S/nothing-here"
check_ref "is a folder" drive-put "My Drive" "a.md" --from "$S/plain"
check_ref "REFUSED: the file's name (id_ecdsa)" drive-put "My Drive" "a.md" --from "$S/id_ecdsa"
check_ref "REFUSED: the file's name (.env)" drive-put "My Drive" "a.md" --from "$S/.env"
check_ref "runs through a .git folder" drive-put "My Drive" "a.md" --from "$S/repo/.git/info/page.html"
check_ref "carries a .. segment" drive-put "My Drive" "../a.md" --from "$S/rules/check-reality.md"
check_ref "starts with a slash" drive-put "My Drive" "/a.md" --from "$S/rules/check-reality.md"
check_ref "carries a backslash" drive-put "My Drive" 'rules\a.md' --from "$S/rules/check-reality.md"
check_ref "carries a control character" drive-put "My Drive" "$(printf 'a\nb')" --from "$S/rules/check-reality.md"
check_ref "the drive name starts with -" drive-put "-x" "a.md" --from "$S/rules/check-reality.md"
check_ref "the drive name is empty" drive-put "" "a.md" --from "$S/rules/check-reality.md"
check_ref "carries a .. segment" drive-cat "My Drive" "../x"
check_ref "carries a .. segment" drive-ls "My Drive" "notes/.."
verdict "K21 drive-put, drive-cat and drive-ls refusals (a missing file, a folder, a secret name, under .git, .., a leading slash, a backslash, a control character, the drive name)" "$why"
if [ -L "$S/link" ]; then
  why=""; check_ref "is a symbolic link" drive-put "My Drive" "a.md" --from "$S/link"
  verdict "K21 drive-put from a symbolic link refused" "$why"
else
  skip "K21 drive-put from a symbolic link refused" "ln -s made no link on this host"
fi
reset_env
why=""
check_ref "--from \"<local-file>\" is missing" drive-put "My Drive" "a.md"
check_ref "--from given twice" drive-put "My Drive" "a.md" --from "$S/rules/check-reality.md" --from "$S/rules/check-reality.md"
check_ref "--from needs a value" drive-put "My Drive" "a.md" --from
check_ref "--ordered given twice" drive-put "My Drive" "a.md" --from "$S/rules/check-reality.md" --ordered --ordered
verdict "K22 --from missing, twice or empty, --ordered twice" "$why"
reset_env
why=""
for c in drive-share drive-rm drive-delete drive-import drive-export drive-tokens drive-revoke drive-create drive-default; do
  check_ref "outside this kit" "$c" "My Drive"
done
check_ref "outside this kit" site-rm alpha-1
verdict "K23 excluded drive.sh commands refused by name, nothing run (9 forms, and a site- one)" "$why"
reset_env
why=""
check_ref "--token: a credential on a command line" drive-put "My Drive" "a.md" --from "$S/rules/check-reality.md" --token t
check_ref "--api-key: a credential on a command line" drive-put "My Drive" "a.md" --from "$S/rules/check-reality.md" --api-key k
check_ref "--base-url: sends the key to an endpoint" drive-put "My Drive" "a.md" --from "$S/rules/check-reality.md" --base-url https://x.example
check_ref "--allow-nonherenow-base-url: sends the key" drive-put "My Drive" "a.md" --from "$S/rules/check-reality.md" --allow-nonherenow-base-url
check_ref "--recursive: an option drive-put does not take" drive-put "My Drive" "a.md" --from "$S/rules/check-reality.md" --recursive
check_ref "--token=t: a credential on a command line" drive-ls --token=t
check_ref "--base-url: sends the key" drive-cat "My Drive" "a.md" --base-url
check_ref "--bogus: site-ls takes no option" site-ls --bogus
check_ref "--token: the kit never passes a key" publish "$S/plain" --token t
verdict "K24 unknown and credential flags refused by name, nothing run" "$why"
reset_env; X_NOCURL=1
t "K25 check never calls curl" 0 "KEY: env" - none check
reset_env; X_NOCURL=1
t "K25 manifest never calls curl" 0 "FILES: 2" - none manifest "$S/plain"

# --- F3: the secret names added -----------------------------------------------------------------------
reset_env
t "F3 a folder holding id_ed25519" 2 "REFUSED: the folder holds keys/id_ed25519," - none manifest "$S/withssh"
t "F3 a folder holding .netrc" 2 "REFUSED: the folder holds .netrc," - none manifest "$S/withnetrc"
t "F3 a folder holding a *.p12, any case" 2 "REFUSED: the folder holds Client.P12," - none publish "$S/withp12"

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
