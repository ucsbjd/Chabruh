class_name WaveSection
extends RefCounted
## One cross-section of the wave: the outline of the water surface in the plane across the crest.
## Points are (z, y) in meters: z runs toward the beach, y is height above the trough, and the
## outline is ordered from the far back of the wave, over the crest and around the lip, down the
## face, and out along the water in front. Water is always on the right of the direction of
## travel, so the outward normal (into the air) is the left normal, (-dy, dz).
##
## Next to each point the section keeps a few attributes for shading, all 0 to 1:
## height up the wave, foam, how deep inside the barrel the point is, and how thin (and so how
## translucent) the water is.

var points := PackedVector2Array()
var height_fraction := PackedFloat32Array()
var foam := PackedFloat32Array()
var cavity := PackedFloat32Array()
var translucency := PackedFloat32Array()

## The rideable face runs from the trough (face_to, u = 0) up to the top of the face (face_from, u = 1).
var face_from := 0
var face_to := 0
## Index of the lip's tip, and of the crest (the highest point).
var lip_tip := 0
var crest := 0


func add(point: Vector2, height_frac: float, foam_amount: float, cavity_amount: float, translucent: float) -> int:
	points.append(point)
	height_fraction.append(clampf(height_frac, 0.0, 1.0))
	foam.append(clampf(foam_amount, 0.0, 1.0))
	cavity.append(clampf(cavity_amount, 0.0, 1.0))
	translucency.append(clampf(translucent, 0.0, 1.0))
	return points.size() - 1


## The point `u` of the way up the rideable face: 0 at the trough, 1 at the top of the face.
func face_point(u: float) -> Vector2:
	var count := face_to - face_from
	var position := (1.0 - clampf(u, 0.0, 1.0)) * count
	var index := mini(int(position), count - 1)
	return points[face_from + index].lerp(points[face_from + index + 1], position - index)


## The outward (into the air) unit normal of the face at `u`. It blends from one outline point's normal to the next, so it
## turns smoothly as a board rides up or down the face instead of jumping at every point (which tipped the board and
## jolted the balance).
func face_normal(u: float) -> Vector2:
	var count := face_to - face_from
	var position := (1.0 - clampf(u, 0.0, 1.0)) * count
	var index := mini(int(position), count - 1)
	return _point_normal(face_from + index).lerp(_point_normal(face_from + index + 1), position - index).normalized()


## The normal at an outline point: between the normals of the segments on either side of it.
func _point_normal(index: int) -> Vector2:
	var before := points[maxi(index - 1, face_from)]
	var after := points[mini(index + 1, face_to)]
	var along := after - before
	return Vector2(-along.y, along.x).normalized()
