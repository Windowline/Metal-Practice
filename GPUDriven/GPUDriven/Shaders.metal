//
/**
 * Copyright (c) 2019 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
 * distribute, sublicense, create a derivative work, and/or sell copies of the
 * Software in any work that is designed, intended, or marketed for pedagogical or
 * instructional purposes related to programming, coding, application development,
 * or information technology.  Permission for such use, copying, modification,
 * merger, publication, distribution, sublicensing, creation of derivative works,
 * or sale is expressly withheld.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */


#include <metal_stdlib>
using namespace metal;
#import "Common.h"

struct VertexIn {
    float4 position [[attribute(Position)]];
    float3 normal [[attribute(Normal)]];
    float2 uv [[attribute(UV)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    uint modelIdx [[flat]];
};

vertex VertexOut vertex_main(const VertexIn vertexIn [[stage_in]],
                             constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]],
                             constant ModelParams* modelParamsArr [[buffer(BufferIndexModelParams)]],
                             uint baseInstance [[base_instance]])
{
    ModelParams modelParams = modelParamsArr[baseInstance];
    
    VertexOut out {
        .position = uniforms.projectionMatrix * uniforms.viewMatrix
                           * modelParams.modelMatrix * vertexIn.position,
        .uv = vertexIn.uv,
        .modelIdx = baseInstance
    };
   
    return out;
}

struct Textures {
    texture2d<float> colorTex;
    texture2d<float> normalTex;
};

fragment float4 fragment_main(
                              VertexOut in [[stage_in]],
                              constant Textures& textures [[buffer(BufferIndexTextures)]],
                              constant FragmentUniforms& fragUniforms [[buffer(BufferIndexFragmentUniforms)]],
                              constant ModelParams* modelParamsArr [[buffer(BufferIndexModelParams)]]
                              ) 
{
    ModelParams modelParams = modelParamsArr[in.modelIdx];
    constexpr sampler textureSampler(filter::linear, address::repeat);
    float3 color = textures.colorTex.sample(textureSampler,
                                            in.uv * modelParams.tiling).rgb;
    
    return float4(color, 1);
}
