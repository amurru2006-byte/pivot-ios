# Workout audio: explicit hardware experiment

This is not a completed speaker-only recovery cue. The final requirement is a
short sound that ends automatically, including with Bluetooth connected and the
phone locked. No fallback has been silently accepted.

## Scope

On iOS 26 or later, Settings → Notifications → Test avviso a schermo spento
offers a separate, opt-in AlarmKit experiment. Merely opening the screen never
requests authorization or schedules anything. The user must acknowledge that
the alarm may need manual dismissal, press Start, and grant system permission.
Only one fixed-date alarm, 20 seconds ahead, can be scheduled. There is no
recurrence, countdown Live Activity, or workout integration. Only the reserved
probe UUID is cancelled; unrelated alarms are never touched.

The generated two-second mono PCM WAV has three tones and fixed cue gain 0.25;
it does not set system volume. AlarmKit might repeat this finite file. A sound
file's duration does **not** establish automatic alarm dismissal. No audio
session override, microphone capture, silent playback loop, network request,
Health access, or background execution workaround is used.

## Hardware check (not replaceable by simulator assertions)

1. Choose a suitable place, set comfortable system volume, connect Bluetooth
   headphones, and play music if normally used.
2. Start the probe, allow alarms if requested, then lock the phone.
3. Record output: phone speaker, headphones, both, paired Watch, or no sound.
   Note whether tones repeat and whether music ducks, stops, changes route, or
   resumes. Stop the alarm if needed. Don't wait on a looping alarm.
4. Repeat only intentionally, including unlocked/locked comparison. A pass with
   one device/OS/headset doesn't certify every accessory or future OS release.

If the system repeats the cue or cannot use the desired route, do not promote
this experiment into automatic workout alerts. Work out a supported solution or
report the unmet requirement explicitly. A foreground Task that stops an alarm
after two seconds would not prove reliability while the app is suspended.

## Verification boundaries

Run38732233933 compiled Debug/Release and passed383Core plus the four QR
preflight tests. Full UI:37passed,1failed,1skipped. All three strengthened
workout layout/recovery/record tests passed. The AlarmKit UI test was skipped
because the harness selected an iPhone16 on an older OS, despite a newer
runtime being installed. Selection now requires an available iOS26+ runtime,
chooses the newest version before preferring a model name, and records its
metadata. Six fixture tests cover that selection. The AlarmKit UI test now
fails instead of silently skipping on an old OS.

The unrelated extra-exercise-picker regression tapped a partially visible
button whose centre was behind the fixed recovery bar (AX button697.7–743.7,
bar starts701). Its existing normal tap and picker/catalog assertions remain;
the test now first scrolls the whole target above the actual bar boundary.
This correction still requires another real UI run.

The workflow groups consecutive Debug simulator runs before compiling
iphoneos Release: logs showed a costly second native dependency rebuild when
switching platforms between simulator passes. This changes order only;
Core, gateway, QR preflight, full UI, Release and signing all still gate IPA.

Core tests check WAV format, exact duration, invalid gains, sample scaling,
headroom, three tones, and silent tail. UI regression checks entry, opt-in,
disabled Start before acknowledgment, and no automatic permission prompt.
Neither verifies system alarm delivery or routing. Existing WorkoutRuntime
notifications remain unchanged while the experiment is being evaluated.

## Primary references checked 15 October 2026

- [Apple AlarmKit sample](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit): authorization, fixed scheduling, system Stop, optional countdown widget requirement.
- [Alarm configuration](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration): no documented speaker-only setting or two-second auto-dismiss option.
- [Speaker override](https://developer.apple.com/documentation/avfaudio/avaudiosession/overrideoutputaudioport(_:)): active play-and-record audio routing, not control of OS notification/alarm delivery while suspended.
- [Usage description](https://developer.apple.com/documentation/bundleresources/information-property-list/nsalarmkitusagedescription): explicit permission-purpose string.
