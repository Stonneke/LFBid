# LFBid + LFDKP Guide

## Overview

This setup combines two addons:

- `LFBid`: Runs loot bidding and roll sessions, shows Master Looter (ML) bid windows, validates DKP, and provides DKP sync tools.
- `LFDKP`: Broadcasts DKP delta changes during raid (for example `Player +1 points`), which `LFBid` can consume live.

Used together, they provide a full loot bidding workflow with live DKP updates.

## Permissions

- `/lfbid start` and `/lfbid roll`: Master Looter only.
- `/lfbid options`: Master Looter, or guild rank `Founder` / `Banker`.

Bidder ALT behavior:

- If player guild rank is `Alt` or `Alts`, the bidder `ALT` checkbox is auto-checked when the bidder frame opens.

## Commands

Visible help commands:

- `/lfbid start <itemlink>`
- `/lfbid roll <itemlink>`
- `/lfbid open`
- `/lfbid options`

Internal test commands exist but are hidden from help text.

## Typical Raid Workflow

1. Pre-raid setup
- Make sure DKP data is loaded (`LFTentDKP`).
- If guild notes are your source of truth: `/lfbid options` -> `Notes => DKP`.
- Set bid DKP tier in options (`T1 Raid` or `T2 Raid`).

2. Start loot session (ML)
- Points session: `/lfbid start <itemlink>`
- Roll session: `/lfbid roll <itemlink>`

3. Raider bidding
- Raiders use `/lfbid open`.
- Enter points.
- Choose spec: `MS`, `OS`, `T-MOG`.
- Optional: check `ALT`.
- Click `BID`.

4. ML review
- Roll mode: 10 visible rows + scrollbar.
- Points mode: 6 visible rows per spec + independent scrollbar per spec.
- ALT-marked bids display as:
  - `<points> - ALT - <player>`
- Non-ALT display:
  - `<points> -- <player>`

5. Close bidding
- Use `Stop Bids` on the ML frame.

6. Apply/sync DKP
- If LFDKP is running, live DKP deltas are consumed by LFBid.
- Optional writeback: `/lfbid options` -> `DKP => Notes`.

## How LFDKP Integration Works

LFBid listens for addon prefix `LFDKP` in RAID addon messages.

When it receives messages like:

- `Alice +1 points`
- `Bob -5 points`

it parses and applies those deltas to `LFTentDKP`, then refreshes ML bid displays.

## DKP Data Format

`LFTentDKP` supports both formats:

- Numeric:

```lua
LFTentDKP = {
  ["Player"] = 120,
}
```

- Tiered:

```lua
LFTentDKP = {
  ["Player"] = { t1 = 120, t2 = 5 },
}
```

The selected raid tier in options determines which tier is checked for bid validation.

## Troubleshooting

- No bids arriving on ML:
  - Confirm ML started session with `/lfbid start` or `/lfbid roll`.
  - Confirm raiders are using `/lfbid open` and `BID`.
- DKP validation colors look wrong:
  - Verify selected tier in options.
  - Verify player names in `LFTentDKP` match roster names.
- Guild sync issues:
  - Check guild note permissions and API availability.
  - Ensure roster is loaded before sync actions.

## Notes

- Addon targets Turtle WoW `Interface: 11200`.
- Saved variable table used for DKP is `LFTentDKP`.
