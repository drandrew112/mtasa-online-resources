//
// wx_snow :: snow_grass.fx
//
// GTA procedural grass / plants (tx* textures): whitened (gWhite) or hidden (gHide).
// Replacement shader (not layered) with a high priority; shader_detail and dynamic_lighting
// both leave tx* alone, so there is nothing to collide with.
//

texture gTexture0 < string textureState="0,Texture"; >;

float gWhite = 0;    // 0..1
float gHide = 0;     // 1 = invisible

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
    float lum = dot(PS.Diffuse.rgb, float3(0.3, 0.59, 0.11));
    tex.rgb = lerp(tex.rgb, float3(0.9, 0.92, 0.95) * saturate(lum * 1.15), gWhite);
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
