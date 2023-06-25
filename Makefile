default_target: jetson_frigate

COMMIT_HASH := $(shell git log -1 --pretty=format:"%h"|tail -1)

version:
	echo "VERSION='0.8.4-$(COMMIT_HASH)'" > frigate/version.py

jetson_ffmpeg:
	docker build --platform linux/arm64/v8 --tag blakeblackshear/frigate-ffmpeg:1.0.0-aarch64 --file docker/Dockerfile.ffmpeg.aarch64-jetson .

OPENVINO_BRANCH := 2023.0.0
TENSORFLOW_BRANCH := 2.12.0

jetson_openvino:
	docker build --tag ratsputin/frigate-openvino:$(OPENVINO_BRANCH)-aarch64 --build-arg OPENVINO_BRANCH=$(OPENVINO_BRANCH) --build-arg TENSORFLOW_AARCH64_BRANCH=$(TENSORFLOW_BRANCH) --file docker/Dockerfile.openvino.aarch64-jetson .

jetson_frigate: version web
	docker build --tag frigate-base --build-arg ARCH=aarch64 --build-arg FFMPEG_VERSION=1.0 --build-arg WHEELS_VERSION=1.0.3 --file docker/Dockerfile.base .
	docker build --tag frigate --file docker/Dockerfile.aarch64 .

jetson_wheels:
	docker build --tag blakeblackshear/frigate-wheels:1.0.3-aarch64 --file docker/Dockerfile.wheels.aarch64-jetson .

clean:
	docker container prune
	docker image prune -a
	docker volume prune

.PHONY: web
