//
// wx_snow :: snow_world_v1.fx (the shader before the F1 speed-up, kept for A/B measuring: /snow shader v1)
//
// LAYERED world shader (dxCreateShader(..., layered = true, "world,object")): drawn as an extra
// alpha blended pass on top of whatever draws the texture (GTA, shader_detail, ...), so it never
// replaces another shader. dynamic_lighting's world shader is layered too and adds its lights.
//
// mask = upward facing (normal) x world space noise vs. coverage
//        x not under a roof (roof map) x not inside a maps_loader indoor box
// Where there is no snow, gWet darkens the surface a little (wet ground).
//

#define GENERATE_NORMALS
#include "mta-helper.fx"

//---------------------------------------------------------------------
// Settings (client/ground.lua)
//---------------------------------------------------------------------
float gCoverage = 0;             // 0..1, already multiplied by the category
float gWet = 0;                  // 0..1
float gUpLo = 0.6;               // normal z where snow starts
float gUpHi = 0.85;              // normal z where the surface is fully snowable
float gRoad = 0;                 // 1 = slush colour
float gSparkle = 1;              // 0 on low quality
float gBright = 1;               // overall snow brightness
float gDebug = 0;                // 1 = category colour view
float3 gDebugColor = float3(0.2, 0.45, 1.0);

texture gNoiseTex;

// roof map (client/roofmap.lua)
texture gRoofTex;
float4 gRoofRect = float4(-3072, -3072, 6144, 1536);   // minX, minY, size, cells
float3 gRoofZ = float3(-60, 1000, 1.6);                // zMin, zMax, tolerance
float gRoofOn = 0;

// lane map (tools/build_roadmap.py, format 3): per 4 m cell the line of its road link, two
// height layers (gRoadTex / gRoad2Tex) + their road heights (gRoadZTex: RG layer 1, BA layer 2).
// Line: RG = 16 bit distance of the cell centre from the centre line (+-gRoadDRange),
// B = normal angle, A = left lanes + right lanes * 4 + median half width / 0.5 * 16. Point sampled.
texture gRoadTex;
texture gRoad2Tex;
texture gRoadZTex;
float4 gRoadRect = float4(-3072, -3072, 6144, 1536);
float gRoadDRange = 32;
float2 gRoadZ = float2(-60, 1000);
float gRoadOn = 0;

// nearest maps_loader indoor boxes (unused ones are far away)
float3 gBox0Min = float3(-99999, -99999, -99999);
float3 gBox0Max = float3(-99998, -99998, -99998);
float3 gBox1Min = float3(-99999, -99999, -99999);
float3 gBox1Max = float3(-99998, -99998, -99998);
float3 gBox2Min = float3(-99999, -99999, -99999);
float3 gBox2Max = float3(-99998, -99998, -99998);
float3 gBox3Min = float3(-99999, -99999, -99999);
float3 gBox3Max = float3(-99998, -99998, -99998);

//---------------------------------------------------------------------
// Render states
//---------------------------------------------------------------------
int gFogEnable       < string renderState="FOGENABLE"; >;
float4 gFogColor     < string renderState="FOGCOLOR"; >;
float gFogStart      < string renderState="FOGSTART"; >;
float gFogEnd        < string renderState="FOGEND"; >;

//---------------------------------------------------------------------
// Samplers
//---------------------------------------------------------------------
sampler SamplerBase = sampler_state
{
    Texture = (gTexture0);
};

sampler SamplerNoise = sampler_state
{
    Texture = (gNoiseTex);
    AddressU = Wrap;
    AddressV = Wrap;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
};

sampler SamplerRoof = sampler_state
{
    Texture = (gRoofTex);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
};

sampler SamplerRoad = sampler_state
{
    Texture = (gRoadTex);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
};

sampler SamplerRoad2 = sampler_state
{
    Texture = (gRoad2Tex);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
};

sampler SamplerRoadZ = sampler_state
{
    Texture = (gRoadZTex);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
};

//---------------------------------------------------------------------
// Structures
//---------------------------------------------------------------------
struct VSInput
{
    float3 Position : POSITION0;
    float3 Normal : NORMAL0;
    float4 Diffuse : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

struct PSInput
{
    float4 Position : POSITION0;
    float4 Diffuse : COLOR0;
    float2 TexCoord : TEXCOORD0;
    float3 WorldPos : TEXCOORD1;
    float3 Normal : TEXCOORD2;
    float4 ViewPos : TEXCOORD3;
    float Dist : TEXCOORD4;
};

struct PSOutput
{
    float4 Color : COLOR0;
    float Depth : DEPTH;
};

//---------------------------------------------------------------------
// Layered depth (same bias as dynamic_lighting, so both layers sit on the surface)
//---------------------------------------------------------------------
float LayeredDepth(float4 viewPos)
{
    float depth = viewPos.z / viewPos.w;
    return depth * pow(1.00004, depth - (0.25 + (1 - depth * depth) * 50)) - 0.00014;
}

//---------------------------------------------------------------------
// Roof map: 1 = this world position is under the top surface of its cell
//---------------------------------------------------------------------
float RoofHeight(float2 uv)
{
    float4 t = tex2Dlod(SamplerRoof, float4(uv, 0, 0));
    float h16 = floor(t.r * 255 + 0.5) * 256 + floor(t.g * 255 + 0.5);
    return h16 / 65535.0 * (gRoofZ.y - gRoofZ.x) + gRoofZ.x;
}

float RoofCoveredAt(float2 uv, float z)
{
    return saturate((RoofHeight(uv) - gRoofZ.z - z) * 2);
}

float RoofCovered(float3 wp)
{
    if (gRoofOn < 0.5) return 0;
    float2 uv = (wp.xy - gRoofRect.xy) / gRoofRect.z;
    if (uv.x < 0 || uv.y < 0 || uv.x > 1 || uv.y > 1) return 0;
    // 2x2 cells, bilinear on the covered result (soft 4 m edge)
    float texel = 1.0 / gRoofRect.w;
    float2 g = uv * gRoofRect.w - 0.5;
    float2 f = frac(g);
    float2 c = (floor(g) + 0.5) * texel;
    float c00 = RoofCoveredAt(c, wp.z);
    float c10 = RoofCoveredAt(c + float2(texel, 0), wp.z);
    float c01 = RoofCoveredAt(c + float2(0, texel), wp.z);
    float c11 = RoofCoveredAt(c + float2(texel, texel), wp.z);
    return lerp(lerp(c00, c10, f.x), lerp(c01, c11, f.x), f.y);
}

//---------------------------------------------------------------------
// Indoor boxes
//---------------------------------------------------------------------
float InBox(float3 p, float3 mn, float3 mx)
{
    float3 a = step(mn, p) * step(p, mx);
    return a.x * a.y * a.z;
}

float Indoor(float3 p)
{
    return max(max(InBox(p, gBox0Min, gBox0Max), InBox(p, gBox1Min, gBox1Max)),
               max(InBox(p, gBox2Min, gBox2Max), InBox(p, gBox3Min, gBox3Max)));
}

//---------------------------------------------------------------------
// Vertex shader
//---------------------------------------------------------------------
PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;
    float3 normal = gDeclNormal == 1 ? VS.Normal : float3(0, 0, 1);
    float4 worldPos = mul(float4(VS.Position, 1), gWorld);
    PS.WorldPos = worldPos.xyz;
    PS.Normal = mul(normal, (float3x3)gWorld);
    PS.Position = mul(float4(VS.Position, 1), gWorldViewProjection);
    PS.ViewPos = PS.Position;
    PS.TexCoord = VS.TexCoord;
    PS.Diffuse = MTACalcGTABuildingDiffuse(VS.Diffuse);
    PS.Dist = distance(gCameraPosition, worldPos.xyz);
    return PS;
}

//---------------------------------------------------------------------
// Surface normal: the real face from the screen space derivatives of the world position
// (GTA buildings often have no / wrong vertex normals), turned toward the camera (a visible
// face always faces it, so a ceiling seen from below points down). The smooth vertex normal
// is used only where it agrees with the face (terrain stays smooth).
//---------------------------------------------------------------------
float3 SurfaceNormal(float3 worldPos, float3 vertexNormal)
{
    float3 toCam = gCameraPosition - worldPos;
    float3 fn = cross(ddx(worldPos), ddy(worldPos));
    float fl = length(fn);
    fn = fl > 1e-10 ? fn / fl : float3(0, 0, 1);
    if (dot(fn, toCam) < 0) fn = -fn;
    float3 vn = normalize(vertexNormal);
    if (dot(vn, toCam) < 0) vn = -vn;
    return dot(vn, fn) > 0.8 ? vn : fn;
}

//---------------------------------------------------------------------
// Lanes at a world position: x = position across the lane (0..1), y = on a lane (soft edge),
// zw = road direction. The layer whose road height matches the pixel is used (overpasses);
// the lateral distance is exact per pixel (line of the cell's link). A link's lanes - left
// lanes, median, right lanes - are centred on its line, 5 m each.
//---------------------------------------------------------------------
float Unpack16(float hi, float lo)
{
    return (floor(hi * 255 + 0.5) * 256 + floor(lo * 255 + 0.5)) / 65535.0;
}

float4 RoadLanes(float3 wp)
{
    float4 none = float4(0.5, 0, 1, 0);
    if (gRoadOn < 0.5) return none;
    float cells = gRoadRect.w;
    float cellSize = gRoadRect.z / cells;
    float2 idx = floor((wp.xy - gRoadRect.xy) / cellSize);
    if (idx.x < 0 || idx.y < 0 || idx.x >= cells || idx.y >= cells) return none;
    float4 uv = float4((idx + 0.5) / cells, 0, 0);

    // pick the height layer of this pixel
    float4 zz = tex2Dlod(SamplerRoadZ, uv);
    float zRange = gRoadZ.y - gRoadZ.x;
    float z1 = Unpack16(zz.r, zz.g) * zRange + gRoadZ.x;
    float z2 = Unpack16(zz.b, zz.a) * zRange + gRoadZ.x;
    float4 r1 = tex2Dlod(SamplerRoad, uv);
    float4 r2 = tex2Dlod(SamplerRoad2, uv);
    float4 r;
    if (r1.a > 0 && abs(wp.z - z1) < 3.5) r = r1;
    else if (r2.a > 0 && abs(wp.z - z2) < 3.5) r = r2;
    else return none;

    float a8 = floor(r.a * 255 + 0.5);
    float dc = Unpack16(r.r, r.g) * 2 * gRoadDRange - gRoadDRange;
    float ang = floor(r.b * 255 + 0.5) / 256.0 * 6.2831853;
    float2 nrm = float2(cos(ang), sin(ang));
    float2 centre = gRoadRect.xy + (idx + 0.5) * cellSize;
    float d = dc + dot(wp.xy - centre, nrm);

    float left = fmod(a8, 4);
    float right = fmod(floor(a8 / 4), 4);
    float med = floor(a8 / 16) * 0.5 * 2;          // full median width
    float leftW = left * 5;
    float width = (left + right) * 5 + med;
    float x = d + width * 0.5;                     // 0 = left edge of the link
    float inLeft = saturate(x * 4 + 1) * saturate((leftW - x) * 4 + 1) * step(0.5, left);
    float xr = x - leftW - med;
    float inRight = saturate(xr * 4 + 1) * saturate((right * 5 - xr) * 4 + 1) * step(0.5, right);
    float lf = x < leftW + med * 0.5 ? frac(max(x, 0) / 5) : frac(max(xr, 0) / 5);
    return float4(lf, saturate(inLeft + inRight), -nrm.y, nrm.x);
}

//---------------------------------------------------------------------
// Pixel shader
//---------------------------------------------------------------------
PSOutput PixelShaderFunction(PSInput PS)
{
    PSOutput output = (PSOutput)0;

    // derivatives first (before any clip)
    float3 n = SurfaceNormal(PS.WorldPos, PS.Normal);

    // nothing to draw (indoors / no snow): cheapest way out
    clip(gCoverage + gWet + gDebug - 0.0001);

    float4 texel = tex2D(SamplerBase, PS.TexCoord);
    float baseAlpha = texel.a * PS.Diffuse.a;
    // see-through part of leaves, fences, grates: nothing to snow on
    clip(baseAlpha - 0.35);

    float up = saturate((n.z - gUpLo) / max(gUpHi - gUpLo, 0.01));

    float2 xy = PS.WorldPos.xy;
    float4 nA = tex2D(SamplerNoise, xy * 0.043);
    float4 nB = tex2D(SamplerNoise, xy * 0.19 + 0.37);
    float4 nC = tex2D(SamplerNoise, xy * 1.1 + 0.71);
    float noise = nA.r * 0.6 + nB.g * 0.3 + nC.b * 0.1;

    float c = gCoverage;
    float edge = 0.11;
    float mask = smoothstep(1 - c - edge, 1 - c + edge, noise * 0.85 + up * 0.15) * up * saturate(c * 25);

    // roads: traffic packs the middle of the lanes, two wheel tracks per lane down to the asphalt
    float tracks = 0;
    float packed = 0;
    if (gRoad > 0.5)
    {
        float4 rl = RoadLanes(PS.WorldPos);
        float lf = rl.x;
        float on = rl.y;
        float2 dir = rl.zw;
        float2 perp = float2(-dir.y, dir.x);
        float along = dot(xy, dir);
        float across = dot(xy, perp);
        // streaks stretched along the road
        float st1 = tex2D(SamplerNoise, float2(along * 0.011, across * 0.31)).g;
        float st2 = tex2D(SamplerNoise, float2(along * 0.035 + 0.5, across * 1.7)).b;
        float st3 = tex2D(SamplerNoise, float2(along * 0.09 + 0.2, across * 4.5)).r;
        float wob = (st1 - 0.5) * 0.07;
        float t1 = 1 - smoothstep(0.03, 0.085, abs(lf - 0.32 - wob));
        float t2 = 1 - smoothstep(0.03, 0.085, abs(lf - 0.68 - wob));
        tracks = saturate(max(t1, t2) * (0.6 + 0.6 * st2) * (0.8 + 0.4 * st3)) * on;
        float centre = 1 - abs(lf - 0.5) * 2;
        packed = on * smoothstep(0.1, 0.55, centre);
        // a blizzard covers the tracks again
        float refill = smoothstep(0.9, 1.0, c);
        float roadSnow = c * (1 - packed * (0.5 - 0.3 * c)) * (1 - tracks * (0.97 - 0.45 * refill));
        // lane edges: ridges of pushed-aside snow
        roadSnow += on * (1 - centre) * 0.25 * c;
        mask = saturate(roadSnow * (0.65 + 0.7 * lerp(noise, st1, 0.5)) * 1.25) * up * saturate(c * 25);
    }

    float covered = RoofCovered(PS.WorldPos);
    float indoor = Indoor(PS.WorldPos);
    float keep = (1 - covered) * (1 - indoor);
    mask *= keep;

    // snow colour: bright, slightly blue; grey slush where traffic runs
    float3 snow = float3(0.93, 0.95, 1.0) * (0.9 + 0.1 * nC.r);
    float3 slush = float3(0.62, 0.63, 0.64) * (0.85 + 0.15 * nB.r);
    snow = lerp(snow, slush, saturate(packed * 0.55 + tracks * 0.5));
    // shading: flat = brightest, drifts, a little of the surface showing through thin snow
    float lum = dot(texel.rgb, float3(0.3, 0.59, 0.11));
    float thin = 1 - saturate(mask * 1.5 - 0.3);
    snow *= (0.86 + 0.14 * n.z) * (0.93 + 0.07 * nA.g);
    snow *= lerp(1, 0.7 + 0.6 * lum, 0.1 + 0.3 * thin);
    float3 lit = snow * saturate(PS.Diffuse.rgb * 1.08) * gBright;

    // sparkle up close (not on slush)
    float sp = tex2D(SamplerNoise, xy * 6.3 + gCameraPosition.xy * 0.031).a;
    lit += step(0.985, sp) * saturate(1 - PS.Dist / 30) * 0.5 * saturate(PS.Diffuse.rgb) * gSparkle * (1 - packed);

    // wet look where the snow is missing (flat-ish surfaces, not under roofs); wheel tracks are wet
    float flat = saturate(n.z * 1.6 - 0.4);
    float wetness = max(gWet * 0.55, tracks * 0.7 * saturate(c * 4));
    float wetA = wetness * flat * keep * (1 - mask);
    float3 wetCol = texel.rgb * PS.Diffuse.rgb * 0.5;

    float alpha = mask + wetA;
    float3 color = (lit * mask + wetCol * wetA) / max(alpha, 0.001);

    if (gDebug > 0.5)
    {
        float3 dc = gDebugColor;
        if (covered > 0.5) dc = float3(0.7, 0.2, 0.9);
        if (indoor > 0.5) dc = float3(1.0, 0.9, 0.1);
        dc = lerp(dc, float3(0, 0, 0), tracks);
        color = lerp(dc, float3(1, 1, 1), mask * 0.6);
        alpha = 0.6;
    }

    if (gFogEnable)
    {
        float fog = saturate((PS.Dist - gFogStart) / max(gFogEnd - gFogStart, 1));
        color = lerp(color, gFogColor.rgb, fog);
    }

    alpha = saturate(alpha) * baseAlpha;
    clip(alpha - 0.004);
    output.Color = float4(saturate(color), alpha);
    output.Depth = LayeredDepth(PS.ViewPos);
    return output;
}

//---------------------------------------------------------------------
// Technique (no fallback: without ps_3_0 the shader is not created and wx_snow says so)
//---------------------------------------------------------------------
technique snow_world
{
    pass P0
    {
        AlphaBlendEnable = TRUE;
        SrcBlend = SRCALPHA;
        DestBlend = INVSRCALPHA;
        ZWriteEnable = FALSE;
        VertexShader = compile vs_3_0 VertexShaderFunction();
        PixelShader = compile ps_3_0 PixelShaderFunction();
    }
}
