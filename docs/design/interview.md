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
