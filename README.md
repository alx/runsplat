# RunSplat

Convert drone or handheld video into a 3D Gaussian Splatting scene in one command.

```
MP4 video(s)
    │
    ▼
ffmpeg — extract ~150 frames
    │
    ▼
COLMAP — structure-from-motion (camera poses + sparse point cloud)
    │
    ▼
Brush — 3D Gaussian Splatting training
    │
    ▼
output.ply + output.splat
```

Results are visualised in a local Hugo website with an in-browser WebGL splat viewer.
The same pipeline is deployable as a serverless GPU endpoint on [RunPod Hub](https://www.runpod.io/console/hub).

---

## Prerequisites

| Tool | Install |
|------|---------|
| Python 3.10+ + [uv](https://docs.astral.sh/uv/) | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| [COLMAP](https://colmap.github.io/) | `sudo apt install colmap` / `brew install colmap` |
| [ffmpeg](https://ffmpeg.org/) | `sudo apt install ffmpeg` / `brew install ffmpeg` |
| [Hugo](https://gohugo.io/) | `sudo apt install hugo` / `brew install hugo` |
| Brush binary | see below |

### Getting the Brush binary

The Brush 3DGS trainer binary is not included in this repo (120 MB). Compile it once:

```bash
git clone https://github.com/ArthurBrussee/brush.git
cd brush
cargo build --release
cp target/release/brush_app /path/to/runsplat/binaries/brush_app_linux
```

Rust installation: https://rustup.rs

> **Docker / RunPod**: the binary is compiled automatically during `docker build` — no manual step needed.

---

## Quick start

```bash
# 1. Create a project and add your video(s)
mkdir -p projects/my-scene/input
cp my-video.mp4 projects/my-scene/input/

# 2. Run the full pipeline
uv run scripts/pipeline.py --project projects/my-scene --gpu

# 3. Browse results
cd site && hugo server
# Open http://localhost:1313
```

Multiple input videos are combined into a single reconstruction:

```bash
cp pass1.mp4 pass2.mp4 projects/my-scene/input/
uv run scripts/pipeline.py --project projects/my-scene --gpu
```

---

## CLI reference

```
uv run scripts/pipeline.py --project <dir> [options]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--project` | *(required)* | Project directory containing `input/` with MP4 files |
| `--steps` | `30000` | Brush training iterations |
| `--gpu` | off | Enable GPU for COLMAP feature extraction and matching |
| `--matching` | `sequential` | `sequential` (video) or `exhaustive` (unordered images) |
| `--from-step` | `frames` | Resume from: `frames` `colmap` `brush` `convert` `hugo` |

### Resuming from a step

```bash
# Re-run only Brush training and everything after
uv run scripts/pipeline.py --project projects/my-scene --from-step brush

# Re-convert PLY → SPLAT and regenerate site data only
uv run scripts/pipeline.py --project projects/my-scene --from-step convert
```

---

## Project folder structure

After a successful run:

```
projects/my-scene/
├── input/                   # Your original MP4 files
│   └── my-video.mp4
├── frames/                  # Extracted PNG frames (all videos combined)
├── colmap/
│   ├── database.db          # Feature/match database
│   ├── distorted/sparse/0/  # Raw COLMAP reconstruction
│   ├── images/              # Undistorted images
│   └── sparse/0/            # Undistorted sparse model (Brush input)
├── brush/
│   ├── export_005000.ply    # Intermediate exports
│   ├── export_010000.ply
│   ├── ...
│   ├── export_030000.ply    # Final export
│   └── export.ply           # Symlink → latest export
├── output.ply               # Symlink → brush/export.ply
├── output.splat             # Binary splat format for web viewer
└── metadata.json            # Project status and video list
```

---

## Hugo site

The pipeline automatically populates the Hugo site under `site/`. To view:

```bash
cd site && hugo server
```

- **Homepage** (`/`) — card list of all processed projects
- **Project page** (`/projects/<name>/`) — video player(s) on the left, interactive WebGL splat viewer on the right

The splat viewer is a self-hosted copy of [antimatter15/splat](https://github.com/antimatter15/splat) served from `site/static/viewer/`.

---

## RunPod Hub deployment

### How it works

The `handler.py` serverless handler:
1. Downloads video URL(s) from the job input
2. Runs the full pipeline (`scripts/pipeline.py`)
3. Returns the final `.ply` as a base64-encoded string

### API input

```json
{
  "input": {
    "video_url": "https://example.com/my-video.mp4",
    "steps": 30000
  }
}
```

Or multiple videos:

```json
{
  "input": {
    "video_urls": [
      "https://example.com/pass1.mp4",
      "https://example.com/pass2.mp4"
    ],
    "steps": 30000
  }
}
```

### API output

```json
{
  "ply_base64": "<base64-encoded PLY file>",
  "status": "done"
}
```

### Publishing to RunPod Hub

1. Push a new GitHub release (e.g. tag `v1.0.0`)
2. RunPod Hub detects the release, builds the Docker image, and runs the tests in `.runpod/tests.json`
3. After tests pass, submit for manual review on the [Hub page](https://www.runpod.io/console/hub)

The `Dockerfile` uses a multi-stage build: Brush is compiled from source in a Rust image, then copied into the lean CUDA runtime image. The binary is never committed to the repo.

Hub configuration is in `.runpod/hub.json`. Available presets: **Fast preview** (5k steps), **Standard quality** (30k steps), **High quality** (60k steps).

---

## Credits

- [Brush](https://github.com/ArthurBrussee/brush) — 3D Gaussian Splatting trainer
- [COLMAP](https://github.com/colmap/colmap) — Structure-from-Motion
- [antimatter15/splat](https://github.com/antimatter15/splat) — WebGL Gaussian splat viewer
- [skysplat_blender](https://github.com/kyjohnso/skysplat_blender) — Blender addon this pipeline is based on
