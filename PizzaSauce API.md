# PizzaSauce API Reference

Complete API documentation for PizzaSauce v0.1.1.


## Table of Contents

- [Getting Started](#getting-started)
- [Core Primitives](#core-primitives)
  - [Tween](#tween)
  - [Sequence](#sequence)
  - [Group](#group)
- [Convenience Functions](#convenience-functions)
  - [Alpha](#alpha) - FadeIn, FadeOut, FadeTo, Flash, Breathe
  - [Scale](#scale) - ScaleIn, ScaleOut, Pulse, Rubber, Flip
  - [Position](#position) - Move, MoveTo, SlideIn, SlideOut, Bounce, Shake, FlyTo
  - [Rotation](#rotation) - Spin
  - [Color](#color) - Color, ColorFlash
  - [Size](#size) - Size, Morph
  - [Value](#value) - Progress
  - [Text](#text) - Typewriter
  - [Clipping](#clipping) - Reveal, Conceal, WipeIn, WipeOut
  - [Meta / Utility](#meta--utility) - Stagger, Delay, Run, Stop
- [Built-in Easings](#built-in-easings)
- [Built-in Types](#built-in-types)
- [Extending PizzaSauce](#extending-pizzasauce)
  - [RegisterType](#registertype)
  - [RegisterEasing](#registereasing)
  - [RegisterHelper](#registerhelper)
- [Animation Objects](#animation-objects)
- [Options Table](#options-table)


## Getting Started

PizzaSauce is an embeddable library. Add `PizzaSauce.lua` to your addon folder and list it in your `.toc` before your own files. Then capture a local reference:

```lua
local Sauce = PizzaSauce
```

> [!WARNING]
> **Important:** Always use a local variable, never the `PizzaSauce` global directly. Each addon gets its own isolated PizzaSauce instance. The global gets overwritten when the next addon loads its copy. Capturing the local ensures you're using the version you shipped.

### Auto-play behavior

By default, every animation plays automatically on the next frame tick. When animations are passed as children to `Sequence` or `Group`, auto-play is suppressed automatically so the parent controls playback.

To manually suppress auto-play (e.g. for use in a `Stagger` callback), pass `{ defer = true }` in the options table:

```lua
local anim = Sauce:FadeIn(frame, 0.5, nil, { defer = true })
anim:Play() -- start manually
```

### The options table

Most convenience functions accept an optional table `o` as the last argument with these fields:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `delay` | `number` | `0` | Wait before starting (seconds). Works on all animations. |
| `defer` | `boolean` | `false` | Suppress auto-play. You don't need this inside Stagger callbacks (Stagger handles it). |
| `onStart` | `function` | `nil` | Called when the animation begins (after delay). Supported on single-tween helpers. Multi-step helpers (Flash, Pulse, Bounce, Shake, etc.) ignore it. |
| `onFinish` | `function` | `nil` | Called when the animation completes normally. |
| `onCancel` | `function` | `nil` | Called when the animation is cancelled (via `Cancel()` or `Stop()`). |

The `delay` option is supported on all animations (Tweens, Sequences, Groups, and every convenience function). It's the simplest way to offset timing without wrapping in a Sequence:

```lua
Sauce:FadeIn(frame1, 0.3)
Sauce:FadeIn(frame2, 0.3, nil, { delay = 0.1 })
Sauce:FadeIn(frame3, 0.3, nil, { delay = 0.2 })
```


## Core Primitives

### Tween

```lua
Sauce:Tween(target, opts) -> tween
```

The fundamental building block. Animates a single property on `target` from one value to another over time.

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `target` | `Frame\|Texture\|FontString` | The UI element to animate. |
| `opts` | `table` | Configuration table (see below). |

**opts fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `type` | `string` | `"alpha"` | Animation type (see [Built-in Types](#built-in-types)). |
| `from` | `any` | auto-detected | Starting value. If omitted, read from the target. |
| `to` | `any` | — | Ending value. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string\|function` | `"inOutQuad"` | Easing function name or custom function. |
| `delay` | `number` | `0` | Delay before the animation starts (seconds). |
| `onStart` | `function` | `nil` | Called when animation begins (after delay). |
| `onUpdate` | `function(self, t)` | `nil` | Called every tick with eased progress `t` [0..1]. |
| `onFinish` | `function` | `nil` | Called when animation completes. |
| `onCancel` | `function` | `nil` | Called when animation is cancelled. |
| `getter` | `function(target) -> value` | `nil` | Custom getter for `"custom"` type. |
| `setter` | `function(target, value)` | `nil` | Custom setter for `"custom"` type. |
| `defer` | `boolean` | `false` | Suppress auto-play. |

Any extra keys in `opts` that aren't listed above are forwarded directly onto the tween object. This lets [custom types](#registertype) receive additional parameters without needing a separate data channel:

```lua
Sauce:Tween(frame, {
  type = "ballistic", from = { 0, 100 }, duration = 2.5, easing = "linear",
  vx = 200, vy = 300, gravity = 350,  -- forwarded to tween.vx, tween.vy, tween.gravity
})
```

Inside the type handler, access them as `tween.vx`, `tween.gravity`, etc.

**Example:**
```lua
Sauce:Tween(myFrame, {
  type = "alpha",
  from = 0,
  to = 1,
  duration = 0.5,
  easing = "outCubic",
  delay = 0.2,
  onFinish = function() print("done!") end,
})
```


### Sequence

```lua
Sauce:Sequence(children, opts) -> sequence
```

Plays an array of animations one after another. Each child starts after the previous one finishes.

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `children` | `table` | Array of Tween/Sequence/Group objects. |
| `opts` | `table` | Optional configuration (see below). |

**opts fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `delay` | `number` | `0` | Delay before the sequence starts. |
| `loop` | `number` | `1` | Number of times to loop. `0` = infinite. |
| `yoyo` | `boolean` | `false` | Reverse child order on alternate loops. |
| `onFinish` | `function` | `nil` | Called when all loops complete (not called if `loop = 0`). |
| `onCancel` | `function` | `nil` | Called when cancelled. |
| `defer` | `boolean` | `false` | Suppress auto-play. |

**Example:**
```lua
Sauce:Sequence({
  Sauce:FadeOut(frame, 0.3),
  Sauce:FadeIn(frame, 0.3, nil, { delay = 1.0 }),
}, { loop = 3 })
```


### Group

```lua
Sauce:Group(children, opts) -> group
```

Plays an array of animations simultaneously. Finishes when the longest child completes.

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `children` | `table` | Array of Tween/Sequence/Group objects. |
| `opts` | `table` | Optional configuration (see below). |

**opts fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `delay` | `number` | `0` | Delay before the group starts. |
| `loop` | `number` | `1` | Number of loops. `0` = infinite. |
| `yoyo` | `boolean` | `false` | Reverse child order each loop. |
| `onFinish` | `function` | `nil` | Called when all children complete. |
| `onCancel` | `function` | `nil` | Called when cancelled. |
| `defer` | `boolean` | `false` | Suppress auto-play. |

**Example:**
```lua
-- Slide and fade at the same time
Sauce:Group({
  Sauce:MoveTo(frame, { 100, 50 }, 0.5),
  Sauce:FadeOut(frame, 0.5),
})
```


## Convenience Functions

All convenience functions return an animation object (Tween, Sequence, or Group) that you can compose, `:Play()`, or `:Cancel()`.

The last parameter `o` is always an optional options table accepting `{ delay, defer, onStart, onFinish, onCancel }`.


### Alpha

#### FadeIn

```lua
Sauce:FadeIn(target, duration, easing, o)
```

Fades a frame from invisible to fully visible. Sets alpha to 0 and calls `Show()` before animating.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | — | Frame to fade in. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string` | `nil` | Easing function. |

```lua
Sauce:FadeIn(myFrame, 0.5, "outCubic")

-- With a delay
Sauce:FadeIn(myFrame, 0.5, nil, { delay = 1.0 })
```


#### FadeOut

```lua
Sauce:FadeOut(target, duration, easing, o)
```

Fades a frame to invisible, then calls `Hide()`.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | — | Frame to fade out. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string` | `nil` | Easing function. |

```lua
Sauce:FadeOut(myFrame, 0.5)
```


#### FadeTo

```lua
Sauce:FadeTo(target, toAlpha, duration, easing, o)
```

Fades a frame to a specific alpha value.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | — | Frame to fade. |
| `toAlpha` | `number` | — | Target alpha [0..1]. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string` | `nil` | Easing function. |

```lua
Sauce:FadeTo(myFrame, 0.3, 0.5)
```


#### Flash

```lua
Sauce:Flash(target, count, duration, o)
```

Rapidly flashes a frame by toggling alpha.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | — | Frame to flash. |
| `count` | `number` | `3` | Number of flashes. |
| `duration` | `number` | `0.6` | Total duration in seconds. |

```lua
Sauce:Flash(myFrame, 4, 1.0)
```


#### Breathe

```lua
Sauce:Breathe(target, minAlpha, maxAlpha, duration, o)
```

Loops alpha between min and max forever (or until cancelled). Like a pulsing glow.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | — | Frame to breathe. |
| `minAlpha` | `number` | — | Minimum alpha. |
| `maxAlpha` | `number` | — | Maximum alpha. |
| `duration` | `number` | `1.6` | Duration of one full cycle. |

```lua
local anim = Sauce:Breathe(glowFrame, 0.2, 1.0, 2.0)
-- Later: Sauce:Stop(glowFrame)
```


### Scale

#### ScaleIn

```lua
Sauce:ScaleIn(target, duration, easing, o)
```

Scales a frame from 0 to full size. Calls `Show()` when the animation starts (not at construction, so it's safe for deferred/staggered use).

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | — | Frame to scale in. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string` | `"outBack"` | Easing function. |

```lua
Sauce:ScaleIn(myFrame, 0.4)
```


#### ScaleOut

```lua
Sauce:ScaleOut(target, duration, easing, o)
```

Scales a frame down to nothing, then calls `Hide()`.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | — | Frame to scale out. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string` | `"inBack"` | Easing function. |

```lua
Sauce:ScaleOut(myFrame, 0.3, "inCubic")
```


#### Pulse

```lua
Sauce:Pulse(target, scale, duration, o)
```

Quick scale-up then back to original size. Think: heartbeat.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | — | Frame to pulse. |
| `scale` | `number` | `1.3` | Peak scale factor. |
| `duration` | `number` | `0.4` | Total duration. |

```lua
Sauce:Pulse(myFrame, 1.5, 0.5)
```


#### Rubber

```lua
Sauce:Rubber(target, scale, duration, o)
```

Starts oversized and snaps to normal with an elastic wobble. Like dropping a rubber ball.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | — | Frame to rubber. |
| `scale` | `number` | `1.3` | Starting scale factor. |
| `duration` | `number` | `0.5` | Duration in seconds. |

```lua
Sauce:Rubber(myFrame, 1.5, 0.6)
```


#### Flip

```lua
Sauce:Flip(target, axis, duration, o)
```

Full 360-degree flip with texture mirroring at 90 and 270 degrees. Works on frames containing textures.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | — | Frame to flip. |
| `axis` | `string` | `"x"` | `"x"` for horizontal, `"y"` for vertical. |
| `duration` | `number` | `0.8` | Duration of the full rotation. |

```lua
Sauce:Flip(myFrame, "x", 1.2)
```


### Position

#### Move

```lua
Sauce:Move(target, from, to, duration, easing, o)
```

Moves a frame from one position to another using absolute anchor offsets. Use this when you need explicit control over both endpoints. For simpler cases where you just need a destination, see [MoveTo](#moveto).

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | -- | Frame to move. |
| `from` | `table` | -- | Start position `{ x, y }`. |
| `to` | `table` | -- | End position `{ x, y }`. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string` | `nil` | Easing function. |

```lua
Sauce:Move(spark, { 0, 100 }, { 80, 220 }, 0.8, "outCubic")
```


#### MoveTo

```lua
Sauce:MoveTo(target, to, duration, easing, o)
```

Moves a frame to absolute anchor offsets.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | — | Frame to move. |
| `to` | `table` | — | Target position { x, y }. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string` | `nil` | Easing function. |

```lua
Sauce:MoveTo(myFrame, { 150, 100 }, 0.5, "outBack")
```


#### SlideIn

```lua
Sauce:SlideIn(target, direction, distance, duration, easing, o)
```

Slides a frame in from off-screen (or off-position) with a simultaneous fade-in. Shows the frame automatically.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | — | Frame to slide in. |
| `direction` | `string` | — | Direction of motion: `"LEFT"`, `"RIGHT"`, `"UP"`, or `"DOWN"`. The frame enters from the opposite side and travels in this direction. `"UP"` enters from below and slides up; `"RIGHT"` enters from the left and slides right. |
| `distance` | `number` | `100` | Pixels to travel. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string` | `"outCubic"` | Easing function. |

```lua
Sauce:SlideIn(myFrame, "RIGHT", 300, 0.5)
```


#### SlideOut

```lua
Sauce:SlideOut(target, direction, distance, duration, easing, o)
```

Slides a frame out with a simultaneous fade, then calls `Hide()`.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | — | Frame to slide out. |
| `direction` | `string` | — | `"LEFT"`, `"RIGHT"`, `"UP"`, or `"DOWN"`. |
| `distance` | `number` | `100` | Pixels to travel. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string` | `"inCubic"` | Easing function. |

```lua
Sauce:SlideOut(myFrame, "LEFT", 300, 0.5)
```


#### Bounce

```lua
Sauce:Bounce(target, height, count, duration, o)
```

Bounces a frame up and down with decaying height.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | — | Frame to bounce. |
| `height` | `number` | `30` | Peak bounce height in pixels. |
| `count` | `number` | `3` | Number of bounces. |
| `duration` | `number` | `0.6` | Total duration. |

```lua
Sauce:Bounce(myFrame, 40, 4, 0.8)
```


#### Shake

```lua
Sauce:Shake(target, intensity, duration, o)
```

Rapid random position jitter, snaps back to original position when done.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | — | Frame to shake. |
| `intensity` | `number` | `5` | Max pixel offset per axis. |
| `duration` | `number` | `0.3` | Duration in seconds. |

```lua
Sauce:Shake(myFrame, 8, 0.4)
```


#### FlyTo

```lua
Sauce:FlyTo(frame, targetFrame, duration, easing, o)
```

Flies a frame to the center of another frame. Useful for "item flies to bag" type effects.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `frame` | `Frame` | — | Frame to move. |
| `targetFrame` | `Frame` | — | Destination frame. |
| `duration` | `number` | `0.5` | Duration in seconds. |
| `easing` | `string` | `"inOutQuad"` | Easing function. |

```lua
Sauce:FlyTo(lootIcon, bagSlot, 0.4, "inCubic")
```


### Rotation

#### Spin

```lua
Sauce:Spin(texture, degreesPerSecond, o)
```

Continuously rotates a texture. Loops forever until cancelled. **Operates on textures, not frames.** Uses `SetTexCoord` UV remapping.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `texture` | `Texture` | — | Texture to rotate. |
| `degreesPerSecond` | `number` | `90` | Rotation speed. |

> **Note:** Square textures will clip at corners during rotation. Use circular textures for best results.

```lua
Sauce:Spin(myTexture, 180)
-- Later: Sauce:Stop(myTexture)
```


### Color

#### Color

```lua
Sauce:Color(target, from, to, duration, easing, o)
```

Animate a texture's vertex color from one value to another. Uses `SetVertexColor`, which **multiplies** with the texture's base color. Use white/grayscale base textures for accurate colors.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Texture` | -- | Texture to animate. |
| `from` | `{r, g, b, a}` | -- | Starting color. |
| `to` | `{r, g, b, a}` | -- | Ending color. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string\|function` | `"inOutQuad"` | Easing function. |

```lua
-- Flash overlay: transparent -> red -> transparent
Sauce:Sequence({
  Sauce:Color(overlay, { 1, 0, 0, 0 }, { 1, 0, 0, 0.7 }, 0.08),
  Sauce:Color(overlay, { 1, 0, 0, 0.7 }, { 1, 0, 0, 0 }, 0.4, "outQuad"),
})
```


#### ColorFlash

```lua
Sauce:ColorFlash(texture, r, g, b, duration, o)
```

Flashes a texture to a color and back to white. Uses `SetVertexColor`, which **multiplies** with the texture's base color. Use white/grayscale base textures for accurate colors.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `texture` | `Texture` | — | Texture to color flash. |
| `r` | `number` | — | Red [0..1]. |
| `g` | `number` | — | Green [0..1]. |
| `b` | `number` | — | Blue [0..1]. |
| `duration` | `number` | `0.4` | Total duration. |

```lua
Sauce:ColorFlash(myIcon, 1, 0.2, 0.2, 0.6) -- red flash
```


### Size

#### Size

```lua
Sauce:Size(target, from, to, duration, easing, o)
```

Animates a frame's width and height from one size to another. Use this when you need explicit control over both start and end sizes. For simpler cases where you just need a target size, see [Morph](#morph).

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | -- | Frame to resize. |
| `from` | `table` | -- | Start size `{ width, height }`. |
| `to` | `table` | -- | End size `{ width, height }`. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string` | `nil` | Easing function. |

```lua
Sauce:Size(bloom, { 10, 10 }, { 140, 140 }, 0.4, "outQuad")
```


#### Morph

```lua
Sauce:Morph(target, to, duration, easing, o)
```

Smoothly resizes a frame to new dimensions.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Frame` | — | Frame to resize. |
| `to` | `table` | — | Target size { width, height }. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string` | `nil` | Easing function. |

```lua
Sauce:Morph(myFrame, { 200, 50 }, 0.5, "outBack")
```


### Value

#### Progress

```lua
Sauce:Progress(statusbar, toValue, duration, easing, o)
```

Smoothly animates a `StatusBar`'s value. Great for health bars, XP bars, cast bars, etc.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `statusbar` | `StatusBar` | — | The status bar to animate. |
| `toValue` | `number` | — | Target value. |
| `duration` | `number` | `0.4` | Duration in seconds. |
| `easing` | `string` | `"outCubic"` | Easing function. |

```lua
Sauce:Progress(healthBar, 0, 1.5) -- drain to 0
Sauce:Progress(xpBar, 75, 0.8)    -- fill to 75
```


### Text

#### Typewriter

```lua
Sauce:Typewriter(fontstring, text, duration, o)
```

Types out text one character at a time.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `fontstring` | `FontString` | — | The font string to type into. |
| `text` | `string` | — | The full text to reveal. |
| `duration` | `number` | `len * 0.05` | Total duration (defaults to 50ms per character). |

```lua
Sauce:Typewriter(myText, "Hello from PizzaSauce!", 1.5)
```


### Clipping

These functions animate textures using `SetTexCoord` and dimension changes to create masking/clipping effects. They temporarily re-anchor the texture to a single edge during animation and restore `SetAllPoints` when done.

> **Important:** These operate on **textures**, not frames. The texture must be a child of a frame (used as the clipping boundary).

#### Reveal

```lua
Sauce:Reveal(target, direction, duration, easing, o)
```

A window progressively opens over a static texture, like a curtain being drawn. The image stays in place, and more of it becomes visible.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Texture` | — | Texture to reveal. |
| `direction` | `string` | `"LEFT"` | Edge to reveal from: `"LEFT"`, `"RIGHT"`, `"UP"`, `"DOWN"`. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string` | `"outQuad"` | Easing function. |

```lua
Sauce:Reveal(myTexture, "LEFT", 0.8)
```


#### Conceal

```lua
Sauce:Conceal(target, direction, duration, easing, o)
```

The reverse of Reveal. A window closes over a static texture. Calls `Hide()` when done.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Texture` | — | Texture to conceal. |
| `direction` | `string` | `"LEFT"` | Edge to conceal toward: `"LEFT"`, `"RIGHT"`, `"UP"`, `"DOWN"`. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string` | `"outQuad"` | Easing function. |

```lua
Sauce:Conceal(myTexture, "RIGHT", 0.8)
```


#### WipeIn

```lua
Sauce:WipeIn(target, direction, duration, easing, o)
```

The image physically slides into view from a direction, like being pushed on stage. Unlike Reveal, the texture content moves with the edge.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Texture` | — | Texture to wipe in. |
| `direction` | `string` | `"LEFT"` | Direction of motion: `"LEFT"`, `"RIGHT"`, `"UP"`, or `"DOWN"`. The image enters from the opposite side and slides in this direction. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string` | `"outQuad"` | Easing function. |

```lua
Sauce:WipeIn(myTexture, "LEFT", 0.8)
```


#### WipeOut

```lua
Sauce:WipeOut(target, direction, duration, easing, o)
```

The image slides out of view. The reverse of WipeIn. Calls `Hide()` when done.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | `Texture` | — | Texture to wipe out. |
| `direction` | `string` | `"LEFT"` | Direction to exit toward. |
| `duration` | `number` | `0.3` | Duration in seconds. |
| `easing` | `string` | `"outQuad"` | Easing function. |

```lua
Sauce:WipeOut(myTexture, "RIGHT", 0.8)
```


### Meta / Utility

#### Stagger

```lua
Sauce:Stagger(targets, animFn, delay, o)
```

Applies an animation to multiple targets with a time offset between each. Wraps everything in a `Group` of delay-offset `Sequences` internally.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `targets` | `table` | — | Array of frames/textures to animate. |
| `animFn` | `function(target, index) -> anim` | — | Factory function that returns a **deferred** animation for each target. |
| `delay` | `number` | `0.08` | Delay between each target's start. |

You don't need to worry about `defer` inside `animFn`. Stagger automatically suppresses auto-play on whatever you return.

```lua
Sauce:Stagger(menuFrames, function(frame)
  return Sauce:ScaleIn(frame, 0.3, "outBack")
end, 0.08)
```

```lua
-- More complex: each frame does a full enter-hold-exit sequence
Sauce:Stagger(frames, function(f)
  return Sauce:Sequence({
    Sauce:ScaleIn(f, 0.3, "outBack"),
    Sauce:FadeOut(f, 0.3, nil, { delay = 1.5 }),
  })
end, 0.1)
```


#### Delay

```lua
Sauce:Delay(duration) -> tween
```

A no-op animation that just waits. Useful as a spacer inside `Sequence`.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `duration` | `number` | `1` | Wait time in seconds. |

Always returns a deferred tween (designed for use inside Sequence/Group).

> **Tip:** In most cases you should use the `delay` option instead:
> ```lua
> -- Standalone:
> Sauce:FadeIn(frame, 0.3, nil, { delay = 0.5 })
>
> -- Inside a Sequence (delay on the next child acts as a pause):
> Sauce:Sequence({
>   Sauce:FadeOut(frame, 0.3),
>   Sauce:FadeIn(frame, 0.3, nil, { delay = 1.0 }),
> })
> ```

```lua
Sauce:Sequence({
  Sauce:FadeOut(frame, 0.3),
  Sauce:FadeIn(frame, 0.3, nil, { delay = 1.0 }),
})
```


#### Run

```lua
Sauce:Run(fn, o)
```

A zero-duration callback step for use inside `Sequence`. Fires `fn` immediately when reached, then completes so the next child can start.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `fn` | `function` | -- | Callback to execute. |

Useful for setup, teardown, or launching standalone animations between Sequence steps.

```lua
Sauce:Sequence({
  Sauce:FadeIn(frame, 0.3),
  Sauce:Run(function()
    text:SetText("Hello!")
    Sauce:Breathe(glow, 0.3, 1.0, 0.6)
  end),
  Sauce:Delay(2.0),
  Sauce:FadeOut(frame, 0.3),
})
```


#### Stop

```lua
Sauce:Stop(target)
```

Immediately cancels **all** active animations on a target, including animations nested inside Sequences and Groups.

| Param | Type | Description |
|-------|------|-------------|
| `target` | `Frame\|Texture\|FontString` | The element to stop animating. |

```lua
Sauce:Stop(myFrame)
```


## Built-in Easings

32 easing functions, organized by family. Each family has `in`, `out`, and `inOut` variants.

| Name | Description |
|------|-------------|
| `linear` | Constant speed, no acceleration. |
| `swing` | Gentle sine-based ease (same as `inOutSine`). |
| **Quad** | |
| `inQuad` | Accelerate from zero. |
| `outQuad` | Decelerate to zero. |
| `inOutQuad` | Accelerate then decelerate. |
| **Cubic** | |
| `inCubic` | Steeper acceleration than Quad. |
| `outCubic` | Steeper deceleration than Quad. |
| `inOutCubic` | Steeper ease in-out. |
| **Quart** | |
| `inQuart`, `outQuart`, `inOutQuart` | Power of 4 curves. |
| **Quint** | |
| `inQuint`, `outQuint`, `inOutQuint` | Power of 5 curves. |
| **Sine** | |
| `inSine`, `outSine`, `inOutSine` | Sine-based curves. Gentle and natural. |
| **Expo** | |
| `inExpo`, `outExpo`, `inOutExpo` | Exponential curves. Very dramatic. |
| **Circ** | |
| `inCirc`, `outCirc`, `inOutCirc` | Circular curves. |
| **Elastic** | |
| `inElastic` | Springs back before accelerating. |
| `outElastic` | Overshoots and oscillates at the end. |
| `inOutElastic` | Elastic on both ends. |
| **Back** | |
| `inBack` | Pulls back before going forward. |
| `outBack` | Overshoots the target, then settles. |
| `inOutBack` | Pull-back and overshoot. |
| **Bounce** | |
| `inBounce` | Bouncy start. |
| `outBounce` | Bouncy landing. |
| `inOutBounce` | Bouncy both ends. |

You can also pass a function directly:

```lua
Sauce:FadeIn(frame, 0.5, function(t) return t * t end)
```


## Built-in Types

Animation types define **what property** gets animated and **how** to read/write it.

| Type | Target | From/To format | Description |
|------|--------|-----------------|-------------|
| `alpha` | Frame/Texture | `number` [0..1] | Opacity via `SetAlpha`/`GetAlpha`. |
| `scale` | Frame | `number` (1.0 = normal) | Width/height scaling. Captures base size on start. |
| `size` | Frame | `{ width, height }` | Absolute width/height via `SetWidth`/`SetHeight`. |
| `position` | Frame | `{ x, y }` | Anchor offsets. Preserves anchor point and relative frame. |
| `color` | Texture | `{ r, g, b, a }` | Vertex color via `SetVertexColor`. Defaults from `{ 1, 1, 1, 1 }`. |
| `rotation` | Texture | `number` (degrees) | UV-based rotation via `SetTexCoord`. |
| `custom` | any | `number` | Uses `getter`/`setter` callbacks for arbitrary properties. |


## Extending PizzaSauce

### RegisterType

```lua
Sauce:RegisterType(name, handlers)
```

Register a custom animation type.

**handlers table:**

| Field | Signature | Description |
|-------|-----------|-------------|
| `init` | `function(target, from, to, tween) -> from` | Called once when animation starts. Resolve and return the `from` value. |
| `apply` | `function(target, from, to, t, tween)` | Called every tick. `t` is eased progress [0..1]. |
| `cleanup` | `function(target, tween)` | Optional. Called after animation finishes. |

```lua
Sauce:RegisterType("fontsize", {
  init = function(target, from)
    return from or 12
  end,
  apply = function(target, from, to, t)
    local size = from + (to - from) * t
    target:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
  end,
})

-- Usage:
Sauce:Tween(myText, { type = "fontsize", from = 12, to = 24, duration = 0.5 })
```

Custom types can also receive extra parameters. Any keys in `opts` that aren't standard Tween fields get forwarded directly onto the tween object:

```lua
Sauce:RegisterType("orbit", {
  apply = function(target, from, to, t, tween)
    local angle = t * tween.rotations * 2 * math.pi
    local x = tween.cx + math.cos(angle) * tween.radius
    local y = tween.cy + math.sin(angle) * tween.radius
    target:ClearAllPoints()
    target:SetPoint("CENTER", UIParent, "CENTER", x, y)
  end,
})

Sauce:Tween(frame, {
  type = "orbit", duration = 2, easing = "linear",
  cx = 0, cy = 0, radius = 100, rotations = 3,
})
```


### RegisterEasing

```lua
Sauce:RegisterEasing(name, fn)
```

Register a custom easing function.

| Param | Type | Description |
|-------|------|-------------|
| `name` | `string` | Name to reference the easing by. |
| `fn` | `function(t) -> t` | Takes normalized time [0..1], returns eased value. |

```lua
Sauce:RegisterEasing("smoothStep", function(t)
  return t * t * (3 - 2 * t)
end)

Sauce:FadeIn(frame, 0.5, "smoothStep")
```

### RegisterHelper

```lua
Sauce:RegisterHelper(name, fn)
```

Register a custom convenience function directly on the PizzaSauce instance. This lets you define reusable animation helpers that are called like built-in ones (`Sauce:MyAnimation(...)`).

| Param | Type | Description |
|-------|------|-------------|
| `name` | `string` | Method name to register. |
| `fn` | `function(self, ...) -> anim` | The animation factory. `self` is the PizzaSauce instance. |

```lua
Sauce:RegisterHelper("TextHeight", function(self, target, from, to, duration, easing, o)
  o = type(easing) == "table" and easing or (o or {})
  if type(easing) == "table" then easing = nil end
  return self:Tween(target, {
    type = "textheight", from = from, to = to,
    duration = duration or 0.3, easing = easing,
    delay = o.delay, onStart = o.onStart, onFinish = o.onFinish, onCancel = o.onCancel, defer = o.defer,
  })
end)

-- Usage:
Sauce:TextHeight(myText, 32, 64, 0.5, "outElastic")
```


## Animation Objects

All animation constructors return an object with these methods:

| Method | Description |
|--------|-------------|
| `:Play()` | Start (or restart) the animation. |
| `:Cancel()` | Stop the animation immediately. Triggers `onCancel`. |
| `:IsPlaying()` | Returns `true` if currently active. |

```lua
local anim = Sauce:FadeIn(frame, 0.5, nil, { defer = true })
anim:Play()
-- ...later...
if anim:IsPlaying() then
  anim:Cancel()
end
```

### Tween Setters

Tweens returned by `Sauce:Tween(...)` have setter methods for updating values between replays. These are primarily useful for the [reuse pattern](Performance.md#optimizing-for-memory-the-reuse-pattern).

| Method | Description |
|--------|-------------|
| `:SetFrom(val)` | Set the start value. |
| `:SetTo(val)` | Set the end value. |
| `:SetDuration(val)` | Set the duration in seconds. |
| `:SetDelay(val)` | Set the delay in seconds. |
| `:SetTarget(val)` | Set the target frame/texture. |

```lua
local tween = Sauce:Tween(frame, {
  type = "position", from = { 0, 0 }, to = { 100, 50 },
  duration = 0.5, defer = true,
})

-- Later: update and replay
tween:SetDuration(0.8)
tween:Play()
```
