## Driftline shared soccer ball logic (pure logic, no Nodes)

class_name DriftBall

static var BALL_RADIUS := 6.0


static func step_ball(ball: DriftTypes.DriftBallState, delta: float, friction: float, max_speed: float) -> void:
	# Apply friction
	ball.velocity *= friction
	# Clamp max speed
	if ball.velocity.length() > max_speed:
		ball.velocity = ball.velocity.normalized() * max_speed
	# Integrate position
	ball.position += ball.velocity * delta
