#!/usr/bin/env python3
"""Remove PNG backgrounds with rembg, optionally scale with GIMP LoHalo, write XCF + PNG pairs."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from fit import fit_inside, parse_size
DEFAULT_GIMP_FLATPAK = Path("/var/lib/flatpak/exports/bin/org.gimp.GIMP")
DEFAULT_MODEL = "birefnet-general"
PODMAN_IMAGE = "localhost/cartel-rembg:3.12"
GIMP_BATCH_SCRIPT = ROOT / "gimp_batch_build.py"


def find_gimp(explicit: str | None) -> str:
    if explicit:
        path = Path(explicit)
        if not path.is_file():
            raise SystemExit(f"GIMP binary not found: {explicit}")
        return str(path)

    env = os.environ.get("GIMP")
    if env and Path(env).is_file():
        return env

    if DEFAULT_GIMP_FLATPAK.is_file():
        return str(DEFAULT_GIMP_FLATPAK)

    home_flatpak = Path.home() / ".local/share/flatpak/exports/bin/org.gimp.GIMP"
    if home_flatpak.is_file():
        return str(home_flatpak)

    which = shutil.which("gimp")
    if which:
        return which

    raise SystemExit(
        "GIMP not found. Install GIMP or pass --gimp /path/to/gimp "
        "(Flatpak: /var/lib/flatpak/exports/bin/org.gimp.GIMP)."
    )


def list_input_pngs(input_dir: Path) -> list[Path]:
    if not input_dir.is_dir():
        raise SystemExit(f"input is not a directory: {input_dir}")
    return sorted(p for p in input_dir.iterdir() if p.is_file() and p.suffix.lower() == ".png")


def output_paths(output_dir: Path, stem: str) -> tuple[Path, Path]:
    return output_dir / f"{stem}.xcf", output_dir / f"{stem}.png"


def should_skip(xcf_out: Path, force: bool) -> bool:
    return xcf_out.exists() and not force


def rembg_folder_podman(input_dir: Path, cuts_dir: Path, model: str) -> None:
    """Remove backgrounds for every PNG in input_dir with one container invocation."""
    repo_root = ROOT.parent.resolve()
    cuts_dir.mkdir(parents=True, exist_ok=True)
    batch_script = cuts_dir / "_rembg_batch.py"
    batch_script.write_text(
        "\n".join(
            [
                "from pathlib import Path",
                "from rembg import remove, new_session",
                f"inp = Path({str(input_dir.resolve())!r})",
                f"out = Path({str(cuts_dir.resolve())!r})",
                f"session = new_session({model!r})",
                'for src in sorted(inp.glob("*.png")):',
                "    cut = out / src.name",
                "    if cut.is_file() and cut.stat().st_size > 0:",
                '        print(f"skip {src.name}")',
                "        continue",
                "    cut.write_bytes(remove(src.read_bytes(), session=session))",
                "    print(src.name)",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    cache = Path.home() / ".cache" / "rembg-podman"
    cache.mkdir(parents=True, exist_ok=True)
    image = PODMAN_IMAGE
    if subprocess.run(["podman", "image", "exists", image], capture_output=True).returncode != 0:
        image = "docker.io/library/python:3.12-slim"
        bootstrap = (
            "pip install -q 'rembg[cpu]' onnxruntime pillow && "
            f"python3 {batch_script.resolve()}"
        )
    else:
        bootstrap = f"python3 {batch_script.resolve()}"
    cmd = [
        "podman",
        "run",
        "--rm",
        "-v",
        f"{repo_root}:{repo_root}:Z",
        "-v",
        f"{cache}:/root/.u2net:Z",
        "-v",
        f"{cache}:/root/.rembg:Z",
        image,
        "bash",
        "-lc",
        bootstrap,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    expected = len(list(input_dir.glob("*.png")))
    got = len([p for p in cuts_dir.glob("*.png") if p.is_file() and p.stat().st_size > 0])
    if result.returncode != 0 and got < expected:
        tail = ((result.stderr or "") + (result.stdout or "")).strip()[-3000:]
        raise RuntimeError(f"podman rembg folder batch failed ({got}/{expected} cuts): {tail}")
    if got < expected:
        raise RuntimeError(f"podman rembg incomplete: {got}/{expected} cuts in {cuts_dir}")


def remove_background_podman(source: Path, cutout_tmp: Path, model: str) -> tuple[int, int]:
    """Run rembg inside a Python 3.12 container when onnxruntime is unavailable on the host."""
    repo_root = ROOT.parent.resolve()
    one_off = cutout_tmp.parent / f"_rembg_one_{cutout_tmp.stem}.py"
    one_off.write_text(
        "\n".join(
            [
                "from pathlib import Path",
                "from rembg import remove, new_session",
                f"source = Path({str(source.resolve())!r})",
                f"cutout = Path({str(cutout_tmp.resolve())!r})",
                f"session = new_session({model!r})",
                "cutout.write_bytes(remove(source.read_bytes(), session=session))",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    cache = Path.home() / ".cache" / "rembg-podman"
    cache.mkdir(parents=True, exist_ok=True)
    image = PODMAN_IMAGE
    bootstrap = (
        f"python3 {one_off.resolve()}"
        if subprocess.run(["podman", "image", "exists", image], capture_output=True).returncode == 0
        else f"pip install -q 'rembg[cpu]' onnxruntime pillow && python3 {one_off.resolve()}"
    )
    cmd = [
        "podman",
        "run",
        "--rm",
        "-v",
        f"{repo_root}:{repo_root}:Z",
        "-v",
        f"{cache}:/root/.u2net:Z",
        "-v",
        f"{cache}:/root/.rembg:Z",
        image if subprocess.run(["podman", "image", "exists", image], capture_output=True).returncode == 0
        else "docker.io/library/python:3.12-slim",
        "bash",
        "-lc",
        bootstrap,
    ]
    result = subprocess.run(cmd, check=False)
    if result.returncode != 0 or not cutout_tmp.is_file() or cutout_tmp.stat().st_size == 0:
        raise RuntimeError(f"podman rembg failed for {source.name} (exit {result.returncode})")
    with Image.open(cutout_tmp) as img:
        return img.size


def remove_background(
    session,
    source: Path,
    cutout_tmp: Path,
    model: str = DEFAULT_MODEL,
) -> tuple[int, int]:
    if session is not None:
        from rembg import remove

        with source.open("rb") as handle:
            cut_bytes = remove(handle.read(), session=session)
        cutout_tmp.write_bytes(cut_bytes)
        with Image.open(cutout_tmp) as img:
            return img.size
    return remove_background_podman(source, cutout_tmp, model)


def run_gimp(gimp_bin: str, job_path: Path) -> None:
    env = os.environ.copy()
    env["BGREMOVE_JOB"] = str(job_path)
    cmd = [
        gimp_bin,
        "-i",
        "--batch-interpreter",
        "python-fu-eval",
        "-b",
        f"exec(open({json.dumps(str(GIMP_BATCH_SCRIPT))}).read())",
        "--quit",
    ]
    result = subprocess.run(
        cmd,
        env=env,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        stderr = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"GIMP batch failed (exit {result.returncode}): {stderr}")


def process_one(
    source: Path,
    output_dir: Path,
    gimp_bin: str,
    session,
    canvas: tuple[int, int] | None,
    force: bool,
    model: str = DEFAULT_MODEL,
    precut: Path | None = None,
) -> str:
    stem = source.stem
    xcf_out, png_out = output_paths(output_dir, stem)
    if should_skip(xcf_out, force):
        return "skip"

    output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        suffix=".png",
        prefix=f"{stem}-cut-",
        dir=output_dir,
        delete=False,
    ) as tmp:
        cutout_path = Path(tmp.name)

    try:
        if precut is not None and precut.is_file():
            shutil.copy2(precut, cutout_path)
            with Image.open(source) as img:
                src_w, src_h = img.size
        else:
            src_w, src_h = remove_background(session, source, cutout_path, model)
        job: dict = {
            "source_png": str(source.resolve()),
            "cutout_png": str(cutout_path.resolve()),
            "xcf_out": str(xcf_out.resolve()),
            "png_out": str(png_out.resolve()),
        }
        if canvas is not None:
            cw, ch = canvas
            tw, th, _scale, off_x, off_y = fit_inside(src_w, src_h, cw, ch)
            job["canvas"] = {
                "width": cw,
                "height": ch,
                "scaled_width": tw,
                "scaled_height": th,
                "offset_x": off_x,
                "offset_y": off_y,
            }

        with tempfile.NamedTemporaryFile(
            mode="w",
            suffix=".json",
            prefix=f"{stem}-job-",
            delete=False,
            encoding="utf-8",
        ) as job_file:
            json.dump(job, job_file)
            job_path = Path(job_file.name)

        try:
            run_gimp(gimp_bin, job_path)
        finally:
            job_path.unlink(missing_ok=True)
    finally:
        cutout_path.unlink(missing_ok=True)

    return "ok"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_dir", type=Path, help="folder of source PNG files (one level)")
    parser.add_argument("output_dir", type=Path, help="folder for paired .xcf and .png outputs")
    parser.add_argument("--size", metavar="WxH", help="fit every image inside this canvas (e.g. 120x160)")
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"rembg model (default: {DEFAULT_MODEL})")
    parser.add_argument("--gimp", metavar="PATH", help="GIMP binary (default: Flatpak org.gimp.GIMP or PATH gimp)")
    parser.add_argument("--force", action="store_true", help="replace existing .xcf outputs")
    args = parser.parse_args(argv)

    canvas: tuple[int, int] | None = None
    if args.size:
        canvas = parse_size(args.size)

    gimp_bin = find_gimp(args.gimp)

    session = None
    use_podman = False
    try:
        from rembg import new_session

        session = new_session(args.model)
    except ImportError:
        if shutil.which("podman") is None:
            print(
                "rembg is not installed and podman was not found. "
                "Run: pip install -r bgremove/requirements.txt",
                file=sys.stderr,
            )
            return 1
        use_podman = True
        print("rembg not on host Python; using podman (python:3.12-slim) for cutouts.", file=sys.stderr)
    sources = list_input_pngs(args.input_dir)
    if not sources:
        print(f"no PNG files in {args.input_dir}", file=sys.stderr)
        return 1

    ok = skip = errors = 0
    for source in sources:
        try:
            status = process_one(
                source,
                args.output_dir,
                gimp_bin,
                session,
                canvas,
                args.force,
                args.model,
                None,
            )
            if status == "skip":
                skip += 1
                print(f"skip {source.name} ({output_paths(args.output_dir, source.stem)[0].name} exists)")
            else:
                ok += 1
                print(f"wrote {source.stem}.xcf and {source.stem}.png")
        except Exception as exc:  # noqa: BLE001 - batch CLI should continue
            errors += 1
            print(f"error {source.name}: {exc}", file=sys.stderr)

    print(f"done: {ok} wrote, {skip} skipped, {errors} failed")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
