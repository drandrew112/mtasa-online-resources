//
// wx_snow :: snow_flakes.fx
//
// Material of dxDrawMaterialPrimitive3D (client/precip.lua). The vertex list is static:
// every flake = 6 vertices with the same position (0..1 inside the box), uv = quad corner,
// colour = random seeds. The vertex shader does everything else: falling + wind (gDrift,
// accumulated in Lua), sway, wrapping inside a box around the camera, billboarding and hiding
// flakes under roofs (roof map) or inside indoor boxes.
//

#include "mta-helper.fx"

float3 gBox = float3(36, 36, 22);
float3 gDrift = float3(0, 0, 0);
float gDensity = 0;              // 0..1 share of the flakes drawn
float gSize = 0.07;              // m
float gAlpha = 1;
float gBright = 1;
float gSway = 0.4;

texture gFlakeTex;

texture gRoofTex;
float4 gRoofRect = float4(-3072, -3072, 6144, 1536);
float3 gRoofZ = float3(-60, 1000, 1.6);
float gRoofOn = 0;

float3 gBox0Min = float3(-99999, -99999, -99999);
float3 gBox0Max = float3(-99998, -99998, -99998);
float3 gBox1Min = float3(-99999, -99999, -99999);
float3 gBox1Max = float3(-99998, -99998, -99998);

sampler SamplerFlake = sampler_state
{
    Texture = (gFlakeTex);
    AddressU = Clamp;
    AddressV = Clamp;
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
    float4 Seed : COLOR0;
    float2 Corner : TEXCOORD0;
};

struct PSInput
{
    float4 Position : POSITION0;
    float2 TexCoord : TEXCOORD0;
    float Alpha : TEXCOORD1;
};

float RoofHeight(float2 wp)
{
    float2 uv = (wp - gRoofRect.xy) / gRoofRect.z;
    float4 t = tex2Dlod(SamplerRoof, float4(uv, 0, 0));
    float h16 = floor(t.r * 255 + 0.5) * 256 + floor(t.g * 255 + 0.5);
    return h16 / 65535.0 * (gRoofZ.y - gRoofZ.x) + gRoofZ.x;
}

float InBox(float3 p, float3 mn, float3 mx)
{
    float3 a = step(mn, p) * step(p, mx);
    return a.x * a.y * a.z;
}

float3 WrapPos(float3 a, float3 b)
{
    return a - b * floor(a / b);
}

PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;
    float4 seed = VS.Seed;

    // flake position, world anchored, wrapped into the box around the camera
    float3 origin = gCameraPosition - gBox * 0.5;
    float t = gTime * (0.6 + seed.g);
    float3 sway = float3(sin(t + seed.r * 6.28), cos(t * 0.8 + seed.a * 6.28), 0) * gSway * seed.b;
    float3 drift = gDrift * (0.75 + 0.5 * seed.a);
    float3 p = origin + WrapPos(VS.Position * gBox + drift + sway - origin, gBox);

    // billboard
    float3 right = float3(gView[0][0], gView[1][0], gView[2][0]);
    float3 up = float3(gView[0][1], gView[1][1], gView[2][1]);
    float size = gSize * (0.55 + 0.9 * seed.r);
    float2 corner = VS.Corner - 0.5;
    float3 world = p + (corner.x * right + corner.y * up) * size;

    // fade at the box border and right in front of the camera
    float3 d = abs(p - gCameraPosition) / (gBox * 0.5);
    float border = saturate((1 - max(max(d.x, d.y), d.z)) * 5);
    float dist = distance(p, gCameraPosition);
    float near = saturate((dist - 0.35) * 2);
    float alpha = border * near * step(seed.b, gDensity) * gAlpha;

    // no flakes under roofs / inside indoor boxes
    if (gRoofOn > 0.5) alpha *= 1 - saturate((RoofHeight(p.xy) - gRoofZ.z - p.z) * 2);
    alpha *= 1 - max(InBox(p, gBox0Min, gBox0Max), InBox(p, gBox1Min, gBox1Max));

    PS.Position = mul(float4(world, 1), gViewProjection);
    if (alpha <= 0.001) PS.Position = float4(0, 0, -10, 1);   // behind the near plane: culled
    PS.TexCoord = VS.Corner;
    PS.Alpha = alpha;
    return PS;
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    float4 tex = tex2D(SamplerFlake, PS.TexCoord);
    return float4(tex.rgb * gBright, tex.a * PS.Alpha);
}

technique snow_flakes
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
