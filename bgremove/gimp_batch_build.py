"""Run inside GIMP batch mode (python-fu-eval). Reads a job JSON path from BGREMOVE_JOB."""

from __future__ import annotations

import json
import os
from pathlib import Path

from gi.repository import Gimp, Gio


def _set_interpolation_lohalo() -> None:
    _pdb_run("gimp-context-set-interpolation", {"interpolation": Gimp.InterpolationType.LOHALO})


def _pdb_status(result: object) -> int:
    if isinstance(result, Gimp.PDBStatusType):
        return int(result)
    if hasattr(result, "length") and result.length() >= 1:
        return int(result.index(0))
    return int(Gimp.PDBStatusType.EXECUTION_ERROR)


def _pdb_run(name: str, props: dict) -> None:
    proc = Gimp.get_pdb().lookup_procedure(name)
    if proc is None:
        raise RuntimeError(f"unknown GIMP procedure: {name}")
    config = proc.create_config()
    for key, value in props.items():
        config.set_property(key, value)
    status = _pdb_status(proc.run(config))
    if status != int(Gimp.PDBStatusType.SUCCESS):
        raise RuntimeError(f"{name} failed with status {status}")


def _load_job() -> dict:
    job_path = os.environ.get("BGREMOVE_JOB")
    if not job_path:
        raise RuntimeError("BGREMOVE_JOB environment variable is not set")
    with Path(job_path).open(encoding="utf-8") as handle:
        return json.load(handle)


def build_from_job(job: dict) -> None:
    src_path = job["source_png"]
    cut_path = job["cutout_png"]
    xcf_path = job["xcf_out"]
    png_path = job["png_out"]
    canvas = job.get("canvas")

    cut_img = Gimp.file_load(Gimp.RunMode.NONINTERACTIVE, Gio.File.new_for_path(cut_path))
    base = cut_img.duplicate()
    cut_img.delete()

    src_layer = Gimp.file_load_layer(Gimp.RunMode.NONINTERACTIVE, base, Gio.File.new_for_path(src_path))
    if src_layer is None:
        raise RuntimeError(f"failed to load source layer: {src_path}")
    base.insert_layer(src_layer, None, 0)
    src_layer.set_name("source")
    src_layer.set_visible(False)

    layers = base.get_layers()
    if not layers:
        raise RuntimeError("cutout image has no layers")
    cut_layer = layers[-1]
    cut_layer.set_name("cutout")
    cut_layer.set_visible(True)

    if canvas is not None:
        canvas_w = int(canvas["width"])
        canvas_h = int(canvas["height"])
        target_w = int(canvas["scaled_width"])
        target_h = int(canvas["scaled_height"])
        off_x = int(canvas["offset_x"])
        off_y = int(canvas["offset_y"])

        if base.get_width() != target_w or base.get_height() != target_h:
            _set_interpolation_lohalo()
            _pdb_run(
                "gimp-image-scale",
                {
                    "image": base,
                    "new-width": target_w,
                    "new-height": target_h,
                },
            )

        if (
            base.get_width() != canvas_w
            or base.get_height() != canvas_h
            or off_x != 0
            or off_y != 0
        ):
            _pdb_run(
                "gimp-image-resize",
                {
                    "image": base,
                    "new-width": canvas_w,
                    "new-height": canvas_h,
                    "offx": off_x,
                    "offy": off_y,
                },
            )

    _pdb_run(
        "gimp-xcf-save",
        {
            "run-mode": Gimp.RunMode.NONINTERACTIVE,
            "image": base,
            "file": Gio.File.new_for_path(xcf_path),
        },
    )
    _pdb_run(
        "file-png-export",
        {
            "run-mode": Gimp.RunMode.NONINTERACTIVE,
            "image": base,
            "file": Gio.File.new_for_path(png_path),
            "save-transparent": True,
        },
    )
    base.delete()


def main() -> None:
    build_from_job(_load_job())


if __name__ == "__main__":
    main()
else:
  # batch-interpreter exec(open(...).read()) leaves __name__ != "__main__"
    main()
