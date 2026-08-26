extends Node2D

const W := 1280.0
const H := 720.0
const PANEL_X := 1000.0
const WORLD_W := 1280.0
const WORLD_H := 720.0
const PATH_WIDTH := 76.0
const TOWER_COSTS := [70, 100, 130, 80, 100, 120]
const TOWER_NAMES := ["Archer", "Cannon", "Frost", "Barricade", "Foundation", "Gold Mine"]
const TOWER_COLORS := [Color("#ffd166"), Color("#ef8354"), Color("#73d2de"), Color("#b08968"), Color("#d6c7a1"), Color("#f4c542")]
const BARRIER_MAX_HP := 800.0
const ENEMY_BASE_ATTACK := 20.0
const FIRST_WAVE_SOLDIER_HP := 80.0
const BOSS_HP := FIRST_WAVE_SOLDIER_HP * 50.0
const BOSS_ATTACK := 100.0
const PATH := [Vector2(-30, 120), Vector2(210, 120), Vector2(210, 300), Vector2(470, 300), Vector2(470, 120), Vector2(760, 120), Vector2(760, 500), Vector2(930, 500), Vector2(1030, 500)]
const BUILD_SPOTS := [Vector2(120,220),Vector2(335,190),Vector2(340,390),Vector2(570,220),Vector2(650,390),Vector2(860,270),Vector2(880,610)]

var gold := 240
var lives := 20
var wave := 0
var score := 0
var selected_type := 0
var selected_tower := -1
var chinese := false
var difficulty := 1 # 0 easy, 1 normal, 2 hard
var enemies: Array[Dictionary] = []
var towers: Array[Dictionary] = []
var barriers: Array[Dictionary] = []
var foundations: Array[Dictionary] = []
var active_path: Array[Vector2] = []
var active_build_spots: Array[Vector2] = []
var shots: Array[Dictionary] = []
var spawn_left := 0
var spawn_timer := 0.0
var boss_spawned_this_wave := false
var bosses_spawned_this_wave := 0
var wave_active := false
var game_over := false
var victory := false
var banner := "Choose a tower, then click a glowing build pad"
var banner_time := 5.0
var hover_spot := -1
var hover_path := Vector2.ZERO
var path_hover_valid := false
var castle_tex: Texture2D
var tower_tex: Texture2D
var archery_tex: Texture2D
var barracks_tex: Texture2D
var enemy_tex: Texture2D
var tree_tex: Texture2D
var sfx_streams: Dictionary = {}
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_player_index := 0
var music_player: AudioStreamPlayer

func localize(english: String, chinese_text: String) -> String:
	return chinese_text if chinese else english

func tower_name(type: int) -> String:
	var chinese_names := ["弓箭塔", "火炮塔", "冰霜塔", "路障", "地基", "矿塔"]
	return chinese_names[type] if chinese else TOWER_NAMES[type]

func difficulty_name() -> String:
	var english_names := ["EASY", "NORMAL", "HARD"]
	var chinese_names := ["简单", "普通", "困难"]
	return chinese_names[difficulty] if chinese else english_names[difficulty]

func enemy_hp_multiplier() -> float:
	return 0.5 if difficulty == 0 else 1.0

func boss_count_for_wave(current_wave: int) -> int:
	if difficulty == 2:
		if current_wave == 10: return 2
		return 1 if current_wave in [5,6,7,8] else 0
	return 1 if current_wave in [5,10] else 0

func _ready() -> void:
	randomize_map()
	castle_tex = load("res://Tiny Swords (Free Pack)/Tiny Swords (Free Pack)/Buildings/Blue Buildings/Castle.png")
	tower_tex = load("res://Tiny Swords (Free Pack)/Tiny Swords (Free Pack)/Buildings/Blue Buildings/Tower.png")
	archery_tex = load("res://Tiny Swords (Free Pack)/Tiny Swords (Free Pack)/Buildings/Blue Buildings/Archery.png")
	barracks_tex = load("res://Tiny Swords (Free Pack)/Tiny Swords (Free Pack)/Buildings/Blue Buildings/Barracks.png")
	enemy_tex = load("res://Tiny Swords (Free Pack)/Tiny Swords (Free Pack)/Units/Red Units/Warrior/Warrior_Run.png")
	tree_tex = load("res://Tiny Swords (Free Pack)/Tiny Swords (Free Pack)/Terrain/Resources/Wood/Trees/Tree2.png")
	setup_sound_effects()
	setup_background_music()
	queue_redraw()

func setup_background_music() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = -16.0
	music_player.stream = create_harmonica_music()
	add_child(music_player)
	music_player.play()

func midi_frequency(note: int) -> float:
	return 440.0 * pow(2.0, (float(note) - 69.0) / 12.0)

func create_harmonica_music() -> AudioStreamWAV:
	var rate := 22050
	var beat := 0.5
	var melody := [67,69,71,72, 74,72,71,67, 64,67,69,71, 72,71,69,67, 67,69,71,74, 76,74,72,71, 69,71,72,69, 67,64,62,67]
	var chords := [[48,52,55],[45,48,52],[41,45,48],[43,47,50],[48,52,55],[45,48,52],[43,47,50],[48,52,55]]
	var duration := melody.size() * beat
	var count := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var t := float(i) / float(rate)
		var note_index := mini(int(t / beat), melody.size() - 1)
		var note_time := fmod(t, beat)
		var note_env := minf(1.0, note_time / 0.055) * minf(1.0, (beat - note_time) / 0.1)
		var vibrato := sin(TAU * 5.4 * t) * 0.006
		var freq := midi_frequency(melody[note_index]) * (1.0 + vibrato)
		var lead := sin(TAU * freq * t) * 0.58
		lead += sin(TAU * freq * 2.0 * t) * 0.19
		lead += sin(TAU * freq * 3.0 * t) * 0.11
		lead += sound_noise(i, 73) * 0.035
		var chord_index := mini(int(t / (beat * 4.0)), chords.size() - 1)
		var pad := 0.0
		for chord_note in chords[chord_index]:
			var chord_freq := midi_frequency(chord_note)
			pad += sin(TAU * chord_freq * t) * 0.075
		var pulse := 0.04 * sin(TAU * 2.0 * t) * exp(-fmod(t, beat * 2.0) * 5.0)
		var sample := lead * note_env * 0.62 + pad + pulse
		bytes.encode_s16(i * 2, int(clampf(sample, -0.95, 0.95) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	stream.data = bytes
	return stream

func setup_sound_effects() -> void:
	var durations := {"arrow":0.16,"fireball":0.34,"freeze":0.38,"enemy_down":0.42,"enemy_attack":0.19,"build":0.34,"coin_gain":0.26,"coin_spend":0.24,"barrier_break":0.52}
	for sound_name in durations:
		sfx_streams[sound_name] = create_sound(sound_name, durations[sound_name])
	for i in 12:
		var player := AudioStreamPlayer.new()
		player.volume_db = -7.0
		add_child(player)
		sfx_players.append(player)

func sound_noise(index: int, seed: int) -> float:
	var n := sin(float(index * 127 + seed * 311) * 12.9898) * 43758.5453
	return (n - floor(n)) * 2.0 - 1.0

func create_sound(sound_name: String, duration: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var t := float(i) / float(rate)
		var x := t / duration
		var env := pow(maxf(0.0, 1.0 - x), 1.7)
		var noise := sound_noise(i, sound_name.hash())
		var sample := 0.0
		match sound_name:
			"arrow":
				var freq := lerpf(1450.0, 430.0, x)
				sample = sin(TAU * freq * t) * 0.38 * env + noise * 0.28 * env
			"fireball":
				var freq := lerpf(190.0, 72.0, x)
				sample = sin(TAU * freq * t) * 0.48 * env + noise * 0.38 * env
			"freeze":
				var shimmer := sin(TAU * (1050.0 + 900.0 * x) * t) + sin(TAU * 1570.0 * t) * 0.55
				sample = shimmer * 0.28 * env + noise * 0.12 * env
			"enemy_down":
				var freq := lerpf(210.0, 48.0, x)
				sample = sin(TAU * freq * t) * 0.55 * env + noise * 0.25 * env
			"enemy_attack":
				sample = (sin(TAU * 105.0 * t) * 0.58 + noise * 0.48) * pow(maxf(0.0, 1.0 - x), 3.0)
			"build":
				var hit_a := exp(-t * 48.0)
				var hit_b := exp(-maxf(0.0, t - 0.16) * 48.0) if t >= 0.16 else 0.0
				sample = (sin(TAU * 310.0 * t) + noise * 0.65) * (hit_a + hit_b) * 0.45
			"coin_gain":
				var freq := 880.0 if t < 0.11 else 1320.0
				sample = (sin(TAU * freq * t) + sin(TAU * freq * 2.0 * t) * 0.25) * 0.42 * env
			"coin_spend":
				var freq := lerpf(1050.0, 460.0, x)
				sample = sin(TAU * freq * t) * 0.42 * env
			"barrier_break":
				var crack := 1.0 if t < 0.07 or (t > 0.16 and t < 0.23) else 0.25
				sample = (noise * 0.58 * crack + sin(TAU * 62.0 * t) * 0.42) * env
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	return stream

func play_sfx(sound_name: String, pitch: float = 1.0) -> void:
	if not sfx_streams.has(sound_name) or sfx_players.is_empty(): return
	var player := sfx_players[sfx_player_index]
	sfx_player_index = (sfx_player_index + 1) % sfx_players.size()
	player.stop()
	player.stream = sfx_streams[sound_name]
	player.pitch_scale = pitch
	player.play()

func randomize_map() -> void:
	active_path.clear()
	var y1 := float(randi_range(90, 185))
	var y2 := float(randi_range(475, 590))
	var y3 := float(randi_range(155, 285))
	var y4 := float(randi_range(405, 555))
	var y5 := float(randi_range(100, 250))
	active_path.assign([Vector2(-30,y1),Vector2(150,y1),Vector2(150,y2),Vector2(350,y2),Vector2(350,y3),Vector2(550,y3),Vector2(550,y4),Vector2(750,y4),Vector2(750,y5),Vector2(980,y5)])
	generate_build_spots()

func generate_build_spots() -> void:
	active_build_spots.clear()
	var attempts := 0
	while active_build_spots.size() < 7 and attempts < 1000:
		attempts += 1
		var candidate := Vector2(randf_range(85.0, PANEL_X-85.0), randf_range(90.0, H-100.0))
		if nearest_path_point(candidate).distance < PATH_WIDTH * 0.5 + 45.0: continue
		if candidate.distance_to(active_path[-1]) < 145.0: continue
		var valid := true
		for existing in active_build_spots:
			if candidate.distance_to(existing) < 105.0:
				valid = false; break
		if valid: active_build_spots.append(candidate)

func _process(delta: float) -> void:
	if banner_time > 0.0: banner_time -= delta
	if game_over: queue_redraw(); return
	if wave_active:
		spawn_timer -= delta
		if spawn_left > 0 and spawn_timer <= 0.0:
			spawn_enemy()
			spawn_left -= 1
			spawn_timer = max(0.28, 0.78 - wave * 0.035)
	update_enemies(delta)
	update_barriers()
	update_towers(delta)
	update_shots(delta)
	if wave_active and spawn_left == 0 and enemies.is_empty():
		wave_active = false
		if wave >= 10:
			victory = true; game_over = true; banner = localize("KINGDOM SAVED!", "王国守住了！"); banner_time = 999.0
		else:
			gold += 35 + wave * 4
			play_sfx("coin_gain")
			banner = localize("Wave cleared! Bonus gold awarded", "波次完成！已获得额外金币")
			banner_time = 3.0
	queue_redraw()

func start_wave() -> void:
	if wave_active or game_over: return
	wave += 1
	boss_spawned_this_wave = false
	bosses_spawned_this_wave = 0
	spawn_left = 5 + wave * 2
	spawn_timer = 0.1
	wave_active = true
	banner = localize("Wave %d incoming!", "第 %d 波来袭！") % wave
	banner_time = 2.0

func spawn_enemy() -> void:
	var boss_target := boss_count_for_wave(wave)
	var is_boss := bosses_spawned_this_wave < boss_target
	if is_boss:
		boss_spawned_this_wave = true
		bosses_spawned_this_wave += 1
		var boss_hp := BOSS_HP * enemy_hp_multiplier()
		enemies.append({"pos":active_path[0],"seg":0,"hp":boss_hp,"max_hp":boss_hp,"speed":42.0,"slow":0.0,"reward":250 + wave * 15,"tank":true,"boss":true,"flash":0.0,"attack_cd":0.0,"attack_damage":BOSS_ATTACK})
		banner = localize("BOSS INCOMING — %d HP!", "BOSS 来袭——%d 点生命！") % int(boss_hp)
		banner_time = 3.0
		return
	var hp := (55.0 + wave * 25.0) * enemy_hp_multiplier()
	var fast := wave % 3 == 0 and spawn_left % 3 == 0
	var tank := wave >= 4 and spawn_left % 5 == 0
	if tank: hp *= 2.3
	enemies.append({"pos":active_path[0],"seg":0,"hp":hp,"max_hp":hp,"speed": (125.0 if fast else (54.0 if tank else 78.0)) + wave * 2.0,"slow":0.0,"reward":(20 if tank else 11) + wave,"tank":tank,"boss":false,"flash":0.0,"attack_cd":0.0,"attack_damage":ENEMY_BASE_ATTACK + max(0, wave - 1) * 10.0})

func update_enemies(delta: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var e := enemies[i]
		if e.hp <= 0:
			gold += e.reward; score += e.reward * 10; play_sfx("enemy_down", 0.72 if e.boss else 1.0); play_sfx("coin_gain", 1.15); enemies.remove_at(i); continue
		e.flash = max(0.0, e.flash - delta)
		e.slow = max(0.0, e.slow - delta)
		e.attack_cd = max(0.0, e.attack_cd - delta)
		var blocking_barrier := barrier_blocking_enemy(e)
		if blocking_barrier >= 0:
			if e.attack_cd <= 0.0:
				barriers[blocking_barrier].hp -= e.attack_damage
				barriers[blocking_barrier].flash = 0.12
				e.attack_cd = 1.0
				play_sfx("enemy_attack", 0.78 if e.boss else 1.0)
			continue
		var target: Vector2 = active_path[e.seg + 1]
		var speed: float = e.speed * (0.55 if e.slow > 0 else 1.0)
		e.pos = e.pos.move_toward(target, speed * delta)
		if e.pos.distance_to(target) < 1.0:
			e.seg += 1
			if e.seg >= active_path.size() - 1:
				lives -= 5 if e.boss else (2 if e.tank else 1)
				enemies.remove_at(i)
				if lives <= 0:
					game_over = true; banner = localize("THE KINGDOM HAS FALLEN", "王国陷落了"); banner_time = 999.0

func barrier_blocking_enemy(e: Dictionary) -> int:
	for i in barriers.size():
		var b := barriers[i]
		if b.seg == e.seg and e.pos.distance_to(b.pos) <= 34.0:
			return i
	return -1

func update_barriers() -> void:
	for i in range(barriers.size() - 1, -1, -1):
		barriers[i].flash = max(0.0, barriers[i].flash - get_process_delta_time())
		if barriers[i].hp <= 0.0:
			play_sfx("barrier_break")
			barriers.remove_at(i)
			banner = localize("Barricade destroyed!", "路障被摧毁了！")
			banner_time = 2.0

func update_towers(delta: float) -> void:
	for t in towers:
		if t.type == 5:
			if wave_active:
				t.income_timer -= delta
				if t.income_timer <= 0.0:
					gold += 10
					play_sfx("coin_gain", 1.2)
					t.income_timer += 3.0
					shots.append({"from":t.pos,"to":t.pos-Vector2(0,38),"life":0.35,"color":TOWER_COLORS[5]})
			continue
		t.cool -= delta
		if t.cool > 0: continue
		var best := -1
		var progress := -1
		for i in enemies.size():
			var e := enemies[i]
			if t.pos.distance_to(e.pos) <= t.range:
				var p: int = e.seg
				if p > progress: progress = p; best = i
		if best >= 0:
			var damage: float = [17.0, 34.0, 9.0][t.type] * (1.0 + (t.level - 1) * 0.55)
			shots.append({"from":t.pos,"to":enemies[best].pos,"life":0.12,"color":TOWER_COLORS[t.type]})
			enemies[best].hp -= damage
			enemies[best].flash = 0.1
			if t.type == 2: enemies[best].slow = 1.4
			play_sfx(["arrow", "fireball", "freeze"][t.type])
			t.cool = [0.62, 1.25, 0.42][t.type] / (1.0 + (t.level - 1) * 0.18)

func update_shots(delta: float) -> void:
	for i in range(shots.size()-1,-1,-1):
		shots[i].life -= delta
		if shots[i].life <= 0: shots.remove_at(i)

func build_at(index: int) -> void:
	if occupied(index): return
	var cost: int = TOWER_COSTS[selected_type]
	if gold < cost: banner = localize("Not enough gold", "金币不足"); banner_time = 2.0; return
	gold -= cost
	play_sfx("coin_spend")
	var tower_range: float = 0.0 if selected_type == 5 else [210.0,185.0,200.0][selected_type]
	towers.append({"spot":index,"pos":active_build_spots[index],"type":selected_type,"level":1,"cool":0.2,"range":tower_range,"spent":cost,"income_timer":3.0})
	selected_tower = towers.size()-1
	play_sfx("build")
	banner = localize("%s tower built", "已建造%s") % tower_name(selected_type)
	banner_time = 2.0

func build_barrier(pos: Vector2, segment: int) -> void:
	var cost: int = TOWER_COSTS[3]
	if gold < cost: banner = localize("Not enough gold", "金币不足"); banner_time = 2.0; return
	for b in barriers:
		if b.pos.distance_to(pos) < 72.0: banner = "Barricades are too close"; banner_time = 2.0; return
	if pos.distance_to(active_path[0]) < 80.0 or pos.distance_to(active_path[-1]) < 100.0:
		banner = "Cannot block the entrance or castle gate"; banner_time = 2.0; return
	gold -= cost
	play_sfx("coin_spend")
	barriers.append({"pos":pos,"seg":segment,"hp":BARRIER_MAX_HP,"max_hp":BARRIER_MAX_HP,"flash":0.0,"spent":cost})
	play_sfx("build")
	banner = localize("Barricade placed: 800 HP", "路障已放置：800 点生命")
	banner_time = 2.0

func build_foundation(pos: Vector2) -> void:
	var path_result := nearest_path_point(pos)
	if path_result.distance <= PATH_WIDTH * 0.5 + 28.0:
		banner = "Foundations cannot be placed on the dirt road"; banner_time = 2.0; return
	if pos.x < 45.0 or pos.x > PANEL_X - 45.0 or pos.y < 75.0 or pos.y > H - 75.0:
		banner = "Too close to the map edge"; banner_time = 2.0; return
	for f in foundations:
		if f.pos.distance_to(pos) < 80.0: banner = "Foundations are too close"; banner_time = 2.0; return
	for spot in active_build_spots:
		if spot.distance_to(pos) < 70.0: banner = "Too close to an existing build pad"; banner_time = 2.0; return
	if gold < TOWER_COSTS[4]: banner = localize("Not enough gold", "金币不足"); banner_time = 2.0; return
	gold -= TOWER_COSTS[4]
	play_sfx("coin_spend")
	foundations.append({"pos":pos,"occupied":false})
	play_sfx("build")
	banner = localize("Foundation built — choose a tower", "地基建造完成——请选择塔")
	banner_time = 2.0

func build_on_foundation(index: int) -> void:
	if foundations[index].occupied: return
	if selected_type not in [0,1,2,5]: return
	var cost: int = TOWER_COSTS[selected_type]
	if gold < cost: banner = localize("Not enough gold", "金币不足"); banner_time = 2.0; return
	gold -= cost
	play_sfx("coin_spend")
	var tower_range: float = 0.0 if selected_type == 5 else [210.0,185.0,200.0][selected_type]
	towers.append({"spot":-1,"foundation":index,"pos":foundations[index].pos,"type":selected_type,"level":1,"cool":0.2,"range":tower_range,"spent":cost,"income_timer":3.0})
	foundations[index].occupied = true
	selected_tower = towers.size() - 1
	play_sfx("build")
	banner = localize("%s built on foundation", "%s已建在地基上") % tower_name(selected_type)
	banner_time = 2.0

func occupied(spot: int) -> bool:
	for t in towers:
		if t.spot == spot: return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var world_mouse: Vector2 = event.position
		hover_spot = nearest_spot(world_mouse, 34.0)
		var path_result := nearest_path_point(world_mouse)
		hover_path = path_result.pos
		path_hover_valid = path_result.distance <= PATH_WIDTH * 0.5
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var p: Vector2 = event.position
		var world_p: Vector2 = p
		if game_over:
			if Rect2(1080,625,170,55).has_point(p): restart_game()
			return
		for i in 6:
			if Rect2(PANEL_X+24,135+i*46,232,40).has_point(p): selected_type=i; selected_tower=-1; return
		if Rect2(PANEL_X+24,420,232,58).has_point(p): start_wave(); return
		if selected_tower >= 0:
			if Rect2(PANEL_X+24,510,110,48).has_point(p): upgrade_selected(); return
			if Rect2(PANEL_X+146,510,110,48).has_point(p): sell_selected(); return
		if Rect2(PANEL_X+176,565,80,30).has_point(p):
			chinese = not chinese
			banner = localize("Language switched to English", "语言已切换为中文")
			banner_time = 2.0
			return
		if Rect2(PANEL_X+24,565,142,30).has_point(p):
			if wave > 0 or wave_active:
				banner = localize("Difficulty can only change before wave 1", "只能在第一波开始前更改难度")
			else:
				difficulty = (difficulty + 1) % 3
				banner = localize("Difficulty: %s", "难度：%s") % difficulty_name()
			banner_time = 2.0
			return
		var clicked_tower := nearest_tower(world_p, 48.0)
		if clicked_tower >= 0:
			selected_tower = clicked_tower
			banner = localize("%s selected — upgrade or sell", "已选择%s——可以升级或出售") % tower_name(towers[clicked_tower].type)
			banner_time = 1.5
			return
		if selected_type == 3:
			var path_result := nearest_path_point(world_p)
			if path_result.distance <= PATH_WIDTH * 0.5:
				build_barrier(path_result.pos, path_result.segment)
			else:
				banner = "Barricades can only be placed on the dirt road"; banner_time = 2.0
			return
		if selected_type == 4:
			build_foundation(world_p)
			return
		var foundation_index := nearest_foundation(world_p, 40.0)
		if foundation_index >= 0 and not foundations[foundation_index].occupied:
			build_on_foundation(foundation_index)
			return
		var si := nearest_spot(world_p, 42.0)
		if si >= 0:
			for i in towers.size():
				if towers[i].spot == si: selected_tower=i; return
			if selected_type in [0,1,2,5]:
				build_at(si)
			else:
				banner = "Choose a tower for this foundation"; banner_time = 2.0

func nearest_spot(p: Vector2, radius: float) -> int:
	for i in active_build_spots.size():
		if active_build_spots[i].distance_to(p) <= radius: return i
	return -1

func nearest_foundation(p: Vector2, radius: float) -> int:
	for i in foundations.size():
		if foundations[i].pos.distance_to(p) <= radius: return i
	return -1

func nearest_tower(p: Vector2, radius: float) -> int:
	for i in towers.size():
		if towers[i].pos.distance_to(p) <= radius: return i
	return -1

func nearest_path_point(p: Vector2) -> Dictionary:
	var best_pos := active_path[0]
	var best_distance: float = INF
	var best_segment := 0
	for i in active_path.size() - 1:
		var a: Vector2 = active_path[i]
		var b: Vector2 = active_path[i + 1]
		var ab: Vector2 = b - a
		var t: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var candidate: Vector2 = a + ab * t
		var distance: float = p.distance_to(candidate)
		if distance < best_distance:
			best_distance = distance; best_pos = candidate; best_segment = i
	return {"pos":best_pos,"distance":best_distance,"segment":best_segment}

func upgrade_selected() -> void:
	if selected_tower < 0 or selected_tower >= towers.size(): return
	var t := towers[selected_tower]
	if t.type == 5: banner=localize("Gold mines cannot be upgraded", "矿塔无法升级"); banner_time=2.0; return
	if t.level >= 3: banner=localize("Tower is already max level", "塔已达到最高等级"); banner_time=2.0; return
	var cost: int = 55 * t.level
	if gold < cost: banner=localize("Not enough gold", "金币不足"); banner_time=2.0; return
	gold -= cost; t.spent += cost; t.level += 1; t.range += 20.0
	play_sfx("coin_spend"); play_sfx("build", 1.15)

func sell_selected() -> void:
	if selected_tower < 0 or selected_tower >= towers.size(): return
	if towers[selected_tower].has("foundation") and towers[selected_tower].foundation >= 0:
		foundations[towers[selected_tower].foundation].occupied = false
	gold += int(towers[selected_tower].spent * 0.7)
	play_sfx("coin_gain")
	towers.remove_at(selected_tower); selected_tower = -1

func restart_game() -> void:
	gold=240; lives=20; wave=0; score=0; enemies.clear(); towers.clear(); barriers.clear(); foundations.clear(); shots.clear(); spawn_left=0; boss_spawned_this_wave=false; bosses_spawned_this_wave=0; wave_active=false; game_over=false; victory=false; selected_tower=-1; randomize_map(); banner="A new random map begins"; banner_time=3.0

func _draw() -> void:
	# World
	draw_rect(Rect2(0,0,WORLD_W,WORLD_H), Color("#80b85a"))
	for x in range(0,int(WORLD_W),64):
		for y in range(0,int(WORLD_H),64):
			if (x/64 + y/64 as int) % 2 == 0: draw_rect(Rect2(x,y,64,64),Color(1,1,1,0.025))
	# River and path
	draw_rect(Rect2(0,WORLD_H-70,WORLD_W,70),Color("#4fa4c4"))
	for i in active_path.size()-1:
		draw_line(active_path[i],active_path[i+1],Color("#c6a66b"),PATH_WIDTH,true)
		draw_line(active_path[i],active_path[i+1],Color("#dfc184"),PATH_WIDTH-14,true)
	if selected_type == 3 and path_hover_valid:
		draw_circle(hover_path, 30, Color(0.69,0.54,0.41,0.35))
		draw_arc(hover_path,30,0,TAU,24,Color("#ffe0b2"),3)
	# scenery
	for pos in [Vector2(60,570),Vector2(535,600),Vector2(900,80)]: draw_tree(pos)
	draw_castle(active_path[-1]-Vector2(85,0))
	# build pads
	for i in active_build_spots.size():
		var free := not occupied(i)
		var col := Color("#f6e58d") if free else Color("#34495e")
		if i == hover_spot: col = Color("#fff3b0")
		draw_circle(active_build_spots[i],38,col, true)
		draw_arc(active_build_spots[i],38,0,TAU,32,Color("#ffffff88"),3)
		if free: draw_string(ThemeDB.fallback_font,active_build_spots[i]+Vector2(-10,8),"+",HORIZONTAL_ALIGNMENT_LEFT,20,28,Color("#6b7d3d"))
	# towers and ranges
	for f in foundations: draw_foundation(f)
	if selected_tower >= 0 and selected_tower < towers.size():
		var st := towers[selected_tower]
		draw_circle(st.pos,st.range,Color(1,1,1,0.08)); draw_arc(st.pos,st.range,0,TAU,64,Color(1,1,1,0.35),2)
	for i in towers.size(): draw_tower(towers[i], i == selected_tower)
	for b in barriers: draw_barrier(b)
	for e in enemies: draw_enemy(e)
	for s in shots: draw_line(s.from,s.to,s.color,4,true); draw_circle(s.to,7,s.color)
	# panel
	draw_rect(Rect2(PANEL_X,0,W-PANEL_X,H),Color("#17212b"))
	draw_rect(Rect2(PANEL_X+10,10,260,700),Color("#22313f"),true)
	draw_string(ThemeDB.fallback_font,Vector2(PANEL_X+28,48),localize("KINGDOM DEFENSE", "王国塔防"),HORIZONTAL_ALIGNMENT_LEFT,-1,26,Color("#f8d56b"))
	draw_string(ThemeDB.fallback_font,Vector2(PANEL_X+28,88),localize("Gold  %d", "金币  %d")%gold,HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("#ffd166"))
	draw_string(ThemeDB.fallback_font,Vector2(PANEL_X+145,88),localize("Lives  %d", "生命  %d")%lives,HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("#ef6f6c"))
	draw_string(ThemeDB.fallback_font,Vector2(PANEL_X+28,122),localize("Wave  %d/10    Score  %d", "波次  %d/10    分数  %d")%[wave,score],HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
	for i in 6: draw_tower_button(i)
	draw_button(Rect2(PANEL_X+24,420,232,58),localize("WAVE IN PROGRESS", "波次进行中") if wave_active else localize("START NEXT WAVE", "开始下一波"),Color("#4f9d69") if not wave_active else Color("#52616b"))
	if selected_tower >= 0 and selected_tower < towers.size():
		var t := towers[selected_tower]
		draw_string(ThemeDB.fallback_font,Vector2(PANEL_X+28,500),"%s  %s%d"%[tower_name(t.type),localize("Lv.", "等级 "),t.level],HORIZONTAL_ALIGNMENT_LEFT,-1,20,TOWER_COLORS[t.type])
		draw_button(Rect2(PANEL_X+24,510,110,48),localize("UPGRADE", "升级"),Color("#3d7ea6")); draw_button(Rect2(PANEL_X+146,510,110,48),localize("SELL", "出售"),Color("#a35d5d"))
	draw_button(Rect2(PANEL_X+176,565,80,30),"中文" if not chinese else "EN",Color("#596f82"))
	draw_button(Rect2(PANEL_X+24,565,142,30),localize("MODE: ", "难度：")+difficulty_name(),Color("#7768ae") if difficulty==2 else (Color("#5c9b68") if difficulty==0 else Color("#596f82")))
	draw_string(ThemeDB.fallback_font,Vector2(PANEL_X+26,604),localize("Tips", "提示"),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("#f8d56b"))
	draw_multiline_string(ThemeDB.fallback_font,Vector2(PANEL_X+26,630),localize("Foundation: anywhere off-road\nMine: +10 gold / 3 sec\nIncome only during waves", "地基：可建在泥路外\n矿塔：每3秒获得10金币\n仅在波次中产生收益"),HORIZONTAL_ALIGNMENT_LEFT,220,16,18,Color("#c9d6df"))
	if banner_time > 0:
		draw_rect(Rect2(210,22,580,48),Color(0.05,0.08,0.12,0.88),true)
		draw_string(ThemeDB.fallback_font,Vector2(210,54),banner,HORIZONTAL_ALIGNMENT_CENTER,580,21,Color.WHITE)
	if game_over:
		draw_rect(Rect2(0,0,W,H),Color(0.03,0.04,0.07,0.72),true)
		draw_string(ThemeDB.fallback_font,Vector2(0,300),banner,HORIZONTAL_ALIGNMENT_CENTER,W,42,Color("#f8d56b") if victory else Color("#ef6f6c"))
		draw_string(ThemeDB.fallback_font,Vector2(0,350),localize("Final score: %d", "最终分数：%d")%score,HORIZONTAL_ALIGNMENT_CENTER,W,24,Color.WHITE)
		draw_button(Rect2(1080,625,170,55),localize("PLAY AGAIN", "再玩一次"),Color("#4f9d69"))

func draw_tree(pos: Vector2) -> void:
	if tree_tex: draw_texture_rect_region(tree_tex,Rect2(pos-Vector2(55,80),Vector2(110,110)),Rect2(0,0,min(192,tree_tex.get_width()),min(192,tree_tex.get_height())))

func draw_castle(pos: Vector2) -> void:
	draw_circle(pos,70,Color("#506d84"))
	if castle_tex: draw_texture_rect_region(castle_tex,Rect2(pos-Vector2(90,110),Vector2(180,180)),Rect2(0,0,min(192,castle_tex.get_width()),min(192,castle_tex.get_height())))

func draw_tower(t: Dictionary, selected: bool) -> void:
	var tex: Texture2D = tower_tex if t.type == 5 else [archery_tex,barracks_tex,tower_tex][t.type]
	if selected: draw_circle(t.pos,45,Color(1,1,1,0.25))
	if tex: draw_texture_rect_region(tex,Rect2(t.pos-Vector2(48,62),Vector2(96,96)),Rect2(0,0,min(192,tex.get_width()),min(192,tex.get_height())))
	draw_circle(t.pos+Vector2(0,35),13,TOWER_COLORS[t.type])
	draw_string(ThemeDB.fallback_font,t.pos+Vector2(-8,41),str(t.level),HORIZONTAL_ALIGNMENT_CENTER,16,15,Color("#17212b"))
	if t.type == 5:
		draw_string(ThemeDB.fallback_font,t.pos+Vector2(-22,-55),"+10",HORIZONTAL_ALIGNMENT_CENTER,44,16,Color("#ffe066"))

func draw_foundation(f: Dictionary) -> void:
	draw_circle(f.pos, 41, Color("#6c584c"))
	draw_circle(f.pos, 35, Color("#b7a27b"))
	draw_arc(f.pos,35,0,TAU,20,Color("#e6d5b8"),3)
	if not f.occupied:
		draw_string(ThemeDB.fallback_font,f.pos+Vector2(-12,9),"+",HORIZONTAL_ALIGNMENT_CENTER,24,28,Color("#4a403a"))

func draw_enemy(e: Dictionary) -> void:
	var tint := Color.WHITE if e.flash <= 0 else Color("#fff3b0")
	var enemy_size := Vector2(92,92) if e.boss else Vector2(56,56)
	var enemy_offset := Vector2(46,60) if e.boss else Vector2(28,38)
	if enemy_tex: draw_texture_rect_region(enemy_tex,Rect2(e.pos-enemy_offset,enemy_size),Rect2(0,0,min(192,enemy_tex.get_width()),min(192,enemy_tex.get_height())),tint)
	else: draw_circle(e.pos,18,Color("#c44545"))
	var ratio: float = max(0.0,e.hp/e.max_hp)
	var bar_width := 90.0 if e.boss else 48.0
	var bar_y := -59.0 if e.boss else -34.0
	draw_rect(Rect2(e.pos+Vector2(-bar_width/2.0,bar_y),Vector2(bar_width,8 if e.boss else 6)),Color("#321f28"),true)
	draw_rect(Rect2(e.pos+Vector2(-bar_width/2.0,bar_y),Vector2(bar_width*ratio,8 if e.boss else 6)),Color("#d62828") if e.boss else (Color("#67c56b") if ratio>.35 else Color("#ef6f6c")),true)
	if e.boss:
		draw_string(ThemeDB.fallback_font,e.pos+Vector2(-45,-66),"BOSS  %d HP" % ceil(e.hp),HORIZONTAL_ALIGNMENT_CENTER,90,15,Color("#ffd166"))
	if e.slow > 0: draw_arc(e.pos,24,0,TAU,24,Color("#73d2de"),2)

func draw_barrier(b: Dictionary) -> void:
	var color := Color("#f6d7b0") if b.flash > 0.0 else Color("#8b5e3c")
	draw_rect(Rect2(b.pos - Vector2(28,18),Vector2(56,36)),Color("#523522"),true)
	for offset in [-18.0, 0.0, 18.0]:
		draw_line(b.pos+Vector2(offset-9,-15),b.pos+Vector2(offset+9,15),color,8,true)
	draw_line(b.pos+Vector2(-29,-17),b.pos+Vector2(29,-17),Color("#d7a86e"),5,true)
	draw_line(b.pos+Vector2(-29,17),b.pos+Vector2(29,17),Color("#d7a86e"),5,true)
	var ratio: float = max(0.0,b.hp/b.max_hp)
	draw_rect(Rect2(b.pos+Vector2(-32,-29),Vector2(64,7)),Color("#321f28"),true)
	draw_rect(Rect2(b.pos+Vector2(-32,-29),Vector2(64*ratio,7)),Color("#67c56b") if ratio>.35 else Color("#ef6f6c"),true)
	draw_string(ThemeDB.fallback_font,b.pos+Vector2(-25,35),"%d" % ceil(b.hp),HORIZONTAL_ALIGNMENT_CENTER,50,13,Color.WHITE)

func draw_tower_button(i: int) -> void:
	var r := Rect2(PANEL_X+24,135+i*46,232,40)
	draw_rect(r,Color("#31475a") if selected_type!=i else Color("#49677f"),true)
	draw_rect(r,TOWER_COLORS[i],false,3)
	draw_circle(r.position+Vector2(25,20),13,TOWER_COLORS[i])
	draw_shop_icon(i, r.position + Vector2(25,20))
	draw_string(ThemeDB.fallback_font,r.position+Vector2(47,18),tower_name(i),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color.WHITE)
	draw_string(ThemeDB.fallback_font,r.position+Vector2(158,25),"%d G"%TOWER_COSTS[i],HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#ffd166"))

func draw_shop_icon(type: int, center: Vector2) -> void:
	if type in [0,1,2,5]:
		var tex: Texture2D = tower_tex if type in [2,5] else (archery_tex if type == 0 else barracks_tex)
		if tex:
			draw_texture_rect_region(tex,Rect2(center-Vector2(15,18),Vector2(30,30)),Rect2(0,0,min(192,tex.get_width()),min(192,tex.get_height())))
		if type == 5:
			draw_circle(center+Vector2(8,-8),6,Color("#f9c74f"))
			draw_string(ThemeDB.fallback_font,center+Vector2(4,-4),"$",HORIZONTAL_ALIGNMENT_CENTER,8,10,Color("#5c4612"))
	elif type == 3:
		draw_line(center+Vector2(-9,-7),center+Vector2(9,7),Color("#4a2f1b"),5,true)
		draw_line(center+Vector2(-9,7),center+Vector2(9,-7),Color("#e0b27a"),5,true)
		draw_line(center+Vector2(-11,0),center+Vector2(11,0),Color("#6b4226"),3,true)
	else:
		draw_rect(Rect2(center-Vector2(10,7),Vector2(20,14)),Color("#6c584c"),true)
		draw_rect(Rect2(center-Vector2(8,5),Vector2(16,10)),Color("#d6c7a1"),true)
		draw_string(ThemeDB.fallback_font,center+Vector2(-6,5),"+",HORIZONTAL_ALIGNMENT_CENTER,12,12,Color("#4a403a"))

func draw_button(r: Rect2, text: String, color: Color) -> void:
	draw_rect(r,color,true); draw_rect(r,Color(1,1,1,0.2),false,2)
	draw_string(ThemeDB.fallback_font,r.position+Vector2(0,r.size.y/2+7),text,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,17,Color.WHITE)
