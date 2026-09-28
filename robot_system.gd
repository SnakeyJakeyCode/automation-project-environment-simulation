extends Node3D

signal status_changed(message: String)


# Rail positions for each station.
const LASER_X: float = -8.0
const BENDER_X: float = -3.0
const WELD_X: float = 2.0
const INSPECTION_X: float = 7.0
const OUTPUT_X: float = 10.0


# Robot joint poses. Angles are in degrees.
const POSE_HOME: Dictionary = {
	"base_y": 0.0,
	"shoulder_z": 0.0,
	"elbow_z": 0.0,
	"wrist_roll_y": 0.0,
	"wrist_pitch_z": 0.0,
	"tool_rotation_y": 0.0
}

const POSE_CARRY: Dictionary = {
	"base_y": 0.0,
	"shoulder_z": -15.0,
	"elbow_z": -30.0,
	"wrist_roll_y": 0.0,
	"wrist_pitch_z": -135.0,
	"tool_rotation_y": 0.0
}

const POSE_PICK: Dictionary = {
	"base_y": 90.0,
	"shoulder_z": -25.0,
	"elbow_z": -45.0,
	"wrist_roll_y": 0.0,
	"wrist_pitch_z": -110.0,
	"tool_rotation_y": 0.0
}


# Motion and presentation settings.
@export var rail_speed: float = 2.5
@export var joint_move_duration: float = 1.5
@export var suction_pause: float = 0.4
@export var heartbeat_flashes: int = 4
@export var heartbeat_interval: float = 0.25
@export var part_attach_offset_y: float = 0.05

# These switches represent the routing choices made by the CODESYS logic.
@export var part_id: int = 1
@export var use_bender: bool = true
@export var use_welder: bool = true
@export var use_inspection: bool = true


# Robot hierarchy.
@onready var carriage: Node3D = $Carriage
@onready var base_pivot: Node3D = $Carriage/RobotBase/BasePivot
@onready var shoulder_pivot: Node3D = $Carriage/RobotBase/BasePivot/ShoulderPivot
@onready var elbow_pivot: Node3D = $Carriage/RobotBase/BasePivot/ShoulderPivot/ElbowPivot
@onready var wrist_roll_pivot: Node3D = $Carriage/RobotBase/BasePivot/ShoulderPivot/ElbowPivot/WristRollPivot
@onready var wrist_pitch_pivot: Node3D = $Carriage/RobotBase/BasePivot/ShoulderPivot/ElbowPivot/WristRollPivot/WristPitchPivot
@onready var tool_rotation_pivot: Node3D = $Carriage/RobotBase/BasePivot/ShoulderPivot/ElbowPivot/WristRollPivot/WristPitchPivot/ToolRotationPivot
@onready var pickup_point: Marker3D = $Carriage/RobotBase/BasePivot/ShoulderPivot/ElbowPivot/WristRollPivot/WristPitchPivot/ToolRotationPivot/GripperPlate/PickupPoint

# Workpiece and process targets.
@onready var workpieces: Node3D = $"../WorkPieces"
@onready var part: Node3D = $"../WorkPieces/Part01"
@onready var laser_target: Marker3D = $"../ProcessTargets/LaserTarget"
@onready var bender_target: Marker3D = $"../ProcessTargets/BenderTarget"
@onready var weld_target: Marker3D = $"../ProcessTargets/WeldTarget"
@onready var inspection_target: Marker3D = $"../ProcessTargets/InspectionTarget"
@onready var output_target: Marker3D = $"../ProcessTargets/OutputTarget"

# Existing station heartbeat meshes.
@onready var laser_light: Node3D = $"../LaserCutter/HeartbeatLight"
@onready var bender_light: Node3D = $"../Bender/HeartbeatLight2"
@onready var weld_light: Node3D = $"../WeldCell/HeartbeatLight3"
@onready var inspection_light: Node3D = $"../Inspection/HeartbeatLight4"


var animation_running: bool = false


func _ready() -> void:
	reset_demo_state()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("run_demo") and not animation_running:
		run_factory_demo()


# Complete Cutter -> Bender -> Welder -> Inspection -> Output demonstration.
func run_factory_demo() -> void:
	animation_running = true
	reset_demo_state()

	await wait_seconds(0.5)

	set_status("Part %d: laser cutting" % part_id)
	await run_station_process("Laser cutter", laser_light)
	await pick_current_part()

	if use_bender:
		await visit_station(BENDER_X, bender_target, bender_light, "Bender")

	if use_welder:
		await visit_station(WELD_X, weld_target, weld_light, "Welder")

	if use_inspection:
		await visit_station(
			INSPECTION_X,
			inspection_target,
			inspection_light,
			"Inspection"
		)

	set_status("Moving part %d to output" % part_id)
	await move_carriage_to(OUTPUT_X)
	await place_part_at(output_target)
	await move_to_pose(POSE_HOME)

	set_all_lights(false)
	set_status("Part %d complete" % part_id)
	animation_running = false


# Visits one optional processing station and collects the part again afterward.
func visit_station(
	station_x: float,
	target: Marker3D,
	heartbeat_light: Node3D,
	station_name: String
) -> void:
	set_status("Moving part %d to %s" % [part_id, station_name])
	await move_carriage_to(station_x)
	await place_part_at(target)
	await run_station_process(station_name, heartbeat_light)
	await pick_current_part()


func pick_current_part() -> void:
	set_status("Robot collecting part %d" % part_id)
	await move_to_pose(POSE_PICK)
	await wait_seconds(suction_pause)
	attach_part_to_tool()
	await wait_seconds(suction_pause)
	await move_to_pose(POSE_CARRY)


func place_part_at(target: Marker3D) -> void:
	set_status("Robot placing part %d" % part_id)
	await move_to_pose(POSE_PICK)
	await wait_seconds(suction_pause)
	release_part_at(target)
	await wait_seconds(suction_pause)
	await move_to_pose(POSE_CARRY)


# Reparenting makes the workpiece follow the moving tool.
func attach_part_to_tool() -> void:
	if part.get_parent() != pickup_point:
		part.reparent(pickup_point, false)

	part.position = Vector3(0.0, part_attach_offset_y, 0.0)
	part.rotation_degrees = Vector3.ZERO


# The target marker provides the exact staged placement at each machine.
func release_part_at(target: Marker3D) -> void:
	if part.get_parent() != workpieces:
		part.reparent(workpieces, false)

	part.global_transform = target.global_transform


func move_carriage_to(target_x: float) -> void:
	if is_equal_approx(carriage.position.x, target_x):
		return

	var safe_speed: float = maxf(rail_speed, 0.01)
	var distance: float = absf(carriage.position.x - target_x)
	var duration: float = distance / safe_speed
	var tween: Tween = create_tween()

	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(carriage, "position:x", target_x, duration)

	await tween.finished


func move_to_pose(pose: Dictionary, duration: float = -1.0) -> void:
	var actual_duration: float = duration
	if actual_duration < 0.0:
		actual_duration = joint_move_duration

	await move_robot_to(
		float(pose["base_y"]),
		float(pose["shoulder_z"]),
		float(pose["elbow_z"]),
		float(pose["wrist_roll_y"]),
		float(pose["wrist_pitch_z"]),
		float(pose["tool_rotation_y"]),
		actual_duration
	)


func move_robot_to(
	base_y: float,
	shoulder_z: float,
	elbow_z: float,
	wrist_roll_y: float,
	wrist_pitch_z: float,
	tool_rotation_y: float,
	duration: float
) -> void:
	var tween: Tween = create_tween()

	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(base_pivot, "rotation_degrees:y", base_y, duration)
	tween.tween_property(shoulder_pivot, "rotation_degrees:z", shoulder_z, duration)
	tween.tween_property(elbow_pivot, "rotation_degrees:z", elbow_z, duration)
	tween.tween_property(wrist_roll_pivot, "rotation_degrees:y", wrist_roll_y, duration)
	tween.tween_property(wrist_pitch_pivot, "rotation_degrees:z", wrist_pitch_z, duration)
	tween.tween_property(tool_rotation_pivot, "rotation_degrees:y", tool_rotation_y, duration)

	await tween.finished


# Blinks the existing heartbeat mesh while a station is processing the part.
func run_station_process(station_name: String, heartbeat_light: Node3D) -> void:
	set_status("%s processing part %d" % [station_name, part_id])

	for _flash_index in range(heartbeat_flashes):
		heartbeat_light.visible = true
		await wait_seconds(heartbeat_interval)
		heartbeat_light.visible = false
		await wait_seconds(heartbeat_interval)


func reset_demo_state() -> void:
	if part.get_parent() != workpieces:
		part.reparent(workpieces, false)

	part.global_transform = laser_target.global_transform
	carriage.position.x = LASER_X
	apply_pose_immediately(POSE_HOME)
	set_all_lights(false)
	set_status("Part %d ready at laser cutter" % part_id)


func apply_pose_immediately(pose: Dictionary) -> void:
	base_pivot.rotation_degrees = Vector3(
		0.0,
		float(pose["base_y"]),
		0.0
	)
	shoulder_pivot.rotation_degrees = Vector3(
		0.0,
		0.0,
		float(pose["shoulder_z"])
	)
	elbow_pivot.rotation_degrees = Vector3(
		0.0,
		0.0,
		float(pose["elbow_z"])
	)
	wrist_roll_pivot.rotation_degrees = Vector3(
		0.0,
		float(pose["wrist_roll_y"]),
		0.0
	)
	wrist_pitch_pivot.rotation_degrees = Vector3(
		0.0,
		0.0,
		float(pose["wrist_pitch_z"])
	)
	tool_rotation_pivot.rotation_degrees = Vector3(
		0.0,
		float(pose["tool_rotation_y"]),
		0.0
	)


func set_all_lights(is_visible: bool) -> void:
	laser_light.visible = is_visible
	bender_light.visible = is_visible
	weld_light.visible = is_visible
	inspection_light.visible = is_visible


func set_status(message: String) -> void:
	print(message)
	status_changed.emit(message)


func wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
