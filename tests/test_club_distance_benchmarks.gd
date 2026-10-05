extends SceneTree

# test_club_distance_benchmarks.gd
# Unit and regression test verifying that aerodynamic flight trajectory calculations
# produce realistic carry distances across 12 distinct club categories and ~10 shot variants
# per club (speed, launch angle/dynamic loft, and spin rate).
# Also defines expected target rollout and total distances for future physics verification.

const CARRY_TOLERANCE_YD: float = 3.5

const BENCHMARK_CASES = [
	# --- DRIVER (10 Variants) ---
	{"club": "Driver", "label": "Senior / Ultra-Slow", "speed": 105.0, "vla": 16.0, "spin": 3100.0, "exp_carry": 152.8, "target_roll": 20.7, "target_total": 173.5},
	{"club": "Driver", "label": "Slow / High HCP Low Launch", "speed": 115.0, "vla": 11.5, "spin": 3300.0, "exp_carry": 166.9, "target_roll": 25.8, "target_total": 192.8},
	{"club": "Driver", "label": "Slow / High HCP High Launch", "speed": 115.0, "vla": 16.0, "spin": 2900.0, "exp_carry": 172.9, "target_roll": 18.9, "target_total": 191.8},
	{"club": "Driver", "label": "High HCP Standard", "speed": 125.0, "vla": 13.0, "spin": 3200.0, "exp_carry": 195.9, "target_roll": 20.6, "target_total": 216.5},
	{"club": "Driver", "label": "Mid HCP Low Spin Sweep", "speed": 135.0, "vla": 12.0, "spin": 2300.0, "exp_carry": 219.2, "target_roll": 23.4, "target_total": 242.6},
	{"club": "Driver", "label": "Mid HCP Standard Baseline", "speed": 135.0, "vla": 14.0, "spin": 2800.0, "exp_carry": 217.6, "target_roll": 18.2, "target_total": 235.8},
	{"club": "Driver", "label": "Low HCP / Scratch", "speed": 150.0, "vla": 12.5, "spin": 2400.0, "exp_carry": 257.4, "target_roll": 18.8, "target_total": 276.2},
	{"club": "Driver", "label": "PGA Tour Average", "speed": 171.0, "vla": 10.9, "spin": 2550.0, "exp_carry": 286.5, "target_roll": 15.1, "target_total": 301.7},
	{"club": "Driver", "label": "Tour High Bomber", "speed": 175.0, "vla": 13.0, "spin": 2200.0, "exp_carry": 311.2, "target_roll": 12.9, "target_total": 324.1},
	{"club": "Driver", "label": "Extreme Fast Long Drive", "speed": 190.0, "vla": 11.0, "spin": 2050.0, "exp_carry": 336.2, "target_roll": 14.1, "target_total": 350.3},

	# --- 3-WOOD (10 Variants) ---
	{"club": "3-Wood", "label": "Senior / Slow Off Turf", "speed": 100.0, "vla": 14.0, "spin": 4000.0, "exp_carry": 137.1, "target_roll": 21.3, "target_total": 158.3},
	{"club": "3-Wood", "label": "High HCP Off Deck", "speed": 112.0, "vla": 10.5, "spin": 4200.0, "exp_carry": 161.5, "target_roll": 22.7, "target_total": 184.2},
	{"club": "3-Wood", "label": "High HCP Teed Up", "speed": 118.0, "vla": 13.5, "spin": 3600.0, "exp_carry": 181.2, "target_roll": 19.5, "target_total": 200.8},
	{"club": "3-Wood", "label": "Mid HCP Off Deck", "speed": 125.0, "vla": 11.0, "spin": 3900.0, "exp_carry": 194.7, "target_roll": 20.1, "target_total": 214.8},
	{"club": "3-Wood", "label": "Mid HCP Teed Up", "speed": 130.0, "vla": 12.5, "spin": 3400.0, "exp_carry": 208.0, "target_roll": 18.8, "target_total": 226.8},
	{"club": "3-Wood", "label": "Low HCP Compressed", "speed": 142.0, "vla": 11.5, "spin": 3500.0, "exp_carry": 233.1, "target_roll": 16.2, "target_total": 249.4},
	{"club": "3-Wood", "label": "LPGA Tour Average", "speed": 132.0, "vla": 11.2, "spin": 3450.0, "exp_carry": 210.8, "target_roll": 20.6, "target_total": 231.4},
	{"club": "3-Wood", "label": "PGA Tour Average", "speed": 160.0, "vla": 10.7, "spin": 3655.0, "exp_carry": 267.9, "target_roll": 11.6, "target_total": 279.5},
	{"club": "3-Wood", "label": "High Spin Balloon", "speed": 130.0, "vla": 15.0, "spin": 4800.0, "exp_carry": 205.8, "target_roll": 8.9, "target_total": 214.7},
	{"club": "3-Wood", "label": "Tour Fast Stinger", "speed": 162.0, "vla": 8.5, "spin": 3200.0, "exp_carry": 270.3, "target_roll": 19.6, "target_total": 289.9},

	# --- 5-WOOD (10 Variants) ---
	{"club": "5-Wood", "label": "Slow Swing Speed", "speed": 95.0, "vla": 15.0, "spin": 4600.0, "exp_carry": 123.3, "target_roll": 22.8, "target_total": 146.1},
	{"club": "5-Wood", "label": "High HCP Typical", "speed": 105.0, "vla": 12.5, "spin": 4800.0, "exp_carry": 145.2, "target_roll": 22.4, "target_total": 167.5},
	{"club": "5-Wood", "label": "Mid HCP Standard", "speed": 118.0, "vla": 13.5, "spin": 4400.0, "exp_carry": 180.4, "target_roll": 15.6, "target_total": 196.0},
	{"club": "5-Wood", "label": "Mid HCP High Launch", "speed": 120.0, "vla": 15.5, "spin": 4300.0, "exp_carry": 186.4, "target_roll": 12.2, "target_total": 198.6},
	{"club": "5-Wood", "label": "Low HCP Piercing", "speed": 132.0, "vla": 12.0, "spin": 4200.0, "exp_carry": 211.1, "target_roll": 14.7, "target_total": 225.8},
	{"club": "5-Wood", "label": "LPGA Tour Average", "speed": 126.0, "vla": 12.8, "spin": 4100.0, "exp_carry": 199.0, "target_roll": 15.4, "target_total": 214.5},
	{"club": "5-Wood", "label": "PGA Tour Average", "speed": 153.0, "vla": 12.1, "spin": 4322.0, "exp_carry": 250.9, "target_roll": 9.0, "target_total": 259.9},
	{"club": "5-Wood", "label": "Approach to Green (Soft)", "speed": 120.0, "vla": 14.5, "spin": 4500.0, "exp_carry": 185.7, "target_roll": 7.5, "target_total": 193.2},
	{"club": "5-Wood", "label": "Tour High Land Angle", "speed": 155.0, "vla": 13.5, "spin": 4600.0, "exp_carry": 251.7, "target_roll": 7.5, "target_total": 259.2},
	{"club": "5-Wood", "label": "Low Hook Runner", "speed": 125.0, "vla": 9.5, "spin": 3300.0, "exp_carry": 184.8, "target_roll": 27.4, "target_total": 212.2},

	# --- HYBRID (10 Variants) ---
	{"club": "Hybrid", "label": "Senior Swing", "speed": 92.0, "vla": 16.0, "spin": 4800.0, "exp_carry": 115.7, "target_roll": 24.0, "target_total": 139.7},
	{"club": "Hybrid", "label": "High HCP Standard", "speed": 102.0, "vla": 14.0, "spin": 4900.0, "exp_carry": 140.4, "target_roll": 21.9, "target_total": 162.3},
	{"club": "Hybrid", "label": "Mid HCP Typical (4H)", "speed": 112.0, "vla": 14.5, "spin": 4600.0, "exp_carry": 166.8, "target_roll": 15.7, "target_total": 182.6},
	{"club": "Hybrid", "label": "Mid HCP Strong (3H)", "speed": 118.0, "vla": 13.0, "spin": 4300.0, "exp_carry": 180.2, "target_roll": 16.6, "target_total": 196.8},
	{"club": "Hybrid", "label": "Low HCP Solid", "speed": 128.0, "vla": 13.5, "spin": 4400.0, "exp_carry": 202.9, "target_roll": 12.7, "target_total": 215.5},
	{"club": "Hybrid", "label": "LPGA Tour Average", "speed": 119.0, "vla": 13.8, "spin": 4600.0, "exp_carry": 182.8, "target_roll": 14.3, "target_total": 197.1},
	{"club": "Hybrid", "label": "PGA Tour Average", "speed": 147.5, "vla": 12.8, "spin": 4587.0, "exp_carry": 239.3, "target_roll": 8.5, "target_total": 247.8},
	{"club": "Hybrid", "label": "Green Landing (Mid HCP)", "speed": 112.0, "vla": 15.0, "spin": 4700.0, "exp_carry": 167.2, "target_roll": 7.5, "target_total": 174.7},
	{"club": "Hybrid", "label": "Green Landing (Tour)", "speed": 145.0, "vla": 13.5, "spin": 4800.0, "exp_carry": 233.6, "target_roll": 7.5, "target_total": 241.1},
	{"club": "Hybrid", "label": "Low Bullet Stinger", "speed": 125.0, "vla": 10.0, "spin": 3800.0, "exp_carry": 192.6, "target_roll": 22.6, "target_total": 215.2},

	# --- 4-IRON (10 Variants) ---
	{"club": "4-Iron", "label": "High HCP Thin Strike", "speed": 95.0, "vla": 11.0, "spin": 3800.0, "exp_carry": 122.6, "target_roll": 26.6, "target_total": 149.2},
	{"club": "4-Iron", "label": "High HCP Typical", "speed": 102.0, "vla": 13.0, "spin": 4400.0, "exp_carry": 140.3, "target_roll": 21.9, "target_total": 162.2},
	{"club": "4-Iron", "label": "Mid HCP Typical", "speed": 112.0, "vla": 12.5, "spin": 4300.0, "exp_carry": 164.9, "target_roll": 19.4, "target_total": 184.4},
	{"club": "4-Iron", "label": "Mid HCP Compressed", "speed": 118.0, "vla": 11.5, "spin": 4600.0, "exp_carry": 178.2, "target_roll": 18.5, "target_total": 196.7},
	{"club": "4-Iron", "label": "Low HCP Pure", "speed": 126.0, "vla": 11.8, "spin": 4500.0, "exp_carry": 197.4, "target_roll": 15.3, "target_total": 212.7},
	{"club": "4-Iron", "label": "PGA Tour Average", "speed": 139.0, "vla": 11.0, "spin": 4782.0, "exp_carry": 223.1, "target_roll": 12.2, "target_total": 235.3},
	{"club": "4-Iron", "label": "Approach to Green (Mid)", "speed": 112.0, "vla": 13.5, "spin": 4500.0, "exp_carry": 166.1, "target_roll": 8.6, "target_total": 174.7},
	{"club": "4-Iron", "label": "Approach to Green (Tour)", "speed": 139.0, "vla": 11.5, "spin": 4800.0, "exp_carry": 223.3, "target_roll": 7.5, "target_total": 230.8},
	{"club": "4-Iron", "label": "High Spin Mishit", "speed": 105.0, "vla": 15.5, "spin": 5500.0, "exp_carry": 152.4, "target_roll": 20.3, "target_total": 172.7},
	{"club": "4-Iron", "label": "Tour Long Stinger", "speed": 142.0, "vla": 9.0, "spin": 3900.0, "exp_carry": 229.8, "target_roll": 19.8, "target_total": 249.6},

	# --- 5-IRON (10 Variants) ---
	{"club": "5-Iron", "label": "Slow Swing Speed", "speed": 88.0, "vla": 15.0, "spin": 4600.0, "exp_carry": 102.9, "target_roll": 25.7, "target_total": 128.7},
	{"club": "5-Iron", "label": "High HCP Sweeper", "speed": 98.0, "vla": 14.5, "spin": 4500.0, "exp_carry": 131.3, "target_roll": 21.8, "target_total": 153.0},
	{"club": "5-Iron", "label": "Mid HCP Typical", "speed": 106.0, "vla": 13.8, "spin": 4900.0, "exp_carry": 150.0, "target_roll": 20.4, "target_total": 170.4},
	{"club": "5-Iron", "label": "Mid HCP Compressed", "speed": 112.0, "vla": 12.8, "spin": 5200.0, "exp_carry": 164.4, "target_roll": 19.6, "target_total": 184.0},
	{"club": "5-Iron", "label": "Low HCP Solid", "speed": 120.0, "vla": 13.0, "spin": 5200.0, "exp_carry": 184.5, "target_roll": 14.8, "target_total": 199.2},
	{"club": "5-Iron", "label": "LPGA Tour Average", "speed": 113.0, "vla": 13.5, "spin": 5100.0, "exp_carry": 167.9, "target_roll": 17.5, "target_total": 185.4},
	{"club": "5-Iron", "label": "PGA Tour Average", "speed": 134.5, "vla": 12.1, "spin": 5280.0, "exp_carry": 213.8, "target_roll": 10.5, "target_total": 224.3},
	{"club": "5-Iron", "label": "Approach to Green (Mid)", "speed": 106.0, "vla": 14.5, "spin": 5000.0, "exp_carry": 150.7, "target_roll": 9.8, "target_total": 160.5},
	{"club": "5-Iron", "label": "Approach to Green (Tour)", "speed": 134.5, "vla": 12.5, "spin": 5400.0, "exp_carry": 213.3, "target_roll": 4.5, "target_total": 217.8},
	{"club": "5-Iron", "label": "Low Hook Runner", "speed": 110.0, "vla": 10.5, "spin": 3800.0, "exp_carry": 159.8, "target_roll": 25.2, "target_total": 185.0},

	# --- 6-IRON (10 Variants) ---
	{"club": "6-Iron", "label": "Slow Swing Speed", "speed": 84.0, "vla": 17.0, "spin": 5100.0, "exp_carry": 99.4, "target_roll": 13.0, "target_total": 112.4},
	{"club": "6-Iron", "label": "High HCP Low Spin", "speed": 92.0, "vla": 16.5, "spin": 4600.0, "exp_carry": 117.3, "target_roll": 11.2, "target_total": 128.5},
	{"club": "6-Iron", "label": "High HCP Typical", "speed": 96.0, "vla": 16.0, "spin": 5300.0, "exp_carry": 125.8, "target_roll": 11.7, "target_total": 137.5},
	{"club": "6-Iron", "label": "Mid HCP Typical", "speed": 102.0, "vla": 15.5, "spin": 5600.0, "exp_carry": 143.7, "target_roll": 11.0, "target_total": 154.7},
	{"club": "6-Iron", "label": "Mid HCP Compressed", "speed": 108.0, "vla": 14.5, "spin": 5900.0, "exp_carry": 158.0, "target_roll": 10.5, "target_total": 168.5},
	{"club": "6-Iron", "label": "Low HCP Solid", "speed": 116.0, "vla": 14.8, "spin": 6100.0, "exp_carry": 173.5, "target_roll": 8.1, "target_total": 181.6},
	{"club": "6-Iron", "label": "LPGA Tour Average", "speed": 108.0, "vla": 15.2, "spin": 5750.0, "exp_carry": 159.5, "target_roll": 9.8, "target_total": 169.3},
	{"club": "6-Iron", "label": "PGA Tour Average", "speed": 129.5, "vla": 14.1, "spin": 6204.0, "exp_carry": 207.4, "target_roll": 4.5, "target_total": 211.9},
	{"club": "6-Iron", "label": "Fairway Lie (Mid)", "speed": 102.0, "vla": 15.5, "spin": 5600.0, "exp_carry": 143.7, "target_roll": 21.9, "target_total": 165.6},
	{"club": "6-Iron", "label": "Delofted Stinger", "speed": 112.0, "vla": 11.5, "spin": 4800.0, "exp_carry": 163.0, "target_roll": 20.6, "target_total": 183.5},

	# --- 7-IRON (10 Variants) ---
	{"club": "7-Iron", "label": "Senior / Slow", "speed": 80.0, "vla": 20.0, "spin": 4800.0, "exp_carry": 96.4, "target_roll": 11.4, "target_total": 107.7},
	{"club": "7-Iron", "label": "High HCP Low Spin", "speed": 90.0, "vla": 20.0, "spin": 4400.0, "exp_carry": 118.8, "target_roll": 8.8, "target_total": 127.6},
	{"club": "7-Iron", "label": "High HCP Standard", "speed": 95.0, "vla": 19.0, "spin": 5100.0, "exp_carry": 130.1, "target_roll": 9.4, "target_total": 139.5},
	{"club": "7-Iron", "label": "Mid HCP Typical", "speed": 102.0, "vla": 18.0, "spin": 5500.0, "exp_carry": 142.9, "target_roll": 8.4, "target_total": 151.4},
	{"club": "7-Iron", "label": "Mid HCP Compressed", "speed": 106.0, "vla": 16.5, "spin": 6200.0, "exp_carry": 154.4, "target_roll": 9.2, "target_total": 163.5},
	{"club": "7-Iron", "label": "Low HCP Solid", "speed": 114.0, "vla": 16.8, "spin": 6700.0, "exp_carry": 168.4, "target_roll": 7.5, "target_total": 175.9},
	{"club": "7-Iron", "label": "LPGA Tour Average", "speed": 103.0, "vla": 17.1, "spin": 6400.0, "exp_carry": 146.9, "target_roll": 9.1, "target_total": 155.9},
	{"club": "7-Iron", "label": "PGA Tour Average", "speed": 123.5, "vla": 16.3, "spin": 7124.0, "exp_carry": 192.6, "target_roll": 4.5, "target_total": 197.1},
	{"club": "7-Iron", "label": "Fairway Lie (Mid HCP)", "speed": 102.0, "vla": 18.0, "spin": 5500.0, "exp_carry": 142.9, "target_roll": 16.9, "target_total": 159.8},
	{"club": "7-Iron", "label": "Flier from Rough (Low Spin)", "speed": 108.0, "vla": 17.5, "spin": 3400.0, "exp_carry": 163.7, "target_roll": 11.0, "target_total": 174.7},

	# --- 8-IRON (10 Variants) ---
	{"club": "8-Iron", "label": "Slow Swing Speed", "speed": 76.0, "vla": 21.5, "spin": 5600.0, "exp_carry": 86.4, "target_roll": 9.9, "target_total": 96.4},
	{"club": "8-Iron", "label": "High HCP Typical", "speed": 86.0, "vla": 20.5, "spin": 5900.0, "exp_carry": 105.0, "target_roll": 9.0, "target_total": 114.0},
	{"club": "8-Iron", "label": "Mid HCP Typical", "speed": 94.0, "vla": 19.5, "spin": 6500.0, "exp_carry": 122.4, "target_roll": 8.3, "target_total": 130.7},
	{"club": "8-Iron", "label": "Mid HCP Compressed", "speed": 98.0, "vla": 18.0, "spin": 7100.0, "exp_carry": 129.6, "target_roll": 8.6, "target_total": 138.1},
	{"club": "8-Iron", "label": "Low HCP Solid", "speed": 106.0, "vla": 18.2, "spin": 7600.0, "exp_carry": 151.8, "target_roll": 7.2, "target_total": 159.1},
	{"club": "8-Iron", "label": "LPGA Tour Average", "speed": 97.0, "vla": 19.0, "spin": 7100.0, "exp_carry": 127.9, "target_roll": 8.0, "target_total": 135.9},
	{"club": "8-Iron", "label": "PGA Tour Average", "speed": 117.5, "vla": 18.1, "spin": 8078.0, "exp_carry": 176.5, "target_roll": 4.5, "target_total": 181.0},
	{"club": "8-Iron", "label": "Flier Rough Release", "speed": 98.0, "vla": 19.0, "spin": 4200.0, "exp_carry": 139.0, "target_roll": 7.4, "target_total": 146.4},
	{"club": "8-Iron", "label": "Punch Knockdown", "speed": 92.0, "vla": 14.5, "spin": 6200.0, "exp_carry": 113.8, "target_roll": 13.2, "target_total": 127.0},
	{"club": "8-Iron", "label": "High Spin Balloon", "speed": 95.0, "vla": 22.5, "spin": 8600.0, "exp_carry": 121.3, "target_roll": 7.5, "target_total": 128.8},

	# --- 9-IRON (10 Variants) ---
	{"club": "9-Iron", "label": "Slow Swing Speed", "speed": 72.0, "vla": 23.0, "spin": 6200.0, "exp_carry": 78.0, "target_roll": 9.4, "target_total": 87.3},
	{"club": "9-Iron", "label": "High HCP Typical", "speed": 82.0, "vla": 22.0, "spin": 6800.0, "exp_carry": 99.8, "target_roll": 8.6, "target_total": 108.4},
	{"club": "9-Iron", "label": "Mid HCP Typical", "speed": 88.0, "vla": 21.0, "spin": 7300.0, "exp_carry": 108.0, "target_roll": 8.0, "target_total": 116.0},
	{"club": "9-Iron", "label": "Mid HCP Compressed", "speed": 92.0, "vla": 19.5, "spin": 7900.0, "exp_carry": 113.5, "target_roll": 8.7, "target_total": 122.2},
	{"club": "9-Iron", "label": "Low HCP Solid", "speed": 100.0, "vla": 20.2, "spin": 8300.0, "exp_carry": 131.3, "target_roll": 7.5, "target_total": 138.8},
	{"club": "9-Iron", "label": "LPGA Tour Average", "speed": 91.0, "vla": 21.2, "spin": 7650.0, "exp_carry": 112.8, "target_roll": 7.7, "target_total": 120.5},
	{"club": "9-Iron", "label": "PGA Tour Average", "speed": 111.5, "vla": 20.4, "spin": 8793.0, "exp_carry": 161.1, "target_roll": 4.5, "target_total": 165.6},
	{"club": "9-Iron", "label": "Flier Rough (Low Spin)", "speed": 92.0, "vla": 21.0, "spin": 4800.0, "exp_carry": 124.3, "target_roll": 8.3, "target_total": 132.6},
	{"club": "9-Iron", "label": "Knockdown Trajectory", "speed": 88.0, "vla": 16.5, "spin": 7100.0, "exp_carry": 106.3, "target_roll": 11.5, "target_total": 117.8},
	{"club": "9-Iron", "label": "Full High Arc", "speed": 95.0, "vla": 23.5, "spin": 9100.0, "exp_carry": 121.4, "target_roll": 4.5, "target_total": 125.9},

	# --- PITCHING WEDGE (PW) (10 Variants) ---
	{"club": "PW", "label": "Slow Swing Speed", "speed": 66.0, "vla": 26.0, "spin": 7000.0, "exp_carry": 67.9, "target_roll": 8.5, "target_total": 76.4},
	{"club": "PW", "label": "High HCP Typical", "speed": 74.0, "vla": 25.5, "spin": 7600.0, "exp_carry": 82.1, "target_roll": 7.6, "target_total": 89.7},
	{"club": "PW", "label": "Mid HCP Typical", "speed": 82.0, "vla": 24.5, "spin": 8200.0, "exp_carry": 99.1, "target_roll": 7.5, "target_total": 106.6},
	{"club": "PW", "label": "Mid HCP Compressed", "speed": 86.0, "vla": 23.0, "spin": 8800.0, "exp_carry": 103.1, "target_roll": 7.4, "target_total": 110.6},
	{"club": "PW", "label": "Low HCP Solid", "speed": 94.0, "vla": 23.8, "spin": 9100.0, "exp_carry": 119.6, "target_roll": 4.5, "target_total": 124.1},
	{"club": "PW", "label": "LPGA Tour Average", "speed": 84.0, "vla": 24.5, "spin": 8400.0, "exp_carry": 103.2, "target_roll": 7.5, "target_total": 110.7},
	{"club": "PW", "label": "PGA Tour Average", "speed": 103.5, "vla": 24.2, "spin": 9316.0, "exp_carry": 137.7, "target_roll": 0.5, "target_total": 138.2},
	{"club": "PW", "label": "3/4 Control Shot", "speed": 72.0, "vla": 22.0, "spin": 7500.0, "exp_carry": 75.8, "target_roll": 10.1, "target_total": 86.0},
	{"club": "PW", "label": "Flier from Rough", "speed": 85.0, "vla": 24.5, "spin": 5200.0, "exp_carry": 108.0, "target_roll": 7.5, "target_total": 115.5},
	{"club": "PW", "label": "Full Pro Strike", "speed": 106.0, "vla": 23.5, "spin": 9800.0, "exp_carry": 148.2, "target_roll": 2.0, "target_total": 150.2},

	# --- SAND / LOB WEDGE (SW/LW) (10 Variants) ---
	{"club": "SW/LW", "label": "Full SW Senior", "speed": 55.0, "vla": 32.0, "spin": 6800.0, "exp_carry": 52.2, "target_roll": 7.5, "target_total": 59.7},
	{"club": "SW/LW", "label": "Full SW High HCP", "speed": 65.0, "vla": 31.0, "spin": 7800.0, "exp_carry": 61.3, "target_roll": 4.5, "target_total": 65.8},
	{"club": "SW/LW", "label": "Full SW Mid HCP", "speed": 72.0, "vla": 30.0, "spin": 8800.0, "exp_carry": 73.6, "target_roll": 4.5, "target_total": 78.1},
	{"club": "SW/LW", "label": "Full SW Tour Average", "speed": 87.0, "vla": 29.5, "spin": 9950.0, "exp_carry": 101.0, "target_roll": 0.5, "target_total": 101.5},
	{"club": "SW/LW", "label": "Full LW Tour Average (60°)", "speed": 76.0, "vla": 33.0, "spin": 9500.0, "exp_carry": 79.2, "target_roll": 0.5, "target_total": 79.7},
	{"club": "SW/LW", "label": "50-Yard Pitch Shot", "speed": 45.0, "vla": 28.0, "spin": 5800.0, "exp_carry": 34.9, "target_roll": 10.5, "target_total": 45.4},
	{"club": "SW/LW", "label": "30-Yard Pitch Shot", "speed": 34.0, "vla": 29.0, "spin": 4200.0, "exp_carry": 20.1, "target_roll": 11.3, "target_total": 31.5},
	{"club": "SW/LW", "label": "High Flop Shot", "speed": 40.0, "vla": 46.0, "spin": 5200.0, "exp_carry": 29.6, "target_roll": 4.5, "target_total": 34.1},
	{"club": "SW/LW", "label": "Low Spinner Check Pitch", "speed": 48.0, "vla": 24.0, "spin": 6800.0, "exp_carry": 38.5, "target_roll": 12.4, "target_total": 50.9},
	{"club": "SW/LW", "label": "Sand Bunker Blast (Firm)", "speed": 35.0, "vla": 38.0, "spin": 4500.0, "exp_carry": 23.4, "target_roll": 7.3, "target_total": 30.7}
]

func _initialize() -> void:
	print("================================================================================")
	print("Running Club Distance Aerodynamic Benchmarks Unit Test")
	print("Total Benchmark Cases: %d" % BENCHMARK_CASES.size())
	print("================================================================================")

	var adapter = load("res://addons/openfairway/physics/PhysicsAdapter.cs").new()
	if adapter == null:
		push_error("Could not load PhysicsAdapter.cs")
		quit(1)
		return

	var passed_count := 0
	var failed_count := 0

	for item in BENCHMARK_CASES:
		var shot = {
			"BallData": {
				"Speed": item["speed"],
				"VLA": item["vla"],
				"HLA": 0.0,
				"TotalSpin": item["spin"],
				"BackSpin": item["spin"],
				"SideSpin": 0.0
			}
		}

		var res = adapter.SimulateCarryOnlyFromJson(shot)
		var simulated_carry: float = float(res.get("carry_yd", 0.0))
		var diff = absf(simulated_carry - item["exp_carry"])

		if diff > CARRY_TOLERANCE_YD:
			push_error("FAIL: [%s] %s | Sim Carry: %.1f yd vs Exp: %.1f yd (Diff: %.1f yd > Tol: %.1f yd)" % [
				item["club"], item["label"], simulated_carry, item["exp_carry"], diff, CARRY_TOLERANCE_YD
			])
			failed_count += 1
		else:
			passed_count += 1

	print("\n--- Test Results Summary ---")
	print("Passed: %d / %d" % [passed_count, BENCHMARK_CASES.size()])
	print("Failed: %d" % failed_count)

	if failed_count == 0:
		print("ALL %d CLUB DISTANCE BENCHMARKS PASSED! 🎉" % BENCHMARK_CASES.size())
		quit(0)
	else:
		push_error("Some distance benchmarks failed tolerance check.")
		quit(1)
