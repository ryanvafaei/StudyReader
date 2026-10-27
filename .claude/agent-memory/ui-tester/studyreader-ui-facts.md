---
name: studyreader-ui-facts
description: How StudyReader's UI looks to accessibility and automation; quirks found at the T52 checkpoint (2026-10-25, run by hand with computer use)
metadata:
  type: project
---

- Library window: sidebar is an outline (rows Library, Highlights, Review, Themed Reviews, Tags, Categories). Toolbar: Import (+), Sort and Filter menu buttons, Grid/List segmented control.
- Grid cards are one AXStaticText each, label "<title>, <author>, <category>, N highlights, N percent read". The cover is hidden from accessibility and sits above the text block (3:4).
- Reader tabs are native window tabs: the window has an AXTabGroup with AXRadioButton (AXTabButton) per tab, labelled with the window title, plus "Close tab" buttons and a "new tab" (+) button. Each tab is its own NSWindow; inactive tabs report as off-screen.
- The library tab's title follows the sidebar section ("Library", "Tags", "Categories").
- Reader toolbar: "Highlight color" menu button, inspector toggle (label mentions "panel").
- Window title of a reader includes the subtitle: "<title> – <category>".
- Synthetic mouse drags don't detach a window tab. Use Window > Move Tab to New Window and Window > Merge All Windows for the same AppKit path, and still try one real Peekaboo `drag`.
- Dropping a Finder file works on the grid view; at T52 it did nothing on the list view (Table).
- Finder Open With launched a stale pre-T47 StudyReader.app as a second instance until stale LaunchServices registrations were removed (scripts/lsregister-clean.sh).
- ⌥⌘H in a reader tab ran the system "Hide Others" (all other apps hid). Undo with StudyReader > Show All.
- The tab bar's "+" (new tab) button creates an empty "StudyReader" tab that says "No document".
- Import of one file shows a modal "Import finished / Imported 1" alert; dismiss with OK.
- System appearance may switch to dark during a run (auto appearance); covers and placeholders were readable in both.
- First real run (2026-10-25): the app started by run-app.sh wasn't frontmost, and the agent kept repeating the same actions. run-app.sh now activates the app; always confirm StudyReader is frontmost before keystrokes, and follow the no-retry-loop rule.
- 2026-10-26: launches with `-ApplePersistenceIgnoreState YES` showed no window at all (0 windows; LaunchView never ran). The flag was removed from run-app.sh and the UI tests; the tests also fall back to Window > StudyReader. If a launch shows no window again, open it from Window > StudyReader and report it.
- T63 cloud run (2026-10-27): `./scripts/uitest.sh` on CI takes ~15 min of test time, output prints only after it ends; run it in background and wait for the notification (don't poll with sleep loops). Screenshots: build/ci/<run>/ui-screenshots/manifest.json; failure attachments (Synthesized Event, UI Snapshot) are plists/mp4, not PNG.
- Highlight colour setting leaks between UI-test launches (later screenshots show pink). Seed highlights now carry richText (T63a), so panel rows/popover show their text. PDF Lecture: 3 pages, seeded position shows page 2 at y=120 from bottom; blue seeded highlight on page 3 line 1.
- Reader accessibility labels: "Page number" field, "Outline", toolbar "Snapshot", "Find in Document", "Highlight color"; panel picker "Panel" (Highlights/Notes), row label = the highlight text (T63a), list "Highlights list", notes editor "Document note", "Preview" checkbox.
