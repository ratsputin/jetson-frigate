# syntax=docker/dockerfile:1.2

# https://askubuntu.com/questions/972516/debian-frontend-environment-variable
ARG DEBIAN_FRONTEND=noninteractive
ARG OPENVINO_BRANCH=2023.0.0
ARG PYTHON_VERSION=3.9
ARG FFMPEG_VERSION=6.0

FROM ratsputin/ffmpeg:${FFMPEG_VERSION}-aarch64 AS ffmpeg
FROM ratsputin/jetson-orin-nx-xavier-nx-devkit-ubuntu:focal-build AS base

ARG PYTHON_VERSION

# Set up proper Python version using Ubuntu update-alternatives.  Default auto is Python 3.9.
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.8 10 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 20 \
    && update-alternatives --set python3 "/usr/bin/python$PYTHON_VERSION"

FROM ratsputin/jetson-orin-nx-xavier-nx-devkit-ubuntu:focal-run AS slim-base

FROM slim-base AS wget
ARG DEBIAN_FRONTEND
RUN apt-get update \
    && apt-get install -y wget xz-utils \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /rootfs

FROM base AS nginx
ARG DEBIAN_FRONTEND

# bind /var/cache/apt to tmpfs to speed up nginx build
RUN --mount=type=tmpfs,target=/tmp --mount=type=tmpfs,target=/var/cache/apt \
    --mount=type=bind,source=docker/build_nginx.sh,target=/deps/build_nginx.sh \
    /deps/build_nginx.sh

FROM wget AS go2rtc
ARG TARGETARCH
WORKDIR /rootfs/usr/local/go2rtc/bin
RUN wget -qO go2rtc "https://github.com/AlexxIT/go2rtc/releases/download/v1.5.0/go2rtc_linux_$TARGETARCH" \
    && chmod +x go2rtc


####
#
# OpenVino Support
#
# 1. Download and convert a model from Intel's Public Open Model Zoo
# 2. Build libUSB without udev to handle NCS2 enumeration
#
####
# Download and Convert OpenVino model
FROM base AS ov-converter
ARG DEBIAN_FRONTEND
ARG OPENVINO_BRANCH

# Install OpenVino Runtime and Dev library
COPY --from=ratsputin/frigate-openvino:2023.0.0-aarch64 /opt/intel/openvino/tools/* /tmp
RUN cd /tmp \
    && wget https://bootstrap.pypa.io/get-pip.py \
    && python3 get-pip.py \
    && pip3 install openvino-dev==${OPENVINO_BRANCH} --find-links=/tmp \
    && pip3 install tensorflow-aarch64 \
    && pip3 install fastjsonschema

# Get OpenVino Model
RUN mkdir /models \
    && cd /models && omz_downloader --name ssdlite_mobilenet_v2 \
    && cd /models && omz_converter --name ssdlite_mobilenet_v2 --precision FP16


# libUSB - No Udev
FROM wget as libusb-build
ARG TARGETARCH
ARG DEBIAN_FRONTEND

# Build libUSB without udev.  Needed for Openvino NCS2 support
WORKDIR /opt
RUN apt-get update && apt-get install -y unzip build-essential automake libtool
RUN wget -q https://github.com/libusb/libusb/archive/v1.0.25.zip -O v1.0.25.zip && \
    unzip v1.0.25.zip && cd libusb-1.0.25 && \
    ./bootstrap.sh && \
    ./configure --disable-udev --enable-shared && \
    make -j $(nproc --all)
RUN apt-get update && \
    apt-get install -y --no-install-recommends libusb-1.0-0-dev && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /opt/libusb-1.0.25/libusb
RUN /bin/mkdir -p '/usr/local/lib' && \
    /bin/bash ../libtool  --mode=install /usr/bin/install -c libusb-1.0.la '/usr/local/lib' && \
    /bin/mkdir -p '/usr/local/include/libusb-1.0' && \
    /usr/bin/install -c -m 644 libusb.h '/usr/local/include/libusb-1.0' && \
    /bin/mkdir -p '/usr/local/lib/pkgconfig' && \
    cd  /opt/libusb-1.0.25/ && \
    /usr/bin/install -c -m 644 libusb-1.0.pc '/usr/local/lib/pkgconfig' && \
    ldconfig

FROM wget AS models

# Get model and labels
RUN wget -qO edgetpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess_edgetpu.tflite
RUN wget -qO cpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess.tflite
COPY labelmap.txt .
# Copy OpenVino model
COPY --from=ov-converter /models/public/ssdlite_mobilenet_v2/FP16 openvino-model
RUN wget -q https://github.com/openvinotoolkit/open_model_zoo/raw/master/data/dataset_classes/coco_91cl_bkgr.txt -O openvino-model/coco_91cl_bkgr.txt && \
    sed -i 's/truck/car/g' openvino-model/coco_91cl_bkgr.txt



FROM wget AS s6-overlay
ARG TARGETARCH
ENV TARGETARCH=${TARGETARCH}
RUN --mount=type=bind,source=docker/install_s6_overlay.sh,target=/deps/install_s6_overlay.sh \
    /deps/install_s6_overlay.sh


FROM base AS wheels
ARG DEBIAN_FRONTEND
ARG TARGETARCH
ARG PYTHON_VERSION

# Use a separate container to build wheels to prevent build dependencies in final image
RUN apt-get -qq update \
    && apt-get -qq install -y \
    apt-transport-https \
    gnupg \
    wget \
    && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 9165938D90FDDD2E \
    && echo "deb http://raspbian.raspberrypi.org/raspbian/ bullseye main contrib non-free rpi" | tee /etc/apt/sources.list.d/raspi.list \
    && apt-get -qq update \
    && apt-get -qq install -y \
    "python$PYTHON_VERSION-dev" \
    wget \
    # opencv dependencies
    build-essential cmake git pkg-config libgtk-3-dev \
    libavcodec-dev libavformat-dev libswscale-dev libv4l-dev \
    libxvidcore-dev libx264-dev libjpeg-dev libpng-dev libtiff-dev \
    gfortran openexr libatlas-base-dev libssl-dev\
    libtbb2 libtbb-dev libdc1394-22-dev libopenexr-dev \
    libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev \
    # scipy dependencies
    gcc gfortran libopenblas-dev liblapack-dev && \
    rm -rf /var/lib/apt/lists/*

RUN wget -q https://bootstrap.pypa.io/get-pip.py -O get-pip.py \
    && python3 get-pip.py

COPY requirements.txt /requirements.txt
RUN pip3 install -r requirements.txt

COPY requirements-wheels.txt /requirements-wheels.txt
RUN pip3 wheel --wheel-dir=/wheels -r requirements-wheels.txt

# Make this a separate target so it can be built/cached optionally
FROM wheels as trt-wheels
ARG DEBIAN_FRONTEND
ARG TARGETARCH

# Pick up tensorrt-8.6.1-cp39-none-linux_x86_64.whl from separately build image
RUN mkdir -p /trt-wheels
COPY --from=ratsputin/tensorrt-wheel:8.6.1-aarch64 /*.whl /trt-wheels

# Add TensorRT wheels to another folder
COPY requirements-jetson-tensorrt.txt /requirements-jetson-tensorrt.txt
RUN pip3 wheel --wheel-dir=/trt-wheels -r requirements-jetson-tensorrt.txt

# Collect deps in a single layer
FROM scratch AS deps-rootfs
COPY --from=nginx /usr/local/nginx/ /usr/local/nginx/
COPY --from=go2rtc /rootfs/ /
COPY --from=libusb-build /usr/local/lib /usr/local/lib
COPY --from=s6-overlay /rootfs/ /
COPY --from=models /rootfs/ /
COPY docker/rootfs/ /


# Frigate deps (ffmpeg, python, nginx, go2rtc, s6-overlay, etc)
FROM slim-base AS deps
ARG TARGETARCH
ARG PYTHON_VERSION

ARG DEBIAN_FRONTEND
# http://stackoverflow.com/questions/48162574/ddg#49462622
ARG APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=DontWarn

# https://github.com/NVIDIA/nvidia-docker/wiki/Installation-(Native-GPU-Support)
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES="compute,video,utility"

ENV PATH="/usr/lib/btbn-ffmpeg/bin:/usr/local/go2rtc/bin:/usr/local/nginx/sbin:${PATH}"

# Install dependencies
RUN apt-get -qq update \
    && apt install -y --no-install-recommends --no-install-suggests \
    wget \
    "python$PYTHON_VERSION" \
    python3-distutils \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.8 10 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 20 \
    && update-alternatives --set python3 "/usr/bin/python$PYTHON_VERSION"

RUN wget https://bootstrap.pypa.io/get-pip.py \
    && python3 get-pip.py

RUN --mount=type=bind,source=docker/install_deps.sh,target=/deps/install_deps.sh \
    /deps/install_deps.sh

RUN --mount=type=bind,from=wheels,source=/wheels,target=/deps/wheels \
    python3 --version; \
    pip3 --version; \
    pip3 install -U /deps/wheels/*.whl

COPY --from=ffmpeg /usr/local /usr/lib/btbn-ffmpeg

COPY --from=deps-rootfs / /

RUN ldconfig

EXPOSE 5000
EXPOSE 1935
EXPOSE 8554
EXPOSE 8555/tcp 8555/udp

# Configure logging to prepend timestamps, log to stdout, keep 0 archives and rotate on 10MB
ENV S6_LOGGING_SCRIPT="T 1 n0 s10000000 T"

ENTRYPOINT ["/init"]
CMD []

# Frigate deps with Node.js and NPM for devcontainer
FROM deps AS devcontainer

# Do not start the actual Frigate service on devcontainer as it will be started by VSCode
# But start a fake service for simulating the logs
COPY docker/fake_frigate_run /etc/s6-overlay/s6-rc.d/frigate/run

# Create symbolic link to the frigate source code, as go2rtc's create_config.sh uses it
RUN mkdir -p /opt/frigate \
    && ln -svf /workspace/frigate/frigate /opt/frigate/frigate

# Install Node 16
RUN apt-get update \
    && apt-get install wget -y \
    && wget -qO- https://deb.nodesource.com/setup_16.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g npm@9

WORKDIR /workspace/frigate

RUN apt-get update \
    && apt-get install make -y \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=bind,source=./requirements-dev.txt,target=/workspace/frigate/requirements-dev.txt \
    pip3 install -r requirements-dev.txt

CMD ["sleep", "infinity"]


# Frigate web build

FROM ratsputin/jetson-orin-nx-xavier-nx-devkit-ubuntu-node:16.19-focal-build AS web-build

WORKDIR /work
COPY web/package.json web/package-lock.json ./
RUN npm install

COPY web/ ./
RUN npm run build \
    && mv dist/BASE_PATH/monacoeditorwork/* dist/assets/ \
    && rm -rf dist/BASE_PATH

# Collect final files in a single layer
FROM scratch AS rootfs

WORKDIR /opt/frigate/
COPY frigate frigate/
COPY migrations migrations/
COPY --from=web-build /work/dist/ web/

# Frigate final container
FROM deps AS frigate

WORKDIR /opt/frigate/
COPY --from=rootfs / /

# Frigate w/ TensorRT Support as separate image
FROM frigate AS frigate-jetson-tensorrt

RUN --mount=type=bind,from=trt-wheels,source=/trt-wheels,target=/deps/trt-wheels \
    pip3 install -U /deps/trt-wheels/*.whl \
    && echo /usr/lib/btbn-ffmpeg/lib > /etc/ld.so.conf.d/ffmpeg.conf \
    && echo /usr/lib/aarch64-linux-gnu/tegra >> /etc/ld.so.conf.d/ffmpeg.conf \
    && ldconfig

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    libnvinfer8 \
    libnvonnxparsers8 \
    libnvparsers8 \
    libnvinfer-plugin8 \
    libcudla-11-4 \
    cuda-cudart-11-4 \
# FFMPEG dependencies \
    libgomp1 \
    libegl1 \
    && rm -rf /var/lib/apt/lists/*

# Dev Container w/ TRT
FROM devcontainer AS devcontainer-jetson-trt

RUN --mount=type=bind,from=trt-wheels,source=/trt-wheels,target=/deps/trt-wheels \
    pip3 install -U /deps/trt-wheels/*.whl \
    && echo /usr/lib/btbn-ffmpeg/lib > /etc/ld.so.conf.d/ffmpeg.conf \
    && echo /usr/lib/aarch64-linux-gnu/tegra >> /etc/ld.so.conf.d/ffmpeg.conf \
    && ldconfig

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    libnvinfer8 \
    libnvonnxparsers8 \
    libnvparsers8 \
    libnvinfer-plugin8 \
    libcudla-11-4 \
    cuda-cudart-11-4 \
# FFMPEG dependencies \
    libgomp1 \
    libegl1 \
    && rm -rf /var/lib/apt/lists/*

