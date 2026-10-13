# Pikmin AI research

Notes from reading the Pikmin 2 and Pikmin 1 decomps (`projectPiki/pikmin2`, `projectPiki/pikmin`; source only, cloned
at `workshop/pikmin-decomp/` on aruki-tek, 2026-10-13). Citations are paths inside that clone. No Pikmin code is copied here.

Each note's "What Corruption could take" section is a menu of options for Austin, not design. Nothing here is settled.
Constants are the decomp's header defaults; the shipped games may override them from data files that aren't in the repo.

- [pathfinding.md](pathfinding.md): route graph, budgeted A*, blocked-link flags, path following, stuck/re-plan, spatial queries.
- [pikmin-swarm.md](pikmin-swarm.md): troop side. Body FSM vs brain vs primitives, formation plate, whistle/dismiss,
  idle task pickup, group carry, latching attack, panic, per-frame budgeting.
- [enemy-ai.md](enemy-ai.md): enemy side. Lifecycle + behaviour FSMs, perception and leash radii, shake-off, off-screen
  freeze, route-walking enemies, boss phases, Pikmin 1's data-driven teki strategies.
