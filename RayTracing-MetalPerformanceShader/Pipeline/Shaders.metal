
#include <metal_stdlib>
using namespace metal;
#import "Common.h"

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 color    [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant Uniforms &uniforms [[buffer(1)]])
{
    VertexOut out;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * float4(in.position, 1.0);
    out.color = float4(in.color, 1.0);
    return out;
}


fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}
