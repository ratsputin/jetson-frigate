# jetson-frigate
[Frigate](https://github.com/blakeblackshear/frigate) 0.12.1-ab50d0b on [Jetson Orin NX](https://www.nvidia.com/en-us/autonomous-machines/embedded-systems/jetson-orin/) with ffmpeg 6.0 NVMPI patches for encoding/decoding hardware acceleration.  The resultant build includes images with a full-featured ffmpeg build (see Dockerfile for details), a native Jetson CUDA 11.4 version of TensorRT, and the related Python wheels to support it.  Note the OpenVINO container is built as part of the process, but only for the tools to download the models from Intel; OpenVINO is specifically for Intel processors.

The current version does not currently support coral acceleration.  This shouldn't present a problem as TensorRT is being leveraged for object detection.

# Install

## Enable nvidia container runtime by default
You need use nvidia-container-runtime as explained in docs: "It is also the only way to have GPU access during docker build".
```
sudo apt-get install nvidia-container-runtime
```
Edit/create the `/etc/docker/daemon.json` with content:
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

# Running
I suggest creating a docker compose file similar to the one below.  Note, in the below example, configuration files and such are stored in /srv/frigate.  It will be necessary to create the appropriate configuration file and directory structure as explained in the Frigate documentation.

Additionally, in order for object detection to work, the models will need to be created using the steps described in the Frigate documentation covering the [topic](https://docs.frigate.video/configuration/detectors/#nvidia-tensorrt-detector), but using the provided `patches/tensorrt_models.sh` and the generated docker image `ratsputin/tensorrt:8.6.1-CUDA-11.4-aarch64` instead of `nvcr.io/nvidia/tensorrt:22.07-py3` in the commands provided in the documentation.  Note that the models *must* be created using *your* GPU or an identical one to be able to be used (they're basically compiled specifically for the GPU).  This is why they cannot be packaged with the sources.
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
## Generating Jetson TRT Models
The instructions provided in the [documentation](https://docs.frigate.video/configuration/detectors/#generate-models) need to be modified slightly to work correctly on the Jetson platform.  An updated version of `tensorrt_models.sh` has been provided in the `jetson-frigate/patches` directory.  In addition to using it, the provided `ratsputin/tensorrt:8.6.1-CUDA-11.4-aarch64` docker image must be used to leverage the Jetson's GPU and generate usable models.
To generate the models, use the following as an example.  In this case, Frigate has been extracted to `~/frigate`.  The models will be generated in `/tmp/trt-models`.
```
cd /tmp
mkdir trt-models
cp ~/frigate/jetson-frigate/patches/tensorrt_models.sh .
docker run --gpus=all --rm -it -e YOLO_MODELS=yolov3-288,yolov3-416,yolov3-608,yolov3-spp-288,yolov3-spp-416,yolov3-spp-608,yolov3-tiny-288,yolov3-tiny-416,yolov4-288,yolov4-416,yolov4-608,yolov4-csp-256,yolov4-csp-512,yolov4-p5-448,yolov4-p5-896,yolov4-tiny-288,yolov4-tiny-416,yolov4x-mish-320,yolov4x-mish-640,yolov7-tiny-288,yolov7-tiny-416,yolov7-640,yolov7-320,yolov7x-640,yolov7x-320 -v `pwd`/trt-models:/tensorrt_models -v `pwd`/tensorrt_models.sh:/tensorrt_models.sh ratsputin/tensorrt:8.6.1-CUDA-11.4-aarch64 /tensorrt_models.sh
```
In the above example, _all_ of the supported models will be created.  This is controlled through the `-e YOLO_MODELS=...` switch and is completely unnecessary and will take _several_ hours.  Not passing that swith will cause the default models to be generated as covered in the Frigate documentation.
# Notes

## Go2rtc
Go2rtc does work but it does have limitations related to the NVMPI implementation.  The native RTSP streaming is not compatible with NVMPI decoding in ffmpeg (it just hangs and streams errors in debug).  It is, however, possible to work around this by using ffmpeg for the encoding.  This has the added benefit of using NVMPI to leverage the NVENC acceleration for encoding.  To take advantage of go2rtc, use the following section (note, I use Reolink cameras, so `audio=opus` is necessary):
```
go2rtc:
  ffmpeg:
    h264: "-c:v h264_nvmpi -g 50 -profile:v high -level:v 4.1 -tune:v zerolatency -pix_fmt:v yuv420p"
  streams:
    front-yard:
      - "ffmpeg:http://192.168.1.206/flv?port=1935&app=bcs&stream=channel0_main.bcs&user=admin&password=#video=h264#audio=opus"
```
The `h264` section is picked up straight from the go2rtc source code with the `-c:v h264_nvmpi` added.  There is, however, an issue with using profiles higher than `high`, so this was selected.
Unfortunately, decoding more than 2-3 high-resolution cameras on top of the work necessary to decode seems to overwhelm the Jetson and sync gets lost.
## Problems with the Jetson and GPU acceleration initializing
Of late, I've noticed the following errors in syslog:
```
Jul 15 05:50:45 jetson kernel: [35639.128931] NVRM rpcRmApiControl_dce: NVRM_RPC_DCE: Failed RM ctrl call cmd:0x2080013f result 0x56:
Jul 15 05:50:45 jetson kernel: [35639.129943] NVRM rpcRmApiControl_dce: NVRM_RPC_DCE: Failed RM ctrl call cmd:0x2080017e result 0x56:
Jul 15 05:50:45 jetson kernel: [35639.132803] NVRM rpcRmApiControl_dce: NVRM_RPC_DCE: Failed RM ctrl call cmd:0x2080014a result 0x56:
Jul 15 05:50:45 jetson kernel: [35639.170849] NVRM rpcRmApiControl_dce: NVRM_RPC_DCE: Failed RM ctrl call cmd:0x730190 result 0x56:
Jul 15 05:50:45 jetson kernel: [35639.234603] NVRM gpumgrGetSomeGpu: Failed to retrieve pGpu - Too early call!.
```
These are frequently paired with starting a container that uses GPU acceleration or the shipped Jetson ffmpeg being invoked from the CLI and just hanging.  When I've seen these, the only recourse I've found is to reboot the Jetson, assuming they cause issues.
# TODO
* Track support for nvmpi fix preventing go2rtc native restreaming from working (https://github.com/jocover/jetson-ffmpeg/issues/113)--this is unlikely to ever be fixed
* Figure out how to train models to inference on Nvidia Jetson DLAs (https://medium.com/@reachmostafa.m/training-yolov4-to-inference-on-nvidia-dlas-8a493f89b091)
* Look into implementing Coral acceleration to see if it frees up cycles for more go2rtc cameras
