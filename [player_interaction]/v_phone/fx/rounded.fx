// Rounded-corner mask for dxDrawImage.
//   sourceTexture : the image (use a 1x1 white texture for solid fills)
//   size          : the on-screen draw size in pixels  { width, height }
//   radius        : corner radius in the same pixel units
// The draw colour passed to dxDrawImage is applied as a tint.

texture sourceTexture;
float  radius;
float2 size;

sampler TextureSampler = sampler_state
{
    Texture   = <sourceTexture>;
    AddressU  = Clamp;
    AddressV  = Clamp;
};

struct PSInput
{
    float2 uv      : TEXCOORD0;
    float4 diffuse : COLOR0;
};

float4 main(PSInput input) : COLOR0
{
    float2 px = input.uv * size;

    float2 tl = float2(radius, radius);
    float2 br = size - radius;

    float2 d    = max(tl - px, px - br);
    float  dist = length(max(d, 0));

    // 1px feather so the corners aren't jagged
    float alpha = 1.0 - smoothstep(radius - 1.0, radius + 1.0, dist);
    if (alpha <= 0.0)
        discard;

    float4 col = tex2D(TextureSampler, input.uv) * input.diffuse;
    col.a *= alpha;
    return col;
}

technique rounded
{
    pass P0
    {
        PixelShader = compile ps_2_0 main();
    }
}
