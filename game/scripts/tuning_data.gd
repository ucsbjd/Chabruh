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

@export_group("Riding")
## How quickly the surfer follows where you point, per second.
@export var follow_rate: float = 6.0
## The fastest the surfer can climb the face, in face heights per second, and slide along the wave, in meters per second.
@export var max_height_speed: float = 2.4
@export var max_steer_speed: float = 14.0
## How much pumping up and down builds speed, and how fast that speed fades.
@export var pump_gain: float = 0.9
@export var energy_decay: float = 0.35
## How much speed times sharpness it takes to throw spray, and the pause between sprays in seconds.
@export var spray_threshold: float = 0.16
@export var spray_pause: float = 0.45
