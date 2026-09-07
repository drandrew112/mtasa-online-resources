local streamURL = "https://goldenwest.leanstream.co/CKMWFM-MP3" -- country 88
function onResourceStart()
	
sound = playSound3D(streamURL, -2043.5, 161.39999389648, 29.39999961853, true) 
setSoundMaxDistance(sound, 100)
setSoundVolume(sound, 0.08)


end

addEventHandler("onClientResourceStart", getResourceRootElement(getThisResource()), onResourceStart)
