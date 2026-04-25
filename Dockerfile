# ── Stage 1: compile Brush from source ───────────────────────────────────────
FROM rust:1.93 AS brush-builder

RUN apt-get update && apt-get install -y \
    git pkg-config libssl-dev lld \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/ArthurBrussee/brush.git /brush
WORKDIR /brush
RUN RUSTFLAGS="-C link-arg=-fuse-ld=lld" cargo build --release -p brush-app --bin brush

# ── Stage 2: build COLMAP with CUDA ───────────────────────────────────────────
FROM nvidia/cuda:12.6.3-devel-ubuntu24.04 AS colmap-builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    ccache cmake ninja-build build-essential \
    libboost-program-options-dev libboost-graph-dev libboost-system-dev \
    libeigen3-dev libopenimageio-dev openimageio-tools \
    libmetis-dev libgoogle-glog-dev libgtest-dev libgmock-dev \
    libsqlite3-dev libglew-dev \
    qt6-base-dev libqt6opengl6-dev libqt6openglwidgets6 libqt6svg6-dev \
    libcgal-dev libceres-dev libcurl4-openssl-dev libssl-dev \
    libmkl-full-dev \
    && rm -rf /var/lib/apt/lists/*

# Required by OpenImageIO's CMake config even when OpenCV support is unused
RUN mkdir -p /usr/include/opencv4

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 https://github.com/colmap/colmap.git /colmap
RUN cd /colmap && mkdir build && cd build && \
    cmake .. -GNinja \
        -DCMAKE_CUDA_ARCHITECTURES=all-major \
        -DCMAKE_INSTALL_PREFIX=/colmap-install \
        -DONNX_ENABLED=OFF \
        -DTESTS_ENABLED=OFF \
        -DBLA_VENDOR=Intel10_64lp \
    && ninja -j2 install

# ── Stage 3: runtime ──────────────────────────────────────────────────────────
FROM nvidia/cuda:12.6.3-base-ubuntu24.04
ENV DEBIAN_FRONTEND=noninteractive
# graphics capability is required for Vulkan (used by brush/wgpu)
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics

RUN apt-get update && apt-get install -y \
    ffmpeg \
    python3 \
    python3-pip \
    libgl1 \
    libglib2.0-0 \
    libvulkan1 \
    libboost-program-options1.83.0 \
    libopengl0 \
    libmetis5 \
    libceres4t64 \
    libopenimageio2.4t64 \
    libglew2.2 \
    libgoogle-glog0v6t64 \
    libqt6core6 \
    libqt6gui6 \
    libqt6widgets6 \
    libqt6openglwidgets6 \
    libqt6svg6 \
    libcurl4 \
    libssl3t64 \
    libmkl-locale \
    libmkl-intel-lp64 \
    libmkl-intel-thread \
    libmkl-core \
    && rm -rf /var/lib/apt/lists/*

COPY --from=colmap-builder /colmap-install/ /usr/local/

RUN pip3 install --no-cache-dir runpod numpy Pillow plyfile

WORKDIR /app
COPY --from=brush-builder /brush/target/release/brush /app/binaries/brush_app_linux
COPY . /app

CMD ["python3", "-u", "handler.py"]
