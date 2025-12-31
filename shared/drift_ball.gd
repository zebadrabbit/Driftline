## Driftline shared soccer ball logic (pure logic, no Nodes)

class_name DriftBall

static var BALL_RADIUS := 6.0
static var BALL_FRICTION := 0.98
static var BALL_MAX_SPEED := 600.0
static var KICK_IMPULSE := 200.0


static func step_ball(ball: DriftTypes.DriftBallState, delta: float) -> void:
	# Apply friction
	ball.velocity *= BALL_FRICTION
	# Clamp max speed
	if ball.velocity.length() > BALL_MAX_SPEED:
		ball.velocity = ball.velocity.normalized() * BALL_MAX_SPEED
	# Integrate position
	ball.position += ball.velocity * delta
