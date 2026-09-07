

-- voice
addEventHandler( 'onPlayerVoiceStart', getRootElement(),
    function()
        setElementData(source, "voice", true)
    end
)
addEventHandler( 'onPlayerVoiceStop', getRootElement(),
    function()
        setElementData(source, "voice", false)
    end
)

