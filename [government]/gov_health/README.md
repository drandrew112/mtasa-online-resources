# gov_health — state healthcare

Part of `[government]` (see gov_core README). /gov page **Healthcare** (category Public services).
Settings `health.enabled`, `health.hp_price`, `health.injuries`, `health.hospitals`.

med_hospitals bills every treatment (treatment marker, ambulance handover; players and NPC
patients): missing HP × price + injury prices by type and severity (medsys). Per hospital: who pays
(nobody / the patient / treasury / state company / private company; default treasury) and who
receives it (nobody / state / private company). Patient pays → the marker is not "free of charge".
A closed private company payer / receiver goes back to the default.

| Export | |
| --- | --- |
| `healthcareCost(patient)` | amount, `{ hp, injuries }` (books nothing) |
| `chargeHealthcare(patient, hospitalName [, taskId [, hospitalId]])` | true, amount, paidByPatient \| false, err |
| `getHealthcarePayer(hospitalId)` / `isHealthcarePaidByPatient(hospitalId)` | payer spec / does the patient pay |
| `getPublicHealth()` | gov_web part |
