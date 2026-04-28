# Overlord Held Items

**Build status:** Not started — design stub.

---

## Overview

Overlords in the tower can **hold a physical item in their hands**. Held items are the diegetic carrier for information and intent that passes between tower stations, minions, and other overlords. Rather than UI popups and abstract "you have a plan queued," the plan is a rolled piece of paper you're literally carrying. Rather than a dialog tree for diplomacy, you carry a sealed letter you hand to a Mirror or an Advisor.

This system is **broader than the War Table** — the War Table is one producer of held items (plan-paper), and the Advisor / Mirror / balcony are consumers. Other systems will plug in later.

```
┌───────── PRODUCER ─────────┐     ┌── HELD SLOT ──┐    ┌──────── CONSUMER ────────┐
│                             │     │                │    │                          │
│  War Table (plan-paper)     │     │                │    │  Advisor (read & enact)  │
│  Mirror (sealed message)    │ ──▶ │  One item at   │ ─▶ │  Mirror (deliver)        │
│  Summoning Circle? (token)  │     │  a time (?)    │    │  Balcony (shout aloud)   │
│  Ritual site? (reagent)     │     │                │    │  Another overlord (?)    │
│                             │     │                │    │                          │
└─────────────────────────────┘     └────────────────┘    └──────────────────────────┘
```

---

## Design goals

- **Diegetic, not UI.** The item exists in world space in the overlord's hands. You can see other overlords' held items at a glance when you watch them through a Mirror or from another tower.
- **One-at-a-time friction.** Holding an item is a commitment — you can't have a plan-paper, a sealed letter, and a ritual reagent simultaneously. Picking up a new item either drops or replaces the current one (TBD).
- **Interruptible.** Holding an item does not pause the game. You can be interrupted mid-walk-to-Advisor by a Mirror message, a Palantir alert, etc.
- **Stealable / droppable (later).** Eventually a held item should be a physical object an enemy or compromised Advisor can take or read. Out of scope for first build.

---

## Item taxonomy (initial)

| Item | Produced by | Consumed by | Payload |
|---|---|---|---|
| Plan-paper | War Table confirm | Advisor (queues as Commands), Balcony (shout to in-range minions) | Up to 5 movement commands + delivery modes |
| Sealed message | Mirror record | Mirror deliver (send to rival) | Recorded video + audio |
| *(future)* Ritual reagent | Ritual Site gather | Ritual Site cast | Per-faction buff input |
| *(future)* Summoning token | Summoning Circle | Summoning Circle spawn | Minion type + count |

Per-faction **flavor variants** of plan-paper (non-mechanical):
- **Undeath** — bone scroll
- **Demonic** — brand-seared hide
- **Fey** — leaf-bound weave
- **Eldritch** — stone tablet etched with sigils

---

## Interaction model (proposed)

- **Pick up**: interacting with a producer station that's ready to emit an item places it in the held slot. If the slot is occupied, the existing item is either returned to the producer, dropped to the floor, or replaced (TBD).
- **Carry**: the item is visible in the overlord's third-person/Palantir silhouette and in their first-person view.
- **Hand off**: interacting with a consumer (Advisor, Mirror, rival overlord) while holding the item transfers the payload and clears the slot.
- **Read**: the overlord can re-read their own item at any time (e.g. to review their plan before handing it to the Advisor).
- **Drop**: explicit drop action places the item in world space. Whether dropped items persist, decay, or can be picked up by other actors is TBD.

---

## Open questions

- One slot or a small inventory (2–3)? One slot maximizes friction and legibility; a small inventory lets overlords carry a plan *and* a sealed letter without juggling.
- Can another overlord or a compromised Advisor **read** your held item without you knowing? (Falsification hook.)
- Do held items survive Avatar transfer? If an overlord becomes the Avatar mid-plan, what happens to the paper in their old tower?
- Do minions (e.g. the Advisor, or an enemy's infiltrator) have their own held-item slot, or is this overlord-only?
- Does the balcony-shouting interaction *consume* the paper or leave it held so it can also be handed to the Advisor?

---

## Dependencies

- **Avatar/Overlord third-person rig** needs a hand attachment bone/socket for the item mesh.
- **Interaction system** needs to distinguish "interact with station" from "hand item to entity."
- **Networking:** held-item state must sync — other players see what you're carrying. Authority lives with the owning overlord's peer, with host validation on transfers.

---

## Consumers currently blocked on this system

- **War Table → Advisor handoff** (see `war-table.md` Build order step 10). Plan-paper is the first held item.
- **Mirror → Mirror** diplomacy delivery (currently abstract; would become a sealed-message item).
