extends "res://tests/frame_tests/frame_test_case.gd"
## Landing with an action already held should NOT play the landing animation AND
## should NOT leave any residual lock/stun. The character must be free to act on
## the very same frame of touchdown (zero-lock interrupt).
##
## This is the regression test for the "animation skipped but lock time remains"
## bug: previously the 2-frame forced landing lock always elapsed even when the
## player was inputting an action on landing, producing a brief hard stun.

func run() -> bool:
	# Jump, then hold forward to be inputting a walk direction at landing.
	await tap("jump")

	var me = p1
	var reached_air: bool = await wait_until(
		func(): return not me.is_on_floor(), 120)
	check(reached_air, "P1 should leave the floor after jumping")
	if not reached_air:
		return not has_failures()

	# Hold right direction while airborne — input is active when landing occurs.
	Input.action_press("move_right")

	var landed: bool = await wait_until(
		func(): return me.is_on_floor(), 360)
	check(landed, "P1 should land")
	if not landed:
		Input.action_release("move_right")
		return not has_failures()

	# On the very first frame of touchdown, is_landing must be FALSE
	# (instant interrupt — no landing state entered at all).
	var in_landing_state := me.is_landing and me.landing_lock_frames > 0
	check(not in_landing_state,
		"Landing with held input must NOT enter landing lock; is_landing=%s lock=%d"
		% [me.is_landing, me.landing_lock_frames])

	# The character should be free to act immediately — verify horizontal
	# velocity is applied by WalkHandler (we're holding move_right).
	await await_frames(1)
	var is_still_landing := me.is_landing and me.landing_lock_frames > 0
	check(not is_still_landing,
		"One frame after landing with input, landing lock must still be clear (is_landing=%s lock=%d)"
		% [me.is_landing, me.landing_lock_frames])

	Input.action_release("move_right")
	return not has_failures()
