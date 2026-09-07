import socket
import json
import sys

PORT = 49152
HOST = "127.0.0.1"

# Presets of shot metrics:
# Speed in mph (will be converted in-game)
# SpinAxis (negative = hook/draw, positive = slice/fade)
# TotalSpin in rpm
# HLA in deg (horizontal launch angle, negative = left, positive = right)
# VLA in deg (vertical launch angle)
PRESETS = {
    "1": {
        "name": "Driver (Bomb) - Long straight drive",
        "BallData": {
            "Speed": 165.0,
            "SpinAxis": 0.5,
            "TotalSpin": 2200.0,
            "HLA": 0.8,
            "VLA": 11.5,
            "ShotType": "drive"
        }
    },
    "2": {
        "name": "Wedge (Approach) - Short iron to green",
        "BallData": {
            "Speed": 85.0,
            "SpinAxis": -1.0,
            "TotalSpin": 7500.0,
            "HLA": -0.5,
            "VLA": 28.0,
            "ShotType": "iron"
        }
    },
    "3": {
        "name": "Slice - Massive curve right",
        "BallData": {
            "Speed": 145.0,
            "SpinAxis": 18.0,
            "TotalSpin": 3500.0,
            "HLA": 3.0,
            "VLA": 14.0,
            "ShotType": "drive"
        }
    },
    "4": {
        "name": "Hook - Massive curve left",
        "BallData": {
            "Speed": 145.0,
            "SpinAxis": -18.0,
            "TotalSpin": 3500.0,
            "HLA": -3.0,
            "VLA": 14.0,
            "ShotType": "drive"
        }
    },
    "5": {
        "name": "Wormburner - Low rolling shot",
        "BallData": {
            "Speed": 110.0,
            "SpinAxis": 0.0,
            "TotalSpin": 1800.0,
            "HLA": 0.0,
            "VLA": 2.5,
            "ShotType": "iron"
        }
    },
    "6": {
        "name": "Duff - Mis-hit going nowhere",
        "BallData": {
            "Speed": 25.0,
            "SpinAxis": 5.0,
            "TotalSpin": 800.0,
            "HLA": 4.0,
            "VLA": 10.0,
            "ShotType": "iron"
        }
    },
    "7": {
        "name": "Putt (Short) - Direct roll on green",
        "BallData": {
            "Speed": 6.5,
            "SpinAxis": 0.0,
            "TotalSpin": 100.0,
            "HLA": 0.1,
            "VLA": 0.0,
            "ShotType": "putt"
        }
    },
    "8": {
        "name": "Putt (Long) - Fast roll on green",
        "BallData": {
            "Speed": 15.0,
            "SpinAxis": 0.0,
            "TotalSpin": 120.0,
            "HLA": -0.2,
            "VLA": 0.0,
            "ShotType": "putt"
        }
    }
}

def inject_shot():
    print("=" * 50)
    print("      HeckleLinks Shot Injection Utility")
    print("=" * 50)
    print("Select a shot type preset to inject:")
    for key, val in PRESETS.items():
        print(f"  [{key}] {val['name']}")
    print("  [9] Custom Shot (Enter custom parameters)")
    print("  [Q] Exit")
    print("-" * 50)

    choice = input("Enter choice: ").strip().lower()
    if choice == 'q':
        sys.exit(0)

    ball_data = None
    if choice in PRESETS:
        ball_data = PRESETS[choice]["BallData"]
    elif choice == '9':
        print("\nEnter custom shot parameters:")
        try:
            speed = float(input("  Speed (mph) [e.g. 150]: ") or "150")
            spin_axis = float(input("  Spin Axis (deg) [e.g. 0]: ") or "0")
            total_spin = float(input("  Total Spin (rpm) [e.g. 2500]: ") or "2500")
            hla = float(input("  Horizontal Launch Angle (deg) [e.g. 0]: ") or "0")
            vla = float(input("  Vertical Launch Angle (deg) [e.g. 12]: ") or "12")
            shot_type = input("  Shot Type (drive/iron/putt) [e.g. iron]: ").strip() or "iron"
            
            ball_data = {
                "Speed": speed,
                "SpinAxis": spin_axis,
                "TotalSpin": total_spin,
                "HLA": hla,
                "VLA": vla,
                "ShotType": shot_type
            }
        except ValueError:
            print("Invalid numeric value entered. Aborting custom shot.")
            return
    else:
        print("Invalid choice.")
        return

    # Construct the JSON wrapper expected by Godot's TcpServer
    payload = {
        "ShotDataOptions": {
            "ContainsBallData": True
        },
        "BallData": ball_data
    }

    payload_str = json.dumps(payload)
    print(f"\nConnecting to HeckleLinks on {HOST}:{PORT}...")
    
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.connect((HOST, PORT))
            print("Connected! Sending payload:")
            print(json.dumps(payload, indent=2))
            s.sendall(payload_str.encode('utf-8'))
            
            # Read confirmation code from server
            data = s.recv(1024)
            resp = json.loads(data.decode('utf-8'))
            if resp.get("Code") == 200:
                print("\n[SUCCESS] Shot injected successfully!")
            else:
                print(f"\n[ERROR] Server returned error: {resp.get('Message', 'Unknown')}")
    except ConnectionRefusedError:
        print("\n[ERROR] Connection refused! Make sure the game is running, a course/range is loaded, and the TCP Server is listening.")
    except Exception as e:
        print(f"\n[ERROR] Failed to inject shot: {e}")

if __name__ == "__main__":
    while True:
        inject_shot()
        print("\n")
