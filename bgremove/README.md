# bgremove

Standalone batch tool: read PNGs from a folder, remove backgrounds with [rembg](https://github.com/danielgatis/rembg), optionally scale every result onto one canvas with GIMP **LoHalo**, and write a matching `.xcf` and transparent `.png` into an output folder. It does not depend on any game engine or project layout.

## Install

```bash
pip install -r bgremove/requirements.txt
```

The first rembg run downloads model weights into your home directory (network once). After that, cutouts are local.

GIMP **3.x** is required for XCF export and LoHalo scaling. On this machine the Flatpak build is used by default (`org.gimp.GIMP`). Override with `--gimp` or the `GIMP` environment variable.

## Usage

```bash
python3 bgremove/bgremove.py INPUT_DIR OUTPUT_DIR
python3 bgremove/bgremove.py INPUT_DIR OUTPUT_DIR --size 64x64
python3 bgremove/bgremove.py INPUT_DIR OUTPUT_DIR --model isnet-anime --force
```

- Only `*.png` files in `INPUT_DIR` (non-recursive) are processed.
- For `foo.png` the tool writes `OUTPUT_DIR/foo.xcf` and `OUTPUT_DIR/foo.png`.
- **No `--size`:** outputs keep the source pixel dimensions (no resampling).
- **`--size WIDTHxHEIGHT`:** every output canvas is exactly that size. The image is scaled uniformly to fit inside (aspect preserved, centred, transparent padding). Sources smaller than the canvas are not enlarged.
- Scaling runs **after** background removal so a scale-down can soften mask speckle. Resampling is done in GIMP (premultiplied alpha, LoHalo), not in Pillow.
- If `foo.xcf` already exists, that file is skipped so hand-edited work is preserved. Use `--force` to rebuild.
- Each XCF has a hidden `source` layer (original) and a visible `cutout` layer. The exported PNG is the visible composite.

## Quality notes

For hard-edged art (sprites, logos, icons), local `birefnet-general` is usually on par with hosted “remove background” tools. Hair, fur, glass, and busy photos may need manual touch-up in GIMP on the `cutout` layer.

## Tests

```bash
python3 bgremove/test_bgremove.py
```

Tests cover size parsing, fit maths, and output naming only (no rembg, no GIMP).
