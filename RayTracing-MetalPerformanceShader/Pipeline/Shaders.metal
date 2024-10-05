//
/**
 * Copyright (c) 2018 Razeware LLC
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
#include <simd/simd.h>
#import "Common.h"

using namespace metal;

struct Ray {
    packed_float3 origin;
    float minDist;
    packed_float3 dir;
    float maxDist;
    float3 color;
};

struct Intersection {
    float dist;
    int primitiveIdx;
    float2 coord;
};

template<typename T>
inline T interpolateVertexAttribute(device T *attributes, Intersection intersection) {
    float3 uvw;
    uvw.xy = intersection.coord;
    uvw.z = 1.0 - uvw.x - uvw.y;
    unsigned int triangleIdx = intersection.primitiveIdx;
    T T0 = attributes[triangleIdx * 3 + 0];
    T T1 = attributes[triangleIdx * 3 + 1];
    T T2 = attributes[triangleIdx * 3 + 2];
    return uvw.x * T0 + uvw.y * T1 + uvw.z * T2;
}

// Maps two uniformly random numbers to the surface of a two-dimensional area light
// source and returns the direction to this point, the amount of light which travels
// between the intersection point and the sample point on the light source, as well
// as the distance between these two points.
inline void sampleAreaLight(constant AreaLight& light,
                            float2 rand,
                            float3 pos,
                            thread float3& lightDir,
                            thread float3& lightColor,
                            thread float& lightDist)
{
    // Map to -1..1
    rand = rand * 2.0f - 1.0f;
  
    // Transform into light's coordinate system
    float3 samplePos = light.pos + light.right * rand.x + light.up * rand.y;
  
    // Compute vector from sample point on light source to intersection point
    lightDir = samplePos - pos;
  
    lightDist = length(lightDir);
  
    float invLightDist = 1.0f / max(lightDist, 1e-3f);
  
    // Normalize the light direction
    lightDir *= invLightDist;
  
    // Start with the light's color
    lightColor = light.color;
  
    // Light falls off with the inverse square of the distance to the intersection point
    lightColor *= (invLightDist * invLightDist);
  
    // Light also falls off with the cosine of angle between the intersection point and
    // the light source
    lightColor *= saturate(dot(-lightDir, light.forward));
}

// Uses the inversion method to map two uniformly random numbers to a three dimensional
// unit hemisphere where the probability of a given sample is proportional to the cosine
// of the angle between the sample direction and the "up" direction (0, 1, 0)
inline float3 sampleCosineWeightedHemisphere(float2 u) {
    float phi = 2.0f * M_PI_F * u.x;
  
    float cos_phi;
    float sin_phi = sincos(phi, cos_phi);
  
    float cos_theta = sqrt(u.y);
    float sin_theta = sqrt(1.0f - cos_theta * cos_theta);
  
    return float3(sin_theta * cos_phi, cos_theta, sin_theta * sin_phi);
}

// Aligns a direction on the unit hemisphere such that the hemisphere's "up" direction
// (0, 1, 0) maps to the given surface normal direction
inline float3 alignHemisphereWithNormal(float3 sample, float3 normal) {
    // Set the "up" vector to the normal
    float3 up = normal;
  
    // Find an arbitrary direction perpendicular to the normal. This will become the
    // "right" vector.
    float3 right = normalize(cross(normal, float3(0.0072f, 1.0f, 0.0034f)));
  
    // Find a third vector perpendicular to the previous two. This will be the
    // "forward" vector.
    float3 forward = cross(right, up);
  
    // Map the direction on the unit hemisphere to the coordinate system aligned
    // with the normal.
    return sample.x * right + sample.y * up + sample.z * forward;
}

kernel void primaryRays(constant Uniforms& uniforms [[buffer(0)]],
                        device Ray* rays [[buffer(1)]],
                        device float2* random [[buffer(2)]],
                        texture2d<float, access::write> t [[texture(0)]],
                        uint2 tid [[thread_position_in_grid]])
{
    
    if (tid.x < uniforms.width && tid.y < uniforms.height) {
        float2 pixel = (float2)tid;
        float2 rand = random[(tid.y % 16) * 16 + (tid.x % 16)];
        pixel += rand;
        float2 uv = (float2)pixel / float2(uniforms.width, uniforms.height);
        uv = uv * 2.0 - 1.0;
        
        constant Camera& cam = uniforms.camera;
        unsigned int rayIdx = tid.y * uniforms.width + tid.x;
        device Ray& ray = rays[rayIdx];
        ray.origin = cam.pos;
        ray.dir = normalize(uv.x * cam.right + uv.y * cam.up + cam.forward);
        ray.minDist = 0;
        ray.maxDist = INFINITY;
        ray.color = float3(1.0);
        t.write(float4(0.0), tid);
    }
}


kernel void rayBounce(uint2 tid [[thread_position_in_grid]],
                      constant Uniforms& uniforms,
                      device Ray* rays,
                      device Ray* shadowRays,
                      device Intersection* intersections,
                      device float3* vtxColors,
                      device float3* vtxNormals,
                      device float2* random)
{
    if (tid.x < uniforms.width && tid.y < uniforms.height) {
        unsigned int rayIdx = tid.y * uniforms.width + tid.x;
        device Ray& ray = rays[rayIdx];
        device Ray& shadowRay = shadowRays[rayIdx];
        device Intersection& intersection = intersections[rayIdx];
        float3 color = ray.color;
        
        if (ray.maxDist >= 0.0 && intersection.dist >= 0.0) {
            float3 interPos = ray.origin + ray.dir * intersection.dist;
            float3 N = interpolateVertexAttribute(vtxNormals, intersection);
            N = normalize(N);
            
            float2 rand = random[(tid.y % 16) * 16 + (tid.x % 16)];
            
            float3 lightDir;
            float3 lightColor;
            float lightDist;
            sampleAreaLight(uniforms.light, rand, interPos,
                            lightDir, lightColor, lightDist);
            
            lightColor *= saturate(dot(N, lightDir));
            
            color *= interpolateVertexAttribute(vtxColors, intersection);
            
            shadowRay.origin = interPos + N * 1e-3;
            shadowRay.dir = lightDir;
            shadowRay.maxDist = lightDist;
            shadowRay.color = lightColor * color;
            
            float3 sampleDir = sampleCosineWeightedHemisphere(rand);
            sampleDir = alignHemisphereWithNormal(sampleDir, N);
            
            ray.origin = interPos + N * 1e-3f;
            ray.dir = sampleDir;
            ray.color = color;
        } else {
            ray.maxDist = -1.0;
            shadowRay.maxDist = -1.0;
        }
    }
}
    
kernel void rayColor(uint2 tid [[thread_position_in_grid]],
                     constant Uniforms& uniforms,
                     device Ray* shadowRays,
                     device float* intersectionDists,
                     texture2d<float, access::read_write> renderTarget)
{
    if (tid.x < uniforms.width && tid.y < uniforms.height) {
        unsigned int rayIdx = tid.y * uniforms.width + tid.x;
        device Ray& shadowRay = shadowRays[rayIdx];
        float intersectionDist = intersectionDists[rayIdx];
        
        if (shadowRay.maxDist >= 0.0 && intersectionDist < 0.0) {
            float3 color = shadowRay.color;
            color += renderTarget.read(tid).xyz;
            renderTarget.write(float4(color, 1.0), tid);
        }
    }
}

kernel void accumulate(constant Uniforms & uniforms,
                       texture2d<float> renderTex,
                       texture2d<float, access::read_write> accumTex,
                       uint2 tid [[thread_position_in_grid]])
{
    if (tid.x < uniforms.width && tid.y < uniforms.height) {
        
        float3 renderColor = renderTex.read(tid).xyz;
        
        if (uniforms.frameIdx > 0) {
            float3 prevAccumColor = accumTex.read(tid).xyz;
            renderColor += (prevAccumColor * uniforms.frameIdx);
            renderColor /= (uniforms.frameIdx + 1);
        }
        
        accumTex.write(float4(renderColor, 1.0), tid);
    }
    
    // frame: i-1
    // accumTex[i-1] = (renderTex[i-1] + accumTex[i-2] * (i-1)) / i
    // frame: i
    // accumTex[i] = (renderTex[i] + accumTex[i-1] * i) / (i+1)
    
    // --> accumTex[i-1] * i = rnderTex[i-1] + accumTex[i-2] * (i-1)
    // --> accumTex[i] = (renderTex[i] + renderTex[i-1] + accumTex[i-2] * (i-1)) / i
    // --> accumTex[i] = (renderTex[i] + renderTex[i-1] + .. renderTex[0]) / i (재귀적으로 해체)
    // 100 frame --> accumTex[100] = sum(renderTex[0:100]) / 100
}
 
// MARK: render
struct Vertex {
    float4 position [[position]];
    float2 uv;
};

constant float2 quadVertices[] = {
    float2(-1, -1),
    float2(-1,  1),
    float2( 1,  1),
    float2(-1, -1),
    float2( 1,  1),
    float2( 1, -1)
};

vertex Vertex vertexShader(unsigned short vid [[vertex_id]])
{
    float2 position = quadVertices[vid];
    Vertex out;
    out.position = float4(position, 0, 1);
    out.uv = position * 0.5 + 0.5;
    return out;
}

fragment float4 fragmentShader(Vertex in [[stage_in]],
                               texture2d<float> tex)
{
    constexpr sampler s(min_filter::nearest, mag_filter::nearest, mip_filter::none);
    float3 color = tex.sample(s, in.uv).xyz;
    return float4(color, 1.0);
}
