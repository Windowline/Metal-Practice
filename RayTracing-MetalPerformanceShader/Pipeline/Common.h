#ifndef Common_h
#define Common_h

#import <simd/simd.h>

struct Camera {
    vector_float3 pos;
    vector_float3 right;
    vector_float3 up;
    vector_float3 forward;
};

struct AreaLight {
    vector_float3 pos;
    vector_float3 forward;
    vector_float3 right;
    vector_float3 up;
    vector_float3 color;
};

struct Uniforms
{
    unsigned int width;
    unsigned int height;
    unsigned int frameIdx;
    struct Camera camera;
    struct AreaLight light;
};


#endif /* Common_h */
