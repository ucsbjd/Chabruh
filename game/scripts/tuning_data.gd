class_name TuningData
extends Resource
## Feel dials. Anything that changes how riding feels lives here, so it can be tuned in one place.

## Fraction of input travel ignored around the centre (0 = none).
@export_range(0.0, 0.5, 0.01) var dead_zone: float = 0.08

## Exponent of the input response curve. 1 is linear, higher is softer near the centre.
@export_range(1.0, 3.0, 0.05) var response_curve: float = 1.6

## How far a full push reaches, as a fraction of the available range.
@export_range(0.3, 1.0, 0.01) var reach: float = 0.8

@export_group("Two-finger drag, wheel and keys")
## How far the height (0 to 1) moves per unit of two-finger scroll. The calibration run sets this.
@export var pan_height_gain: float = 0.02
## The same for steering along the wave.
@export var pan_steer_gain: float = 0.02
## Height (and steering) per unit of wheel scroll. A mouse notch is 1; a trackpad's two-finger scroll sends many
## small steps that add up. Set from the calibration run.
@export var wheel_height_step: float = 0.075
@export var wheel_steer_step: float = 0.05
## A trackpad sends bigger steps the faster the fingers move, so a snap would pin the surfer to the top or the
## bottom. Steps are compressed smoothly toward this size: small ones stay exact, a flick counts for more but never more than this.
@export var wheel_cap: float = 1.0
## While scrolling mostly one way, the other direction's stray steps are ignored: a step is dropped when the
## other direction has been this many times busier over the last `axis_lock_window` seconds.
@export var axis_lock_ratio: float = 3.0
@export var axis_lock_window: float = 0.15
## Flip these if the surfer goes the wrong way for your trackpad's scroll direction.
@export var invert_pan_height: bool = false
@export var invert_pan_steer: bool = false
## Per second, for held keys.
@export var key_rate: float = 0.9

@export_group("Carving")
## Gravity along the face (m/s squared), how much carving bleeds speed, and how fast a steady rhythm of pumping adds speed
## (m/s squared per radian of rhythm, scaled by the steepness and how much room there is to speed up).
@export var g_eff: float = 9.0
@export var k_carve: float = 0.12
@export var k_pump: float = 45.0
## Skidding across the line (pointing off the way the wave is breaking) costs speed in proportion to this.
@export var k_skid: float = 0.12
## The most sideways acceleration the board can hold (m/s squared): faster means wider turns.
@export var grip: float = 22.0
## How fast the wave's own draw lifts a surfer up the face, m/s (scaled by the wave's height).
@export var v_draw_base: float = 1.1
## The sharpest the board can turn, rad/s.
@export var max_omega: float = 3.5
## Until the finger controls (step 11), scrolling is a virtual stick: radians of heading per unit of height scrolled, and how
## long the stick takes to fade back to centre once the scrolling stops.
@export var stick_gain: float = 4.5
@export var stick_decay: float = 0.55
## With no input at all the wave carries him up the face at about this many meters per second of height.
@export var drift_climb: float = 0.3
## Until step 11: how hard the surfer drives toward the point on the wave being aimed at.
@export var drive_reach: float = 0.7
@export var drive_gain: float = 0.5
@export var max_drive: float = 6.0

@export_group("Spray")
## How much speed times sharpness it takes to throw spray, and the pause between sprays in seconds.
@export var spray_threshold: float = 0.16
@export var spray_pause: float = 0.45
