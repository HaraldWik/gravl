#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float position[3];
    float color[3];
};

struct VertexOutput {
    float4 position [[position]];
    float3 color;
};

vertex VertexOutput vertex_main(
    uint vertex_id [[vertex_id]],
    const device Vertex* vertices [[buffer(0)]]
) {
    VertexOutput out;
    Vertex vertex_data = vertices[vertex_id];

    out.position = float4(
        vertex_data.position[0],
        vertex_data.position[1],
        vertex_data.position[2],
        1.0
    );
    out.color = float3(
        vertex_data.color[0],
        vertex_data.color[1],
        vertex_data.color[2]
    );

    return out;
}

fragment float4 fragment_main(VertexOutput in [[stage_in]]) {
    return float4(in.color, 1.0);
}