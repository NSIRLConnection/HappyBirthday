# Happy Birthday

A native iOS SwiftUI implementation of the Nanit "Happy Birthday" take-home
assignment. All five steps are complete. No third-party dependencies.

## Build and run

Verified with **Xcode 27.2**. Deployment target **iOS 17.0**; the layout adapts
to iPhone and iPad.

In Xcode:

```sh
open HappyBirthday.xcodeproj
```

Select the `HappyBirthday` scheme and an installed simulator, then run (⌘R).

From the command line, list your installed destinations first:

```sh
xcodebuild -showdestinations \
  -project HappyBirthday.xcodeproj \
  -scheme HappyBirthday
```

Then build and test, replacing the destination name with a simulator installed
on your machine:

```sh
# Build (example simulator name — replace with an installed one)
xcodebuild build \
  -project HappyBirthday.xcodeproj \
  -scheme HappyBirthday \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'

# Unit + UI tests
xcodebuild test \
  -project HappyBirthday.xcodeproj \
  -scheme HappyBirthday \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

The simulator needs no Apple developer account. To run on a physical device,
select your own signing team and, if the bundle ID collides, change it to a
unique value. **Camera capture requires a physical device.**

## What each step does

| Git tag | Functionality | Tests passed |
| --- | --- | ---: |
| `step-1` | Details screen: app title, name, birthday, photo, and a "Show birthday screen" button enabled only when a non-whitespace name **and** a birthday are present. A photo is optional and never gates the button. | 8 |
| `step-2` | Every detail is editable and persists across launches: name text field with keyboard dismissal, date-only graphical picker (committed on Done, unchanged on Cancel), and a photo from the gallery (`PhotosPicker`) or camera. | 46 |
| `step-3` | Full-screen birthday screen with a random per-entry theme (fox / elephant / pelican), the `TODAY <NAME> IS` title, the age in completed months (<1 year) or years, the photo in the ringed placeholder, and a close button. | 75 |
| `step-4` | A theme-matched camera badge on the photo ring opens the library or camera through the shared photo flow; changes appear on both screens immediately and persist. | 87 |
| `step-5` | "Share the news" opens the native system share sheet with a rendered birthday image (name, age, theme, photo) that excludes all on-screen controls. | 106 |

## Architecture

- **`DetailsStore`** is the single app-owned source of truth for name, birthday,
  and photo. Name and birthday live in `UserDefaults`; the photo is stored as a
  JPEG with a maximum 1024px edge in Application Support and written atomically. A
  failed import or save keeps the previous value; corrupt or missing data
  degrades gracefully without discarding the rest.
- **Birthdays are canonical Gregorian calendar components** (`StoredBirthday`),
  so the chosen day survives reloads, calendar settings, and time-zone changes.
  The date-only picker uses a fixed time zone while its upper bound follows
  the device’s local today, including historical calendar-day skips.
- **Age** is computed in a fixed UTC Gregorian calendar on bare calendar days:
  completed months below one year, completed years from the first anniversary
  onward, born-today is 0 months, and future dates clamp to 0. This avoids
  time-of-day, DST, and historical time-zone-transition bugs. The number art and
  caption fold into one spoken accessibility phrase.
- **`PhotoSelection`** is a shared picker/import coordinator used by both
  screens: latest import wins, stale or cancelled completions are ignored, and
  camera captures commit only after the camera cover dismisses.
- **Each birthday presentation draws one random theme** and keeps it for the
  whole presentation (redraws, rotation, and backgrounding never reshuffle it);
  the draw is injectable for deterministic tests.
- **The on-screen content and the shared export reuse the same SwiftUI
  components.** The export is deterministic, excludes all controls, and bounds
  bitmap memory with a pixel budget. The share sheet uses an iPad popover anchor.
- **Responsive layout:** the title wraps to two lines and scales for long names;
  at accessibility sizes or short/landscape heights the screen becomes
  scrollable so the age, photo, and close button stay reachable.

## Assumptions

- The button readiness rule requires both a name and a birthday; the photo is
  optional.
- A system (SF) font substitutes for the proprietary Figma typeface, which the
  assignment explicitly permits.
- Layout was validated across short, wide, accessibility-scroll, and
  full-content export cases.

## Project layout

- `HappyBirthday/` — app sources and assets (`DetailsView`, `DetailsStore`,
  `Persistence`, `BirthdayView`, `PhotoSelection`, `BirthdayScreenModel`,
  `BirthdayTheme`, `BirthdayAge`/`AgeCalculator`, picker/image helpers).
- `HappyBirthdayTests/` — readiness, persistence, calendar-day, store, age,
  theme, asset, photo-flow, and share-renderer unit tests.
- `HappyBirthdayUITests/` — launch, accessibility, editing, persistence, and
  birthday-screen and native sharing UI tests against an isolated debug store.
- `HappyBirthday.xcodeproj` — the project and shared `HappyBirthday` scheme.

## Tests

The final version passed **106 tests** (91 unit, 15 UI) on
iPhone 18 Pro / iOS 27.2. Simulator tests and an unsigned physical-iPhone
Release build passed from an isolated source snapshot. Manual checks covered gallery persistence, physical-iPhone camera
capture, Duo folded/unfolded layouts, the iPad share popover, iPhone SE, and the
actual exported share image. Each tagged milestone also passed its own full
test suite and unsigned device Release build from an isolated source snapshot.

A pre-existing Details keyboard-transition runtime warning appears during the
automated keyboard tests; no functional failure was observed. The iOS 17 runtime
was not separately tested.

### Manual review flow

1. Open the project and run on an installed simulator.
2. Enter a name and pick a birthday; confirm the button enables.
3. Optionally add a photo from the gallery; relaunch to confirm it persists.
4. Show the birthday screen; confirm the title, age, theme, and photo ring.
5. Tap the camera badge to change the photo; confirm both screens update.
6. Tap "Share the news" and confirm the rendered image omits all controls.

## Artwork attribution

The birthday artwork is Nanit's and is used only for this assignment. See
[`Design/README.md`](Design/README.md) for provenance and licensing notes.
