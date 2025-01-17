default_target: local

COMMIT_HASH := $(shell git log -1 --pretty=format:"%h"|tail -1)
VERSION = 0.12.1
CURRENT_UID := $(shell id -u)
CURRENT_GID := $(shell id -g)
OPENVINO_BRANCH = 2023.0.0
TENSORFLOW_BRANCH = 2.12.0
PYTHON_VERSION = 3.9
FFMPEG_VERSION = 6.0

patch:
	echo "Patching Frigate for NVIDIA Jetson support"
	cp Makefile patches/docker-compose.yml patches/Dockerfile patches/requirements-jetson-tensorrt.txt patches/requirements-wheels.txt ../
	cp patches/docker/install_deps.sh ../docker/

version:
	echo 'VERSION = "$(VERSION)-$(COMMIT_HASH)"' > frigate/version.py

local: version jetson_trt_wheel jetson_ffmpeg jetson_openvino
	docker buildx build --target=frigate-jetson-tensorrt --tag frigate-jetson-tensorrt:latest --load .

jetson_onnx: ./jetson-frigate/docker/Dockerfile.onnx-1.14.0.aarch64-jetson
	docker buildx build --platform linux/arm64/v8 --tag ratsputin/onnx-wheel:1.14.0-aarch64 --file ./jetson-frigate/docker/Dockerfile.onnx-1.14.0.aarch64-jetson .

jetson_tensorrt: ./jetson-frigate/docker/Dockerfile.tensorrt-8.6.1.aarch64-jetson jetson_onnx
	docker buildx build --platform linux/arm64/v8 --tag ratsputin/tensorrt:8.6.1-CUDA-11.4-aarch64 --target=tensorrt-python --file ./jetson-frigate/docker/Dockerfile.tensorrt-8.6.1.aarch64-jetson .

jetson_trt_wheel: ./jetson-frigate/docker/Dockerfile.tensorrt-8.6.1.aarch64-jetson jetson_tensorrt
	docker buildx build --platform linux/arm64/v8 --tag ratsputin/tensorrt-wheel:8.6.1-aarch64 --file ./jetson-frigate/docker/Dockerfile.tensorrt-8.6.1.aarch64-jetson .

jetson_ffmpeg: ./jetson-frigate/docker/Dockerfile.ffmpeg-$(FFMPEG_VERSION).aarch64-jetson
	docker buildx build --platform linux/arm64/v8 --tag ratsputin/ffmpeg:$(FFMPEG_VERSION)-aarch64 --file ./jetson-frigate/docker/Dockerfile.ffmpeg-$(FFMPEG_VERSION).aarch64-jetson .

jetson_openvino: ./jetson-frigate/docker/Dockerfile.openvino.aarch64-jetson
	docker buildx build --tag ratsputin/frigate-openvino:$(OPENVINO_BRANCH)-aarch64 --build-arg OPENVINO_BRANCH=$(OPENVINO_BRANCH) --build-arg TENSORFLOW_AARCH64_BRANCH=$(TENSORFLOW_BRANCH) --build-arg PYTHON_VERSION=$(PYTHON_VERSION) --file ./jetson-frigate/docker/Dockerfile.openvino.aarch64-jetson .

build: version jetson_trt_wheel jetson_ffmpeg jetson_openvino
	docker buildx build --platform linux/arm64/v8 --target=frigate-jetson-tensorrt --build-arg OPENVINO_BRANCH=$(OPENVINO_BRANCH) --build-arg PYTHON_VERSION=$(PYTHON_VERSION) --tag ratsputin/frigate-jetson-tensorrt:$(VERSION)-$(COMMIT_HASH) .

push: build
	docker buildx build --push --platform linux/arm64/v8 --target=frigate-jetson-tensorrt --build-arg PYTHON_VERSION=$(PYTHON_VERSION) --tag $(IMAGE_REPO):${GITHUB_REF_NAME}-$(COMMIT_HASH)-tensorrt .

run: local
	docker run --gpus=all --rm --publish=5000:5000 --volume=${PWD}/config/config.yml:/config/config.yml frigate-jetson-tensorrt:latest

run_tests: local
	docker run --gpus=all --rm --workdir=/opt/frigate --entrypoint= frigate-jetson-tensorrt:latest python3 -u -m unittest
	docker run --gpus=all --rm --workdir=/opt/frigate --entrypoint= frigate-jetson-tensorrt:latest python3 -u -m mypy --config-file frigate/mypy.ini frigate

.PHONY: run_tests
