//
// marker_wall.fx
// Gradient wall for cylinder markers.
// Vertex color = original marker color (RGBA), TexCoord.x = angle (0..1), TexCoord.y = height (0 bottom .. 1 top)
//

float4x4 gWorldViewProjection : WORLDVIEWPROJECTION;
float3 gCameraPosition : CAMERAPOSITION;
float gTime : TIME;

float gScrollSpeed = 0.55;     // speed of the rising light bands
float gBandCount = 2.0;        // visible bands along the height
float gBaseStrength = 0.38;    // body gradient strength
float gRimStrength = 0.55;     // silhouette (fresnel) glow strength
float gBottomStrength = 0.75;  // bright base line strength

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

    // Horizontal normal of the cylinder from the angle coordinate
    float angle = PS.TexCoord.x * 6.2831853;
    float3 normal = float3(cos(angle), sin(angle), 0);
    float3 toCam = gCameraPosition - PS.WorldPos;
    float3 viewDir = normalize(float3(toCam.xy, 0.0001));
    float facing = abs(dot(normal, viewDir));
    float fresnel = pow(1.0 - facing, 2.0);

    // Smooth fade from the bottom to the top
    float fade = pow(1.0 - v, 1.7);

    float body = gBaseStrength * fade;
    float rim = gRimStrength * fresnel * fade;

    // Bright thin line at the base
    float bottom = gBottomStrength * (1.0 - smoothstep(0.0, 0.07, v));

    // Soft bands rising along the wall
    float bandPos = frac(v * gBandCount - gTime * gScrollSpeed);
    float band = exp(-pow((bandPos - 0.5) * 7.0, 2.0)) * 0.28 * fade;

    // Gentle breathing
    float breathe = 0.92 + 0.08 * sin(gTime * 2.2);

    float alpha = saturate((body + rim + bottom + band) * breathe) * PS.Diffuse.a;

    // Highlights lean slightly toward white, the hue stays the marker's own color
    float highlight = saturate(bottom * 0.45 + band * 0.6 + rim * 0.25);
    float3 color = lerp(PS.Diffuse.rgb, float3(1, 1, 1), highlight * 0.5);

    return float4(color, alpha);
}

technique marker_wall
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
