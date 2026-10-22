#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 model;
    float4x4 vp;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut vertex_main(
    VertexIn in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]]
) {
    VertexOut out;

    float4 world_position =
        uniforms.model * float4(in.position, 1.0);

    out.position = uniforms.vp * world_position;
    out.color = in.color;

    return out;
}

fragment float4 fragment_main(
    VertexOut in [[stage_in]]
) {
    return in.color;
}