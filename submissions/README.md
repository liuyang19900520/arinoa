# App Store submission material

One folder per version, named after the version number (`submissions/1.0.2/`). The `Submit for review` workflow
(`.github/workflows/submit-review.yml`, run by Yang only) reads the folder of the version it submits.

## Folder layout

```
<version>/
├── README.md            what changed, checks before submitting, submission log
├── review-notes.txt     App Review information → Notes (English)
└── en/  ja/  zh-Hans/   one folder per language
    └── whats-new.txt    What's New for this version
```

- Only `whats-new.txt` (per language) and `review-notes.txt` are read by the workflow; anything missing is left as it is
  in App Store Connect. Other fields (description, keywords, screenshots) are filled in App Store Connect by hand.
- Language folders map to App Store Connect locales: `en` → en-US, `ja` → ja, `zh-Hans` → zh-Hans.
  A locale that isn't set up on the version in App Store Connect is skipped.
- What's New is at most 4000 characters.
- Write the text yourself or have Yang approve it; don't submit generated marketing copy unreviewed.

## Adding a version

1. Copy the previous version's folder (or start from the layout above) and rename it.
2. Write the three `whats-new.txt` files and `review-notes.txt`.
3. Add a row to the index below.

## Index

| Version | Status |
|---|---|
| 1.0.2 | Not prepared yet. The version bump to 1.0.2 is in the unmerged `feature/v1.0.2` branch (PR #12). |
