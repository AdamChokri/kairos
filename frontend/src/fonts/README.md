# The interface font

`schibsted-grotesk-latin-wght-normal.woff2` is **Schibsted Grotesk**, a variable font (weights 400 to 900, Latin range), licensed under the SIL Open Font License 1.1 (`OFL-schibsted-grotesk.txt`, kept with the font as the licence asks).

| | |
|---|---|
| Source | npm package `@fontsource-variable/schibsted-grotesk` **5.3.0**, published 2026-07-19 (older than the 7 days of D-12), file `files/schibsted-grotesk-latin-wght-normal.woff2` |
| SHA-256 | `4c8b93f431d462c696e12b9d6a033feb3394d36e66e781357c496b95d8a75e05` |
| Why a file and not a dependency | a font is data: the file is read once, by the browser, from this origin (the policy allows `font-src 'self'` and nothing else). Making it a dependency would add a package, its updates and its supply chain to `package.json` for no code |
| Characters | Latin, which includes the French accents. Anything outside it falls back to the system font of the stack in `styles.css` |

To change it: download the new file from the package version you choose (after the 7-day wait), check the licence file in the same package, replace the two files and the hash above, and run the pipeline once.
