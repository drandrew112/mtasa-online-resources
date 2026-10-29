//
// cp_ground.fx - race checkpoint ground disc (mode_race/client/checkpoints.lua)
// Vertex color = checkpoint color (RGBA), TexCoord.y = distance from the centre (0 centre .. 1 rim)
//

float4x4 gWorldViewProjection : WORLDVIEWPROJECTION;
float gTime : TIME;

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
};

PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;
    PS.Position = mul(float4(VS.Position, 1), gWorldViewProjection);
    PS.Diffuse = VS.Diffuse;
    PS.TexCoord = VS.TexCoord;
    return PS;
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    float r = saturate(PS.TexCoord.y);

    // bright rim, soft inside
    float rim = smoothstep(0.80, 0.97, r) * (1.0 - smoothstep(0.97, 1.0, r));
    float inner = 0.14 * (1.0 - r * 0.5);

    // a ring expanding from the centre to the rim, again and again
    float wave = frac(gTime * 0.6);
    float ring = exp(-pow((r - wave) * 14.0, 2.0)) * 0.45 * (1.0 - wave);

    float alpha = saturate(rim * 0.95 + inner + ring) * PS.Diffuse.a;
    float3 color = lerp(PS.Diffuse.rgb, float3(1, 1, 1), saturate(rim * 0.35 + ring * 0.5));
    return float4(color, alpha);
}

technique cp_ground
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
