extends Node
## Every colour in the game lives here. This is the starting palette from CLAUDE.md; tune freely.

const SKY_TOP := Color("#2B1B5E")
const SKY_VIOLET := Color("#7B3FA0")
const SKY_PINK := Color("#E8559A")
const SKY_PEACH := Color("#FF9A6B")
const SKY_HORIZON := Color("#FFD79A")

const SUN := Color("#FFE3A3")
const SUN_STRIPE := Color("#FF7A8A")

const WAVE_LIGHT := Color("#7AF2E0")
const WAVE_MID := Color("#19C9C0")
const WAVE_DEEP := Color("#0B7C8C")
const WAVE_SHADOW := Color("#25306B")

const FOAM_LIT := Color("#FFF4E6")
const FOAM_SHADE := Color("#C7A8E0")

const NEON_LIME := Color("#C6F135")
const NEON_PINK := Color("#FF3D8B")
const INK := Color("#1B1730")

## Sky colours from the top of the screen down to the horizon, evenly spaced.
const SKY_STOPS: Array[Color] = [SKY_TOP, SKY_VIOLET, SKY_PINK, SKY_PEACH, SKY_HORIZON]
