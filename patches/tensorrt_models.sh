#!/bin/bash

set -euxo pipefail

# One of the makefiles invokes python3 with 'python'
update-alternatives --install /usr/bin/python python /usr/bin/python3.8 10
update-alternatives --install /usr/bin/python python /usr/bin/python3.9 20

export CUDA_HOME=/usr/local/cuda
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64"
export PATH="/usr/local/cuda-11.4/bin:$PATH"
export OUTPUT_FOLDER=/tensorrt_models
echo "Generating the following TRT Models: ${YOLO_MODELS:="yolov4-tiny-288,yolov4-tiny-416,yolov7-tiny-416"}"

# Create output folder
mkdir -p ${OUTPUT_FOLDER}

# Install packages
pip install --upgrade pip && pip install cuda-python

# Clone tensorrt_demos repo
git clone --depth 1 https://github.com/yeahme49/tensorrt_demos.git /tensorrt_demos

# Build libyolo
cd /tensorrt_demos/plugins && make all
cp libyolo_layer.so ${OUTPUT_FOLDER}/libyolo_layer.so

# Download yolo weights
cd /tensorrt_demos/yolo && ./download_yolo.sh

# Build trt engine
cd /tensorrt_demos/yolo

for model in ${YOLO_MODELS//,/ }
do
    python3 yolo_to_onnx.py -m ${model}
    python3 onnx_to_tensorrt.py -m ${model}
    cp /tensorrt_demos/yolo/${model}.trt ${OUTPUT_FOLDER}/${model}.trt;
done
