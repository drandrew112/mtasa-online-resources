-- Proximity voice settings (shared by server and client).
VOICE = {
	RANGE = 30,              -- m, beyond this a speaker is silent (same as v_chat local channel)
	BROADCAST_MARGIN = 5,    -- m, the server keeps sending a bit past RANGE so the fade-out is not cut off
	FULL_VOLUME_RANGE = 4,   -- m, closer than this the speaker is at full volume
	SERVER_UPDATE_MS = 500,  -- how often the server rebuilds who hears whom
	CLIENT_UPDATE_MS = 50,   -- how often the client recalculates volume / pan of speakers
	OCCLUDED_VOLUME = 0.45,  -- volume multiplier when a building is between us and the speaker
	PAN_STRENGTH = 0.7,      -- 0 = mono, 1 = full left / right panning by direction
	VEHICLE_SHARED = true,   -- players in the same vehicle always hear each other at full volume
	BLOCK_MUTED = true,      -- players muted in v_chat (mute_until element data) cannot talk either
}
