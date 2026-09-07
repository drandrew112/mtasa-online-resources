
sirenVehicles = {
    [416] = true, -- Ambulance
    [596] = true, -- Police LS
    [597] = true, -- Police SF
    [598] = true, -- Police LV
    [490] = true, -- FBI Rancher
}

sirenTypes = {
    fsvas320 = {
        sirens = {
            "sounds_fsvas320/SIREN_PA20A_WAIL.wav",
            "sounds_fsvas320/SIREN_2.wav",
            "sounds_fsvas320/POLICE_WARNING.wav",
        },
        horn = "sounds_fsvas320/AIRHORN_EQD.wav"
    },

    soundoff = {
        sirens = {
            "sounds_soundoff/SIREN_PA20A_WAIL.wav",
            "sounds_soundoff/SIREN_2.wav",
            "sounds_soundoff/POLICE_WARNING.wav",
        },
        horn = "sounds_soundoff/AIRHORN_EQD.wav"
    },

    hella_rtk7 = {
        sirens = {
            "sounds_rtk7/1.wav",
            "sounds_rtk7/2.wav",
            "sounds_rtk7/3.wav",
        },
        horn = "sounds_rtk7/horn.wav"
    },

    italy = {
        sirens = {
            "sounds_fsvas320/italy.wav",
        },
        horn = "sounds_soundoff/AIRHORN_EQD.wav"
    },

    eriston = {
        sirens = {
            "sounds_eriston150/3.wav",
            "sounds_eriston150/1.wav",
            "sounds_eriston150/2.wav",
        },
        horn = "sounds_eriston150/horn.wav"
    },

    dal = {
        sirens = {
            "sounds_dal/1.wav",
            "sounds_dal/2.wav",
            "sounds_dal/3.wav",
        },
        horn = "sounds_dal/horn.wav"
    },
}

vehicleLights = {
    [416] = { -- mentő
        { offset = {0.3,    3,    0}, color = {30,30,255} },
        { offset = {-0.3,   3,    0}, color = {30,30,255} },

        { offset = {0.5,    1.2,    1.6}, color = {30,30,255} },
        { offset = {-0.5,   1.2,    1.6}, color = {255,30,30} },

        { offset = {0.5,    -2.9,    1.6}, color = {30,30,255} },
        { offset = {-0.5,   -2.9,    1.6}, color = {30,30,255} },
    }
}
