# OathBreaker 

A lightweight Turtle WoW (1.12) addon that helps melee classes stack **Holy Strength** (Crusader) by swapping to the next weapon in your queue as soon as a **brand‑new** Holy Strength proc is detected.

OathBreaker runs **only when you press the slash command** (no background loops). It retries a pending swap on each keypress until the weapon is **verified equipped**, then arms itself for the next proc.

---

## Installation

1. Create a folder `Interface/AddOns/OathBreaker/`.
2. Put **OathBreaker.lua** and **OathBreaker.toc** inside that folder.
3. `/reload` in game.

---

## Core Slash Command

* **`/oathbreaker`** – The main key you spam while fighting.

  * If a swap is **pending**, it keeps trying until the weapon is verified equipped.
  * Otherwise, it scans for a **new Holy Strength** proc; if detected, it marks the next weapon in your queue as **pending** (skips if that weapon is already equipped).

> Tip: Bind `/oathbreaker` to a comfy key. The addon is designed to work exactly on your keypresses, not on timers.

---

## Queue Management

* **`/obadd <weapon or item link>`**

  * Adds a weapon to the end of the queue.
  * You can shift‑click an item link (e.g., `/obadd [Corrupted Ashbringer]`). The addon stores **only the item name**.

* **`/obdel <index | weapon or item link>`**

  * Removes a weapon by its **index** (from `/oblist`) or by **exact name/link**.
  * Examples: `/obdel 2` or `/obdel [Chromatically Tempered Sword]`.

* **`/oblist`**

  * Prints your queue in order and shows which position is **next**.

* **`/obclear`**

  * Clears the queue and any pending swaps.

* **`/obnext`** (manual test)

  * Sets the next weapon as **pending** and immediately attempts to equip it once.
  * Useful to sanity‑check that equipping works with your current setup.

---

## Chat Verbosity

* **`/obquiet`** *(default)* – Silent mode. Only prints when a weapon **actually switches**.
* **`/obverbose`** – Debug mode. Prints retries/failures and pending notifications.

Optional debug tools:

* **`/obping`** – Prints a simple "ping" to confirm the addon is loaded.
* **`/obdebug`** – Prints a small environment check (for troubleshooting).

---

## How It Decides to Swap

1. You press **`/oathbreaker`**.
2. If a swap is pending: it tries multiple equip methods and **verifies** slot 16 actually changed.
3. If no swap is pending: it scans your buffs for a **new** Holy Strength proc:

   * Prefers icon fingerprint (texture contains `Spell_Holy_BlessingOfStrength` and expiration time when available).
   * Falls back to tooltip-based count increase if fingerprint APIs aren’t available.
4. When a new proc is detected, it sets the **next** weapon in your queue as pending.
5. Once a pending weapon is **verified equipped**, the queue **advances** (wraps back to the top).

---

## Notes & Tips

* The queue **skips** a weapon if it’s already equipped and moves to the next.
* Works with bag items; **bank items are not supported**.
* Some cores block item swaps mid‑cast or during certain actions; just press `/oathbreaker` again and the addon will keep trying until it sticks.
* Make sure your weapons really have **Crusader**; the technique depends on repeated Holy Strength procs.

---

## Examples

```text
/obadd [Corrupted Ashbringer]
/obadd [Chromatically Tempered Sword]
/oblist
/oathbreaker   (press during combat; on a new Holy Strength, it starts the next swap)
```

