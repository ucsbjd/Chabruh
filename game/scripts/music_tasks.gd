class_name MusicTasks
extends RefCounted
## The resumable render tasks MusicLayers runs a few milliseconds a frame. Each one writes into a
## shared PackedFloat32Array and reads its numbers from MusicDsp only (see there for why).
## A piece of rendering that can stop after any chunk and carry on next frame.
class Task extends RefCounted:
	## Renders up to `count` more samples; true once finished.
	func step(_count: int) -> bool:
		return true


class CallTask extends Task:
	var fn: Callable

	func _init(callable: Callable) -> void:
		fn = callable

	func step(_count: int) -> bool:
		fn.call()
		return true


class TableTask extends Task:
	var out: PackedFloat32Array
	var harmonics: int
	var odd_only: bool

	func _init(table: PackedFloat32Array, harmonic_count: int, odd: bool) -> void:
		out = table
		harmonics = harmonic_count
		odd_only = odd

	func step(_count: int) -> bool:
		var peak := 0.0
		for i in MusicDsp.TABLE_SIZE:
			var x := TAU * i / MusicDsp.TABLE_SIZE
			var v := 0.0
			for h in range(1, harmonics + 1):
				if odd_only and h % 2 == 0:
					continue
				v += sin(x * h) / h
			out[i] = v
			peak = maxf(peak, absf(v))
		for i in MusicDsp.TABLE_SIZE:
			out[i] /= peak
		return true


## A note written into a looping buffer: it may start anywhere and its tail wraps round to the
## start, which is what makes the loop seamless.
class Note extends Task:
	var out: PackedFloat32Array
	var start: int
	var total: int
	var pos := 0

	## How many samples the next chunk covers without crossing the end of the buffer.
	func _span(count: int) -> int:
		var dest := (start + pos) % MusicDsp.LOOP_SAMPLES
		return mini(mini(count, total - pos), MusicDsp.LOOP_SAMPLES - dest)

	func _dest() -> int:
		return (start + pos) % MusicDsp.LOOP_SAMPLES


class PadChord extends Note:
	var tab: PackedFloat32Array
	var incs := PackedFloat32Array()
	var phases := PackedFloat32Array()
	var gate: int
	var attack: int
	var release: int
	var env := PackedFloat32Array()

	func _init(buf: PackedFloat32Array, table: PackedFloat32Array, at: int, tones: Array,
			rng: RandomNumberGenerator) -> void:
		out = buf
		tab = table
		start = at
		gate = MusicDsp.SAMPLES_PER_BAR
		attack = int(MusicDsp.PAD_ATTACK_SECONDS * MusicDsp.SAMPLE_RATE)
		release = int(MusicDsp.PAD_RELEASE_SECONDS * MusicDsp.SAMPLE_RATE)
		total = gate + release
		for midi: int in tones:
			for side in [-1.0, 1.0]:
				var hz := MusicDsp.midi_hz(midi + side * MusicDsp.PAD_DETUNE_CENTS / 100.0)
				incs.append(MusicDsp.table_inc(hz))
				# Random phases, so the detuned pairs do not all start in step and thump.
				phases.append(rng.randf() * MusicDsp.TABLE_SIZE)
		env.resize(MusicDsp.GEN_CHUNK)

	func step(count: int) -> bool:
		var n := _span(count)
		var dest := _dest()
		for j in n:
			var t := pos + j
			var e := 1.0
			if t < attack:
				e = 0.5 - 0.5 * cos(PI * t / attack)
			elif t >= gate:
				var r := 1.0 - float(t - gate) / release
				e = r * r
			env[j] = e * MusicDsp.PAD_OSC_AMP
		var size := float(MusicDsp.TABLE_SIZE)
		for k in incs.size():
			var ph := phases[k]
			var inc := incs[k]
			for j in n:
				ph += inc
				if ph >= size:
					ph -= size
				out[dest + j] += tab[int(ph)] * env[j]
			phases[k] = ph
		pos += n
		return pos >= total


## Two one-pole low-passes over the whole pad loop, cutoff breathing with the loop. Starts a little
## before zero (reading the wrapped end) so the filter state at the seam matches.
class PadFilter extends Task:
	var buf: PackedFloat32Array
	var pos := -MusicDsp.FILTER_WARM_SAMPLES
	var l1 := 0.0
	var l2 := 0.0
	var c := 0.0

	func _init(target: PackedFloat32Array) -> void:
		buf = target

	func step(count: int) -> bool:
		var n_total := MusicDsp.LOOP_SAMPLES
		var end := mini(pos + count, n_total)
		for j in range(pos, end):
			var idx := j if j >= 0 else j + n_total
			if (j & (MusicDsp.CONTROL_SAMPLES - 1)) == 0:
				var sweep := sin(TAU * MusicDsp.PAD_SWEEP_CYCLES * idx / n_total)
				c = MusicDsp.pole(MusicDsp.PAD_CUTOFF_HZ
						* pow(2.0, MusicDsp.PAD_CUTOFF_OCTAVES * sweep))
			l1 += c * (buf[idx] - l1)
			l2 += c * (l1 - l2)
			if j >= 0:
				buf[idx] = l2
		pos = end
		return pos >= n_total


class BassNote extends Note:
	var saw: PackedFloat32Array
	var sine: PackedFloat32Array
	var inc: float
	var vel: float
	var gate: int
	var attack: int
	var release: int
	var ph := 0.0
	var l1 := 0.0
	var l2 := 0.0
	var c := 0.0

	func _init(buf: PackedFloat32Array, saw_tab: PackedFloat32Array, sine_tab: PackedFloat32Array,
			at: int, midi: int, velocity: float) -> void:
		out = buf
		saw = saw_tab
		sine = sine_tab
		start = at
		vel = velocity
		inc = MusicDsp.table_inc(MusicDsp.midi_hz(midi))
		gate = int(MusicDsp.BASS_GATE_SECONDS * MusicDsp.SAMPLE_RATE)
		attack = int(MusicDsp.BASS_ATTACK_SECONDS * MusicDsp.SAMPLE_RATE)
		release = int(MusicDsp.BASS_RELEASE_SECONDS * MusicDsp.SAMPLE_RATE)
		total = gate + release

	func step(count: int) -> bool:
		var n := _span(count)
		var dest := _dest()
		var size := float(MusicDsp.TABLE_SIZE)
		var decay := MusicDsp.BASS_CUT_DECAY_SECONDS * MusicDsp.SAMPLE_RATE
		for j in n:
			var t := pos + j
			if (t & (MusicDsp.CONTROL_SAMPLES - 1)) == 0:
				c = MusicDsp.pole(MusicDsp.BASS_CUT_LOW_HZ
						+ (MusicDsp.BASS_CUT_HIGH_HZ - MusicDsp.BASS_CUT_LOW_HZ) * exp(-t / decay))
			var e := 1.0
			if t < attack:
				e = float(t) / attack
			elif t >= gate:
				e = 1.0 - float(t - gate) / release
			ph += inc
			if ph >= size:
				ph -= size
			var i := int(ph)
			var x := saw[i] * MusicDsp.BASS_SAW_MIX + sine[i] * MusicDsp.BASS_SINE_MIX
			l1 += c * (x - l1)
			l2 += c * (l1 - l2)
			out[dest + j] += l2 * e * vel
		pos += n
		return pos >= total


class Kick extends Note:
	var sine: PackedFloat32Array
	var vel: float
	var ph := 0.0
	var sweep := 1.0
	var amp := 1.0
	var sweep_k: float
	var amp_k: float

	func _init(buf: PackedFloat32Array, sine_tab: PackedFloat32Array, at: int, velocity: float) -> void:
		out = buf
		sine = sine_tab
		start = at
		vel = velocity
		total = int(MusicDsp.KICK_SECONDS * MusicDsp.SAMPLE_RATE)
		sweep_k = exp(-1.0 / (MusicDsp.KICK_SWEEP_SECONDS * MusicDsp.SAMPLE_RATE))
		amp_k = exp(-1.0 / (MusicDsp.KICK_DECAY_SECONDS * MusicDsp.SAMPLE_RATE))

	func step(count: int) -> bool:
		var n := _span(count)
		var dest := _dest()
		var size := float(MusicDsp.TABLE_SIZE)
		var to_inc := size / MusicDsp.SAMPLE_RATE
		for j in n:
			var t := pos + j
			var hz := MusicDsp.KICK_END_HZ + (MusicDsp.KICK_START_HZ - MusicDsp.KICK_END_HZ) * sweep
			sweep *= sweep_k
			ph += hz * to_inc
			if ph >= size:
				ph -= size
			var a := amp
			if t < MusicDsp.KICK_ATTACK_SAMPLES:
				a *= float(t) / MusicDsp.KICK_ATTACK_SAMPLES
			# The last few ms fade out, so the note never stops on a step.
			var left := total - t
			if left < MusicDsp.KICK_ATTACK_SAMPLES:
				a *= float(left) / MusicDsp.KICK_ATTACK_SAMPLES
			out[dest + j] += sine[int(ph)] * a * vel
			amp *= amp_k
		pos += n
		return pos >= total


## The gated-reverb snare: a bright crack, then a dense plateau of dark noise that sags a little
## and is cut off by the gate, the sound of 1984.
class Snare extends Note:
	var sine: PackedFloat32Array
	var rng: RandomNumberGenerator
	var vel: float
	var ph := 0.0
	var tone_amp := 1.0
	var hit_amp := 1.0
	var tone_k: float
	var hit_k: float
	var gate: int
	var close: int
	var inc: float
	var hp_c: float
	var dark_c: float
	var hp_l := 0.0
	var dark_l := 0.0

	func _init(buf: PackedFloat32Array, sine_tab: PackedFloat32Array, at: int, velocity: float,
			noise: RandomNumberGenerator) -> void:
		out = buf
		sine = sine_tab
		rng = noise
		start = at
		vel = velocity
		gate = int(MusicDsp.SNARE_GATE_SECONDS * MusicDsp.SAMPLE_RATE)
		close = int(MusicDsp.SNARE_CLOSE_SECONDS * MusicDsp.SAMPLE_RATE)
		total = gate + close
		tone_k = exp(-1.0 / (MusicDsp.SNARE_TONE_DECAY_SECONDS * MusicDsp.SAMPLE_RATE))
		hit_k = exp(-1.0 / (MusicDsp.SNARE_HIT_DECAY_SECONDS * MusicDsp.SAMPLE_RATE))
		inc = MusicDsp.table_inc(MusicDsp.SNARE_TONE_HZ)
		hp_c = MusicDsp.pole(MusicDsp.SNARE_HP_HZ)
		dark_c = MusicDsp.pole(MusicDsp.SNARE_DARK_HZ)

	func step(count: int) -> bool:
		var n := _span(count)
		var dest := _dest()
		var size := float(MusicDsp.TABLE_SIZE)
		for j in n:
			var t := pos + j
			var noise := rng.randf() * 2.0 - 1.0
			hp_l += hp_c * (noise - hp_l)
			var hp := noise - hp_l
			dark_l += dark_c * (hp - dark_l)
			var body := 0.0
			if t < gate:
				body = 1.0 - (1.0 - MusicDsp.SNARE_TAIL_END) * t / gate
			else:
				body = MusicDsp.SNARE_TAIL_END * (0.5 + 0.5 * cos(PI * (t - gate) / close))
			ph += inc
			if ph >= size:
				ph -= size
			var s := sine[int(ph)] * tone_amp * MusicDsp.SNARE_TONE_MIX \
					+ hp * hit_amp * MusicDsp.SNARE_HIT_MIX + dark_l * body * MusicDsp.SNARE_BODY_MIX
			if t < MusicDsp.CLICK_GUARD_SAMPLES:
				s *= float(t) / MusicDsp.CLICK_GUARD_SAMPLES
			out[dest + j] += s * vel
			tone_amp *= tone_k
			hit_amp *= hit_k
		pos += n
		return pos >= total


class Hat extends Note:
	var rng: RandomNumberGenerator
	var vel: float
	var amp := 1.0
	var amp_k: float
	var c: float
	var l1 := 0.0
	var l2 := 0.0

	func _init(buf: PackedFloat32Array, at: int, velocity: float, noise: RandomNumberGenerator) -> void:
		out = buf
		rng = noise
		start = at
		vel = velocity
		total = int(MusicDsp.HAT_SECONDS * MusicDsp.SAMPLE_RATE)
		amp_k = exp(-1.0 / (MusicDsp.HAT_DECAY_SECONDS * MusicDsp.SAMPLE_RATE))
		c = MusicDsp.pole(MusicDsp.HAT_HP_HZ)

	func step(count: int) -> bool:
		var n := _span(count)
		var dest := _dest()
		for j in n:
			var noise := rng.randf() * 2.0 - 1.0
			l1 += c * (noise - l1)
			var hp1 := noise - l1
			l2 += c * (hp1 - l2)
			var a := amp
			var t := pos + j
			if t < MusicDsp.CLICK_GUARD_SAMPLES:
				a *= float(t) / MusicDsp.CLICK_GUARD_SAMPLES
			out[dest + j] += (hp1 - l2) * a * vel
			amp *= amp_k
		pos += n
		return pos >= total


class Pluck extends Note:
	var tab: PackedFloat32Array
	var inc: float
	var vel: float
	var ph := 0.0
	var amp := 1.0
	var amp_k: float
	var c: float
	var l := 0.0

	func _init(buf: PackedFloat32Array, table: PackedFloat32Array, at: int, midi: int,
			velocity: float) -> void:
		out = buf
		tab = table
		start = at
		vel = velocity
		inc = MusicDsp.table_inc(MusicDsp.midi_hz(midi))
		total = int(MusicDsp.ARP_SECONDS * MusicDsp.SAMPLE_RATE)
		amp_k = exp(-1.0 / (MusicDsp.ARP_DECAY_SECONDS * MusicDsp.SAMPLE_RATE))
		c = MusicDsp.pole(MusicDsp.ARP_CUTOFF_HZ)

	func step(count: int) -> bool:
		var n := _span(count)
		var dest := _dest()
		var size := float(MusicDsp.TABLE_SIZE)
		var rise := float(MusicDsp.ARP_ATTACK_SAMPLES)
		for j in n:
			var t := pos + j
			ph += inc
			if ph >= size:
				ph -= size
			l += c * (tab[int(ph)] - l)
			var a := amp
			if t < MusicDsp.ARP_ATTACK_SAMPLES:
				a *= t / rise
			var left := total - t
			if left < MusicDsp.ARP_ATTACK_SAMPLES:
				a *= left / rise
			out[dest + j] += l * a * vel
			amp *= amp_k
		pos += n
		return pos >= total


## A long singing note: two detuned soft saws, vibrato that blooms after the attack.
class LeadNote extends Note:
	var tab: PackedFloat32Array
	var sine: PackedFloat32Array
	var inc: float
	var gate: int
	var attack: int
	var release: int
	var vib_delay: int
	var vib_inc: float
	var detune: float
	var ph1 := 0.0
	var ph2 := 0.0
	var vib_ph := 0.0
	var c: float
	var l := 0.0

	func _init(buf: PackedFloat32Array, table: PackedFloat32Array, sine_tab: PackedFloat32Array,
			at: int, midi: int, length: int) -> void:
		out = buf
		tab = table
		sine = sine_tab
		start = at
		gate = length
		attack = int(MusicDsp.LEAD_ATTACK_SECONDS * MusicDsp.SAMPLE_RATE)
		release = int(MusicDsp.LEAD_RELEASE_SECONDS * MusicDsp.SAMPLE_RATE)
		vib_delay = int(MusicDsp.LEAD_VIBRATO_DELAY_SECONDS * MusicDsp.SAMPLE_RATE)
		total = gate + release
		inc = MusicDsp.table_inc(MusicDsp.midi_hz(midi))
		vib_inc = MusicDsp.table_inc(MusicDsp.LEAD_VIBRATO_HZ)
		detune = pow(2.0, MusicDsp.LEAD_DETUNE_CENTS / 1200.0)
		c = MusicDsp.pole(MusicDsp.LEAD_CUTOFF_HZ)
		ph2 = MusicDsp.TABLE_SIZE * 0.37

	func step(count: int) -> bool:
		var n := _span(count)
		var dest := _dest()
		var size := float(MusicDsp.TABLE_SIZE)
		for j in n:
			var t := pos + j
			var e := 1.0
			if t < attack:
				e = float(t) / attack
			elif t >= gate:
				e = 1.0 - float(t - gate) / release
			var depth := 0.0
			if t > vib_delay:
				depth = MusicDsp.LEAD_VIBRATO_DEPTH * minf(1.0, float(t - vib_delay) / vib_delay)
			vib_ph += vib_inc
			if vib_ph >= size:
				vib_ph -= size
			var bend := 1.0 + depth * sine[int(vib_ph)]
			ph1 += inc * bend
			if ph1 >= size:
				ph1 -= size
			ph2 += inc * bend * detune
			if ph2 >= size:
				ph2 -= size
			l += c * ((tab[int(ph1)] + tab[int(ph2)]) * 0.5 - l)
			out[dest + j] += l * e * MusicDsp.LEAD_VELOCITY
		pos += n
		return pos >= total


## A darkening dotted-eighth echo on a loop. The echo train is run round the loop twice, so what
## spills past the end has already fed back into the start, then mixed in once.
class Echo extends Task:
	var buf: PackedFloat32Array
	var wet := PackedFloat32Array()
	var delay: int
	var c: float
	var l := 0.0
	var pos := 0

	func _init(target: PackedFloat32Array) -> void:
		buf = target
		wet.resize(MusicDsp.LOOP_SAMPLES)
		delay = MusicDsp.ECHO_STEPS * MusicDsp.SAMPLES_PER_STEP
		c = MusicDsp.pole(MusicDsp.ECHO_CUTOFF_HZ)

	func step(count: int) -> bool:
		var n_total := MusicDsp.LOOP_SAMPLES
		var end := mini(pos + count, n_total * 3)
		for j in range(pos, end):
			var i := j % n_total
			if j < n_total * 2:
				var back := (i - delay + n_total) % n_total
				l += c * (buf[back] + MusicDsp.ECHO_FEEDBACK * wet[back] - l)
				wet[i] = l
			else:
				buf[i] += MusicDsp.ECHO_MIX * wet[i]
		pos = end
		if pos >= n_total * 3:
			wet = PackedFloat32Array()
			return true
		return false


class SumSquares extends Task:
	var buf: PackedFloat32Array
	var result: PackedFloat32Array
	var index: int
	var pos := 0
	var sum := 0.0

	func _init(source: PackedFloat32Array, results: PackedFloat32Array, slot: int) -> void:
		buf = source
		result = results
		index = slot

	func step(count: int) -> bool:
		var end := mini(pos + count * 4, buf.size())
		for i in range(pos, end):
			var v := buf[i]
			sum += v * v
		pos = end
		if pos >= buf.size():
			result[index] = sum
			return true
		return false


## Peak of the four stems summed at their balance gains, so the final scale is set by the loudest
## moment of the full mix.
class MixPeak extends Task:
	var b0: PackedFloat32Array
	var b1: PackedFloat32Array
	var b2: PackedFloat32Array
	var b3: PackedFloat32Array
	var gains: PackedFloat32Array
	var result: PackedFloat32Array
	var pos := 0
	var peak := 0.0

	func _init(bufs: Array[PackedFloat32Array], stem_gains: PackedFloat32Array,
			out: PackedFloat32Array) -> void:
		b0 = bufs[0]
		b1 = bufs[1]
		b2 = bufs[2]
		b3 = bufs[3]
		gains = stem_gains
		result = out

	func step(count: int) -> bool:
		var g0 := gains[0]
		var g1 := gains[1]
		var g2 := gains[2]
		var g3 := gains[3]
		var end := mini(pos + count * 2, b0.size())
		for i in range(pos, end):
			var v := absf(b0[i] * g0 + b1[i] * g1 + b2[i] * g2 + b3[i] * g3)
			if v > peak:
				peak = v
		pos = end
		if pos >= b0.size():
			result[0] = peak
			return true
		return false


## Finds a buffer's peak and stores the gain that brings it to `target`.
class Normalise extends Task:
	var buf: PackedFloat32Array
	var target: float
	var result: PackedFloat32Array
	var pos := 0
	var peak := 0.0

	func _init(source: PackedFloat32Array, target_peak: float, out: PackedFloat32Array) -> void:
		buf = source
		target = target_peak
		result = out

	func step(count: int) -> bool:
		var end := mini(pos + count * 4, buf.size())
		for i in range(pos, end):
			var v := absf(buf[i])
			if v > peak:
				peak = v
		pos = end
		if pos >= buf.size():
			result[0] = target / maxf(peak, MusicDsp.SILENT_GAIN)
			return true
		return false


## Packs floats into 16-bit PCM, two samples per int32 so the conversion to bytes is one native call.
class Encode extends Task:
	var buf: PackedFloat32Array
	var gains: PackedFloat32Array
	var index: int
	var words := PackedInt32Array()
	var pos := 0

	func _init(source: PackedFloat32Array, stem_gains: PackedFloat32Array, slot: int) -> void:
		buf = source
		gains = stem_gains
		index = slot

	func step(count: int) -> bool:
		# Sized on the first chunk, not at planning: a bed's buffer shrinks when its seam is folded.
		if pos == 0 and words.is_empty():
			words.resize(buf.size() / 2)
		var scale := gains[index] * 32767.0
		var end := mini(pos + count * 2, words.size())
		for p in range(pos, end):
			var a := int(buf[p * 2] * scale)
			var b := int(buf[p * 2 + 1] * scale)
			a = clampi(a, -32768, 32767)
			b = clampi(b, -32768, 32767)
			var w := (a & 0xFFFF) | ((b & 0xFFFF) << 16)
			if w >= 0x80000000:
				w -= 0x100000000
			words[p] = w
		pos = end
		return pos >= words.size()


## A looping noise bed: a dark body and a brighter hiss, each riding slow swells and occasional
## washes. Rendered BED_FADE_SAMPLES long, then `fold` cross-fades the overhang into the start.
class NoiseBed extends Task:
	var out := PackedFloat32Array()
	var length: int
	var rng: RandomNumberGenerator
	var low_hz := 300.0
	var hiss_hz := 2000.0
	var base_low := 1.0
	var swell_low := 0.0
	var base_hiss := 0.0
	var swell_hiss := 0.0
	var swell_cycles := Vector2(1, 2)
	var events := PackedFloat32Array()   # start of each wash, as a fraction of the loop
	var event_attack := 0.3
	var event_decay := 1.0
	var event_low := 0.0
	var event_hiss := 0.0
	var pos := 0
	var cl := 0.0
	var ch := 0.0
	var l1 := 0.0
	var l2 := 0.0
	var h := 0.0
	var env_low := 0.0
	var env_hiss := 0.0

	func _init(samples: int, noise: RandomNumberGenerator) -> void:
		length = samples
		rng = noise
		out.resize(samples + MusicDsp.BED_FADE_SAMPLES)

	func _envelopes(i: int) -> Vector2:
		var x := TAU * float(i % length) / length
		var swell := (0.5 + 0.5 * sin(x * swell_cycles.x)) * 0.65 \
				+ (0.5 + 0.5 * sin(x * swell_cycles.y + 1.3)) * 0.35
		swell *= swell
		var wash := 0.0
		var attack := event_attack * MusicDsp.SAMPLE_RATE
		var decay := event_decay * MusicDsp.SAMPLE_RATE
		for e in events:
			var d := float(posmod(i - int(e * length), length))
			if d < attack:
				wash += 0.5 - 0.5 * cos(PI * d / attack)
			else:
				wash += exp(-(d - attack) / decay)
		return Vector2(base_low + swell_low * swell + event_low * wash,
				base_hiss + swell_hiss * swell + event_hiss * wash)

	func step(count: int) -> bool:
		if pos == 0:
			cl = MusicDsp.pole(low_hz)
			ch = MusicDsp.pole(hiss_hz)
			var env := _envelopes(0)
			env_low = env.x
			env_hiss = env.y
		var end := mini(pos + count, out.size())
		var block := MusicDsp.CONTROL_SAMPLES * 4
		var i := pos
		while i < end:
			var stop := mini(i + block, end)
			var target := _envelopes(stop)
			var steps := float(stop - i)
			var dl := (target.x - env_low) / steps
			var dh := (target.y - env_hiss) / steps
			for j in range(i, stop):
				var noise := rng.randf() * 2.0 - 1.0
				l1 += cl * (noise - l1)
				l2 += cl * (l1 - l2)
				h += ch * (noise - h)
				env_low += dl
				env_hiss += dh
				out[j] = l2 * env_low * MusicDsp.BED_BODY_BOOST + h * env_hiss
			i = stop
		pos = end
		return pos >= out.size()

	## Equal-power cross-fade of the overhang into the head (uncorrelated noise keeps its level).
	func fold() -> void:
		var fade := MusicDsp.BED_FADE_SAMPLES
		for j in fade:
			var a := float(j) / fade * PI * 0.5
			out[j] = out[j] * sin(a) + out[length + j] * cos(a)
		out.resize(length)


## The spray whoosh: band-passed noise sweeping down, quick to swell and slow to settle.
class Splash extends Task:
	var out := PackedFloat32Array()
	var rng: RandomNumberGenerator
	var pos := 0
	var a1 := 0.0
	var a2 := 0.0
	var b1 := 0.0
	var ca := 0.0
	var cb := 0.0

	func _init(samples: int, noise: RandomNumberGenerator) -> void:
		rng = noise
		out.resize(samples)

	func step(count: int) -> bool:
		var n_total := out.size()
		var end := mini(pos + count, n_total)
		var attack := MusicDsp.SPLASH_ATTACK_SECONDS * MusicDsp.SAMPLE_RATE
		var decay := MusicDsp.SPLASH_DECAY_SECONDS * MusicDsp.SAMPLE_RATE
		var tail := MusicDsp.BED_FADE_SAMPLES
		for t in range(pos, end):
			if (t & (MusicDsp.CONTROL_SAMPLES - 1)) == 0:
				var k := float(t) / n_total
				var fc := MusicDsp.SPLASH_FC_START_HZ \
						* pow(MusicDsp.SPLASH_FC_END_HZ / MusicDsp.SPLASH_FC_START_HZ, k)
				ca = MusicDsp.pole(fc)
				cb = MusicDsp.pole(fc * MusicDsp.SPLASH_BAND_RATIO)
			var noise := rng.randf() * 2.0 - 1.0
			a1 += ca * (noise - a1)
			a2 += ca * (a1 - a2)
			b1 += cb * (noise - b1)
			var e := 0.0
			if t < attack:
				e = 0.5 - 0.5 * cos(PI * t / attack)
			else:
				e = exp(-(t - attack) / decay)
			var left := n_total - t
			if left < tail:
				e *= float(left) / tail
			out[t] = (a2 - b1) * e
		pos = end
		return pos >= n_total
