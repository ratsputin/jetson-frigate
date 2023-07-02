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

Once the build completes, you will have a **frigate-jetson-tensorrt:latest** docker image.

## Running
```
docker run -d \
 --runtime nvidia \
 --gpus all \
 --name frigate \
 --restart unless-stopped \
 --privileged \
 --shm-size=1024m \
 -p 5000:5000 \
 -v /path/to/config:/config:ro \
 -v /etc/localtime:/etc/localtime:ro \
 -v /media/storage:/media/frigate \
 --device /dev/bus/usb:/dev/bus/usb \
 -e FRIGATE_RTSP_PASSWORD='pass' \
 frigate-jetson-tensorrt:latest
```

## TODO

* Track support for nvmpi fix preventing go2rtc restreaming from working (https://github.com/jocover/jetson-ffmpeg/issues/113)
