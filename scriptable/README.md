# Volumio home screen widget (Scriptable)

An iPhone/iPad home screen widget for Volumio, built with [Scriptable](https://scriptable.app). Nothing goes through the App Store: it's one JavaScript file you paste into Scriptable.

It shows the player name, cover art, title, artist, album and play state, with buttons for previous, play/pause, next, mute, volume − / +, and a 10-step volume bar where each step is tappable (10%, 20%, ... 100%). It works as a large (full-width) widget, and also has medium and small layouts.

## Setup

1. Install **Scriptable** from the App Store (free).
2. In Scriptable, tap **+**, paste the contents of [`Volumio.js`](Volumio.js), and rename the script to **Volumio** (tap the title at the top).
3. Near the top of the script, set `DEFAULT_HOST` to your player's IP address, for example `"192.168.1.40"`. The port defaults to 3000. `volumio.local` works too if your player uses that name.
4. Tap ▶︎ to try it. You should see a small remote with what's playing.
5. On the home screen, long-press, tap **Edit** › **Add Widget**, choose **Scriptable**, and pick the **large** size.
6. Long-press the new widget › **Edit Widget**:
   - **Script:** Volumio
   - **When Interacting:** Run Script
   - **Parameter:** leave empty, or enter an IP to show a different player in this widget.

## How it behaves

- **Refresh:** iOS decides when widgets update, usually every 5 to 15 minutes. The widget shows the time of its last update in the corner.
- **Buttons:** Scriptable widgets can't run code in place, so a tap opens Scriptable, sends the command, and shows the remote with the new state. Swipe home when you're done. If you'd rather not see the remote, set `SHOW_REMOTE_AFTER_TAP = false` (Scriptable still opens briefly).
- **Home network only:** it talks to Volumio's REST API on your LAN, so it shows "Can't reach ..." when you're away from home.
- If the player's mixer is set to "None" (`disableVolumeControl`), the volume controls are replaced by a note, the same as in the Mac app.

## Settings at the top of the script

| Setting | Default | What it does |
|---|---|---|
| `DEFAULT_HOST` | `volumio.local` | Player address, used when the widget has no parameter |
| `VOLUME_STEP` | `5` | How much − and + change the volume |
| `VOLUME_PRESETS` | `10 … 80` | Volume buttons in the in-app remote |
| `SHOW_REMOTE_AFTER_TAP` | `true` | Show the remote after a widget tap |
