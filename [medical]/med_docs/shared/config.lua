-- med_docs - medical documents (MySQL med_docs). Every document is stored structured (codes, keys,
-- numbers) with the author's language code; the free text stays as it was typed, everything coded
-- (BNO, interventions, field names) is shown in the viewer's language.

DOCS = {
    TABLE = "med_docs",
    -- document types: number prefix and who may read them (staff = hospital staff on duty)
    TYPES = {
        amb      = { prefix = "AL" },   -- Ambuláns lap (ER case sheet)
        lab      = { prefix = "LB" },   -- Labor lelet
        ct       = { prefix = "CT" },   -- CT lelet
        xray     = { prefix = "RX" },   -- Röntgen lelet
        fast     = { prefix = "UH" },   -- Ultrahang (FAST) lelet
        ecg      = { prefix = "EK" },   -- EKG lelet
        ems      = { prefix = "ML" },   -- Mentési lap (EMS case sheet)
        op       = { prefix = "MU" },   -- Műtéti leírás
        death    = { prefix = "HV" },   -- Halottvizsgálati bizonyítvány
    },
    VERSIONED = { amb = true, ems = true },   -- a new document of the same case = a new version
    LIST_LIMIT = 60,                    -- documents in one list answer
    EMS_CHIEF_COMPETENCY = "e",         -- work_ems rank that may read every EMS case sheet
    PAPER_FONT = "client/fonts/Tinos-Regular.ttf",   -- serif paper font with Hungarian accents (SIL OFL 1.1)
    PAPER_FONT_BOLD = "client/fonts/Tinos-Bold.ttf",
}
