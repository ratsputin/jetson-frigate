# jetson-frigate
[Frigate](https://github.com/blakeblackshear/frigate) on [Jetson Orin NX](https://www.nvidia.com/en-us/autonomous-machines/embedded-systems/jetson-orin/) with ffmpeg 6.0 NVMPI patches for encoding/decoding hardware acceleration, docker build files and many more.

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

## Docker images
Once the build is complete, you should end up with the following images.  Note the size of the images.  This does not represent the total amount of space necessary to build this container, as intermediate images and caching consume considerable space as well.
```
REPOSITORY                                              TAG                       IMAGE ID       CREATED        SIZE
frigate-jetson-tensorrt                                 latest                    ************   26 hours ago   7.34GB
ratsputin/frigate-openvino                              2023.0.0-aarch64          ************   26 hours ago   15.4GB
ratsputin/ffmpeg                                        6.0-aarch64               ************   27 hours ago   4.42GB
ratsputin/tensorrt-wheel                                8.6.1-aarch64             ************   28 hours ago   940kB
ratsputin/tensorrt                                      8.6.1-CUDA-11.4-aarch64   ************   28 hours ago   13GB
ratsputin/onnx-wheel                                    1.14.0-aarch64            ************   28 hours ago   29.5MB
ratsputin/jetson-orin-nx-xavier-nx-devkit-ubuntu        focal-run                 ************   8 days ago     206MB
ratsputin/jetson-orin-nx-xavier-nx-devkit-ubuntu        focal-build               ************   8 days ago     11.1GB
```
The images serve the following purposes:
* `frigate-jetson-tensorrt:latest` - Docker image containing the fully-built Frigate system supporting the Jetson using TensorRT
* `ratsputin/frigate-openvino:2023.0.0-aarch64' - Intermediate image used to gather OpenVINO components and build necessary utilities
* `ratsputin/ffmpeg:6.0-aarch64` - Intermediate image used to build a static ffmpeg binary; useful for testing ffmpeg outside of Frigate
* `ratsputin/tensorrt-wheel:8.6.1-aarch64` - Intermediate image containing various Python 3.9 wheel files used by Frigate
* `ratsputin/tensorrt:8.6.1-CUDA-11.4-aarch64` - Build of TensorRT on the platform necessary during the Frigate build as well as to create models
* `ratsputin/onnx-wheel:1.14.0-aarch64` - Intermediate image containing a build of ONNX on the platform
* `ratsputin/jetson-orin-nx-xavier-nx-devkit-ubuntu:focal-run` - Custom version of the BalenaLib Ubuntu Focal distribution for the Jetson Orin - runtime only from my [repo](https://github.com/ratsputin/jetson-orin-nx-xavier-nx-devkit-ubuntu-focal)
* `ratsputin/jetson-orin-nx-xavier-nx-devkit-ubuntu:focal-build` - Custom version of the BalenaLib Ubuntu Focal distribution for the Jetson Orin - build image from my [repo](https://github.com/ratsputin/jetson-orin-nx-xavier-nx-devkit-ubuntu-focal)

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
## Making sure NVMPI is used
Adding the following to your config.yml file will tell Frigate to use the appropriate switches on ffmpeg to take advantage of the Jetson's capabilities
```
ffmpeg:
  hwaccel_args: -hwaccel_output_format yuv420p -c:v h264_nvmpi
```
## Using Vulkan instead of NVMPI
With release v0.1-alpha, Vulkan support in ffmpeg is supported.  Note that performance isn't as good and it's unclear whether full acceleration is being taken advantage of as CPU load is greater; however, it's possible it may be a workaround for the NVMPI issue with go2rtc.
```
ffmpeg:
  hwaccel_args: -init_hw_device "vulkan=vk:0" -hwaccel vulkan -hwaccel_output_format yuv420p
```


## TODO
* Explain how to build TRT model files using patches/tensorrt_models.sh
* Track support for nvmpi fix preventing go2rtc restreaming from working (https://github.com/jocover/jetson-ffmpeg/issues/113)
* Figure out how to train models to inference on Nvidia Jetson DLAs (https://medium.com/@reachmostafa.m/training-yolov4-to-inference-on-nvidia-dlas-8a493f89b091)
* Get additional HW acceleration working in ffmpeg to possibly work around the nvmpi issue with go2rtc (vulkan, cuda, cuvid).  Lacking libnvcuvid.so.1 for cuda/cuvid.  Possibly in Deepstream v6.2 (https://docs.nvidia.com/metropolis/deepstream/dev-guide/text/DS_Quickstart.html)
