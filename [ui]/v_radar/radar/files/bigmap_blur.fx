texture ScreenSource;

sampler ScreenSampler = sampler_state
{
    Texture = <ScreenSource>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
    AddressU = Clamp;
    AddressV = Clamp;
};

float4 PixelShaderFunction(float2 uv : TEXCOORD0) : COLOR0
{
    // A small 3x3 Gaussian-style blur. Offsets are normalized screen-space
    // values, so the blur remains subtle and consistent at every resolution.
    const float2 offset = float2(0.0025, 0.0025);
    float4 color = tex2D(ScreenSampler, uv) * 4.0;
    color += tex2D(ScreenSampler, uv + float2(-offset.x, -offset.y));
    color += tex2D(ScreenSampler, uv + float2( offset.x, -offset.y));
    color += tex2D(ScreenSampler, uv + float2(-offset.x,  offset.y));
    color += tex2D(ScreenSampler, uv + float2( offset.x,  offset.y));
    return color / 8.0;
}

technique BigmapBlur
{
    pass P0
    {
        PixelShader = compile ps_2_0 PixelShaderFunction();
    }
}
