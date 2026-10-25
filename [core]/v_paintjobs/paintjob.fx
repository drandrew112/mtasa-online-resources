// v_paintjobs: replaces the texture only, GTA keeps its own lighting / reflections
texture gTexture;

technique TexReplace
{
    pass P0
    {
        Texture[0] = gTexture;
    }
}
