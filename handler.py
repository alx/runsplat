import base64
import subprocess
import tempfile
import urllib.request
from pathlib import Path

import runpod


def handler(event):
    inp = event["input"]

    # Accept a single video_url or a list via video_urls
    raw = inp.get("video_urls") or inp.get("video_url")
    if not raw:
        return {"error": "Provide video_url (string) or video_urls (list of strings)"}
    video_urls = raw if isinstance(raw, list) else [raw]

    steps = int(inp.get("steps", 30000))
    gpu = bool(inp.get("gpu", True))

    with tempfile.TemporaryDirectory() as tmp:
        project_dir = Path(tmp) / "project"
        input_dir = project_dir / "input"
        input_dir.mkdir(parents=True)

        for i, url in enumerate(video_urls):
            dest = input_dir / f"video_{i:02d}.mp4"
            print(f"Downloading {url} → {dest.name}", flush=True)
            urllib.request.urlretrieve(url, dest)

        cmd = [
            "python3", str(Path(__file__).parent / "scripts" / "pipeline.py"),
            "--project", str(project_dir),
            "--steps", str(steps),
        ]
        if gpu:
            cmd.append("--gpu")

        result = subprocess.run(cmd, stderr=subprocess.PIPE, text=True)
        if result.returncode != 0:
            return {"error": f"Pipeline failed (exit {result.returncode}):\n{result.stderr[-3000:]}"}

        output_ply = project_dir / "output.ply"
        resolved = output_ply.resolve()
        with open(resolved, "rb") as f:
            ply_b64 = base64.b64encode(f.read()).decode()

    return {"ply_base64": ply_b64, "status": "done"}


runpod.serverless.start({"handler": handler})
