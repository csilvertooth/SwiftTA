//
//  ModelViewRenderer+MetalShaders.metal
//  Metal Template macOS
//
//  Created by Logan Jones on 5/20/18.
//  Copyright © 2018 Logan Jones. All rights reserved.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "TntViewRenderer+MetalShaderTypes.h"

using namespace metal;

#pragma mark - Quad

typedef struct
{
    float4 position [[position]];
    float2 texCoord;
} QuadFragmentIn;

vertex QuadFragmentIn mapQuadVertexShader(MetalTntViewRenderer_MapQuadVertex in [[stage_in]],
                                       constant MetalTntViewRenderer_MapUniforms & uniforms [[ buffer(MetalTntViewRenderer_BufferIndexUniforms) ]])
{
    QuadFragmentIn out;
    out.position = uniforms.mvpMatrix * float4(in.position, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 mapQuadFragmentShader(QuadFragmentIn in [[stage_in]],
                                   constant MetalTntViewRenderer_MapUniforms & uniforms [[ buffer(MetalTntViewRenderer_BufferIndexUniforms) ]],
                                   texture2d<half> colorMap     [[ texture(MetalTntViewRenderer_TextureIndexColor) ]])
{
    // Discard fragments that fall outside the actual map texture so the
    // clear color shows past the map edge instead of the sampler smearing
    // the last row/column of pixels.
    if (in.texCoord.x < 0.0 || in.texCoord.x > 1.0 ||
        in.texCoord.y < 0.0 || in.texCoord.y > 1.0) {
        discard_fragment();
    }
    constexpr sampler colorSampler(mip_filter::nearest,
                                   mag_filter::nearest,
                                   min_filter::nearest,
                                   s_address::clamp_to_zero,
                                   t_address::clamp_to_zero);
    half4 colorSample = colorMap.sample(colorSampler, in.texCoord.xy);

    return float4(colorSample);
}

#pragma mark - Array

typedef struct
{
    float4 position [[position]];
    float2 texCoord;
    float2 worldPosition;
    int slice;
} TileFragmentIn;

vertex TileFragmentIn mapTileVertexShader(MetalTntViewRenderer_MapTileVertex in [[stage_in]],
                                          constant int *slice [[buffer(MetalTntViewRenderer_BufferIndexVertexTextureSlice)]],
                                          uint vid [[vertex_id]],
                                          constant MetalTntViewRenderer_MapUniforms & uniforms [[ buffer(MetalTntViewRenderer_BufferIndexUniforms) ]])
{
    TileFragmentIn out;
    out.position = uniforms.mvpMatrix * float4(in.position, 1.0);
    out.texCoord = in.texCoord;
    out.worldPosition = in.position.xy;
    out.slice = slice[vid];
    return out;
}

fragment float4 mapTileFragmentShader(TileFragmentIn in [[stage_in]],
                                      constant MetalTntViewRenderer_MapUniforms & uniforms [[ buffer(MetalTntViewRenderer_BufferIndexUniforms) ]],
                                      texture2d_array<half> colorMap     [[ texture(MetalTntViewRenderer_TextureIndexColor) ]])
{
    // Discard pixels outside the map's actual pixel area so partial-edge
    // tiles don't expose uninitialized slice memory or repeat the last
    // real column of terrain.
    if (uniforms.mapSize.x > 0.0 && uniforms.mapSize.y > 0.0) {
        if (in.worldPosition.x >= uniforms.mapSize.x ||
            in.worldPosition.y >= uniforms.mapSize.y) {
            discard_fragment();
        }
    }
    constexpr sampler colorSampler(mip_filter::nearest,
                                   mag_filter::nearest,
                                   min_filter::nearest,
                                   s_address::clamp_to_zero,
                                   t_address::clamp_to_zero);
    half4 colorSample = colorMap.sample(colorSampler, in.texCoord.xy, in.slice);

    return float4(colorSample);
}
