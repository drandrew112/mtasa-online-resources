-- ER supplies (plan: Felszerelés és mennyiségek). Pools: shock room (both bays + the drug cabinet and
-- the blood fridge), wound room, cast room, CT, and the nurses' station (corridor, ward, ICU, X-ray:
-- the blood draw cart and the basics). Devices do not run out; consumables are used by the
-- interventions (medsys categories: drugs, ivKits, fluids, bandages, splints, airwayKits) and come back
-- with an order (30 s, everything that was missing at the time of the order).
--
-- item = { id, cat (medsys stock category or "hosp"), drug (medsys drug id), amount, device, price }

ERC.STOCK = {
    shock = {
        { id = "monitor", device = true, amount = 2 }, { id = "ventilator", device = true, amount = 2 },
        { id = "wall_o2", device = true, amount = 2 }, { id = "infusion_pump", device = true, amount = 4 },
        { id = "ultrasound", device = true, amount = 2 }, { id = "ecg12", device = true, amount = 2 },
        { id = "videolaryngoscope", device = true, amount = 2 }, { id = "rapid_infuser", device = true, amount = 2 },
        { id = "cannula", cat = "ivKits", amount = 16, price = 4 },
        { id = "isolyte", cat = "fluids", amount = 16, price = 6 },
        { id = "saline", cat = "hosp", amount = 12, price = 5 },
        { id = "intubation_kit", cat = "airwayKits", amount = 4, price = 40 },
        { id = "chest_drain_kit", cat = "hosp", amount = 4, price = 60 },
        { id = "decompression_needle", cat = "hosp", amount = 4, price = 15 },
        { id = "pelvic_binder", cat = "hosp", amount = 2, price = 80 },
        { id = "sterile_dressing", cat = "bandages", amount = 16, price = 3 },
        { id = "burn_dressing", cat = "hosp", amount = 4, price = 16 },
        { id = "abg_syringe", cat = "hosp", amount = 8, price = 6 },
        { id = "ecg_electrodes", cat = "hosp", amount = 8, price = 4 },
        { id = "splint", cat = "splints", amount = 6, price = 12 },
        -- drug cabinet (medsys drug ids; the hospital drugs come with medsys/hospital)
        { id = "epinephrine", cat = "drugs", drug = "epinephrine", amount = 10, price = 5 },
        { id = "adenosine", cat = "drugs", drug = "adenosine", amount = 6, price = 12 },
        { id = "ketamine", cat = "drugs", drug = "ketamine", amount = 6, price = 15 },
        { id = "rocuronium", cat = "drugs", drug = "rocuronium", amount = 6, price = 20 },
        { id = "midazolam", cat = "drugs", drug = "midazolam", amount = 6, price = 6 },
        { id = "fentanyl", cat = "drugs", drug = "fentanyl", amount = 8, price = 8 },
        { id = "naloxone", cat = "drugs", drug = "naloxone", amount = 4, price = 10 },
        { id = "glucose", cat = "drugs", drug = "glucose", amount = 4, price = 3 },
        { id = "insulin", cat = "drugs", drug = "insulin", amount = 2, price = 10 },
        { id = "nitroglycerin", cat = "drugs", drug = "nitroglycerin", amount = 2, price = 6 },
        { id = "salbutamol", cat = "drugs", drug = "salbutamol", amount = 4, price = 5 },
        { id = "captopril", cat = "drugs", drug = "captopril", amount = 4, price = 3 },
        { id = "amiodarone", cat = "drugs", drug = "amiodarone", amount = 6, price = 9 },
        { id = "atropine", cat = "drugs", drug = "atropine", amount = 6, price = 4 },
        { id = "noradrenaline", cat = "drugs", drug = "noradrenaline", amount = 4, price = 12 },
        { id = "propofol", cat = "drugs", drug = "propofol", amount = 4, price = 14 },
        { id = "morphine", cat = "drugs", drug = "morphine", amount = 6, price = 6 },
        { id = "flumazenil", cat = "drugs", drug = "flumazenil", amount = 2, price = 25 },
        { id = "txa", cat = "drugs", drug = "txa", amount = 4, price = 18 },
        { id = "alteplase", cat = "drugs", drug = "alteplase", amount = 1, price = 600 },
        { id = "aspirin", cat = "drugs", drug = "aspirin", amount = 2, price = 2 },
        { id = "clopidogrel", cat = "drugs", drug = "clopidogrel", amount = 2, price = 6 },
        { id = "heparin", cat = "drugs", drug = "heparin", amount = 2, price = 8 },
        { id = "ceftriaxone", cat = "drugs", drug = "ceftriaxone", amount = 4, price = 9 },
        { id = "calcium", cat = "drugs", drug = "calcium", amount = 4, price = 4 },
        { id = "bicarbonate", cat = "drugs", drug = "bicarbonate", amount = 4, price = 5 },
        -- blood fridge: emergency units (bt_stock, transfusion module)
        { id = "rbc_0neg", cat = "blood", amount = 4, price = 0 },
        { id = "ffp_ab", cat = "blood", amount = 2, price = 0 },
    },
    wound = {
        { id = "irrigation_saline", cat = "hosp", amount = 10, price = 3 },
        { id = "povidone", cat = "hosp", amount = 6, price = 4 },
        { id = "lidocaine", cat = "drugs", drug = "lidocaine", amount = 10, price = 3 },
        { id = "suture_kit", cat = "hosp", amount = 8, price = 14 },
        { id = "sterile_dressing", cat = "bandages", amount = 15, price = 3 },
        { id = "burn_dressing", cat = "hosp", amount = 6, price = 16 },
        { id = "steristrip", cat = "hosp", amount = 10, price = 2 },
        { id = "skin_glue", cat = "hosp", amount = 4, price = 9 },
        { id = "tetanus", cat = "drugs", drug = "tetanus", amount = 6, price = 7 },
        { id = "sterile_gloves", cat = "hosp", amount = 20, price = 1 },
    },
    cast = {
        { id = "plaster", cat = "hosp", amount = 20, price = 4 },
        { id = "synthetic_splint", cat = "splints", amount = 10, price = 15 },
        { id = "padding", cat = "hosp", amount = 15, price = 2 },
        { id = "elastic_bandage", cat = "bandages", amount = 15, price = 2 },
        { id = "sling", cat = "hosp", amount = 6, price = 5 },
        { id = "lidocaine", cat = "drugs", drug = "lidocaine", amount = 4, price = 3 },
    },
    ct = {
        { id = "contrast", cat = "hosp", amount = 6, price = 30 },
        { id = "injector_set", cat = "hosp", amount = 6, price = 10 },
        { id = "cannula", cat = "ivKits", amount = 4, price = 4 },
    },
    nurse = {   -- nurses' station: the blood draw cart and the basics for the corridor / ward / ICU
        { id = "monitor", device = true, amount = 3 }, { id = "glucometer", device = true, cat = "glucometers", amount = 2 },
        { id = "tourniquet", device = true, amount = 4 }, { id = "wall_o2", device = true, amount = 8 },
        { id = "tube_blue", cat = "hosp", amount = 20, price = 1 }, { id = "tube_red", cat = "hosp", amount = 20, price = 1 },
        { id = "tube_green", cat = "hosp", amount = 10, price = 1 }, { id = "tube_purple", cat = "hosp", amount = 20, price = 1 },
        { id = "tube_grey", cat = "hosp", amount = 10, price = 1 }, { id = "blood_culture", cat = "hosp", amount = 6, price = 8 },
        { id = "abg_syringe", cat = "hosp", amount = 4, price = 6 },   -- ABG in the ICU
        { id = "draw_needle", cat = "hosp", amount = 20, price = 1 }, { id = "butterfly", cat = "hosp", amount = 10, price = 2 },
        { id = "alcohol_swab", cat = "hosp", amount = 40, price = 0.2 }, { id = "plaster_strip", cat = "hosp", amount = 20, price = 0.2 },
        { id = "cannula", cat = "ivKits", amount = 12, price = 4 },
        { id = "isolyte", cat = "fluids", amount = 10, price = 6 },
        { id = "sterile_dressing", cat = "bandages", amount = 12, price = 3 },
        { id = "burn_dressing", cat = "hosp", amount = 4, price = 16 },   -- burns are dressed anywhere (no room)
        { id = "splint", cat = "splints", amount = 6, price = 12 },
        { id = "intubation_kit", cat = "airwayKits", amount = 1, price = 40 },
        { id = "epinephrine", cat = "drugs", drug = "epinephrine", amount = 6, price = 5 },
        { id = "glucose", cat = "drugs", drug = "glucose", amount = 4, price = 3 },
        { id = "glucose_gel", cat = "drugs", drug = "glucose_gel", amount = 4, price = 2 },
        { id = "naloxone", cat = "drugs", drug = "naloxone", amount = 2, price = 10 },
        { id = "salbutamol", cat = "drugs", drug = "salbutamol", amount = 4, price = 5 },
        { id = "metamizole", cat = "drugs", drug = "metamizole", amount = 8, price = 2 },
        { id = "morphine", cat = "drugs", drug = "morphine", amount = 4, price = 6 },
        { id = "ondansetron", cat = "drugs", drug = "ondansetron", amount = 6, price = 3 },
        { id = "fentanyl", cat = "drugs", drug = "fentanyl", amount = 4, price = 8 },
        { id = "midazolam", cat = "drugs", drug = "midazolam", amount = 2, price = 6 },
        { id = "nitroglycerin", cat = "drugs", drug = "nitroglycerin", amount = 2, price = 6 },
        { id = "aspirin", cat = "drugs", drug = "aspirin", amount = 2, price = 2 },
        { id = "captopril", cat = "drugs", drug = "captopril", amount = 2, price = 3 },
        { id = "insulin", cat = "drugs", drug = "insulin", amount = 2, price = 10 },
        { id = "tetanus", cat = "drugs", drug = "tetanus", amount = 4, price = 7 },
        { id = "ceftriaxone", cat = "drugs", drug = "ceftriaxone", amount = 2, price = 9 },
    },
}
ERC.STOCK_ORDER_TIME = 30   -- s until an order arrives
ERC.STOCK_POOLS = { "shock", "wound", "cast", "ct", "nurse" }

-- the stock pool of a patient location (case.location)
function ERC.stockPool(location)
    location = tostring(location or "")
    if location:find("^shock") then return "shock" end
    if location == "wound" or location == "cast" or location == "ct" then return location end
    return "nurse"
end
