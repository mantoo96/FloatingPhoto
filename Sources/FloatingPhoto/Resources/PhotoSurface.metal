#include <metal_stdlib>
using namespace metal;

struct PhotoVertex {
    float4 position [[position]];
    float2 uv;
};

struct PhotoUniforms {
    float4 camera;
    float4 effects;
    float4 blur;
};

vertex PhotoVertex projectPhoto(uint id [[vertex_id]]) {
    constexpr float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    constexpr float2 coordinates[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    PhotoVertex output;
    output.position = float4(positions[id], 0.0, 1.0);
    output.uv = 0.5 + (coordinates[id] - 0.5) * float2(1.0, 1.0);
    return output;
}

constexpr sampler linearClamp(coord::normalized, address::clamp_to_edge, filter::linear);

float heightAt(texture2d<float, access::sample> depth, float2 uv) {
    return depth.sample(linearClamp, uv).r;
}

float2 parallaxOcclusionMapping(
    float2 offset,
    float2 texCoords,
    texture2d<float, access::sample> depth,
    float pivot,
    float heightScale
) {
    if (length_squared(offset) < 0.0000001) {
        return texCoords;
    }

    float3 viewDirection = normalize(float3(offset, -1.0));
    float angle = abs(dot(float3(0.0, 0.0, 1.0), viewDirection));
    int layerCount = int(mix(64.0, 24.0, angle));
    float layerDepth = 1.0 / float(layerCount);
    float2 delta = offset * heightScale / float(layerCount);

    float currentLayerDepth = 0.0;
    float2 currentUV = texCoords + pivot * offset;
    float currentHeight = heightAt(depth, currentUV);

    for (int layer = 0; layer < 64 && currentLayerDepth < currentHeight; layer++) {
        currentUV -= delta;
        currentHeight = heightAt(depth, currentUV);
        currentLayerDepth += layerDepth;
    }

    float2 previousUV = currentUV + delta;
    float afterDepth = currentHeight - currentLayerDepth;
    float beforeDepth = heightAt(depth, previousUV) - currentLayerDepth + layerDepth;
    float denominator = afterDepth - beforeDepth;
    float weight = abs(denominator) > 0.00001 ? afterDepth / denominator : 0.0;
    return clamp(mix(previousUV, currentUV, 1.0 - weight), 0.0, 1.0);
}

half4 depthAwareBlur(
    texture2d<float, access::sample> photo,
    texture2d<float, access::sample> depth,
    float2 uv,
    float2 texelSize,
    float blurIntensity,
    float blurOpacity,
    float focalPoint
) {
    half4 color = half4(photo.sample(linearClamp, uv)) * 0.227027;
    float depthDistance = abs(depth.sample(linearClamp, uv).r - focalPoint);
    float amount = depthDistance * blurIntensity * blurOpacity;
    float2 step = texelSize * (min(3.0, amount) * 1.8);
    constexpr half weights[4] = {0.1945946h, 0.1216216h, 0.0540541h, 0.0162162h};

    for (int i = 1; i < 5; i++) {
        float2 delta = step * float(i);
        half weight = weights[i - 1] * 0.5h;
        color += half4(photo.sample(linearClamp, uv + float2(delta.x, 0.0))) * weight;
        color += half4(photo.sample(linearClamp, uv - float2(delta.x, 0.0))) * weight;
        color += half4(photo.sample(linearClamp, uv + float2(0.0, delta.y))) * weight;
        color += half4(photo.sample(linearClamp, uv - float2(0.0, delta.y))) * weight;
    }
    return color;
}

fragment float4 samplePhoto(
    PhotoVertex point [[stage_in]],
    texture2d<float> photo [[texture(0)]],
    texture2d<float> depth [[texture(1)]],
    constant PhotoUniforms &uniforms [[buffer(0)]]
) {
    float2 visibleScale = max(uniforms.camera.xy, float2(0.001));
    float2 baseUV = 0.5 + (point.uv - 0.5) * visibleScale;
    float2 parallaxUV = baseUV;

    if (uniforms.blur.z > 0.5) {
        parallaxUV = parallaxOcclusionMapping(
            uniforms.camera.zw,
            baseUV,
            depth,
            uniforms.effects.w,
            uniforms.effects.z
        );
    }

    half4 color = depthAwareBlur(
        photo,
        depth,
        parallaxUV,
        uniforms.effects.xy,
        uniforms.blur.x,
        uniforms.blur.y * uniforms.blur.z,
        uniforms.effects.w
    );
    return float4(color);
}
