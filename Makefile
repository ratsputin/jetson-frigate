default_target: local

COMMIT_HASH := $(shell git log -1 --pretty=format:"%h"|tail -1)
VERSION = 0.12.1
CURRENT_UID := $(shell id -u)
CURRENT_GID := $(shell id -g)
OPENVINO_BRANCH := 2023.0.0
TENSORFLOW_BRANCH := 2.12.0

version:
	echo 'VERSION = "$(VERSION)-$(COMMIT_HASH)"' > frigate/version.py

local: version jetson_ffmpeg jetson_openvino
	docker buildx build --target=frigate-jetson-tensorrt --tag frigate-jetson-tensorrt:latest --load .

jetson_ffmpeg:
	docker build --platform linux/arm64/v8 --tag blakeblackshear/frigate-ffmpeg:1.0.0-aarch64 --file ./jetson-frigate/docker/Dockerfile.ffmpeg.aarch64-jetson .

jetson_openvino:
	docker build --tag ratsputin/frigate-openvino:$(OPENVINO_BRANCH)-aarch64 --build-arg OPENVINO_BRANCH=$(OPENVINO_BRANCH) --build-arg TENSORFLOW_AARCH64_BRANCH=$(TENSORFLOW_BRANCH) --file ./jetson-frigate/docker/Dockerfile.openvino.aarch64-jetson .

build: version jetson_ffmpeg jetson_openvino
	docker buildx build --platform linux/arm64/v8 --target=frigate-jetson-tensorrt --tag ratsputin/frigate-jetson-tensorrt:$(VERSION)-$(COMMIT_HASH) .

push: build
	docker buildx build --push --platform linux/arm64/v8 --target=frigate-jetson-tensorrt --tag $(IMAGE_REPO):${GITHUB_REF_NAME}-$(COMMIT_HASH)-tensorrt .

run: local
	docker run --gpus=all --rm --publish=5000:5000 --volume=${PWD}/config/config.yml:/config/config.yml frigate-jetson-tensorrt:latest

run_tests: local
	docker run --gpus=all --rm --workdir=/opt/frigate --entrypoint= frigate-jetson-tensorrt:latest python3 -u -m unittest
	docker run --gpus=all --rm --workdir=/opt/frigate --entrypoint= frigate-jetson-tensorrt:latest python3 -u -m mypy --config-file frigate/mypy.ini frigate

.PHONY: run_tests
