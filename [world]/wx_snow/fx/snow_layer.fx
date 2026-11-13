//
// wx_snow :: snow_layer.fx
//
// One cylinder of falling snow around the camera (client/precip.lua, one shader per PAIR of layers).
// F4: the cylinder carries two layers: the second is the same view ray seen on a cylinder gRatio
// times wider (its own texture scale / scroll / alpha), so a pair costs one full screen overdraw
// instead of two.
// Static vertex list: x, y = unit circle, z = 0 (bottom) / 1 (top); uv.x = 0..1 around.
// The texture scrolls down (gScroll.y) and sideways with the wind (gScroll.x); u is tied to the
// angle, so turning the camera keeps the flakes in place. Pixels under a roof are hidden.
//

#include "mta-helper.fx"

float gRadius = 10;
float2 gHeight = float2(-12, 26);  // bottom / top relative to the camera
float2 gTile = float2(4, 4);       // world metres of one texture repeat (u, v)
float2 gScroll = float2(0, 0);     // texture offset (in repeats)
float gAlpha = 0;
float gBright = 1;
// second layer of the pair (gRatio = 0: none)
float gRatio = 0;
float2 gTile2 = float2(4, 4);
float2 gScroll2 = float2(0, 0);
float gAlpha2 = 0;

texture gLayerTex;

texture gRoofTex;
float4 gRoofRect = float4(-3072, -3072, 6144, 1536);
float3 gRoofZ = float3(-60, 1000, 1.6);
float gRoofOn = 0;

sampler SamplerLayer = sampler_state
{
    Texture = (gLayerTex);
    AddressU = Wrap;
    AddressV = Wrap;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
};

sampler SamplerRoof = sampler_state
{
    Texture = (gRoofTex);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
};

struct VSInput
{
    float3 Position : POSITION0;
    float4 Diffuse : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

struct PSInput
{
    float4 Position : POSITION0;
    float2 TexCoord : TEXCOORD0;
    float3 WorldPos : TEXCOORD1;
    float Fade : TEXCOORD2;
    float Around : TEXCOORD3;
};

float RoofCover(float3 wp)
{
    float2 uv = (wp.xy - gRoofRect.xy) / gRoofRect.z;
    float4 t = tex2Dlod(SamplerRoof, float4(uv, 0, 0));
    float h16 = floor(t.r * 255 + 0.5) * 256 + floor(t.g * 255 + 0.5);
    float h = h16 / 65535.0 * (gRoofZ.y - gRoofZ.x) + gRoofZ.x;
    return saturate((h - gRoofZ.z - wp.z) * 2);
}

float RoofHeight(float2 wp)
{
    float2 uv = (wp - gRoofRect.xy) / gRoofRect.z;
    float4 t = tex2Dlod(SamplerRoof, float4(uv, 0, 0));
    float h16 = floor(t.r * 255 + 0.5) * 256 + floor(t.g * 255 + 0.5);
    return h16 / 65535.0 * (gRoofZ.y - gRoofZ.x) + gRoofZ.x;
}

PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;
    float h = lerp(gHeight.x, gHeight.y, VS.Position.z);
    float3 world = gCameraPosition + float3(VS.Position.x * gRadius, VS.Position.y * gRadius, h);
    PS.Position = mul(float4(world, 1), gViewProjection);
    PS.WorldPos = world;
    float around = 6.2831853 * gRadius;
    PS.TexCoord = float2(VS.TexCoord.x * around / gTile.x, world.z / gTile.y) + gScroll;
    // fade out at the top and bottom of the cylinder
    PS.Fade = saturate(VS.Position.z * 4) * saturate((1 - VS.Position.z) * 3);
    PS.Around = VS.TexCoord.x;
    return PS;
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    float4 tex = tex2D(SamplerLayer, PS.TexCoord);
    float a = tex.a * PS.Fade * gAlpha;
    if (gRoofOn > 0.5) a *= 1 - RoofCover(PS.WorldPos);
    float3 rgb = tex.rgb;
    [branch] if (gRatio > 0)
    {
        // the same ray on the wider cylinder: horizontal and vertical offsets scale with the radius
        float3 d = PS.WorldPos - gCameraPosition;
        float3 p2 = gCameraPosition + d * gRatio;
        float2 uv2 = float2(PS.Around * 6.2831853 * gRadius * gRatio / gTile2.x, p2.z / gTile2.y) + gScroll2;
        float4 tex2 = tex2Dlod(SamplerLayer, float4(uv2, 0, 0));
        float f2 = saturate((p2.z - gCameraPosition.z - gHeight.x) / (gHeight.y - gHeight.x));
        float a2 = tex2.a * saturate(f2 * 4) * saturate((1 - f2) * 3) * gAlpha2;
        if (gRoofOn > 0.5) a2 *= 1 - RoofCover(p2);
        float out_a = 1 - (1 - a) * (1 - a2);
        rgb = (tex.rgb * a + tex2.rgb * a2 * (1 - a)) / max(out_a, 0.001);
        a = out_a;
    }
    return float4(rgb * gBright, a);
}

technique snow_layer
{
    pass P0
    {
        AlphaBlendEnable = TRUE;
        SrcBlend = SRCALPHA;
        DestBlend = INVSRCALPHA;
        ZWriteEnable = FALSE;
        CullMode = NONE;
        Lighting = FALSE;
        FogEnable = FALSE;
        VertexShader = compile vs_3_0 VertexShaderFunction();
        PixelShader = compile ps_3_0 PixelShaderFunction();
    }
}
