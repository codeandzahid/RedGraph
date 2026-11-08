# RedGraph

Make narrated faceless Shorts (YouTube Shorts, TikTok, Reels) fully in code, on your own computer. No AI images. No AI video. No API keys. No credits.

You give it a topic. It writes the script, speaks it with a free local voice, times every word, draws the shots in code, and renders a vertical MP4 with word-synced captions, sound, and music.

## Styles

Six styles, one per folder in `styles/`:

- **Deep Dive 3D** (`deep-dive`) — the flagship. Zack D. Films-like 3D "what happens if…?" body and science explainers. Sculpted 3D people in sunlit sets, glowing x-ray bodies, camera trips through blood vessels.
- **Night File 3D** (`night-file`) — unsolved mysteries and true crime. Dark 3D places with one light, faceless people, typewriter dates, case-file inserts.
- **Inside Out** (`inside-out`) — flat 2D "what happens if…?" explainers. A simple hero, x-ray cutaways, bold 1–3 word captions.
- **Stick Story** (`stick-story`) — "what would you do if…?" survival steps. Stick people with acting eyes, flat rooms day and night, gold step cards.
- **Paper Atlas** (`paper-atlas`) — history in cut paper. Parchment maps, crimson routes, gold date ribbons, period figures.
- **Tall Tale 3D** (`tall-tale`) — funny true stories. Flat 2D cartoon people acting in a sunny 3D small-town world, camera always moving, one-word captions.

## Install

Needs: Node.js 22+, ffmpeg, Google Chrome, Python 3.10+. About 1 GB of free downloads on first setup (voice + word-timing models).

```bash
git clone https://github.com/codeandzahid/RedGraph.git
cd RedGraph
bash scripts/setup.sh
```

Run `setup.sh` until it prints **All set**. Then prove it works:

```bash
bash scripts/selftest.sh
```

Run it until it prints **SELFTEST PASSED**. Look at the contact sheet and clip it names.

## Make your first video

```bash
bash scripts/new_video.sh deep-dive knuckles
```

That copies the Deep Dive example into `~/faceless-shorts/knuckles/`. Then:

1. Write your script in `script.json` (lines + caption chunks + sources).
2. Voice + word timings: `scripts/py scripts/voice.py ~/faceless-shorts/knuckles` then `scripts/py scripts/words.py ~/faceless-shorts/knuckles`
3. Rewrite `src/shots.js`: one shot per line, each placed on its word.
4. In the project folder: `node tools/capture.mjs check` (must say CHECK OK) → `node tools/capture.mjs cues` → `scripts/py tools/mix.py .` → check the contact sheet → `node tools/capture.mjs video renders/knuckles.mp4`

Read `SKILL.md` for the full steps, script rules, and QA checklist. The skill's own readme is in `docs/skill-readme.md`.

## Cloud computer / no graphics card

RedGraph runs on a plain cloud computer with no graphics card. Two things to know:

**Chrome.** If the computer has no Google Chrome installed, point the skill at any Chromium binary with the `CHROME` env var. `setup.sh` and `capture.mjs` both respect it. On this VM the working Chrome is the Playwright one:

```bash
export CHROME=/home/hatch/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome
```

**Slow 3D render.** With no graphics card, the 3D styles render in software. Put this in front of every `capture.mjs` render command:

```bash
SOFTWARE_GL=1 QS='&res=0.6&aa=0&shadow=1024' FPS=24
```

That is about 2 seconds per frame, about 30 minutes for a 35 second short. Run renders in the background and check the contact sheet first (`node tools/capture.mjs sheet review/all.jpg 1 10`).

## Fast render

`scripts/render-fast.sh` renders the same video faster. It splits the video into frame-exact chunks, renders each chunk in its own Chrome in parallel, at a smaller 3D size (`res=0.4`, `shadow=512`), joins the chunks, and adds the sound once at the end. The video stays 1080x1920 — the 3D is drawn smaller and upscaled, so it looks a little softer than the full render.

```bash
bash scripts/render-fast.sh ~/faceless-shorts/knuckles renders/fast.mp4
```

Options: `--workers N` (how many Chromes at once; it picks from free RAM if you do not say), `--res 0.4`, `--fps 24`, `--range START END` (render only part of the video, for example to redo one fixed shot).

Measured on this computer (4 CPUs, 8 GB RAM, no graphics card), Deep Dive 3D, a 5 second slice (120 frames):

- Standard render: 874 s — 7.3 s per frame.
- Fast render: 399 s — 3.3 s per frame. That is 2.2x faster.
- Two chunks in parallel instead of one after the other: 347 s instead of 408 s. Only 1.2x — the software renderer already uses all the cores, so a second Chrome adds little.
- All together the fast render is about 2.6x faster than the standard render.

What that means for a 1 minute video: about 30–70 minutes with the fast render, depending on how heavy the 3D scenes are (light scenes about 30, heavy scenes about 70). The standard render takes 70–175 minutes. So it is much faster, but it is not 10 minutes.

10 minutes needs a graphics card. That is the real fix — with a graphics card these frames draw in milliseconds. A bigger computer with many more cores and RAM would help too, because then the parallel chunks would actually scale. On this computer, use the fast render for drafts and quick checks, and the full render when the softer 3D would bother you.

## Notes

- Videos are 1080x1920, 24 fps, 25–60 seconds depending on style.
- The code, stories, drawings, and sound in this repo are original and free to use in your videos. Inter font: SIL Open Font License 1.1. Installed on first use: Kokoro-82M (Apache-2.0) via kokoro-onnx (MIT), faster-whisper + Whisper small.en (MIT), numpy, scipy.
