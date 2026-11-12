# Phase 58: Twentieth feedback: clicks that always land, balanced splits, a smoother chat

Goal: the fixes from the user's twentieth round (round 9 after phase 57's eight):

- A click anywhere on a card gives it the keyboard, for every kind of card.
- Splits stay balanced as panes open and close (a setting, on by default).
- A program's own copy on select works again.
- The chat moves smoothly: no flicker, fades instead of jumps, tables without artifacts.
- Small fixes to onboarding, windows, settings, the explorer and links.

The user's words are quoted; the decisions under them are the orchestrator's. Screenshots in `.build/fb57/` (not
committed; JPEG copies in `~/Downloads/ovvi-research/fb/`):

| File | Shows |
|---|---|
| `r9-2.07.24.png` | a remote File Explorer showing "Can't list /home/hkandala/swebench-autopilot/learnings" |
| `r9-2.33.00.png`, `r9-2.33.03.png` | a chat table's header row while scrolling sideways: a rounded-corner fill in a cell |
| `r9-2.33.42.png` | a chat table's row cut off at the bottom ("in MiniWorld and Habitat" clipped) |

Tracks run in parallel and push straight to main after their review, `make lint build test` and the UI tests they
touch in the Tart VM (no per-track CI, no host GUI; `~/Downloads/ovvi-research/p58-common.md`). The phase ends with
two full runs and on-demand on the final head.

## Track A: onboarding, windows, settings (items 1, 2, 4, 5, 6)

1. "during onboaridng if herdr is installed don't show the herdr slide at all, i see it worked fine before, but this
   time i saw the herdr slide where as soon as i moved to it, it showed herdr is installed? just make sure no
   flakiness is there in it"
2. "when starting session we show the power button icon, can we have some other icon? power button icon doesn't fit
   well"
4. "new window size should remember previous size, like when i open new window resized to certain size and position
   and when i open another new window it should follow same sizing and position"
5. "for font selection why there is a line separator? just list all fonts in alphabetic order and choose jetbrains
   mono as default"
6. "when installing new plugins, show in new pane should be unchecked by default"

Also: `scripts/herdr-session.sh` `down` and `up` wait 5 s (50 × 0.1 s), a bound that only matters when something
fails; lessons.md's rule makes it 60 s (round 8's final CI, '### Final CI, round 8' in phase 57).

## Track K: a click always activates the card (item 3)

3. "when plugin pane has some error, i saw some error saying nodejs not installed, while that's not the bug, but when
   such error comes, i cannot click on the pane to activate, clicking on header works, but clicking near the error
   doesn't activate the pane, also why this is such a common issue with activating panes, i have told these kind of
   bugs so many times already, investigate how clicking on pane activates and make sure it works all the time for
   terminal panes or browwser panes or plugin panes without any edge cases like this"

## Track P: the overview's zoom, balanced splits (items 7, 8)

7. "i don't see any animation now when selecting a tab from overview, before i used to see some animation of pane
   zooming in and sidebar and tabs fading in, now its immediate without any animation, why it got removed?"
8. "when a pane is opened on side can we do auto resize automatically to balance like how we do when new side pane is
   opeened? also when a pane is closed as well do auto resize, so they are equal in size, basically apply auto resize
   all the time when panes are opened or closed, we can keep this is settings may be whether to auto resize or not,
   defaulting to auto resize, and if disabled, all auto resize should be disabled and should work like herdr tui
   splits where it goes half and half evry split"

## Track M: a program's own copy on select (item 9)

9. "now with our custom select or something i guess, copying text on pi agent is not copying text, if i choose option
   of copy on select from settings, it does select but loses formatting, that is okay with the settings, basically
   when you select normally on any tui its native copy on select should be invoked, coz pi agent pastes the well
   formatted text into the clipboard when i select, so make sure that works, that used to work fine before your white
   block fix i guess"

   Phase 57 item 113 (Track L3) made left drags the card's, because herdr 0.9.5 reports no mouse mode; the white block
   was pi's reverse-video selection drawn beside the card's. Both must hold: pi's own selection and copy work, and no
   white block.

## Track C: a smoother chat (items 10, 11, 12, 13, 15, 16)

10. "on new chat, let's move it bit up such that propmt input is vertically center aligned, right now with logo and
    text it feels bit off"
11. "in the chat when long chat is loaded, i know we show loader and load it, but when transcript is revealed can we
    fade it in isntead of suddenly? like even if i switch between chat and tui quickly, i see transcript goes away and
    comes back like a flicker, let's either fix the flicker or add fade in animation so it doesn't look abrupt,
    similar animation when swithcing from low opactity to full opacity when prompt is submitted, it is bit abrupt now
    as soon as i submit prompt, i see bit dimmed version and then suddenyl changes, overall make the chat transcript
    smoother"
12. "make the prompt input bit more less transparent, like right now when i scroll, i see almost transparent and make
    typing propmt there harder, increase the opaqueness a bit while still keeping the glass effect"
13. "dimming blue for links in chat view is not good when hovering, is that what default style in browsers when you
    hover on a link? or does it show underline or something? idk that blue link and hover effect doesn't feel like
    regular link styles? idk check properly and fix it"
15. "there are weird artifacts when scrolling tables in chat view, like on table header there is some rounded corner
    kinda thing? i also see table contetn is getting clipped vertically?" (`r9-2.33.00.png`, `r9-2.33.03.png`,
    `r9-2.33.42.png`)
16. "let's increase propmt input max height to 10 lines"

## Track X: Codex chats from the transcript (item 14)

14. "that codex limitation for resumed chats is weird? why is that? are we relying on codex app server? or relying on
    transcript? should we change to rely on transcripy for codex as well so it works fine on resume and stuff"

    The limitation, from phase 57 Track C5: "A resumed Codex chat stays empty until its first prompt, because Codex
    starts its session only then."

## Track E: File Explorer and Git (items 17, 18, 19, 20)

17. "sometimes i see file explorer listing goes blank like this randomly and then comes back on its own? folder is
    still there, but something happening in the way it lists i see this. also this happens only on remote machines, i
    never saw this hapepning on mac" (`r9-2.07.24.png`)
18. "in file explorer if i have sidebar opened, and i am on certain file editor, how can i take my keyboard focus back
    to file tree? like with mouse click i can make it active but with keyboard i can't shift focus between file tree
    and editor? can we use some hotkey to toggle around between them?"
19. "in markdown for the outline thing as well, can we make it like glass button, so all three buttons on the right
    look consistent in markdown?"
20. "cmd+option+click not working in file explorer and git plugins, wherever cmd+click and option+click is enabeld,
    cmd+option+click should work too (except clicking on commit, i don't think there are any default apps you can bind
    to open diffs)"
