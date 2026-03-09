#!/usr/bin/env bash
set -euo pipefail

CONFIG_ENV="${CONFIG_ENV:-/config/config.env}"
[[ -f "$CONFIG_ENV" ]] || { echo "Missing $CONFIG_ENV" >&2; exit 1; }

# shellcheck disable=SC1090
source "$CONFIG_ENV"

MEDIA_ROOT="${MEDIA_ROOT:-/MEDIA}"
OUTPUT_ROOT="${OUTPUT_ROOT:-/TORRENTS}"
DEFAULT_TEAM="${DEFAULT_TEAM:-NOTAG}"
PREFERRED_LANG_MULTI="${PREFERRED_LANG_MULTI:-MULTI}"
ANNOUNCE="${ANNOUNCE:-}"
PRIVATE_FLAG="${PRIVATE_FLAG:-1}"
SHOW_PROGRESS="${SHOW_PROGRESS:-1}"
SKIP_EXISTING="${SKIP_EXISTING:-1}"
DRY_RUN="${DRY_RUN:-0}"
PAGE_SIZE="${PAGE_SIZE:-20}"

TORRENT_THREADS="${TORRENT_THREADS:-}"
TORRENT_PIECE_MODE="${TORRENT_PIECE_MODE:-fast}"
TORRENT_PIECE_EXP="${TORRENT_PIECE_EXP:-}"
TORRENT_COMMENT="${TORRENT_COMMENT:-Created on Silasplex}"
OUTPUT_UID="${OUTPUT_UID:-99}"
OUTPUT_GID="${OUTPUT_GID:-100}"
OUTPUT_UMASK="${OUTPUT_UMASK:-0002}"

# 0 = direct torrent from source
# 1 = use staging directory
USE_STAGING="${USE_STAGING:-0}"
STAGING_DIR="${STAGING_DIR:-/STAGING/torrent-creator}"
STAGING_MIN_FREE_GB="${STAGING_MIN_FREE_GB:-20}"

MOVIE_ROOTS=("MOVIES_ENG" "MOVIES_FR" "MOVIES_4K" "STAND-UP" "DOC" "LIVE" "LIVE_TV")
SERIES_ROOTS=("SERIES" "SERIES_4K" "SERIES_FR_ONLY" "ANIME" "ANIME_FR" "ANIME_SERIES")
VIDEO_EXTENSIONS=("*.mkv" "*.mp4" "*.m2ts" "*.avi" "*.ts" "*.mov" "*.wmv")

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
have(){ command -v "$1" >/dev/null 2>&1; }
status(){ echo "==> $*"; }
press_enter(){ read -r -p "Press Enter to continue..." _; }

common_init() {
  local c
  for c in curl jq python3 mktorrent stat du df find sort awk sed grep cp mkdir rm realpath mktemp; do
    need "$c"
  done

  if have mediainfo; then
    MEDIAINFO_AVAILABLE=1
  else
    MEDIAINFO_AVAILABLE=0
    echo "WARNING: mediainfo not found, NFO generation will be skipped."
  fi

  [[ -n "$ANNOUNCE" ]] || { echo "ANNOUNCE is empty in $CONFIG_ENV" >&2; exit 1; }
  TORRENT_THREADS="${TORRENT_THREADS:-$(nproc 2>/dev/null || echo 16)}"
  umask "$OUTPUT_UMASK"
  mkdir -p "$OUTPUT_ROOT"

  if [[ "$USE_STAGING" == "1" ]]; then
    mkdir -p "$STAGING_DIR"
    check_staging_space
  fi
}

term_width() {
  local w
  w="$( (tput cols 2>/dev/null) || true )"
  echo "${w:-80}"
}

prompt() {
  local m="${1:-}" d="${2:-}" v
  if [[ -n "$d" ]]; then
    read -r -p "$m [$d]: " v
    echo "${v:-$d}"
  else
    read -r -p "$m: " v
    echo "$v"
  fi
}

api_get() {
  local url="${1:-}" key="${2:-}"
  [[ -n "$url" && -n "$key" ]] || return 1
  curl -fsS --max-time 120 -H "X-Api-Key: $key" "$url"
}

extract_title_year_from_folder() {
  python3 - "${1:-}" <<'PY'
import sys, os, re
name=os.path.basename((sys.argv[1] if len(sys.argv)>1 else "").rstrip("/"))
m=re.search(r"\((\d{4})\)", name)
year=m.group(1) if m else ""
title=re.sub(r"\s*\(\d{4}\)\s*$", "", name).strip()
print(title)
print(year)
PY
}

safe_relpath() {
  python3 - "${1:-}" "${2:-}" <<'PY'
import os,sys
a=sys.argv[1] if len(sys.argv)>1 else "."
b=sys.argv[2] if len(sys.argv)>2 else "."
print(os.path.relpath(os.path.realpath(a), os.path.realpath(b)))
PY
}

norm_path() {
  python3 - "${1:-}" <<'PY'
import os,sys,re
p=sys.argv[1] if len(sys.argv)>1 else ""
p=os.path.realpath(p)
p=p.replace("\\","/")
p=re.sub(r"/+","/",p)
print(p.rstrip("/"))
PY
}

calc_piece_exp() {
  python3 - "${1:-0}" <<'PY'
import sys
b=int(sys.argv[1]); g=1024**3
print(20 if b<1*g else 21 if b<2*g else 22 if b<3*g else 23 if b<8*g else 24)
PY
}

choose_piece_size() {
  local path="${1:-}"
  local size_kb size_gb mode profile

  [[ -n "$path" && -e "$path" ]] || return 1

  if [[ -n "${TORRENT_PIECE_EXP:-}" ]]; then
    echo "$TORRENT_PIECE_EXP"
    return 0
  fi

  size_kb="$(du -s "$path" | awk '{print $1}')"
  size_gb=$(( size_kb / 1024 / 1024 ))

  mode="${TORRENT_PIECE_MODE:-tracker}"
  profile="${TORRENT_PIECE_PROFILE:-auto}"

  if [[ "$profile" == "auto" ]]; then
    case "${TRACKER_NAME:-${ANNOUNCE_URL:-${ANNOUNCE:-}}}" in
      *C411*|*c411*|*cinemaz*|*cinemageddon*)
        profile="c411"
        ;;
      *)
        profile="default"
        ;;
    esac
  fi

  case "$mode:$profile" in
    tracker:c411|*:c411)
      if   (( size_gb < 1 )); then echo 20
      elif (( size_gb < 2 )); then echo 21
      elif (( size_gb < 3 )); then echo 22
      elif (( size_gb < 8 )); then echo 23
      else                         echo 24
      fi
      ;;
    fast:*)
      if   (( size_gb < 2 ));   then echo 22
      elif (( size_gb < 8 ));   then echo 23
      elif (( size_gb < 30 ));  then echo 24
      elif (( size_gb < 120 )); then echo 25
      else                           echo 26
      fi
      ;;
    normal:*|tracker:*|*)
      if   (( size_gb < 1 ));   then echo 20
      elif (( size_gb < 2 ));   then echo 21
      elif (( size_gb < 3 ));   then echo 22
      elif (( size_gb < 8 ));   then echo 23
      else                           echo 24
      fi
      ;;
  esac
}


piece_exp_to_mib() {
  local exp="${1:-}"
  case "$exp" in
    20) echo "1" ;;
    21) echo "2" ;;
    22) echo "4" ;;
    23) echo "8" ;;
    24) echo "16" ;;
    25) echo "32" ;;
    26) echo "64" ;;
    *) echo "?" ;;
  esac
}

current_piece_size_label() {
  if [[ -n "${TORRENT_PIECE_EXP:-}" ]]; then
    echo "Manual ($(piece_exp_to_mib "$TORRENT_PIECE_EXP") MiB)"
    return 0
  fi

  case "${TORRENT_PIECE_MODE:-tracker}" in
    fast)
      echo "Fast"
      ;;
    tracker)
      case "${TORRENT_PIECE_PROFILE:-auto}" in
        c411) echo "Auto (C411)" ;;
        auto) echo "Auto (tracker)" ;;
        *)    echo "Auto (${TORRENT_PIECE_PROFILE})" ;;
      esac
      ;;
    normal)
      echo "Normal"
      ;;
    *)
      echo "${TORRENT_PIECE_MODE:-tracker}"
      ;;
  esac
}

set_piece_mode_auto() {
  TORRENT_PIECE_MODE="tracker"
  TORRENT_PIECE_PROFILE="auto"
  TORRENT_PIECE_EXP=""
}

set_piece_mode_fast() {
  TORRENT_PIECE_MODE="fast"
  TORRENT_PIECE_EXP=""
}

set_piece_mode_normal() {
  TORRENT_PIECE_MODE="normal"
  TORRENT_PIECE_EXP=""
}

set_piece_mode_manual_exp() {
  local exp="${1:-}"
  [[ -n "$exp" ]] || return 1
  TORRENT_PIECE_MODE="manual"
  TORRENT_PIECE_EXP="$exp"
}

configure_piece_size_manual_menu() {
  local profile resolved choice
  profile="${TORRENT_PIECE_PROFILE:-auto}"
  resolved="$profile"

  if [[ "$resolved" == "auto" ]]; then
    case "${TRACKER_NAME:-${ANNOUNCE_URL:-${ANNOUNCE:-}}}" in
      *C411*|*c411*|*cinemaz*|*cinemageddon*)
        resolved="c411"
        ;;
      *)
        resolved="default"
        ;;
    esac
  fi

  while true; do
    echo
    echo "Manual hash piece size"
    if [[ "$resolved" == "c411" ]]; then
      echo "Tracker profile : C411"
      echo "Allowed sizes   : 1 / 2 / 4 / 8 / 16 MiB"
      echo " 1) 1 MiB"
      echo " 2) 2 MiB"
      echo " 3) 4 MiB"
      echo " 4) 8 MiB"
      echo " 5) 16 MiB"
      echo " 0) Back"
    else
      echo "Tracker profile : Generic"
      echo " 1) 1 MiB"
      echo " 2) 2 MiB"
      echo " 3) 4 MiB"
      echo " 4) 8 MiB"
      echo " 5) 16 MiB"
      echo " 6) 32 MiB"
      echo " 7) 64 MiB"
      echo " 0) Back"
    fi

    read -r -p "Select: " choice
    case "$resolved:$choice" in
      c411:1|default:1) set_piece_mode_manual_exp 20; return 0 ;;
      c411:2|default:2) set_piece_mode_manual_exp 21; return 0 ;;
      c411:3|default:3) set_piece_mode_manual_exp 22; return 0 ;;
      c411:4|default:4) set_piece_mode_manual_exp 23; return 0 ;;
      c411:5|default:5) set_piece_mode_manual_exp 24; return 0 ;;
      default:6)        set_piece_mode_manual_exp 25; return 0 ;;
      default:7)        set_piece_mode_manual_exp 26; return 0 ;;
      c411:0|default:0) return 0 ;;
      *) echo "Invalid" ;;
    esac
  done
}

configure_piece_size_menu() {
  local choice
  while true; do
    echo
    echo "Hash piece size"
    echo "Current : $(current_piece_size_label)"
    echo " 1) Auto (tracker rules)"
    echo " 2) Fast"
    echo " 3) Normal"
    echo " 4) Manual"
    echo " 0) Back"
    read -r -p "Select: " choice

    case "$choice" in
      1) set_piece_mode_auto;   echo "Set: $(current_piece_size_label)"; return 0 ;;
      2) set_piece_mode_fast;   echo "Set: $(current_piece_size_label)"; return 0 ;;
      3) set_piece_mode_normal; echo "Set: $(current_piece_size_label)"; return 0 ;;
      4) configure_piece_size_manual_menu; echo "Set: $(current_piece_size_label)"; return 0 ;;
      0) return 0 ;;
      *) echo "Invalid" ;;
    esac
  done
}

slug_release() {
  python3 - "${1:-}" <<'PY'
import sys,re,unicodedata
s=sys.argv[1]
s=unicodedata.normalize("NFKD", s).encode("ascii","ignore").decode()
s=s.replace("&","And")
s=re.sub(r"[^A-Za-z0-9]+",".",s)
s=re.sub(r"\.+",".",s).strip(".")
print(s)
PY
}

pick_from_list_paged() {
  local title="${1:-}"; shift || true
  local page_size="${PAGE_SIZE}"
  local -a all=("$@")
  local -a items=("${all[@]}")
  local filter="" page=0

  apply_filter() {
    items=()
    if [[ -z "$filter" ]]; then
      items=("${all[@]}")
      return
    fi
    local f="${filter,,}" it name
    for it in "${all[@]}"; do
      name="$(basename "$it")"
      [[ "${name,,}" == *"$f"* ]] && items+=("$it")
    done
  }

  render_page() {
    local total="${#items[@]}"
    local total_pages=$(( (total + page_size - 1) / page_size ))
    (( total_pages < 1 )) && total_pages=1
    (( page < 0 )) && page=0
    (( page >= total_pages )) && page=$((total_pages - 1))
    local start=$((page * page_size))
    local end=$((start + page_size))
    (( end > total )) && end=$total

    echo >&2
    echo >&2 "$title  (items: $total)  filter: ${filter:-<none>}  page: $((page + 1))/$total_pages"
    echo >&2 "------------------------------------------------------------"

    local i display=1
    for ((i=start; i<end; i++)); do
      printf >&2 " %2d) %s\n" "$display" "$(basename "${items[$i]}")"
      ((display++))
    done

    echo >&2 "------------------------------------------------------------"
    echo >&2 "Pick: number | space/n=next | p=prev | /=filter | q=cancel"
  }

  apply_filter

  while true; do
    if [[ "${#items[@]}" -eq 0 ]]; then
      echo >&2
      echo >&2 "$title  (no matches for filter: $filter)"
      echo >&2 "Type / to change filter, or q to cancel."
    else
      render_page
    fi

    local choice
    IFS= read -r -p "Select: " choice || true
    [[ "$choice" == " " ]] && choice="n"

    case "${choice:-}" in
      q|Q|0) echo ""; return 1 ;;
      n|N|"") ((page=page+1)) ;;
      p|P) ((page=page-1)); (( page < 0 )) && page=0 ;;
      /)
        filter="$(prompt "Filter (substring, empty=clear)" "$filter")"
        apply_filter
        page=0
        ;;
      *)
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
          local visible_idx=$((choice - 1))
          local abs_idx=$((page * page_size + visible_idx))
          if (( visible_idx >= 0 && abs_idx < ${#items[@]} )); then
            echo "${items[$abs_idx]}"
            return 0
          else
            echo "Out of range." >&2
          fi
        else
          echo "Invalid input." >&2
        fi
        ;;
    esac
  done
}

select_movie_root() {
  local -a candidates=()
  local r
  for r in "${MOVIE_ROOTS[@]}"; do
    [[ -d "$MEDIA_ROOT/$r" ]] && candidates+=("$MEDIA_ROOT/$r")
  done
  pick_from_list_paged "Select a movie root:" "${candidates[@]}"
}

select_series_root() {
  local -a candidates=()
  local r
  for r in "${SERIES_ROOTS[@]}"; do
    [[ -d "$MEDIA_ROOT/$r" ]] && candidates+=("$MEDIA_ROOT/$r")
  done
  pick_from_list_paged "Select a series root:" "${candidates[@]}"
}

pick_main_video() {
  find "$1" -maxdepth 2 -type f \( \
    -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.m2ts" -o \
    -iname "*.avi" -o -iname "*.ts" -o -iname "*.mov" -o -iname "*.wmv" \
  \) -printf "%s\t%p\n" | sort -nr | head -n1 | awk -F'\t' '{print $2}'
}

container_media_path() {
  local p="${1:-}"
  [[ -n "$p" ]] || return 1

  case "$p" in
    /MEDIA/*)
      echo "$p"
      ;;
    /mnt/MEDIA/*)
      echo "/MEDIA/${p#/mnt/MEDIA/}"
      ;;
    /mnt/user/MEDIA/*)
      echo "/MEDIA/${p#/mnt/user/MEDIA/}"
      ;;
    *)
      echo "$p"
      ;;
  esac
}


mediainfo_cache_root() {
  local root="${TORRENTARR_MEDIAINFO_CACHE_DIR:-/tmp/torrentarr_mediainfo_cache}"
  mkdir -p "$root"
  echo "$root"
}

mediainfo_cache_key() {
  local video="${1:-}" size mtime raw
  [[ -n "$video" && -f "$video" ]] || return 1

  size="$(stat -c '%s' "$video" 2>/dev/null || echo 0)"
  mtime="$(stat -c '%Y' "$video" 2>/dev/null || echo 0)"
  raw="${video}|${size}|${mtime}"

  if command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$raw" | sha1sum | awk '{print $1}'
  else
    python3 - "$raw" <<'PY2'
import sys, hashlib
print(hashlib.sha1(sys.argv[1].encode('utf-8')).hexdigest())
PY2
  fi
}

mediainfo_cache_file() {
  local video="${1:-}" root key
  [[ -n "$video" ]] || return 1
  root="$(mediainfo_cache_root)"
  key="$(mediainfo_cache_key "$video")" || return 1
  echo "$root/${key}.txt"
}

write_nfo_from_cache_file() {
  local cache_file="${1:-}" out="${2:-}" tmp_out
  [[ -n "$cache_file" && -f "$cache_file" && -n "$out" ]] || return 1

  mkdir -p "$(dirname "$out")"
  tmp_out="$(mktemp /tmp/torrentarr_nfo.XXXXXX)" || return 1
  cp -f "$cache_file" "$tmp_out" || { rm -f "$tmp_out"; return 1; }
  mv -f "$tmp_out" "$out"
}

mediainfo_cached_dump() {
  local actual_video="${1:-}" cache_file tmp_cache
  [[ -n "$actual_video" && -f "$actual_video" ]] || return 1

  cache_file="$(mediainfo_cache_file "$actual_video")" || return 1
  if [[ -s "$cache_file" ]]; then
    echo "$cache_file"
    return 0
  fi

  tmp_cache="$(mktemp /tmp/torrentarr_mediainfo.XXXXXX)" || return 1
  if ! mediainfo "$actual_video" > "$tmp_cache"; then
    rm -f "$tmp_cache"
    echo "ERROR: mediainfo failed for: $actual_video" >&2
    return 1
  fi

  if [[ ! -s "$tmp_cache" ]]; then
    rm -f "$tmp_cache"
    echo "ERROR: Empty mediainfo output for: $actual_video" >&2
    return 1
  fi

  mkdir -p "$(dirname "$cache_file")"
  cp -f "$tmp_cache" "$cache_file" 2>/dev/null || true
  echo "$tmp_cache"
}

write_nfo() {
  local video="${1:-}" out="${2:-}" actual_video cache_or_tmp
  [[ -n "$video" && -n "$out" ]] || return 1

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "DRY_RUN: NFO -> $out"
    return 0
  fi

  if [[ "${MEDIAINFO_AVAILABLE:-0}" != "1" ]]; then
    echo "Skipping NFO generation (mediainfo missing): $out"
    return 0
  fi

  actual_video="$(container_media_path "$video")"

  if [[ ! -f "$actual_video" ]]; then
    echo "ERROR: NFO source video not found: $video -> $actual_video" >&2
    return 1
  fi

  cache_or_tmp="$(mediainfo_cached_dump "$actual_video")" || return 1

  if ! write_nfo_from_cache_file "$cache_or_tmp" "$out"; then
    if [[ "$cache_or_tmp" == /tmp/torrentarr_mediainfo.* ]]; then
      rm -f "$cache_or_tmp"
    fi
    return 1
  fi

  if [[ "$cache_or_tmp" == /tmp/torrentarr_mediainfo.* ]]; then
    rm -f "$cache_or_tmp"
  fi

  return 0
}

_should_skip_path() {
  local rel="${1:-}"
  local base
  base="$(basename "$rel")"

  [[ "$rel" == *"/.@__thumb/"* ]] && return 0
  [[ "$rel" == .@__thumb/* ]] && return 0
  [[ "$rel" == *"/.DS_Store" ]] && return 0
  [[ "$base" == ".DS_Store" ]] && return 0
  [[ "$base" == "Thumbs.db" ]] && return 0
  [[ "$base" == *.jpg || "$base" == *.jpeg || "$base" == *.png || "$base" == *.webp ]] && return 0
  [[ "$base" == *.JPG || "$base" == *.JPEG || "$base" == *.PNG || "$base" == *.WEBP ]] && return 0
  [[ "$base" == *.nfo || "$base" == *.NFO ]] && return 0
  [[ "$base" == *.txt || "$base" == *.TXT ]] && return 0
  [[ "$base" == *.sfv || "$base" == *.SFV ]] && return 0
  [[ "$base" == *.srr || "$base" == *.SRR ]] && return 0
  [[ "$base" == *.xml || "$base" == *.XML ]] && return 0
  [[ "$base" == *.metathumb || "$base" == *.METATHUMB ]] && return 0
  [[ "$base" == *.srt || "$base" == *.sub || "$base" == *.idx ]] && return 0
  [[ "$base" == *.SRT || "$base" == *.SUB || "$base" == *.IDX ]] && return 0
  [[ "$rel" == sample/* || "$rel" == Sample/* ]] && return 0
  [[ "$base" == *.sample.mkv || "$base" == *.sample.mp4 || "$base" == *.sample.avi || "$base" == *.sample.m2ts ]] && return 0

  return 1
}

check_staging_space() {
  [[ "$USE_STAGING" == "1" ]] || return 0

  local free_gb
  free_gb="$(df -BG "$STAGING_DIR" | awk 'NR==2 {gsub(/G/,"",$4); print $4}')"
  free_gb="${free_gb:-0}"

  if (( free_gb < STAGING_MIN_FREE_GB )); then
    echo "ERROR: Not enough free space in staging: ${free_gb} GB free, ${STAGING_MIN_FREE_GB} GB required." >&2
    return 1
  fi
}

_prepare_clean_payload_dir() {
  local src_dir="${1:-}"
  local stage_root stage_dir rel src dst copied=0

  check_staging_space || return 1

  stage_root="$(mktemp -d "${STAGING_DIR}/payload.XXXXXX")"
  stage_dir="$stage_root/$(basename "$src_dir")"
  mkdir -p "$stage_dir"

  while IFS= read -r src; do
    rel="${src#"$src_dir"/}"
    if _should_skip_path "$rel"; then
      continue
    fi
    dst="$stage_dir/$rel"
    mkdir -p "$(dirname "$dst")"

    if ! cp -al "$src" "$dst" 2>/dev/null; then
      if ! cp -a "$src" "$dst"; then
        echo "ERROR: Failed to stage file: $src" >&2
        rm -rf "$stage_root"
        return 1
      fi
    fi

    copied=1
  done < <(find "$src_dir" -type f | sort)

  if [[ "$copied" -eq 0 ]]; then
    rm -rf "$stage_root"
    return 1
  fi

  echo "$stage_dir"
}

cleanup_payload_dir() {
  local payload_path="${1:-}"
  [[ -n "$payload_path" ]] || return 0

  if [[ "$USE_STAGING" == "1" && "$payload_path" == "$STAGING_DIR"/payload.*/* ]]; then
    rm -rf "$(dirname "$payload_path")"
  fi
}

get_payload_dir() {
  local src="${1:-}"
  [[ -n "$src" ]] || return 1

  local src_abs
  src_abs="$(realpath "$src")"
  [[ -e "$src_abs" ]] || { echo "Payload not found: $src_abs" >&2; return 1; }

  if [[ "$USE_STAGING" == "1" && -d "$src_abs" ]]; then
    _prepare_clean_payload_dir "$src_abs"
  else
    echo "$src_abs"
  fi
}

prepare_output_slot() {
  local out_torrent="${1:-}"
  [[ -n "$out_torrent" ]] || return 1

  local out_dir target_base f other_base sibling_nfo
  out_dir="$(dirname "$out_torrent")"
  target_base="$(basename "$out_torrent")"

  mkdir -p "$out_dir"

  if [[ "$SKIP_EXISTING" == "1" && -f "$out_torrent" ]]; then
    echo "Skip existing: $out_torrent"
    return 10
  fi

  shopt -s nullglob
  for f in "$out_dir"/*.torrent; do
    [[ -f "$f" ]] || continue
    other_base="$(basename "$f")"
    [[ "$other_base" == "$target_base" ]] && continue

    echo "Replacing existing torrent with new name:"
    echo " - old: $f"
    echo " - new: $out_torrent"
    rm -f -- "$f"

    sibling_nfo="${f%.torrent}.nfo"
    [[ -f "$sibling_nfo" ]] && rm -f -- "$sibling_nfo"
  done
  shopt -u nullglob

  return 0
}

fix_output_permissions() {
  local path parent
  for path in "$@"; do
    [[ -e "$path" ]] || continue

    if [[ -d "$path" ]]; then
      chown "$OUTPUT_UID:$OUTPUT_GID" "$path" 2>/dev/null || true
      chmod 775 "$path" 2>/dev/null || true
      continue
    fi

    chown "$OUTPUT_UID:$OUTPUT_GID" "$path" 2>/dev/null || true
    chmod 664 "$path" 2>/dev/null || true

    parent="$(dirname "$path")"
    if [[ -d "$parent" ]]; then
      chown "$OUTPUT_UID:$OUTPUT_GID" "$parent" 2>/dev/null || true
      chmod 775 "$parent" 2>/dev/null || true
    fi
  done
}

fix_output_permissions_recursive() {
  local path
  for path in "$@"; do
    [[ -e "$path" ]] || continue
    chown -R "$OUTPUT_UID:$OUTPUT_GID" "$path" 2>/dev/null || true
    find "$path" -type d -exec chmod 775 {} \; 2>/dev/null || true
    find "$path" -type f -exec chmod 664 {} \; 2>/dev/null || true
  done
}


collect_video_files() {
  local root="${1:-}"
  [[ -d "$root" ]] || return 1

  find "$root" -type f \( \
    -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.m2ts" -o \
    -iname "*.avi" -o -iname "*.ts" -o -iname "*.mov" -o -iname "*.wmv" \
  \) ! -path "*/.@__thumb/*" -print | sort | while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    printf '%s
' "$f"
  done
}

prepare_release_payload() {
  local source_root="${1:-}" payload_name="${2:-}" nfo_file="${3:-}"
  shift 3 || true
  local -a include_files=("$@")

  [[ -n "$source_root" && -n "$payload_name" && -n "$nfo_file" ]] || return 1
  [[ -d "$source_root" ]] || return 1
  [[ -f "$nfo_file" ]] || return 1

  mkdir -p "$STAGING_DIR"
  check_staging_space || return 1

  local stage_root payload_dir src rel dst copied=0
  stage_root="$(mktemp -d "${STAGING_DIR}/payload.XXXXXX")"
  payload_dir="$stage_root/$payload_name"
  mkdir -p "$payload_dir"

  for src in "${include_files[@]}"; do
    [[ -f "$src" ]] || continue

    if [[ "$src" == "$nfo_file" ]]; then
      dst="$payload_dir/$(basename "$nfo_file")"
    else
      rel="$(safe_relpath "$src" "$source_root")"
      dst="$payload_dir/$rel"
    fi

    mkdir -p "$(dirname "$dst")"

    if ! cp -al "$src" "$dst" 2>/dev/null; then
      if ! cp -a "$src" "$dst"; then
        echo "ERROR: Failed to stage file: $src" >&2
        rm -rf "$stage_root"
        return 1
      fi
    fi
    copied=1
  done

  if [[ "$copied" -eq 0 ]]; then
    rm -rf "$stage_root"
    echo "ERROR: No files included in payload." >&2
    return 1
  fi

  echo "$payload_dir"
}


should_use_direct_series_hash() {
  local scope_path="${1:-}" payload_root="${2:-}"
  [[ "${USE_DIRECT_SERIES_HASH:-0}" == "1" ]] || return 1
  [[ -n "$scope_path" && -n "$payload_root" ]] || return 1

  # Only for directory-based releases (season / integrale), not single episode files
  [[ -d "$scope_path" ]] || return 1
  [[ -d "$payload_root" ]] || return 1

  return 0
}

print_recheck_hint() {
  local payload_dir="${1:-}" source_hint="${2:-}"
  [[ -n "$payload_dir" ]] || return 0

  local torrent_root parent_hint
  torrent_root="$(basename "$payload_dir")"

  if [[ -n "${source_hint:-}" ]]; then
    if [[ -d "$source_hint" ]]; then
      parent_hint="$(dirname "$source_hint")"
    else
      parent_hint="$(dirname "$(dirname "$source_hint")")"
    fi
  else
    parent_hint=""
  fi

  echo
  echo "Recheck hint"
  echo "------------"
  echo "Torrent root : $torrent_root"
  if [[ -n "$parent_hint" ]]; then
    echo "Use in qBittorrent as save path:"
    echo "  $parent_hint"
  else
    echo "Use in qBittorrent as save path:"
    echo "  parent folder of: $torrent_root"
  fi
  echo
}

build_torrent() {
  local payload_path="${1:-}" out_torrent="${2:-}" piece_exp="${3:-}" torrent_display_name="${4:-}"
  [[ -n "$payload_path" && -n "$out_torrent" ]] || return 1

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "DRY_RUN: TORRENT -> $out_torrent"
    return 0
  fi

  mkdir -p "$(dirname "$out_torrent")"

  local payload_abs mount_src target
  payload_abs="$(realpath "$payload_path")"
  [[ -e "$payload_abs" ]] || { echo "Payload not found: $payload_abs" >&2; return 1; }

  if [[ -z "${piece_exp:-}" ]]; then
    piece_exp="$(choose_piece_size "$payload_abs")"
  fi

  mount_src="$(dirname "$payload_abs")"
  target="$(basename "$payload_abs")"

  local threads
  threads="${TORRENT_THREADS:-$(nproc 2>/dev/null || echo 16)}"

  local -a args=(-a "$ANNOUNCE" -l "$piece_exp" -o "$out_torrent" -t "$threads")
  [[ "$PRIVATE_FLAG" == "1" ]] && args+=(-p)
  [[ -n "${TORRENT_COMMENT:-}" ]] && args+=(-c "$TORRENT_COMMENT")

  local -a runner=()
  command -v ionice >/dev/null 2>&1 && runner+=(ionice -c2 -n7)
  command -v nice   >/dev/null 2>&1 && runner+=(nice -n 10)

  if [[ "$SHOW_PROGRESS" == "1" ]]; then
    echo "Torrent file name : $(basename "$out_torrent")"
    echo "Torrent root      : $target"
    echo "mktorrent threads : $threads"
    echo "piece exponent    : $piece_exp"
    (cd "$mount_src" && "${runner[@]}" mktorrent "${args[@]}" -- "$target")
  else
    (cd "$mount_src" && "${runner[@]}" mktorrent "${args[@]}" -- "$target" >/dev/null)
  fi
}
