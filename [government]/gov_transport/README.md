# gov_transport — public transport money

Part of `[government]` (see gov_core README). /gov page **Public transport** (category Public
services). Setting `pt.<mode>` per mode (`GOV_PT_MODES`, now `rail`; buses: add `pt.bus` to
`GOV_DEFAULTS` and the mode to `GOV_PT_MODES` + the page's `PT_MODES`).

Ticket prices: fare per km of the journey (straight line between the stops), minimum fare, IC
supplement once per ticket; the ticket money goes to the fare receiver (nobody / state / private
company). Running costs per IC trip, per RB trip and per served stop, paid by the cost payer to the
cost receiver. Payer nobody + receiver nobody (the default) = nothing is booked. pt_tickets sells the
tickets, rw_timetable charges the costs.

| Export | |
| --- | --- |
| `getTransportSettings(mode)` | the merged `pt.<mode>` settings |
| `getTransportFare(mode, km, category)` | price (`"IC"` adds the supplement), details |
| `bookFareIncome(mode, amount, params)` | the paid ticket money to the fare receiver |
| `chargeTransportCost(mode, kind, params)` | `"run"` (`params.category`) or `"stop"` (`params.count`) |
| `getRailDayCosts(ts)` | planned railway running costs of a day (rw_timetable timetable × cost settings, every stop served) |
