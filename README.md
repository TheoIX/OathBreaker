# OathBreaker (Turtle WoW 1.12)

A weapon-swapping helper for Vanilla/Turtle-WoW that juggles your main-hand around **Holy Strength** procs, with anchor-first logic, per-weapon soft cooldowns, optional post-swing gating, and a global ON/OFF toggle.

## Features

- **Anchor-first (priority) mode**
  - Keep your preferred “anchor” weapon equipped most of the time.
  - On Holy Strength procs, briefly chase other weapons not on soft cooldown, then snap back to the anchor.

- **Round-robin mode**
  - Classic “cycle through the queue on each proc.”

- **Per-weapon soft cooldowns**
  - Default 13s (configurable).
  - Prevents re-picking the same weapon too soon in priority mode.

- **Post-swing gating (optional)**
  - Finalizes equips shortly **after** your white swing lands to avoid clipping.
  - **Requires** the SwingTimer addon (SP_SwingTimer): https://github.com/MarcelineVQ/SP_SwingTimer
  - OathBreaker reads the global variables `st_timer` and `st_timerMax` to detect the swing edge.

- **Robust equipping**
  - Attempts `EquipItemByName` → `/equip` → bag-scan fallback and verifies that the equip “stuck”.

- **Global enable/disable toggle**
  - `/obtoggle` flips the addon ON/OFF.
  - When OFF, `/oathbreaker` does nothing.
  - Enabling plays: `Sound\Creature\Ashbringer\ASH_SPEAK_12.Wav`
  - Disabling plays: `Sound\Creature\Ashbringer\ASH_SPEAK_03.Wav`

- **Quiet by default**
  - Optional verbose/debug messages when needed.

## Installation

1. Create a folder: `Interface/AddOns/OathBreaker/`
2. Put `OathBreaker.lua` and a `.toc` file inside.
3. Restart the client or `/reload`.

**Example `OathBreaker.toc`:**
Interface: 11200
Title: OathBreaker
Notes: Holy-Strength-aware weapon swapper with anchor, soft CDs, swing gating, and global toggle.
Author: Theodan
Version: 1.4
OathBreaker.lua

markdown
Copy code

## Quick Start

1. Build a queue (two or more weapons recommended):
   - `/obadd <weapon or shift-linked item>`
   - `/obadd <another weapon>`

2. Pick a mode:
   - Priority (anchor-first):
     - `/obmode priority`
     - `/obanchor 1`  *(or use the weapon name)*
   - Round-robin:
     - `/obmode round`

3. (Optional) Set soft cooldown (priority only):
   - `/obcd 13`

4. (Optional) Enable post-swing gating:
   - `/obswinggate on`
   - *(Requires SP_SwingTimer — see link above.)*

5. Run the driver each time you want it to act:
   - `/oathbreaker`
   - Bind to a key and press during combat; OathBreaker detects Holy Strength and performs the swap logic.

## Slash Commands

- `/oathbreaker`
  - Run the logic once (bind this to a key).

- `/obtoggle [on/off]`
  - Globally enable/disable OathBreaker. OFF = `/oathbreaker` does nothing.
  - Plays Ashbringer VO when toggled (12 = enable, 03 = disable).

- `/obadd <item|link>`
  - Add a weapon to the queue.

- `/obdel <index|item>`
  - Remove a weapon from the queue.

- `/oblist`
  - Show queue, anchor, and cooldown hints.

- `/obclear`
  - Clear the queue.

- `/obnext`
  - Manually request the next candidate (mode-aware).

- `/obmode priority|round`
  - Choose anchor-first or round-robin.

- `/obpriority on|off`
  - Quick toggle for priority mode.

- `/obanchor <index|item>`
  - Set the anchor weapon.

- `/obcd <seconds>`
  - Per-weapon soft cooldown (priority only).

- `/obcdlist`
  - Show current soft-CD status per weapon.

- `/obswinggate on|off`
  - Enable/disable post-swing gating.

- `/obquiet`
  - Reduce chat prints.

- `/obverbose`
  - Increase chat prints.

- `/obping`
  - Simple health check.

- `/obdebug`
  - Toggle debug prints.

## Example Macros

**Driver key**
#showtooltip
/oathbreaker

vbnet
Copy code

**Toggle ON/OFF with VO cue**
/obtoggle

java
Copy code

**Session setup (example)**
/obclear
/obadd Quel'Serrar
/obadd The Hungering Cold
/obmode priority
/obanchor 1
/obcd 13
/obswinggate on

pgsql
Copy code

## How It Works (Short)

- Detect **Holy Strength** and track “new proc” edges.
- **Priority mode**:
  - On a new proc: start soft CD for the current weapon → chase a non-anchor weapon not on soft CD → later snap back to the anchor.
  - If all non-anchors are cooling down, prefer the anchor.
- **Round-robin**:
  - On a new proc: move to the next queue entry.
- **Post-swing gate (optional)**:
  - If enabled, the equip finalizes ~50 ms after a detected swing edge (`st_timer` / `st_timerMax`).
- **Equip reliability**:
  - Attempt API → `/equip` → bag-scan; verify the equip “stuck,” retry if needed.

## Tips & Troubleshooting

- If pressing `/oathbreaker` appears to do nothing, ensure **/obtoggle** is **ENABLED** (you’ll hear the enable VO).
- Keep candidate weapons in your **bags** and not locked.
- If you don’t use SP_SwingTimer, turn swing gating **OFF**: `/obswinggate off`.
- Use `/oblist` and `/obcdlist` to check queue order, anchor, and cooldown state.
- For minimal chat spam, use `/obquiet`. Turn on `/obverbose` when debugging.

## Changelog (Summary)

- **v1.4**
  - Added **post-swing gating** (optional).
  - Added **`/obtoggle`** global ON/OFF with distinct Ashbringer VO for enable/disable.
  - Retains anchor-first logic, per-weapon soft cooldowns, robust equip path, and diagnostics.

## Credits

- Design & implementation: **Theodan**
- Feedback: Turtle-WoW community
