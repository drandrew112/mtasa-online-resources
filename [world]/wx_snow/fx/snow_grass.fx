//
// wx_snow :: snow_grass.fx
//
// GTA procedural grass / plants (tx* textures): whitened (gWhite) or hidden (gHide).
// Replacement shader (not layered) with a high priority; shader_detail and dynamic_lighting
// both leave tx* alone, so there is nothing to collide with.
//

texture gTexture0 < string textureState="0,Texture"; >;

float gWhite = 0;    // 0..1 frost amount (client/ground.lua: follows the ground coverage)
float gHide = 0;     // 0..1 blades shrink away (the grass is buried)
float gSunWarm = 0;  // sunrise / sunset tint

sampler Sampler0 = sampler_state
{
    Texture = (gTexture0);
};

struct PSInput
{
    float4 Diffuse : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    float4 tex = tex2D(Sampler0, PS.TexCoord) * PS.Diffuse;
    // frost: lit like the ground snow (luminance of the vertex light only, cool shade, warm sunset),
    // never brighter than the light there is, so blades do not glow white on a dark / bare ground
    float lv = saturate(dot(PS.Diffuse.rgb, float3(0.3, 0.59, 0.11)) * 1.12);
    float3 tint = lerp(float3(1.0, 0.985, 0.96), float3(1.0, 0.8, 0.62), gSunWarm);
    float3 frost = lerp(float3(0.8, 0.86, 0.97), tint, saturate((lv - 0.12) / 0.4)) * lv * float3(0.76, 0.79, 0.85);
    // keep some of the blade's own shading (a flat white blade glows next to the partly covered ground)
    float tl = dot(tex.rgb, float3(0.3, 0.59, 0.11)) / max(lv, 0.05);
    frost *= 0.78 + 0.3 * saturate(tl * 1.6);
    tex.rgb = lerp(tex.rgb, frost, gWhite);
    tex.a *= 1 - gHide;
    return tex;
}

technique snow_grass
{
    pass P0
    {
        PixelShader = compile ps_2_0 PixelShaderFunction();
    }
}
