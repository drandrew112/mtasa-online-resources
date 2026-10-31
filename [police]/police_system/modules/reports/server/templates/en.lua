-- police_system / modules/reports/server/templates/en.lua
-- Report draft sentences in English, one per log line kind. %s / named fields from the line data (d), the time of
-- the line (time) and the officer (o). Missing kinds are left out of the text.

REPORT_TEMPLATES = REPORT_TEMPLATES or {}

REPORT_TEMPLATES.en = {
    types = { traffic_stop = "TRAFFIC STOP", ped_stop = "PEDESTRIAN STOP", pursuit = "PURSUIT", arrest = "ARREST",
              backup = "BACKUP", other = "REPORT" },
    intro = "At {time} unit {unit} ({members}) {what}.",
    what = {
        traffic_stop = "stopped a {color}{model}, plate {plate}, in {zone}",
        ped_stop = "stopped a pedestrian, {name}, in {zone}",
        pursuit = "started a pursuit of {name} in {zone}",
        arrest = "made an arrest in {zone}",
        backup = "was sent as backup to unit {for}",
        other = "was on duty",
    },
    lines = {
        query_person = "{time} {o} checked the identity of {name}.{warrant}",
        query_vehicle = "{time} {o} checked the vehicle {plate} ({model}).{flags}",
        test_bac = "{time} Breathalyser test of {name}: {value} per mille.",
        test_drug = "{time} Drug test of {name}: {result}.",
        fine = "{time} {o} issued a fine to {name}: {item} ({amount}).",
        warning = "{time} {o} gave {name} a warning: {item}.",
        cuffed = "{time} {o} handcuffed {name}.",
        uncuffed = "{time} {o} removed the handcuffs of {name}.",
        escort = "{time} {o} escorted {name}.",
        placed = "{time} {name} was placed in the police vehicle.",
        taken_out = "{time} {name} was taken out of the police vehicle.",
        handover = "{time} {name} was handed over at {station}.",
        released = "{time} {name} was released.",
        order_out = "{time} The driver was ordered out of the vehicle.",
        returned = "{time} {name} got back into the vehicle.",
        pursuit_level = "{time} The suspect's wanted level rose to {level}.",
        evading = "{time} Visual contact with the suspect was lost.",
        caught = "{time} The suspect was caught.",
        lost = "{time} The suspect escaped.",
        backup_arrived = "{time} {o} arrived on the scene.",
        weapon_fired = "{time} {o} fired {count} shots.",
        weapon_drawn = "{time} {o} drew a weapon.",
        surrendered = "{time} The suspect surrendered.",
        warrant_found = " Active warrant found.",
        flags_none = "",
        flag_stolen = " The vehicle is reported stolen.",
        flag_inspection = " Inspection: {value}.",
    },
    drug = { pos = "positive", neg = "negative" },
}
