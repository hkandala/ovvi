# Phase 62: twenty-first feedback, a look of our own

The first feedback after v0.1.0. Round 1 is a report of options (no code); the user picks, then tracks run in
parallel.

## The user's words

"hey, i still need to finish your checklist and take care of npm publish and other stuff, while i do that i want you
to work on few improvements:

- when update is there we currently show that toast at bottom centered, can we show that bottom right side, and have
  some different coloring so it grabs user attention, like can have some bright border or something like that, don't
  make it too flashy just make sure its unique from regular toasts
- [screenshot r1-1] - we should improve markdown formatting with lists and code blocks, i see code blocks are going
  before the list margin, like text and code block should be aligned well, like code block shoudln't go before the
  list margin, if that makes sense
- [screenshot r1-2] - so for logos especially agnet ones, can we make them high quality, so i am trying out ovvi on
  ultrawide monitor, and i see when i start an agent those logos looks very blurry, make sure we have all high quality
  logos, preferably svgs, if we can get svgs for all logos
- and when i am using mouse on regular scroll tab strip should be scrollable, like horizontal scroll works now,
  basically even with vertical scroll i should be able to scroll the tab strip

and another major changes i want to do is more on getting unique look to our app, so our app has two major
inspirations: rex and t3code. specifically rex, before we launch to public i don't want our app to look like clone of
rex or copied from t3 etc

- from t3, i think only major thing i can think of is working icon, so t3code has unique working icon that dotted
  circle, and we adapted that, other ones are pretty much fine, give me some simlar alternate working icons which are
  circular and fits to our design better, give me multiple options to choose from. let's keep colors of statuses and
  everything same
- and coming to rex things, main thing is our top right buttons, i am thinking to drop overview and cmd+k buttons on
  top right, and top right we should show only + icon
- let's move overview button in left sidebar beside sorting button, and for now let's drop cmd+k button, and let's
  make the session title be like dropdown, it should be sublte, same design as now, when hoverred, we should see a
  down arrow beside the title, indicating its dropdown, and cliking on it should show dropdwon, it should list other
  sessions, and at the end open session button, so on clicking on it, it shouldn't show any glass dropdwon, instead,
  show something like our wrokspaces, like have a border for everything including + and sorting buttons and lists
  other sessions and open session as a button kinda thing, and when lost focus it should collapse to current view,
  and we should move the filter thing to top just below session header and drop the open session button as we show it
  in the new session dropdown, give me multile mockups of how this looks, so i can choose the right one what i am
  thinking, also cahnge placeholder from filter to something else, give me options, also when session changes and it
  scrolls to different session, only workspaces part should be scrolled, not this session header, in sessoin header
  of course the session titlt changes but we should show scroll effect only on workspaces
- one more thing when new workspace is created by default it goes to home dir and we see ~ in the workspace, instead
  let's show username like for me it should show hkandala, basically replace ~ with username so it looks better and
  it still can be renameable if user wants it
- [screenshot r1-3] - another approach for sessions is to have sesion drop down at the bottom like here, and at the
  top we have big new space button and sorting buttons, show me how this option would look as well
- and another thing let's drop the interface style option which is from rex, instead let's have one option in
  settings called something like use liquid glass feature or something along that lines, which is enabled by default
  and when its disabled we show our current classic view
- [screenshots r1-4, r1-5] - in rex i see this thing, for multiple hotkeys, there it will show + button on hover and
  when clicked on it adds a new hotkey below it and you can individually seelect and change them or remove them, i
  think we should update our shorcuts to similar to this so adding multiple hotkeys is easier
- one more thing i noticed our glass pane for cmd+k and cmd+/ ones its very frosted? like i don't see any trnasparency
  in them, can we improve that a bit with some transparency while maintaining readability, check what other glass
  panes we use have that and update them so they look consistent
- [screenshot r1-6] - let's have our icons on top right of pane exactly like this, change the floating pane icon and
  move its position as shown in image, and also i see our zoom pane icon is slightly bigger than other icons,
  basically make all icons of equal size visually, and update it
- [screenshot r1-7] - and on hover on any of these icons our current tooltip is not good, let's make the tooltips look
  something like this, with good padding, and good styling for hotkeys and also make them visible on less time, right
  now i have to hover for long time for it to show, let's make it shown in fairly quick time, like in 1s or less than
  that, update this for all icons in the ui to follow similar styling showing the right hotkey and same timing etc,
  make them consistnet

don't make any changes yet, give me a html report with multiple variations and ui mockups and with options for me to
choose and share the options easily, once i confirm on options, you can work on them in paralell"

The screenshots are in `.build/fb59/r1-1.png` to `r1-7.png` (not committed):

1. the markdown card: a fenced code block inside a numbered list starts left of the item's text;
2. "Starting Pi…" with a blurry pi logo, on an ultrawide monitor;
3. t3code's sidebar footer: a session picker ("Home ⌄") at the bottom, next to Feedback, Discord and a gear;
4. Rex's shortcut settings: a ⊕ on hover beside a shortcut, with the tooltip "Add a Shortcut";
5. Rex: two shortcuts stacked for New Window (⌘N, ⇧⌘L);
6. Rex's pane header buttons, left to right: split right, split down, float (two overlapping squares), zoom (two
   diagonal arrows), close;
7. Rex's tooltip: "Split Right" with a ⌘D key cap, a dark rounded panel with good padding.

## Round 1: the options report

`~/Downloads/ovvi-research/p62-options/index.html`. Each question has an id; the user's picks come back as a short
line such as `Q1 B, Q2 D, …`.

## Round 2: the picks

The user's picks, word for word: "Q1 D, Q2 F ("but no animated ones, we need to have still ones all the time"), Q3 B
("don’t show agent status indicators in sessions, also we show only attached session, so running/stopped doesn’t make
sense as well. so list attached sessions, and open session and open session basically opens up anyway showing list of
detached sessions and manage them"), Q4 A, Q5 A, Q6 A ("few more things: that confirmation use here or cancel should
show as regular confimration dialog instead of showing inline, and instead of remove shortcut we should show + icon
again there to add more shortcuts if eneded, and to remove shortcuts, one should be able to click to type and there we
shuld show cross icon to remove it"), Q7 B, Q8 C ("also on hover we or active we show circular padded one right, let’s
change that to rectangular one, no circular ones"), Q9 B, Q9 delay B ("oh also for float pane, can we add default
shortcut as cmd+opt+enter"), Home name ("sounds good"), Session slide ("looks good"), Markdown ("love it"), Logos
("sounds good"), Wheel ("sounds good")

go with these options and implement evrything, whatever can be parallelised, work on them in parallel"

What they mean:

- Q1 D: the update notice moves to the bottom right, with a still accent-to-green gradient ring and one sweep when it
  appears (none with Reduce Motion).
- Q2 F, still: the working icon is a ring with a centre dot, never animated.
- Q3 B: the session title is a quiet dropdown (⌄ on hover). It opens a bordered shelf, like Archived Sessions, with
  the window's attached sessions (no state dots, no running/stopped) and Open Session at the end. Open Session opens
  the full panel for detached sessions and managing them. The filter moves under the header; the old Open Session
  button at the foot goes. The top right shows only +. Overview moves beside Sort; the ⌘K button goes.
- Q4 A: the filter says "Find a space or agent".
- Q5 A: the Interface Style choice becomes one switch, "Liquid Glass", on by default. Its description: "The desktop
  shows softly through the window. Off, the window is solid." Off is today's Classic look.
- Q6 A: shortcuts stack like fields. On hover, ⊕ adds one, and stays the only button (no ⊖). To remove a shortcut,
  click it to record, and an × in the field removes it. A conflict asks in a standard dialog, not inline.
- Q7 B: floating panels use glass with ultraThinMaterial, the same level everywhere (see 2-look.html's table).
- Q8 C: the float button is macwindow.on.rectangle. The order is split right, split down, float, zoom, close; every
  glyph has the same visual size. Hover and active backgrounds are rounded rectangles, never circles.
- Q9 B with delay B: tooltips are a solid panel with an outlined key cap, shown after 0.5 s and at once when moving
  to the next button. Float Pane gets the default shortcut ⌥⌘↩.
- Plans: home name, session slide, markdown, logos and wheel, as written in the report.

## Round 2: tracks

| Track | Items | Worktree |
|---|---|---|
| S | Q3, Q4, home name, session slide | ../ovvi-p62s |
| G | Q1, Q5, Q7 | ../ovvi-p62g |
| I | Q2, Q8, logos | ../ovvi-p62i |
| T | Q9 and the ⌥⌘↩ default | ../ovvi-p62t |
| K | Q6 | ../ovvi-p62k |
| M | markdown, wheel | ../ovvi-p62m |
