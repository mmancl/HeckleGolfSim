extends Object
class_name GolfDataExporter

## Utility class to export golf shot data and player statistics into CSV format
## and draft emails with the CSV file attached using standard MIME .eml format and mailto fallback.

static func csv_escape(val: Variant) -> String:
	var s = str(val)
	if s.contains(",") or s.contains("\"") or s.contains("\n") or s.contains("\r"):
		return "\"" + s.replace("\"", "\"\"") + "\""
	return s


static func sanitize_filename(text: String) -> String:
	var safe := ""
	for c in text:
		if (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '-' or c == '_':
			safe += c
		elif c == ' ':
			safe += "_"
	return safe if not safe.is_empty() else "export"


## Generates a complete CSV string of all golf shot data for a round.
static func generate_round_csv(player: Dictionary, match_data: Dictionary) -> String:
	var player_name = player.get("name", "Player")
	var course_title = match_data.get("course_title", "Unknown Course")
	var date_str = match_data.get("formatted_date", "Unknown Date")
	var tee = player.get("tee", "Blue")

	# Collect hole pars and scores
	var pars: Dictionary = match_data.get("pars", {})
	var hole_scores: Dictionary = player.get("hole_scores", {})
	var hole_ids: Array = match_data.get("hole_ids", [])
	if hole_ids.is_empty():
		hole_ids = hole_scores.keys()
		hole_ids.sort()

	# Shot stats can be a Dictionary (hole_id -> Array[shot]) or an Array[shot]
	var shot_stats = player.get("shot_stats", {})

	var headers = [
		"Player", "Course", "Date", "Tee", "Hole", "Par", "Hole Score",
		"Shot", "Club", "Ball Speed (mph)", "Launch Angle (deg)", "Horizontal Angle (deg)",
		"Total Spin (rpm)", "Back Spin (rpm)", "Side Spin (rpm)", "Spin Axis (deg)",
		"Apex (ft)", "Carry Distance (yds)", "Total Distance (yds)",
		"Offline (yds)", "Offline Direction"
	]
	
	var csv_lines: PackedStringArray = []
	csv_lines.append(",".join(headers))

	if typeof(shot_stats) == TYPE_DICTIONARY:
		for h_id in hole_ids:
			var par_val = pars.get(h_id, 4)
			var score_val = hole_scores.get(h_id, "")
			var score_str = str(score_val) if score_val != null and str(score_val) != "" else "-"
			var shots = shot_stats.get(h_id, [])

			if shots.is_empty():
				# Write a single summary row for the hole
				var row = [
					csv_escape(player_name),
					csv_escape(course_title),
					csv_escape(date_str),
					csv_escape(tee),
					csv_escape(h_id),
					csv_escape(par_val),
					csv_escape(score_str),
					"-", "-", "-", "-", "-", "-", "-", "-", "-", "-", "-", "-", "-", "-"
				]
				csv_lines.append(",".join(row))
			else:
				for i in range(shots.size()):
					var shot = shots[i]
					var shot_num = shot.get("shot_num", i + 1)
					var club = shot.get("club", "Unknown")
					if club == "": club = "Unknown"

					var speed = "%.1f" % float(shot.get("speed_mph", 0.0))
					var vla = "%.1f" % float(shot.get("vla_deg", 0.0))
					var hla = "%.1f" % float(shot.get("hla_deg", 0.0))
					var tot_spin = "%d" % int(shot.get("total_spin_rpm", 0.0))
					var back_spin = "%d" % int(shot.get("back_spin_rpm", 0.0))
					var side_spin = "%d" % int(shot.get("side_spin_rpm", 0.0))
					var spin_axis = "%.1f" % float(shot.get("spin_axis_deg", 0.0))
					var apex = "%.1f" % float(shot.get("apex_ft", 0.0))
					var carry = "%.1f" % float(shot.get("carry_yds", 0.0))
					var total = "%.1f" % float(shot.get("total_yds", 0.0))

					var off_val = float(shot.get("offline_yds", 0.0))
					if absf(off_val) > 120.0:
						off_val = 0.0
					var off_dir = "R" if off_val >= 0 else "L"
					var offline_str = "%.1f" % absf(off_val)

					var row = [
						csv_escape(player_name),
						csv_escape(course_title),
						csv_escape(date_str),
						csv_escape(tee),
						csv_escape(h_id),
						csv_escape(par_val),
						csv_escape(score_str),
						csv_escape(shot_num),
						csv_escape(club),
						speed, vla, hla,
						tot_spin, back_spin, side_spin, spin_axis,
						apex, carry, total,
						offline_str, off_dir
					]
					csv_lines.append(",".join(row))

	elif typeof(shot_stats) == TYPE_ARRAY:
		var shots_by_hole: Dictionary = {}
		for shot in shot_stats:
			if typeof(shot) != TYPE_DICTIONARY:
				continue
			var h_id = shot.get("hole_id", "Hole")
			if not shots_by_hole.has(h_id):
				shots_by_hole[h_id] = []
			shots_by_hole[h_id].append(shot)

		var all_holes = hole_ids.duplicate()
		for h_id in shots_by_hole.keys():
			if not all_holes.has(h_id):
				all_holes.append(h_id)

		for h_id in all_holes:
			var par_val = pars.get(h_id, 4)
			var score_val = hole_scores.get(h_id, "")
			var score_str = str(score_val) if score_val != null and str(score_val) != "" else "-"
			var shots = shots_by_hole.get(h_id, [])

			if shots.is_empty():
				var row = [
					csv_escape(player_name),
					csv_escape(course_title),
					csv_escape(date_str),
					csv_escape(tee),
					csv_escape(h_id),
					csv_escape(par_val),
					csv_escape(score_str),
					"-", "-", "-", "-", "-", "-", "-", "-", "-", "-", "-", "-", "-", "-"
				]
				csv_lines.append(",".join(row))
			else:
				for i in range(shots.size()):
					var shot = shots[i]
					var stroke = shot.get("stroke", shot.get("shot_num", i + 1))
					var club = shot.get("club", "Dr")
					var raw = shot.get("raw_data", {})

					var speed = "%.1f" % float(shot.get("speed_mph", raw.get("Speed", 0.0)))
					var vla = "%.1f" % float(shot.get("vla_deg", raw.get("VLA", 0.0)))
					var hla = "%.1f" % float(shot.get("hla_deg", raw.get("HLA", 0.0)))
					var tot_spin = "%d" % int(shot.get("total_spin_rpm", raw.get("TotalSpin", 0.0)))
					var back_spin = "%d" % int(shot.get("back_spin_rpm", raw.get("BackSpin", 0.0)))
					var side_spin = "%d" % int(shot.get("side_spin_rpm", raw.get("SideSpin", 0.0)))
					var spin_axis = "%.1f" % float(shot.get("spin_axis_deg", raw.get("SpinAxis", 0.0)))
					var apex = "%.1f" % float(shot.get("apex_ft", raw.get("Apex", 0.0) * 3.28084))
					var carry = "%.1f" % float(shot.get("carry_yds", raw.get("CarryDistance", 0.0) * 1.09361))
					var total = "%.1f" % float(shot.get("total_yds", raw.get("TotalDistance", 0.0) * 1.09361))

					var off_val = float(shot.get("offline_yds", raw.get("SideDistance", 0.0) * 1.09361))
					if absf(off_val) > 120.0:
						off_val = 0.0
					var off_dir = "R" if off_val >= 0 else "L"
					var offline_str = "%.1f" % absf(off_val)

					var row = [
						csv_escape(player_name),
						csv_escape(course_title),
						csv_escape(date_str),
						csv_escape(tee),
						csv_escape(h_id),
						csv_escape(par_val),
						csv_escape(score_str),
						csv_escape(stroke),
						csv_escape(club),
						speed, vla, hla,
						tot_spin, back_spin, side_spin, spin_axis,
						apex, carry, total,
						offline_str, off_dir
					]
					csv_lines.append(",".join(row))

	return "\n".join(csv_lines) + "\n"


## Generates a CSV of player profile historical club averages.
static func generate_profile_csv(player_name: String) -> String:
	var headers = [
		"Player", "Club", "Shot Count", "Avg Carry (yds)", "Avg Total (yds)",
		"Avg Speed (mph)", "Avg Total Spin (rpm)", "Avg Offline (yds)", "Avg +/- Target (yds)"
	]
	var csv_lines: PackedStringArray = []
	csv_lines.append(",".join(headers))

	var stats_path = "user://player_club_stats.json"
	if not FileAccess.file_exists(stats_path):
		return "\n".join(csv_lines) + "\n"

	var file = FileAccess.open(stats_path, FileAccess.READ)
	if file == null:
		return "\n".join(csv_lines) + "\n"

	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return "\n".join(csv_lines) + "\n"

	var player_club_stats = json.data.get(player_name, {})
	if player_club_stats.is_empty():
		return "\n".join(csv_lines) + "\n"

	var club_order = ["Dr", "3w", "5w", "2H", "3H", "4H", "1i", "2i", "3i", "4i", "5i", "6i", "7i", "8i", "9i", "Pw", "Gw", "Sw", "Lw", "Pt"]
	for c in player_club_stats.keys():
		if not club_order.has(c):
			club_order.append(c)

	for club in club_order:
		if not player_club_stats.has(club) or player_club_stats[club].is_empty():
			continue

		var club_shots = player_club_stats[club]
		var sum_carry := 0.0
		var sum_total := 0.0
		var sum_speed := 0.0
		var sum_spin := 0.0
		var sum_offline := 0.0
		var sum_target_diff := 0.0
		var valid_target_diff_count := 0

		for shot in club_shots:
			sum_carry += float(shot.get("CarryDistance", 0.0))
			var t_dist = float(shot.get("TotalDistance", shot.get("CarryDistance", 0.0)))
			sum_total += t_dist
			sum_speed += float(shot.get("Speed", 0.0))
			sum_spin += float(shot.get("TotalSpin", 0.0))

			var s_dist = absf(float(shot.get("SideDistance", 0.0)))
			if s_dist > 100.0 or (t_dist > 15.0 and s_dist > t_dist * 1.2):
				s_dist = 0.0
			sum_offline += s_dist

			var target_dist = float(shot.get("TargetDistance", 0.0))
			if target_dist > 0.0:
				sum_target_diff += (t_dist - target_dist)
				valid_target_diff_count += 1

		var cnt = club_shots.size()
		var avg_carry_yds = (sum_carry / cnt) * 1.09361
		var avg_total_yds = (sum_total / cnt) * 1.09361
		var avg_speed_mph = sum_speed / cnt
		var avg_spin_rpm = sum_spin / cnt
		var avg_offline_yds = (sum_offline / cnt) * 1.09361
		var avg_target_diff_yds = ((sum_target_diff / valid_target_diff_count) * 1.09361) if valid_target_diff_count > 0 else 0.0

		var target_diff_str = ("%+.1f" % avg_target_diff_yds) if valid_target_diff_count > 0 else "---"

		var row = [
			csv_escape(player_name),
			csv_escape(club),
			str(cnt),
			"%.1f" % avg_carry_yds,
			"%.1f" % avg_total_yds,
			"%.1f" % avg_speed_mph,
			"%.0f" % avg_spin_rpm,
			"%.1f" % avg_offline_yds,
			target_diff_str
		]
		csv_lines.append(",".join(row))

	return "\n".join(csv_lines) + "\n"


## Saves the CSV text to user://exports/ and copies to Documents/HeckleGolfSim/Exports/ if accessible.
## Returns the absolute filesystem path to the primary CSV file.
static func save_csv_file(filename: String, csv_text: String) -> String:
	# Ensure user://exports exists
	DirAccess.make_dir_recursive_absolute("user://exports")
	var user_file_path = "user://exports/" + filename
	var f = FileAccess.open(user_file_path, FileAccess.WRITE)
	if f != null:
		f.store_string(csv_text)
		f.close()

	var primary_path = ProjectSettings.globalize_path(user_file_path)

	# Also attempt to save a copy in Documents/HeckleGolfSim/Exports for easy user discovery
	var docs_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if not docs_dir.is_empty() and DirAccess.dir_exists_absolute(docs_dir):
		var target_dir = docs_dir.path_join("HeckleGolfSim").path_join("Exports")
		DirAccess.make_dir_recursive_absolute(target_dir)
		var doc_path = target_dir.path_join(filename)
		var doc_f = FileAccess.open(doc_path, FileAccess.WRITE)
		if doc_f != null:
			doc_f.store_string(csv_text)
			doc_f.close()

	return primary_path


## Builds an RFC 822 / MIME multipart .eml file content with an attached CSV and UTF-8 body.
static func create_eml_content(to_email: String, subject: String, body_text: String, attachment_filename: String, csv_content: String) -> String:
	var boundary = "----=_Part_HeckleGolf_" + str(Time.get_unix_time_from_system()).replace(".", "")
	var base64_data = Marshalls.utf8_to_base64(csv_content)

	# Chunk base64 into standard 76-character lines
	var chunked_b64 := ""
	var pos := 0
	var total_len := base64_data.length()
	while pos < total_len:
		var take_len = mini(76, total_len - pos)
		chunked_b64 += base64_data.substr(pos, take_len) + "\r\n"
		pos += take_len

	var eml := ""
	eml += "X-Unsent: 1\r\n"
	if not to_email.strip_edges().is_empty():
		eml += "To: %s\r\n" % to_email.strip_edges()
	eml += "Subject: %s\r\n" % subject
	eml += "MIME-Version: 1.0\r\n"
	eml += "Content-Type: multipart/mixed; boundary=\"%s\"\r\n" % boundary
	eml += "\r\n"

	# Part 1: Email Body Text
	eml += "--%s\r\n" % boundary
	eml += "Content-Type: text/plain; charset=UTF-8\r\n"
	eml += "Content-Transfer-Encoding: 8bit\r\n"
	eml += "\r\n"
	eml += body_text.replace("\r\n", "\n").replace("\n", "\r\n") + "\r\n"
	eml += "\r\n"

	# Part 2: CSV Attachment
	eml += "--%s\r\n" % boundary
	eml += "Content-Type: text/csv; name=\"%s\"\r\n" % attachment_filename
	eml += "Content-Transfer-Encoding: base64\r\n"
	eml += "Content-Disposition: attachment; filename=\"%s\"\r\n" % attachment_filename
	eml += "\r\n"
	eml += chunked_b64
	eml += "\r\n"
	eml += "--%s--\r\n" % boundary

	return eml


## Saves an .eml draft file to user://exports/ and returns the absolute global path.
static func save_eml_file(filename: String, eml_text: String) -> String:
	DirAccess.make_dir_recursive_absolute("user://exports")
	var user_file_path = "user://exports/" + filename
	var f = FileAccess.open(user_file_path, FileAccess.WRITE)
	if f != null:
		f.store_string(eml_text)
		f.close()
	return ProjectSettings.globalize_path(user_file_path)


## Complete pipeline to export CSV, create .eml draft, open email client, and provide fallback.
static func export_and_email(to_email: String, subject: String, body_summary: String, attachment_basename: String, csv_content: String) -> void:
	var csv_filename = attachment_basename + ".csv"
	var eml_filename = attachment_basename + ".eml"

	# 1. Save CSV file
	var csv_global_path = save_csv_file(csv_filename, csv_content)

	# 2. Add local CSV attachment reference note to email body
	var full_body = body_summary
	full_body += "\nATTACHED FILE:\n"
	full_body += "--------------------------------------------------\n"
	full_body += "Detailed golf telemetry attached: %s\n" % csv_filename
	full_body += "Local file saved at:\n%s\n" % csv_global_path

	# 3. Create .eml draft with attachment
	var eml_content = create_eml_content(to_email, subject, full_body, csv_filename, csv_content)
	var eml_global_path = save_eml_file(eml_filename, eml_content)

	# 4. Copy CSV path to clipboard so user can easily paste if needed
	DisplayServer.clipboard_set(csv_global_path)

	# 5. Open the .eml file in default email client (Outlook, Thunderbird, Mail, etc.)
	var open_err = OS.shell_open(eml_global_path)
	if open_err == OK:
		print("[GolfDataExporter] Successfully opened email draft: %s" % eml_global_path)
	else:
		# Fallback to mailto if .eml cannot be opened by OS
		print("[GolfDataExporter] .eml shell_open returned code %d, falling back to mailto:" % open_err)
		var recipient = to_email.strip_edges()
		var mailto_url = "mailto:%s?subject=%s&body=%s" % [
			recipient,
			subject.uri_encode(),
			full_body.uri_encode()
		]
		OS.shell_open(mailto_url)
