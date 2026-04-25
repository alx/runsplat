# RunSplat

Convert drone or handheld video into an interactive **3D Gaussian Splat** scene — viewable in any browser, no software required.

> Fly around and see your scene exactly as it is, from every angle, with real photographic textures. Not a point cloud. Not a basic mesh. The actual place.

- See your land as it really looks
- Easier to understand than technical maps
- Ideal for design, planning, and client presentations
- Take remote measurements without revisiting the site
- Track construction progress or erosion over time

Explore the ecosystem: [superspl.at](https://superspl.at/) — [antimatter15/splat WebGL viewer](https://antimatter15.com/splat/)

---

## Architecture

RunSplat is built as three independent serverless services:

```
┌─────────────────────────────────────────────────────────────┐
│  runsplat  (this repo)                                      │
│  Sequential orchestrator + result web viewer                │
│                                                             │
│  MP4 video(s)                                               │
│      │                                                      │
│      ▼  ffmpeg — extract frames                             │
│      │                                                      │
│      ▼  COLMAP 4.0.3 ── ── ── ── also available as         │
│      │                          colmap-serverless endpoint  │
│      ▼  Brush 3DGS training ─── also available as          │
│      │                          brush-serverless endpoint   │
│      ▼  PLY → SPLAT conversion                             │
│      │                                                      │
│      ▼  output.ply + output.splat                           │
└─────────────────────────────────────────────────────────────┘
```

| Repo | Role | RunPod Hub |
|------|------|-----------|
| **runsplat** (this repo) | Full pipeline + result viewer | Video → PLY |
| [colmap-serverless](https://github.com/alx/colmap-serverless) | COLMAP SfM only | Video → COLMAP workspace |
| [brush-serverless](https://github.com/alx/brush-serverless) | Brush 3DGS training only | COLMAP workspace → PLY |

The runsplat Docker image pulls compiled binaries from both upstream images — COLMAP and Brush are never rebuilt here:

```dockerfile
FROM ghcr.io/alx/colmap-serverless:latest AS colmap-stage
FROM ghcr.io/alx/brush-serverless:latest  AS brush-stage
FROM ghcr.io/alx/colmap-serverless:latest
COPY --from=brush-stage /app/binaries/brush_app_linux /app/binaries/brush_app_linux
```

---

## Why Gaussian Splatting?

Traditional photogrammetry outputs meshes or point clouds. 3D Gaussian Splatting lets you **fly through a real scene with photographic accuracy**, not an approximation:

- **See your land as it really looks** — every texture, every shadow, every surface
- **Easier to understand** — clients and decision-makers grasp it instantly
- **Design and planning** — walk through a space before it's built
- **Remote measurements** — measure distances and areas from the browser
- **No heavy software** — a URL is enough; WebGL runs everywhere
- **Change detection** — compare two captures of the same site over time

---

## Drone capture tips

The quality of your Gaussian Splat is determined by how well COLMAP can reconstruct camera poses, which depends on **diversity of viewing angles**. Circular flight patterns outperform grid surveys:

> *Unlike traditional grid or double-grid patterns, Circlegrammetry enables drones to fly in circular patterns, with the camera angled between 45° and 70° toward the center of each circle. This method captures images from more angles in fewer flights.*
>
> — [SPH Engineering, Circlegrammetry](https://www.sphengineering.com/news/sph-engineering-launches-circlegrammetry-a-game-changer-in-drone-photogrammetry)

More viewing angles → stronger COLMAP reconstruction → better Gaussian Splat.

---

## Quick start (local)

### Prerequisites

| Tool | Install |
|------|---------|
| Python 3.10+ + [uv](https://docs.astral.sh/uv/) | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| [COLMAP](https://colmap.github.io/) | `sudo apt install colmap` / `brew install colmap` |
| [ffmpeg](https://ffmpeg.org/) | `sudo apt install ffmpeg` / `brew install ffmpeg` |
| [Hugo](https://gohugo.io/) | `sudo apt install hugo` / `brew install hugo` |
| Brush binary | see below |

### Getting the Brush binary

Compile from source (requires [Rust](https://rustup.rs)):

```bash
git clone https://github.com/ArthurBrussee/brush.git
cd brush
cargo build --release -p brush-app --bin brush_app
cp target/release/brush_app /path/to/runsplat/binaries/brush_app_linux
```

> **Docker / RunPod:** both binaries are compiled automatically during image build — no manual step needed.

### Run the pipeline

```bash
# 1. Create a project and add your video(s)
mkdir -p projects/my-scene/input
cp drone-flight.mp4 projects/my-scene/input/

# 2. Run the full pipeline
uv run scripts/pipeline.py --project projects/my-scene --gpu

# 3. View results
cd site && hugo server
# Open http://localhost:1313
```

Multiple input videos are combined into a single reconstruction:

```bash
cp pass-north.mp4 pass-south.mp4 projects/my-scene/input/
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

# Re-convert PLY → SPLAT only
uv run scripts/pipeline.py --project projects/my-scene --from-step convert
```

---

## Project folder structure

```
projects/my-scene/
├── input/                   # Your original MP4 files
├── frames/                  # Extracted PNG frames
├── colmap/
│   ├── database.db          # Feature/match database
│   ├── images/              # Undistorted frames (Brush input)
│   └── sparse/0/            # Camera poses + sparse point cloud
├── brush/
│   ├── export_005000.ply    # Intermediate checkpoints
│   ├── export_030000.ply    # Final export
│   └── export.ply           # Symlink → latest export
├── output.ply               # Symlink → brush/export.ply
├── output.splat             # Web-optimised binary for viewer
└── metadata.json
```

---

## Result viewer

The pipeline auto-populates a Hugo site under `site/` with an in-browser WebGL splat viewer:

```bash
cd site && hugo server
# http://localhost:1313
```

- **Homepage** — card list of all processed projects
- **Project page** — video player(s) on the left, interactive 3D viewer on the right

The viewer is a self-hosted copy of [antimatter15/splat](https://github.com/antimatter15/splat) — no external dependency, no plugin, pure WebGL 2.0.

---

## RunPod Hub

### Full pipeline endpoint (this repo)

One API call runs the entire pipeline: download → frames → COLMAP → Brush → PLY.

**Input:**

```json
{
  "input": {
    "video_url": "https://example.com/drone-flight.mp4",
    "steps": 30000
  }
}
```

Or multiple videos:

```json
{
  "input": {
    "video_urls": [
      "https://example.com/pass-north.mp4",
      "https://example.com/pass-south.mp4"
    ],
    "steps": 30000
  }
}
```

**Output:**

```json
{
  "ply_base64": "<base64 PLY file>",
  "status": "done"
}
```

Presets: **Fast preview** (5k steps, ~5 min), **Standard quality** (30k, ~20 min), **High quality** (60k, ~40 min).

### Separate endpoints

Use [colmap-serverless](https://github.com/alx/colmap-serverless) and [brush-serverless](https://github.com/alx/brush-serverless) independently when you need finer control — for example, running COLMAP once and experimenting with different Brush training parameters.

---

## Docker

### Build and test

The runsplat image layers on top of the two upstream images. Both must be published to GHCR before building:

```bash
# Build
docker build -t runsplat:local .

# Test full pipeline
./scripts/test_local.sh

# Test COLMAP image only (requires ~/code/colmap-serverless)
./scripts/test_local_colmap.sh

# Test Brush image only (requires ~/code/brush-serverless)
./scripts/test_local_brush.sh
```

### Publishing

1. Publish `colmap-serverless` and `brush-serverless` images to GHCR first
2. Build and test `runsplat:local` locally
3. `gh release create v1.0.0 --generate-notes`
4. RunPod Hub builds the image and runs `.runpod/tests.json`

---

## Marketing site

A Hugo marketing site lives at `docs/frontmarket/` and is deployed to GitHub Pages on every push:

```bash
cd docs/frontmarket && hugo server
# http://localhost:1313
```

Live at: `https://alx.github.io/runsplat/`

---

## Credits

- [Brush](https://github.com/ArthurBrussee/brush) — Arthur Brussee, 3DGS trainer
- [COLMAP](https://github.com/colmap/colmap) — Schönberger & Frahm, Structure-from-Motion
- [antimatter15/splat](https://github.com/antimatter15/splat) — Kevin Kwok, WebGL viewer
- [superspl.at](https://superspl.at/) — The Home for 3D Gaussian Splatting
- [SPH Engineering](https://www.sphengineering.com/news/sph-engineering-launches-circlegrammetry-a-game-changer-in-drone-photogrammetry) — Circlegrammetry capture technique
- [skysplat_blender](https://github.com/kyjohnso/skysplat_blender) — Blender addon this pipeline is based on
