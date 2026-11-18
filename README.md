# Agent Office

A small macOS window that shows your Claude Code agents at work, as a pixel-art office.

![Agent Office: the manager in the corner office with its edit button, three PR reviews at their desks and three in the queue on the sofa; Claude Code sessions with their subagents, each with its state, model and effort, beside the shared room's chat; the lounge at the bottom with the jukebox playing in the kitchen corner, teammates on a break and the list of people in the room, each with a Poke button](docs/screenshot.png)

*Demo data. Open `web/office.html` in a browser to see it live.*

See at a glance which session is **waiting for you**, which is working, which has finished, and what
its subagents are doing, without switching between terminals.

## Quick start

Needs macOS 13+, the Xcode command-line tools, `jq` and Claude Code.

```bash
git clone https://github.com/ArdaThePolat/agent-office.git
cd agent-office
scripts/build-app.sh                 # builds ~/Applications/Agent Office.app
scripts/install-hook.sh --dry-run    # shows the change to ~/.claude/settings.json
scripts/install-hook.sh              # registers the hook (keeps your existing hooks)
open ~/Applications/"Agent Office.app"
```

Sessions report from their next turn on; start a new Claude Code session (or send a message in an
open one) and it walks into the office.

The first time it opens, a short welcome tour shows what the office is, asks for your name and
(optionally) a picture, and offers to create or join a room; every step can be skipped, and the
tour is in the Agent Office menu (Welcome Tour…) to see again. Then make it yours, all from the app:
- **✎ edit** in the manager's room (or Agent Office → Your Name and Picture…): your name and
  picture, the manager at the desk and your character in a shared room.
- **Create a room** or **Join a room** in the lounge's right-hand panel (or the **Room** menu):
  share the lounge and a chat with teammates on your network.

### Or let your agent set it up

Run this in a terminal; Claude Code clones the repo and installs it, step by step:

```bash
claude "Clone https://github.com/ArdaThePolat/agent-office into ~/agent-office, then install Agent Office by following its AGENTS.md exactly. Show me the change to my Claude settings and ask me before applying it."
```

Using another coding agent? Paste the same sentence into it. [`AGENTS.md`](AGENTS.md) has the
steps with a check after each one, and the agent asks you before it touches your Claude settings
or your config.

Missing a prerequisite: `xcode-select --install` for the command-line tools, `brew install jq`.

## What you see

- **Others room**: every Claude Code session as a person at a desk, with its subagents at smaller
  desks below. Sessions in the same repo share a shirt and rug colour. They walk in through the
  door when a session starts and out when it ends. Under each one: its title, folder and state, and
  the model and effort of its latest reply (e.g. *Opus 5.5 · xhigh*).
- **Bubbles** say what each one needs:

  | bubble | means |
  |---|---|
  | **!** orange, blinking | waiting for your permission |
  | **✓** | done, your turn (for 30 minutes after its turn ends) |
  | **×** | its turn ended on an API error, often a network drop (for 30 minutes, then idle; send it a message to carry on) |
  | **hourglass** | its turn is over but subagents it started in the background are still running |
  | **…** | compacting its context |
  | **?** | quiet: working, but silent for over 10 minutes |
  | **z** | idle |

- **Manager's room** (optional, top left): you, at your desk. A screen on the wall counts the
  sessions that need you, are working or are done, with your weekly plan usage when
  the companion mod reports it; an orange **!** over your head when someone needs you. Under the
  desk: who needs you and who is working, your weekly usage as a battery that drains
  as you use it (orange, then red and blinking as they run low), when the week resets, and
  what the open sessions have cost. Click it
  for the stats screen. **✎ edit** under its window sets your name and picture (also in
  Settings, and Agent Office → Your Name and Picture…); the picture is copied next to the config,
  and a teammate in your shared room sees the change at once. Saving makes it the manager right
  away: `AGENT_OFFICE_MANAGER_…` lines in the env file, which would win over it, are taken out
  (a copy stays in `env.bak`). Or set `manager` by hand (see
  *Configuration*). The weekly number is one for the whole account: each session reports the
  value from its own last reply, so the gauge shows the highest report for the current week.
- **Lounge**: where agents with nothing to do go. A session that has been idle (or done for over 30
  minutes) leaves its desk for the lounge and keeps itself busy there: it makes a coffee at the machine,
  drinks it at the kitchen table, plays on the console, chats at the high table, each agent in
  its own order, walking between spots. It walks back to a desk the moment it gets work. **Right-click → Release to the lounge** sends
  one there yourself and empties its desk; it comes back on its own when you send it a message,
  or with **Back to the desk**.
- **Jukebox**: in the kitchen's corner, between two speakers. It shows what is playing on this
  Mac, from any app that shows in macOS's Now Playing (Spotify, Music, a YouTube video in Chrome
  or Safari, a podcast app): the cover as pixel art, the title and artist scrolling on its display
  with a line for how far in it is, and the app, album and time when you hover it. Its three
  buttons skip back, play/pause and skip ahead in that app, with no permission to give. The cover
  stays while you pause. It never starts an app, and nothing about what you play goes to the
  shared room. The lever on top switches soft party lights on over the lounge (drifting colours
  and mirror-ball glints; they hold still with Energy saver on), remembered on this Mac. Turn the
  jukebox off in Settings.

  macOS gives Now Playing only to Apple's own programs, so the app reads it through a small helper
  (`app/nowplaying.py`) that runs with the python3 of the Xcode command line tools the build
  already needs. Without them, the jukebox shows Spotify only: Spotify's own notification for the
  song, and Apple Events for the buttons, which makes macOS ask once whether Agent Office may
  control Spotify (if you said no, the tooltip says where to change it: System Settings → Privacy
  & Security → Automation).
- **Review room** (optional): one desk per PR-review slot with repo, PR, owner and how long it has
  been running, and a sofa for the queue. A review running longer than `overdueMinutes` (45 by
  default) gets a red frame and a ⚠ by its time: it may be stuck. A shelf along the front holds the
  last finished reviews, newest first (up to 5, fewer on a narrow window): PR, how long ago, and
  the result and cost when the reviewer logs them; green posted, amber asked you on Slack, grey
  rejected on Slack, red failed. Hover one for the details; a click opens its PR. See *Configuration*.
- **Log strip**: general events only (session waiting for you, done, subagent started / finished,
  review started / posted).

Hover an agent for details. **Click a session to bring it to the front where it runs:**

| started in | a click |
|---|---|
| Terminal, iTerm2 | selects that exact tab (and iTerm pane) |
| VS Code's Claude panel | brings that project's VS Code window forward and opens the session's tab in it |
| a VS Code terminal | brings that project's VS Code window forward (a terminal tab inside it cannot be picked from outside) |
| the Claude app | opens that session in the Claude app (`claude://code/continue?session=…`) |

VS Code (and Cursor, Windsurf, VSCodium) is found by the folder its window has open: the window
whose folder holds the session's directory. If no open window holds it, Agent Office falls back to
matching window titles, which needs **Accessibility** (System Settings → Privacy & Security →
Accessibility); without it the editor is just brought forward. The first click on a Terminal or
iTerm session asks once for permission to control that app. A review desk, or a review on its shelf, opens its PR.

Sessions already running when you install or update Agent Office learn where they run on their next
message.

**Right-click an agent** for *Open*, *Reveal folder*, *Copy session id*, *Release to the lounge* and *Hide from view*. A
hidden agent stays out of the office until something new happens to it (you send it a message, it
asks for a permission, its turn ends, it errors); then it walks back in. Right-click anywhere →
**Show hidden agents** brings them all back.

### Stats screen

**Stats** (top right, or press **S**) lists every session with where it runs, its state, model and
effort, how full its context is, what it has cost and its subagents' states, plus your plan usage
(the weekly window, and when it resets). Click a row to open that session.

**Cost by repo** adds up the sessions that did something today (the hook heard from them since
midnight), grouped by folder the same way as the shirt colours, most expensive first, with a total.
The mod reports what a session has cost since it started, not per day, so a session that began
yesterday and is still in use counts in full; sessions with nothing since midnight are left out
(the note under it says how many). Without the mod's cost the section is not shown.

![The stats screen: plan usage, totals, and one row per session](docs/stats.png)

### Companion mod (optional): context, cost, plan usage

The hook sees what a session does; only the session itself knows how full its context is, what it
costs, your plan usage and each subagent's exact state. The optional companion
[mod](https://code.claude.com/docs/en/plugins/mods/overview) in `mod/` reports those, and the office
shows them: a **context gauge** under each desk, **status dots** on subagents (running, waiting,
idle, failed), and the numbers on the stats screen. It also pins a one-line status under your
prompt in every session, e.g. `office: 2 need you (Flaky test hunt, Infra cleanup) · 3 working`.

```
/plugin install agent-office --marketplace ArdaThePolat/agent-office
```

(or `claude plugin install agent-office --marketplace ArdaThePolat/agent-office` from a shell).
Needs Claude Code 2.1.287 or later. It writes one small file per session under
`~/.local/state/agent-office/live/`, records no prompts or tool calls, and everything else works
without it.

### Shared room (optional): one lounge for the team

Teammates on the same office network can share their lounge. Everyone in the room appears in
everyone's lounge as their own pixel character, their name over their head, drinking coffee and
playing on the console, and the chat talks to the whole room. With a room set up the chat is a
fixed panel on the right of the others room, whether you are in the room or it is local right
now (the panel then says so, with **Try now**); in a narrow window it moves behind a **Chat**
button (or **C**). **Hide** (or **C**) folds it away and gives the desks the room back; a bell tab
stays on the right edge and rings, with the number of unread messages, when someone writes. Click
it (or **C**) to bring the chat back. Hidden or shown is remembered.

Hover one of your own messages for **edit** and **delete**. Edit puts its text back in the box
(Send saves it, Esc drops it) and marks it *(edited)* for everyone; delete asks once more and
leaves *message deleted* in its place. Only the person who sent a message can change it, and only
from the same connection: after you rejoin, the messages from before are no longer yours to edit.
A teammate whose app predates this keeps seeing the first text.

You are in the lounge too, as your own character, next to your teammates (two teammates in the
room is three people in your lounge). Click a piece of the lounge (the coffee machine, the
kitchen table, the high table, the sofa) and your character walks there and stays, in your
office and in everyone else's; click it again, or click your character, and it goes back to its
own routine.

Click a teammate for a menu: **Hug**, **Kiss**, **High five**, **Pillow fight**, **Bring a coffee**,
**Wave**, **Poke**, or **Chat**. Your character walks over and the two of you do it, in every lounge in the
room, and the log says so ("Alex hugged Jordan"). The lounge counts everyone in it, you included.

On the lounge's right side, a panel lists everyone in the room, you first. Click a name for the
same menu, or **👉 Poke** next to it: the person you poke gets a notification on their Mac and
their Agent Office window gives a little shake (with the window minimised, its Dock icon
bounces). You can poke the same person once every 20 seconds, and a person sees at most one poke
notification from the same teammate in 20 seconds. macOS asks once whether Agent Office may show
notifications. A teammate on an older version than this one does not get pokes. Without a room,
the panel has **Create a room** and **Join a room** buttons; **⋯** next to the room's name joins
another room, creates one, or leaves this one. The same three are in the **Room** menu. (In a
narrow window the panel is left out: use the Room menu.)

Only the people are shared. Your agents stay yours: your desks, your review room, your manager's
room, and your agents on a break in the lounge are drawn from your own sessions and are never
sent anywhere, so each person sees their own agents next to the shared teammates. Only you see
yourself in the manager's chair.

#### Create a room (one person, the host)

1. Pick who hosts: a Mac on the office network that usually has Agent Office open. The room
   exists only while that app is open.
2. Set your name and picture with **✎ edit**: that is your character in the room.
3. Click **Create a room** in the lounge's panel (or Room → Create a Room…), type a name and a
   password of at least 8 characters, and click **Create**. The app saves them in
   `~/.config/agent-office/config.json` (readable only by you) and opens the room.
4. macOS asks whether Agent Office may accept incoming connections and find devices on the local
   network: allow both. The panel lists you, and says *you host it*.
5. Send the room to your team over a private channel: Room → Create a Room… (or Join a Room…)
   shows the current room's name, password and your Mac's address, and **Copy Room Info** copies
   them as three lines a teammate pastes with **Paste Room Info**.
6. Tick Settings → **Open at login**, so the room comes back by itself after you restart your Mac.

The room stays saved: every launch hosts it again, with the same password, until you create or
join another one or use Settings → **Delete Saved Room…**. Room → **Leave the Room** only pauses it.

<details><summary>By hand, without the app's dialog</summary>

1. Pick who hosts: a Mac that is on the office network and usually has Agent Office open. The
   room exists only while that app is open.
2. Make sure the host has a `manager` name (and picture, if they like) in
   `~/.config/agent-office/config.json`: that is their character in the room.
3. Add the room to the same file, with a long random password. This prints the password once,
   to pass on to the team (`team-lounge` is your room's name, pick any):

   ```bash
   cd ~/.config/agent-office && P=$(openssl rand -base64 18) && jq --arg p "$P" '.room = {name: "team-lounge", password: $p, host: true}' config.json > config.json.new && mv config.json.new config.json && echo "room password: $P"
   ```

4. Restart Agent Office. macOS asks whether it may accept incoming connections and find devices
   on the local network: allow both. The **Chat** button appears; it says *you host it*.
5. Send the room name and password to your team over a private channel.
6. Tick Settings → **Open at login**, so the room comes back by itself after you restart your Mac.
   The room's name and password stay in your config: closing and reopening the app hosts the same
   room, and your team's password keeps working.

</details>

#### Join a room (everyone else)

1. Install Agent Office, or update it (Agent Office → **Check for Updates…** → **Update Now**).
2. Set your name and picture with **✎ edit** (or Agent Office → Your Name and Picture…).
3. Click **Join a room** in the lounge's panel (or Room → Join a Room…). Copy the room info the
   host sent you and click **Paste Room Info**, or type the room's name and password; then click
   **Join**. Leave the host address empty unless the room is not found by name (see below).
   The lines it reads look like this (the host's **Copy Room Info** writes them):

   ```
   AGENT_OFFICE_ROOM_NAME=team lounge
   AGENT_OFFICE_ROOM_PASSWORD=<the room's password>
   AGENT_OFFICE_ROOM_ADDRESS=their-mac.local
   ```
4. Allow Agent Office to find devices on the local network. Within a few seconds the host and
   everyone else walk into your lounge, and the panel lists them, each with a **👉 Poke** button.

Joined once, the room is saved and rejoined at every launch. Set up earlier with the env file?
The first launch of v0.5.1 or later moves those lines into `config.json` by itself, once; after
that the dialogs and Settings change them.

<details><summary>By hand, without the app's dialog</summary>

1. Install or update Agent Office (`git pull`, then `scripts/build-app.sh`).
2. Set your character: `manager.name` and `manager.image` in `~/.config/agent-office/config.json`
   (see *Configuration*).
3. Add the room to the same file, without `host` (`team-lounge` is the room's name):

   ```bash
   cd ~/.config/agent-office && jq --arg p '<the password>' '.room = {name: "team-lounge", password: $p}' config.json > config.json.new && mv config.json.new config.json
   ```

   (The `AGENT_OFFICE_ROOM_NAME` / `AGENT_OFFICE_ROOM_PASSWORD` lines in
   `~/.config/agent-office/env` still work, and win over `config.json`.)
4. Restart Agent Office and allow it to find devices on the local network.

</details>

Not in the office, or the host's app closed? Your office is simply local, and it looks for the
room again every 15 minutes (or click **Try now** in the panel).

**The chat says "the room is not on this network"?** Some networks hide devices from each other's
discovery (company Wi-Fi often does, and so does a VPN exit node, such as Tailscale's: turn on
**Allow Local Network Access** in its Exit Node menu, or turn the exit node off). Join by address
instead: the host's IP address (on the host: `ipconfig getifaddr en0`) or its `.local` name, in
the Join dialog's **Host address** field (by hand: `"address"` in the `room` block, or
`AGENT_OFFICE_ROOM_ADDRESS` in the env file).

The app still looks for the room by name first and tries the address after 3 seconds. The host
listens on port 48731 (`"port"` in the host's room block changes it; then add `:<port>` to the
address). An IP address can change when the host reconnects to the Wi-Fi; the `.local` name
does not, but it needs the same discovery some networks block. To check from a member's Mac
whether the host is reachable at all: `nc -vz <host address> 48731`.

To leave, untick Settings → **Join the shared room**.

#### Details

One Mac hosts the room (its Agent Office has to be open); everyone else needs only the room's
name and password. Set them in `~/.config/agent-office/config.json`:

```json
"manager": { "name": "Alex", "image": "~/agent-office/local/me.png" },
"room": { "name": "team-lounge", "password": "<long random password>", "host": true }
```

`host: true` on the host's Mac only. Or, on each member's Mac, in `~/.config/agent-office/env`
(an app opened from the Dock does not see your shell's exports; this file it reads):

```bash
AGENT_OFFICE_ROOM_NAME=team-lounge
AGENT_OFFICE_ROOM_PASSWORD=<the room's password>
```

- **Your character** is your `manager` picture and name. Without a picture you get a drawn one.
- **Joining:** the app looks for the room by name on the local network (Bonjour) when it starts,
  and again every 15 minutes while it is not in (`"alwaysJoin": false` looks only once; **Try
  now** in the chat panel looks at once). When the room goes away while you are in it (the host
  updated or restarted its app, or its Mac), every member's app watches for the room to be
  announced again and joins within a second or two of the host coming back; it also looks again
  on its own, quickly at first (10 seconds, then gradually up to 5 minutes, for about 15 minutes),
  for a room joined by address on a network that hides announcements. Meanwhile the people panel
  keeps the people who were there, greyed with how long they have been away, until they are back
  (for up to 15 minutes; this also works on the host, across its own restart). If the room is not
  there, the office is simply local.
  The first time, macOS asks to let Agent Office find devices on the local network: allow it.
  On the host it also asks to accept incoming connections.
- **Turning it off:** Settings → **Join the shared room**, or `"enabled": false` in the `room`
  block (`AGENT_OFFICE_ROOM_ENABLED=0`).
- **What is shared:** your name, a small picture, your chat messages, and the mini-games' moves and
  scores (see *Mini-games*). Nothing about your
  sessions, folders or prompts. Messages are kept in each app's memory only, and are gone when
  it quits; someone who joins later does not see earlier ones.
- **Security:** the password never crosses the network. Each connection derives a key from it
  (HKDF-SHA256 over two fresh random values), proves it knows the password with that key, and
  encrypts everything after that with AES-GCM, so others on the same network cannot read the
  chat or join without it. Use a long random password: someone who records a join can try
  guesses against it offline. After three wrong passwords from one address the host ignores it
  for 10 minutes.

### Terminal (optional): a shell under the office

**View → Terminal** (⌃`) opens a terminal under the office; drag the divider to set its height,
and the app remembers it and whether the terminal was open. It runs your own login shell (the one
in your user account, as Terminal and iTerm start it), so your `.zshrc`, Oh My Zsh, prompt
themes and aliases load as usual. Hiding the terminal keeps the shell running; quitting the app
ends it. When the shell exits, Return starts a new one.

- It is drawn by [xterm.js](https://xtermjs.org) (`web/vendor/xterm/`, MIT), bundled with the app:
  nothing is fetched at run time.
- Font: MesloLGS NF when it is installed (the Nerd Font Powerlevel10k and similar prompts draw
  their icons with), else SF Mono or Menlo; 13 pt.
- Option types your keyboard layout's characters; it is not Meta.
- The shell inherits the app's background priority (`nice` 10), like everything the app starts:
  a long build in it yields to other work on a busy Mac.
- `TERM_PROGRAM` is `AgentOffice`, so clicking an agent that runs in this terminal does not bring
  a Terminal or iTerm tab to the front.
- macOS counts what you run here as Agent Office: the first `ls ~/Desktop` (or Documents,
  Downloads…) asks whether *Agent Office* may open that folder. Allow it once; with
  `scripts/signing-setup.sh` it stays allowed across updates.
- A paste into a program that is not reading its input (a dev server, `sleep`) waits until it reads,
  without holding up the app; beyond 1 MB the rest of it is dropped, as a terminal does.

## Settings

Agent Office → Settings… (⌘,):
- **Your name and picture**: **Change…** opens the same editor as **✎ edit** in the manager's room.
- **Saved room** and **Delete Saved Room…**: a room you create or join is saved in
  `~/.config/agent-office/config.json` and joined (or hosted) again at every launch, until you
  join or create another one, or delete it here. Room → Leave the Room only pauses it and keeps
  the name and password; Delete removes both.
- **Import from env file…**: for a setup made with `~/.config/agent-office/env`. It moves the
  `AGENT_OFFICE_ROOM_…` and `AGENT_OFFICE_MANAGER_…` lines into `config.json` (it lists them first,
  the password only as its length) and takes them out of the env file, keeping a copy in
  `env.bak`. The first launch of a version with this does it by itself, once, without asking:
  after that your own edits stand and the env file is not read for an import again. The button
  is for env lines you add later. The env file wins over `config.json`, so until those lines are
  imported, the Room menu and Delete Saved Room cannot change a room they set (the app says so
  when you try).
- **Check for updates once a day** (off by default): see *Updating* below.
- **Join the shared room** (on by default, does nothing until a room is configured).
- **Jukebox in the lounge** (on by default): off hides it and stops its helper.
- **Open at login** (off by default): starts Agent Office when you log in. Turn it on on the Mac
  that hosts a room, so the room is back after a restart. macOS may ask you to approve it in
  System Settings → General → Login Items.

The rest are off by default:
- **Keep on top**: float the window above other apps and across Spaces.
- **Play a sound**: "Glass" when an agent waits for your permission, "Pop" when one finishes.
- **Energy saver**: 2 redraws a second instead of 6, no walking or blinking.

The window remembers its size and position. **Check Setup…** in the same menu says whether the
hook is registered for every event and when a session last reported.

## Updating

By hand: `git pull && scripts/build-app.sh` in your checkout, then reopen the app.

**macOS asks for its permissions again after every update?** (Desktop folder, Accessibility,
Automation, Local Network.) macOS remembers a permission by the app's signature, and an ad-hoc
signature changes with every build. The app offers the fix itself: before an update it asks
**Keep Agent Office's permissions after updates?** (**Set Up**, **Not Now**, **Don't Ask Again**), and
Settings has **Keep permissions → Set Up…**. Or run it once in your checkout:

```bash
scripts/signing-setup.sh
```

It makes a certificate for signing this app, good for nothing else, keeps it in your login
keychain and trusts it for code signing (macOS asks for your password). From then on
`scripts/build-app.sh` and the in-app updater sign with it, every build is the same app to macOS,
and a permission you give once stays: you are asked one last time after the first signed build.
If a dialog asks whether codesign may use the key, choose **Always Allow**.
`scripts/signing-setup.sh --remove` takes it out again. (The Desktop folder is asked for when your
checkout lives there: the updater builds from it.)

Or let the app do it: tick Settings → **Check for updates once a day**, or use Agent Office →
**Check for Updates…** once (when it finds a newer release, **Update Now** in its alert does the
same as the button). It asks GitHub for the repository's latest release and compares it
with the release your app was built from; when there is a newer one, an **Update to vX** button
appears at the top right. Clicking it:

1. fetches the release into the checkout the app was built from and moves it there with
   `git merge --ff-only <tag>`, so it never overwrites anything: local commits or uncommitted
   changes in the way stop the update with the reason and the manual command;
2. runs `scripts/build-app.sh` into the folder the app is in;
3. reopens the new app.

The steps are logged to `~/Library/Logs/agent-office-update.log`. The hook runs from the checkout,
so it is updated in the same move. The companion mod is a plugin and updates through Claude Code.

## Configuration

Optional: `~/.config/agent-office/config.json`. Everything specific to your setup lives in this
file, not in the repository. Every key is optional.

```json
{ "officeState": "~/.local/state/agent-office",
  "manager": { "name": "Alex", "image": "~/agent-office/local/manager.png" },
  "room": { "name": "team-lounge", "password": "<password>", "host": false, "alwaysJoin": true,
            "address": "10.20.30.40" },
  "reviews": { "state": "~/.local/state/pr-watch", "log": "~/Library/Logs/pr-watch.log",
               "slots": 5, "overdueMinutes": 45, "bitbucketWorkspace": "<workspace>" },
  "sessionKinds": [
    { "startsWith": "You are running the automated PR review", "kind": "review",
      "repoAfter": "for the repo '", "title": "PR review: {repo}" },
    { "startsWith": "You maintain the list of known defects", "kind": "automation",
      "repoAfter": "for the repo '", "title": "clean-reports: {repo}" } ] }
```

- **`room`** shares your lounge with your team: see *Shared room* above.
- **`manager`** adds the manager's room; **✎ edit** writes it for you. `image` is any picture of you (PNG, JPEG, WebP…). A plain
  white or transparent background is cut away and the rest redrawn as pixel art, so a pixel-art
  avatar looks best. `name` goes on the desk's name plate. With a name and no image, a drawn
  manager sits there. `local/` in the repository is ignored by git: a good place to keep the
  picture. `AGENT_OFFICE_MANAGER_IMAGE` and `AGENT_OFFICE_MANAGER_NAME` override both keys, until
  **✎ edit** saves a new name and picture: that takes those two lines out of the env file.
- **`reviews`** feeds the review room from a PR reviewer that keeps:
  - `<state>/running/<repo>-<pr>`: one tab-separated line per review in progress (repo name, repo
    slug, PR number, commit, author, start time `HH:MM`, pid, title);
  - `<state>/queue`: one line per waiting PR (repo name, slug, number, commit, author,
    `auto`/`manual`, title);
  - a log whose lines look like `YYYY-MM-DD HH:MM:SS [pr-watch] <repo>#<pr>: …`. A line whose
    event is `posted comment`, `asked you on Slack`, `rejected on Slack` or starts with `FAILED`
    is a finished review and goes on the shelf. After the event, optional ` | key: value` fields
    say how it went: `result` and `cost` are shown on the shelf, any others in its tooltip.

    ```
    2026-11-18 11:03:55 [pr-watch] infra#230: posted comment | result: 2 Blocking, 1 Major | cost: $1.84
    2026-11-18 11:20:12 [pr-watch] web-app#126: posted comment | result: No blockers | cost: $0.62
    ```

  `slots` is the number of review desks. `overdueMinutes` (default 45, `0` turns it off) is how
  long a review may run before its desk is flagged.
  `bitbucketWorkspace` makes a review desk and a shelf entry link to the Bitbucket PR; the shelf
  only has the log's repo name, so it is used as the slug. Without a `reviews` block the review
  room stays empty.
- **`roomLabels`** renames the plaques on the walls: `others`, `review` and `lounge`, each a short
  line (24 characters at most, shown in capitals), e.g. `{ "others": "MAIN OFFICE" }`. A plaque
  stops before the room's first window or picture: a name too long for that wall space (in a narrow
  window, say) is shortened with "…". A room left out keeps its name.
- **`sessionKinds`** tells headless jobs apart from your own sessions by how their first prompt
  starts.
  - `kind` is `review` (drawn at a review desk) or `automation` (⚙ in the others room).
  - `repoAfter`, and `repoEnd` (default `'`), cut a repo name out of the prompt for `{repo}` in
    `title`.
  - Sessions that match no entry are your own, titled from the Claude app or their folder.

## How it works

```
Claude Code ──hook──▶ ~/.local/state/agent-office/sessions/<id>.json  ─┐
                       ~/.local/state/agent-office/events.log           ├─▶ Agent Office.app (reads every 2 s
PR reviewer ─────────▶ <reviews state>/running/*, queue, log file ─────┘    while its window is visible)
```

- **`hook/agent-office-hook.sh`** is a Claude Code hook.
  - It keeps one small JSON file per session: title, folder, state, subagents, model, effort, and
    the Claude process id.
  - It appends general events to a log.
  - It always exits 0, prints nothing, and on the frequent "tool finished" event returns after a
    single `grep`.
- **`app/AgentOffice.swift`** is the window: a WKWebView around `web/office.html`.
  - It drops a session whose Claude process is gone, so a crashed session never lingers.
  - Without a shared room there is no server and no port, and nothing runs while the window is
    closed.
- **`app/Room.swift`** is the shared room: the host (a WebSocket listener advertised with
  Bonjour) and the member connection, with the handshake and encryption described in its header.
- **`web/office.html`** is the office, drawn in code. Opened in a browser on its own, it shows demo
  data.

## Privacy and cost

- **What is recorded:** states only. No prompt text, tool names or arguments are recorded. The first
  prompt is read only to match `sessionKinds`, and the transcript only for the latest model and
  effort. Where a session runs (the app, its terminal device) is recorded so a click can open it.
  With the companion mod, each session's context use, cost, plan usage and subagent states too.
  Everything stays on your Mac, under `~/.local/state/agent-office/`. There are two exceptions. The
  optional shared room sends your name, picture and chat messages to the room. The jukebox reads
  covers from macOS's Now Playing, on your Mac; only when that is not available (no Xcode command
  line tools) does it ask Spotify's public oEmbed endpoint (`open.spotify.com/oembed`) for each new
  Spotify song's cover, by its track id. Spotify already knows what you play, and nothing about it
  is sent anywhere else.
- **CPU and memory:** the app runs at background priority and reads its state only while its window
  is visible. It redraws at most 6 times a second (none while hidden) and draws at most 30 sessions;
  walls, floors and furniture are painted once and cached. Measured on an M-series Mac with the
  window visible: about 4% of one core and about 55 MB of memory. The jukebox's helper adds about
  25 MB and wakes only when what is playing changes (and every 5 seconds to check).

## Uninstall

```bash
scripts/install-hook.sh --uninstall           # removes exactly the hook entries it added
claude plugin uninstall agent-office          # the companion mod, if you installed it
rm -rf ~/Applications/"Agent Office.app"
rm -rf ~/.local/state/agent-office            # session files and the event log
```

## Mini-games

The lounge's right-hand panel has three tabs: **Room** (the people), **Games** and **Scores**. **G**
(or Room → Mini-Games…) opens the games over the office; **Esc** goes back, and Esc again closes.

- **🏎 Race:** five top-down tracks (Oval, Hairpin, Snake, Chicane, Grand Loop), 1 to 10 laps.
  **↑/W** go, **↓/S** brake, **←→/AD** steer. On the asphalt you reach full speed; on the grass
  you slow right down until you are back on it; cars bump off each other. In a room, **Open the
  race to the room** makes a lobby: teammates see it (a toast in their game, a line in the log,
  **Join** in their Games tab) and join; you press **Start** when everyone is in, and every car
  starts the same countdown from its own spot on the grid. The leaderboard keeps the **best lap**
  on each track, so races of any length compare.
- **🎣 Fishing:** one pond for the whole room. Hold **Space** to charge a cast and let go to throw;
  when a fish swims by your bobber it may bite (**!**): press Space to hook it, then hold Space to
  reel and let go when the line's tension climbs into the red, or it snaps. Everyone sees the same
  fish and each other's lines on the dock; a fish someone hooks is theirs (when two try, the first
  to reach the pond's keeper gets it), and once caught it is gone for everyone. Eight kinds, up to a
  rare golden koi. Start a **2-minute round** alone or with the room: everyone's catch adds up live.
- **🪲 Bug Whack:** 45 seconds of bugs climbing out of the monitors: click them (golden ones are
  worth 5, every fifth hit in a row 1 more), but leave the green ones, they are features (−3). Play
  alone or **open a round for the room**: everyone who joins gets the same bugs at the same moment,
  the first click takes each one, and the scores show live.
- **🏓 Ping-pong:** first to 7, with **↑↓/WS** or the mouse. Play the computer, or **Challenge** a
  teammate from the Games tab; they get a toast and **Accept**. Wins against teammates count.
- **📅 Daily challenge:** today's track and today's fish, picked from the date, so the same for
  everyone in the room on the same day (in the same time zone), with their own boards (the best lap
  on today's track, the biggest of today's fish). The host keeps the last 7 days and takes a daily
  score only for its yesterday, today or tomorrow, so teammates in other time zones still count.
- **🏅 Achievements:** sixteen of them (finish on all five tracks, a 10-lap race, win against a
  teammate, a golden koi, 50 in a Bug Whack round, beat the computer…), kept on your Mac and listed
  in the games and the Scores tab. How many you have shows next to your name in the lounge, for your
  teammates too.
- **Leaderboard (Scores tab):** in a room it is the room's: the host keeps it in `leaderboard.json`
  in its config folder (`~/.config/agent-office`, or `~/.config/agent-office-dev` for the dev app),
  taking only scores within each board's bounds, a few a minute per person, and each name's best,
  top 10. Entries go by display name: the room trusts its members, so two people with the same name
  share a line. Without a room, your own bests on this Mac.
- **While you play,** an agent that starts waiting for you shows at the top of the game (click it
  to go to that session) and as a macOS notification.

How the shared games stay in step: a round's bugs and the pond's fish come from a random seed that
whoever opened it sends once, so every Mac shows the same ones without sending them; whoever opened
it is also the referee for who got a bug or hooked a fish first (in the pond, when its keeper
leaves, the next person keeps it, with the same fish).

What crosses the network for the games: your name and medal, which race, round, pond or match you
opened or joined, your car's position ten times a second while racing, the ball and paddles fifteen
times a second in ping-pong, your bobber's place while fishing, which bug or fish you went for,
finish times, catches and scores.

## Trying a change: the dev app

```bash
scripts/build-app.sh --dev        # builds ~/Applications/Agent Office Dev.app from this checkout
open ~/Applications/"Agent Office Dev.app"
```

It runs next to your installed Agent Office without touching it:
- **Its own app:** a separate bundle id (`local.agent-office.dev`), so its own settings and macOS
  permissions, and its own Dock icon (an orange stripe along the bottom).
- **Its own config:** `~/.config/agent-office-dev/`, so its own name, picture, room and scores.
- **No updater:** it never replaces itself.

It reads the same sessions, so your agents show up in it too. To try the shared room, mini-games
and chat with yourself, join your room from the dev app as a second person (Room → Join a Room…).
Both apps can even host: when the room's port is taken, the second one listens on any free port and
is found by name. Rebuild with the same command after each change. Remove it with
`rm -rf ~/Applications/"Agent Office Dev.app" ~/.config/agent-office-dev`.

## Debugging

- `"$HOME/Applications/Agent Office.app/Contents/MacOS/AgentOffice" --dump-snapshot` prints exactly
  what the window is given.
- `"$HOME/Applications/Agent Office.app/Contents/MacOS/AgentOffice" --check-room` prints the room
  settings the app sees (config.json, the env file and the environment together; the password
  only as its length) and whether it will join.
- `ls ~/.local/state/agent-office/sessions/` should hold one file per running session; if it is
  empty, check **Check Setup…** and that `jq` is installed (the hook needs it).
- Open `web/office.html` in a browser to see the demo.

## License

[MIT](LICENSE)
