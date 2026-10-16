class_name WaveMesh
extends RefCounted
## Sweeps the wave's cross-sections along the crest into a 3D mesh. Stations are packed close
## around the break, where the shape changes fastest, and spread out far down the line.
##
## Each vertex carries (in its colour) four shading attributes from the section: height up the
## wave, foam, how deep inside the barrel it is, and how thin (translucent) the water is. The
## UVs are (distance along the outline, distance along the crest) in meters, so a texture
## laid on the mesh is foreshortened by perspective for free.
##
## The vertex positions are the thrown lip. Two more shapes ride along so the shader can make the
## lip lift, throw and fall without a rebuild: CUSTOM0 holds (y, z) of the lifted shape and then
## of the landed shape, and UV2 holds (how much lip there is here, how much whitewater).

const CUSTOM_FORMAT := WaveMeshBuilder.CUSTOM_FORMAT


## Distances d (meters ahead of the peel point) of the stations, from far behind to far ahead.
static func station_distances() -> PackedFloat32Array:
	return WaveMeshBuilder.station_distances()


## Builds the whole mesh at once (about 15 ms on a laptop). WaveStage.reshape() spreads the same work over frames.
static func build(model: WaveModel) -> ArrayMesh:
	var builder := WaveMeshBuilder.new(model)
	builder.step(1 << 40)
	return builder.mesh
