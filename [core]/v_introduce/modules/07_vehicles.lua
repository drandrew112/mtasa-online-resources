-- Chapter 7: own vehicles, the Customs workshop, and "On the road": the player sits in a
-- practice vehicle (INTRO.VEHICLE, an ELS ambulance) and tries the headlights, the radio and the
-- emergency lights and siren.
Intro.module {
    id = "vehicles", order = 70, version = 1, xp = 250,
    title = "Vehicles",
    requires = { "v_ownveh" },
    scenes = {
        { type = "card",
          title = "Your own vehicles",
          text = "Vehicles you buy are yours for good. They are saved with their colour, upgrades and plate. "
              .. "Call them with the MyVeh app on your phone and they are delivered to a parking spot near you." },
        { type = "world", requires = { "v_customs" }, duration = 9,
          camera = { from = { 1290, 1350, 24, 1322, 1396, 11 }, to = { 1355, 1360, 22, 1322, 1396, 11 } },
          point = { 1322.97, 1396.46, 10.65 }, radius = 4, label = "Customs workshop", blip = 27,
          text = "Drive your own vehicle into the Customs workshop to change the paint, wheels, performance "
              .. "parts and the plate. The upgrades stay on the vehicle." },
        { type = "task", vehicle = true, camera = "vehicle", requires = { "v_headlights", "v_radio" },
          title = "On the road",
          text = "Here is a vehicle to try things out. It stays where it is - just use the switches.",
          tasks = {
              { text = "Press {key:headlights} to switch the headlights",
                check = { vehicleData = "headlights:on", changed = true } },
              { text = "Hold {key:radio} and turn the mouse wheel to change the radio station",
                check = { vehicleData = "radiostation_id", changed = true } },
          } },
        { type = "task", vehicle = true, camera = "vehicle", requires = { "v_els" },
          title = "Emergency lights",
          text = "Emergency vehicles - ambulances, police cars - have emergency lights and a siren. "
              .. "Use them only on duty, when you really respond to an emergency.",
          tasks = {
              { text = "Press {key:elsLights} to switch on the emergency lights",
                check = { vehicleData = "mkjState", equals = true } },
              { text = "Press {key:elsSiren} to switch on the siren",
                check = { vehicleData = "sirenState", equals = true } },
              { text = "Press {key:elsPattern} to change the flashing pattern",
                check = { vehicleData = "elsPattern", changed = true } },
              { text = "Press {key:elsLights} to switch everything off",
                check = { vehicleData = "mkjState", equals = false } },
          },
          note = "Hold 3 for the air horn, 2 changes the siren sound." },
    },
}
