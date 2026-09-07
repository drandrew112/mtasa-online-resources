// light.fx - MTA-compatible HLSL shader
float4 gColor : COLOR;      // RGB szín (0-1)
float gIntensity = 1.0;     // fényerő
float gBlinkSpeed = 1.0;    // villogás sebesség
float gTime = 0.0;          // idő

sampler2D texture0 : register(s0);

struct PS_INPUT
{
    float2 tex : TEXCOORD0;
};

float4 ps_main(PS_INPUT IN) : COLOR
{
    // Alap textúra
    float4 texColor = tex2D(texture0, IN.tex);

    // Villogás: szinusz alapú
    float blink = (sin(gTime * gBlinkSpeed * 6.28318) * 0.5 + 0.5);

    // Emissive szín
    float4 emissive = gColor * blink * gIntensity;

    // Override: csak emissive szín jelenik meg
    float4 finalColor = emissive;

    finalColor = saturate(finalColor);

    return finalColor;
}


technique Default
{
    pass P0
    {
        PixelShader = compile ps_3_0 ps_main();
    }
}
