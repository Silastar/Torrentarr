#!/usr/bin/env bash

find_radarr_movie_by_path_or_name() {
  local folder_path="${1:-}" api_url="${2:-}" api_key="${3:-}"
  [[ -n "$folder_path" && -n "$api_url" && -n "$api_key" ]] || return 1

  local tmp_json title year
  tmp_json="$(mktemp /tmp/radarr_movies.XXXXXX.json)"
  mapfile -t ty < <(extract_title_year_from_folder "$folder_path")
  title="${ty[0]:-}"
  year="${ty[1]:-}"

  if ! api_get "${api_url%/}/api/v3/movie" "$api_key" > "$tmp_json"; then
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
    mpath=item.get("path") or ""
    if norm_path(mpath) in want_paths:
        print(json.dumps(item))
        raise SystemExit(0)

candidates=[]
for m in data:
    titles=[m.get("title",""), m.get("originalTitle",""), m.get("sortTitle","")]
    movie_year=str(m.get("year") or "")
    score=0
    for t in titles:
        nt=norm_text(t)
        if nt == want_title:
            score=max(score, 100)
        elif want_title and nt.startswith(want_title):
            score=max(score, 90)
        elif want_title and want_title in nt:
            score=max(score, 80)
    if year and movie_year == year:
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

movie_profile_json() {
  local movie_raw="${1:-}" main_video="${2:-}"
  MOVIE_RAW="$movie_raw" MAIN_VIDEO="$main_video" DEFAULT_TEAM="$DEFAULT_TEAM" PREFERRED_LANG_MULTI="$PREFERRED_LANG_MULTI" python3 - <<'PY'
import os, json, re, unicodedata, subprocess

movie=json.loads(os.environ.get("MOVIE_RAW","{}"))
main_video=os.environ.get("MAIN_VIDEO","")
default_team=os.environ.get("DEFAULT_TEAM","NOTAG")
preferred_multi=os.environ.get("PREFERRED_LANG_MULTI","MULTI")
BAD_GROUPS={"new","unknown","scene","nogroup","group","release","proper","repack"}

mf=movie.get("movieFile") or {}
q=(mf.get("quality") or {}).get("quality") or {}

def norm_title(s: str) -> str:
    s=unicodedata.normalize("NFKD", s or "").encode("ascii","ignore").decode()
    s=s.replace("&", "And")
    s=re.sub(r"[^A-Za-z0-9]+",".",s)
    s=re.sub(r"\.+",".",s).strip(".")
    return s

def split_langs(value: str):
    if not value:
        return set()
    parts=re.split(r"[/,;| ]+", str(value).strip().lower())
    out=set()
    for p in parts:
        p=p.strip()
        if not p:
            continue
        if p in ("fre","fra","fr","french"):
            out.add("french")
        elif p in ("eng","en","english"):
            out.add("english")
        elif p in ("jpn","jap","ja","jp","japanese"):
            out.add("japanese")
        elif p in ("ger","deu","de","german"):
            out.add("german")
        elif p in ("ita","it","italian"):
            out.add("italian")
        elif p in ("spa","es","spanish"):
            out.add("spanish")
        elif p in ("tha","th","thai"):
            out.add("thai")
        elif p in ("por","pt","portuguese"):
            out.add("portuguese")
        elif p in ("dut","nld","nl","dutch"):
            out.add("dut")
        elif p in ("dan","da","danish"):
            out.add("dan")
        elif p in ("fin","fi","finnish"):
            out.add("fin")
        elif p in ("nor","nob","nb","no","norwegian"):
            out.add("nor")
        elif p in ("swe","sv","swedish"):
            out.add("swe")
        elif p in ("chi","zho","zh","chinese"):
            out.add("chi")
        elif p in ("cze","ces","cs","czech"):
            out.add("cze")
        elif p in ("kor","ko","korean"):
            out.add("kor")
        elif p in ("pol","pl","polish"):
            out.add("pol")
        elif p in ("ara","ar","arabic"):
            out.add("ara")
        elif p in ("ben","bn","bengali"):
            out.add("ben")
        elif p in ("per","fas","fa","persian"):
            out.add("per")
        elif p in ("gre","ell","el","greek"):
            out.add("gre")
        elif p in ("hun","hu","hungarian"):
            out.add("hun")
        elif p in ("ind","id","indonesian"):
            out.add("ind")
        elif p in ("rum","ron","ro","romanian"):
            out.add("rum")
        elif p in ("slo","slk","sk","slovak"):
            out.add("slo")
        elif p in ("tur","tr","turkish"):
            out.add("tur")
        else:
            out.add(p)
    return out

def clean_group(value: str) -> str:
    value=(value or "").strip()
    value=re.sub(r'[^A-Za-z0-9]+', '', value)
    return value

def normalize_audio_codec_from_name(codec, profile="", additional="", title="", commercial=""):
    codec=(codec or "").strip()
    profile=(profile or "").strip().lower()
    additional=(additional or "").strip().lower()
    title=(title or "").strip().lower()
    commercial=(commercial or "").strip().lower()

    base=codec
    c=codec.lower()

    if c in ("e-ac-3", "eac3", "dd+", "dolby digital plus"):
        base="EAC3"
    elif c in ("ac-3", "ac3", "dd", "dolby digital"):
        base="AC3"
    elif c in ("truehd", "true-hd", "mlp fba", "dolby truehd"):
        base="TrueHD"
    elif c in ("aac", "aac lc", "he-aac"):
        base="AAC"
    elif c in ("flac",):
        base="FLAC"
    elif c in ("pcm",):
        base="PCM"
    elif c in ("dts",):
        if "master" in profile or "ma" in profile or "ma" in commercial:
            base="DTS-HD.MA"
        elif "hra" in profile:
            base="DTS-HD.HRA"
        else:
            base="DTS"
    elif c in ("dts-hd", "dtshd"):
        if "master" in profile or "ma" in profile or "ma" in commercial:
            base="DTS-HD.MA"
        elif "hra" in profile:
            base="DTS-HD.HRA"
        else:
            base="DTS-HD"

    if "atmos" in additional or "atmos" in title or "atmos" in commercial:
        base=f"{base}.Atmos"

    return base

def parse_channel_count(value):
    if value is None:
        return 0.0
    s=str(value).strip().replace(",", ".")
    m=re.search(r'(\d+(?:\.\d+)?)', s)
    if m:
        try:
            return float(m.group(1))
        except Exception:
            return 0.0
    return 0.0

def format_channels(ch):
    if ch >= 7.5:
        return "7.1"
    if ch >= 5.5:
        return "5.1"
    if ch >= 2.0:
        return "2.0"
    if ch >= 1.0:
        return "1.0"
    return ""

def is_commentary_track(title):
    blob=(title or "").lower()
    return any(x in blob for x in (
        "commentary", "commentaire", "descriptive", "description audio",
        "director", "réalisateur", "narration"
    ))

def mediainfo_json(path):
    if not path or not os.path.isfile(path):
        return {}
    try:
        out=subprocess.check_output(["mediainfo", "--Output=JSON", path], text=True)
        return json.loads(out)
    except Exception:
        return {}

def detect_source(movie, mf):
    q=(mf.get("quality") or {}).get("quality") or {}
    source=(q.get("source") or "").lower()
    path=(mf.get("path") or "")
    rel=(mf.get("relativePath") or "")
    joined=(path + " " + rel + " " + (movie.get("path") or "")).lower()

    if "remux" in joined:
        return "Remux"

    source_map={
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
    if "remux" in joined:
        return "Remux"
    if "dvdrip" in joined or "dvd" in joined:
        return "DVDRip"
    return "WEB"

def pick_video_track(mi_tracks):
    vids=[t for t in mi_tracks if str(t.get("@type","")).lower()=="video"]
    return vids[0] if vids else {}

def pick_best_audio_track(mi_tracks):
    auds=[t for t in mi_tracks if str(t.get("@type","")).lower()=="audio"]
    if not auds:
        return {}

    codec_priority = {
        "TrueHD.Atmos": 120,
        "TrueHD": 115,
        "DTS-HD.MA": 110,
        "DTS-HD.HRA": 105,
        "DTS-HD": 100,
        "EAC3.Atmos": 95,
        "EAC3": 90,
        "DTS": 80,
        "AC3": 70,
        "AAC.Atmos": 65,
        "AAC": 60,
        "FLAC": 55,
        "PCM": 50,
    }

    ranked=[]
    for t in auds:
        codec=normalize_audio_codec_from_name(
            t.get("Format") or t.get("CodecID/Hint") or "",
            t.get("Format_Profile") or t.get("Format profile") or "",
            t.get("Title") or "",
            t.get("Title") or "",
            t.get("Commercial name") or "",
        )
        channels_value=parse_channel_count(t.get("Channel(s)") or t.get("Channels") or t.get("Channel(s)_Original"))
        title=t.get("Title") or ""
        commentary_penalty = -1000 if is_commentary_track(title) else 0
        default_bonus = 50 if str(t.get("Default","")).lower()=="yes" else 0
        forced_penalty = -10 if str(t.get("Forced","")).lower()=="yes" else 0
        cp = codec_priority.get(codec, 10)
        score = commentary_penalty + default_bonus + forced_penalty + cp*100 + int(channels_value*10)
        ranked.append((score, {
            "codec": codec,
            "channels_value": channels_value,
            "channels": format_channels(channels_value),
            "language": t.get("Language") or "",
            "title": title,
            "default": t.get("Default") or "",
        }))

    ranked.sort(key=lambda x: x[0], reverse=True)
    return ranked[0][1]

def detect_hdr(video_track):
    bits=[]
    vals=[
        video_track.get("HDR_Format") or video_track.get("HDR format") or "",
        video_track.get("HDR_Format_Compatibility") or "",
        video_track.get("colour_description_present") or "",
        video_track.get("Transfer characteristics") or "",
    ]
    joined=" | ".join(str(v) for v in vals if v).upper()
    if "DOLBY VISION" in joined or re.search(r"\bDV\b", joined):
        bits.append("DV")
    if "HDR10+" in joined:
        bits.append("HDR10PLUS")
    elif "HDR10" in joined:
        bits.append("HDR10")
    elif re.search(r"\bHDR\b", joined):
        bits.append("HDR")
    elif "HLG" in joined:
        bits.append("HLG")
    return bits

def normalize_resolution(video_track, mf):
    q=(mf.get("quality") or {}).get("quality") or {}
    resolution=q.get("resolution")
    if resolution:
        try:
            return f"{int(resolution)}p"
        except Exception:
            pass

    for key in ("Height", "height", "VideoHeight", "videoHeight"):
        val=video_track.get(key)
        if val:
            m=re.search(r'(\d{3,4})', str(val))
            if m:
                return f"{int(m.group(1))}p"

    mi=mf.get("mediaInfo") or {}
    val = mi.get("videoResolution") or mi.get("resolution") or mi.get("height") or mi.get("videoHeight")
    if val:
        m = re.search(r'(\d{3,4})', str(val))
        if m:
            return f"{int(m.group(1))}p"
    return ""

def normalize_vcodec(video_track):
    vc=(video_track.get("Format") or video_track.get("CodecID/Hint") or "").lower()
    if vc in ("avc","h.264","h264","x264"):
        return "H264"
    if vc in ("hevc","h.265","h265","x265"):
        return "x265"
    if vc:
        return str(video_track.get("Format") or "").upper()
    return "H264"

title=norm_title(movie.get("originalTitle") or movie.get("title") or "")
year=str(movie.get("year") or "")

mij=mediainfo_json(main_video)
tracks=((mij.get("media") or {}).get("track") or [])

video_track=pick_video_track(tracks)
audio_track=pick_best_audio_track(tracks)

audio_langs=set()
for t in tracks:
    if str(t.get("@type","")).lower()=="audio":
        audio_langs |= split_langs(t.get("Language") or "")
sub_langs=set()
for t in tracks:
    if str(t.get("@type","")).lower()=="text":
        sub_langs |= split_langs(t.get("Language") or "")

if not audio_langs:
    for x in (mf.get("languages") or []):
        name=(x.get("name") or "").lower().strip()
        if name:
            audio_langs |= split_langs(name)
    audio_langs |= split_langs((mf.get("mediaInfo") or {}).get("audioLanguages") or "")

if not sub_langs:
    sub_langs |= split_langs((mf.get("mediaInfo") or {}).get("subtitles") or "")

if "french" in audio_langs and "english" in audio_langs:
    lang=preferred_multi
elif "french" in audio_langs and len(audio_langs) == 1:
    lang="FRENCH"
elif "english" in audio_langs and "french" in sub_langs:
    lang="VOSTFR"
elif "english" in audio_langs and len(audio_langs) == 1:
    lang="ENGLISH"
elif "japanese" in audio_langs and "french" in audio_langs:
    lang=preferred_multi
elif "japanese" in audio_langs and "french" in sub_langs:
    lang="VOSTFR"
elif "japanese" in audio_langs and len(audio_langs) == 1:
    lang="JAPANESE"
else:
    lang=preferred_multi if len(audio_langs) > 1 else "UNKNOWN"

source=detect_source(movie, mf)
res=normalize_resolution(video_track, mf)
audio_codec=audio_track.get("codec") or ""
channels=audio_track.get("channels") or ""
vcodec=normalize_vcodec(video_track)
hdr_bits=detect_hdr(video_track)

release_group=clean_group(mf.get("releaseGroup") or "")
if release_group.lower() in BAD_GROUPS:
    release_group=""
if not release_group:
    release_group=default_team

parts=[title]
if year:
    parts.append(year)
parts.append(lang)
if res:
    parts.append(res)
if source:
    parts.append(source)
parts.extend(hdr_bits)
if audio_codec:
    parts.append(audio_codec)
if channels:
    parts.append(channels)
if vcodec:
    parts.append(vcodec)

name=".".join([p for p in parts if p])
name=re.sub(r"\.+",".",name).strip(".")

print(name)
print(release_group)
print(movie.get("title") or "")
print(year)
print(movie.get("path") or "")
print(mf.get("path") or "")
print(source)
print(res)
print(f"{audio_codec}.{channels}" if audio_codec and channels else (audio_codec or channels))
print(vcodec)
print(",".join(sorted(audio_langs)) if audio_langs else "")
print(",".join(sorted(sub_langs)) if sub_langs else "")
print(lang)
PY
}

create_movie_release() {
  local movie_dir="${1:-}" root="${2:-}" api_url="${3:-}" api_key="${4:-}"
  [[ -n "$movie_dir" && -n "$root" && -n "$api_url" && -n "$api_key" ]] || return 1

  local raw
  raw="$(find_radarr_movie_by_path_or_name "$movie_dir" "$api_url" "$api_key" || true)"
  [[ -n "${raw:-}" ]] || { echo "No Radarr match found: $movie_dir"; return 0; }

  local main_video
  main_video="$(pick_main_video "$movie_dir")"
  [[ -n "${main_video:-}" ]] || { echo "No video file found: $movie_dir"; return 1; }

  mapfile -t preview < <(movie_profile_json "$raw" "$main_video")
  local release_base="${preview[0]}"
  local release_group="${preview[1]}"
  local display_title="${preview[2]}"
  local display_year="${preview[3]}"
  local display_movie_path="${preview[4]}"
  local display_file_path="${preview[5]}"
  local display_source="${preview[6]}"
  local display_res="${preview[7]}"
  local display_audio="${preview[8]}"
  local display_video="${preview[9]}"
  local display_langs="${preview[10]}"
  local display_subs="${preview[11]}"
  local display_lang_tag="${preview[12]}"

  local release_name="${release_base}-${release_group}"
  local rel out_dir out_torrent out_nfo payload_dir piece

  rel="$(safe_relpath "$movie_dir" "$MEDIA_ROOT")"
  out_dir="$OUTPUT_ROOT/$rel"

  out_torrent="$out_dir/${release_name}.torrent"
  out_nfo="$out_dir/${release_name}.nfo"

  echo
  echo "Title        : $display_title"
  echo "Year         : $display_year"
  echo "Movie path   : $display_movie_path"
  echo "File path    : $main_video"
  echo "Source       : $display_source"
  echo "Resolution   : $display_res"
  echo "Audio        : $display_audio"
  echo "Video        : $display_video"
  echo "Languages    : $display_langs"
  echo "Subtitles    : $display_subs"
  echo "Lang tag     : $display_lang_tag"
  echo "Preview      : $release_name"
  echo "Output dir   : $out_dir"
  echo

  prepare_output_slot "$out_torrent"
  case $? in
    10) return 0 ;;
    0) ;;
    *) return 1 ;;
  esac

  local source_nfo
  source_nfo="$movie_dir/${release_name}.nfo"

  status "NFO"
  write_nfo "$main_video" "$out_nfo"
  cp -f "$out_nfo" "$source_nfo"
  fix_output_permissions "$out_nfo" "$source_nfo"
  fix_output_permissions "$movie_dir" "$out_dir"

  payload_dir="$(prepare_release_payload "$movie_dir" "$(basename "$movie_dir")" "$source_nfo" "$main_video" "$source_nfo")" || return 1
  piece="$(choose_piece_size "$payload_dir")"

  status "TORRENT"
  if ! build_torrent "$payload_dir" "$out_torrent" "$piece"; then
    cleanup_payload_dir "$payload_dir"
    return 1
  fi

  cleanup_payload_dir "$payload_dir"
  fix_output_permissions "$out_torrent" "$out_nfo"

  echo
  echo "Done:"
  echo " - $out_torrent"
  echo " - $out_nfo"
  print_recheck_hint "$payload_dir" "$movie_dir"
}

batch_movies_root() {
  local root="${1:-}" api_url="${2:-}" api_key="${3:-}"
  mapfile -t items < <(find "$root" -mindepth 1 -maxdepth 1 -type d | sort)
  local total="${#items[@]}" i=0 d
  for d in "${items[@]}"; do
    i=$((i + 1))
    echo
    echo "============================================================"
    echo "[$i/$total] $(basename "$d")"
    echo "============================================================"
    create_movie_release "$d" "$root" "$api_url" "$api_key" || true
  done
}

movies_menu() {
  local root
  root="$(select_movie_root)" || return 0
  [[ -n "${root:-}" ]] || return 0

  echo
  echo "Movies actions"
  echo " 1) One movie"
  echo " 2) Batch entire root"
  echo " 0) Back"
  local c
  read -r -p "Select: " c

  case "$c" in
    1)
      mapfile -t items < <(find "$root" -mindepth 1 -maxdepth 1 -type d | sort)
      local picked
      picked="$(pick_from_list_paged "Select a movie folder:" "${items[@]}")" || return 0
      if [[ "$root" == *"MOVIES_4K" ]]; then
        create_movie_release "$picked" "$root" "$RADARR_4K_URL" "$RADARR_4K_API_KEY"
      else
        create_movie_release "$picked" "$root" "$RADARR_URL" "$RADARR_API_KEY"
      fi
      press_enter
      ;;
    2)
      if [[ "$root" == *"MOVIES_4K" ]]; then
        batch_movies_root "$root" "$RADARR_4K_URL" "$RADARR_4K_API_KEY"
      else
        batch_movies_root "$root" "$RADARR_URL" "$RADARR_API_KEY"
      fi
      press_enter
      ;;
    0) return 0 ;;
    *) echo "Invalid" ;;
  esac
}
