OathBreaker (Turtle WoW 1.12)

A weapon-swapping helper for Vanilla/Turtle-WoW that juggles your main-hand around Holy Strength procs, with anchor-first logic, per-weapon soft cooldowns, optional post-swing gating, and a global ON/OFF toggle.

Features

Anchor-first (priority) mode
Keep your preferred “anchor” weapon equipped most of the time. When Holy Strength procs, briefly chase other weapons not on soft cooldown, then snap back to the anchor.

Round-robin mode
Classic “cycle through the queue on each proc.”

Per-weapon soft cooldowns
Default 13s (configurable). Prevents re-picking the same weapon too soon in priority mode.

Post-swing gating (optional)
Finalizes equips shortly after your white swing lands to avoid clipping.
Requires the SwingTimer addon (SP_SwingTimer):
https://github.com/MarcelineVQ/SP_SwingTimer

OathBreaker reads its st_timer / st_timerMax variables to detect the swing edge.

Robust equipping
Tries EquipItemByName, then /equip, then a bag-scan fallback to ensure the swap sticks.

Global enable/disable toggle
/obtoggle flips the addon ON/OFF. When OFF, /oathbreaker does nothing.


Quiet by default
Optional verbose/debug messages when needed.

Quick Start

Build a queue (two or more weapons recommended):

/obadd <weapon or shift-linked item>
/obadd <another weapon>


Pick a mode
Priority (anchor-first):

/obmode priority
/obanchor 1       -- make first item the anchor (or use weapon name)


Round-robin:

/obmode round


(Optional) Set soft cooldown (priority only):

/obcd 13


(Optional) Post-swing gating:

/obswinggate on


(Requires SP_SwingTimer—see link above.)

Run the driver:

/oathbreaker


Bind to a key and press during combat; OathBreaker detects Holy Strength and performs the swap logic.

Slash Commands
Command	Description
/oathbreaker	Run the logic once (bind this).
/obtoggle [on/off]	Globally enable/disable OathBreaker. OFF = /oathbreaker does nothing. Plays Ashbringer VO on toggle.
`/obadd <item	link>`
`/obdel <index	item>`
/oblist	Show queue, anchor, and cooldown hints.
/obclear	Clear the queue.
/obnext	Manually request the next candidate (mode-aware).
`/obmode priority	round`
`/obpriority on	off`
`/obanchor <index	item>`
/obcd <seconds>	Per-weapon soft cooldown (priority only).
/obcdlist	Show current soft-CD status per weapon.
`/obswinggate on	off`
/obquiet	Reduce chat prints.
/obverbose	Increase chat prints.
/obping, /obdebug	Utilities/diagnostics.
Example Macros

Driver key

#showtooltip
/oathbreaker


Toggle ON/OFF with VO cue

/obtoggle


Session setup (example)

/obclear
/obadd Quel'Serrar
/obadd The Hungering Cold
/obmode priority
/obanchor 1
/obcd 13
/obswinggate on

How It Works (Short)

Detect Holy Strength and track “new proc” edges.

Priority mode:

On a new proc: start soft CD for current weapon → chase a non-anchor weapon not on soft CD → later snap back to anchor.

If all non-anchors are cooling down, prefer the anchor.

Round-robin:

On a new proc: move to the next queue entry.

Post-swing gate (optional):

If enabled, the equip finalizes ~50 ms after a detected swing edge (needs SP_SwingTimer).

Equip reliability:

Attempt API → /equip → bag-scan fallback; verify the equip “stuck,” retry if needed.

Tips & Troubleshooting

If pressing /oathbreaker appears to do nothing, ensure /obtoggle is ENABLED (you’ll hear the enable VO).

Keep candidate weapons in your bags and not locked.

If you don’t use SP_SwingTimer, turn swing gating OFF: /obswinggate off.

Use /oblist and /obcdlist to check queue order, anchor, and cooldown state.

For minimal chat spam, use /obquiet. Turn on /obverbose when debugging.

Changelog (Summary)

v1.4

Added post-swing gating (optional).

Added /obtoggle global ON/OFF with distinct Ashbringer VO for enable/disable.

Kept anchor-first logic, per-weapon soft cooldowns, robust equip path, and diagnostics.

Credits

Design & implementation by Theodan with feedback from the Turtle-WoW community.
