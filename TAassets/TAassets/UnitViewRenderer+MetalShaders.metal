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
#import "UnitViewRenderer+MetalShaderTypes.h"

using namespace metal;

#pragma mark - Model

typedef struct
{
    float4 position [[position]];
    float3 positionM;
    float3 normal;
    float2 texCoord;
    int pieceIndex [[flat]];
} FragmentIn;

vertex FragmentIn unitVertexShader(UnitMetalRenderer_ModelVertex in [[stage_in]],
                                   constant UnitMetalRenderer_ModelUniforms & uniforms [[ buffer(UnitMetalRenderer_BufferIndexUniforms) ]])
{
    FragmentIn out;

    float4 position = (uniforms.modelMatrix * uniforms.pieces[in.pieceIndex]) * float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * position;
    out.positionM = float3(position);
    out.normal = uniforms.normalMatrix * in.normal;
    out.texCoord = in.texCoord;
    out.pieceIndex = in.pieceIndex;

    return out;
}

fragment float4 unitFragmentShader(FragmentIn in [[stage_in]],
                                   constant UnitMetalRenderer_ModelUniforms & uniforms [[ buffer(UnitMetalRenderer_BufferIndexUniforms) ]],
                                   texture2d<half> colorMap     [[ texture(UnitMetalRenderer_TextureIndexColor) ]])
{
    constexpr sampler colorSampler(mip_filter::nearest,
                                   mag_filter::nearest,
                                   min_filter::nearest);
    half4 colorSample = colorMap.sample(colorSampler, in.texCoord.xy);
    
    float3 lightColor = float3(1.0, 1.0, 1.0);
    
    // ambient
    float ambientStrength = 0.6;
    float3 ambient = ambientStrength * lightColor;
    
    // diffuse
    float diffuseStrength = 0.4;
    float3 norm = normalize(in.normal);
    float3 lightDir = normalize(uniforms.lightPosition - in.positionM);
    float diff = max(dot(norm, lightDir), 0.0);
    float3 diffuse = diffuseStrength * diff * lightColor;
    
    // specular
    float specularStrength = 0.1;
    float3 viewDir = normalize(uniforms.viewPosition - in.positionM);
    float3 reflectDir = reflect(-lightDir, norm);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32);
    float3 specular = specularStrength * spec * lightColor;
    
    // all together now
    float4 lightContribution = float4(ambient + diffuse + specular, 1.0);
    
    float4 out_color;
    if (uniforms.objectColor.a == 0.0) {
        out_color = lightContribution * float4(colorSample);
    }
    else {
        out_color = lightContribution * uniforms.objectColor;
    }
    if (uniforms.highlightedPieceIndex >= 0 && in.pieceIndex == uniforms.highlightedPieceIndex) {
        out_color.rgb = mix(out_color.rgb, float3(1.0, 0.85, 0.15), 0.55);
    }
    return out_color;
}

fragment float4 unitUnlitFragmentShader(FragmentIn in [[stage_in]],
                                   constant UnitMetalRenderer_ModelUniforms & uniforms [[ buffer(UnitMetalRenderer_BufferIndexUniforms) ]],
                                   texture2d<half> colorMap     [[ texture(UnitMetalRenderer_TextureIndexColor) ]])
{
    constexpr sampler colorSampler(mip_filter::nearest,
                                   mag_filter::nearest,
                                   min_filter::nearest);
    half4 colorSample = colorMap.sample(colorSampler, in.texCoord.xy);

    float4 out_color;
    if (uniforms.objectColor.a == 0.0) {
        out_color = float4(colorSample);
    }
    else {
        out_color = uniforms.objectColor;
    }
    if (uniforms.highlightedPieceIndex >= 0 && in.pieceIndex == uniforms.highlightedPieceIndex) {
        out_color.rgb = mix(out_color.rgb, float3(1.0, 0.85, 0.15), 0.55);
    }
    return out_color;
}
