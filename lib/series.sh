#!/usr/bin/env bash

find_sonarr_series_by_path_or_name() {
  local folder_path="${1:-}" api_url="${2:-}" api_key="${3:-}"
  [[ -n "$folder_path" && -n "$api_url" && -n "$api_key" ]] || return 1

  local tmp_json title year
  tmp_json="$(mktemp /tmp/sonarr_series.XXXXXX.json)"
  mapfile -t ty < <(extract_title_year_from_folder "$folder_path")
  title="${ty[0]:-}"
  year="${ty[1]:-}"

  if ! api_get "${api_url%/}/api/v3/series" "$api_key" > "$tmp_json"; then
    rm -f "$tmp_json"
    return 1
  fi

  python3 - "$folder_path" "$title" "$year" "$tmp_json" <<'PY'
import sys, json, re, unicodedata, os

folder_path=sys.argv[1].strip()
title=sys.argv[2].strip()
year=sys.argv[3].strip()
json_file=sys.argv[4]

def norm_text(s: str) -> str:
    s=unicodedata.normalize("NFKD", s or "").encode("ascii","ignore").decode()
    s=s.lower().strip().replace("&", "and")
    s=re.sub(r"[^a-z0-9]+", " ", s)
    s=re.sub(r"\s+", " ", s).strip()
    return s

def norm_path(p: str) -> str:
    p=(p or "").strip().replace("\\","/")
    p=re.sub(r"/+","/",p)
    return os.path.normpath(p)

def equivalent_paths(p: str):
    p=norm_path(p)
    out={p}
    if p.startswith("/MEDIA/"):
        s=p[len("/MEDIA/"):]
        out.add(norm_path("/mnt/MEDIA/" + s))
        out.add(norm_path("/mnt/user/MEDIA/" + s))
    elif p.startswith("/mnt/MEDIA/"):
        s=p[len("/mnt/MEDIA/"):]
        out.add(norm_path("/MEDIA/" + s))
        out.add(norm_path("/mnt/user/MEDIA/" + s))
    elif p.startswith("/mnt/user/MEDIA/"):
        s=p[len("/mnt/user/MEDIA/"):]
        out.add(norm_path("/MEDIA/" + s))
        out.add(norm_path("/mnt/MEDIA/" + s))
    return out

want_title=norm_text(title)
want_paths=equivalent_paths(folder_path)

with open(json_file, "r", encoding="utf-8") as f:
    data=json.load(f)

for item in data:
    spath=item.get("path") or ""
    if norm_path(spath) in want_paths:
        print(json.dumps(item))
        raise SystemExit(0)

candidates=[]
for m in data:
    titles=[m.get("title",""), m.get("sortTitle","")]
    series_year=str(m.get("year") or "")
    score=0
    for t in titles:
        nt=norm_text(t)
        if nt == want_title:
            score=max(score, 100)
        elif want_title and nt.startswith(want_title):
            score=max(score, 90)
        elif want_title and want_title in nt:
            score=max(score, 80)
    if year and series_year == year:
        score += 20
    if score > 0:
        candidates.append((score, m))

candidates.sort(key=lambda x: x[0], reverse=True)
if not candidates:
    raise SystemExit(1)

print(json.dumps(candidates[0][1]))
PY
  local rc=$?
  rm -f "$tmp_json"
  return $rc
}

sonarr_episode_files_for_series() {
  local series_id="${1:-}" api_url="${2:-}" api_key="${3:-}"
  [[ -n "$series_id" && -n "$api_url" && -n "$api_key" ]] || return 1

  local tmp_json
  tmp_json="$(mktemp /tmp/sonarr_episodes.XXXXXX.json)"

  if ! api_get "${api_url%/}/api/v3/episode?seriesId=${series_id}&includeEpisodeFile=true" "$api_key" > "$tmp_json"; then
    rm -f "$tmp_json"
    return 1
  fi

  if ! python3 - <<'PY' "$tmp_json" >/dev/null 2>&1
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    json.load(f)
PY
  then
    echo "ERROR: Sonarr returned invalid JSON for seriesId=${series_id}" >&2
    sed -n '1,80p' "$tmp_json" >&2
    rm -f "$tmp_json"
    return 1
  fi

  python3 - "$tmp_json" <<'PY'
import sys, json
with open(sys.argv[1], "r", encoding="utf-8") as f:
    data=json.load(f)

out=[]
seen=set()
for ep in data:
    ef=ep.get("episodeFile")
    if not ef:
        continue
    path=(ef.get("path") or "").strip()
    if not path or path in seen:
        continue
    seen.add(path)
    item=dict(ef)
    item["seasonNumber"]=ep.get("seasonNumber")
    item["episodeNumber"]=ep.get("episodeNumber")
    item["title"]=ep.get("title")
    out.append(item)

print(json.dumps(out))
PY

  local rc=$?
  rm -f "$tmp_json"
  return $rc
}

series_plan_from_json() {
  local raw="${1:-}"
  RAW_JSON="$raw" python3 - <<'PY'
import os, json, re, unicodedata
raw=os.environ.get("RAW_JSON","")
m=json.loads(raw)

def norm_title(s: str) -> str:
    s=unicodedata.normalize("NFKD", s or "").encode("ascii","ignore").decode()
    s=s.replace("&", "And")
    s=re.sub(r"[^A-Za-z0-9]+",".",s)
    s=re.sub(r"\.+",".",s).strip(".")
    return s

title=m.get("title") or ""
year=str(m.get("year") or "")
status=(m.get("status") or "").lower()
path=m.get("path") or ""
sid=str(m.get("id") or "")
seasons=m.get("seasons") or []
season_numbers=sorted([s.get("seasonNumber") for s in seasons if isinstance(s.get("seasonNumber"), int) and s.get("seasonNumber") > 0])
season_count=len(season_numbers)
base=norm_title(title)
base_with_year=f"{base}.{year}" if year else base

ended = status in ("ended","canceled","cancelled")
if ended:
    plan="INTEGRALE + SEASONS + EPISODES"
else:
    plan="SEASONS + EPISODES"

print(title)
print(year)
print(path)
print(status)
print(",".join(str(x) for x in season_numbers))
print(str(season_count))
print(plan)
print(base_with_year)
print(sid)
PY
}

scope_profile_json() {
  local series_raw="${1:-}" epfiles_json="${2:-}" scope_mode="${3:-all}" scope_value="${4:-}" extra_tag="${5:-}"
  local series_file epfiles_file

  series_file="$(mktemp /tmp/series_raw.XXXXXX.json)"
  epfiles_file="$(mktemp /tmp/epfiles_raw.XXXXXX.json)"

  printf '%s' "$series_raw" > "$series_file"
  printf '%s' "$epfiles_json" > "$epfiles_file"

  SCOPE_MODE="$scope_mode" SCOPE_VALUE="$scope_value" EXTRA_TAG="$extra_tag" DEFAULT_TEAM="$DEFAULT_TEAM" PREFERRED_LANG_MULTI="$PREFERRED_LANG_MULTI" python3 - "$series_file" "$epfiles_file" <<'PY'
import os, sys, json, re, unicodedata, collections

with open(sys.argv[1], "r", encoding="utf-8") as f:
    series = json.load(f)
with open(sys.argv[2], "r", encoding="utf-8") as f:
    epfiles = json.load(f)

scope_mode = os.environ.get("SCOPE_MODE", "all")
scope_value = os.environ.get("SCOPE_VALUE", "")
extra = os.environ.get("EXTRA_TAG", "")
default_team = os.environ.get("DEFAULT_TEAM", "NOTAG")
preferred_multi = os.environ.get("PREFERRED_LANG_MULTI", "MULTI")
BAD_GROUPS = {"new","unknown","scene","nogroup","group","release","proper","repack"}

def norm_title(s: str) -> str:
    s = unicodedata.normalize("NFKD", s or "").encode("ascii","ignore").decode()
    s = s.replace("&", "And")
    s = re.sub(r"[^A-Za-z0-9]+", ".", s)
    s = re.sub(r"\.+", ".", s).strip(".")
    return s

def split_langs(value: str):
    if not value:
        return set()
    parts = re.split(r"[/,;| ]+", value.strip().lower())
    out = set()
    for p in parts:
        p = p.strip()
        if not p:
            continue
        if p in ("fre","fra","fr","french"):
            out.add("french")
        elif p in ("eng","en","english"):
            out.add("english")
        elif p in ("jpn","jap","ja","jp","japanese"):
            out.add("japanese")
        else:
            out.add(p)
    return out

def clean_group(value: str) -> str:
    value = (value or "").strip()
    value = re.sub(r'[^A-Za-z0-9]+', '', value)
    return value

def normalize_audio_codec(mi):
    codec = (mi.get("audioCodec") or "").strip()
    profile = (mi.get("audioProfile") or "").strip().lower()
    additional = (mi.get("audioAdditionalFeatures") or "").strip().lower()
    title = (mi.get("audioTitle") or "").strip().lower()
    commercial = (mi.get("audioCommercial") or "").strip().lower()

    base = codec
    c = codec.lower()

    if c in ("eac3", "e-ac-3", "dd+"):
        base = "EAC3"
    elif c in ("ac3", "ac-3", "dd"):
        base = "AC3"
    elif c in ("truehd", "true-hd", "mlp fba"):
        base = "TrueHD"
    elif c == "dts":
        if "master" in profile or "ma" in profile or "ma" in commercial:
            base = "DTS-HD.MA"
        elif "hra" in profile:
            base = "DTS-HD.HRA"
        else:
            base = "DTS"
    elif c in ("dtshd", "dts-hd"):
        if "master" in profile or "ma" in profile or "ma" in commercial:
            base = "DTS-HD.MA"
        elif "hra" in profile:
            base = "DTS-HD.HRA"
        else:
            base = "DTS-HD"
    elif c == "aac":
        base = "AAC"
    elif c == "flac":
        base = "FLAC"
    elif c == "pcm":
        base = "PCM"

    if "atmos" in additional or "atmos" in title or "atmos" in commercial:
        base = f"{base}.Atmos"

    return base

def normalize_channels(mi):
    channels = str(mi.get("audioChannels") or "")
    if channels == "8":
        return "7.1"
    if channels == "6":
        return "5.1"
    if channels == "2":
        return "2.0"
    if channels == "1":
        return "1.0"
    return channels

def normalize_vcodec(mi):
    video_codec = (mi.get("videoCodec") or "").lower()
    if video_codec in ("x264","h264","avc"):
        return "H264"
    if video_codec in ("x265","h265","hevc"):
        return "x265"
    if video_codec:
        return (mi.get("videoCodec") or "").upper()
    return "H264"

def detect_hdr(mi):
    bits = []
    values = [
        mi.get("videoDynamicRangeType") or "",
        mi.get("videoDynamicRange") or "",
        mi.get("hdrFormat") or "",
        mi.get("hdrFormatString") or "",
        mi.get("videoHdrFormat") or "",
        mi.get("videoHdrFormatString") or "",
    ]
    joined = " | ".join([str(v) for v in values if v]).upper()
    if "DOLBY VISION" in joined or re.search(r"DV", joined):
        bits.append("DV")
    if "HDR10+" in joined:
        bits.append("HDR10PLUS")
    elif "HDR10" in joined:
        bits.append("HDR10")
    elif re.search(r"HDR", joined):
        bits.append("HDR")
    elif "HLG" in joined:
        bits.append("HLG")
    return bits

def detect_source(epf):
    q = (epf.get("quality") or {}).get("quality") or {}
    source = (q.get("source") or "").lower()
    path = (epf.get("path") or "")
    rel = (epf.get("relativePath") or "")
    joined = (path + " " + rel).lower()

    if "remux" in joined:
        return "Remux"

    source_map = {
        "bluray":"BluRay",
        "webdl":"WEB-DL",
        "webrip":"WEBRip",
        "web":"WEB",
        "dvd":"DVDRip",
        "hdtv":"HDTV",
        "television":"HDTV",
        "tv":"HDTV",
        "uhdbluray":"UHD.BluRay"
    }
    if source in source_map:
        return source_map[source]

    if "web-dl" in joined or "webdl" in joined:
        return "WEB-DL"
    if "webrip" in joined:
        return "WEBRip"
    if "bluray" in joined or "blu-ray" in joined or "bdrip" in joined:
        return "BluRay"
    if "hdtv" in joined:
        return "HDTV"
    if "dvdrip" in joined or "dvd" in joined:
        return "DVDRip"
    return "WEB"

def normalize_resolution(epf):
    q = (epf.get("quality") or {}).get("quality") or {}
    resolution = q.get("resolution")
    if resolution:
        return f"{resolution}p"
    mi = epf.get("mediaInfo") or {}
    for key in ("height", "videoHeight"):
        val = mi.get(key)
        if val:
            try:
                return f"{int(val)}p"
            except Exception:
                pass
    return ""

def normalize_group(epf):
    group = clean_group(epf.get("releaseGroup") or "")
    if group.lower() in BAD_GROUPS:
        return ""
    return group

def lang_tag(audio_langs, sub_langs):
    if "french" in audio_langs and "english" in audio_langs:
        return preferred_multi
    if "french" in audio_langs and len(audio_langs) == 1:
        return "FRENCH"
    if "english" in audio_langs and "french" in sub_langs:
        return "VOSTFR"
    if "english" in audio_langs and len(audio_langs) == 1:
        return "ENGLISH"
    if "japanese" in audio_langs and "french" in audio_langs:
        return preferred_multi
    if "japanese" in audio_langs and "french" in sub_langs:
        return "VOSTFR"
    if "japanese" in audio_langs and len(audio_langs) == 1:
        return "JAPANESE"
    return preferred_multi if len(audio_langs) > 1 else "UNKNOWN"

def path_eq(a, b):
    def norm(p):
        p = (p or "").strip().replace("\\","/")
        p = re.sub(r"/+","/",p)
        return p.rstrip("/")
    return norm(a) == norm(b)

selected = []
if scope_mode == "all":
    selected = list(epfiles)
elif scope_mode == "season":
    try:
        wanted = int(scope_value)
    except Exception:
        wanted = -1
    selected = [e for e in epfiles if int(e.get("seasonNumber") or -1) == wanted]
elif scope_mode == "path":
    selected = [e for e in epfiles if path_eq(e.get("path"), scope_value)]
else:
    selected = list(epfiles)

if not selected:
    print(json.dumps({}))
    raise SystemExit(0)

title = norm_title(series.get("title") or "")
year = str(series.get("year") or "")

audio_union = set()
sub_union = set()
source_counts = collections.Counter()
res_counts = collections.Counter()
audio_counts = collections.Counter()
vcodec_counts = collections.Counter()
group_counts = collections.Counter()
lang_counts = collections.Counter()
hdr_counts = collections.Counter()

for e in selected:
    mi = e.get("mediaInfo") or {}
    source = detect_source(e)
    res = normalize_resolution(e)
    audio = normalize_audio_codec(mi)
    channels = normalize_channels(mi)
    vcodec = normalize_vcodec(mi)
    hdr = ".".join(detect_hdr(mi))
    group = normalize_group(e)

    audio_langs = split_langs(mi.get("audioLanguages") or "")
    sub_langs = split_langs(mi.get("subtitles") or "")

    audio_union |= audio_langs
    sub_union |= sub_langs

    if source:
        source_counts[source] += 1
    if res:
        res_counts[res] += 1
    if audio:
        audio_counts[(audio, channels)] += 1
    if vcodec:
        vcodec_counts[vcodec] += 1
    if hdr:
        hdr_counts[hdr] += 1
    if group:
        group_counts[group] += 1

    lang_counts[lang_tag(audio_langs, sub_langs)] += 1

def pick(counter, default=""):
    if not counter:
        return default
    return counter.most_common(1)[0][0]

source = pick(source_counts, "WEB")
res = pick(res_counts, "")
audio_tuple = pick(audio_counts, ("", ""))
audio_codec, channels = audio_tuple if isinstance(audio_tuple, tuple) else (audio_tuple, "")
vcodec = pick(vcodec_counts, "H264")
hdr = pick(hdr_counts, "")
release_group = pick(group_counts, "")
lang = pick(lang_counts, lang_tag(audio_union, sub_union))
if not release_group:
    release_group = default_team

parts = [title]
if year:
    parts.append(year)
if extra:
    parts.append(extra)
parts.append(lang)
if res:
    parts.append(res)
if source:
    parts.append(source)
if hdr:
    parts.extend(hdr.split("."))
if audio_codec:
    parts.append(audio_codec)
if channels:
    parts.append(channels)
if vcodec:
    parts.append(vcodec)

name = ".".join([p for p in parts if p])
name = re.sub(r"\.+", ".", name).strip(".")

representative = sorted(
    selected,
    key=lambda x: (x.get("seasonNumber") or 0, x.get("episodeNumber") or 0, x.get("path") or "")
)[0]

out = {
    "release_base": name,
    "release_group": release_group,
    "display_title": series.get("title") or "",
    "display_year": year,
    "display_path": representative.get("path") or "",
    "display_source": source,
    "display_res": res,
    "display_audio": f"{audio_codec}.{channels}" if audio_codec and channels else (audio_codec or channels),
    "display_video": vcodec,
    "display_langs": ",".join(sorted(audio_union)) if audio_union else "",
    "display_subs": ",".join(sorted(sub_union)) if sub_union else "",
    "display_lang_tag": lang,
    "media_target": representative.get("path") or "",
    "episode_count": len(selected),
}
print(json.dumps(out))
PY
  local rc=$?
  rm -f "$series_file" "$epfiles_file"
  return $rc
}


profile_json_to_preview() {
  local profile_json="${1:-}" extra_tag="${2:-}"

  jq -r --arg extra "$extra_tag" '
    def release_base_from_parts:
      [
        .title_slug,
        .display_year,
        (if $extra != "" then $extra else empty end),
        .display_lang_tag,
        .display_res,
        .display_source
      ]
      + (.hdr_bits // [])
      + [
        .audio_codec,
        .channels,
        .vcodec
      ]
      | map(select(. != null and . != ""))
      | join(".");

    if has("release_base") then
      .release_base,
      (.release_group // ""),
      (.display_title // ""),
      (.display_year // ""),
      (.display_path // ""),
      (.display_source // ""),
      (.display_res // ""),
      (.display_audio // ""),
      (.display_video // ""),
      (.display_langs // ""),
      (.display_subs // ""),
      (.display_lang_tag // ""),
      (.media_target // ""),
      ((.episode_count // 0) | tostring)
    else
      release_base_from_parts,
      (.release_group // ""),
      (.display_title // ""),
      (.display_year // ""),
      (.display_path // ""),
      (.display_source // ""),
      (.display_res // ""),
      (.display_audio // ""),
      (.display_video // ""),
      (.display_langs // ""),
      (.display_subs // ""),
      (.display_lang_tag // ""),
      (.media_target // ""),
      ((.episode_count // 0) | tostring)
    end
  ' <<<"$profile_json"
}

build_series_scope_cache() {
  return 1
}

cleanup_series_scope_cache() {
  local cache_dir="${1:-}"
  [[ -n "$cache_dir" && -d "$cache_dir" ]] || return 0
  rm -rf "$cache_dir"
}

series_scope_profile_from_cache() {
  return 1
}

series_episode_paths_for_season_from_cache() {
  local cache_dir="${1:-}" season_num="${2:-}"
  [[ -n "$cache_dir" && -n "$season_num" ]] || return 1
  return 1
}

season_dir_candidates() {
  local series_dir="${1:-}" season_num="${2:-0}"
  printf '%s\n' \
    "$series_dir/Season $season_num" \
    "$series_dir/Season $(printf '%02d' "$season_num")" \
    "$series_dir/Saison $season_num" \
    "$series_dir/Saison $(printf '%02d' "$season_num")" \
    "$series_dir/S$(printf '%02d' "$season_num")"
}

find_existing_season_dir() {
  local series_dir="${1:-}" season_num="${2:-0}" d
  while IFS= read -r d; do
    [[ -d "$d" ]] && { echo "$d"; return 0; }
  done < <(season_dir_candidates "$series_dir" "$season_num")
  return 1
}

season_tag_from_num() {
  local season_num="${1:-0}"
  printf 'S%02d\n' "$season_num"
}

episode_tag_from_path() {
  local name="${1##*/}"
  if [[ "$name" =~ ([Ss][0-9]{2}[Ee][0-9]{2}) ]]; then
    printf '%s
' "${BASH_REMATCH[1]^^}"
  fi
}


create_series_scope_release() {
  local series_raw="${1:-}" epfiles_json="${2:-}" scope_mode="${3:-all}" scope_value="${4:-}" scope_path="${5:-}" out_dir="${6:-}" extra_tag="${7:-}" cache_dir="${8:-}"
  [[ -n "$series_raw" && -n "$epfiles_json" && -n "$scope_mode" && -n "$scope_path" && -n "$out_dir" ]] || return 1

  local profile_json=""
  if [[ -n "${cache_dir:-}" && -d "${cache_dir:-}" ]] && declare -F series_scope_profile_from_cache >/dev/null 2>&1; then
    profile_json="$(series_scope_profile_from_cache "$cache_dir" "$scope_mode" "$scope_value" || true)"
  fi
  if [[ -z "${profile_json:-}" || "$profile_json" == "{}" ]]; then
    profile_json="$(scope_profile_json "$series_raw" "$epfiles_json" "$scope_mode" "$scope_value" "$extra_tag")"
  fi
  [[ -n "${profile_json:-}" && "$profile_json" != "{}" ]] || return 1

  mapfile -t preview < <(profile_json_to_preview "$profile_json" "$extra_tag")
  local release_base="${preview[0]}"
  local release_group="${preview[1]}"
  local display_title="${preview[2]}"
  local display_year="${preview[3]}"
  local display_path="${preview[4]}"
  local display_source="${preview[5]}"
  local display_res="${preview[6]}"
  local display_audio="${preview[7]}"
  local display_video="${preview[8]}"
  local display_langs="${preview[9]}"
  local display_subs="${preview[10]}"
  local display_lang_tag="${preview[11]}"
  local media_target="${preview[12]}"
  local episode_count="${preview[13]}"

  local release_name="${release_base}-${release_group}"
  local out_torrent="$out_dir/${release_name}.torrent"
  local out_nfo="$out_dir/${release_name}.nfo"

  echo >&2
  echo "Title        : $display_title"
  echo "Year         : $display_year"
  echo "Path         : $display_path"
  echo "Scope files  : $episode_count"
  echo "Source       : $display_source"
  echo "Resolution   : $display_res"
  echo "Audio        : $display_audio"
  echo "Video        : $display_video"
  echo "Languages    : $display_langs"
  echo "Subtitles    : $display_subs"
  echo "Lang tag     : $display_lang_tag"
  echo "Preview      : $release_name"
  echo "Output dir   : $out_dir"
  echo >&2

  prepare_output_slot "$out_torrent"
  case $? in
    10) return 0 ;;
    0) ;;
    *) return 1 ;;
  esac

  local payload_dir piece payload_root source_nfo direct_hash="0"
  local -a payload_files=()

  if [[ -f "$scope_path" ]]; then
    [[ -n "$media_target" ]] || media_target="$scope_path"
    payload_files=("$scope_path")
    payload_root="$(dirname "$scope_path")"
  else
    [[ -n "$media_target" ]] || media_target="$(pick_main_video "$scope_path")"
    [[ -n "${media_target:-}" ]] || { echo "No video file found in: $scope_path"; return 1; }
    mapfile -t payload_files < <(collect_video_files "$scope_path")
    [[ "${#payload_files[@]}" -gt 0 ]] || { echo "No video files found in: $scope_path"; return 1; }
    payload_root="$scope_path"
  fi

  source_nfo="$payload_root/${release_name}.nfo"

  status "NFO"
  write_nfo "$media_target" "$out_nfo"
  cp -f "$out_nfo" "$source_nfo"
  fix_output_permissions "$out_nfo" "$source_nfo"
  fix_output_permissions "$payload_root" "$out_dir"

  if declare -F should_use_direct_series_hash >/dev/null 2>&1 && should_use_direct_series_hash "$scope_path" "$payload_root"; then
    payload_dir="$payload_root"
    direct_hash="1"
  else
    payload_dir="$(prepare_release_payload "$payload_root" "$(basename "$payload_root")" "$source_nfo" "${payload_files[@]}" "$source_nfo")" || return 1
  fi

  piece="$(choose_piece_size "$payload_dir")"

  status "TORRENT"
  if ! build_torrent "$payload_dir" "$out_torrent" "$piece" "$release_name"; then
    [[ "$direct_hash" != "1" ]] && cleanup_payload_dir "$payload_dir"
    return 1
  fi

  [[ "$direct_hash" != "1" ]] && cleanup_payload_dir "$payload_dir"
  fix_output_permissions "$out_torrent" "$out_nfo"

  echo >&2
  echo "Done:"
  echo " - $out_torrent"
  echo " - $out_nfo"
  print_recheck_hint "$payload_dir" "$payload_root"
}

show_series_plan() {
  local series_dir="${1:-}" root="${2:-}" api_url="${3:-}" api_key="${4:-}"
  local raw
  raw="$(find_sonarr_series_by_path_or_name "$series_dir" "$api_url" "$api_key" || true)"
  [[ -n "${raw:-}" ]] || { echo "No Sonarr match found: $series_dir"; return 0; }

  mapfile -t plan < <(series_plan_from_json "$raw")
  local display_title="${plan[0]}"
  local display_year="${plan[1]}"
  local display_path="${plan[2]}"
  local display_status="${plan[3]}"
  local display_seasons="${plan[4]}"
  local display_season_count="${plan[5]}"
  local display_plan="${plan[6]}"
  local display_base="${plan[7]}"

  echo >&2
  echo "Title        : $display_title"
  echo "Year         : $display_year"
  echo "Path         : $display_path"
  echo "Status       : $display_status"
  echo "Seasons      : $display_seasons"
  echo "Season count : $display_season_count"
  echo "Plan         : $display_plan"
  echo >&2
  echo "Preview examples:"
  if [[ "$display_status" == "ended" || "$display_status" == "canceled" || "$display_status" == "cancelled" ]]; then
    echo " - INTEGRALE: ${display_base}.INTEGRALE"
  fi
  echo " - SEASON   : ${display_base}.S01"
  echo " - EPISODE  : ${display_base}.S01E01"
}

format_season_token() {
  local n="${1:-0}"
  printf 'S%02d' "$n"
}

format_seasons_display() {
  local csv="${1:-}"
  local out="" token
  IFS=',' read -r -a arr <<< "$csv"
  for token in "${arr[@]}"; do
    [[ -z "${token:-}" ]] && continue
    [[ -n "$out" ]] && out+=", "
    out+="$(format_season_token "$token")"
  done
  echo "$out"
}

pack_tag_from_seasons_csv() {
  local csv="${1:-}"
  local first="" last="" token
  IFS=',' read -r -a arr <<< "$csv"
  for token in "${arr[@]}"; do
    [[ -z "${token:-}" ]] && continue
    token="$((10#$token))"
    [[ -z "$first" ]] && first="$token"
    last="$token"
  done

  if [[ -z "$first" ]]; then
    echo "INTEGRALE"
  elif [[ "$first" == "$last" ]]; then
    format_season_token "$first"
    echo >&2
  else
    printf 'S%02dS%02d\n' "$first" "$last"
  fi
}

prompt_select_seasons_csv() {
  local available_csv="${1:-}"
  local display choice token cleaned="" available_wrap

  display="$(format_seasons_display "$available_csv")"
  echo "Dispo: $display" >&2
  read -r -p "Choix saisons [all]: " choice

  if [[ -z "${choice:-}" || "${choice,,}" == "all" ]]; then
    echo "$available_csv"
    return 0
  fi

  available_wrap=",$available_csv,"
  IFS=',' read -r -a wanted_arr <<< "$choice"

  for token in "${wanted_arr[@]}"; do
    token="${token// /}"
    token="${token#S}"
    token="${token#s}"
    [[ -z "$token" ]] && continue
    [[ "$token" =~ ^[0-9]+$ ]] || continue
    token="$((10#$token))"

    if [[ "$available_wrap" == *",$token,"* ]]; then
      if [[ ",$cleaned," != *",$token,"* ]]; then
        if [[ -n "$cleaned" ]]; then
          cleaned="$cleaned,$token"
        else
          cleaned="$token"
        fi
      fi
    fi
  done

  [[ -n "$cleaned" ]] || return 1
  echo "$cleaned"
}

prompt_select_episode_paths() {
  local season_dir="${1:-}"
  local -a eps=()
  local i ep_path ep_tag choice idx cleaned=()

  mapfile -t eps < <(find "$season_dir" -maxdepth 1 -type f \(     -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.m2ts" -o     -iname "*.avi" -o -iname "*.ts" -o -iname "*.mov" -o -iname "*.wmv"   \) | sort)

  [[ "${#eps[@]}" -gt 0 ]] || return 0

  echo >&2
  echo "Episodes in $(basename "$season_dir"):" >&2
  for ((i=0; i<${#eps[@]}; i++)); do
    ep_path="${eps[$i]}"
    ep_tag="$(episode_tag_from_path "$ep_path")"
    printf >&2 ' %2d) %s\n' "$((i+1))" "${ep_tag:-$(basename "$ep_path")}"
  done

  read -r -p "Episodes to process [all/skip or comma list]: " choice

  if [[ -z "${choice:-}" || "${choice,,}" == "all" ]]; then
    printf '%s\n' "${eps[@]}"
    return 0
  fi

  if [[ "${choice,,}" == "skip" ]]; then
    return 0
  fi

  IFS=',' read -r -a wanted_idx <<< "$choice"
  for idx in "${wanted_idx[@]}"; do
    idx="${idx// /}"
    [[ "$idx" =~ ^[0-9]+$ ]] || continue
    idx="$((10#$idx))"
    if (( idx >= 1 && idx <= ${#eps[@]} )); then
      ep_path="${eps[$((idx-1))]}"
      local seen=0 existing
      for existing in "${cleaned[@]}"; do
        [[ "$existing" == "$ep_path" ]] && seen=1 && break
      done
      (( seen == 0 )) && cleaned+=("$ep_path")
    fi
  done

  printf '%s\n' "${cleaned[@]}"
}


create_series_release_set() {
  local series_dir="${1:-}" root="${2:-}" api_url="${3:-}" api_key="${4:-}"
  [[ -n "$series_dir" && -n "$api_url" && -n "$api_key" ]] || return 1

  local series_raw
  series_raw="$(find_sonarr_series_by_path_or_name "$series_dir" "$api_url" "$api_key" || true)"
  [[ -n "${series_raw:-}" ]] || { echo "No Sonarr match found: $series_dir"; return 0; }

  mapfile -t plan < <(series_plan_from_json "$series_raw")
  local display_title="${plan[0]}"
  local display_year="${plan[1]}"
  local display_status="${plan[3]}"
  local display_seasons="${plan[4]}"
  local display_season_count="${plan[5]}"
  local display_plan="${plan[6]}"
  local series_id="${plan[8]}"

  echo >&2
  echo "Title        : $display_title"
  echo "Year         : $display_year"
  echo "Status       : $display_status"
  echo "Seasons      : $display_seasons"
  echo "Season count : $display_season_count"
  echo "Plan         : $display_plan"
  echo >&2

  local epfiles_json
  epfiles_json="$(sonarr_episode_files_for_series "$series_id" "$api_url" "$api_key" || true)"
  [[ -n "${epfiles_json:-}" ]] || { echo "No Sonarr episode files found."; return 1; }

  local cache_dir=""
  cache_dir="$(build_series_scope_cache "$series_raw" "$epfiles_json" 2>/dev/null || true)"
  trap 'cleanup_series_scope_cache "$cache_dir"' RETURN

  local rel_base out_series_dir
  rel_base="$(safe_relpath "$series_dir" "$MEDIA_ROOT")"
  out_series_dir="$OUTPUT_ROOT/$rel_base"

  local ended='0'
  [[ "$display_status" == 'ended' || "$display_status" == 'canceled' || "$display_status" == 'cancelled' ]] && ended='1'

  local pack_tag='INTEGRALE'
  if [[ "$ended" != '1' && "$display_season_count" -gt 1 ]]; then
    pack_tag="$(pack_tag_from_seasons_csv "$display_seasons")"
  fi

  local do_pack='0'
  local do_seasons='0'
  local do_all_episodes='0'
  local do_selected_episodes='0'
  local selected_seasons_csv="$display_seasons"
  local -a selected_episode_paths=()

  echo 'Choose generation mode:'
  if [[ "$ended" == '1' || "$display_season_count" -gt 1 ]]; then
    echo " 1) ${pack_tag}"
    echo ' 2) Select Seasons'
    echo " 3) ${pack_tag} + SEASONS"
    echo ' 4) All Episodes'
    echo ' 5) Select Episodes'
    echo " 6) ${pack_tag} + SEASONS + ALL EPISODES"
    echo ' 0) Cancel'
  else
    echo 'Only first season available for this ongoing series.'
    echo ' 4) All Episodes'
    echo ' 5) Select Episodes'
    echo ' 0) Cancel'
  fi

  local mode
  read -r -p 'Select: ' mode

  case "$mode" in
    1)
      [[ "$ended" == '1' || "$display_season_count" -gt 1 ]] || { echo 'Invalid'; return 1; }
      do_pack='1'
      ;;
    2)
      [[ "$ended" == '1' || "$display_season_count" -gt 1 ]] || { echo 'Invalid'; return 1; }
      selected_seasons_csv="$(prompt_select_seasons_csv "$display_seasons")" || { echo 'No valid seasons selected.'; return 1; }
      do_seasons='1'
      ;;
    3)
      [[ "$ended" == '1' || "$display_season_count" -gt 1 ]] || { echo 'Invalid'; return 1; }
      selected_seasons_csv="$(prompt_select_seasons_csv "$display_seasons")" || { echo 'No valid seasons selected.'; return 1; }
      do_pack='1'
      do_seasons='1'
      ;;
    4)
      do_all_episodes='1'
      ;;
    5)
      selected_seasons_csv="$(prompt_select_seasons_csv "$display_seasons")" || { echo 'No valid seasons selected.'; return 1; }
      local season_num season_dir
      IFS=',' read -r -a season_arr <<< "$selected_seasons_csv"
      for season_num in "${season_arr[@]}"; do
        [[ -z "${season_num:-}" ]] && continue
        season_dir="$(find_existing_season_dir "$series_dir" "$season_num" || true)"
        [[ -d "${season_dir:-}" ]] || continue
        while IFS= read -r ep_path; do
          [[ -n "${ep_path:-}" ]] || continue
          selected_episode_paths+=("$ep_path")
        done < <(prompt_select_episode_paths "$season_dir")
      done
      [[ "${#selected_episode_paths[@]}" -gt 0 ]] || { echo 'No episodes selected.'; return 1; }
      do_selected_episodes='1'
      ;;
    6)
      [[ "$ended" == '1' || "$display_season_count" -gt 1 ]] || { echo 'Invalid'; return 1; }
      echo >&2
      echo 'WARNING:'
      echo 'This will generate the complete pack, all season packs, and all episode torrents.'
      echo 'This can take a long time on large series.'
      read -r -p 'Continue? [y/N]: ' confirm
      [[ "${confirm,,}" == 'y' ]] || return 0
      do_pack='1'
      do_seasons='1'
      do_all_episodes='1'
      ;;
    0)
      return 0
      ;;
    *)
      echo 'Invalid'
      return 1
      ;;
  esac

  if [[ "$do_pack" == '1' ]]; then
    local pack_out_dir="$out_series_dir/$pack_tag"
    create_series_scope_release "$series_raw" "$epfiles_json" 'all' '' "$series_dir" "$pack_out_dir" "$pack_tag" "$cache_dir"
  fi

  local season_num season_dir season_tag
  IFS=',' read -r -a season_arr <<< "$selected_seasons_csv"

  if [[ "$do_seasons" == '1' ]]; then
    for season_num in "${season_arr[@]}"; do
      [[ -z "${season_num:-}" ]] && continue
      season_dir="$(find_existing_season_dir "$series_dir" "$season_num" || true)"
      [[ -d "${season_dir:-}" ]] || continue
      season_tag="$(season_tag_from_num "$season_num")"
      create_series_scope_release "$series_raw" "$epfiles_json" 'season' "$season_num" "$season_dir" "$out_series_dir/$season_tag" "$season_tag" "$cache_dir"
    done
  fi

  if [[ "$do_all_episodes" == '1' ]]; then
    local ep_path ep_tag out_ep_dir
    for season_num in "${season_arr[@]}"; do
      [[ -z "${season_num:-}" ]] && continue
      while IFS= read -r ep_path; do
        [[ -n "${ep_path:-}" ]] || continue
        ep_tag="$(episode_tag_from_path "$ep_path")"
        [[ -n "${ep_tag:-}" ]] || continue
        out_ep_dir="$out_series_dir/$(season_tag_from_num "$season_num")/EPISODES"
        create_series_scope_release "$series_raw" "$epfiles_json" 'path' "$ep_path" "$ep_path" "$out_ep_dir" "$ep_tag" "$cache_dir"
      done < <(
        if [[ -n "${cache_dir:-}" ]] && declare -F series_episode_paths_for_season_from_cache >/dev/null 2>&1; then
          series_episode_paths_for_season_from_cache "$cache_dir" "$season_num" 2>/dev/null || true
        fi
      )
    done
  fi

  if [[ "$do_selected_episodes" == '1' ]]; then
    local ep_path ep_tag ep_season out_ep_dir
    for ep_path in "${selected_episode_paths[@]}"; do
      [[ -n "${ep_path:-}" ]] || continue
      ep_tag="$(episode_tag_from_path "$ep_path")"
      [[ -n "${ep_tag:-}" ]] || continue
      ep_season="${ep_tag#S}"
      ep_season="${ep_season%%E*}"
      ep_season="$((10#$ep_season))"
      out_ep_dir="$out_series_dir/$(season_tag_from_num "$ep_season")/EPISODES"
      create_series_scope_release "$series_raw" "$epfiles_json" 'path' "$ep_path" "$ep_path" "$out_ep_dir" "$ep_tag" "$cache_dir"
    done
  fi

  trap - RETURN
  cleanup_series_scope_cache "$cache_dir"
}

batch_series_root() {
  local root="${1:-}" api_url="${2:-}" api_key="${3:-}"
  mapfile -t items < <(find "$root" -mindepth 1 -maxdepth 1 -type d | sort)
  local total="${#items[@]}" i=0 d
  for d in "${items[@]}"; do
    i=$((i + 1))
    echo >&2
    echo "============================================================"
    echo "[$i/$total] $(basename "$d")"
    echo "============================================================"
    create_series_release_set "$d" "$root" "$api_url" "$api_key" || true
  done
}

series_menu() {
  local root
  root="$(select_series_root)" || return 0
  [[ -n "${root:-}" ]] || return 0

  echo >&2
  echo "Series actions"
  echo " 1) One series (show plan only)"
  echo " 2) One series (create real files)"
  echo " 3) Batch root (create real files)"
  echo " 0) Back"
  local c
  read -r -p "Select: " c

  case "$c" in
    1)
      mapfile -t items < <(find "$root" -mindepth 1 -maxdepth 1 -type d | sort)
      local picked
      picked="$(pick_from_list_paged "Select a series folder:" "${items[@]}")" || return 0
      if [[ "$root" == *"SERIES_4K" ]]; then
        show_series_plan "$picked" "$root" "$SONARR_4K_URL" "$SONARR_4K_API_KEY"
      else
        show_series_plan "$picked" "$root" "$SONARR_URL" "$SONARR_API_KEY"
      fi
      press_enter
      ;;
    2)
      mapfile -t items < <(find "$root" -mindepth 1 -maxdepth 1 -type d | sort)
      local picked
      picked="$(pick_from_list_paged "Select a series folder:" "${items[@]}")" || return 0
      if [[ "$root" == *"SERIES_4K" ]]; then
        create_series_release_set "$picked" "$root" "$SONARR_4K_URL" "$SONARR_4K_API_KEY"
      else
        create_series_release_set "$picked" "$root" "$SONARR_URL" "$SONARR_API_KEY"
      fi
      press_enter
      ;;
    3)
      if [[ "$root" == *"SERIES_4K" ]]; then
        batch_series_root "$root" "$SONARR_4K_URL" "$SONARR_4K_API_KEY"
      else
        batch_series_root "$root" "$SONARR_URL" "$SONARR_API_KEY"
      fi
      press_enter
      ;;
    0) return 0 ;;
    *) echo "Invalid" ;;
  esac
}
