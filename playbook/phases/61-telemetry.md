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
