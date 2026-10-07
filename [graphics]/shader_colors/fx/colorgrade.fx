// shader_colors / colorgrade.fx
// Full-screen color grading pass. Every value is prepared on the CPU
// (c_main.lua) so the pixel shader stays a short, branch-free chain.

texture gScreen;

float3 gBalance    = float3(1, 1, 1); // exposure * white balance (luma-normalised)
float2 gLevels     = float2(0, 1);    // x = black point, y = 1 / (white - black)
float  gContrast   = 0;               // filmic S-curve blend, 0 = linear
float3 gLift       = float3(0, 0, 0); // shadow tint, zero-luma offset
float3 gGain       = float3(1, 1, 1); // highlight tint, unit-luma multiplier
float  gSaturation = 1;
float  gVibrance   = 0;
float  gSplit      = -1;              // left of this uv.x shows the original image

static const float3 LUMA = float3(0.2126, 0.7152, 0.0722);

sampler ScreenSampler = sampler_state
{
    Texture   = <gScreen>;
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
    AddressU  = Clamp;
    AddressV  = Clamp;
};

float3 BaseGrade(float3 c)
{
    c = saturate((c * gBalance - gLevels.x) * gLevels.y);
    float3 s = c * c * (3.0 - 2.0 * c);
    return saturate(lerp(c, s, gContrast));
}

float4 PSFull(float2 uv : TEXCOORD0) : COLOR0
{
    float3 src = tex2D(ScreenSampler, uv).rgb;
    float3 c = BaseGrade(src);

    float l = dot(c, LUMA);
    float sh = 1.0 - l;
    c = c + gLift * (sh * sh);
    c = c * lerp(float3(1, 1, 1), gGain, l * l);

    l = dot(c, LUMA);
    float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
    c = lerp(l.xxx, c, gSaturation + gVibrance * (1.0 - sat));

    c = lerp(saturate(c), src, step(uv.x, gSplit));
    return float4(c, 1);
}

float4 PSLite(float2 uv : TEXCOORD0) : COLOR0
{
    float3 src = tex2D(ScreenSampler, uv).rgb;
    float3 c = BaseGrade(src);
    c = lerp(dot(c, LUMA).xxx, c, gSaturation + gVibrance * 0.5);
    c = lerp(saturate(c), src, step(uv.x, gSplit));
    return float4(c, 1);
}

technique colorgrade_full
{
    pass P0
    {
        PixelShader = compile ps_2_0 PSFull();
    }
}

technique colorgrade_lite
{
    pass P0
    {
        PixelShader = compile ps_2_0 PSLite();
    }
}
