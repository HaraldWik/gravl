#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float2 position;
    float3 color;
};

struct VertexOut {
    float4 position [[position]];
    float3 color;
};

vertex VertexOut vertex_main(
    const device Vertex *vertices [[buffer(0)]],
    uint vertex_id [[vertex_id]]
) {
    Vertex vertex = vertices[vertex_id];

    VertexOut out;
    out.position = float4(vertex.position, 0.0, 1.0);
    out.color = vertex.color;

    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return float4(in.color, 1.0);
}