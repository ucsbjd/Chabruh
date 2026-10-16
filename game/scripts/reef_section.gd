class_name ReefSection
extends RefCounted
## One stretch of reef under the wave (see SectionDirector): where it is in wave space and what it does to the wave.

var kind: int                        # a SectionDirector.Kind
var d_center: float                  # meters ahead of the peel point
var half_width: float                # it reaches this far either side of its centre
var delta_size: float                # offsets to WaveModel's size and hollowness dials at its centre
var delta_hollow: float
var peel_mult: float                 # how much faster the break peels over it


## `spec` is the kind's entry in SectionDirector.KINDS.
func _init(section_kind: int, at_d: float, spec: Dictionary) -> void:
	kind = section_kind
	d_center = at_d
	half_width = spec.half_width
	delta_size = spec.size
	delta_hollow = spec.hollow
	peel_mult = spec.peel


## 1 at the centre, easing to 0 at half_width either side.
func weight(d: float) -> float:
	return 1.0 - smoothstep(0.0, 1.0, absf(d - d_center) / half_width)
