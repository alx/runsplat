# ── Stage 1: compile Brush from source ───────────────────────────────────────
FROM rust:1.93 AS brush-builder

RUN apt-get update && apt-get install -y \
    git pkg-config libssl-dev lld \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/ArthurBrussee/brush.git /brush
WORKDIR /brush
RUN RUSTFLAGS="-C link-arg=-fuse-ld=lld" cargo build --release -p brush-app --bin brush

# ── Stage 2: runtime ──────────────────────────────────────────────────────────
FROM nvidia/cuda:12.1.0-base-ubuntu22.04
ENV DEBIAN_FRONTEND=noninteractive
# graphics capability is required for Vulkan (used by brush/wgpu)
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics

RUN apt-get update && apt-get install -y \
    colmap \
    ffmpeg \
    python3 \
    python3-pip \
    libgl1 \
    libglib2.0-0 \
    libvulkan1 \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir runpod numpy Pillow plyfile

WORKDIR /app
COPY --from=brush-builder /brush/target/release/brush /app/binaries/brush_app_linux
COPY . /app

CMD ["python3", "-u", "handler.py"]
