class_name MusicDsp
extends RefCounted
## The score and synthesis numbers behind MusicLayers, and the small DSP helpers its render tasks
## share. Kept apart from MusicLayers (and never naming it) so the task scripts depend on this alone:
## an inner class that names its own outer class makes a script reference cycle that leaks at exit.

# --- Timing. 98 BPM is chosen because a beat is then exactly 13500 samples at 22050 Hz, so every
# note lands on a whole sample and the loop is a whole number of beats with no drift.
const SAMPLE_RATE := 22050
const SAMPLES_PER_BEAT := 13500
const STEPS_PER_BEAT := 4
const SAMPLES_PER_STEP := SAMPLES_PER_BEAT / STEPS_PER_BEAT
const BEATS_PER_BAR := 4
const STEPS_PER_BAR := STEPS_PER_BEAT * BEATS_PER_BAR
const SAMPLES_PER_BAR := SAMPLES_PER_BEAT * BEATS_PER_BAR
const BARS := 4
const LOOP_SAMPLES := SAMPLES_PER_BAR * BARS

# --- Generation budget. A chunk is small enough that one never blows the frame budget by much.
const GEN_BUDGET_USEC := 3000
const GEN_CHUNK := 1024

# --- Wavetables: one cycle each, band-limited so the highest note used stays under Nyquist.
const TABLE_SIZE := 2048
const TABLE_MASK := TABLE_SIZE - 1
const SAW_HARMONICS := 24         # fine up to about 460 Hz (pad and bass)
const SAW_SOFT_HARMONICS := 12    # fine up to about 900 Hz (lead)
const SQUARE_HARMONICS := 11      # odd harmonics only, fine up to about 1000 Hz (arp)

# --- Harmony: vi IV I V in A minor, voiced as Am9, Fmaj9, Cmaj7(add9-ish cluster) and G6, which
# is the warm, unresolved golden-hour colour of the genre. MIDI notes.
const CHORD_ROOTS: Array[int] = [33, 29, 36, 31]
const CHORD_TONES: Array = [[60, 64, 67, 71], [57, 60, 64, 67], [55, 59, 60, 64], [55, 59, 62, 64]]

# --- Pad (stem 1): two detuned saws per chord tone, slow attack, long overlapping release, then a
# 12 dB low-pass whose cutoff breathes once per loop.
const PAD_DETUNE_CENTS := 8.0
const PAD_OSC_AMP := 0.12
const PAD_ATTACK_SECONDS := 0.55
const PAD_RELEASE_SECONDS := 0.9
const PAD_CUTOFF_HZ := 1100.0
const PAD_CUTOFF_OCTAVES := 0.8
const PAD_SWEEP_CYCLES := 1
const FILTER_WARM_SAMPLES := 4096   # filter memory is milliseconds, so this settles it fully

# --- Bass (stem 2): punchy octave eighths, a plucky filter envelope on every note.
const BASS_GATE_SECONDS := 0.24
const BASS_ATTACK_SECONDS := 0.004
const BASS_RELEASE_SECONDS := 0.03
const BASS_CUT_HIGH_HZ := 1600.0
const BASS_CUT_LOW_HZ := 260.0
const BASS_CUT_DECAY_SECONDS := 0.09
const BASS_SAW_MIX := 0.7
const BASS_SINE_MIX := 0.6
const BASS_ACCENT := 1.0
const BASS_OFFBEAT := 0.78
const CONTROL_SAMPLES := 16          # filter coefficients update this often (under 1 ms)
const CLICK_GUARD_SAMPLES := 22      # a 1 ms rise, so noise hits never start on a step

# --- Drums (stem 3): a soft kick, the gated-reverb snare and quiet hats.
const KICK_STEPS: Array[int] = [0, 8]
const KICK_PUSH_STEP := 10           # the "and of three" on every second bar, a gentle push
const SNARE_STEPS: Array[int] = [4, 12]
const KICK_SECONDS := 0.45
const KICK_START_HZ := 120.0
const KICK_END_HZ := 46.0
const KICK_SWEEP_SECONDS := 0.03
const KICK_DECAY_SECONDS := 0.13
const KICK_ATTACK_SAMPLES := 30
const KICK_VELOCITY := 1.0
const KICK_PUSH_VELOCITY := 0.6
const SNARE_TONE_HZ := 185.0
const SNARE_TONE_DECAY_SECONDS := 0.05
const SNARE_TONE_MIX := 0.5
const SNARE_HIT_DECAY_SECONDS := 0.015
const SNARE_HIT_MIX := 0.7
const SNARE_BODY_MIX := 0.55
const SNARE_GATE_SECONDS := 0.24     # the plateau of the gated reverb tail...
const SNARE_TAIL_END := 0.55         # ...sagging to this before the gate shuts
const SNARE_CLOSE_SECONDS := 0.02
const SNARE_HP_HZ := 900.0
const SNARE_DARK_HZ := 5200.0
const SNARE_VELOCITY := 0.85
const HAT_SECONDS := 0.09
const HAT_DECAY_SECONDS := 0.025
const HAT_HP_HZ := 6500.0
const HAT_OFFBEAT_VELOCITY := 0.32
const HAT_ONBEAT_VELOCITY := 0.16

# --- Lead (stem 4): a 16th-note arp of the chord an octave up, a few long singing notes on top,
# all through a dotted-eighth echo.
const ARP_PATTERN: Array[int] = [0, 1, 2, 3, 1, 2, 3, 2]
const ARP_OCTAVE := 12
const ARP_SECONDS := 0.32
const ARP_DECAY_SECONDS := 0.11
const ARP_ATTACK_SAMPLES := 44
const ARP_CUTOFF_HZ := 3400.0
const ARP_ACCENT := 0.85
const ARP_SOFT := 0.55
# (start beat, MIDI note, length in beats): a slow line that lands back on E for the loop.
const LEAD_NOTES: Array[Vector3] = [
	Vector3(0, 76, 3), Vector3(3, 79, 1), Vector3(4, 81, 2), Vector3(6, 79, 2),
	Vector3(8, 76, 4), Vector3(12, 74, 2), Vector3(14, 71, 2),
]
const LEAD_DETUNE_CENTS := 6.0
const LEAD_ATTACK_SECONDS := 0.09
const LEAD_RELEASE_SECONDS := 0.3
const LEAD_VIBRATO_HZ := 5.2
const LEAD_VIBRATO_DEPTH := 0.007    # about 12 cents
const LEAD_VIBRATO_DELAY_SECONDS := 0.35
const LEAD_CUTOFF_HZ := 2800.0
const LEAD_VELOCITY := 0.75
const ECHO_STEPS := 3                # a dotted eighth
const ECHO_FEEDBACK := 0.38
const ECHO_MIX := 0.45
const ECHO_CUTOFF_HZ := 2600.0

# --- Mix. Stems are balanced by RMS, then scaled together so the full mix peaks at MUSIC_PEAK_DB.
const STEM_RMS_BALANCE: Array[float] = [1.0, 0.8, 0.75, 0.5]
const MUSIC_PEAK_DB := -4.0

# --- Ambience beds. Noise loops are rendered a little long and the tail is cross-faded into the
# head, which makes them seamless without storing the noise.
const BED_FADE_SAMPLES := 4410
const BED_BODY_BOOST := 4.0          # doubly low-passed noise is quiet; this levels it with the hiss
const OCEAN_SAMPLES := LOOP_SAMPLES * 2
const LAP_SAMPLES := LOOP_SAMPLES
const ROAR_SAMPLES := SAMPLE_RATE * 4
const OCEAN_PEAK_DB := -12.0
const LAP_PEAK_DB := -14.0
const ROAR_PEAK_DB := -8.0
const SPLASH_SECONDS := 1.1
const SPLASH_PEAK_DB := -6.0
const SPLASH_ATTACK_SECONDS := 0.06
const SPLASH_DECAY_SECONDS := 0.32
const SPLASH_FC_START_HZ := 5500.0
const SPLASH_FC_END_HZ := 1400.0
const SPLASH_BAND_RATIO := 0.25
const SPLASH_POOL := 3

const SILENT_GAIN := 0.0001


static func midi_hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


static func table_inc(hz: float) -> float:
	return hz * TABLE_SIZE / SAMPLE_RATE


## One-pole low-pass coefficient for a cutoff.
static func pole(hz: float) -> float:
	return 1.0 - exp(-TAU * hz / SAMPLE_RATE)
