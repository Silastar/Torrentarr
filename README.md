# Torrentarr v5

![Version](https://img.shields.io/github/v/release/Silastar/Torrentarr)
![Stars](https://img.shields.io/github/stars/Silastar/Torrentarr?style=social)
![License](https://img.shields.io/badge/license-not%20set-lightgrey)
![GitHub Repo](https://img.shields.io/github/stars/Silastar/Torrentarr?style=social)

<p align="center">
  <img src="assets/logo.png" width="500">
</p>

# Torrentarr

**Pack • Share • Automate**

<p align="center">
  <img src="assets/logo.png" width="500">
</p>

<h1 align="center">Torrentarr</h1>

<p align="center">
<b>Pack • Share • Automate</b>
</p>

<p align="center">
<img src="https://img.shields.io/github/v/release/Silastar-1976/Torrentarr">
<img src="https://img.shields.io/github/stars/Silastar-1976/Torrentarr?style=social">
<img src="https://img.shields.io/github/license/Silastar-1976/Torrentarr">
<img src="https://img.shields.io/badge/docker-ready-blue">
<img src="https://img.shields.io/badge/bash-script-green">
<img src="https://img.shields.io/badge/Radarr-compatible-orange">
<img src="https://img.shields.io/badge/Sonarr-compatible-yellow">
</p>

---

Torrentarr is a Dockerized Bash tool that generates tracker-ready `.torrent` and `.nfo` files from media libraries managed by **Radarr** and **Sonarr**.

It automates the creation of properly named torrents using the real metadata of your media files.

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
