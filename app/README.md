# Task board app

The app under test: a Vite + React + TypeScript task board whose first screen is controlled by the Flagsmith flag `first_screen` (`control` = empty board, `sample_data` = pre-filled examples).

```bash
cp .env.example .env.local   # add your Flagsmith client-side environment key
npm install && npm run dev
```

`?variant=control|sample_data` previews a variant offline (no flag call, no events). `?uid=<id>` sets the visitor id.

See the [root README](../README.md) and [EXPERIMENT.md](../EXPERIMENT.md).
