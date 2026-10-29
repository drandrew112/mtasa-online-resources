// Replaces the monitor model's screen texture with the static picture (client/screen.lua).
texture gTexture;

technique replace
{
    pass P0
    {
        Texture[0] = gTexture;
    }
}
