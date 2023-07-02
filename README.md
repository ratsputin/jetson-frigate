# jetson-frigate
[Frigate](https://github.com/blakeblackshear/frigate) on [Jetson Nano](https://developer.nvidia.com/embedded/jetson-nano-developer-kit) with ffmpeg 6.0 NVMPI patches for encoding/decoding hardware acceleration, docker build files and many more.

The current version does not support go2rtc nor coral acceleration.  The former due to a bug in the nvmpi support that precludes ffmpeg from decoding some RTSP streams.  The latter as it's unnecessary due to TensorRT being leveraged for object detection.

# Install

## Enable nvidia container runtime by default
You need use nvidia-container-runtime as explained in docs: "It is also the only way to have GPU access during docker build".
```
sudo apt-get install nvidia-container-runtime
```
Edit/create the **/etc/docker/daemon.json** with content:
```
{
    "runtimes": {
        "nvidia": {
            "path": "/usr/bin/nvidia-container-runtime",
            "runtimeArgs": []
         } 
    },
    "default-runtime": "nvidia" 
}
```

Restart docker daemon:

```
sudo systemctl restart docker
```
## Download frigate

```
git clone https://github.com/blakeblackshear/frigate.git -b v0.12.1 --depth=1
cd frigate
```

## Download docker build files and patch Frigate

```
git clone https://github.com/ratsputin/jetson-frigate.git
cd jetson-frigate
make patch
```

## Build ffmpeg and frigate
```
cd ..
make local
```
**Note**: a complete build takes close to three hours and significant resources as far as disk space, CPU and memory.  This has only been tested on a 16GB Jetson Orin NX with a 1TB M.2 SSD.

Once the build completes, you will have a `frigate-jetson-tensorrt:latest` docker image.

## Running
I suggest creating a docker compose file similar to the one below.  Note, in the below example, configuration files and such are stored in /srv/frigate.  It will be necessary to create the appropriate configuration file and directory structure as explained in the Frigate documentation.

Additionally, in order for object detection to work, the models will need to be created using the steps described in the Frigate documentation covering the [topic](https://docs.frigate.video/configuration/detectors/#nvidia-tensorrt-detector), but using the provided `patches/tensorrt_models.sh` and the generated docker image `ratsputin/tensorrt:8.6.1-CUDA-11.4-aarch64` instead of `nvcr.io/nvidia/tensorrt:22.07-py3` in the commands provided in the documentation.
```
version: "3.9"
services:
  frigate:
    container_name: frigate
    privileged: true
    restart: unless-stopped
    image: frigate-jetson-tensorrt:latest
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ['0']
              capabilities: [gpu]
    shm_size: "512mb"
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /srv/frigate/config:/config
      - /srv/frigate/storage:/media/frigate
      - /srv/frigate/trt-models:/trt-models
      - type: tmpfs
        target: /tmp/cache
        tmpfs:
          size: 1g
    ports:
      - "5000:5000"
      - "8554:8554"
      - "8555:8555/tcp"
      - "8555:8555/udp"
```

## TODO
* Explain how to build TRT model files using patches/tensorrt_models.sh
* Track support for nvmpi fix preventing go2rtc restreaming from working (https://github.com/jocover/jetson-ffmpeg/issues/113)
