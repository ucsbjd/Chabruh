class_name Rider
extends RefCounted
## The surfer's motion on the wave, as a snowboard-style carving model (docs/finger-surf-controls.md has the reasoning).
## Where they are on the wave: `d`, meters ahead of the peel point, and `u`, height up the face (0 trough, 1 crest).
## How they move: a heading `theta` in the face plane (0 down the line toward +d, negative nose down toward the
## trough, positive nose up toward the lip), the turn rate `omega`, a speed `v` in m/s and a hip `compression`.
##
## Energy comes from the slope under the board and the water drawing up the face (WaveModel.draw_at). Both are strongest
## near the peak where the wave is breaking (small d, on the right of the screen); down the shoulder the face relaxes,
## the draw calms and the wave's push fades (WaveModel.power_at), so out in front he slows and the curl comes back to
## him, and the trough is flat. So dropping into the steep part builds speed, carrying it to the flat trough only coasts
## and then bleeds it away, and pointing across the line (instead of along the way the wave is breaking) costs speed to
## skidding and lets the curl gain on him. How fast he can change direction is limited by grip (sideways acceleration),
## so the faster he goes the wider he turns. Pumping, small strokes up and down the face, adds speed in proportion to the rhythm.
##
## Two moves off the top, told apart by where the turn starts (the Bells footage at 19 to 21 s and 22.6 to 24 s, and the
## slow-motion cutback, docs/balance.md, "Seventh pass"). Hitting the lip: a steep climb all the way to the lip, a
## violent snap that pivots the board on its tail, and all the energy goes there. The cutback: out in front, a turn
## started below the lip is a long carve on the rail that keeps swinging round for as long as the player holds the push,
## until he faces back toward the curl with his chest to the beach; let go (or meet the foam) and the board pivots back.
##
## Hitting the lip has the rhythm of the Bells footage (docs/balance.md, "Timing"): he explodes up out of the bottom
## turn (the press of the turn is stored as `charge` and released as the nose comes up, and the water rushing up the
## face carries him), stops at the top while the board comes round and his speed goes into the spray (`release`), then
## floats down with the wave (`afloat`: the rising water holds him, so he does not fall down the face) and only gets his
## speed back low on the face, in the next bottom turn. About 0.4 s up, 0.5 s at the top, 1.2 s down.
##
## Balance is the core of every move, as in the J-Bay footage (docs/balance.md): the board can swing through 150 degrees
## while the body stays close to upright, because the centre of mass always sits over the feet along the apparent gravity
## (gravity plus the pull of the turn). So he turns the way a skier or a cyclist does: the player's push sets a heading to
## aim for, he leans his centre of mass into the turn at the speed a body can move it, and the board carves only as
## tight as that lean holds. The turn rate follows from the lean, never the other way round, so no input can make him
## jerk. `balance` is the direction from his feet to his centre of mass (upright when trimming, square to the face when
## climbing or dropping straight, into the wave in a bottom turn, laid back in a top turn); the board rolls onto its rail
## by part of the lean and his legs take the rest. He crouches as the load lightens and extends under load, which is the
## rhythm of a real bottom turn and top turn. `strain` (debug) says how far the player's input asked for more than a body
## can do; above 1 a real surfer would have fallen, though here he never does.
## `aim` is the heading he has been asked for and `lead` how far it is from where the board points: the front arm and
## the head go there first, then the chest, the hips and the board (the J-Bay and Ethan Ewing footage). At the lip a hard
## reversal swings the board round on its tail from nearly straight up to straight down (`snap_omega`), and the lip holds
## the tail while it does (`snapping`), so the whole pivot happens at the top and he drops once the nose is round. A push
## holds until the board has turned to it, so one flick commits to a move (a drop, a climb to the lip); climbing hard he
## is committed to the lip and any reversal waits for the top. A cutback needs room on the shoulder; nearer the curl the
## same push is a snap. Steering back behind where he is stalls him: weight over the tail, speed bleeds off and the curl
## catches up. Closing on the curl is soft-limited and eases to a stop, and near it he settles: he tucks, the board comes
## round along the line and he finds his height and balance (`tuck`), then rides on. For now the old input is turned into
## pushes and a point to aim at along the wave; the finger controls replace that in step 11.
## Spray and the wake come from speed times sharpness, and the spray leaves off the outside of the turn (`spray_dir`).

const D_NEAR := -3.0                 # closest to the curl (inside the barrel zone)
const D_FAR := 16.0                  # far down the shoulder, where the face has relaxed
const STEER_CURVE := 1.6             # puts the pocket near the middle of the steering range
const CURL_CUSHION := 2.5            # meters from D_NEAR over which closing on the curl eases to a stop
const FAR_CUSHION := 2.0             # ...and from D_FAR over which running ahead does
const BACK_MAX := 1.0                # the fastest he closes on the curl, as a factor of the peel speed (a soft limit)
const SETTLE_FROM := 1.0             # meters ahead of the peel point: nearer the curl than this he tucks and settles
const SETTLE_HEIGHT := 0.45          # ...at this height on the face
const BARREL_HEIGHT := 0.3           # ...or this one in a barrel, low under the lip
const SETTLE_GAIN := 2.0             # meters per second of rise he steers for, per face height away from it
const SETTLE_PULL := 0.6             # ...and at most this many
const DROP_SINK_RATE := 0.8         # face heights a second of drop at which he is fully sunk for it
const TUCK_CROUCH := 0.35            # how much deeper he crouches, tucked by the curl
const U_LOW := 0.06
const U_HIGH := 0.96
const THETA_MIN := -2.9              # past straight down, round toward the curl: only reached in a cutback
const STICK_MIN := -1.45             # how far down the player's push can point him outside a cutback (almost straight down)
const DROP_MAX := 1.25               # the steepest drop he aims for outside a cutback (radians): a snap leaves him facing down the
                                     # face, but not straight down it, where the curl would gain on him all the way to the bottom
const STICK_FULL := 1.45             # radians: the push that points the board fully the way it was pushed
const STICK_REACHED := 0.15          # radians: once the board is this close to the heading asked for, the push starts to fade
const PUSH_MEMORY := 0.12           # seconds: pushes closer together than this are one gesture still coming in
const REVERSE_PUSH := 0.03           # face heights of push the other way that cancel the held push (a new move)
## Climbing harder than CLIMB_COMMIT, below the lip, he carries on up: the heading asked for cannot drop below
## CLIMB_HOLD until he reaches the lip, where the reversal becomes a snap.
const CLIMB_COMMIT := 0.85
const CLIMB_HOLD := 0.8
## The snap: at the lip, with the nose no lower than SNAP_HEADING, a reversal of more than SNAP_START radians commits to
## turning the nose at least SNAP_DOWN down the face. The lip holds the tail (over LIP_HOLD_TIME) until the nose is within
## SNAP_RELEASE of that heading, then he drops. Once started it carries through, whatever the input does.
const SNAP_HEADING := -0.3
const SNAP_START := 0.6
const SNAP_RELEASE := 0.3
const SNAP_DOWN := 0.6
const LIP_HOLD_TIME := 0.05
## The cutback (the slow-motion clip and Bells 22.6 to 24 s): out in front (more than CUT_ROOM ahead of the peel point),
## in the upper face (above CUT_FROM) but below the lip (CUT_TOP), a push down that starts while the nose is still up
## the face (above CUT_START_HEADING: turning back off a climb, not diving from trim; below CLIMB_COMMIT: a steep climb's
## reversal waits for the lip and snaps there), pushed hard (the stick past CUT_PUSH: a slow, gentle scroll is a carve)
## and held for CUT_HOLD_TIME, with the nose not yet far down the face (above CUT_LATE_HEADING), starts a long carve on
## the rail (a quicker push is an ordinary top turn): while
## the push is held (pushes no more than CUT_HOLD_GAP seconds apart) it swings on round toward the curl, up to
## CUTBACK_REACH at a steady sweep (CUT_SWEEP times the usual eagerness to turn), mostly carved (only CUT_PIVOT skids
## round on the tail, the buried rail holding CUT_GRIP more), bleeding
## CUT_DRAG of his speed a second: about 180 degrees in a second, as in the footage. Holding on, he rides back toward the
## curl. Let go once past straight down (CUT_PAST), or meet the foam (CUT_FOAM ahead of the peel point) or the bottom,
## and the water pivots the board back toward the line, quickly (up to REBOUND_OMEGA, reached at REBOUND_ACCEL; the
## footage's 180 degrees in about 0.3 s), and he is back to ordinary riding once his heading is above CUT_DONE. Let go
## before straight down and the turn just ends, a long carve down the face.
const CUT_ROOM := 4.0
const CUT_FOAM := 1.5
const CUT_PIVOT := 0.2
const CUT_GRIP := 0.6
const CUT_SWEEP := 2.5
const RAIL_SPRAY := 2.2              # how thick the sheet the rail throws carving round is, per unit of speed times turn rate
const CUT_DRAG := 0.5
const CUT_FROM := 0.3
const CUT_TOP := 0.8
const CUT_START_HEADING := 0.1
const CUT_LATE_HEADING := -1.2
const CUT_HOLD_TIME := 0.4
const CUT_PUSH := -1.0
const CUT_HOLD_GAP := 0.25
const CUTBACK_REACH := 3.0
const CUT_PAST := -1.6
const CUT_DONE := -0.5
const REBOUND_TIME := 0.15
const REBOUND_OMEGA := 10.0
const REBOUND_ACCEL := 90.0
## Pumping (the 300 fps footage): running behind where he is steered, he pumps for speed down the line, little turns
## up and down the face with the knees, one every PUMP_PERIOD seconds, PUMP_SWING radians each way, more the further
## behind he is (from PUMP_SLACK to PUMP_RANGE meters behind), folding PUMP_CROUCH as the nose goes down.
const PUMP_PERIOD := 1.3
const PUMP_SWING := 0.32
const PUMP_SLACK := 0.5
const PUMP_RANGE := 2.5
const PUMP_CROUCH := 0.18
const PUMP_HEADING := 0.6            # radians: pumping is small turns about the line; steeper than this a push is a move, not a pump
## Exploding up: loaded low on the face (below CHARGE_TOP), the press of the bottom turn and its turn rate charge him up
## (CHARGE_RATE a second per g of extra load or full turn rate), and as the nose comes up he extends and the charge
## pushes him up the face (LAUNCH_ACCEL at full charge), spent over about half a second (LAUNCH_SPEND a second); unused it
## leaks away (CHARGE_LEAK). Below the top of the face the water rushing up it carries a climbing board, taking LIFT_SHARE
## of the brake gravity puts on the climb.
const CHARGE_TOP := 0.5
const CHARGE_RATE := 2.2
const CHARGE_LEAK := 0.8
const LAUNCH_ACCEL := 12.0
const LAUNCH_SPEND := 2.0
const LIFT_SHARE := 0.6
## Stopping at the top (hitting the lip, never in a cutback): from TOP_FROM up the face (all of it by TOP_FULL), up by
## the lip, turning down at RELEASE_TURN rad/s or more
## releases fully: his speed falls toward STALL_SPEED (a factor of the peel speed) with a time constant of RELEASE_TIME,
## the board goes light and pivots, and the top holds him (RELEASE_HOLD of his drop) while it comes round. It is only
## as big as the climb before it: a nose-up heading of RELEASE_FROM radians gives none, RELEASE_STEEP or more a full
## release, remembered over APPROACH_MEMORY seconds. It builds at RELEASE_ATTACK a second and fades at
## RELEASE_DECAY once the nose points down the face (past RELEASE_DONE), unless he is still coming round in a cutback.
const TOP_FROM := 0.8
const TOP_FULL := 0.9
const RELEASE_TURN := 1.8
const RELEASE_FROM := 0.45
const RELEASE_STEEP := 1.05
const APPROACH_MEMORY := 0.8
const STALL_SPEED := 0.3
const RELEASE_TIME := 0.15
const RELEASE_ATTACK := 7.0
const RELEASE_DECAY := 3.0
const RELEASE_DONE := -1.0
const RELEASE_HOLD := 0.85
## Floating down: after a release he floats down with the wave. He feels only FLOAT_GRAVITY of the pull down the face,
## the water holds him back above FLOAT_SPEED (a factor of the peel speed) by FLOAT_DRAG a second, and the wave's drive
## waits. The water rushing up the face no longer holds a board that has stopped planing: he comes down with the lip
## and the foam, sinking FLOAT_SINK meters a second down the face (on a steep face) wherever the board points, and the
## section he hit carries him along with it, FLOAT_CARRY of the curl's pace, and the foam goes on carrying him while he
## gets his speed back (fading CARRY_FADE a second once the float is over), so the curl does not swallow him. The float lasts the descent (fading FLOAT_FADE a second) and goes quickly low on the face (below FLOAT_END,
## FLOAT_FADE_LOW a second) or once he turns back up, so the speed comes back in the next bottom turn. Floating, his rail
## throws FLOAT_QUIET less spray.
const FLOAT_GRAVITY := 0.45
const FLOAT_SPEED := 0.7
const FLOAT_DRAG := 6.0
const FLOAT_FADE := 0.35
const FLOAT_FADE_LOW := 3.0
const FLOAT_END := 0.45
const FLOAT_QUIET := 0.7
const FLOAT_SINK := 2.0
const FLOAT_CARRY := 0.75
const CARRY_FADE := 0.5
const THETA_MAX := 1.5               # almost straight up it
const COMPRESSION_K := 100.0         # hips: slightly underdamped, about 120 ms (natural frequency 10 rad/s)
const COMPRESSION_D := 17.0
const LEAD_MAX := 0.8
const MIN_SPEED := 0.45              # speeds are factors of the wave's own peel speed, so they follow the wave
const TRIM_SPEED := 1.05
const MAX_SPEED := 2.1
const OMEGA_FULL := 3.0              # turn rate that counts as a fully sharp carve, rad/s
const STICK_SMOOTHING := 0.10        # seconds: how smoothly the heading request follows the player's pushes
const MOVE_HOLD := 0.3               # seconds a move label stays once seen
const BURST_POWER := 1.9             # spray strength per unit of speed times sharpness
const SPRAY_STEP := 0.15             # a turn that bites this much harder (speed times sharpness) throws again, even straight after a burst
const LIP_SPRAY := 0.5               # how much more a snap at the lip throws
const CARRIED_MEMORY := 0.5          # seconds the speed he carried up the face is remembered for the release's spray
const RELEASE_SPRAY := 0.75          # speed to shed (a factor of the peel speed) that, fully released, throws as much as a
                                     # full-speed carve at full sharpness
const LIP_SPRAY_DIR := Vector3(0.25, 0.85, -0.45)  # hitting the lip the spray goes up and back over the crest (+x toward the curl, -z over the back)
const MIN_PRESS := 0.6               # the least the board presses on his feet, in g: high on a steep face the water rising up it holds the board
const LIGHT_UPRIGHT := 0.7           # nearly weightless (cresting, the lip holding the tail, dropping down a steep face) he keeps his
                                     # body this much closer to upright, as the footage shows, instead of square to a near-vertical face
const PITCH_MAX := 0.35              # how far his weight goes over the front or back foot, radians
const LOAD_SMOOTHING := 0.08         # seconds: the feel of the load through the legs
const CURVE_SMOOTHING := 0.15        # seconds for the push of the face's curve to come and go through his legs
const PIVOT_SMOOTHING := 0.15        # seconds for a pivot on the tail to build or fade...
const SNAP_SMOOTHING := 0.08         # ...and in a snap, where it comes on harder
const PIVOT_ACCEL := 10.0            # rad/s squared: the fastest a pivot spins up or settles (a top turn comes on gently)...
const SNAP_ACCEL := 45.0             # ...and in a snap, which still starts smoothly
const SNAP_FROM := 0.95              # face slope (radians) where turns start to pivot on the tail rather than carve...
const SNAP_FULL := 1.25              # ...and where they pivot fully
const FACE_CUSHION := 0.15           # how far from the top or the bottom of the face (in face heights) a climb or drop starts to ease
const GUARD_NEAR := 0.2              # seconds from the trough: the turn out of it is fully on...
const GUARD_FAR := 0.6               # ...and it starts this far out
const TOP_GUARD_NEAR := 0.08        # seconds from the top: a climb not committed to the lip is fully eased level...
const TOP_GUARD_FAR := 0.4           # ...and starts to ease this far out
const TOP_EASE := 0.08               # at the top of the face the heading eases level only over this last bit (face heights), so he
                                     # can drive up nearly vertically and hit the lip; the face's cushion slows the climb
const ROOM_FROM := -1.5              # meters from the peel point: behind here he runs along the line in the barrel...
const ROOM_FULL := 0.3               # ...and ahead of here he can point anywhere
const DRIVE_CAP := 1.2               # the most the arcade drive chases, as a factor of trim speed, before d is added
const ALONG_FROM := -0.1             # cos of the heading where the drive starts to push (pointing back toward the curl it does not)...
const ALONG_FULL := 0.4              # ...and where it pushes fully
const SHOULDER_PACE := 0.6          # where the wave has no push left, the drive keeps only this share of the curl's pace
const REF_D := 2.0                   # where the water drag is set from: the trim heading holds trim speed here, mid face
const BURIED_GRIP := 0.35           # how much more turn a buried rail holds, deep and low in a bottom turn
const LIP_FROM := 0.78               # height up the face where the board starts to pivot on its tail at the lip...
const LIP_FULL := 0.9                # ...and where it is all pivot
const PIVOT_SKID := 0.35             # speed lost per second per rad/s of pivot while the tail skids round
const LIP_GAIN := 4.0                # rad/s of pivot per radian still to turn when the board is light at the top...
const SNAP_GAIN := 7.0               # ...and in a snap (full speed until the last radian)
const STALL_SLACK := 1.0             # meters ahead of where he is steered before he starts to stall...
const STALL_RANGE := 3.0             # ...and how much farther ahead for a full stall
const STALL_SMOOTHING := 0.2         # seconds for his weight to go back over the tail
const STALL_STEER := 0.25            # how far behind the pocket the steering has to go for a full stall
## What a body can do, for the strain readout: how far the centre of mass can lag where the input wants it, how fast the
## input may swing the wanted lean, and the most load the legs hold, before a real surfer would have fallen.
const STRAIN_LAG := 0.7              # radians
const STRAIN_RATE := 4.0             # radians per second
const STRAIN_LOAD := 3.0             # g

var d := 3.0
var u := 0.5
var vel_d := 0.0                     # meters per second, positive is ahead (to the left)
var vel_u := 0.0                     # face heights per second
var theta := 0.0
var omega := 0.0
var v := 0.0                         # meters per second along the heading
var speed := 0.5                     # v scaled to 0..1 between the wave's slowest and fastest riding speed
var compression := 0.2
var compression_vel := 0.0
var lead := 0.0                      # how far the head and chest are already turned into the coming move, radians
var rail_roll := 0.0                 # radians, onto the inside rail (positive) or the outside rail (negative)
var sharpness := 0.0
var move := "trim"
var aim := 0.0                       # the heading he has been asked for, radians (after the guardrails)
var stall := 0.0                     # 0 to 1: weight back over the tail to slow down
var pivoting := 0.0                  # 0 to 1: how much the board is turning on its tail rather than carving
var cutting_back := false            # in a cutback: allowed round toward the curl, until the board comes back to the line
var rebounding := false              # the end of a cutback: the board pivoting back toward the line
var rail_spray := 0.0                # 0 to 1: the sheet of water the rail throws while it carves round in a cutback
var pumping := 0.0                   # 0 to 1: how hard he is pumping for speed
var snapping := false                # hitting the lip: the lip holds the tail while the board pivots round
var tuck := 0.0                      # 0 to 1: settling by the curl, small and compact
var lip_hit := 0.0                   # 0 to 1: how much the turn now is a snap off the lip
var spray_power := 0.0               # how much water the rail is throwing now (what the bursts are measured by)
var burst_release := 0.0             # 0 to 1: how much the last burst came from stopping at the top (the giant fan)
var charge := 0.0                    # 0 to 1: the bottom turn's press, stored to explode up the face
var release := 0.0                   # 0 to 1: stopping at the top, his speed going into the spray
var afloat := 0.0                    # 0 to 1: floating down with the wave after a release
var spray_dir := Vector3(0.6, 0.6, 0.0)  # world direction the spray leaves the tail
## The centre of mass. `lean` is across the board from the face's normal (positive toward the wave, the toe side, which
## turns the nose up the face; negative toward the beach, the heel side); `carve` is the part of it that turns him (the
## rest just holds his line on the slope); `pitch` is over the front (positive) or back foot.
var lean := 0.0
var lean_vel := 0.0
var carve := 0.0
var pitch := 0.0
var balance := Vector3.UP            # world direction from his feet to his centre of mass
var load_g := 1.0                    # how hard the board presses on his feet, in g
## Debug: how far the input asks for more than a body can do (above 1 a real surfer would fall), why, and how often.
var strain := 0.0
var strain_reason := ""
var falls := 0
var fall_reason := ""

var _fresh := true
var _stick := 0.0                    # radians of heading the player is asking for; fades when the input stops
var _stick_smooth := 0.0             # the same, smoothed so a scroll notch is not a jerk
var _against := 0.0                  # push against the held one so far
var _since_push := 1.0               # seconds since the last push
var _since_down := 1.0               # seconds since the last push down the face (holding a cutback)
var _carving_down := false           # a push down began below the lip off a climb that was not committed to it, and is still
                                     # held: a carved turn, never a snap
var _cut_armed := false              # ...and it began out in front: a cutback if it goes on
var _cut_held := 0.0                 # seconds the armed push has been held
var _lip_hold := 0.0                 # 0 to 1: how much the lip is holding the tail
var _snap_to := 0.0                  # the heading a snap is turning the nose to
var _last_burst := 0.0               # speed times sharpness of the last burst, while it is recent
var _stick_slow := 0.0               # a slow average of the stick: what is left over after removing it is the rhythm
var _pump_amount := 0.0              # how much rhythmic up-and-down the player is doing, smoothed
var _burst_ready_in := 0.0
var _pending_burst := 0.0
var _pending_release := 0.0
var _approach := 0.0                 # 0 to 1: how steeply he came up the face just now (how big a release can be)
var _carry := 0.0                    # 0 to 1: how much the section he hit and its foam carry him along (see FLOAT_CARRY)
var _carried := 0.0                  # the speed he brought up the face: falls slowly, so a release knows what it is shedding
var _move_until := 0.0
var _clock := 0.0
var _press_curve := 0.0              # m/s squared the concave face adds to the press, smoothed
var _push_along := 0.0               # m/s squared of drive (positive) or drag (negative) along the board, smoothed
var _pivot := 0.0                    # rad/s the board swings round on its tail while it is light, smoothed
var _pump_phase := 0.0
var _rebounding := false             # round in a cutback: the water is pivoting the board back
var _load_rhythm := 0.0              # the crouch that the rhythm of the load asks for, see _update_crouch
var _turning_g := 0.0                # the sideways pull of the carve, in g
var _lean_asked := 0.0
var _lean_target := 0.0
var _lean_asked_prev := 0.0
var _lean_asked_rate := 0.0
var _last_point := Vector3.ZERO
var _last_normal := Vector3.UP
var _straining := false


static func d_for(steer: float) -> float:
	return lerpf(D_NEAR, D_FAR, pow(clampf(steer, 0.0, 1.0), STEER_CURVE))


static func steer_for(meters: float) -> float:
	return pow(clampf((meters - D_NEAR) / (D_FAR - D_NEAR), 0.0, 1.0), 1.0 / STEER_CURVE)


static func u_for(height: float) -> float:
	return lerpf(U_LOW, U_HIGH, clampf(height, 0.0, 1.0))


static func height_for(face_height: float) -> float:
	return clampf((face_height - U_LOW) / (U_HIGH - U_LOW), 0.0, 1.0)


## Puts the rider somewhere, riding at trim speed and heading.
func place(meters_ahead: float, face_height: float) -> void:
	d = meters_ahead
	u = face_height
	vel_d = 0.0
	vel_u = 0.0
	omega = 0.0
	compression_vel = 0.0
	_fresh = true
	_stick = 0.0
	_stick_smooth = 0.0
	_stick_slow = 0.0
	_pump_amount = 0.0
	lean_vel = 0.0
	_pivot = 0.0
	stall = 0.0
	cutting_back = false
	_rebounding = false
	rebounding = false
	rail_spray = 0.0
	_since_down = 1.0
	_cut_armed = false
	_carving_down = false
	pumping = 0.0
	_press_curve = 0.0
	_push_along = 0.0
	_load_rhythm = 0.0
	_lean_asked_rate = 0.0
	strain = 0.0
	snapping = false
	tuck = 0.0
	_against = 0.0
	_lip_hold = 0.0
	_last_burst = 0.0
	aim = 0.0
	charge = 0.0
	release = 0.0
	afloat = 0.0
	_carry = 0.0
	_approach = 0.0


## The slope of the face under the board, in radians: from the model's real surface, so it is steepest near the peak
## and in the upper face and flattens down the shoulder and into the trough.
static func slope_at(model: WaveModel, at_d: float, at_u: float) -> float:
	return acos(clampf(model.surface_normal(at_d, at_u).y, 0.0, 1.0))


## `height_push` is how far the player pushed up (+) or down (-) the face this frame, in face heights (scroll, keys, drag).
func step(delta: float, steer: float, height_push: float, model: WaveModel, tuning: TuningData) -> void:
	if delta <= 0.0:
		return
	_clock += delta
	var peel := model.peel_speed()
	var v_min := MIN_SPEED * peel
	var v_trim := TRIM_SPEED * peel
	var v_max := MAX_SPEED * peel
	# u runs along the face's outline (not its height), so a speed along the face is turned into a rate of u through
	# the length of face here: a climb is as quick on the gentle foot of the face as on its steep top.
	var face_len := maxf(1.0, model.face_length_at(d, u))
	# The face here: its outward normal n, the way the nose points (f), and the side a positive turn swings it toward
	# (s: up the face when he runs down the line).
	var here := model.surface_point(d, u)
	var n := model.surface_normal(d, u).normalized()
	var phi := acos(clampf(n.y, 0.0, 1.0))
	var sin_phi := sin(phi)
	var g := tuning.g_eff
	# The water rising up the face lifts him (strongest in the pocket and up by the lip, calm down the shoulder). With no
	# input he is carried up it slowly (drift_climb, meters per second up the face); holding his line takes a small nose-down
	# heading, and pointed down the line that lift is what drives him.
	var draw := tuning.v_draw_base * model.draw_at(d, u)
	# (floating down after a release it no longer holds him up: he sinks with the lip and the foam)
	var lift := lerpf(draw, -FLOAT_SINK * sin_phi, afloat)
	var fresh := _fresh
	if _fresh:
		v = v_trim
	# Near the curl he settles: instead of drifting up he steers for a comfortable height (low under the lip in a barrel).
	var near_curl := 1.0 - smoothstep(D_NEAR + 0.5, SETTLE_FROM, d)
	var settle := clampf((lerpf(SETTLE_HEIGHT, BARREL_HEIGHT, model.barrel()) - u) * SETTLE_GAIN, -SETTLE_PULL, SETTLE_PULL)
	var climb := lerpf(tuning.drift_climb, settle, near_curl)
	var theta_trim := asin(clampf((climb - draw) / maxf(v, 0.5), -0.6, 0.6))
	if _fresh:
		_fresh = false
		theta = theta_trim
		_last_point = here
		_last_normal = n

	# The player's pushes (scroll, keys, drag) move a virtual stick, so scrolling down points the nose down. While a push
	# is still coming in the stick fades back toward centre as it goes (a slow steady scroll is a gentle carve); once the
	# gesture stops, what is left holds while the board is still turning to it (one flick commits to a drop or a climb to
	# the lip) and fades once he has got there, so letting go lets the wave take him again. Pushing the other way starts a
	# new move at once. A smoothed copy steers, so there are no jerks.
	_since_down = 0.0 if height_push < 0.0 else _since_down + delta
	_update_cutback(height_push, delta)
	var stick_min := -CUTBACK_REACH if cutting_back else STICK_MIN
	if height_push * _stick < 0.0:
		_against += absf(height_push)
		if _against > REVERSE_PUSH:
			_stick = 0.0
	elif height_push != 0.0:
		_against = 0.0
	# (the move is done once the board has turned to it, or the face has run out the way he was pushed)
	var reached := 1.0 - smoothstep(STICK_REACHED, 3.0 * STICK_REACHED, absf(aim - theta))
	# (a cutback carves round across the face, so reaching the lower face does not end it)
	if not cutting_back:
		reached = maxf(reached, smoothstep(0.35, 0.2, u) if _stick < 0.0 else smoothstep(0.75, 0.9, u))
	_since_push = 0.0 if height_push != 0.0 else _since_push + delta
	if _since_push < PUSH_MEMORY:
		reached = 1.0
	# (coming round in a cutback the push holds until he is round and rebounds)
	var fade := 1.0 if cutting_back and not _rebounding else exp(-delta / lerpf(tuning.stick_hold, tuning.stick_decay, reached))
	_stick = clampf(_stick * fade + height_push * tuning.stick_gain, stick_min, STICK_FULL)
	# (holding a cutback swings him all the way round: how long it is held, not how hard, says how far)
	if cutting_back and not _rebounding:
		_stick = -CUTBACK_REACH
	if _rebounding:
		_stick = lerpf(_stick, 0.0, 1.0 - exp(-delta / REBOUND_TIME))
	var want_d := d_for(steer)
	# Pumping: a steady rhythm of small turns, folded into the stick so it also feeds the pump's speed.
	pumping = lerpf(pumping, clampf((want_d - d - PUMP_SLACK) / PUMP_RANGE, 0.0, 1.0) * (0.0 if cutting_back else 1.0), 1.0 - exp(-delta / 0.5))
	_pump_phase = fmod(_pump_phase + TAU * delta / PUMP_PERIOD, TAU)
	var pump_turn := PUMP_SWING * pumping * sin(_pump_phase)
	_stick_smooth = lerpf(_stick_smooth, _stick + pump_turn, 1.0 - exp(-delta / STICK_SMOOTHING))
	_stick_slow = lerpf(_stick_slow, _stick_smooth, 1.0 - exp(-delta / 0.6))
	# (only small strokes are a rhythm: a big swing of the stick is a move, and what is left of a turn off the top or a
	# cutback once it is over is not a stroke either)
	if cutting_back or _carry > 0.0:
		_stick_slow = _stick_smooth
	_pump_amount = lerpf(_pump_amount, minf(absf(_stick_smooth - _stick_slow), PUMP_HEADING), 1.0 - exp(-delta / 0.35))
	# A small push turns him from his trim heading; a full one points the board the way he pushed (straight up the face).
	var target_theta := clampf(theta_trim * (1.0 - clampf(absf(_stick_smooth) / STICK_FULL, 0.0, 1.0)) + _stick_smooth, THETA_MIN, THETA_MAX)
	var wanted := target_theta  # what the player asks for, before the face's guardrails (only this can start a snap)
	# Inside the barrel, behind the peel point, there is no room to point across the line: the heading is held along the
	# way the wave is breaking. In the pocket in front of the curl, and anywhere ahead of it, he can go straight down or up
	# (the pocket is where the vertical turns happen).
	var room := smoothstep(ROOM_FROM, ROOM_FULL, d)
	var limit := lerpf(0.35, THETA_MAX, room)
	var low_limit := lerpf(0.35, -THETA_MIN if cutting_back else DROP_MAX, room)
	target_theta = clampf(target_theta, -low_limit, limit)
	# Soft guardrails: scoop out of the trough and ease off at the crest instead of hitting them, starting while there is
	# still time for a body to make the turn (a surfer sets up a bottom turn or a top turn well before the end of the face).
	var heading_rise := (v * sin(theta) + lift) / face_len  # u a second, before the face's ends soften it
	if target_theta < 0.0:
		var to_bottom := (u - U_LOW) / maxf(-heading_rise, 0.001)
		# (coming round in a cutback the board is not diving at the trough, so only the trough itself stops it)
		var early := 1.0 if cutting_back and not _rebounding else smoothstep(GUARD_NEAR, GUARD_FAR, to_bottom)
		target_theta *= minf(clampf(u / 0.15, 0.0, 1.0), early)
	if target_theta > 0.0:
		var ease := clampf((U_HIGH - u) / TOP_EASE, 0.0, 1.0)
		# A climb that is not committed to the lip rounds into a top turn while there is still time to make it; a vertical
		# one drives on into the lip and snaps there.
		if theta < CLIMB_COMMIT:
			var to_top := (U_HIGH - u) / maxf(v * sin(theta) / face_len, 0.001)
			ease = minf(ease, smoothstep(TOP_GUARD_NEAR, TOP_GUARD_FAR, to_top))
		target_theta *= ease
	# Driving hard up the face he is committed to the lip: a real surfer going vertical cannot turn back halfway up, so the
	# reversal waits for the top, where the lip takes the tail and it becomes a snap.
	if theta > CLIMB_COMMIT and u < LIP_FROM and not cutting_back:
		target_theta = maxf(target_theta, minf(theta, CLIMB_HOLD))
	var at_lip := smoothstep(LIP_FROM, LIP_FULL, u)
	_update_snap(at_lip, maxf(wanted, -DROP_MAX))
	if snapping:
		target_theta = _snap_to
	aim = target_theta

	var t_crest := Vector3(-1.0, 0.0, 0.0)
	var t_face := t_crest.cross(n).normalized()
	t_crest = n.cross(t_face).normalized()
	var f := t_crest * cos(theta) + t_face * sin(theta)
	var s := t_face * cos(theta) - t_crest * sin(theta)
	# How hard the board presses up into his feet across the face: gravity's share, plus the concave face pushing back
	# as he rides up or down its curve (from how the normal turned under him since the last step).
	var curve := -((here - _last_point) / delta).dot((n - _last_normal) / delta)
	_press_curve = lerpf(_press_curve, clampf(curve, -g, 2.0 * g), 1.0 - exp(-delta / CURVE_SMOOTHING))
	_last_point = here
	_last_normal = n
	var press := maxf(g * n.y + _press_curve, MIN_PRESS * g)
	# The lean that holds this heading on the slope without turning: with the nose down the line it is the slope itself
	# (he stands upright); with the nose straight up or down the face it is none (he stands square to the face).
	var hold := atan2(g * s.y, press)
	if fresh:
		lean = hold
		_lean_target = hold
		_lean_asked = hold
		_lean_asked_prev = hold

	# Tier 1: the head and chest turn into the move at once.
	lead = clampf(target_theta - theta, -LEAD_MAX, LEAD_MAX)
	# Tier 2: the centre of mass. The turn he wants (toward the aimed heading, no sharper than grip allows) needs a lean
	# that keeps the pull of the turn and gravity together through his feet. He moves toward it as fast as a body can.
	# When the board is light (cresting the face) or high on a face too steep to carve against (at the lip) he leans less
	# and swings the board round under him on its tail instead, the way a snap pivots: the body stays over the board while
	# the board comes round.
	var steep := smoothstep(SNAP_FROM, SNAP_FULL, phi) * clampf((1.8 - load_g) / 0.8, 0.0, 1.0)  # (not while still driving hard up the face)
	# At the very top only the tail is still in the water, so there it pivots however hard he came up (at_lip), and in a
	# snap the lip holds the tail until the nose is round. Coming round in a cutback the board is carved on its rail with a
	# little skid off the tail, throwing the fan; rebounding off the foam it pivots. Turning off the top, while his speed
	# goes into the spray (release), only the tail and rail are biting and the board swings round at the top.
	var coming_round := (1.0 if _rebounding else CUT_PIVOT) if cutting_back else 0.0
	var light := 1.0 if snapping else maxf(maxf(clampf((1.0 - load_g) / 0.5, 0.0, 1.0), steep), maxf(maxf(at_lip, coming_round), release))
	pivoting = light
	# Deep in a compressed bottom turn the rail is buried and holds a tighter turn: that is what sends him vertical.
	var buried := smoothstep(0.5, 0.9, compression) * clampf((0.6 - u) / 0.3, 0.0, 1.0)
	# (and carving round in a cutback the whole rail is buried, so it holds a tighter, sweeping turn)
	var carving_back := 1.0 if cutting_back and not _rebounding else 0.0
	var omega_cap := minf(tuning.max_omega, tuning.grip * (1.0 + BURIED_GRIP * buried + CUT_GRIP * carving_back) / maxf(v, 4.0))
	# (a cutback sweeps round at a steady rate all the way, rather than easing off as it nears facing back)
	var want_omega := clampf(tuning.head_gain * (1.0 + (CUT_SWEEP - 1.0) * carving_back) * (target_theta - theta), -omega_cap, omega_cap)
	_lean_asked = atan2(v * want_omega + g * s.y, press)  # the whole turn the input asks for (the strain readout judges this)
	# Light, he stays over the board (close to the lean that holds his line) and lets the pivot turn it.
	_lean_target = clampf(hold + (_lean_asked - hold) * (1.0 - light * tuning.pivot_share), hold - tuning.carve_max, hold + tuning.carve_max)
	var wn := tuning.lean_response
	lean_vel = clampf(lean_vel + (wn * wn * (_lean_target - lean) - 2.0 * wn * lean_vel) * delta, -tuning.lean_rate_max, tuning.lean_rate_max)
	lean += lean_vel * delta
	carve = lean - hold
	# Tier 3: the board carves only as tight as his lean holds, so the turn rate is as smooth as his body. While it is
	# light the pivot makes up the rest of the turn he asks for; the pivot skids, so his body only follows the carving part.
	var carve_omega := clampf((press * tan(lean) - g * s.y) / maxf(v, 3.0), -omega_cap, omega_cap)
	_turning_g = absf(v * carve_omega) / g
	# The pivot is not limited by grip: with only the tail in the water a hard reversal at the lip swings the board from
	# nearly straight up to straight down in about half a second (hitting the lip).
	# (a snap, the foam knocking the board back round in a cutback and a full release at the top pivot hard; a light top
	# turn comes on gently)
	var hard := 1.0 if snapping or _rebounding else release
	var pivot_max := REBOUND_OMEGA if _rebounding else tuning.snap_omega
	var want_snap := clampf(lerpf(LIP_GAIN, SNAP_GAIN, hard) * (target_theta - theta), -pivot_max, pivot_max)
	var pivot_to := lerpf(_pivot, light * (want_snap - carve_omega), 1.0 - exp(-delta / lerpf(PIVOT_SMOOTHING, SNAP_SMOOTHING, hard)))
	_pivot = move_toward(_pivot, pivot_to, (REBOUND_ACCEL if _rebounding else lerpf(PIVOT_ACCEL, SNAP_ACCEL, hard)) * delta)
	# (the foam knocks the board back round in a cutback faster than any snap: about 180 degrees in 0.3 s)
	var omega_limit := maxf(tuning.max_omega, (REBOUND_OMEGA if _rebounding else tuning.snap_omega) * light)
	omega = clampf(carve_omega + _pivot, -omega_limit, omega_limit)
	theta += omega * delta
	if theta < THETA_MIN or theta > THETA_MAX:
		theta = clampf(theta, THETA_MIN, THETA_MAX)
		omega = 0.0
	_update_cycle(delta)

	# Energy. The slope gives speed going down and takes it going up. Water drag is chosen so that the trim heading settles
	# at trim speed in the middle of the wave; carving and skidding across the line take more. Pumping adds speed in
	# proportion to the rhythm of the strokes, to how steep the face is here and to how much room there is left to speed up.
	# A turn off the top runs on its own rhythm (_update_cycle): launched up the face, stopped at the top, floated down.
	var mid_slope := slope_at(model, REF_D, 0.5)
	var ref_draw := tuning.v_draw_base * model.draw_at(REF_D, 0.5)
	var ref_trim := asin(clampf((ref_draw - tuning.drift_climb) / (v_trim * sin(mid_slope)), 0.0, 0.6))
	var k_water := g * sin(mid_slope) * sin(ref_trim) / (v_trim * v_trim)
	var climbing := clampf(sin(theta), 0.0, 1.0)
	var dropping := clampf(-sin(theta), 0.0, 1.0)
	var top := smoothstep(TOP_FROM, TOP_FULL, u)
	# (held at the lip with the nose already down he is not dropping yet, so the slope gives him nothing; floating down
	# after a release the water rising up the face holds him, so he feels only part of it; climbing below the top the
	# water rushing up the face carries the board and takes part of the brake)
	var a_slope := -g * sin_phi * sin(theta)
	if theta < 0.0:
		a_slope *= (1.0 - _lip_hold) * lerpf(1.0, FLOAT_GRAVITY, afloat)
	else:
		a_slope *= 1.0 - LIFT_SHARE * (1.0 - top)
	# Steered back behind where he is, he stalls: weight over the tail, the nose lifts and the water holds him back,
	# so the curl catches up and he can sit deep in the pocket, then the steeper face there sends him off again.
	var steering_back := clampf((RideInput.REST_STEER - steer) / STALL_STEER, 0.0, 1.0)
	stall = lerpf(stall, steering_back * clampf((d - want_d - STALL_SLACK) / STALL_RANGE, 0.0, 1.0), 1.0 - exp(-delta / STALL_SMOOTHING))
	# Swinging the board round on its tail throws the big fan, and that spray is speed: a pivot skids the speed off.
	var a_drag := -k_water * v * v - tuning.k_carve * absf(omega) * v - tuning.k_skid * absf(sin(theta)) * v - tuning.stall_drag * stall * v - PIVOT_SKID * pivoting * absf(_pivot) * v
	if cutting_back and not _rebounding:
		a_drag -= CUT_DRAG * v
	# Turning off the top his speed goes into the spray: it falls toward a stall while the board comes round. Floating
	# down after it, the rising water holds him back above a gentle pace, so he never rockets down the middle of the face.
	var v_stall := STALL_SPEED * peel
	var a_release := -release * maxf(v - v_stall, 0.0) / RELEASE_TIME
	var a_float := -FLOAT_DRAG * afloat * dropping * maxf(v - FLOAT_SPEED * peel, 0.0)
	var headroom := clampf(1.0 - speed, 0.0, 1.0)
	var push := model.power_at(d)  # the wave's push here: all of it in the pocket, fading down the shoulder
	# (pumping works off the wave's own push too, so on the soft shoulder it gains little; and it is small turns about the
	# line, so a big move up or down the face, or floating down after one, is not a pump)
	var a_pump := tuning.k_pump * _pump_amount * sin_phi * headroom * push * push
	a_pump *= (1.0 - smoothstep(PUMP_HEADING, PUMP_HEADING + 0.4, absf(theta))) * (1.0 - maxf(release, afloat))
	# Out of the bottom turn the press he stored launches him up the face (below the top, where it is spent).
	var a_launch := LAUNCH_ACCEL * charge * climbing * (1.0 - top) * push
	# Drive toward the speed that holds (or closes on) the point being aimed at; the slope still shows through. Pointing
	# well up or down the face it does not chase the curl harder than DRIVE_CAP times trim speed (gravity does the rest),
	# so he is not flying through the bottom turn too fast to come round. It is the wave's push, so it fades down the
	# shoulder (out in front he slows and the curl comes back to him), and it only pushes along the line: pointed back
	# toward the curl in a cutback it does nothing, so he is not driven back into it.
	var keep_pace := minf(peel / maxf(cos(theta), 0.35), DRIVE_CAP * v_trim) * lerpf(SHOULDER_PACE, 1.0, push)
	var want_v := keep_pace + clampf(tuning.drive_reach * (want_d - d), -0.4 * peel, 0.8 * peel) * push
	var along := smoothstep(ALONG_FROM, ALONG_FULL, cos(theta))
	# (it brakes gently, so speed he has earned by diving or pumping is not taken straight back)
	var a_drive := clampf(tuning.drive_gain * (want_v - v) * (1.0 if want_v > v else 0.3), -tuning.max_drive, tuning.max_drive) * along * push * push
	# (it waits while he floats down after a release)
	a_drive *= 1.0 - afloat
	# (stopped at the top, and floating down after it, he can be slower than he ever is riding)
	var floor_v := lerpf(v_min, v_stall, maxf(release, afloat))
	v = clampf(v + (a_slope + a_drag + a_pump + a_drive + a_launch + a_release + a_float) * delta, floor_v, v_max)
	speed = clampf(remap(v, v_min, v_max, 0.0, 1.0), 0.0, 1.0)

	# Move along the wave: ahead of the peel point while faster than the curl, up the face by the heading's rise. Closing
	# on the curl is soft-limited (BACK_MAX) and eases to a stop near the end of the range, as does running out to the far
	# end of the shoulder, so he never slams into either. The top and the bottom of the face take him softly (the lip
	# carries a board along it), so a climb never stops dead, and in a snap the lip holds the tail until the nose is round.
	# (stopped at the top and floating down after it he comes down with the section he hit, and the foam carries him on
	# while he gets his speed back, so the curl gains on him by only part of its pace: a re-entry lands at the foot of
	# the curl, where the next bottom turn has the wave's power)
	var run := v * cos(theta) - peel * (1.0 - FLOAT_CARRY * _carry)
	if run < 0.0:
		var back_max := BACK_MAX * peel
		run = -back_max * tanh(-run / back_max) * clampf((d - D_NEAR) / CURL_CUSHION, 0.0, 1.0)
	else:
		run *= clampf((D_FAR - d) / FAR_CUSHION, 0.0, 1.0)
	var new_d := clampf(d + run * delta, D_NEAR, D_FAR)
	var rise := (v * sin(theta) + lift) / face_len
	rise *= clampf((U_HIGH - u) / FACE_CUSHION, 0.0, 1.0) if rise > 0.0 else clampf((u - U_LOW) / FACE_CUSHION, 0.0, 1.0)
	_lip_hold = lerpf(_lip_hold, 1.0 if snapping else 0.0, 1.0 - exp(-delta / LIP_HOLD_TIME))
	# (the top holds him while the board comes round, then he lets go and floats down)
	if rise < 0.0:
		rise *= (1.0 - _lip_hold) * (1.0 - RELEASE_HOLD * release)
	var new_u := clampf(u + rise * delta, U_LOW, U_HIGH)
	vel_d = (new_d - d) / delta
	vel_u = (new_u - u) / delta
	d = new_d
	u = new_u

	# Balance: what he stands against is the board's acceleration minus gravity. Along the board that is the water's drag
	# and his own pumping (gravity along the slope, and the wave's drive that stands in for it, move his body and the
	# board alike, so they do not tilt him), across it the turn against the slope, and up through the deck the press.
	# His centre of mass sits over his feet along it: a hard turn's drag puts him back over the tail.
	_push_along = lerpf(_push_along, a_drag + a_pump + a_release + a_float, 1.0 - exp(-delta / LOAD_SMOOTHING))
	pitch = clampf(atan2(_push_along, press), -PITCH_MAX, PITCH_MAX)
	var felt := f * press * tan(pitch) + s * (v * carve_omega + g * s.y) + n * press
	# With hardly any press under the board (gravity nearly all along a near-vertical face) the felt pull is tiny, so his
	# body is free to stay near upright while the board goes vertical under him (J-Bay, 15.4 to 18.6 s).
	var weightless := maxf(clampf(1.0 - (g * n.y + _press_curve) / (MIN_PRESS * g), 0.0, 1.0), _lip_hold)
	balance = felt.normalized().lerp(Vector3.UP, LIGHT_UPRIGHT * weightless).normalized()
	load_g = lerpf(load_g, felt.length() / g, 1.0 - exp(-delta / LOAD_SMOOTHING))
	# The board rolls onto its rail by part of the lean that turns him, and a little onto its uphill rail to hold the line;
	# his knees and ankles take the rest, never more than a body can bend.
	var rail := tuning.rail_share * carve + tuning.trim_rail * hold
	rail = clampf(rail, lean - tuning.body_tilt_max, lean + tuning.body_tilt_max)
	rail_roll = clampf(rail, -tuning.rail_max, tuning.rail_max)
	tuck = near_curl
	_update_crouch(delta, model, tuning)
	# The spray leaves the tail off the outside of the turn (the rail pushes the water away from the turn's centre), back
	# along the board and up off the face; snapping off the lip it goes up and back over the crest.
	lip_hit = smoothstep(0.68, 0.9, u) * clampf(-omega / 1.5, 0.0, 1.0)
	var outward := -signf(omega) * clampf(absf(omega) / 0.6, 0.0, 1.0) * s
	spray_dir = (-0.45 * f + 0.85 * outward + (0.35 + 0.65 * lip_hit) * n).normalized()
	spray_dir = spray_dir.lerp(LIP_SPRAY_DIR.normalized(), lip_hit * 0.75).normalized()
	_update_strain(delta)

	# Sharpness: how hard the board is turning, held a moment so a snap throws spray and a wobble does not.
	sharpness = maxf(clampf(absf(omega) / OMEGA_FULL, 0.0, 1.0), sharpness)
	sharpness *= exp(-6.0 * delta)

	# Carving round in a cutback the rail throws a sheet of water the whole way, a curtain that sweeps round with the board.
	rail_spray = clampf(RAIL_SPRAY * speed * absf(omega) / OMEGA_FULL, 0.0, 1.0) * carving_back
	rebounding = _rebounding
	_update_spray(delta, tuning, peel)
	_update_move(model, peel)


## The hips. He sinks with speed, in the tube and as he points down the face (getting ready to load the bottom turn), and
## on top of that follows the rhythm of the load: he folds as the board goes light (cresting the face), as the curve at
## the foot of the face pushes up into him and through the first half of a turn (he absorbs it), and extends through the
## second half as the nose comes up (he pushes through it). So he is deepest, head down by his hips, in the heart of a
## bottom turn and tallest as he comes out of it, which is the rhythm of the footage, and the same rhythm pumps a board.
func _update_crouch(delta: float, model: WaveModel, tuning: TuningData) -> void:
	var rising := smoothstep(-0.3, 0.3, theta)
	var folding := clampf(1.0 - load_g, 0.0, 1.0) + 0.6 * maxf(_press_curve, 0.0) / tuning.g_eff + _turning_g * (0.5 * (1.0 - rising) - rising)
	_load_rhythm += (tuning.crouch_rhythm * folding - _load_rhythm / tuning.crouch_memory) * delta
	_load_rhythm = clampf(_load_rhythm, -0.3, 0.45)
	# (he sinks as he drops down the face, not just for pointing down it: run along the bottom, he comes back up)
	var dropping := clampf(-theta / 0.9, 0.0, 1.0) * clampf(-vel_u / DROP_SINK_RATE, 0.0, 1.0)
	# Round in a cutback he is very compact, knees almost touching; pumping, he folds as the nose goes down the face.
	var round_back := clampf((-theta - 1.7) / 0.6, 0.0, 1.0)
	var pump_fold := PUMP_CROUCH * pumping * -sin(_pump_phase)
	var target_crouch := clampf(0.15 + 0.2 * speed + 0.45 * dropping + 0.35 * round_back + pump_fold + _load_rhythm + model.barrel_amount_at(d, u) * 0.65 + TUCK_CROUCH * tuck, 0.05, 1.0)
	compression_vel += (COMPRESSION_K * (target_crouch - compression) - COMPRESSION_D * compression_vel) * delta
	compression = clampf(compression + compression_vel * delta, 0.0, 1.0)


## Debug: how far the input asks for more than a body can do. The surfer never falls (that would punish), but this says
## when a real one would have: his centre of mass far behind where the input wants it, the input swinging the wanted
## lean faster than a body moves, or more load than legs hold.
func _update_strain(delta: float) -> void:
	# (in a cutback the move, not the hands, sets the turn all the way round and then knocks it back, so it is not judged)
	if cutting_back:
		_lean_asked_prev = _lean_asked
		_lean_asked_rate = 0.0
		strain = 0.0
		_straining = false
		return
	_lean_asked_rate = lerpf(_lean_asked_rate, absf(_lean_asked - _lean_asked_prev) / delta, 1.0 - exp(-delta / 0.12))
	_lean_asked_prev = _lean_asked
	var lag := absf(_lean_target - lean) / STRAIN_LAG
	var swing := _lean_asked_rate / STRAIN_RATE
	var heavy := load_g / STRAIN_LOAD
	strain = maxf(lag, maxf(swing, heavy))
	strain_reason = "lean far behind the input" if strain == lag else ("input too jerky" if strain == swing else "too many g")
	if strain > 1.0 and not _straining:
		falls += 1
		fall_reason = strain_reason
	_straining = strain > (0.8 if _straining else 1.0)


## The rhythm of a turn off the top (the Bells footage). Loaded low on the face (the press of the bottom turn and its
## turn up the face) he stores a `charge`, and once the nose is up he spends it exploding up the face. Turning hard off
## the top is a `release`: he stops there while the board comes round and his speed goes into the spray. After it he is
## `afloat`, floating down with the wave: that lasts the descent and goes quickly once he is low or turning back up.
func _update_cycle(delta: float) -> void:
	var low := 1.0 - smoothstep(CHARGE_TOP - 0.15, CHARGE_TOP, u)
	var loading := clampf(load_g - 1.0, 0.0, 1.0) + clampf(omega / OMEGA_FULL, 0.0, 1.0)
	if low * loading > 0.05:
		charge = minf(charge + CHARGE_RATE * low * loading * delta, 1.0)
	else:
		charge = move_toward(charge, 0.0, (LAUNCH_SPEND if sin(theta) > 0.2 else CHARGE_LEAK) * delta)
	var top := smoothstep(TOP_FROM, TOP_FULL, u)
	var turning_down := clampf(-omega / RELEASE_TURN, 0.0, 1.0)
	# (it is only as big as the climb that came before it: driving steeply up the face is a full stop at the top, a
	# shallow one only a carved top turn, and trimming high then diving is a drop. Once the nose points down the face it
	# is done. A cutback is a carve, not a stop)
	_approach = maxf(smoothstep(RELEASE_FROM, RELEASE_STEEP, theta), _approach * exp(-delta / APPROACH_MEMORY))
	var still_round := smoothstep(RELEASE_DONE, RELEASE_DONE + 0.4, theta)
	var wanted := 0.0 if cutting_back or _carving_down else top * turning_down * _approach * still_round
	release = move_toward(release, wanted, (RELEASE_ATTACK if wanted > release else RELEASE_DECAY) * delta)
	afloat = maxf(afloat, smoothstep(0.15, 0.45, release))
	if release < 0.15:
		var ending := maxf(1.0 - smoothstep(FLOAT_END - 0.1, FLOAT_END + 0.1, u), smoothstep(0.1, 0.4, theta))
		afloat = move_toward(afloat, 0.0, lerpf(FLOAT_FADE, FLOAT_FADE_LOW, ending) * delta)
	_carry = maxf(maxf(release, afloat), _carry - CARRY_FADE * delta)


## Hitting the lip: at the top of the face, with the nose up or along it, a reversal toward down the face commits to a
## snap. The lip holds the tail while the board pivots round on it, so the whole turn happens at the top; he lets go and
## drops once the nose is nearly where it was going. Once started it carries through: a snap cannot be taken back halfway.
func _update_snap(at_lip: float, target: float) -> void:
	if not snapping:
		snapping = at_lip > 0.3 and theta > SNAP_HEADING and target - theta < -SNAP_START and not cutting_back and not _carving_down
		_snap_to = minf(target, -SNAP_DOWN)
	elif theta < _snap_to + SNAP_RELEASE or cutting_back or u < LIP_FROM - 0.2:
		snapping = false
	else:
		_snap_to = minf(_snap_to, target)  # (a push still building can take it further round, never back)


## The cutback: out in front, in the upper face but below the lip, a hard push down that is held starts a long carve
## that swings on round toward the curl for as long as it is held. Let go once he is past straight down, or meet the
## foam or the bottom, and the water pivots the board back toward the line; once his heading is back above CUT_DONE he
## rides on as usual. Let go before straight down and it was only a long carve down the face.
func _update_cutback(push: float, delta: float) -> void:
	var holding := _since_down < CUT_HOLD_GAP
	if not cutting_back:
		# (where the turn starts decides it: below the lip, off a climb not committed to the lip, it is a carve, and out
		# in front it is a cutback if it is held; a steep climb's reversal waits for the lip and snaps there)
		if not holding:
			_carving_down = false
			_cut_armed = false
		elif push < 0.0 and not _carving_down and not snapping and u < CUT_TOP and theta > CUT_START_HEADING and theta < CLIMB_COMMIT:
			_carving_down = true
			_cut_armed = d > CUT_ROOM and u > CUT_FROM
			_cut_held = 0.0
		if _cut_armed:
			_cut_held += delta
		if _cut_armed and _cut_held > CUT_HOLD_TIME and _stick < CUT_PUSH and theta > CUT_LATE_HEADING:
			cutting_back = true
			_rebounding = false
			_cut_armed = false
		return
	if not _rebounding:
		# (he sees the foam coming: the rebound starts early enough to finish before he gets there)
		var foam_close := d + minf(vel_d, 0.0) * REBOUND_TIME * 2.0 < CUT_FOAM
		if theta < CUT_PAST and (not holding or foam_close or u < 0.12):
			# (the water knocks the board straight back toward the line: no slow fade of the push)
			_rebounding = true
			_stick = 0.0
			_stick_smooth = 0.0
		elif not holding:
			cutting_back = false
			return
	if _rebounding and theta > CUT_DONE:
		cutting_back = false
		_rebounding = false


## The strength of a spray that should be thrown now, 0 to 1, or 0 for none. Asking clears it, and sets `burst_release`
## to how much of it came from stopping at the top (the giant fan).
func take_burst() -> float:
	var strength := _pending_burst
	burst_release = _pending_release
	_pending_burst = 0.0
	_pending_release = 0.0
	return strength


## A burst as a turn starts to throw water, and a bigger one each time it bites harder (SPRAY_STEP), so the biggest comes
## at the peak of the turn, the snap at the lip, instead of being locked out by the first one. The rail throws water in
## proportion to speed and how hard it turns; turning off the top, the speed he is shedding is what it throws, so the
## biggest fan comes as he stops up there, and floating down after it he throws little.
func _update_spray(delta: float, tuning: TuningData, peel: float) -> void:
	_burst_ready_in = maxf(_burst_ready_in - delta, 0.0)
	if _burst_ready_in <= 0.0:
		_last_burst = 0.0
	var lip := 1.0 + LIP_SPRAY * lip_hit
	var carving := speed * sharpness * lip * (1.0 - FLOAT_QUIET * afloat * (1.0 - release))
	_carried = maxf(v, lerpf(_carried, v, 1.0 - exp(-delta / CARRIED_MEMORY)))
	var shedding := release * maxf(_carried - STALL_SPEED * peel, 0.0) / (RELEASE_SPRAY * peel) * lip
	var power := maxf(carving, shedding)
	spray_power = power
	# (a fan that is already full is not thrown again while the turn bites harder still, but one that was not full yet is
	# topped up to a full one)
	var full := 1.0 / BURST_POWER
	var felt := minf(power, full)
	var bar := minf(_last_burst + SPRAY_STEP, full) if _last_burst > 0.0 else 0.0
	if power > tuning.spray_threshold and felt >= bar and felt > _last_burst:
		_pending_burst = maxf(_pending_burst, clampf(power * BURST_POWER, 0.0, 1.0))
		_pending_release = maxf(_pending_release, release if shedding >= carving else 0.0)
		_last_burst = felt
		_burst_ready_in = tuning.spray_pause


## Moves are labels the state earns, never buttons: a bottom turn happens low on the face, a top turn high.
func _update_move(model: WaveModel, peel: float) -> void:
	var seen := "trim"
	if model.barrel_amount_at(d, u) > 0.5 and compression > 0.5:
		seen = "barrel"
	elif snapping or (u > 0.72 and theta > 0.65 and omega < -1.8):
		seen = "hit_the_lip"
	elif cutting_back:
		seen = "cutback"
	elif u > 0.9 and absf(theta) < 0.35:
		seen = "floater"
	elif u < 0.45 and omega > 1.0 and v > 0.65 * peel:
		seen = "bottom_turn"
	elif u > 0.55 and omega < -1.1:
		seen = "top_turn"
	# A move label stays a moment once seen, so it does not flicker.
	if seen != "trim" or _clock > _move_until:
		move = seen
		_move_until = _clock + MOVE_HOLD
