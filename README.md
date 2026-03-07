# torrent-creator v5

`torrent-creator` is a Dockerized Bash tool that generates tracker-ready `.torrent` and `.nfo` files from media already managed by Radarr and Sonarr.

It supports:

- Movies
- Series
- Season packs
- Full series packs for ended shows
- Individual episode torrents
- 4K / HDR / DV detection
- Audio / subtitle / language tagging
- Release group reuse when available
- Direct torrent creation from source media, with optional staging

---

## Features

### Movies
- Match movie folders against Radarr
- Read the real media file metadata
- Generate tracker-style names
- Create `.torrent`
- Create `.nfo`

### Series
- Match series folders against Sonarr
- Generate:
  - season packs
  - episode torrents
  - full series packs for ended shows
- Use majority metadata for packs
- Create `.torrent`
- Create `.nfo`

### Media detection
- Resolution: `720p`, `1080p`, `2160p`
- Video: `H264`, `x265`
- Audio: `AAC`, `AC3`, `EAC3`, `TrueHD`, `DTS`, `DTS-HD`, `DTS-HD.MA`, `Atmos`
- HDR: `DV`, `HDR`, `HDR10`, `HDR10PLUS`, `HLG`
- Source: `WEB`, `WEB-DL`, `WEBRip`, `BluRay`, `Remux`, `HDTV`, `DVDRip`

---

## Project layout

```text
torrent-creator/
├─ Dockerfile
├─ docker-compose.yml
├─ config.env
├─ config.env.example
├─ README.md
├─ torrent_creator.sh
└─ lib/
   ├─ common.sh
   ├─ movies.sh
   └─ series.sh

