# GDD v2 interview log

Clean-slate rework (Austin, 2026-10-08). The April GDD (`docs/Corruption_GDD_v0.1.md`) and the 2026-06-10 calls in
`docs/technical/mvp-roadmap.md` are reference only. Only what Austin says here is settled; the GDD is written from this log.

## 2026-10-08 — Austin's overview

> The primary idea is a low information rts. In traditional rts, you get a top down view with full visibility and micro
> manageable units, buildings, and a camera and ping system that works instantly. What I want to do is build a very basic
> rts where those assumptions for the genre are taken away. You exist as a dark lord in a tower and you know you are at
> war, you have objectives, enemies, outposts, armies, etc, but you DONT have free information. You cant control how well
> your units maneuver on the field, when they decide to retreat or advance, you won't even learn when they win or lost
> until the information makes its way to you. In this way, the upgrades and improvements you use resources for are not
> necessarily for stronger troops and armor, but rather to try to get closer to perfect information and smarter combat
> tactics for your troops. For the objectives, a player wants to control sites of corruption, which give them a usable
> resource to increase their influence on the world. The eventual goal is to control the central city's holy site.
> Controlling corrupting sites require collecting corrupting forces at that site, and waiting. This is easier for smaller
> sites and harder for larger sites. One of the easiest ways to gain corrupted sites is to use the Corrupted Avatar. In
> the theme of the game, each player is a corrupting force on the lands of good. The human population of the world is a
> neutral faction that needs to be destroyed, bought, or turned depending on strategy by the player. Among the good
> neutral faction is a chosen Paladin of the gods. The same thing that makes him a powerful tool of good makes him a
> powerful tool of evil, and corruption can be used to possess him and control him in third person, for a time. Similar
> to the main game being an imperfect rts, this is an imperfect arpg. More powerful corruption gives you more control over
> the avatar. At first you may only be able to get him to walk where you want him to walk. He corrupts sites much faster
> than normal troops, and also gives the player the ability to "see" what is on the field via the Orb used to control
> him. The downside is that all players have visibility of the avatar, and may be able to use that info to figure out
> your troop placement and strategy. To win the game, a player needs control of the avatar, and to get into the holy site
> in the map center. This triggers a boss run where they have to "purge" corrupting influences from the other players.
> Each other player gets to play as a "boss" form with power and abilities relative to their corruption level, and a
> player that successfully beats all players corrupts the site and wins the game.

## Questions and answers

**Q1. When you give an army an order from the tower, what are you telling it?**
Austin, 2026-10-08:
> I think I want the map to be imprecise as well. it is a rough estimation of the terrain, with classic illustrated
> features showing things like rivers, cliff faces, and towns, mountains, etc. so there are a discreet number of
> selectable points to send troops to. A troop order is both a route and a goal. where they are going, and what they are
> doing there. so "go to site, try to take it" means they will fight and stay there regardless of if they win "go to
> site to assess threat level" includes going and coming back as part of the goal

**Q2. How much of the route do you choose?**
Austin, 2026-10-08:
> the ability to get granular with troop orders on the map is one of the upgrade axes. Start with couriers that can
> "run" information including orders. Troops can be told to go somewhere, but can't be recalled without a courier.
> Couriers themselves can be given orders that include a "go and come back" from the beginning. Sending orders includes a
> "path" for the orders, which is a cool visual effect of ink darkening on the map in a line. Here is an illustrative
> example of what I want the player to discover in play:
> Start of game, a player sees their tools, their objectives. They see that there are two corruption sites, one closer
> than the other, but that is across a river and forest, whereas the other is a straight shot south along a road and then
> out into stepplands. they choose to send troops to the closer site, but never see their corruption increase. they send
> a courier to find out what happened, the courier gets to the river and finds the whole army standing around, confused.
> The player then has to send a courier to find a ford in the river, and then send a courier to give the army orders
> that include a path across the ford. Then, in the woods, the army is attacked by monsters, maybe the minions of another
> player, and those that get to the holy site are not enough to corrupt it, and the player sends two couriers to get
> this information, because the first courier also gets attacked and killed. The player then decides to go the longer
> route to the safer site, and manages to corrupt it unaccosted. then, with the added corruption, they are able to gain
> an upgrade to their troops that will automatically send a courier back to the base if the company is attacked, so that
> in the future they won't loose resources and time for such mistakes.

**Q3. Does your map change as you learn things?**
Austin, 2026-10-08:
> yeah I think of the fixed points on the map, not all are available from the jump.. it fills in with info from couriers
> but lots are there already, including far off ones. for instance a player could send a courier across the map right
> away if they wanted to, and they would be richly rewarded for a bunch of information if they return safely, but it is
> risky because they have limited couriers at the start of the game and any number of issues could cause the courier to
> be killed or captured

**Q4. What does capturing a courier mean for the captor?**
Austin, 2026-10-08:
> players can get access to abilities that allow them to get information from other players' couriers, but this is an
> unlocked ability

**Q5. How do you get more troops and couriers?**
Austin, 2026-10-08:
> this is different for every faction, but for the starting undead faction, they can be raised from killed humans, and
> regular units can be trained as couriers but this takes time, and requires the use of a courier to do the training

**Q6. Where does raising the dead happen?**
Austin, 2026-10-08:
> b, have to be brought to the tower. can also be done at corruption sites after an upgrade

**Q7. What does "starting faction" mean for the first playable version?**
Austin, 2026-10-08:
> Yes, for the MVP I want everyone to be undead, but want this to be an asym PvP and will add more factions later

**Q8. How do you play in the tower?**
Austin, 2026-10-08:
> it is first person perspective, you are in the tower and have a few tools at your disposal. you have an advisor who is
> how you hear information from couriers, how you give orders, and other dialog. there is a magic mirror for sending
> messages to other players. a Palantir orb for spying on the Avatar, a balcony for surveying the nearby territory
> (mostly useless and just for flavor, but useful for things like seeing beams of light when sites are corrupted or
> keeping track of the day/night cycle. Then there is the map, which is a huge sprawling stone floor so that players can
> give relatively granular commands, and get a sense of scale. Then there is a summoning circle for turning human
> remains, and a desk with books where the player devises their plans and tech tree. There are very few UI elements and
> interactions in the game. everything is meant to be diagetic and low info. mostly interactions with the advisor.

**Q9. How does an order get made?**
Austin, 2026-10-08:
> First select one or more chess piece style markers representing units, then draw a path by walking across the map.
> Then select a location and confirm. This puts a scroll of orders in the players hand. Give it to the advisor and they
> will ask what the orders should be, starting options are "go here" and "assess location state and return" different
> types of selected locations include other options. Corruption sites include "corrupt site" option. After choosing,
> advisor dispenses orders and couriers as necessary

**Q10. What does a chess piece's position on the floor show?**
Austin, 2026-10-08:
> You can move as a way to make guesses or visually plan but you can ask advisor to update to latest info

**Q11. How does taking a corruption site work? (threshold / rate / both)**
Austin, 2026-10-08:
> Both
(A minimum strength of your forces present to start corrupting; more forces after that go faster.)

**Q12. Once you hold a site, how can you lose it? (rivals / the humans / upkeep)**
Austin, 2026-10-08:
> All three
(Rivals can corrupt it over to them; the good faction can retake or purify it, especially if unguarded; it slips back
unless some of your forces stay to hold it.)

**Q13. Is corruption something you spend? (spent / a level / both)** — OPEN
Austin, 2026-10-08:
> I'm still thinking about this. A lot of what I'm trying to do with this project is play with expectations for the
> genre, and using a resource seems too flatly genre convention. But at the same time it's important to use players
> experience with other games to help them understand a game's systems.

**Q14. How does a player take control of the Paladin? (Palantir / earned in the field / contest)**
Austin, 2026-10-08:
> All of the above. You could raw overpower an avatar, even if currently controlled by another player, via corruption,
> but the easier way is to find the avatar, take him down, and turn him with troops the same way you do with holy
> sites. Requires having strong enough troops to fight him and his company if he has one. Any time the avatar gets low
> health, though, anyone can begin the takeover, and there should be a mechanic for contested takeover

**Q15. If nobody takes him, what ends your control of the Paladin?**
Austin, 2026-10-08:
> B a limit, but holding him near a source of corruption can keep him indefinitely, so others would have to find and
> attack to take him. Any time he is dropped to zero hp corruption is wiped and whoever currently has him loses control.

**Q16. When nobody controls him, what is the Paladin doing?**
Austin, 2026-10-08:
> The forces of good will try to recover him if they can when he is weak. If he has full strength, he will take armies
> out to hunt and remove corruption

**Q17. While you play the Paladin, what happens with your tower?**
Austin, 2026-10-08:
> B he can follow orders and move with armies and gets his own map token, but is most powerful being directly
> controlled as you can micro movements and combat in ways he can't alone.

**Q18. With little control of the Paladin, what does it feel like? (locked actions / he resists / both)**
Austin, 2026-10-08:
> Both. You may be able to attack but if you try attacking a priest or soldier of the good faction, he'll resist you
> until you have more corruption

**Q19. What can rivals see of the Paladin?**
Austin, 2026-10-08:
> Live view, using the palantir anyone can see and hear the avatar and each other. Viewers appear as ghostly orbs that
> orbit around the avatar reflecting where their "camera" is in real time

**Q20. How do the boss fights in the holy site run?**
Austin, 2026-10-08:
> A a gauntlet from least to most powerful in corruption. This is also a comeback mechanic because those least powerful
> have a chance to fight and take control of the avatar if they win

**Q21. When a rival's boss wins and takes the Paladin, what happens next?**
Austin, 2026-10-08:
> They take control and the boss gauntlet ends. Maybe they should also be able to "take" the avatar back to their base,
> since they'd have to presumably fight through enemy armies to get it of the city. Is they then want to try and win the
> game they would need to take the avatar to the city center and start a fresh boss run

**Q22. After winning the Paladin in the gauntlet, where is he?**
(Austin asked for reasoning; Claude recommended sending him home so the winner can't start a new run on the spot.)
Austin, 2026-10-08:
> Ok yeah let's say a boss form player somehow uses the corruption to take the avatar to their base.
(How he gets there is not yet described.)

**Q23. What do buying and turning humans look like in play?**
Austin, 2026-10-08:
> This is for individuals, so individual humans can be corrupted by being killed and raised as undead, or they can be
> asked to join with the player overlord's cause, and this takes resources like gold and a promise not to harm humans in
> that settlement or to assassinate a rival. Only nobles can be bought in this way. So only a few or one per settlement
> and there are advantages and diaanvantages to doing this over other methods of control

**Q24. Where does gold come from?** — Austin asked for a proposal
Austin, 2026-10-08:
> Again instead of gold and wealth being a number I want it to be diagetic and feel material. So maybe some of the
> locations on the board are resource locations that require human intelligent overseers to collect from, and instead of
> building up wealth and managing it directly we have to rely on human and minion advisors and agents to distribute and
> the player has low information. What do you think would be a good system that plays on rts expectations while still
> being fun and clear?
(Claude's proposal, not settled: 1 overseers work resource locations, goods pile up there; 2 goods must be hauled by
order, hauls can be ambushed; 3 tower treasure room physically shows what's held; 4 everything else is a stale report,
better ledgers are an upgrade; 5 spending is physical, e.g. goods sent to a noble.)
Austin, 2026-10-08:
> Partly, I like the idea of a treasure room, but this should include a ledger of most-up-to-date info on resources held
> at other sites, the treasure room only shows what gold or special artifacts are held at the base location.

**Q25. Hauling and physical spending: keep either?**
Austin, 2026-10-08:
> Yes to both
(Goods must be hauled by order to be used, and hauls can be ambushed; spending is physical, e.g. paying a noble means
sending the goods.)
