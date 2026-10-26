#!/usr/bin/env python3
"""Generate placeholder OGG for the audio system (replace with shipped assets later).

Music and ambience: silent loops. UI/SFX: short dry tones. Skips hand-authored paths in SKIP_REL_OGG.
"""

from __future__ import annotations

import math
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


def _tone_wav(path: Path, freq: float, duration_sec: float) -> None:
    n = int(SAMPLE_RATE * duration_sec)
    samples = []
    attack = int(SAMPLE_RATE * 0.008)
    release = int(SAMPLE_RATE * 0.04)
    for i in range(n):
        amp = 0.45
        if i < attack:
            amp *= i / max(attack, 1)
        elif i > n - release:
            amp *= max(n - i, 0) / max(release, 1)
        t = i / SAMPLE_RATE
        samples.append(int(32767 * amp * math.sin(2 * math.pi * freq * t)))

    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def _loop_tone_wav(path: Path, freq: float, duration_sec: float) -> None:
    n = int(SAMPLE_RATE * duration_sec)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = 0.35
        if i < SAMPLE_RATE * 0.02:
            env *= i / (SAMPLE_RATE * 0.02)
        if i > n - SAMPLE_RATE * 0.02:
            env *= (n - i) / (SAMPLE_RATE * 0.02)
        samples.append(int(32767 * env * math.sin(2 * math.pi * freq * t)))
    if n > 1:
        samples[-1] = samples[0]
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


def _emit_silence(rel_ogg: str, duration: float) -> None:
    if rel_ogg in SKIP_REL_OGG:
        print("skip", rel_ogg)
        return
    ogg_path = AUDIO_ROOT / rel_ogg
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / "silence.wav"
        _silence_wav(wav_path, duration)
        _to_ogg(wav_path, ogg_path)
    print("wrote (silent)", ogg_path.relative_to(REPO))


def _emit_tone(rel_ogg: str, freq: float, duration: float, *, loop: bool = False) -> None:
    ogg_path = AUDIO_ROOT / rel_ogg
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / "tone.wav"
        if loop:
            _loop_tone_wav(wav_path, freq, duration)
        else:
            _tone_wav(wav_path, freq, duration)
        _to_ogg(wav_path, ogg_path)
    print("wrote (tone)", ogg_path.relative_to(REPO))


def main() -> int:
    silence_specs: list[tuple[str, float]] = [
        ("music/menu/menu_01.ogg", 8.0),
        ("music/exploration/exploration_01.ogg", 8.0),
        ("music/habitat/habitat_01.ogg", 8.0),
        ("music/shipyard/shipyard_01.ogg", 8.0),
        ("music/market/market_01.ogg", 8.0),
        ("music/exploration/danger_01.ogg", 8.0),
        ("ambience/space/space_ambience_01.ogg", 6.0),
        ("ambience/habitat/habitat_ambience_01.ogg", 6.0),
    ]
    tone_specs: list[tuple[str, float, float, bool]] = [
        ("sfx/ui/ui_button_click_01.ogg", 880.0, 0.06, False),
        ("sfx/ui/ui_button_hover_01.ogg", 660.0, 0.04, False),
        ("sfx/ui/ui_confirm_01.ogg", 988.0, 0.08, False),
        ("sfx/ship/ship_collision_metal_01.ogg", 320.0, 0.12, False),
        ("sfx/ship/ship_collision_metal_02.ogg", 280.0, 0.12, False),
        ("sfx/ship/ship_collision_metal_03.ogg", 350.0, 0.12, False),
        ("sfx/ship/ship_thruster_loop.ogg", 90.0, 2.0, True),
        ("sfx/interaction/salvage_complete_01.ogg", 523.0, 0.15, False),
        ("sfx/notification/notification_alert_01.ogg", 740.0, 0.2, False),
    ]
    for rel, duration in silence_specs:
        _emit_silence(rel, duration)
    for rel, freq, duration, loop in tone_specs:
        _emit_tone(rel, freq, duration, loop=loop)
    return 0


if __name__ == "__main__":
    sys.exit(main())
