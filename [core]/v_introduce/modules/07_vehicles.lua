if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chapter 7: own vehicles, the Customs workshop, and "On the road": the player sits in a
-- practice vehicle (INTRO.VEHICLE, an ELS ambulance) and tries the headlights, the radio and the
-- emergency lights and siren.
Intro.module {
    id = "vehicles", order = 70, version = 1, xp = 250,
    title = L.msg("v_introduce.07_vehicles.vehicles"),
    requires = { "v_ownveh" },
    scenes = {
        { type = "card",
          title = L.msg("v_introduce.07_vehicles.your_own_vehicles"),
          text = L.msg("v_introduce.07_vehicles.vehicles_you_buy_are_yours_for") },
        { type = "world", requires = { "v_customs" }, duration = 9,
          camera = { from = { 1290, 1350, 24, 1322, 1396, 11 }, to = { 1355, 1360, 22, 1322, 1396, 11 } },
          point = { 1322.97, 1396.46, 10.65 }, radius = 4, label = L.msg("v_introduce.07_vehicles.customs_workshop"), blip = 27,
          text = L.msg("v_introduce.07_vehicles.drive_your_own_vehicle_into_customs") },
        { type = "task", vehicle = true, camera = "vehicle", requires = { "v_headlights", "v_radio" },
          title = L.msg("v_introduce.07_vehicles.on_road"),
          text = L.msg("v_introduce.07_vehicles.here_is_vehicle_to_try_things"),
          tasks = {
              { text = L.msg("v_introduce.07_vehicles.press_to_switch_headlights"),
                check = { vehicleData = "headlights:on", changed = true } },
              { text = L.msg("v_introduce.07_vehicles.hold_and_turn_mouse_wheel_to"),
                check = { vehicleData = "radiostation_id", changed = true } },
          } },
        { type = "task", vehicle = true, camera = "vehicle", requires = { "v_els" },
          title = L.msg("v_introduce.07_vehicles.emergency_lights"),
          text = L.msg("v_introduce.07_vehicles.emergency_vehicles_ambulances_police_cars_have"),
          tasks = {
              { text = L.msg("v_introduce.07_vehicles.press_to_switch_on_emergency_lights"),
                check = { vehicleData = "mkjState", equals = true } },
              { text = L.msg("v_introduce.07_vehicles.press_to_switch_on_siren"),
                check = { vehicleData = "sirenState", equals = true } },
              { text = L.msg("v_introduce.07_vehicles.press_to_change_flashing_pattern"),
                check = { vehicleData = "elsPattern", changed = true } },
              { text = L.msg("v_introduce.07_vehicles.press_to_switch_everything_off"),
                check = { vehicleData = "mkjState", equals = false } },
          },
          note = L.msg("v_introduce.07_vehicles.hold_3_for_air_horn_2") },
    },
}
