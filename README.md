# DoiteAuras

DoiteAuras is a 1.12 lightweight, condition-based tracker for **abilities**, **buffs**, **debuffs**, **items** and **bars**.

This is a reworked and expanded fork of the original [DoiteAuras](https://github.com/Player-Doite/DoiteAuras).

**[!IMPORTANT]**
**Vanilla 1.12 API is very limited. This addon requires you to have [Nampower](https://gitea.com/avitasia/nampower) installed.**

## Intended servers

- Turtle-like 1.12 servers with Nampower available
- Any 1.12 client that ships Nampower ≥ 4.1.3

## Quick start
- Use the **minimap icon**
- `/da` or `/doite` or `/doiteauras`

## Features

### Base (from the original addon)
- Able to track an ability, buff, debuff and/or item (on player, target or pet)
- Create customizable health- or power-bars (mana/energy/rage)
- Match generically by entering a name or uniquely via SpellID
- Player and target buffs/debuffs visible beyond the visible cap (32/48)
- Import/export functions to share UI profiles
- Custom conditions (~50) to align when to show/hide icons
- Custom "and/or () logic" extra conditional builder for a more precise tracking
- Custom dynamic time-tracking and ownership system for auras on the target
- Custom dynamic and static grouping system, collapsing towards a relative point or fixed point
- Custom condition block input, for unlimited coding freedom

### Added in this fork
- **Reworked settings window** — everything configurable from one panel.
- **Font customization** — font, size and outline for timer and stack text, set either globally or per icon.
- **Name wildcards for auras** — track by patterns like `Seal of*` to match every rank and variant with one entry.
- **Popup effect on cast** — a short scale + glow burst over the icon when a spell successfully casts. Duration, peak scale, glow color, scale and texture are all tunable.
- **Custom glow effect** — behind / in front, scale, alpha, RGB color, animation speed, rotation, and a texture picker that browses built-in textures plus the bundled MPOWA pack (246 textures).
- **Glow and popup presets** — save the current configuration under a name, switch, rename or delete it later.
- **"Soon off CD" effect choice** — ability icons can now signal cooldown-end either by sliding in or by **shatter-assemble**: the icon reassembles itself from a grid of scattered pieces flying in from the side, with optional wave motion and fading.
- **Particle sparks** — alongside the shatter pieces, a cloud of small particles flies in from the same direction; each has its own size, alpha and delay.
- **Command-line tuner `/dshatter`** — every shatter and particle parameter can be tweaked live, with named presets saved to SavedVariables (`/dshatter help` for the full reference).
- **Shared cooldown tracking via DBC category** — Holy Strike / Crusader Strike and other server-side shared-CD pairs are now correctly detected, so the "soon off CD" effect triggers on siblings even when the client reports 0/0 for them.
- **Debug tools** — live player/target aura counts, aura cap simulation, and spell-cast debug output.
- [**PizzaSauce animation library**](https://codeberg.org/Pizzahawaii/PizzaSauce) — used internally for the shatter effect. Full credit to PizzaSauce's authors; see the library header for its license.

### Optimizations
- Lazy resolution of the animation library (safe against `.toc` load-order changes).
- Texture pools for shatter pieces and particles — reused across animations, no per-cast allocation.
- Shared setter functions — no per-piece closures in the hot path.
- Optional dynamic particle cap — automatically reduces the particle count of new shatters when many are running at once.
- Rate-limited full re-evaluation during the armed cooldown window (10 Hz instead of every frame).
- Reduced per-frame C-API calls in the shatter animator.
- Cleanup of stale per-key state on icon removal (glow version cache, shatter marks, wait timers).

## Command-line reference

Shatter + particle tuner https://github.com/ZaiiaDS/DoiteAuras/blob/main/dshatter.md

## Installation
1. Navigate to your World of Warcraft installation folder.
2. Go into the `Interface` -> `AddOns` directory.
3. Place the `DoiteAuras` folder directly into the `AddOns` folder.
4. Restart World of Warcraft completely.

## Authorship
- **Original addon** — Doite. All base architecture, engine, aura tracking, grouping, export/import, icons, bars and the edit UI are his work.
- **Rework and expansion** — Zaiia. Custom effects, extended glow settings, command-line tuner, additional optimization passes.

## Thanks to all fellow addon developers — a special thank you to:
- [**Doite**](https://github.com/Player-Doite/DoiteAuras) — for the base addon and years of work.
- [**PizzaSauce**](https://codeberg.org/Pizzahawaii/PizzaSauce) authors — for the tweening library used by the shatter effect.