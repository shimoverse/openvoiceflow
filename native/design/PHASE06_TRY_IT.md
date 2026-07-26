# Trying the redesign on your own Mac

No Xcode knowledge needed. One command builds it and opens it.

```bash
git clone https://github.com/shimoverse/openvoiceflow.git ~/ovf-test \
  && cd ~/ovf-test \
  && git checkout claude/native-redesign-phase06 \
  && bash native/scripts/run-local.sh
```

If you already have the repo somewhere, skip the clone:

```bash
cd <your-checkout> && git fetch origin claude/native-redesign-phase06 \
  && git checkout claude/native-redesign-phase06 \
  && bash native/scripts/run-local.sh
```

The first build takes 5–10 minutes — it downloads the speech engine. After
that it's under a minute. The script checks what you're missing and tells you
how to get it rather than failing with a wall of red.

This is a **test build**, not the release. It installs nothing and touches
nothing you already have. To get rid of it: quit from the menu bar, then
`rm -rf ~/ovf-test`.

---

## What to look at, in the order you'll hit it

Nine things in this release can only be judged by eye. They're below in the
order they come up, phrased as what to look for rather than what to verify.

### 1. Does it look like it belongs on your Mac?

**If your Mac is in light mode, this is the single most important one.** The
old build forced a dark window regardless — a light-mode Mac got a dark panel
that matched nothing else on screen. Everything should now follow your Mac.

If you're normally in dark mode, it's worth switching to light for one launch:
 System Settings ▸ Appearance ▸ Light. Then quit and relaunch the app.

Look for: any panel, card, or patch of text that stayed dark, or grey text you
have to squint at.

### 2. The menu-bar waveform waves once

Right at the start, on the "I live up there" screen, the small waveform in your
menu bar should swell three times, then settle. It's answering "where did the
app go?" before you have to ask.

Look for: does your eye actually go up there? That's the whole point of it.

### 3. Granting a permission — the fiddly one

You'll get three permission rows, one at a time. The second only appears once
the first is granted.

**This is the bit worth being deliberate about.** When it asks for
Accessibility, macOS opens System Settings. Flip the switch there, then —
without clicking back on the onboarding window — look at the onboarding
window.

The dot should turn green on its own within about a second.

The old build only noticed when you clicked back into it, so it looked frozen
and people assumed the grant hadn't worked. If the dot sits grey until you
click the window, that's the bug back.

### 4. The download, and whether waiting is bearable

The speech model is about a gigabyte. While it downloads you should see real
numbers — "412 of 981 MB · 5.4 MB/s · 2 min left" — and be able to type your
name and your words *while it runs*.

Look for: does the "time left" jump around? It's meant to hold steady for a
second at a time. A number that flickers between 2 min and 5 min reads as
broken even when it's accurate.

### 5. Saying your sentence, and the words appearing as you talk

It'll show a grey suggested sentence. Say anything — your own words are fine,
it's not checking.

Look for: your words filling in over the grey as you speak, not appearing all
at once at the end.

### 6. The payoff screen

Your sentence, large, plus how long it took versus typing it.

Look for: is the sentence *yours*? The old build showed a hardcoded fake one,
which is the bug you originally caught.

### 7. The HUD changing shape — the hardest to describe

Now do a real dictation: hold **fn**, say something, let go.

A small capsule appears near the bottom of the screen. While you talk it's a
wave tracking your voice. When you stop it becomes a tighter coil, then a
checkmark.

**Look for: one line changing shape.** Not one drawing disappearing and
another appearing in its place. If it looks like a cut or a flicker between
two pictures rather than a shape bending into another shape, that's worth
telling me.

Also: the capsule should feel small — a status light, not a banner. It used to
be about 70% wider.

### 8. Reduce Motion — if anyone using this is motion-sensitive

System Settings ▸ Accessibility ▸ Display ▸ Reduce Motion, on.

Now dictate again. The wave should be replaced by **nine dots** that light up
with your voice. Nothing should slide, bounce, or grow. The menu-bar waveform
should not wave on launch either.

Skip this one if it doesn't matter to you — it's an accessibility check, not a
correctness check.

### 9. The dashboard

Click the menu-bar icon ▸ Dashboard (or the Dock icon).

Home should open with **one big number** — time you didn't spend typing —
then your first-ever dictation with its date and the app it landed in.

Look for: anything cut off or overlapping at the default window size. And if
you have a long first sentence, whether it collides with what's below it.

---

## If something's wrong

Tell me in plain words — "the thing in the corner flickers", "text is too
light to read", "it didn't notice when I flipped the switch". That's enough;
I don't need a bug report.

If the **build** fails, copy the lines that look like
`SomeFile.swift:123:4: error: ...` and paste them back. That's a compile
error, which is mine to fix and quick.

If the **hotkey stops working after a rebuild**, that's macOS, not us: it ties
permissions to the exact binary and a rebuild makes a new one. System Settings
▸ Privacy & Security ▸ Accessibility, remove OpenVoiceFlow with `−`, add it
back with `+`.
