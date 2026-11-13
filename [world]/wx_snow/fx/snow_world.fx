//
// wx_snow :: snow_world.fx
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
float gRoad = 0;                 // 1 = road surface, 2 = plain asphalt shared with plazas / lots (road look only where the lane map has a lane)
float gSparkle = 1;              // 0 on low quality
float gBright = 1;               // overall snow brightness
float gDebug = 0;                // 1 = category colour view
float3 gDebugColor = float3(0.2, 0.45, 1.0);

texture gNoiseTex;
texture gMacroTex;               // tex/macro.png: 1024^2 tileable multi scale fbm, 256 m per repeat
float3 gSunDir = float3(0.35, 0.45, 0.8);   // world space, towards the sun (moon at night); client/ground.lua
float gSunWarm = 0;              // 0..1 sunrise / sunset tint
float3 gSky = float3(0.8, 0.86, 0.93);      // horizon colour: the wet road mirrors it

// roof map (client/roofmap.lua)
texture gRoofTex;
float4 gRoofRect = float4(-3072, -3072, 6144, 1536);   // minX, minY, size, cells
float3 gRoofZ = float3(-60, 1000, 1.6);                // zMin, zMax, tolerance
float gRoofOn = 0;

// F1 distance tiers (client/ground.lua, x0.6 on Low quality), metres from the camera:
// gLodRoof  x = roof map bilinear up to, y = roof map point sample up to (then ignored)
// gLodRoad  x = lane map fully on up to, y = lane map off from (blend between)
// gLodNoise x = finest noise octave up to, y = middle octave up to, z = sparkle up to
float2 gLodRoof = float2(80, 250);
float2 gLodRoad = float2(70, 110);
float3 gLodNoise = float3(100, 300, 30);

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

// junction layer (format 4, belongs to layer 1): gRoadJTex = window, per cell RG = texel offset of the
// cell's path list in gJListTex, B = list length, A = region (255 junction, 128 ring cell, 0; read bilinear).
// gJListTex: 2 path indices per texel (RG, BA). gJPathTex: 4 texels per path, T0 = origin cell i
// (bits 0-10) + type (11-12) + entry / exit noise frame flipped (13 / 14), j; T1..T3 = p0, p1, p2 of a
// quadratic Bezier, 16 bit, -gJRel..gJRel m from the corner of the origin cell.
#define JK 8                     // paths per cell at most (tools/build_roadmap.py K)
texture gRoadJTex;
texture gJPathTex;
texture gJListTex;
float4 gJSize = float4(1024, 1, 1024, 1);      // jpaths width, height, jlists width, height
float2 gRoadMin = float2(-3072, -3072);        // corner of the whole lane map (origin cells)
float gJRel = 64;
float gJOn = 0;

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

sampler SamplerMacro = sampler_state
{
    Texture = (gMacroTex);
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

sampler SamplerRoadJ = sampler_state
{
    Texture = (gRoadJTex);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
};

// the same texture, bilinear: only its A (junction mask) is used, a soft junction edge
sampler SamplerRoadJLin = sampler_state
{
    Texture = (gRoadJTex);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
};

sampler SamplerJPath = sampler_state
{
    Texture = (gJPathTex);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
};

sampler SamplerJList = sampler_state
{
    Texture = (gJListTex);
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

// dist < gLodRoof.x: 2x2 cells, bilinear on the covered result (soft 4 m edge, as before)
// dist < gLodRoof.y: one point sample (4 m steps are not visible from here)
// farther: not covered (the pixel is tiny and mostly in the fog)
float RoofCovered(float3 wp, float dist)
{
    if (gRoofOn < 0.5 || dist > gLodRoof.y) return 0;
    float2 uv = (wp.xy - gRoofRect.xy) / gRoofRect.z;
    if (uv.x < 0 || uv.y < 0 || uv.x > 1 || uv.y > 1) return 0;
    float texel = 1.0 / gRoofRect.w;
    float2 g = uv * gRoofRect.w - 0.5;
    float2 f = frac(g);
    float2 c = (floor(g) + 0.5) * texel;
    if (dist > gLodRoof.x)
    {
        float2 cp = (floor(uv * gRoofRect.w) + 0.5) * texel;
        return RoofCoveredAt(cp, wp.z);
    }
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

float Raw16(float hi, float lo)
{
    return floor(hi * 255 + 0.5) * 256 + floor(lo * 255 + 0.5);
}

// edgeD: metres from the nearest edge of the link (99 = no lane here), used for the snow banks
// jc: junction layer of the cell (only when the pixel is at the layer 1 height): x = list offset,
//     y = list length, z = region (bilinear: 1 junction, 0.5 ring, 0 outside)
float4 RoadLanes(float3 wp, out float edgeD, out float4 jc)
{
    edgeD = 99;
    jc = float4(0, 0, 0, 0);
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
    if (gJOn > 0.5 && abs(wp.z - z1) < 3.5)
    {
        float4 j = tex2Dlod(SamplerRoadJ, uv);
        float jm = tex2Dlod(SamplerRoadJLin, float4((wp.xy - gRoadRect.xy) / gRoadRect.z, 0, 0)).a;
        jc = float4(Raw16(j.r, j.g), floor(j.b * 255 + 0.5), jm, 0);
    }
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
    if (left + right < 0.5) return none;
    float med = floor(a8 / 16) * 0.5 * 2;          // full median width
    float leftW = left * 5;
    float width = (left + right) * 5 + med;
    float x = d + width * 0.5;                     // 0 = left edge of the link
    float inLeft = saturate(x * 4 + 1) * saturate((leftW - x) * 4 + 1) * step(0.5, left);
    float xr = x - leftW - med;
    float inRight = saturate(xr * 4 + 1) * saturate((right * 5 - xr) * 4 + 1) * step(0.5, right);
    float lf = x < leftW + med * 0.5 ? frac(max(x, 0) / 5) : frac(max(xr, 0) / 5);
    edgeD = min(x, width - x);
    return float4(lf, saturate(inLeft + inRight), -nrm.y, nrm.x);
}

//---------------------------------------------------------------------
// Junctions (format 4): the traffic paths of the cell's list, exact quadratic Beziers
//---------------------------------------------------------------------
float4 JTexel(sampler s, float idx, float2 size)
{
    float row = floor(idx / size.x);
    float col = idx - row * size.x;
    return tex2Dlod(s, float4((col + 0.5) / size.x, (row + 0.5) / size.y, 0, 0));
}

float2 JPoint(float4 t, float2 origin)
{
    return origin + float2(Raw16(t.r, t.g), Raw16(t.b, t.a)) / 65535.0 * 2 * gJRel - gJRel;
}

// the two lane noises (st1 = wobble, st2 = depth) in the lane frame of an arm: the very same samples the
// lanes of that arm take, so a track runs on from the arm into the junction without a jump
float2 JFrameNoise(float2 xy, float2 dWx, float2 dWy, float2 dir)
{
    float2 perp = float2(-dir.y, dir.x);
    float along = dot(xy, dir);
    float across = dot(xy, perp);
    float2 dAx = float2(dot(dWx, dir), dot(dWx, perp));
    float2 dAy = float2(dot(dWy, dir), dot(dWy, perp));
    float st1 = tex2Dgrad(SamplerNoise, float2(along * 0.011, across * 0.31),
                          dAx * float2(0.011, 0.31), dAy * float2(0.011, 0.31)).g;
    float st2 = tex2Dgrad(SamplerNoise, float2(along * 0.035 + 0.5, across * 1.7),
                          dAx * float2(0.035, 1.7), dAy * float2(0.035, 1.7)).b;
    return float2(st1, st2);
}

// -> x = wheel tracks, y = slush rim of the tracks, z = slush at the stop line (first metres of a path)
// Traffic weight: straight 1.0, right turn 0.7, left turn 0.5 (turn tracks also a little wider: the
// cars do not follow one line). The paths are combined with max: crossing tracks cross.
float3 JunctionTracks(float2 xy, float2 dWx, float2 dWy, float2 list, float mask, float pf)
{
    float3 res = float3(0, 0, 0);
    float cs = gRoadRect.z / gRoadRect.w;
    [loop] for (int k = 0; k < JK; k++)
    {
        if (k >= list.y) break;
        float4 le = JTexel(SamplerJList, list.x + floor(k * 0.5), gJSize.zw);
        float idx = fmod(k, 2) < 0.5 ? Raw16(le.r, le.g) : Raw16(le.b, le.a);
        float b4 = idx * 4;
        float4 t0 = JTexel(SamplerJPath, b4, gJSize.xy);
        float hi = Raw16(t0.r, t0.g);
        float2 origin = gRoadMin + float2(fmod(hi, 2048), Raw16(t0.b, t0.a)) * cs;
        float ptype = fmod(floor(hi / 2048), 4);
        float fa = fmod(floor(hi / 8192), 2);
        float fb = floor(hi / 16384);
        float2 p0 = JPoint(JTexel(SamplerJPath, b4 + 1, gJSize.xy), origin);
        float2 p1 = JPoint(JTexel(SamplerJPath, b4 + 2, gJSize.xy), origin);
        float2 p2 = JPoint(JTexel(SamplerJPath, b4 + 3, gJSize.xy), origin);

        // nearest point: projection on the chord, then 3 Newton steps on dot(B(t) - x, B'(t)) = 0
        float2 qa = p0 - 2 * p1 + p2;
        float2 qb = 2 * (p1 - p0);
        float2 ch = p2 - p0;
        float t = dot(xy - p0, ch) / max(dot(ch, ch), 0.01);
        [unroll] for (int n = 0; n < 3; n++)
        {
            float2 r = (qa * t + qb) * t + p0 - xy;
            float2 d1 = 2 * qa * t + qb;
            float f = dot(r, d1);
            float fp = dot(d1, d1) + 2 * dot(r, qa);
            t = clamp(t - f / max(fp, 0.05), -0.5, 1.5);
        }
        float2 bp = (qa * t + qb) * t + p0;
        float2 tg = normalize(2 * qa * t + qb + float2(0.00001, 0));
        float s = dot(xy - bp, float2(-tg.y, tg.x));
        float len = (length(ch) + length(p1 - p0) + length(p2 - p1)) * 0.5;
        float endF = 1 - smoothstep(0, 1, max(-t, t - 1) * len);
        [branch] if (abs(s) < 2.6 && endF > 0.001)
        {
            // noise in the frame of the entry arm, blended into the frame of the exit arm
            float2 tin = normalize(p1 - p0 + ch * 0.001 + float2(0.00001, 0));
            float2 tout = normalize(p2 - p1 + ch * 0.001 + float2(0.00001, 0));
            float bl = smoothstep(0.3, 0.7, t);
            float2 nA = float2(0.5, 0.5);
            float2 nB = float2(0.5, 0.5);
            [branch] if (bl < 0.999) nA = JFrameNoise(xy, dWx, dWy, fa > 0.5 ? -tin : tin);
            [branch] if (bl > 0.001) nB = JFrameNoise(xy, dWx, dWy, fb > 0.5 ? -tout : tout);
            float2 nz = lerp(nA, nB, bl);
            float w = ptype < 0.5 ? 1.0 : (ptype < 1.5 ? 0.7 : 0.5);
            float sp = ptype < 0.5 ? 0 : 0.012;
            float wob = (nz.x - 0.5) * 0.07;
            float lf = s / 5 + 0.5;
            float d1 = abs(lf - 0.32 - wob);
            float d2 = abs(lf - 0.68 - wob);
            float tr = max(1 - smoothstep(0.03 + sp, 0.085 + 2 * sp, d1), 1 - smoothstep(0.03 + sp, 0.085 + 2 * sp, d2));
            float arcT = saturate(t) * len;
            // the first / last metres lie on the lanes of the arm: fade in / out (a cross-fade, no seam)
            float g = w * endF * smoothstep(0, 4, arcT) * smoothstep(0, 4, len - arcT) * pf;
            res.x = max(res.x, saturate(tr * (0.6 + 0.6 * nz.y)) * g * (1 - 0.3 * mask));
            float dm = min(d1, d2);
            res.y = max(res.y, smoothstep(0.05, 0.1, dm) * (1 - smoothstep(0.1, 0.2, dm)) * g * (1 - smoothstep(2.0, 2.5, abs(s))));
            res.z = max(res.z, smoothstep(0.5, 2, arcT) * (1 - smoothstep(5, 7, arcT)) * (1 - smoothstep(1.8, 2.5, abs(s))) * 0.6);
        }
    }
    return res;
}

//---------------------------------------------------------------------
// Pixel shader
//
// F1 (speed, same picture as snow_world_v1.fx):
// 1. derivatives first (normal, texture / world coordinate gradients), then every texture read
//    inside branches uses tex2Dgrad / tex2Dlod with those gradients (no implicit derivative in
//    divergent flow).
// 2. early out: nothing to draw, farther than the fog end (the pixel is fog colour anyway) or a
//    surface that cannot hold snow / get wet (walls, undersides): no texture read, no noise.
// 3. distance tiers (gLod*): fine noise octaves, relief and sparkle are blurred away by the mip
//    chain far off anyway, lanes / roof map are only worth their taps near the camera.
// 4. the roof map / indoor boxes are only evaluated when the pixel would get snow or wetness.
//
// F2 / F3 (look):
// - no 23 m repeat: the big octaves come from tex/macro.png (256 m per repeat) read through a slow
//   domain warp, the second one rotated 31 degrees on an unrelated scale (common period >> view).
// - snow is a thickness: a threshold on the noise (+ a little of the surface brightness, so tufts
//   and cracks show through thin snow); thin edge = darker blue rim with the surface in it.
// - light: only the LUMINANCE of the GTA vertex light is used (its warm tint made the snow cream
//   coloured); shade goes blue, sunrise / sunset warm; micro relief lit by the sun direction.
// - roads: banks of pushed aside snow along the link edge, slush around the wheel tracks, the
//   wet tracks mirror the sky at a grazing angle.
//---------------------------------------------------------------------
static const float4 kMeanC = float4(0.532, 0.544, 0.505, 0.499);   // mean of the tex/noise.png channels

float4 NoiseG(float2 xy, float2 dx, float2 dy, float scale, float2 offs)
{
    return tex2Dgrad(SamplerNoise, xy * scale + offs, dx * scale, dy * scale);
}

float2 Rot31(float2 v)
{
    return float2(0.857 * v.x - 0.515 * v.y, 0.515 * v.x + 0.857 * v.y);
}

PSOutput PixelShaderFunction(PSInput PS)
{
    PSOutput output = (PSOutput)0;

    // derivatives first (before any branch / clip)
    float3 n = SurfaceNormal(PS.WorldPos, PS.Normal);
    float2 xy = PS.WorldPos.xy;
    float2 dWx = ddx(xy);
    float2 dWy = ddy(xy);
    float2 dTx = ddx(PS.TexCoord);
    float2 dTy = ddy(PS.TexCoord);
    float dist = PS.Dist;

    float up = saturate((n.z - gUpLo) / max(gUpHi - gUpLo, 0.01));
    float flat = saturate(n.z * 1.6 - 0.4);

    // early out
    bool fogged = gFogEnable && gFogEnd > 50 && dist > gFogEnd;
    bool wetPossible = gWet > 0 || gRoad > 0.5;
    bool candidate = gDebug > 0.5 || up > 0 || (wetPossible && flat > 0);
    [branch] if (gCoverage + gWet + gDebug < 0.0001 || fogged || !candidate)
    {
        clip(-1);
        return output;
    }

    float4 texel = tex2Dgrad(SamplerBase, PS.TexCoord, dTx, dTy);
    float baseAlpha = texel.a * PS.Diffuse.a;
    // see-through part of leaves, fences, grates: nothing to snow on
    clip(baseAlpha - 0.35);
    float lum = dot(texel.rgb, float3(0.3, 0.59, 0.11));

    // thickness noise: warp, big octave, rotated second octave (<gLodNoise.y), fine grain (<gLodNoise.x)
    float4 w0 = tex2Dgrad(SamplerMacro, xy * 0.0113 + 0.31, dWx * 0.0113, dWy * 0.0113);
    float2 q = xy + (w0.gb - 0.5) * 18;
    float4 n1 = tex2Dgrad(SamplerMacro, q * 0.0039, dWx * 0.0039, dWy * 0.0039);
    float4 n2 = float4(0.5, 0.5, 0.5, 0.5);
    float4 nC = kMeanC;
    [branch] if (dist < gLodNoise.y)
    {
        n2 = tex2Dgrad(SamplerMacro, Rot31(q) * 0.0171 + 0.57, Rot31(dWx) * 0.0171, Rot31(dWy) * 0.0171);
    }
    [branch] if (dist < gLodNoise.x) nC = NoiseG(xy, dWx, dWy, 1.1, 0.71);
    float noise = n1.r * 0.6 + n2.r * 0.3 + nC.b * 0.1;

    float c = gCoverage;
    float tt = noise * 0.82 + up * 0.12 + lum * 0.06 - (1 - c);   // > 0: snow, grows with depth

    // roads: traffic packs the middle of the lanes, two wheel tracks per lane down to the asphalt
    float tracks = 0;
    float packed = 0;
    float trackEdge = 0;
    float laneOn = 0;
    float roadMask = 0;
    float roadW = 0;                  // 0..1: how much of the road look this pixel gets
    [branch] if (gRoad > 0.5)
    {
        float edgeD;
        float4 rl = float4(0.5, 0, 1, 0);
        float4 jc = float4(0, 0, 0, 0);
        float lodF = 0;
        edgeD = 99;
        [branch] if (dist < gLodRoad.y)
        {
            rl = RoadLanes(PS.WorldPos, edgeD, jc);
            lodF = 1 - smoothstep(gLodRoad.x, gLodRoad.y, dist);
            rl.y *= lodF;
        }
        float lf = rl.x;
        float on = max(rl.y, 0);
        // junction region (bilinear = soft edges): jm = junction mask, the lanes of the link fade out from the
        // ring centre to the junction border; pf: the traffic paths fade in from the outer ring border
        float jm = smoothstep(0.51, 0.75, jc.z) * lodF;
        float pf = smoothstep(0.251, 0.5, jc.z);
        float2 dir = rl.zw;
        float2 perp = float2(-dir.y, dir.x);
        float along = dot(xy, dir);
        float across = dot(xy, perp);
        float2 dAx = float2(dot(dWx, dir), dot(dWx, perp));
        float2 dAy = float2(dot(dWy, dir), dot(dWy, perp));
        // streaks stretched along the road
        float st1 = tex2Dgrad(SamplerNoise, float2(along * 0.011, across * 0.31),
                              dAx * float2(0.011, 0.31), dAy * float2(0.011, 0.31)).g;
        float centre = 1 - abs(lf - 0.5) * 2;
        [branch] if (on > 0.001)
        {
            float st2 = tex2Dgrad(SamplerNoise, float2(along * 0.035 + 0.5, across * 1.7),
                                  dAx * float2(0.035, 1.7), dAy * float2(0.035, 1.7)).b;
            float st3 = tex2Dgrad(SamplerNoise, float2(along * 0.09 + 0.2, across * 4.5),
                                  dAx * float2(0.09, 4.5), dAy * float2(0.09, 4.5)).r;
            float wob = (st1 - 0.5) * 0.07;
            float d1 = abs(lf - 0.32 - wob);
            float d2 = abs(lf - 0.68 - wob);
            float t1 = 1 - smoothstep(0.03, 0.085, d1);
            float t2 = 1 - smoothstep(0.03, 0.085, d2);
            tracks = saturate(max(t1, t2) * (0.6 + 0.6 * st2) * (0.8 + 0.4 * st3)) * on;
            packed = on * smoothstep(0.1, 0.55, centre);
            float dm = min(d1, d2);
            trackEdge = on * smoothstep(0.05, 0.1, dm) * (1 - smoothstep(0.1, 0.2, dm));
        }
        // junction (format 4): the wheel tracks of the traffic paths through it, trodden snow between them,
        // slush at the stop lines
        [branch] if (jc.y > 0.5 || jm > 0.001)
        {
            float3 jt = float3(0, 0, 0);
            [branch] if (jc.y > 0.5) jt = JunctionTracks(xy, dWx, dWy, jc.xy, jm, pf) * lodF;
            float keepL = 1 - jm;
            tracks = max(tracks * keepL, jt.x);
            trackEdge = max(trackEdge * keepL, max(jt.y, jm * 0.3));
            packed = max(packed * keepL, max(jm * 0.85, jt.z));
            on *= keepL;
        }
        // gRoad 2: the surface is also used off the roads, so the road look follows the lane map
        // (faded out with the lane map LOD, back to the plain snow look)
        roadW = gRoad > 1.5 ? saturate(max(max(on, jm), max(tracks, packed))) : 1;
        laneOn = on + jm * 0.5;
        // a blizzard covers the tracks again
        float refill = smoothstep(0.9, 1.0, c);
        float roadSnow = c * (1 - packed * (0.5 - 0.3 * c)) * (1 - tracks * (0.97 - 0.45 * refill));
        // lane edges: ridges of pushed-aside snow; the verge of the link: a bank
        roadSnow += on * (1 - centre) * 0.25 * c;
        roadSnow += on * (1 - smoothstep(0.4, 3.2, edgeD)) * 0.22 * c;
        float mk = roadSnow * (0.65 + 0.7 * lerp(noise, st1, 0.5)) * 1.25;
        roadMask = saturate(mk);
    }
    float plainMask = smoothstep(-0.035, 0.055, tt);
    // no thin rim on roads: the tracks and the slush give the edges
    [branch] if (gRoad > 0.5) tt = lerp(tt, 1, roadW);
    float cg = saturate(c * 25);
    float mask = (gRoad > 0.5 ? lerp(plainMask, roadMask, roadW) : plainMask) * up * cg;

    // wet look where the snow is missing (flat-ish surfaces, not under roofs); wheel tracks are wet
    float wetness = max(gWet * 0.55, tracks * 0.7 * saturate(c * 4));

    // roof map / indoor boxes only where something would be drawn
    float covered = 0;
    float indoor = 0;
    [branch] if (mask + wetness * flat * (1 - mask) > 0.004 || gDebug > 0.5)
    {
        covered = RoofCovered(PS.WorldPos, dist);
        indoor = Indoor(PS.WorldPos);
    }
    float keep = (1 - covered) * (1 - indoor);
    mask *= keep;

    // snow albedo: thin = blue rim with the surface in it, thick = bright; slush where traffic runs
    float thick = smoothstep(0, 0.2, tt);
    float rimAmt = (1 - smoothstep(0, 0.07, tt)) * mask;       // only the very edge of the snow
    float3 body = float3(0.93, 0.95, 1.0) * (0.9 + 0.1 * nC.r);
    float3 rim = float3(0.74, 0.82, 0.93);
    float3 albedo = lerp(rim, body, smoothstep(0, 0.1, tt));
    albedo = lerp(albedo, texel.rgb * 0.6 + float3(0.2, 0.25, 0.32), rimAmt * 0.45);
    float3 slush = float3(0.56, 0.54, 0.51) * (0.85 + 0.15 * n2.g);
    albedo = lerp(albedo, slush, saturate(packed * 0.5 + trackEdge * 0.6 + tracks * 0.3));
    albedo *= (0.86 + 0.14 * n.z) * (0.93 + 0.07 * w0.r);

    // light: luminance of the GTA vertex light only, cool in the shade, warm at sunrise / sunset
    float lv = saturate(dot(PS.Diffuse.rgb, float3(0.3, 0.59, 0.11)) * 1.12);
    float3 tint = lerp(float3(1.0, 0.985, 0.96), float3(1.0, 0.8, 0.62), gSunWarm);
    float3 lightCol = lerp(float3(0.8, 0.86, 0.97), tint, saturate((lv - 0.12) / 0.4)) * lv * gBright;
    float3 lit = albedo * lightCol;

    // micro relief close to the camera (two extra taps), lit by the sun direction
    [branch] if (dist < gLodNoise.z * 1.3 && gSparkle > 0.5 && mask > 0.01)
    {
        float2 e = float2(0.12, 0);
        float h0 = NoiseG(xy, dWx, dWy, 0.25, 0.13).r;
        float hx = NoiseG(xy + e.xy, dWx, dWy, 0.25, 0.13).r;
        float hy = NoiseG(xy + e.yx, dWx, dWy, 0.25, 0.13).r;
        float3 rn = normalize(float3(-(hx - h0) / 0.12 * 0.3, -(hy - h0) / 0.12 * 0.3, 1));
        float diff = saturate(dot(rn, normalize(gSunDir)));
        float flatD = saturate(normalize(gSunDir).z);
        float k = thick * (1 - smoothstep(10, 36, dist)) * (1 - packed);
        lit *= lerp(1, (0.78 + 0.5 * diff) / (0.78 + 0.5 * flatD), k);
    }

    // sparkle up close (not on slush)
    [branch] if (gSparkle > 0.5 && dist < gLodNoise.z)
    {
        float sp = tex2Dgrad(SamplerNoise, xy * 6.3 + gCameraPosition.xy * 0.031, dWx * 6.3, dWy * 6.3).a;
        lit += step(0.985, sp) * saturate(1 - dist / 30) * 0.5 * lv * gSparkle * (1 - packed) * thick;
    }

    // wet surface: darker, and at a grazing angle it mirrors the sky
    float wetA = wetness * flat * keep * (1 - mask);
    float3 toCam = normalize(gCameraPosition - PS.WorldPos);
    float fres = pow(1 - saturate(dot(toCam, n)), 4);
    float3 wetCol = texel.rgb * PS.Diffuse.rgb * 0.5 + gSky * fres * 0.55 * lv;

    float alpha = mask + wetA;
    float3 color = (lit * mask + wetCol * wetA) / max(alpha, 0.001);

    if (gDebug > 0.5)
    {
        float3 dc = gDebugColor;
        if (covered > 0.5) dc = float3(0.7, 0.2, 0.9);
        if (indoor > 0.5) dc = float3(1.0, 0.9, 0.1);
        dc = lerp(dc, float3(0, 1, 0), laneOn * 0.5);      // green tint = the lane map knows this road
        dc = lerp(dc, float3(0, 0, 0), tracks);
        color = lerp(dc, float3(1, 1, 1), mask * 0.6);
        alpha = 0.6;
    }

    if (gFogEnable)
    {
        float fog = saturate((dist - gFogStart) / max(gFogEnd - gFogStart, 1));
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
