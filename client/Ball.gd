extends Node2D

const DriftBall = preload("res://shared/drift_ball.gd")
const DriftConstants = preload("res://shared/drift_constants.gd")

## Simple soccer ball for FlyableMain single-player scene.
## Inertial movement with friction damping, wall bouncing.

@export_range(0.0, 1.0, 0.01) var wall_restitution: float = 0.8  # Bounce damping on walls

var velocity: Vector2 = Vector2.ZERO

# Use shared ball constants
var _radius: float = DriftBall.BALL_RADIUS
var _friction: float = DriftBall.BALL_FRICTION
var _max_speed: float = DriftBall.BALL_MAX_SPEED


func _ready() -> void:
	# Start at a position away from origin
	global_position = Vector2(512, 384)
	# Give it some initial velocity for testing
	velocity = Vector2(200, 150)
	queue_redraw()


func _physics_process(delta: float) -> void:
	# Apply friction (exponential decay per frame)
	velocity *= _friction
	
	# Clamp max speed
	var speed := velocity.length()
	if speed > _max_speed:
		velocity = velocity.normalized() * _max_speed
	
	# Integrate position
	global_position += velocity * delta
	
	# Wall bounce (same logic as PlayerShip)
	var old_pos := global_position
	global_position.x = clampf(global_position.x, DriftConstants.ARENA_MIN.x, DriftConstants.ARENA_MAX.x)
	global_position.y = clampf(global_position.y, DriftConstants.ARENA_MIN.y, DriftConstants.ARENA_MAX.y)
	
	var collision_normal := Vector2.ZERO
	var did_collide := false
	
	if global_position.x != old_pos.x:
		did_collide = true
		if global_position.x <= DriftConstants.ARENA_MIN.x:
			collision_normal = Vector2.RIGHT
		else:
			collision_normal = Vector2.LEFT
	
	if global_position.y != old_pos.y:
		if did_collide:
			if global_position.y <= DriftConstants.ARENA_MIN.y:
				collision_normal += Vector2.DOWN
			else:
				collision_normal += Vector2.UP
			collision_normal = collision_normal.normalized()
		else:
			did_collide = true
			if global_position.y <= DriftConstants.ARENA_MIN.y:
				collision_normal = Vector2.DOWN
			else:
				collision_normal = Vector2.UP
	
	if did_collide:
		velocity = velocity.bounce(collision_normal)
		velocity *= wall_restitution
		global_position += collision_normal * 1.0
	
	queue_redraw()


func _draw() -> void:
	# Draw filled circle (classic soccer ball black/white pattern would go here later)
	var ball_color := Color(1.0, 1.0, 1.0, 1.0)
	var outline_color := Color(0.0, 0.0, 0.0, 1.0)
	
	draw_circle(Vector2.ZERO, _radius, ball_color)
	draw_arc(Vector2.ZERO, _radius, 0, TAU, 32, outline_color, 1.5)
