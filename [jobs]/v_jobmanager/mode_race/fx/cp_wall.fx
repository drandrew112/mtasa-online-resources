//
// cp_wall.fx - race checkpoint wall (mode_race/client/checkpoints.lua)
// Vertex color = checkpoint color (RGBA), TexCoord.x = angle (0..1), TexCoord.y = height (0 bottom .. 1 top)
//

float4x4 gWorldViewProjection : WORLDVIEWPROJECTION;
float3 gCameraPosition : CAMERAPOSITION;
float gTime : TIME;

float gFlash = 0;              // 0..1, set for a moment after the checkpoint appears

struct VSInput
{
    float3 Position : POSITION0;
    float4 Diffuse : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

struct PSInput
{
    float4 Position : POSITION0;
    float4 Diffuse : COLOR0;
    float2 TexCoord : TEXCOORD0;
    float3 WorldPos : TEXCOORD1;
};

PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;
    PS.Position = mul(float4(VS.Position, 1), gWorldViewProjection);
    PS.WorldPos = VS.Position;
    PS.Diffuse = VS.Diffuse;
    PS.TexCoord = VS.TexCoord;
    return PS;
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    float v = saturate(PS.TexCoord.y);

    float angle = PS.TexCoord.x * 6.2831853;
    float3 normal = float3(cos(angle), sin(angle), 0);
    float3 toCam = gCameraPosition - PS.WorldPos;
    float3 viewDir = normalize(float3(toCam.xy, 0.0001));
    float fresnel = pow(1.0 - abs(dot(normal, viewDir)), 2.0);

    float fade = pow(1.0 - v, 1.4);
    float body = 0.30 * fade;
    float rim = 0.60 * fresnel * fade;
    float bottom = 0.90 * (1.0 - smoothstep(0.0, 0.06, v));

    // two light bands running up the wall
    float bandPos = frac(v * 1.6 - gTime * 0.8);
    float band = exp(-pow((bandPos - 0.5) * 6.0, 2.0)) * 0.45 * fade;

    // stripes around the ring, slowly turning
    float stripes = 0.12 * fade * step(0.5, frac(PS.TexCoord.x * 24.0 + gTime * 0.15));

    float alpha = saturate(body + rim + bottom + band + stripes + gFlash * 0.5 * fade) * PS.Diffuse.a;
    float highlight = saturate(bottom * 0.4 + band * 0.7 + gFlash * 0.6);
    float3 color = lerp(PS.Diffuse.rgb, float3(1, 1, 1), highlight * 0.55);
    return float4(color, alpha);
}

technique cp_wall
{
    pass P0
    {
        AlphaBlendEnable = TRUE;
        SrcBlend = SRCALPHA;
        DestBlend = INVSRCALPHA;
        ZEnable = TRUE;
        ZWriteEnable = FALSE;
        CullMode = NONE;
        Lighting = FALSE;
        FogEnable = FALSE;
        VertexShader = compile vs_3_0 VertexShaderFunction();
        PixelShader = compile ps_3_0 PixelShaderFunction();
    }
}
