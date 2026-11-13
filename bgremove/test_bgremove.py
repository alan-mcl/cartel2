#!/usr/bin/env python3
"""Unit tests for bgremove helpers (no rembg, no GIMP)."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

_ROOT = Path(__file__).resolve().parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

import bgremove as bgremove_mod  # noqa: E402
from fit import fit_inside, parse_size  # noqa: E402


class TestParseSize(unittest.TestCase):
    def test_parses_lowercase_x(self) -> None:
        self.assertEqual(parse_size("64x64"), (64, 64))

    def test_parses_uppercase_x(self) -> None:
        self.assertEqual(parse_size("120X160"), (120, 160))

    def test_rejects_invalid(self) -> None:
        with self.assertRaises(ValueError):
            parse_size("abc")


class TestFitInside(unittest.TestCase):
    def test_uniform_downscale(self) -> None:
        w, h, scale, ox, oy = fit_inside(200, 100, 64, 64)
        self.assertAlmostEqual(scale, 0.32)
        self.assertEqual((w, h), (64, 32))
        self.assertEqual((ox, oy), (0, 16))

    def test_no_upscale(self) -> None:
        w, h, scale, ox, oy = fit_inside(40, 50, 120, 160)
        self.assertEqual(scale, 1.0)
        self.assertEqual((w, h), (40, 50))
        self.assertEqual((ox, oy), (40, 55))

    def test_aspect_preserved_not_stretched(self) -> None:
        w, h, _, _, _ = fit_inside(100, 40, 64, 64)
        self.assertEqual(h, 26)
        self.assertEqual(w, 64)


class TestPathsAndSkip(unittest.TestCase):
    def test_output_names(self) -> None:
        out = Path("/tmp/out")
        xcf, png = bgremove_mod.output_paths(out, "sprite")
        self.assertEqual(xcf.name, "sprite.xcf")
        self.assertEqual(png.name, "sprite.png")

    def test_skip_when_xcf_exists(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            output_dir = Path(tmp)
            xcf, _ = bgremove_mod.output_paths(output_dir, "a")
            xcf.write_text("placeholder", encoding="utf-8")
            self.assertTrue(bgremove_mod.should_skip(xcf, force=False))
            self.assertFalse(bgremove_mod.should_skip(xcf, force=True))


if __name__ == "__main__":
    unittest.main()
