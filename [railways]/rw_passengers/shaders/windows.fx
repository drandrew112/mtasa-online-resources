// rw_passengers – coach windows (DESIGN.md 4.2)
//
// Applied to the world texture "mp_jet_wall" (only used by the Shamal cabin, jet_interior) while
// the local player rides a coach. Wall pixels keep the original texture; the painted window
// panes (bright, unsaturated pixels) show the outside: a ray from the camera through the pane is
// intersected with vertical "curtains" parallel to the track (far / mid / near layers) and the
// ground plane, so the view has real parallax when the player moves. The layers scroll with the
// distance the coach travelled (gScroll*, fractions of each layer's period, from Lua).

// ------------------------------------------------------------------ MTA state

float4x4 gWorldViewProjection : WORLDVIEWPROJECTION;
float4x4 gWorld : WORLD;
float3 gCameraPosition : CAMERAPOSITION;

int gLighting                 < string renderState="LIGHTING"; >;
float4 gGlobalAmbient         < string renderState="AMBIENT"; >;
int gDiffuseMaterialSource    < string renderState="DIFFUSEMATERIALSOURCE"; >;
int gAmbientMaterialSource    < string renderState="AMBIENTMATERIALSOURCE"; >;
int gEmissiveMaterialSource   < string renderState="EMISSIVEMATERIALSOURCE"; >;
float4 gMaterialAmbient       < string materialState="Ambient"; >;
float4 gMaterialDiffuse       < string materialState="Diffuse"; >;
float4 gMaterialEmissive      < string materialState="Emissive"; >;
texture gTexture0             < string textureState="0,Texture"; >;

// ------------------------------------------------------------------ parameters (Lua)

float gCentreX = 1.73;         // cabin centre line (x): + side = the coach's right
float gFloorZ = 1198.594;      // cabin floor (the floor is ~1.2 m above the rail)

float3 gLayerFar  = float3(250, 900, 80);    // distance from the window, period, height (m)
float3 gLayerMid  = float3(25, 220, 22);
float3 gLayerNear = float3(3.5, 60, 8);
float gScrollFar = 0;
float gScrollMid = 0;
float gScrollNear = 0;
float gScrollLamp = 0;         // tunnel lamps, period 25 m
float gBlur = 0;               // near layer motion blur (u offset per tap)

texture gFar0;  texture gMid0;  texture gNear0;
texture gFar1;  texture gMid1;  texture gNear1;
float gBlend = 0;              // 0 = set 0, 1 = set 1 (class change)
float3 gGround0 = float3(0.3, 0.3, 0.3);
float3 gGround1 = float3(0.3, 0.3, 0.3);
float gDepth0 = 0;             // the ground plane lies this much deeper (bridges)
float gDepth1 = 0;
float gTunnel = 0;             // 0..1 tunnel wall instead of the outside

float3 gSkyTop = float3(0.4, 0.6, 0.9);
float3 gSkyBot = float3(0.7, 0.8, 0.9);
float gLight = 1;              // daylight brightness 0.2 .. 1
float gNight = 0;              // 0 day .. 1 night (lit windows)
float gRain = 0;
float gTime = 0;

// ------------------------------------------------------------------ samplers

sampler BaseSampler = sampler_state { Texture = (gTexture0); };

// layers: wrap along the track, clamp in height
sampler2D Far0 = sampler_state { Texture = (gFar0); AddressU = Wrap; AddressV = Clamp; MinFilter = Linear; MagFilter = Linear; MipFilter = Linear; };
sampler2D Mid0 = sampler_state { Texture = (gMid0); AddressU = Wrap; AddressV = Clamp; MinFilter = Linear; MagFilter = Linear; MipFilter = Linear; };
sampler2D Near0 = sampler_state { Texture = (gNear0); AddressU = Wrap; AddressV = Clamp; MinFilter = Linear; MagFilter = Linear; MipFilter = Linear; };
sampler2D Far1 = sampler_state { Texture = (gFar1); AddressU = Wrap; AddressV = Clamp; MinFilter = Linear; MagFilter = Linear; MipFilter = Linear; };
sampler2D Mid1 = sampler_state { Texture = (gMid1); AddressU = Wrap; AddressV = Clamp; MinFilter = Linear; MagFilter = Linear; MipFilter = Linear; };
sampler2D Near1 = sampler_state { Texture = (gNear1); AddressU = Wrap; AddressV = Clamp; MinFilter = Linear; MagFilter = Linear; MipFilter = Linear; };

// ------------------------------------------------------------------ vertex shader

struct VSInput
{
    float3 Position : POSITION0;
    float4 Diffuse  : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

struct PSInput
{
    float4 Position : POSITION0;
    float4 Diffuse  : COLOR0;
    float2 TexCoord : TEXCOORD0;
    float3 WorldPos : TEXCOORD1;
};

// GTA building lighting, as in MTA's mta-helper.fx
float4 BuildingDiffuse(float4 inDiffuse)
{
    float4 outDiffuse;
    if (!gLighting)
    {
        outDiffuse = inDiffuse;
    }
    else
    {
        float4 ambient  = gAmbientMaterialSource  == 0 ? gMaterialAmbient  : inDiffuse;
        float4 diffuse  = gDiffuseMaterialSource  == 0 ? gMaterialDiffuse  : inDiffuse;
        float4 emissive = gEmissiveMaterialSource == 0 ? gMaterialEmissive : inDiffuse;
        outDiffuse = gGlobalAmbient * saturate(ambient + emissive);
        outDiffuse.a *= diffuse.a;
    }
    return outDiffuse;
}

PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;
    PS.Position = mul(float4(VS.Position, 1), gWorldViewProjection);
    PS.WorldPos = mul(float4(VS.Position, 1), gWorld).xyz;
    PS.TexCoord = VS.TexCoord;
    PS.Diffuse = BuildingDiffuse(VS.Diffuse);
    return PS;
}

// ------------------------------------------------------------------ outside

float4 SampleLayer(sampler2D s0, sampler2D s1, float2 uv)
{
    return lerp(tex2D(s0, uv), tex2D(s1, uv), gBlend);
}

float3 ApplyLayer(float3 col, sampler2D s0, sampler2D s1, float3 L, float scroll, float blur,
                  float3 ray, float outw, float eyeH, float along0, float sideOff, float dg)
{
    if (L.x >= dg) return col;                       // the ground is hit before this curtain
    float t = L.x / outw;
    float h = eyeH + ray.z * t;
    if (h < 0 || h > L.z) return col;
    float u = scroll + (along0 + ray.y * t) / L.y + sideOff;
    float v = 1 - h / L.z;
    float4 c = SampleLayer(s0, s1, float2(u, v));
    if (blur > 0.0001)
    {
        c += SampleLayer(s0, s1, float2(u + blur, v));
        c += SampleLayer(s0, s1, float2(u + blur * 2, v));
        c += SampleLayer(s0, s1, float2(u + blur * 3, v));
        c *= 0.25;
    }
    // lit windows: dark glass by day, lamps at night
    float lamp = step(0.9, c.r) * step(0.75, c.g) * step(c.b, 0.6);
    float3 lit = c.rgb * gLight;
    float3 glass = float3(0.22, 0.27, 0.33) * gLight;
    lit = lerp(lit, lerp(glass, c.rgb, gNight), lamp);
    float fog = saturate(L.x / 600) * (0.35 + 0.5 * gRain);
    lit = lerp(lit, gSkyBot, fog);
    return lerp(col, lit, c.a);
}

float Hash(float n) { return frac(sin(n * 12.9898) * 43758.5453); }

// ------------------------------------------------------------------ pixel shader

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    float4 base = tex2D(BaseSampler, PS.TexCoord);
    float4 wall = base * PS.Diffuse;

    // pane = the bright, unsaturated pixels of mp_jet_wall (frame wood is saturated / darker)
    float lum = dot(base.rgb, float3(0.3, 0.59, 0.11));
    float sat = max(max(base.r, base.g), base.b) - min(min(base.r, base.g), base.b);
    float mask = smoothstep(0.70, 0.80, lum) * (1 - smoothstep(0.06, 0.12, sat));
    if (mask < 0.003) return wall;

    float3 ray = normalize(PS.WorldPos - gCameraPosition);
    float side = PS.WorldPos.x >= gCentreX ? 1 : -1;
    float outw = max(ray.x * side, 0.03);            // outward component (glancing rays clamped)
    float eyeH = PS.WorldPos.z - gFloorZ + 1.2;      // height above the rail at the pane
    float sideOff = side > 0 ? 0 : 0.5;              // the two sides show different stretches
    float along0 = PS.WorldPos.y;                    // cabin +y = the coach's front

    // sky / ground
    float3 sky = lerp(gSkyBot, gSkyTop, saturate(ray.z * 1.6 + 0.25));
    float3 col = sky;
    float dg = 100000;
    if (ray.z < -0.001)
    {
        float depth = lerp(gDepth0, gDepth1, gBlend);
        dg = (eyeH + depth) / -ray.z * outw;
        float3 g = lerp(gGround0, gGround1, gBlend) * gLight;
        // ballast and sleepers right beside the track
        float t = dg / outw;
        float a = gScrollNear * 60 + along0 + ray.y * t;
        float sleeper = step(0.6, frac(a / 0.65)) * (1 - smoothstep(1.5, 3.0, dg));
        g = lerp(g, float3(0.32, 0.29, 0.26) * gLight, 1 - smoothstep(1.2, 4.0, dg));
        g *= 1 - sleeper * 0.35;
        col = lerp(g, gSkyBot, saturate(dg / 450) * (0.7 + 0.3 * gRain));
    }

    col = ApplyLayer(col, Far0, Far1, gLayerFar, gScrollFar, 0, ray, outw, eyeH, along0, sideOff, dg);
    col = ApplyLayer(col, Mid0, Mid1, gLayerMid, gScrollMid, 0, ray, outw, eyeH, along0, sideOff, dg);

    // tunnel wall 2.2 m out with lamps every 25 m
    if (gTunnel > 0.001)
    {
        float tt = 2.2 / outw;
        float th = eyeH + ray.z * tt;
        float ta = gScrollLamp + (along0 + ray.y * tt) / 25.0;
        float lampv = (1 - smoothstep(0.0, 0.03, abs(frac(ta) - 0.5))) * (1 - smoothstep(0.0, 0.5, abs(th - 3.6)));
        float3 wallc = float3(0.07, 0.07, 0.075) * (0.75 + 0.25 * Hash(floor(ta * 50)));
        float3 tun = wallc + float3(1.0, 0.85, 0.55) * lampv * 1.5;
        col = lerp(col, tun, gTunnel);
    }

    col = ApplyLayer(col, Near0, Near1, gLayerNear, gScrollNear, gBlur, ray, outw, eyeH, along0, sideOff, dg);

    // rain drops on the glass
    if (gRain > 0.01)
    {
        float2 p = floor(PS.TexCoord * 256 / 2);
        float d = step(0.975, Hash(p.x * 37 + p.y * 11 + floor(gTime * 0.5)));
        col = lerp(col, col * 0.6 + 0.2, d * gRain);
    }

    // a faint reflection of the cabin, stronger when it is dark outside
    col = lerp(col, float3(0.55, 0.45, 0.35) * PS.Diffuse.rgb, 0.05 + 0.2 * gNight * (1 - gTunnel * 0.5));

    return float4(lerp(wall.rgb, col, mask), wall.a);
}

technique windows
{
    pass P0
    {
        VertexShader = compile vs_3_0 VertexShaderFunction();
        PixelShader  = compile ps_3_0 PixelShaderFunction();
    }
}
