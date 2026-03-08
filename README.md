<p align="center">
  <img src="assets/logo.png" width="500" alt="Torrentarr logo">
</p>

<h1 align="center">Torrentarr</h1>

<p align="center">
<b>Pack • Share • Automate</b>
</p>

<p align="center">
  <img src="https://img.shields.io/github/stars/Silastar/Torrentarr?style=social" alt="GitHub stars">
  <img src="https://img.shields.io/github/license/Silastar/Torrentarr" alt="GitHub license">
  <img src="https://img.shields.io/badge/docker-ready-blue" alt="Docker ready">
  <img src="https://img.shields.io/badge/bash-script-green" alt="Bash script">
  <img src="https://img.shields.io/badge/Radarr-compatible-orange" alt="Radarr compatible">
  <img src="https://img.shields.io/badge/Sonarr-compatible-yellow" alt="Sonarr compatible">
</p>

---

Torrentarr is a Dockerized Bash tool that generates tracker-ready `.torrent` and `.nfo` files from media libraries managed by **Radarr** and **Sonarr**.

It automates the creation of properly named torrents using the real metadata of your media files.

---

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Release Naming](#release-naming)
- [Example Output](#example-output)
- [Project Layout](#project-layout)
- [Requirements](#requirements)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

Torrentarr is a command-line tool designed to automate the creation of properly formatted torrent releases from media already managed by the *arr ecosystem.

It reads metadata directly from media files and generates tracker-ready releases including:

- `.torrent` files
- `.nfo` files

Torrentarr integrates naturally with:

- **Radarr** for movies
- **Sonarr** for series

It is designed for private tracker upload workflows where releases must follow strict naming conventions.

---

## How It Works

Torrentarr scans media folders already organized by Radarr or Sonarr.

Typical workflow:

1. Select a movie or series folder
2. Detect the main media file
3. Read metadata using MediaInfo
4. Build a tracker-compliant release name
5. Generate a `.torrent` file
6. Generate a `.nfo` file
7. Prepare the release folder ready for upload

---

## Features

### Movies

- Match movie folders against Radarr
- Read media metadata automatically
- Generate tracker-style release names
- Create `.torrent`
- Create `.nfo`

### Series

- Match series folders against Sonarr
- Generate season packs, episode torrents, and full series packs
- Use majority metadata for packs
- Create `.torrent`
- Create `.nfo`

### Media Detection

- Resolution: `720p`, `1080p`, `2160p`
- Video: `H264`, `x265`
- Audio: `AAC`, `AC3`, `EAC3`, `TrueHD`, `DTS`, `DTS-HD`, `DTS-HD.MA`, `Atmos`
- HDR: `DV`, `HDR`, `HDR10`, `HDR10PLUS`, `HLG`
- Source: `WEB`, `WEB-DL`, `WEBRip`, `BluRay`, `Remux`, `HDTV`, `DVDRip`

---

## Installation

Clone the repository:

```bash
git clone https://github.com/Silastar/Torrentarr.git
cd Torrentarr
```

Start the container:

```bash
docker compose up -d --build
```

Enter the container:

```bash
docker exec -it torrentarr bash
```

Run Torrentarr:

```bash
./torrent_creator.sh
```

---

## Configuration

Torrentarr uses a configuration file:

```
config.env
```

This file defines runtime settings such as:

- Media paths
- Output directories
- Radarr API settings
- Sonarr API settings
- Tracker announce URL

Example:

```env
MEDIA_ROOT=/MEDIA
OUTPUT_ROOT=/TORRENTS

RADARR_URL=http://radarr_url:radarr_port
RADARR_API_KEY=your_radarr_api_key

SONARR_URL=http://sonarr_url:sonarr_port
SONARR_API_KEY=your_sonarr_api_key

ANNOUNCE=https://your-tracker/announce/xxxxxxxx
PRIVATE_FLAG=1
```

---

## Usage

Run the tool inside the container:

```bash
./torrent_creator.sh
```

Main menu:

```
1) Movies
2) Series
0) Quit
```

Movie mode allows:

- single movie processing
- batch processing

Series mode allows:

- full series packs
- season packs
- individual episode releases

---

## Release Naming

Torrentarr builds tracker-compliant release names based on detected metadata.

Example:

```
Dune.Part.Two.2024.MULTI.2160p.WEB-DL.DV.HDR10.EAC3.Atmos.5.1.x265-Torrentarr
```

Naming may include:

- resolution
- source
- HDR flags
- audio codec
- channel layout
- video codec
- release group

---

## Example Output

Example movie release structure:

```
Dune.Part.Two.2024.MULTI.2160p.WEB-DL.DV.HDR10.EAC3.Atmos.5.1.x265-Torrentarr
├── Dune.Part.Two.2024.mkv
├── Dune.Part.Two.2024-Torrentarr.nfo
└── Dune.Part.Two.2024-Torrentarr.torrent
```

Torrentarr automatically generates:

- `.torrent` file
- `.nfo` file
- release folder ready for upload

---

## Project Layout

```
Torrentarr/
├─ assets/
│  ├─ icon.png
│  └─ logo.png
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
```

---

## Requirements

- Docker
- Radarr
- Sonarr
- Media files organized by the *arr ecosystem

---

## Roadmap

Planned improvements:

- Terminal UI (TUI)
- batch processing improvements
- tracker profile support
- better metadata detection
- Unraid template

---

## Contributing

Contributions are welcome.

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Open a Pull Request

Bug reports and feature requests can be submitted using GitHub Issues.

---

## License

This project is currently provided without a formal license.
A license will be added in a future release.
