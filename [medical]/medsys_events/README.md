# medsys_events

In-game events that injure players through the **medsys** exports. GTA still takes the health;
this resource adds the medical side (injuries, bleeding, pain, SpO2, knockouts). The player does
not see any of it yet; that comes with a later medsys update.

## What hurts

| event | detected by | result (see `MEDEV_RULES`) |
|---|---|---|
| fall | `onPlayerDamage` weapon 54, by health loss | leg fractures (both legs / arm / pelvis on big falls), pain, knockout |
| gunshot | weapons 22-34, 38, by hit body part + loss | gunshot wound on the hit part (head = critical), bone fracture chance; a vest turns a torso hit into blunt trauma |
| fist | weapons 0-1 | head hit: small dazed chance |
| blunt melee | bat, nightstick, shovel ... | fracture chance on the hit limb, head: dazed / unconscious + bleeding |
| sharp melee | knife, katana, chainsaw | bleeding (bandage stops it), pain |
| explosion | weapons 16, 19, 35, 36, 39, 51 | burns, fractures, shrapnel, knockout |
| fire | weapons 37, 18, summed into an episode | one burn when the fire stops, severity by total damage |
| drowning | weapon 53, episode | SpO2 drop, suffocation (aspiration) |
| tear gas | weapon 17, episode | SpO2 drop, pain, dazed |
| hit by a vehicle | weapons 49, 50 | leg / pelvis / rib fractures, bleeding, knockout |
| vehicle crash | client measures the speed change (km/h) | every occupant rolls separately; extra health loss; bikes x1.35 |
| punching a vehicle | client ray check when the fist lands | hand / arm fracture chance, rising with every punch in a row |

Players have **no clinical death**: when medsys stops a player's heart, the player dies
(`PLAYER_DEATH_IS_FINAL`), so CPR never applies to players. Peds are untouched by this rule and
are only injured with `APPLY_TO_PEDS = true`.

Untreated leg fractures disable sprint + jump, splinted ones sprint (`MEDEV_EFFECTS`).

## Export / event

medsys has no body part or cause on its injuries, so this resource keeps them:

```lua
local details = exports.medsys_events:getInjuryDetails(player)
-- { [injuryId] = { type, severity, treated, part, partLabel, cause, causeLabel } }

addEventHandler("onMedicalEventInjury", root, function(injuryId, injuryType, severity, part, cause) end)
```

## Config

`shared/config.lua`: tiers, chances, cooldowns, episodes, crash / punch detection, effects.
`MEDEV.MEDSYS` is the medsys resource name.
