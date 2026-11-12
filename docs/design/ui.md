# The Kairos interface (UI-01)

One theme, **Graphite**: a dark rail for the tasks and for Kairos Assist, and a light page for the task that is open. Decision D-40 records the choice; this page records what was built, so the next change keeps it.

## What it is made of

| Part | Choice |
|---|---|
| Layout | two columns from 860 px up: the rail (22 rem) and the page. Below 860 px the two become two screens: the list, then the task with a *All tasks* link |
| Size | rem units; the root size is `clamp(15px, 0.3vw + 11px, 20px)`, so a 1707 px window (a 2560 px laptop screen at 150 %) reads at 16 px and a 2560 px window at 19 px |
| Type | Schibsted Grotesk, one family, weights 400 to 800 (`src/fonts`, SIL OFL 1.1) |
| Colour | rail `#202327` / `#2a2e33`, page `#f5f6f7`, text `#1b1d20`, accent **raspberry `#cc2d5e`** (hover `#ae204c`), muted text `#5d636b` on the page and `#a3a9b0` on the rail |
| Accent | used for the primary action, the task that is open (a filled dot in the rail), and the *Open* status. Nothing else is coloured: done tasks are grey, errors are a red box with an icon and a sentence |
| Mark | two halves of a diamond with a gap between them, an inline SVG (`src/Icons.tsx`, `public/favicon.svg`) |
| Motion | a background colour change of 0.12 to 0.15 s on buttons and rows, switched off for `prefers-reduced-motion` |

## What the screens do

- **Log in / create an account:** a dark panel that says what Kairos is, and the form. A session that ended shows *Your session has ended. Log in again.*; a refusal shows the API's own sentence.
- **Rail:** search, *New task* (a form that opens in place, closes with Escape), the tasks grouped *Open* and *Done* with counts, then Kairos Assist.
- **Kairos Assist:** a note in, a suggestion out, shown as text (SV-12). *Add to my tasks* creates the task and opens it; *Dismiss* drops it.
- **A task:** status, title, description, *Mark as done / open*, *Delete task* (asks first, with the keyboard on *Keep it*), comments with their time, a comment form.
- **Empty, loading and error states** say what happened and what to do, in plain sentences, without apology.

## What must not change

- **The rule of the page**: no inline style, no inline script, no other host, no `data:` font, so that the page would run under a strict Content-Security-Policy. All styles are in `src/styles.css`; no component sets a `style` attribute.
- **SV-03 and SV-12:** a comment and a suggestion are text. `CommentList.tsx` and `AssistPanel.tsx` keep their names and their tests; `react/no-danger` stays an error.
- **No new dependency** in `package.json`. A change of font is a file, not a package (`src/fonts/README.md`).
- **The API:** the interface calls the same routes with the same bodies. A comment's time is read as UTC when the API sends it without a zone (`src/format.ts`, tested).

## Checked

`tsc`, ESLint and Vitest (31 tests) run in the pipeline; the page was rendered in Chromium under a strict policy of its own with no violation reported, at 1280, 1707 and 2560 px wide and at 390 px, in every state above. Every text and background pair of `styles.css` has a contrast of at least 4.5:1 (computed, the lowest is 4.52:1) and the marks that are not text at least 3:1. Not checked: other browsers than Chromium, and a screen reader.
