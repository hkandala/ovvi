# Phase 61: anonymous usage data

## The user's words

"once i release this app for public, i want to basically track few things such that i can udnerstand how many are
using, what features etc things so i can have some basic dashboard to monitor, no user related data should be collected
at all, fully anonymous info"

"i don't want to start with somthing simple and later difficulto migrate, if its simpler to do id approach now let's go
wth it, let's avoid sdk like you said, default should send automatically, and have an option in settings to disable,
leave crash report fornow"

"id approach okay", "yep at the end of onboarding or somewhere, keep it subtle", "let's go with EU"

## Decisions

- PostHog Cloud EU (`https://eu.i.posthog.com`), plain HTTPS, no SDK. IP capture off. The project key is write-only
  and lives in the app.
- A random install id (UUID), made at the first send, kept in app storage only. Turning sending off deletes it; turning
  it on again makes a new one. `$process_person_profile: false`.
- One event, `app_day`, at most once per local day of use: version, macOS version, arch, and yes/no flags for the
  features used that day. No paths, names, hosts, URLs, commands, text, error messages, screen size, time zone,
  locale or IP.
- On by default. Settings ▸ General ▸ "Share anonymous usage data". `DO_NOT_TRACK=1` (or `OVVI_TELEMETRY=0`) turns
  it off. Ovvi Dev, Debug builds, UI tests and runs with `-session` never send.
- A subtle line at the end of onboarding says Ovvi sends anonymous usage counts and where to turn it off.
- A log of what was sent; a public docs page lists every field, checked against the code by a test.
- No crash reports for now.
- The earlier plan, ~/Downloads/ovvi-research/telemetry-plan.html, is superseded where it differs.

## Tracks

### Track T (one agent)

Build phase 61 with the least code: one app file, the typed event in HerdrKit for its unit tests, the Settings switch,
the onboarding line, the log, the docs page and the PostHog steps for the user.

## Findings

### Track T

- **Decisions.** A day goes only after it ended (the next launch or the hourly check), so it is sent once with all its
  flags; today waits. Every pending day goes in one `/batch/` request; a failed one keeps them, and a day older than 7
  goes. The timestamp is the day's date at 12:00 UTC: no time of day or time zone. The log keeps the last 7 events
  (one a day of use), not 7 calendar days. The switch sits in General under "Analytics". The key is committed in the
  Makefile as `zip`'s `POSTHOG_KEY` (a project key only writes); release.yml's `make zip` takes it, no secret.
- **Decisions.** The hooks are one line each where the thing starts: `Browser.init`, `Plugin.init` (explorer, git,
  any other), `ChatView` and `FloatingWindow` appearing, the palette's `onAppear`, `toggleOverview`, `FileDrop.drop`,
  an `ovvi` request answered, and each snapshot (a remote machine's session, herdr's agents by name).
- **Decisions.** `DO_NOT_TRACK`/`OVVI_TELEMETRY` come from the app's environment plus the login shell's (`ProcessExec`
  merges those two keys besides PATH and HOME); either deletes the id and the days at launch, as the switch does.
- **Runs.** HerdrKit's `UsageTests`: a local NWListener takes the POST (no network): once a day, the 503 retry and the
  7-day drop, the switch's delete and new id, DO_NOT_TRACK, and the event's keys against the docs table.
  Nothing sends in UI tests: Debug builds have no key and `-session` runs make no `Usage` at all.
- **Fix (review).** The day is the Mac's date from its UTC offset, not from `Calendar.current`: a Buddhist calendar
  put the timestamp 543 years ahead. The request says `Accept-Language: en`: URLSession's own told the user's
  languages. The onboarding line shows on the herdr step too, beside Skip.
- **Open.** A login shell slower than its 3 s bound brings no rc-file variables, so a `DO_NOT_TRACK` set only there
  is missed on that launch; the app's own environment always counts.
- **For the user.** PostHog: in project 350784 (Cloud EU), Settings ▸ Project ▸ General ▸ "Discard client IP data"
  on. Insights in the reply. The welcome's films show the last page without the new line until the next recording.
