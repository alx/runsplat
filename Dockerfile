# ── Pull compiled COLMAP from colmap-serverless ───────────────────────────────
FROM ghcr.io/alx/colmap-serverless:latest AS colmap-stage

# ── Pull compiled Brush from brush-serverless ─────────────────────────────────
FROM ghcr.io/alx/brush-serverless:latest AS brush-stage

# ── Runtime: layer on top of the COLMAP image (includes COLMAP + CUDA + deps) ─
FROM ghcr.io/alx/colmap-serverless:latest
ENV DEBIAN_FRONTEND=noninteractive
# graphics capability required for Vulkan (used by brush/wgpu)
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics

RUN apt-get update && apt-get install -y \
    xvfb libvulkan1 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /usr/share/vulkan/icd.d /etc/vulkan/icd.d

# Add Brush binary from brush-serverless image
COPY --from=brush-stage /app/binaries/brush_app_linux /app/binaries/brush_app_linux

RUN pip3 install --no-cache-dir --break-system-packages numpy Pillow plyfile runpod

WORKDIR /app
COPY . /app

CMD ["python3", "-u", "handler.py"]
