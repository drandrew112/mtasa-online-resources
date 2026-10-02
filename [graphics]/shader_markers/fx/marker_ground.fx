//
// marker_ground.fx
// Ground disc under cylinder markers: radial gradient, edge ring, expanding pulse.
// Vertex color = original marker color (RGBA), TexCoord.x = radius (0 center .. 1 edge)
//

float4x4 gWorldViewProjection : WORLDVIEWPROJECTION;
float gTime : TIME;

float gPulseSpeed = 0.45;     // expanding ring cycles per second
float gFillStrength = 0.30;   // inner radial gradient strength
float gRingStrength = 0.95;   // edge ring strength
float gPulseStrength = 0.55;  // expanding pulse strength

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
    float r = saturate(PS.TexCoord.x);

    // Inner gradient: transparent center, denser toward the edge
    float fill = gFillStrength * (0.25 + 0.75 * r * r);

    // Crisp edge ring with a soft inner falloff
    float ring = gRingStrength * smoothstep(0.84, 0.965, r) * (1.0 - smoothstep(0.965, 1.0, r));

    // Pulse ring expanding from the center, fading out at the edge
    float p = frac(gTime * gPulseSpeed);
    float pulse = gPulseStrength * exp(-pow((r - p) * 13.0, 2.0)) * (1.0 - p);

    float alpha = saturate(fill + ring + pulse) * PS.Diffuse.a;

    float highlight = saturate(ring * 0.4 + pulse * 0.5);
    float3 color = lerp(PS.Diffuse.rgb, float3(1, 1, 1), highlight * 0.45);

    return float4(color, alpha);
}

technique marker_ground
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
