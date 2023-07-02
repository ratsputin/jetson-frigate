# jetson-frigate
[Frigate](https://github.com/blakeblackshear/frigate) on [Jetson Nano](https://developer.nvidia.com/embedded/jetson-nano-developer-kit) with ffmpeg 6.0 NVMPI patches for encoding/decoding hardware acceleration, docker build files and many more.

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
git clone https://github.com/blakeblackshear/frigate.git
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

After quite a while you will have **frigate-jetson-tensorrt:latest** docker image.

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
 frigate:latest
```

## TODO

* Track support for nvmpi fix preventing go2rtc restreaming from working (https://github.com/jocover/jetson-ffmpeg/issues/113)
