# DoiteAuras

Looking for WeakAuras in Vanilla WoW? DoiteAuras is a 1.12 lightweight, condition-based tracker for **abilities**, **buffs**, **debuffs**, **items** and **bars**.

This is a reworked and expanded fork of the [original DoiteAuras by Doite](https://github.com/Player-Doite/DoiteAuras). Original concept, architecture and the bulk of the feature set are by Doite. This fork adds custom animations, extended glow settings, a command-line tuner and a number of performance optimizations, focused on **Turtle-like servers**.

_Please respect the license note._

> [!IMPORTANT]
>
> **Vanilla 1.12 API is very limited. This addon requires you to have [Nampower](https://gitea.com/avitasia/nampower) installed.**

_[UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3) is optional and only needed for positional target-distance options (behind/in front)._

## Authorship

- **Original addon** — [Doite](https://github.com/Player-Doite/DoiteAuras). All base architecture, condition engine, aura tracking, grouping, export/import, icons, bars and the edit UI are his work.
- **Rework and expansion** — Zaiia. Custom effects, extended glow settings, command-line tuner, additional optimization passes.

If you are looking for the upstream project, please visit the original repository. Bug reports specific to this fork should go here; bug reports about the base addon behavior most likely belong upstream.

## Intended servers

- Turtle WoW (and Turtle-like 1.12 servers with Nampower available)
- Any 1.12 client that ships Nampower ≥ 4.1.3

## Shared exported builds (for inspiration or use)
- Reddit / DoiteAuras - Share your UI: **[LINK](https://www.reddit.com/r/DoiteAuras/comments/1r8w4zf/doiteauras_share_your_ui/)**

_To import - copy the text, press the import button inside DoiteAuras in-game and paste._

## Quick start
- Use the **minimap icon** <img width="32" height="32" alt="doiteauras-icon" src="https://github.com/user-attachments/assets/908afec6-0de1-4a4a-8081-198cac49e937" />
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
- **Custom glow effect with full settings panel** — behind/in front, scale, alpha, RGB color picker, animation speed, texture selection (Doite Glow compound preset, Action button border, and more).
- **"Soon off CD" effect choice** — ability icons can now signal cooldown-end either by sliding in or by **shatter-assemble**: the icon reassembles itself from a grid of scattered pieces flying in from the side, with optional wave motion and fading.
- **Particle sparks** — alongside the shatter pieces, a cloud of small particles flies in from the same direction; each has its own size, alpha and delay.
- **Command-line tuner `/dshatter`** — every shatter and particle parameter can be tweaked live, with named presets saved to SavedVariables (`/dshatter help` for the full reference).
- **Shared cooldown tracking via DBC category** — Holy Strike / Crusader Strike and other server-side shared-CD pairs are now correctly detected, so the "soon off CD" effect triggers on siblings even when the client reports 0/0 for them.
- **PizzaSauce animation library** — used internally for the shatter effect. Full credit to PizzaSauce's authors; see the library header for its license.

### Optimizations
- Lazy resolution of the animation library (safe against `.toc` load-order changes).
- Texture pools for shatter pieces and particles — reused across animations, no per-cast allocation.
- Shared setter functions — no per-piece closures in the hot path.
- Rate-limited full re-evaluation during the armed cooldown window (10 Hz instead of every frame).
- Reduced per-frame C-API calls in the shatter animator.
- Cleanup of stale per-key state on icon removal (glow version cache, shatter marks, wait timers).

## Tutorial & How-to instructions
[![Watch the video](https://img.youtube.com/vi/L049puyYDV8/maxresdefault.jpg)](https://youtu.be/L049puyYDV8)
_Timestamps are available in the description. Tutorial covers the base addon; fork-specific features are documented in-chat via `/dshatter help` and in the Settings panel._

## Command-line reference

Shatter + particle tuner:

```
/dshatter                     list every parameter and its value
/dshatter <key> <value>       set one parameter
/dshatter reset [<key>]       reset one parameter (or all) to defaults
/dshatter preset save <name>  snapshot the current settings
/dshatter preset load <name>  apply a saved snapshot
/dshatter preset delete <name>
/dshatter preset list
/dshatter help
```

Full parameter reference: see `dshatter.md` in this repository, or run `/dshatter help` in-game.

## Installation
1. Navigate to your World of Warcraft installation folder.
2. Go into the `Interface` -> `AddOns` directory.
3. Place the `DoiteAuras` folder directly into the `AddOns` folder.
4. Restart World of Warcraft completely.

Alternatively, add the repository URL to your launcher (addon tab -> "+ Add new addon") or a similar GitHub addon manager.

## Tip
The original project is free and built with care in the author's spare time. If this fork is useful to you and you want to support the original work, consider [supporting Doite](https://buymeacoffee.com/doite).

## Contact
- **Original addon** — contact Doite via [GitHub Issues](https://github.com/Player-Doite/DoiteAuras) or Discord if something is wrong with **the base addon**.
- **Fork-specific bugs** (glow settings, shatter, particles, `/dshatter`) — open an issue on this repository.

Doite's other addon: [Tactica](https://github.com/Player-Doite/tactica) — a raid helper for raid-leaders, including auto-building raids, auto-invite, posting tactics, assigning roles in the raid roster and more.

## Thanks to all fellow addon developers — a special thank you to:
- **Doite** — for the base addon and years of work.
- **PizzaSauce** authors — for the tweening library used by the shatter effect.
- See contributors.