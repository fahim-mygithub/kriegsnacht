extends RefCounted

## The one line-of-sight test.
##
## There are four callers that have to agree about what "can see" means: a zombie
## deciding whether to chase directly or follow the flow field, the Thundergun's
## wedge, an explosive's splash, and the interaction scan deciding whether a
## wall-buy is reachable. When they disagree, the disagreement is invisible until a
## player kills something through a wall — which is exactly what shipped, twice.
##
## So this is deliberately a shared file rather than a method on any of them, and it
## exists because two packages needed it in the same wave and neither should have
## written its own. Godot's own answer is already correct and cheap; the value here
## is that there is only one of it.
##
## Reached by `const LOS := preload("res://scripts/world/los.gd")` rather than by the
## `Los` class name, matching the convention the rest of this project uses: a freshly
## added script is not in the class registry until the editor rescans, and a headless
## run has no editor.

## Static world geometry. Enemies are on 4 and the player is on 2, and neither
## belongs in a visibility test — a zombie standing between you and a wall does not
## make the wall visible, and a body in the blast does not shield the one behind it
## (the ancestor's `explode` gates every target on its own ray, html:2589).
const MASK_WORLD := 1


## True when nothing solid stands between the two points.
##
## Takes Vector3s because the callers do not agree about height and must not have to.
## The AI test wants a body-height ray; the Thundergun and the interaction scan want
## the camera's actual origin, and pinning those to a fixed eye height would let a
## player shoot over a low wall they cannot see over, or fail to buy something they
## are looking straight at.
static func clear(world: World3D, a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = MASK_WORLD
	return world.direct_space_state.intersect_ray(q).is_empty()


## The grid-plane form: two tile positions, tested at a body height.
##
## This is the shape `Zombie._has_los` had, kept so the AI call site reads the way it
## did. The default is that function's own 1.2 m, which is a torso rather than an eye
## — right for "can this body see that body", wrong for anything originating at the
## camera, which is why it is a parameter and not a constant.
static func clear_flat(world: World3D, from: Vector2, to: Vector2, height := 1.2) -> bool:
	return clear(world, Vector3(from.x, height, from.y), Vector3(to.x, height, to.y))
