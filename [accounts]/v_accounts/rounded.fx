texture sourceTexture;

float radius;
float2 size;

sampler TextureSampler = sampler_state
{
    Texture = <sourceTexture>;
};

float4 main(float2 uv : TEXCOORD0) : COLOR0
{
    float2 px = uv * size;

    float2 tl = float2(radius, radius);
    float2 br = size - radius;

    float2 d = max(tl - px, px - br);
    float dist = length(max(d, 0));

    if (dist > radius)
        discard;

    return tex2D(TextureSampler, uv);
}

technique rounded
{
    pass P0
    {
        PixelShader = compile ps_2_0 main();
    }
}
