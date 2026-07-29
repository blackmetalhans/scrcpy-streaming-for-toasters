## [0.1.1] - 2026-07-29
- Refactor: README expanded with practical uses and low-end PC tips.
- Behavior: Autodetect ADB_SERIAL when empty; safer device selection.
- Helpers: Hardened get_scrcpy_release.sh and get_scrcpy_release.ps1 with better fallbacks.
- Repo metadata: .gitattributes and .gitignore improved.
- archive/: added README explaining archived files.
- CI: Add basic GitHub Actions workflow to build release asset on tag.
- Misc: prepare for v0.1.1 release.
# Changelog

All notable changes to this project.

## [0.1.0] - 2026-07-29
- Initial release: scripts and documentation to stream from an Android camera to OBS using scrcpy.
- Added helpers: get_scrcpy_release.ps1, get_scrcpy_release.sh to download scrcpy binaries into bin/.
- Archived legacy files: BASS_CAM_final.bat, BASS_Cam_min.bat (moved to archive/).
- README updated with Quickstart, troubleshooting and release instructions.
