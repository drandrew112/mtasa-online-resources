-- Proximity voice settings (shared by server and client).
VOICE = {
	RANGE = 30,              -- m, beyond this a speaker is silent (same as v_chat local channel)
	BROADCAST_MARGIN = 5,    -- m, the server keeps sending a bit past RANGE so the fade-out is not cut off
	FULL_VOLUME_RANGE = 6,   -- m, closer than this the speaker is at full volume
	SERVER_UPDATE_MS = 500,  -- how often the server rebuilds who hears whom
	CLIENT_UPDATE_MS = 50,   -- how often the client recalculates volume / pan of speakers
	OCCLUDED_VOLUME = 0.45,  -- volume multiplier when a building is between us and the speaker
	GAIN = 10,                -- overall voice loudness multiplier on top of the distance fade (1 = old level)
	PAN_STRENGTH = 0.7,      -- 0 = mono, 1 = full left / right panning by direction
	VEHICLE_SHARED = true,   -- players in the same vehicle always hear each other at full volume
	BLOCK_MUTED = true,      -- players muted in v_chat (mute_until element data) cannot talk either
}

-- Radio (radio/): players on the same frequency hear each other while one of them holds RADIO.KEY.
-- Frequencies are set by other resources through exports (setPlayerRadioFrequency); the agency
-- watcher (radio/agencies.lua) puts EMS / police on duty on their own channel.
RADIO = {
	KEY = "x",               -- push to talk (hold)
	INTRO_MS = 1170,         -- length of sounds/intro.wav: listeners hear it first, the voice is routed only after it
	SFX_VOLUME = 0.6,        -- push / release / intro / outro volume
	STATIC_VOLUME = 0.1,     -- static loop under an incoming transmission
	VOICE_VOLUME = 1,        -- radio voice volume multiplier (on top of VOICE.GAIN), no distance fade or pan
	SPEAKER_HOLD_MS = 2500,  -- the last speaker's name stays on the radar this long after the transmission ends
	-- any of these local player element data blocks the radio key (typing in chat / a text field)
	BLOCK_DATA = { "showChatInput", "textInputOpen" },

	-- agency watcher: work duty (work_core work.id) -> frequency; unit = the unit the player is signed in to
	AGENCY_UPDATE_MS = 2000,
	AGENCIES = {
		{ id = "ems",    work = "ems",    freq = 104, tag = "EMS" },
		{ id = "police", work = "police", freq = 107, tag = "PD" },
	},
}
