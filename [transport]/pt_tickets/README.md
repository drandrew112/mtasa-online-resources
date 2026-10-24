# pt_tickets — public transport tickets

Ticket sales for every public transport mode. Built for the railway first (2026-10-24); buses
plug in later (an adapter file here or another resource calling `openTicketSale`).

## How it works (railway)
1. The player picks "Board the train" at a coach door (rw_passengers). `server/rail.lua` handles
   rw_passengers' cancellable `onPlayerBoardTrain`: no ticket for this trip covering the stop the
   train stands at → boarding refused (`cancelEvent(true, "-")`) and the DX ticket panel opens.
   A train without a service (rw_timetable) takes no passengers.
2. The panel lists the trip's remaining stops with the distance and the price; the player picks
   how far to travel. Price = gov_transport `getTransportFare("rail", km, category)`: km = straight lines
   between the stops, × fare per km, at least the minimum fare, + the IC supplement (default €500)
   once on IC trains. Set on the /gov Public transport page.
3. Buying takes the money (v_bank `payMoney`, cash first then the bank, key `pt.ticket`), books
   the same sum to the fare receiver (gov_transport `bookFareIncome`, default nobody) and boards the player
   at once (rw_passengers `boardCoach`).
4. The ticket holds until its last stop. When the train stands there with the doors released the
   passenger is told, and `PTT.RAIL.EJECT_DELAY` s later put on the platform
   (`removePassenger(player, reason, true)`). If the doors close first (the driver left early) it
   happens at the next stop. Leaving earlier ends the ticket — except getting off again at the
   boarding stop while the train still stands there.

The running costs of the trains (per IC / RB trip, per served stop) are not here: rw_timetable
`server/costs.lua` charges them through gov_transport `chargeTransportCost`.

## Settings
`shared/config.lua` (`PTT`): offer timeout, panel size (≈30 % of the screen width), the rail
eject delay, `RAIL.REQUIRED` (false = free travel as before), fallback prices while gov_transport is off.

## Server exports
| Export | |
| --- | --- |
| `getTicket(player)` | `{ mode, ref, line, category, from, to, fromName, toName, price, km, bought }` or false |
| `hasValidTicket(player, mode, ref [, stopIndex])` | ticket for this trip / run (covering the stop) |
| `endTicket(player, reason)` | drops the ticket |
| `openTicketSale(player, offer)` | opens the panel for another mode (offer format: top of server/tickets.lua) |
| `closeTicketSale(player)` | |

## Events (server)
- `onPlayerTicketBought` (source player; mode, ticket, ctx) — continue the boarding here.
- `onPlayerTicketEnded` (source player; mode, ticket, reason).

## Adding buses
Either a `server/bus.lua` adapter like `rail.lua` (add `pt.bus` defaults to gov_transport `GOV_DEFAULTS`
and `"bus"` to `GOV_PT_MODES`), or the bus resource builds an offer `{ mode = "bus", ref, line,
title, category, operator, from, fromName, stops = { {index, name, km} }, ctx }`, calls
`exports.pt_tickets:openTicketSale(player, offer)` and listens to `onPlayerTicketBought`.

Texts: v_locals `pt_tickets.*` (locales/en + hu). Untested in-game.
