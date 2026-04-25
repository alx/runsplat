# ── Stage 1: download pre-built Brush binary ──────────────────────────────────
FROM ubuntu:24.04 AS brush-builder

RUN apt-get update && apt-get install -y curl xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fL https://github.com/ArthurBrussee/brush/releases/download/v0.3.0/brush-app-x86_64-unknown-linux-gnu.tar.xz \
    -o /tmp/brush.tar.xz \
    && echo "4f0f9a8785d1951c62df26aae247c02c5bba32b00f40b06df4e1c9b867399e20  /tmp/brush.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/brush.tar.xz --strip-components=1 -C /usr/local/bin \
        brush-app-x86_64-unknown-linux-gnu/brush_app \
    && chmod +x /usr/local/bin/brush_app \
    && rm /tmp/brush.tar.xz

# ── Stage 2: runtime (COLMAP 4.0.3 + CUDA 12.9.1 already included) ───────────
FROM colmap/colmap:latest
ENV DEBIAN_FRONTEND=noninteractive
# graphics capability is required for Vulkan (used by brush/wgpu)
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics

RUN apt-get update && apt-get install -y \
    ffmpeg \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir --break-system-packages runpod numpy Pillow plyfile

WORKDIR /app
COPY --from=brush-builder /usr/local/bin/brush_app /app/binaries/brush_app_linux
COPY . /app

CMD ["python3", "-u", "handler.py"]
