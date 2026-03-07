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

TORRENT_THREADS="${TORRENT_THREADS:-16}"
TORRENT_COMMENT="${TORRENT_COMMENT:-Created on Silasplex}"

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
  local size_kb size_gb

  size_kb="$(du -s "$path" | awk '{print $1}')"
  size_gb=$(( size_kb / 1024 / 1024 ))

  if (( size_gb < 8 )); then
    echo 20   # 1 MiB
  elif (( size_gb < 50 )); then
    echo 22   # 4 MiB
  elif (( size_gb < 200 )); then
    echo 23   # 8 MiB
  else
    echo 24   # 16 MiB
  fi
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

write_nfo() {
  local video="${1:-}" out="${2:-}"
  [[ -n "$video" && -n "$out" ]] || return 1

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "DRY_RUN: NFO -> $out"
    return 0
  fi

  if [[ "${MEDIAINFO_AVAILABLE:-0}" != "1" ]]; then
    echo "Skipping NFO generation (mediainfo missing): $out"
    return 0
  fi

  mkdir -p "$(dirname "$out")"
  mediainfo "$video" > "$out"
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
  local path
  for path in "$@"; do
    [[ -e "$path" ]] || continue
    chown nobody:users "$path" 2>/dev/null || true
    chmod 664 "$path" 2>/dev/null || true
  done
}

build_torrent() {
  local payload_path="${1:-}" out_torrent="${2:-}" piece_exp="${3:-}"
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

  local -a args=(-a "$ANNOUNCE" -l "$piece_exp" -o "$out_torrent" -t "$TORRENT_THREADS")
  [[ "$PRIVATE_FLAG" == "1" ]] && args+=(-p)
  [[ -n "${TORRENT_COMMENT:-}" ]] && args+=(-c "$TORRENT_COMMENT")

  if [[ "$SHOW_PROGRESS" == "1" ]]; then
    (cd "$mount_src" && mktorrent "${args[@]}" -- "$target")
  else
    (cd "$mount_src" && mktorrent "${args[@]}" -- "$target" >/dev/null)
  fi
}
