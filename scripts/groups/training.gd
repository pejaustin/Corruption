class_name Training

## Getting better without a bought tech tree (GDD §5, Q35/Q36): group leaders
## gain experience and learn maneuvers, teach them to other groups at the cost
## of time out of the field, and a successor keeps only some of them. Which
## maneuvers exist is Austin's (ticket #581); see data/maneuvers/.

## PLACEHOLDER: tuning, not designed — chance a successor remembers each
## maneuver, and the share of experience carried over.
const SUCCESSION_KEEP_CHANCE: float = 0.5
const SUCCESSION_KEEP_EXPERIENCE: float = 0.5
## PLACEHOLDER: tuning — experience a leader gains per enemy his group kills,
## and per second his group spends fighting.
const XP_PER_KILL: float = 1.0
const XP_PER_FIGHT_SECOND: float = 0.05
## PLACEHOLDER: tuning — seconds to train a regular unit as a courier (Q5).
const COURIER_TRAINING_SECONDS: float = 90.0
## PLACEHOLDER: tuning — seconds a leader spends teaching one maneuver.
const TEACHING_SECONDS: float = 120.0
