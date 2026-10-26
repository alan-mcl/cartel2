#!/usr/bin/env python3
"""Generate silent placeholder OGG files for the audio system (replace with shipped assets later)."""

from __future__ import annotations

import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
AUDIO_ROOT = REPO / "assets" / "audio"
SAMPLE_RATE = 44100

# Paths under assets/audio/ to leave unchanged (e.g. hand-authored menu music).
SKIP_REL_OGG: frozenset[str] = frozenset({"music/menu/menu_01.ogg"})


def _silence_wav(path: Path, duration_sec: float) -> None:
    n = max(1, int(SAMPLE_RATE * duration_sec))
    samples = [0] * n
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def _to_ogg(wav_path: Path, ogg_path: Path) -> None:
    ogg_path.parent.mkdir(parents=True, exist_ok=True)
    for cmd in (
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav_path), "-c:a", "libvorbis", "-q:a", "4", str(ogg_path)],
        ["oggenc", "-q", "4", "-o", str(ogg_path), str(wav_path)],
    ):
        if shutil.which(cmd[0]) is None:
            continue
        subprocess.run(cmd, check=True)
        return
    raise RuntimeError("Need ffmpeg or oggenc on PATH to build placeholder OGG files.")


def _emit(rel_ogg: str, duration: float) -> None:
    if rel_ogg in SKIP_REL_OGG:
        print("skip", rel_ogg)
        return
    ogg_path = AUDIO_ROOT / rel_ogg
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / "silence.wav"
        _silence_wav(wav_path, duration)
        _to_ogg(wav_path, ogg_path)
    print("wrote", ogg_path.relative_to(REPO))


def main() -> int:
    # Duration only affects file size; loops and one-shots are all silent.
    specs: list[tuple[str, float]] = [
        ("music/menu/menu_01.ogg", 8.0),
        ("music/exploration/exploration_01.ogg", 8.0),
        ("music/habitat/habitat_01.ogg", 8.0),
        ("music/shipyard/shipyard_01.ogg", 8.0),
        ("music/market/market_01.ogg", 8.0),
        ("music/exploration/danger_01.ogg", 8.0),
        ("ambience/space/space_ambience_01.ogg", 6.0),
        ("ambience/habitat/habitat_ambience_01.ogg", 6.0),
        ("sfx/ui/ui_button_click_01.ogg", 0.05),
        ("sfx/ui/ui_button_hover_01.ogg", 0.05),
        ("sfx/ui/ui_confirm_01.ogg", 0.05),
        ("sfx/ship/ship_collision_metal_01.ogg", 0.05),
        ("sfx/ship/ship_collision_metal_02.ogg", 0.05),
        ("sfx/ship/ship_collision_metal_03.ogg", 0.05),
        ("sfx/ship/ship_thruster_loop.ogg", 2.0),
        ("sfx/interaction/salvage_complete_01.ogg", 0.05),
        ("sfx/notification/notification_alert_01.ogg", 0.05),
    ]
    for rel, duration in specs:
        _emit(rel, duration)
    return 0


if __name__ == "__main__":
    sys.exit(main())
