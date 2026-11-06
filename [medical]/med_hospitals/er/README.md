# med_hospitals / er — sürgősségi osztály (ER)

Hospital ER gameplay on top of med_hospitals. Plan (all decisions, images, codes): https://claude.ai/artifact/DhTja6KHwrZuoTQnZU2udF

Active only for hospitals with an `"er"` block in `hospitals.json` (now `ls_allsaints`, positions measured with MCP).
Most features run only while the hospital has staff on duty (`work_hospital`); without staff the old handover stays.

## Files

| file | what |
|---|---|
| `shared/catalog.lua` | `ERC`: times (1 game h = 10 real min), orders (lab / xray / ct / fast / ecg), hidden FINDINGS (region, BNO, CT/XR/US image, surgery / cast / suture / drain), SURGERIES, OUTCOMES, BNO subset (HU = exact BNOTORZS.DBF text, EN = WHO) |
| `server/core.lua` | `ER` state: staff (`work_hospital`), cases (`ER.cases[ped]`, synced element data `er.case`), corridor spots F1–F5, bay snapping on `onStretcherSettled` (shock: untriaged → T1 + pusher treating), case restore after restart |
| `server/arrival.lua` | gate of the EMS handover (`server/handover.lua`): mandatory description (ui_core text input) for every NPC handover; no free corridor spot (with staff) → refused + nearest alternative; `ER.receivePatient` moves the ped onto a new hospital stretcher |
| `server/menus.lua` | stretcher point marker (request / remove, ui_inac temp menu), patient ui_interactobject menu (triage, take over, info) |
| `server/his.lua` | findings resolver (medsys injuries + `getInjuryDetails` part → ERC.FINDINGS), orders / perform (room check, CT one at a time, lab 120 s), results, room treatments (suture, irrigate, cast, reduction, drain, burn dressing), diagnoses (max 5), todo list, `his:request` / `his:action`, points for medsys interventions |
| `server/outcome.lua` | discharge, ward (12 fixed beds, 20 min), ICU (4 beds, 30 min), OR (NPC, 3–10 min, one patient), death + morgue drop, deterioration alert (timer stops), board |
| `server/transfer.lua` | S1 / S2 transfer: ERM task (`meta.kind = "transfer"`, `transferClass`, `needsALS`), pickup by the EMS stretcher at `transferPickup`, automatic transfer when no suitable unit is logged in |
| `server/docs.lua` | documents through med_docs (Ambuláns lap, results, op note, death certificate) |
| `server/comms.lua` | `getHospitalStatus` / `receiveParams` exports (ERM tablet hospital status + parameter cards) |
| `server/walkin.lua` | walk-in patients (rate by staff / EMS units / recent handovers), NPC patients removed after 5 min without staff |
| `client/er.lua` | notifications, handover text prompt, stretcher point key (the hint is the marker card), patient cards above peds |
| `client/gfx.lua` | DX helpers; skins `HGfx.setSkin("modern")` (tablet, bedside) / `"w7"` (PC): palette swapped in place, square glossy buttons, classic tabs |
| `client/his.lua` | DX HIS: J tablet (modern) and the PC pages (`HIS.drawPC`: Win7 toolbar, page, status bar): Patients, Todo, Ward board, Stock, Comms, Notes; `/sbo`, `/sbopc <caseId> <tab>` |
| `client/exam.lua` | patient panel (`EXAM.draw`); tabs by source: PC = with Dokumentáció, tablet / bedside = without; Elhelyezés (outcome) everywhere; a result open = only the result (X back); X close at the top right |
| `client/w7.lua` | the hospital PC (2026-11-06): dark Windows 7 monitor on 80 % of the screen, opens on the empty desktop (no window), desktop icons, taskbar + Start menu + clock, maximized windows SBO / Beteglap / Dokumentumtár (med_docs embedded via `setDocumentsRect`); EMS medics: only the Dokumentumtár with their EMS sheets; closes 3.2 m from the desk |
| `img/` | CT / X-ray / US / ECG library (`download="false"`, staff clients download on demand) |

Related: `med_equipments/stretcher/server/hospital.lua` (hospital stretchers + fixed beds), `[work]/work_hospital`,
`med_docs` (documents + viewer + EMS case sheet at every handover), `med_erm` (`server/hospitalparams.lua`,
`client/hospitalparams.lua`, auto dispatch S1/S2 order), `police_system` export `requestNPCIdentity`.

## 2026-11-06 changes (plan round 3)

- Documentation (anamnesis / status / epicrisis texts, BNO diagnoses) only at a hospital PC: the tablet has no
  Dokumentáció tab, the server refuses `text` / `diagAdd` / `diagRemove` more than 3 m from a PC (`ER.atPC`).
- Points: `ERC.POINT_MULT = 5`; `ER.points` pays base * 5 to the player, `c.pointsTotal` keeps the base (state care value).
- A failed minigame (its pass rule not met) gives no result, no points, no document; the order goes back to
  "ordered", the treatment stays to do (`ER.minigameFailed`). Treatment stock is used only after a success; a failed
  chest drain still bleeds on a vessel hit.
- Walk-in handover (`ER.walkInHandover`, outcome.lua): pushing the patient into a ward / ICU / OR / morgue marker,
  3 s countdown on the marker card, then `med_equipments:releaseHospitalStretcher` and the handover. Putting the
  stretcher down still works.
- 12-lead ECG (mg_ecg): bigger electrodes, `options.guide` for Nurses / Residents (`ER.ecgGuide`).
