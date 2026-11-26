# Rotala: response to App Review

App: Rotala (6753818565)  
Rejected submission: 7d64c6e9-2caf-4c90-bc93-db8657530d7f  
Reviewed binary: 1.0.0 (4), rejected March 14, 2026  
Development baseline for these changes: beta_1.1 at 1cfa838

This is a preparation document. No reply, binary, or metadata has been submitted.

## What Apple reported

- **2.3.1(a):** Hidden features. The message did not identify a particular feature,
  screen, account condition, or reproduction step. We cannot yet attribute this
  finding to a specific line of code.
- **4.2:** The experience was considered too limited and too similar to browsing
  a website. Apple asked for a more robust experience. Its message explicitly
  says notifications, location, or sharing alone do not satisfy this requirement.

## Changes in this branch

- The dashboard navigation now exposes Tasks, Record, and Settings. It no longer
  links to the unfinished Think Tank, RALA, or Library pages.
- Record chooses an aquarium and opens the existing reading editor, preserving
  that aquarium's parameter selections and ideal ranges. The first-use empty
  state provides an Add tank action. Cached aquariums can be selected offline.
- The unfinished RFID shortcut and recording placeholder are removed from active
  navigation. The unused assistant sheet is removed.
- The tank's action button is labeled Add reading, Export CSV, Add note, or Add
  task according to its active tab.
- Add/edit reading forms reject invalid numbers, non-finite values, pH outside
  0–14, and negative non-temperature measurements.
- CSV exports include all supported water parameters and both Celsius and
  Fahrenheit columns. They fetch multiple server pages, include pending local
  readings, and identify exports limited to cached data. Sharing has an iPad
  popover anchor.
- The walkthrough describes the available tools and their locations. It no
  longer promises notifications, streaks, or badges. The tank-limit message no
  longer calls the production user a beta tester.
- Full-app checks also found an obsolete icon-package incompatibility with the
  current Flutter SDK, incorrect imports in older extracted tank widgets, a
  sign-in layout overflow, and Settings tiles without a Material ink surface.
  These have been corrected. The single third-party walkthrough icon now uses a
  built-in icon, and the unused icon dependency has been removed.

## Automated validation

- Flutter 3.50.1 / Dart 3.14.0 on Linux.
- `flutter test --no-pub`: **13 tests passed**. Covers sign-in startup, active
  dashboard actions, Settings navigation, compact-screen/large-text layouts,
  first-tank entry, selection preserving custom tracking/ranges, CSV parameter
  and unit handling, pending/selected data, and invalid-number rejection.
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`: **0 errors**;
  25 warnings and 140 informational/deprecation findings remain. The check is
  configured to tolerate warnings and information, not errors.
- No production database records were created or modified for these tests.

## Complete feature inventory for the release

| Feature | Location | Requirements / limits |
| --- | --- | --- |
| Aquarium profiles, water type, volume, profile photo | Dashboard → Add tank; aquarium → Edit tank | Sign-in; up to 10 tanks |
| Manual water test entry with timestamp | Record → aquarium; aquarium → Overview → Add reading | No hardware; up to 500 readings per aquarium |
| Per-aquarium tracked parameters and ideal ranges | Aquarium → Edit tank | Extended fields must exist in the deployed Supabase schema |
| Historical charts and date windows | Aquarium → Overview | Existing readings |
| Reading history, edit/delete manual entries | Aquarium → Readings | Existing readings |
| Photo notes and aquarium journal | Aquarium → Notes → Add note | Photo library permission on use; server connection for uploads |
| Maintenance tasks and due dates | Dashboard → Tasks; aquarium → Tasks | In-app task list; no scheduled notification delivery |
| Local aquarium/reading cache and queued test results | Same Record and tank screens | Requires a previously authenticated session and cached aquarium; refresh after reconnecting |
| CSV export through native share sheet | Aquarium → Readings → Export CSV; Settings → Export tank data | Local cached export may be incomplete and is explicitly labeled |
| Units, light/dark appearance, walkthrough, password reset | Settings | Available in the app |

Parameters supported by the current source: temperature, pH, ammonia, nitrite,
nitrate, GH, KH, TDS, CO2, salinity, alkalinity, calcium, magnesium, phosphate.

No reviewer-only account, timed unlock, secret gesture, payment unlock, or remote
flag is introduced by this change. All reviewer instructions below use normal
user controls. AquaSpec hardware setup, RFID/NFC, AI chat, community, and a content
library are not reachable from this release's dashboard navigation; they must not
be advertised as available features. Experimental source retained from earlier
branches is not an instruction to unlock these screens during review.

## Suggested reviewer walkthrough

Provide working credentials in the private App Review Information fields. Use a
normal account that can create and edit tanks. Do not commit credentials here.

1. Sign in and tap Add tank. Set the name, water type, volume, and tracked
   parameters. Save the aquarium.
2. Tap Record and select that aquarium. Log two test results at different
   timestamps, including temperature and pH. Values may be entered manually;
   no AquaSpec device is required.
3. Open the aquarium's Overview. Select parameters and a date window to inspect
   the chart and compare results against the configured ideal ranges.
4. Open Readings, edit a manual entry, and use Export CSV to open the system
   share sheet. The file includes the configured chemistry values.
5. Open Notes, create a journal entry, and attach a photograph when prompted.
6. Open Tasks, create a maintenance task with a due date, and mark it complete.
7. After loading a tank online, disconnect networking, reopen Record, and save
   a reading. Confirm the offline message. Reconnect and refresh the dashboard;
   confirm the record is synchronized and is not duplicated.
8. Open Settings to change temperature/volume units and appearance, or view the
   walkthrough again.

## Draft response (use only after device validation)

We have revised Rotala's core aquarium-management flow and removed unfinished
navigation and recording controls. All available functionality is listed in the
review notes and is accessible through the same controls for every account.

Rotala is implemented with Flutter widgets and native device integrations. It is
an aquarium test log and maintenance journal: users configure tracked water
parameters and ideal ranges, record and edit timestamped measurements, inspect
historical charts, maintain photo notes and due-dated tasks, save test results
locally when offline, and synchronize after reconnecting. This experience works
without AquaSpec hardware. The review notes provide step-by-step instructions.

Your 2.3.1(a) message did not identify the hidden feature or the steps that revealed
it. If a concern remains after reviewing the supplied feature inventory, please
identify the specific screen or behavior so we can address it precisely.

## Remaining work before claiming this resolves review

- Run the automated checks and validate a fresh build on a physical iPhone and
  iPad. This Linux workspace cannot validate iOS camera permissions or sharing.
- Confirm the deployed database supports every parameter and that a standard
  account can read/write only its own records. Source inspection alone cannot
  establish server configuration or row-level security.
- Verify offline-to-online synchronization with real data, including closing
  and reopening the app. There is no background-sync promise.
- Match screenshots, description, age-rating and privacy answers to this feature
  inventory; provide current review credentials.
- Address account deletion and an accessible privacy policy before submission.
  These are separate readiness gaps; they are not implemented by this patch.
- Renew the developer membership and select a new build only when distribution
  work resumes. These changes do not guarantee Apple's approval.
