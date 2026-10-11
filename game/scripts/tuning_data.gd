class_name TuningData
extends Resource
## Feel dials. Anything that changes how riding feels lives here, so it can be tuned in one place.

## Fraction of input travel ignored around the centre (0 = none).
@export_range(0.0, 0.5, 0.01) var dead_zone: float = 0.08

## Exponent of the input response curve. 1 is linear, higher is softer near the centre.
@export_range(1.0, 3.0, 0.05) var response_curve: float = 1.6

## How far a full push reaches, as a fraction of the available range.
@export_range(0.3, 1.0, 0.01) var reach: float = 0.8
