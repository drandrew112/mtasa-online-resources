# gov_votes — state votes

Part of `[government]` (see gov_core README). /gov page **Votes** (category Public affairs).
Tables `gov_votes`, `gov_vote_ballots`.

A minister opens a vote (title, description, 2-10 options, length up to 14 days); every logged-in
player gets a notification and votes with **`/vote`** (`web/vote.html`, opened on gov_core's relay
with `openGovPage`); the vote may be changed until it closes. Votes past their end close by
themselves; results are shown after the close (in /gov and on gov_web).

Export `getPublicVotes()` (gov_web, open + closed in the last 30 days, no creator names).
Events: `onGovVoteOpened(title)`, `onGovVoteClosed(voteId)`.
