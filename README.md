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
