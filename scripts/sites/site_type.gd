class_name SiteType extends Resource

## One kind of corruption site (GDD §7). Authored as .tres under res://data/sites/.
## Names, art and which types exist are Austin's to design; the shipped .tres
## files other than the corrupted chapel are placeholders (PLACEHOLDERS.md).

enum Size { SMALL, LARGE }

@export var id: StringName
@export var display_name: String
## What holding a site of this type gives its holder. See SiteCapability.
@export var capability: StringName = SiteCapability.NONE
## "Small sites are easier than large ones" (GDD §7). Sets the defaults below.
@export var size: Size = Size.SMALL

@export_group("Taking it")
## Minimum strength of your forces present before corruption starts (Q11). A
## troop counts its MinionType.strength; the Paladin counts much more.
@export var strength_threshold: float = 3.0
## Seconds to corrupt the site from neutral with exactly the threshold present.
## More strength goes proportionally faster.
@export var corrupt_seconds: float = 60.0

@export_group("Losing it")
## Seconds for an unguarded held site to slip back to neutral (Q12).
@export var slip_seconds: float = 180.0
## Seconds for the good faction to purify a site it stands in unopposed.
@export var purify_seconds: float = 45.0

@export_group("Presentation")
## Marker colour while neutral. PLACEHOLDER art.
@export var neutral_color: Color = Color(0.75, 0.75, 0.7)
