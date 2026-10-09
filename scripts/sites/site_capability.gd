class_name SiteCapability

## The discrete capability each corruption site type grants its holder
## (GDD §7: "Corruption is not a resource. Each type of corruption site grants
## one discrete capability you have to use in the world").
##
## Settled by Austin (2026-10-08, Q26/Q27): the corrupted chapel dominates live
## humans into thralls; some sites strengthen your control of the Avatar; some
## strengthen your boss form. Your tower is a site that is permanently yours.
## Further capabilities are his to design (GDD §11).

const NONE: StringName = &""
## Corrupted chapel: bring a live human here to dominate them into a thrall.
const DOMINATE_THRALLS: StringName = &"dominate_thralls"
## Strengthens your control of the Paladin (stacks per site held).
const AVATAR_CONTROL: StringName = &"avatar_control"
## Strengthens your boss form in the gauntlet (stacks per site held).
const BOSS_POWER: StringName = &"boss_power"
## Your tower: raising the dead, the advisor, couriers.
const TOWER: StringName = &"tower"
## The holy site at the centre of the city (the win condition, GDD §9).
const HOLY_SITE: StringName = &"holy_site"
