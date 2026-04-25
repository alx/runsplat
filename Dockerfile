# ── Stage 1: compile Brush from source ───────────────────────────────────────
FROM rust:1.78-slim AS brush-builder

RUN apt-get update && apt-get install -y \
    git pkg-config libssl-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/ArthurBrussee/brush.git /brush
WORKDIR /brush
RUN cargo build --release

# ── Stage 2: runtime ──────────────────────────────────────────────────────────
FROM nvidia/cuda:12.1.0-base-ubuntu22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    colmap \
    ffmpeg \
    python3 \
    python3-pip \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir runpod numpy Pillow plyfile

WORKDIR /app
COPY --from=brush-builder /brush/target/release/brush_app /app/binaries/brush_app_linux
COPY . /app

CMD ["python3", "-u", "handler.py"]
