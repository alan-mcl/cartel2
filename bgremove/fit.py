"""Canvas fit maths (no image I/O)."""

from __future__ import annotations

import re


_SIZE_RE = re.compile(r"^\s*(\d+)\s*[xX×]\s*(\d+)\s*$")


def parse_size(value: str) -> tuple[int, int]:
    match = _SIZE_RE.match(value)
    if not match:
        raise ValueError(f"invalid --size {value!r}; expected WIDTHxHEIGHT (e.g. 64x64)")
    width = int(match.group(1))
    height = int(match.group(2))
    if width < 1 or height < 1:
        raise ValueError("--size dimensions must be positive integers")
    return width, height


def fit_inside(
    src_width: int,
    src_height: int,
    canvas_width: int,
    canvas_height: int,
) -> tuple[int, int, float, int, int]:
    """Return scaled size, scale factor, and centre offsets on the target canvas."""
    if src_width < 1 or src_height < 1:
        raise ValueError("source dimensions must be positive")

    scale = min(canvas_width / src_width, canvas_height / src_height)
    if scale > 1.0:
        scale = 1.0

    new_width = max(1, int(round(src_width * scale)))
    new_height = max(1, int(round(src_height * scale)))
    offset_x = (canvas_width - new_width) // 2
    offset_y = (canvas_height - new_height) // 2
    return new_width, new_height, scale, offset_x, offset_y
