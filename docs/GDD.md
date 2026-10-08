# Corruption — Game Design Document v2

Clean-slate rework, written 2026-10-08 from the interview in `docs/design/interview.md` (Q numbers below point there).
Everything under a heading is Austin's (2026-10-08) unless marked **Open** or **Proposal**. The April GDD
(`Corruption_GDD_v0.1.md`), `docs/systems/` and `docs/technical/mvp-roadmap.md` are reference only and are superseded
wherever they disagree with this file.

## 1. Pitch

A low-information RTS. Each player is a dark lord in a tower, at war over a land of good, but none of the genre's free
information exists: no top-down view of the truth, no micro, no instant pings. You don't control how your troops
maneuver, when they advance or retreat, or even learn whether they won until word reaches you. What you improve is not
mainly stronger troops but **better information and smarter troops**. Alongside it sits an imperfect ARPG: a possessed
Paladin you play in third person, as far as your corruption lets you. (Overview)

- 4 players, ~90-minute match. A slower setting (unit move speed + the good faction's growth timer) stretches it to
  4–5 hours. (Q31)
- MVP: everyone plays **Undead**. The game is asymmetric PvP; more factions come later, and factions differ in how they
  gain troops, which site types suit them, and whether they lean Avatar or boss. (Q5, Q7, Q27)
- Design principles: diegetic and low-information everywhere, few UI elements, most interaction through the advisor
  (Q8); play with RTS expectations while staying clear and precise (Q13, Q24, Q26); a game isn't over until it's done,
  so nobody is left waiting for the end (Q39).

## 2. The tower (first person)

You start in a **ruined tower** that becomes more whole with every corruption site you gain. (Q26, Q38)

| Station | What it does |
|---|---|
| **Advisor** | Hears couriers' reports, takes your orders, other dialogue. The main interface. (Q8) |
| **Map** | A huge stone floor, illustrated, an imprecise rendering of the terrain. (Q1, Q8) |
| **Palantir** | Live view of the Paladin; possessing and controlling him. (Overview, Q19) |
| **Magic mirror** | Live calls and recorded messages to rivals. (Q33, Q34) |
| **Balcony** | Mostly flavour: nearby territory, the day/night cycle, beacons in the sky when sites change hands. (Q8, Q26) |
| **Summoning circle** | Raises human remains into undead. (Q6, Q8) |
| **Desk with books** | Records (leaders' maneuvers, relics held, what's been learned) and your own free notes. (Q37) |
| **Treasure room** | Physically shows the gold and special artifacts held at the tower; a **ledger** there holds the latest reports on goods held elsewhere. (Q24) |

## 3. The map and orders

- **The map is a sketch.** Illustrated features (rivers, cliff faces, towns, mountains) and a discrete set of
  selectable points. Many points, including far ones, are known at the start; others are missing and get filled in
  from what couriers bring home. (Q1, Q3)
- **Chess-piece markers** stand for unit groups. You can move them freely to guess or plan; asking the advisor resets
  them to the latest reports. (Q9, Q10)
- **Making an order:** select one or more pieces → walk a path across the floor → select a destination and confirm →
  a scroll of orders appears in your hand → give it to the advisor, who asks what the orders are → the advisor
  dispatches the orders and couriers needed. The order's path darkens on the map in ink. (Q2, Q9)
- **An order is a route and a goal.** Starting goals: "go here" and "assess location state and return". Location types
  add goals (a corruption site adds "corrupt site"). "Take it" means fight and stay whatever happens; "assess" includes
  coming back. (Q1, Q9)
- How granular your orders can get is an upgrade axis. (Q2)

## 4. Couriers and information

- Couriers carry all information, including orders. Troops can't be recalled without one. Couriers can be ordered to
  "go and come back" from the start. (Q2)
- Couriers are scarce at the start and can be killed or captured. A courier sent far and returned safely brings back a
  lot. (Q3)
- Reading a rival's captured couriers is an unlocked ability; otherwise a captured courier is simply lost. (Q4)
- Undead couriers are trained from regular units; training takes time and needs an existing courier. (Q5)
- Example of intended play (Q2): an army sent to the near site never arrives; a courier finds it stuck at a river; a
  second courier finds a ford; a third carries a new path across it; the army is ambushed in the woods; two couriers
  are needed to learn that, because the first dies; the player switches to the longer, safer road and takes a site;
  that pays for troops that auto-send a courier home when attacked.

## 5. Troops and the field

- **All units exist in the real 3D world** the Paladin walks; fights play out there. (Q32)
- **Undead troops** are raised from killed humans; bodies must be brought to the tower (or, after an upgrade, to a
  corruption site). (Q5, Q6)
- **Humans are handled one by one:** killed and raised; dominated into a thrall by bringing a *live* human to a
  corrupted chapel (capture and transport them without killing them); or, for nobles only (one or a few per
  settlement), bought with goods plus a promise, such as sparing their settlement or assassinating a rival. Each route
  has its own trade-offs. (Q23, Q26)

### Getting better

No tech tree you buy. Three parallel paths (Q35):
- **Training.** Group leaders gain experience and learn more complex maneuvers. They can teach them to others, at the
  cost of being out of the field while teaching. When a leader dies, someone steps up and remembers some of the
  maneuvers but loses others. (Q36)
- **Relics** retrieved from locations (corruption sites or not), such as signal flares that anyone can see.
- **Paid gear:** possibly, goods paid to humans for things like better armour.

## 6. Goods (wealth)

Wealth is material, never a number in the corner. (Q24, Q25)
- Resource locations produce only while an intelligent overseer works them (a human or a minion).
- Goods pile up where they're produced. They must be **hauled** by order to be used, and hauls can be ambushed or
  stolen.
- **Spending is physical:** paying a noble means sending them the goods.
- What you know: the treasure room shows the tower's holdings exactly; the ledger holds the latest reports for
  everywhere else.

## 7. Corruption sites

- **Corruption is not a resource.** Each type of corruption site grants one discrete capability you have to use in the
  world. Site types may differ by faction later, and the map is built with paths of play in mind. (Q26)
- Examples Austin has given: the **corrupted chapel** dominates live humans into thralls; some sites strengthen your
  control of the Avatar; some strengthen your boss form. (Q26, Q27)
- **Taking a site:** gather enough of your forces there to meet a minimum strength, then wait; more forces go faster.
  Small sites are easier than large ones. The Avatar corrupts sites much faster than troops. (Overview, Q11)
- **Losing a site:** rivals corrupt it over; the good faction retakes or purifies it, especially if unguarded; or it
  slips back unless some of your forces stay to hold it. (Q12)
- **You feel it.** Your tower becomes more whole and your character stronger as you gain sites. A beacon in the sky,
  seen from the balcony, marks a site taken for the first time, changing hands, or returning to neutral. (Q26)
- **Your tower is a corruption site that is permanently yours.** It can be sacked but always comes back, and it spawns
  units in a way that discourages rivals from killing you and hanging around. (Q39)

## 8. The Paladin (the Avatar)

The good faction's chosen Paladin. What makes him a powerful tool of good makes him a powerful tool of evil.
(Overview)

- **Taking him:** overpower his current controller with raw corruption (hard); or, the easier way, find him, beat him
  and his company with troops, and turn him like a site. When he's low on health anyone can begin a takeover. (Q14)
- **Keeping him:** your hold fades over time, unless he's kept near a source of corruption, which holds him
  indefinitely. At zero HP his corruption is wiped and the controller loses him. (Q15)
- **Unclaimed:** when he's weak, the good faction tries to recover him; at full strength he leads armies out to hunt
  and remove corruption. (Q16)
- **Controlling him:** you can leave the Palantir for the tower and come back freely. Left alone, he follows orders,
  moves with armies and has his own map piece; he's strongest when driven directly, because you can micro his movement
  and combat. (Q17)
- **Imperfect ARPG:** more corruption gives more control. Some actions are locked at first (at the start, maybe only
  walking), and the ones you have can meet resistance; for example, he resists attacking the good faction's priests
  and soldiers until you're stronger. (Overview, Q18)
- **Seen by all:** through any Palantir, every player sees and hears him live, and the viewers hear each other. Each
  viewer appears as a ghostly orb orbiting him where their camera is. This can give away your troops and strategy.
  He also lets his controller "see" the field. (Overview, Q19)

## 9. Winning, losing, drawing

- **Win:** control the Paladin and bring him into the holy site at the center of the city. That starts a **boss
  gauntlet**: each other player plays a boss form, weakest first. Boss strength comes from the corruption sites they
  hold (boss-type sites especially). Beat every boss and you corrupt the site and win. (Overview, Q20, Q27, Q28)
- **Comeback:** a boss who beats the Paladin takes control of him and the gauntlet ends. The winner uses the
  corruption to take him back to their own tower; to win they must bring him to the city center and start a fresh
  gauntlet. (Q20, Q21, Q22)
- **Building for it:** a player can lean on Avatar sites or boss sites. A strong boss collection makes you the wall
  nobody gets past, and the one who ends up holding the Paladin most. (Q27)
- **Draw:** the good faction slowly grows stronger. Flavour moments mark it, some corruption sites become permanently
  unusable, and site thresholds keep rising, until the city center can't be corrupted and the match ends in a draw.
  (Q29, Q30)

## 10. Diplomacy

The magic mirror (Q33, Q34): live calls and recorded messages. It captures audio and skeleton movement and animates a
"clone" of you on the other side. A call rings the rival's mirror; if nobody answers, it becomes a recorded message.

## 11. Open questions (for the next session, after playtesting)

- **Good faction, day to day:** patrols, purifying, how fast its threat grows, whether it attacks towers.
- **Day and night:** do they change anything beyond the balcony view?
- **Contested takeover** of the Paladin: Austin wants a rule for when several players try at once. (Q14)
- **Paladin control tiers:** which actions unlock, and which sites raise control.
- **Boss forms:** what each looks like and does; how sites feed them.
- **How the Paladin gets home** after a gauntlet comeback. (Q22)
- **Your tower's unit spawning:** what it spawns, and when. (Q39)
- **Content (Austin's to write):** site types and their capabilities, relics, maneuvers, the advisor, the map and its
  locations, unit types, boss forms.

## 12. Proposals not adopted

Claude's suggestions from the interview, recorded so they aren't mistaken for design:
- Site types: relay post, watch post, burial ground, crossing, scriptorium, Paladin anchor, market. (Q26)
- A courier "floor" so a beaten player always regains one courier; a sack that loots but never stops the tower rooms
  working. (Q39)
