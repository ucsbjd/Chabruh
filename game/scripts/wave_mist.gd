class_name WaveMist
extends RefCounted
## The spray that blows off the crest, as a thin curtain standing on the wave's top edge and following
## it down the line. The curtain is only a surface to hang the shader's drifting droplets on: it is
## dense where the wave is breaking (and over the whitewater behind it), and sparse spindrift elsewhere.
## Vertex colour red is how much mist there is at that distance.

const FIRST := WaveMistBuilder.FIRST
const LAST := WaveMistBuilder.LAST
const STEP := WaveMistBuilder.STEP
const ROWS := WaveMistBuilder.ROWS
const HEIGHT_OF_WAVE := WaveMistBuilder.HEIGHT_OF_WAVE
const LEAN := WaveMistBuilder.LEAN


static func build(model: WaveModel) -> ArrayMesh:
	var builder := WaveMistBuilder.new(model)
	builder.step(1 << 40)
	return builder.mesh
