#include <metal_stdlib>
using namespace metal;

struct PhotoVertex {
    float4 position [[position]];
    float2 uv;
};

vertex PhotoVertex projectPhoto(uint id [[vertex_id]],
                                const device float4 *surface [[buffer(0)]],
                                constant float4 &camera [[buffer(1)]]) {
    float4 point = surface[id]; // Top-left UV and relative disparity.
    float2 position = (2.0 * point.xy - 1.0) * camera.xy + point.z * camera.zw;
    return {float4(position.x, -position.y, 0.0, 1.0), point.xy};
}

fragment float4 samplePhoto(PhotoVertex point [[stage_in]], texture2d<float> photo [[texture(0)]]) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    return photo.sample(linearSampler, point.uv);
}
