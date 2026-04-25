#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "Pillow", "plyfile"]
# ///

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
SITE_DIR = REPO_ROOT / "site"

_LFS_MARKER = b"version https://git-lfs.github.com"


def find_brush_binary() -> Path:
    candidates = [
        REPO_ROOT / "binaries/brush_app_linux",
        Path.home() / "projects/brush/target/release/brush",
        Path("/usr/local/bin/brush"),
    ]
    for p in candidates:
        if not p.exists():
            continue
        with open(p, "rb") as f:
            if f.read(64).startswith(_LFS_MARKER):
                continue
        if os.access(p, os.X_OK):
            return p
    raise FileNotFoundError(
        "brush binary not found or is a Git LFS stub.\n"
        "Compile it with:\n"
        "  git clone https://github.com/ArthurBrussee/brush.git\n"
        "  cd brush && cargo build --release -p brush-app --bin brush\n"
        f"  cp target/release/brush {REPO_ROOT}/binaries/brush_app_linux"
    )


from convert import process_ply_to_splat, save_splat_file


def run(cmd: list, **kwargs):
    print(f"+ {' '.join(str(c) for c in cmd)}", flush=True)
    subprocess.run(cmd, check=True, **kwargs)


def get_frame_count(mp4_path: Path) -> int:
    result = subprocess.run(
        [
            "ffprobe", "-v", "quiet", "-select_streams", "v:0",
            "-count_packets", "-show_entries", "stream=nb_read_packets",
            "-of", "csv=p=0", str(mp4_path),
        ],
        capture_output=True, text=True, check=True,
    )
    return int(result.stdout.strip())


def detect_colmap_gpu_flags() -> tuple[str, str]:
    try:
        result = subprocess.run(
            ["colmap", "feature_extractor", "--help"],
            capture_output=True, text=True, timeout=10,
        )
        if "FeatureExtraction.use_gpu" in result.stdout + result.stderr:
            return "FeatureExtraction.use_gpu", "FeatureMatching.use_gpu"
    except Exception:
        pass
    return "SiftExtraction.use_gpu", "SiftMatching.use_gpu"


def extract_frames(mp4_path: Path, frames_dir: Path, step: int, prefix: str):
    frames_dir.mkdir(parents=True, exist_ok=True)
    run([
        "ffmpeg", "-i", str(mp4_path),
        "-vf", f"select=not(mod(n\\,{step}))",
        "-vsync", "vfr",
        str(frames_dir / f"{prefix}_frame_%04d.png"),
    ])


def run_colmap(
    project_dir: Path, use_gpu: bool, matching: str,
    feature_flag: str, matching_flag: str,
):
    gpu_val = "1" if use_gpu else "0"
    colmap_dir = project_dir / "colmap"
    frames_dir = project_dir / "frames"
    (colmap_dir / "distorted" / "sparse").mkdir(parents=True, exist_ok=True)
    database = colmap_dir / "database.db"
    colmap_env = {**os.environ, "QT_QPA_PLATFORM": "offscreen"}

    run([
        "colmap", "feature_extractor",
        "--database_path", str(database),
        "--image_path", str(frames_dir),
        "--ImageReader.single_camera", "1",
        "--ImageReader.camera_model", "SIMPLE_RADIAL",
        f"--{feature_flag}", gpu_val,
    ], env=colmap_env)

    matcher = "sequential_matcher" if matching == "sequential" else "exhaustive_matcher"
    run([
        "colmap", matcher,
        "--database_path", str(database),
        f"--{matching_flag}", gpu_val,
        *(["--SequentialMatching.overlap", "10"] if matching == "sequential" else []),
    ], env=colmap_env)

    run([
        "colmap", "mapper",
        "--database_path", str(database),
        "--image_path", str(frames_dir),
        "--output_path", str(colmap_dir / "distorted" / "sparse"),
        "--Mapper.ba_global_function_tolerance=0.000001",
    ], env=colmap_env)

    sparse_0 = colmap_dir / "distorted" / "sparse" / "0"
    if not sparse_0.exists():
        found = sorted((colmap_dir / "distorted" / "sparse").glob("*"))
        print(
            f"Error: COLMAP mapper produced no reconstruction (sparse/0 missing).\n"
            f"  Expected: {sparse_0}\n"
            f"  Found: {[p.name for p in found] or 'nothing'}\n"
            f"  Too few inlier feature matches — try a slower video or --matching exhaustive.",
            file=sys.stderr,
        )
        sys.exit(1)

    run([
        "colmap", "image_undistorter",
        "--image_path", str(frames_dir),
        "--input_path", str(sparse_0),
        "--output_path", str(colmap_dir),
        "--output_type", "COLMAP",
    ], env=colmap_env)


def run_brush(project_dir: Path, steps: int):
    brush_bin = find_brush_binary()
    print(f"Using brush binary: {brush_bin}", flush=True)
    colmap_dir = project_dir / "colmap"
    brush_dir = project_dir / "brush"
    brush_dir.mkdir(parents=True, exist_ok=True)
    export_name = f"export_{steps:06d}.ply"
    run([
        "xvfb-run", "-a",
        str(brush_bin),
        str(colmap_dir),
        "--export-path", str(brush_dir),
        "--export-name", export_name,
        "--total-steps", str(steps),
        "--eval-every", "1000",
        "--export-every", "5000",
    ])
    _normalise_brush_exports(brush_dir, export_name)


def _normalise_brush_exports(brush_dir: Path, expected_name: str):
    stem = Path(expected_name).stem
    bare = brush_dir / stem
    if bare.exists() and not bare.suffix:
        bare.rename(brush_dir / f"{stem}.ply")

    plys = sorted(brush_dir.glob("export_*.ply"))
    if not plys:
        return
    latest = plys[-1]
    link = brush_dir / "export.ply"
    if link.is_symlink() or link.exists():
        link.unlink()
    link.symlink_to(latest.name)
    print(f"export.ply → {latest.name}", flush=True)


def convert_to_splat(project_dir: Path) -> Path:
    brush_dir = project_dir / "brush"
    link = brush_dir / "export.ply"
    if link.is_symlink():
        final_ply = link.resolve()
    else:
        plys = sorted(brush_dir.glob("export_*.ply"))
        if not plys:
            raise FileNotFoundError(f"No PLY exports found in {brush_dir}")
        final_ply = plys[-1]

    output_ply = project_dir / "output.ply"
    if output_ply.is_symlink() or output_ply.exists():
        output_ply.unlink()
    output_ply.symlink_to(final_ply)

    output_splat = project_dir / "output.splat"
    print(f"Converting {final_ply.name} → output.splat", flush=True)
    save_splat_file(process_ply_to_splat(str(final_ply)), str(output_splat))
    return output_splat


def update_hugo(project_dir: Path, videos: list[str]):
    name = project_dir.name
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    (project_dir / "metadata.json").write_text(
        json.dumps({"name": name, "status": "done", "videos": videos, "created_at": now}, indent=2)
    )

    content_dir = SITE_DIR / "content" / "projects"
    content_dir.mkdir(parents=True, exist_ok=True)
    videos_yaml = "\n".join(f'  - "{v}"' for v in videos)
    (content_dir / f"{name}.md").write_text(
        f'---\ntitle: "{name}"\ndate: "{now}"\nstatus: "done"\nvideos:\n{videos_yaml}\n---\n'
    )

    static_input = SITE_DIR / "static" / "projects" / name / "input"
    static_input.mkdir(parents=True, exist_ok=True)

    for video in videos:
        dst = static_input / video
        if dst.is_symlink() or dst.exists():
            dst.unlink()
        dst.symlink_to((project_dir / "input" / video).resolve())

    splat_dst = SITE_DIR / "static" / "projects" / name / "output.splat"
    if splat_dst.is_symlink() or splat_dst.exists():
        splat_dst.unlink()
    splat_dst.symlink_to((project_dir / "output.splat").resolve())


def main():
    parser = argparse.ArgumentParser(description="RunSplat — MP4s → 3DGS PLY")
    parser.add_argument("--project", required=True, type=Path,
                        help="Project directory containing an input/ subfolder with MP4 files")
    parser.add_argument("--steps", type=int, default=30000,
                        help="Brush training steps (default: 30000)")
    parser.add_argument("--gpu", action="store_true",
                        help="Enable GPU acceleration for COLMAP")
    parser.add_argument("--matching", choices=["sequential", "exhaustive"],
                        default="sequential",
                        help="COLMAP feature matching strategy (default: sequential)")
    parser.add_argument("--from-step",
                        choices=["frames", "colmap", "brush", "convert", "hugo"],
                        default="frames",
                        help="Resume from this step, skipping earlier ones (default: frames)")
    args = parser.parse_args()

    project_dir = args.project.resolve()
    input_dir = project_dir / "input"

    if not input_dir.exists():
        print(f"Error: {input_dir} not found. Create it and place MP4 files inside.", file=sys.stderr)
        sys.exit(1)

    mp4s = sorted(input_dir.glob("*.mp4"))
    if not mp4s:
        print(f"Error: No .mp4 files found in {input_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"Project: {project_dir.name}", flush=True)
    print(f"Videos: {[f.name for f in mp4s]}", flush=True)

    pipeline_steps = ["frames", "colmap", "brush", "convert", "hugo"]
    start = pipeline_steps.index(args.from_step)
    feature_flag, matching_flag = "SiftExtraction.use_gpu", "SiftMatching.use_gpu"

    if start <= pipeline_steps.index("frames"):
        feature_flag, matching_flag = detect_colmap_gpu_flags()
        print(f"COLMAP GPU flags: {feature_flag} / {matching_flag}", flush=True)
        target_per_video = max(50, 150 // len(mp4s))
        frames_dir = project_dir / "frames"
        for mp4 in mp4s:
            total = get_frame_count(mp4)
            step = max(1, total // target_per_video)
            print(f"\n[frames] {mp4.name}: {total} total, extracting every {step}th frame", flush=True)
            extract_frames(mp4, frames_dir, step, mp4.stem)

    if start <= pipeline_steps.index("colmap"):
        if start > pipeline_steps.index("frames"):
            feature_flag, matching_flag = detect_colmap_gpu_flags()
        print("\n[colmap] Running COLMAP reconstruction...", flush=True)
        run_colmap(project_dir, args.gpu, args.matching, feature_flag, matching_flag)

    if start <= pipeline_steps.index("brush"):
        print("\n[brush] Running Brush 3DGS training...", flush=True)
        run_brush(project_dir, args.steps)

    if start <= pipeline_steps.index("convert"):
        print("\n[convert] Converting PLY → SPLAT...", flush=True)
        convert_to_splat(project_dir)

    if start <= pipeline_steps.index("hugo"):
        print("\n[hugo] Updating site data...", flush=True)
        update_hugo(project_dir, [f.name for f in mp4s])

    print(f"\nDone! Output: {project_dir / 'output.ply'}", flush=True)


if __name__ == "__main__":
    main()
