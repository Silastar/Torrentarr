<p align="center">
  <img src="assets/logo.png" width="500">
</p>

<h1 align="center">Torrentarr</h1>

<p align="center">
<b>Pack • Share • Automate</b>
</p>

<p align="center">

![Stars](https://img.shields.io/github/stars/Silastar-1976/Torrentarr?style=social)
![License](https://img.shields.io/github/license/Silastar-1976/Torrentarr)
![Docker](https://img.shields.io/badge/docker-ready-blue)
![Bash](https://img.shields.io/badge/bash-script-green)
![Radarr](https://img.shields.io/badge/Radarr-compatible-orange)
![Sonarr](https://img.shields.io/badge/Sonarr-compatible-yellow)

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
- [Project Layout](#project-layout)
- [Requirements](#requirements)
- [Roadmap](#roadmap)

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

The typical workflow is:

1. Select a movie or series folder
2. Detect the main media file
3. Read metadata using MediaInfo
4. Build a tracker-compliant release name
5. Generate a `.torrent` file
6. Generate a `.nfo` file
7. Prepare the release folder ready for upload

---

## Configuration

Torrentarr uses a configuration file named:

```bash
config.env

This file defines all runtime settings used by the container and the scripts.

Main configuration areas

Media source paths

Torrent output paths

Radarr API connection

Sonarr API connection

Tracker announce URL

Naming preferences

Staging and behavior options

Example settings
MEDIA_ROOT=/MEDIA
OUTPUT_ROOT=/TORRENTS

RADARR_URL=http://192.168.1.127:2250
RADARR_API_KEY=your_radarr_api_key

SONARR_URL=http://192.168.1.127:2252
SONARR_API_KEY=your_sonarr_api_key

ANNOUNCE=https://your-tracker/announce/xxxxxxxx
PRIVATE_FLAG=1

DEFAULT_TEAM=NOTAG
PREFERRED_LANG_MULTI=MULTI

USE_STAGING=1
STAGING_DIR=/MEDIA/.torrentarr-staging
SHOW_PROGRESS=1
SKIP_EXISTING=1
DRY_RUN=0
Notes

MEDIA_ROOT is the root folder where your media library is mounted

OUTPUT_ROOT is where generated .torrent and .nfo files will be written

ANNOUNCE must match your private tracker announce URL

DRY_RUN=1 allows testing without creating real torrent files

USE_STAGING=1 enables a temporary clean payload directory before torrent creation

---

## Usage

Start the container:

```bash
docker compose up -d --build

Enter the container:

docker exec -it torrentarr bash

Run Torrentarr:

./torrent_creator.sh

Main Menu

Torrentarr provides an interactive menu:

1) Movies
2) Series
0) Quit
Movies

In movie mode, Torrentarr can:

process a single movie folder

process a full movie root in batch mode

Series

In series mode, Torrentarr can:

preview the release plan for a series

generate releases for one series

batch process a full series root

Depending on the series status, Torrentarr can generate:

full series packs

season packs

episode releases

---

## Release Naming

Torrentarr generates tracker-compliant release names based on the detected metadata from the media file.

A generated release name may include:

- Title
- Year
- Language tag
- Resolution
- Source
- HDR or Dolby Vision flags
- Audio codec
- Channel layout
- Video codec
- Release group

### Example Movie Release

```text
Dune.Part.Two.2024.MULTI.2160p.WEB-DL.DV.HDR10.EAC3.Atmos.5.1.x265-Torrentarr

### Example Series Release

The.Last.of.Us.S01.MULTI.1080p.WEB-DL.EAC3.5.1.H264-Torrentarr

### Example Episode Release

The.Last.of.Us.S01E01.MULTI.1080p.WEB-DL.EAC3.5.1.H264-Torrentarr

### Naming behavior depends on:

detected media metadata

available audio and subtitle languages

source quality

tracker naming expectations

configured default team or release group

# Features

### Movies

* Match movie folders against Radarr
* Read media metadata automatically
* Generate tracker-style release names
* Create `.torrent`
* Create `.nfo`

### Series

* Match series folders against Sonarr
* Generate:

  * season packs
  * episode torrents
  * full series packs for ended shows
* Use majority metadata for packs
* Create `.torrent`
* Create `.nfo`

### Media detection

* Resolution: `720p`, `1080p`, `2160p`
* Video: `H264`, `x265`
* Audio: `AAC`, `AC3`, `EAC3`, `TrueHD`, `DTS`, `DTS-HD`, `DTS-HD.MA`, `Atmos`
* HDR: `DV`, `HDR`, `HDR10`, `HDR10PLUS`, `HLG`
* Source: `WEB`, `WEB-DL`, `WEBRip`, `BluRay`, `Remux`, `HDTV`, `DVDRip`

---

# Installation

Clone the repository:

```bash
git clone https://github.com/Silastar-1976/Torrentarr.git
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

# Project Layout

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

# Requirements

* Docker
* Radarr
* Sonarr
* Media files already organized by the *arr ecosystem

---

# Roadmap

Future improvements planned:

* TUI interface
* automatic batch processing
* tracker profile support
* improved metadata detection
* Unraid template
