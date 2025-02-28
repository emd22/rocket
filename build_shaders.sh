#!/bin/bash

glslc -fshader-stage=vertex shaders/triangle.vert.hlsl -o shaders/triangle.vert.spv
glslc -fshader-stage=fragment shaders/main.frag.hlsl -o shaders/main.frag.spv

spirv-cross --msl --stage vert shaders/triangle.vert.spv --output shaders/triangle.vert.msl
spirv-cross --msl --stage frag shaders/main.frag.spv --output shaders/main.frag.msl
