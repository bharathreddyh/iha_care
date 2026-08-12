# Scan Window Calculator

A single-page tool for Sahyadri Scan & Diagnostics to work out booking windows for:

- **NT scan**: 12w5d – 13w5d
- **Anomaly (TIFFA) scan**: 20w0d – 22w0d

Enter LMP, current gestational age, or EDD and it computes both windows. All
calculation runs client-side in the browser — no data is sent anywhere.

## Hosting on GitHub Pages

This lives in `/docs` so Pages can serve it without exposing the rest of the repo.

1. Merge this to the default branch (`main`).
2. On GitHub: **Settings → Pages**.
3. Under "Build and deployment", set **Source** = `Deploy from a branch`,
   **Branch** = `main`, **Folder** = `/docs`. Save.
4. Within a minute or two the live URL appears at the top of that page —
   usually `https://<username>.github.io/<repo-name>/`
   (here: `https://bharathreddyh.github.io/iha_care/`).
5. Open that URL on your phone and use "Add to Home Screen" for a one-tap shortcut.

## Files

- `index.html` — the full calculator (HTML/CSS/JS, no dependencies)
