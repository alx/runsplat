import base64
import os
import subprocess
import tempfile
import urllib.request
from collections import deque
from pathlib import Path

import runpod


def handler(event):
    inp = event["input"]

    # Accept a single video_url or a list via video_urls
    raw = inp.get("video_urls") or inp.get("video_url")
    if not raw:
        return {"error": "Provide video_url (string) or video_urls (list of strings)"}
    video_urls = raw if isinstance(raw, list) else [raw]

    # Job input takes priority over env vars (set via RunPod Hub config)
    steps = int(inp.get("steps") or os.environ.get("TRAINING_STEPS") or 30000)
    matching = inp.get("matching") or os.environ.get("MATCHING_TYPE") or "sequential"
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
            "--matching", matching,
        ]
        if gpu:
            cmd.append("--gpu")

        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        tail = deque(maxlen=100)
        for line in proc.stdout or []:
            print(line, end="", flush=True)
            tail.append(line)
        proc.wait()

        if proc.returncode != 0:
            return {"error": f"Pipeline failed (exit {proc.returncode}):\n{''.join(tail)}"}

        output_ply = project_dir / "output.ply"
        resolved = output_ply.resolve()
        with open(resolved, "rb") as f:
            ply_b64 = base64.b64encode(f.read()).decode()

    return {"ply_base64": ply_b64, "status": "done"}


runpod.serverless.start({"handler": handler})
