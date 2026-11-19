

https://github.com/user-attachments/assets/1200f708-005d-4e4f-adb9-44da06ef267b

# QueueCue (qq)

> QueueCue (qq). Because job hunting makes everyone want to cry.

## The problem

At campus career fairs, popular booths have 2+ hour lines, students print many copies of the same resume, many scan a booth QR code and leave without reaching a recruiter, and almost nobody prepares a company-specific pitch. Recruiters get a pile of paper and no way to find the best fits.

## What QueueCue does



https://github.com/user-attachments/assets/4372a572-f92b-447f-b4d8-6766219e3811


**Students (phone web app, installable to the home screen)**

- **Fair plan**: every booth ranked by blind fit, with which resume to use and why, and flags for visa sponsorship, "hires my major" and US-citizens-only. No booth is hidden; low fits show the reason.
- **Virtual lines**: scan the booth QR, join the line, see people ahead and a wait *range* ("~35 to 45 min") from that booth's real service times.
- **Drop and go**: send the matched resume plus an optional 2-line note (AI can suggest one in your voice) straight to the recruiter's inbox.
- **Pitch brief**: 20 to 30 seconds that sounds like you, built from your Voice Profile, with one booth-specific question, two talking points and a source for every sentence. Buttons: More like me, Shorter, Different project, Edit.
- **Card exchange**: a rotating personal QR (changes every 30 s). The recruiter scans it: cards swap, you leave the line, the conversation lands in your Rolodex.
- **Rolodex**: 15-second voice or text note after each chat; AI drafts the follow-up email in your voice. Copy or Open in Mail.
- **Fair Play guarantee**: at close, your best resume reaches your top 3 fit recruiters, even if you never reached their booths. **Line credit**: if a line closes while you're in it, you land in that recruiter's inbox as "Waited 50 min, did not reach you".
- **Game layer**: Fair Play points that reward quality (verified conversations, follow-ups), capped volume, levels, 3 side quests, pixel badges, a Fair Recap and an opt-in friends leaderboard.

**Recruiters (tablet or laptop, no training)**: live line with one-tap **Met** or **Scan student QR**; optional pile + memory note at the moment of confirming; a shortlist in three sections (Met you in person / Waited for you / Sent their resume) labelled "Suggested order. You decide."; private stars and notes; drag to reorder; blind review; second-look check; rating-drift notice; filters; CSV and ZIP-of-PDFs export; sign-in with "Download top rated (over 3.5 stars)".

**Organizers**: live heat map of the floor, Close fair, fairness weights, committed lottery seed, accessibility requests with staff confirmation, post-fair fairness audit (CSV), printable booth QR codes, Demo Mode controls (Simulate crowd, Reset demo, live AI toggle).

## Architecture: free, local, one laptop

```
 iPhones (Safari / home-screen app)          Recruiter laptop / tablet     Organizer screen
            │  HTTPS (Cloudflare quick tunnel, no account) or LAN
            ▼
 ┌──────────────────────── host laptop ─────────────────────────┐
 │  Dart server (shelf + shelf_web_socket)  :8080                │
 │   ├─ REST API + WebSocket live updates                        │
 │   ├─ serves the Flutter web build (app/build/web)             │
 │   ├─ SQLite (server/data/queuecue.db)                         │
 │   ├─ Fairness engine (pure Dart, property-tested)             │
 │   └─ AiService ─┬─ OllamaAiService → Ollama (qwen3:14b)        │
 │                 ├─ CachedAiService → assets/demo/ai_cache.json│
 │                 └─ OfflineAi (deterministic fallback)         │
 │  whisper.cpp (speech-to-text, local)                          │
 └───────────────────────────────────────────────────────────────┘
```

No API keys, no cloud accounts, no billing. AI runs as background jobs with honest progress ("Reading your resumes: 2 of 3"). Every AI call uses Ollama structured output (JSON schema), is validated, retried once, then falls back to the cached or offline result with a visible notice.

## Setup (under 10 minutes on a fresh laptop)

| Laptop RAM | Model (`server/config.json` → `"model"`) | Download |
| ---------- | --------------------------------------------- | -------- |
| 8 GB       | `qwen3:8b` (critic pass stays on)           | ~5 GB    |
| 16 GB      | `qwen3:14b` (default)                       | ~9 GB    |
| 24 GB+     | `gpt-oss:20b`                               | ~14 GB   |

The model name is a single config value. Demo Mode works without any model installed.

### macOS

```bash
# 1. Flutter (includes Dart)
brew install --cask flutter
# 2. Ollama + model
brew install ollama            # or the app from ollama.com
ollama serve &                 # the app does this automatically
ollama pull qwen3:14b          # pick the row for your RAM above
# 3. whisper.cpp (local speech-to-text) + English model
brew install whisper-cpp       # provides whisper-cli
mkdir -p tools/whisper && curl -L -o tools/whisper/ggml-small.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin
# 4. Cloudflare quick tunnel (free, no account)
brew install cloudflared
# 5. Run everything
./run_demo.sh --reset
```

### Windows (PowerShell)

```powershell
winget install --id Ollama.Ollama
winget install --id Cloudflare.cloudflared
ollama pull qwen3:14b
# Flutter: unzip the SDK from docs.flutter.dev/get-started/install/windows and add flutter\bin to PATH
# SQLite: download the 64-bit sqlite3.dll from sqlite.org/download.html into the server\ folder
# whisper.cpp: download whisper-bin-x64.zip from github.com/ggml-org/whisper.cpp/releases,
#   put whisper-cli.exe in tools\whisper\, set "whisper_bin" in server\config.json to its path,
#   and download ggml-small.en.bin into tools\whisper\
.\run_demo.ps1 -Reset
```

### What `./run_demo.sh` does

1. Checks Ollama (starts it if installed) and the model, and whisper.cpp.
2. Builds the web app if the source changed (`flutter build web --no-web-resources-cdn`, so nothing loads from a CDN).
3. Starts the server on :8080.
4. Opens a Cloudflare quick tunnel (`cloudflared tunnel --url http://localhost:8080`) and prints the **HTTPS link as a QR code** in the terminal, plus the Phone A / Phone B / recruiter / organizer links.

Flags: `--reset` (fresh seed), `--live` (live model on), `--cached`, `--lan` (skip the tunnel).

**LAN-only fallback** (no internet at the venue): `./run_demo.sh --lan` prints `http://<laptop-ip>:8080`. Phones must be on the same Wi-Fi. iPhone Safari only allows the camera and microphone on HTTPS, so on LAN use the Demo Mode booth taps instead of scanning and type answers instead of recording. The recruiter laptop can still scan with its webcam because `localhost` counts as secure.

## Add QueueCue to an iPhone home screen

1. Open the link in **Safari** (scan the terminal QR with the Camera app).
2. Tap the **Share** button, then **Add to Home Screen**, then **Add**.
3. Launch it from the "QueueCue" icon: it opens full screen like an app. Allow camera access the first time you scan.

## Demo Mode

- Organizer → **Floor** tab: **Simulate crowd** (simulated students join lines and are served every few seconds; real students are never moved), **Reset demo**, and the **Live AI** toggle (off = cache, the default).
- Seeded data: one fair, 12 fictional employers (big tech, AI startup, embedded/EE, finance, a defense company that requires US citizenship, and more), 110 simulated students, and 3 demo students with distinct resumes and voices:
  - **Viktor Krum**: international MS CS student, F-1. Casual, story-first.
  - **Hermione Granger**: computer engineering, US citizen. Concise, numbers-first.
  - **Percy Weasley**: MS Business Analytics, permanent resident. Formal.
- Sign a phone in as a demo student with `/?student=demo-viktor` (or `demo-hermione`, `demo-percy`), or tap them on the welcome screen.
- Recruiter accounts: `<first name>@<company>.example`, password = company short name. Example: `kingsley@northwind.example` / `northwind`. Booth links: `/booth/<id>?key=bk-<id>`.
- Organizer: `/organizer?org=org-demo-key` (change `organizer_key` in `server/config.json` for a real fair).

**The AI cache.** `server/assets/demo/ai_cache.json` ships as a hand-written starter for the 3 demo students, and the test suite checks every cached pitch against the critic rules. Before the demo, regenerate it from the live model so judges see real model output:

```bash
cd server && dart run bin/build_cache.dart            # all demo students x all booths (slow)
cd server && dart run bin/build_cache.dart northwind  # just one booth
```

Anything not in the cache falls back to an offline draft built only from the student's own resume lines, labelled as such in the app.

## 90-second demo script

**Before you start:** `./run_demo.sh --reset`. Projector shows the recruiter view for Northwind on the laptop (`/booth/northwind?key=bk-northwind`), organizer in a second tab. Phone A opens `/?student=demo-viktor`, Phone B opens `/?student=demo-hermione`.

| # | Who                | Do                                                                                                             | Show                                                                                                                                     |
| - | ------------------ | -------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | Phone A (Viktor)   | Plan tab                                                                                                       | Halcyon Systems at the bottom: **US citizens only**, **Does not sponsor visas**. Lumen Labs #1: **Use: AI/ML resume**. |
| 2 | Phone A            | Tap **Northwind Cloud**, **Join line**                                                             | **~35 to 45 min**, **13 ahead of you**. Pitch brief appears. Read it aloud.                                                  |
| 3 | Phone B (Hermione) | Northwind, **More like me**                                                                              | "140 pages a week, down to 53…": the same booth in a clearly different voice.                                                           |
| 4 | Phone B            | **Drop and go**, Production Eng resume (marked "Matched"), Send. Then **Join line**.               | "Dropped at Booth 1. The recruiter can see it now." 14 ahead.                                                                            |
| 5 | Laptop (recruiter) | Look under **Sent their resume**                                                                         | Hermione appeared live with the fit reason. Tap 5 stars.                                                                                 |
| 6 | Laptop + Phone A   | Phone A: **My card** tab. Laptop: **Scan student QR**, pick **Standout**, type a memory note | Cards swap, Phone A leaves the line, Phone B's estimate drops to 13 ahead.                                                               |
| 7 | Phone A            | **Rolodex**, **Record 15-second note**, then **Draft follow-up in my voice**, **Copy** | An email that sounds like Viktor, referencing what the recruiter said.                                                                   |
| 8 | Organizer          | **Close fair**                                                                                           | Phone B: "Your resume reached 3 best-fit recruiters." **Fair Recap** with badges; **Me** tab shows the friends leaderboard.  |

Without whisper.cpp installed, step 7 uses the cached demo transcript; with it installed the recording is transcribed on the laptop.

## Fairness engine (provable, auditable)

- **Live line**: strict first-in, first-out. Nobody can skip anyone.
- **Recruiter shortlist**: three sections in order: *Met you in person* (verified conversations only), *Waited for you* (line credit), *Sent their resume* (drops + Fair Play, with a "Strong matches you didn't meet" strip for fit 0.85+).
- Within each section: **Score = 0.85 × Fit + 0.15 × Effort**, Effort = min(minutes waited in this line, 60) / 60. Waiting can lift a student past someone up to ~0.18 more qualified, never further.
- **Fit** is blind: name, email, phone, links, pronouns, years/dates and addresses are removed before scoring, and each resume is scored twice with the role list in two orders, then averaged.
- **Ties**: lottery keyed by SHA-256 of a seed committed at fair start (hash on the organizer screen) and revealed at close.
- **Never used in Score**: Fair Play points, level, badges, arrival time of day, name, school year, anything identity-related. Recruiter stars and piles are private tools and never merged into Score.
- **Presence verification**: only the recruiter's device (booth key) or organizer staff can confirm a conversation. Student QR codes rotate every 30 s (HMAC of student id + time window). Booth QR codes never count as a conversation. One verified conversation per student per booth; two confirmations within 20 s ask "Group chat?"; only checked-in students. Accessibility exception: staff can confirm a conversation held at the accessibility desk or by video.
- **Fairness receipt**: students open "Why am I here?" to see their Fit, Effort, Score and the formula for every list they're on. Recruiters see the formula above their list.
- **Post-fair audit** (organizer): correlation between arrival time and rank within each section (should be near zero), average rank by arrival hour, Fair Play delivery by major and by work authorization with a four-fifths flag, revealed seed, CSV export.

### Proof: invariance tests (`cd server && dart test`)

```
$ dart test
  ✓ Invariance: identity, arrival time, points and level never change the order random changes to name, arrival time of day, points, level and grad year
  ✓ Sections every verified-conversation student appears above every non-verified student
  ✓ Sections line credit ("Waited for you") sits above remote resumes, below verified
  ✓ Sections a highly qualified remote candidate is flagged as a strong unmet match
  ✓ Effort cap changing only wait minutes changes order only within the effort cap
  ✓ Effort cap waiting 500 minutes counts the same as waiting the cap (60)
  ✓ Effort cap waiting can lift a student past someone slightly more qualified, never far more
  ✓ Lottery ties are broken by SHA-256 of the committed seed, reproducibly
  ✓ Lottery a different seed gives a different tie order (seed matters, is not ignored)
  ✓ Wait estimate is a range, never a single number
  ✓ Wait estimate rolling average ignores outliers and falls back to the default
  ✓ 1. Plan: "US citizens only" booth flagged; AI/ML resume chosen for the AI booth
  ✓ 2. Join the big tech line: 13 ahead, "~35 to 45 min", pitch brief appears
  ✓ 3. "More like me" on a different student gives a different voice
  ✓ 4. Drop and go with the Production Eng resume
  ✓ 5. Recruiter view shows the drop live with a reason; stars are private
  ✓ 6a. A student cannot verify their own conversation
  ✓ 6b. An old screenshot of the rotating QR is rejected
  ✓ 6c. Recruiter scans Phone A: cards swap, A leaves the line, B moves up
  ✓ 6d. Sanity limits: second confirm within 20 s asks "Group chat?"; one per booth
  ✓ 7. Rolodex voice note becomes a follow-up email in the student's voice
  ✓ 8. Close fair: line credit + Fair Play reaches top-3; recap and audit
  ✓ Every cached pitch passes the deterministic critic
  ✓ Every number in a cached pitch is traceable to the student materials

00:01 +24: All tests passed!
```

The full output is in [docs/test_output.txt](docs/test_output.txt). The property tests run 300 random shortlists each: randomly changing name, arrival time, points, level and grad year never changes the order; every verified student sits above every non-verified one; changing only wait minutes reorders two students only when their fit gap is within the effort cap; a student token cannot confirm a conversation.

## AI layer

One `AiService` interface (`server/lib/ai/ai_service.dart`) with `OllamaAiService` (live) and `CachedAiService` (demo), plus a deterministic `OfflineAi` fallback. Tasks: resume → skills/projects, Voice Profile, booth fit + resume choice, pitch (facts → draft → separate critic pass → up to 2 rewrites), drop note, recruiter summary, follow-up email. Every prompt carries the grounding rule (only facts from the student's materials and the employer data; "unknown" otherwise). The critic is backed by a deterministic lint (banned phrases, company praise, self-praise, emoji, more than one exclamation mark, generic questions, untraceable numbers) that runs on every pitch, cached or live.

All prompts and their JSON schemas: **[PROMPTS.md](PROMPTS.md)** (regenerate with `cd server && dart run bin/dump_prompts.dart`).

## Project structure

```
app/                      Flutter (Dart 3, Riverpod, go_router)
  lib/core/design/        design tokens + theme (restyle = this folder)
  lib/core/api/           REST client, WebSocket live updates
  lib/core/strings.dart   all user-facing copy
  lib/features/           onboarding, plan, booth, recruiter, rolodex, organizer, game, about
server/                   Dart (shelf, shelf_web_socket, sqlite3)
  bin/server.dart         entry point
  bin/build_cache.dart    regenerate the AI cache from the live model
  lib/routes/             REST API
  lib/ai/prompts/         one prompt file per task
  lib/db/                 SQLite schema
  lib/seed/               seed fair, personas, crowd simulation
  lib/fairness/           fairness engine
  lib/game/               points, quests, badges, recap
  test/                   invariance + demo-script tests
run_demo.sh / run_demo.ps1  one command to start everything
PROMPTS.md                every prompt + JSON schema
```

## Routes

`/` student app · `/join/:booth?t=…` booth QR target · `/b/:booth` booth screen · `/booth/:booth?key=…` recruiter view · `/recruiter` recruiter sign-in · `/organizer?org=…` organizer · `/recap` · `/fairplay` · `/why` · `/about`

## Troubleshooting

- **Phone can't open the link**: on LAN, phone and laptop must share Wi-Fi and the laptop firewall must allow port 8080. Prefer the tunnel link.
- **Camera or mic does nothing on iPhone**: you're on `http://`. Use the `https://…trycloudflare.com` link.
- **QR scanner shows a camera but never reads codes**: the in-browser scanner (mobile_scanner) downloads its ZXing decoder from a public CDN the first time, so the scanning device needs internet. On LAN-only Wi-Fi, use the Demo Mode booth list on phones; for the recruiter, open the booth view once while online so the browser caches the decoder.
- **"Local AI could not complete…"**: Ollama is down or the model isn't pulled. The app shows the cached or offline result meanwhile; the organizer Live AI switch shows status.
- **Start over**: Organizer → Reset demo, or `./run_demo.sh --reset`.
