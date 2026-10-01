------------------------------------------------------------
-- JÁRMŰVEK
------------------------------------------------------------

-- csak ezeken a modelleken működik az ELS
sirenVehicles = {
    [416] = true, -- Ambulance
    [596] = true, -- Police LS
    [597] = true, -- Police SF
    [598] = true, -- Police LV
    [490] = true, -- FBI Rancher
}

DEFAULT_SIREN_TYPE = "fsvas320"

-- /elseditor minimum admin_level (v_mysql account data)
ELS_ADMIN_LEVEL = 1

------------------------------------------------------------
-- SZIRÉNA HANGOK
------------------------------------------------------------

sirenTypes = {
    fsvas320 = {
        sirens = {
            "sounds_fsvas320/SIREN_PA20A_WAIL.wav",
            "sounds_fsvas320/SIREN_2.wav",
            "sounds_fsvas320/POLICE_WARNING.wav",
        },
        horn = "sounds_fsvas320/AIRHORN_EQD.wav",
    },

    soundoff = {
        sirens = {
            "sounds_soundoff/SIREN_PA20A_WAIL.wav",
            "sounds_soundoff/SIREN_2.wav",
            "sounds_soundoff/POLICE_WARNING.wav",
        },
        horn = "sounds_soundoff/AIRHORN_EQD.wav",
    },

    hella_rtk7 = {
        sirens = {
            "sounds_rtk7/1.wav",
            "sounds_rtk7/2.wav",
            "sounds_rtk7/3.wav",
        },
        horn = "sounds_rtk7/horn.wav",
    },

    rumbler = {
        sirens = {
            "sounds_rumbler/SIREN_PA20A_WAIL.wav",
            "sounds_rumbler/SIREN_2.wav",
            "sounds_rumbler/POLICE_WARNING.wav",
        },
        horn = "sounds_soundoff/AIRHORN_EQD.wav",
    },

    italy = {
        sirens = {
            "sounds_italy/italy.wav",
        },
        horn = "sounds_soundoff/AIRHORN_EQD.wav",
    },

    eriston = {
        sirens = {
            "sounds_eriston150/3.wav",
            "sounds_eriston150/1.wav",
            "sounds_eriston150/2.wav",
        },
        horn = "sounds_eriston150/horn.wav",
    },

    dal = {
        sirens = {
            "sounds_dal/1.wav",
            "sounds_dal/2.wav",
            "sounds_dal/3.wav",
        },
        horn = "sounds_dal/horn.wav",
    },
}

------------------------------------------------------------
-- FÉNYEK
------------------------------------------------------------

-- A fénypontok elrendezése modellenként a lights.json-ban van (/elseditor írja).
-- Minden pont egy csoportba (A-D) tartozik; a villogási minta csoportonként
-- adja meg, mikor világít.

ELS_GROUPS = { "A", "B", "C", "D" }

-- Villogási minták. step = egy lépés hossza (ms), a szöveg minden karaktere egy
-- lépés: "1" = ég, "0" = nem ég. A hiányzó csoport nem világít.
ELS_PATTERNS = {
    { name = "Wig-wag",      step = 200,
      A = "10", B = "01", C = "10", D = "01" },
    { name = "Double flash", step = 70,
      A = "1010000000", B = "0000010100", C = "1010000000", D = "0000010100" },
    { name = "Quad flash",   step = 50,
      A = "1010101000000000", B = "0000000010101010", C = "1010101000000000", D = "0000000010101010" },
    { name = "Front / rear", step = 80,
      A = "1010000000", B = "1010000000", C = "0000010100", D = "0000010100" },
    { name = "Steady",       step = 100,
      A = "1", B = "1", C = "1", D = "1" },
}

-- szerkesztőben választható színek ({név, r, g, b})
ELS_COLORS = {
    { "Blue",  30,  60,  255 },
    { "Red",   255, 30,  30  },
    { "White", 255, 255, 255 },
    { "Amber", 255, 140, 0   },
    { "Green", 30,  255, 60  },
}

ELS_MAX_POINTS = 32
ELS_SIZE_MIN, ELS_SIZE_MAX = 0.05, 1.5

-- környezeti megvilágítás (dynamic_lighting resource, kliens)
ELS_ENV = {
    enabled        = true,
    maxVehicles    = 2,    -- egyszerre ennyi legközelebbi jármű világítja a környezetet
    perVehicle     = 2,    -- járművenként ennyi fényforrás (a legnépesebb csoportok)
    range          = 70,   -- ennél távolabbi jármű nem kap környezeti fényt (m)
    radius         = 14,   -- fény hatótáv (attenuation)
    intensity      = 1.0,
    sideOffset     = 0.8,  -- a fényforrás ennyivel kijjebb kerül a jármű oldalán (m)
    heightOffset   = 0.3,
}

------------------------------------------------------------
-- ELEMENT DATA
------------------------------------------------------------

-- jármű elementData kulcsok és a várt típusuk
SIREN_DATA_KEYS = {
    mkjState   = "boolean", -- fények
    sirenState = "boolean", -- sziréna hang
    sirenIndex = "number",  -- hang sorszáma a sirenTypes[type].sirens-ben
    sirenHorn  = "boolean", -- kürt (lenyomva tartva)
    sirenType  = "string",  -- sirenTypes kulcs
    elsPattern = "number",  -- ELS_PATTERNS index
}
