using System;
using System.Text;
using Godot;
using Godot.Collections;
using TcpServerPeer = Godot.TcpServer;

namespace LaunchMonitors.Common.Tcp;

public partial class TcpServer : Node
{
	private const int MaxTcpBuffer = 65536;
	private const int DefaultPort = 49152;
	private const string DefaultAddress = "*";

	private readonly TcpServerPeer _tcpServer = new();
	private StreamPeerTcp? _tcpConnection;
	private bool _tcpConnected;
	private string _tcpString = string.Empty;
	private Dictionary _shotData = new();
	private readonly Dictionary _resp200 = new() { { "Code", 200 } };
	private readonly Dictionary _resp50x = new() { { "Code", 501 }, { "Message", "Failure Occured" } };

	[Signal]
	public delegate void HitBallEventHandler(Dictionary data);

	[Signal]
	public delegate void ServerStatusChangedEventHandler(bool isListening, string host, int port, string error);

	[Export]
	public int Port { get; set; } = DefaultPort;

	[Export]
	public string BindAddress { get; set; } = DefaultAddress;

	public bool IsListening => _tcpServer.IsListening();
	public string LastError { get; private set; } = string.Empty;

	public override void _Ready()
	{
		CallDeferred(MethodName.ListenDeferred);
	}

	private void ListenDeferred()
	{
		if (!GodotObject.IsInstanceValid(this) || !IsInsideTree())
		{
			return;
		}

		var parent = GetParent();
		if (parent != null)
		{
			if (Name == "TcpServer" && parent.HasNode("TCPServer"))
			{
				GD.Print("[TcpServer] Detected duplicate node. Skipping port binding.");
				return;
			}
		}

		LoadConfiguredEndpoint();
		ListenOnEndpoint(Port, BindAddress);
	}

	public override void _ExitTree()
	{
		Shutdown();
	}

	public override void _Process(double delta)
	{
		if (!_tcpConnected)
		{
			_tcpConnection = _tcpServer.TakeConnection();
			if (_tcpConnection != null)
			{
				GD.Print($"We have a tcp connection at {_tcpConnection.GetConnectedHost()}");
				_tcpConnected = true;
			}

			return;
		}

		if (_tcpConnection == null)
		{
			_tcpConnected = false;
			return;
		}

		_tcpConnection.Poll();
		var status = _tcpConnection.GetStatus();
		if (status == StreamPeerTcp.Status.None)
		{
			_tcpConnected = false;
			GD.Print("tcp disconnected");
			return;
		}

		if (status != StreamPeerTcp.Status.Connected)
		{
			return;
		}

		var bytesAvailable = (int)_tcpConnection.GetAvailableBytes();
		if (bytesAvailable <= 0)
		{
			return;
		}

		if (bytesAvailable > MaxTcpBuffer)
		{
			GD.PushWarning($"TCP payload too large ({bytesAvailable} bytes), dropping");
			_ = _tcpConnection.GetUtf8String(bytesAvailable);
			respond_error(413, "Payload too large");
			return;
		}

		_tcpString = _tcpConnection.GetUtf8String(bytesAvailable);
		var json = new Json();
		if (json.Parse(_tcpString) != Error.Ok)
		{
			respond_error(501, "Bad JSON data");
			return;
		}

		var data = json.GetData();
		if (data.VariantType != Variant.Type.Dictionary)
		{
			respond_error(501, "Expected JSON object");
			return;
		}

		_shotData = data.AsGodotDictionary();
		GD.Print($"Launch monitor payload: {_tcpString}");

		if (_shotData.TryGetValue("ShotDataOptions", out var shotDataOptionsVar)
			&& shotDataOptionsVar.VariantType == Variant.Type.Dictionary)
		{
			var shotDataOptions = shotDataOptionsVar.AsGodotDictionary();
			if (shotDataOptions.TryGetValue("ContainsBallData", out var containsBallDataVar)
				&& containsBallDataVar.VariantType == Variant.Type.Bool
				&& (bool)containsBallDataVar
				&& _shotData.TryGetValue("BallData", out var ballDataVar)
				&& ballDataVar.VariantType == Variant.Type.Dictionary)
			{
				var hitData = ballDataVar.AsGodotDictionary().Duplicate();
				if (_shotData.TryGetValue("ClubData", out var clubDataVar)
					&& clubDataVar.VariantType == Variant.Type.Dictionary)
				{
					var clubData = clubDataVar.AsGodotDictionary();
					foreach (var kvp in clubData)
					{
						hitData[kvp.Key] = kvp.Value;
					}
					if (clubData.TryGetValue("Speed", out var cs)) hitData["ClubSpeed"] = cs;
					if (clubData.TryGetValue("AngleOfAttack", out var aoa)) hitData["AttackAngle"] = aoa;
					if (clubData.TryGetValue("FaceToTarget", out var ft)) hitData["FaceAngle"] = ft;
					if (clubData.TryGetValue("Path", out var cp)) hitData["ClubPath"] = cp;
					if (clubData.TryGetValue("FaceToPath", out var ftp)) hitData["FaceToPath"] = ftp;
					if (clubData.TryGetValue("SmashFactor", out var sf)) hitData["SmashFactor"] = sf;
					if (clubData.TryGetValue("DynamicLoft", out var dl)) hitData["DynamicLoft"] = dl;
				}

				EmitSignal(SignalName.HitBall, hitData);
				return;
			}
		}

		respond_error(501, "Missing or invalid shot data");
	}

	public void respond_error(int code, string message)
	{
		if (_tcpConnection == null)
		{
			return;
		}

		_tcpConnection.Poll();
		var status = _tcpConnection.GetStatus();
		if (status == StreamPeerTcp.Status.None)
		{
			_tcpConnected = false;
			return;
		}

		if (status != StreamPeerTcp.Status.Connected)
		{
			return;
		}

		_resp50x["Code"] = code;
		_resp50x["Message"] = message;
		_tcpConnection.PutData(Encoding.ASCII.GetBytes(Json.Stringify(_resp50x)));
	}

	public void _on_golf_ball_good_data()
	{
		if (_tcpConnection == null)
		{
			return;
		}

		_tcpConnection.Poll();
		var status = _tcpConnection.GetStatus();
		if (status == StreamPeerTcp.Status.None)
		{
			_tcpConnected = false;
			return;
		}

		if (status == StreamPeerTcp.Status.Connected)
		{
			_tcpConnection.PutData(Encoding.ASCII.GetBytes(Json.Stringify(_resp200)));
		}
	}

	public void _on_player_bad_data()
	{
		respond_error(501, "Invalid ball data");
	}

	public void LoadConfiguredEndpoint()
	{
		try
		{
			var tree = GetTree();
			if (tree != null)
			{
				var root = tree.Root;
				if (root != null && root.HasNode("GlobalSettings"))
				{
					var globalSettings = root.GetNode("GlobalSettings");
					var rangeSettings = globalSettings?.Get("range_settings").AsGodotObject();
					if (rangeSettings != null)
					{
						var portObj = rangeSettings.Get("tcp_server_port").AsGodotObject();
						if (portObj != null)
						{
							var p = portObj.Get("value").AsInt32();
							if (p >= 1 && p <= 65535)
							{
								Port = p;
							}
						}

						var ipObj = rangeSettings.Get("tcp_server_ip").AsGodotObject();
						if (ipObj != null)
						{
							var ip = ipObj.Get("value").AsString();
							if (!string.IsNullOrWhiteSpace(ip))
							{
								BindAddress = ip.Trim();
							}
						}

						return;
					}
				}
			}
		}
		catch (Exception ex)
		{
			GD.PushWarning($"[TcpServer] Could not read settings from GlobalSettings: {ex.Message}");
		}

		// Fallback to reading directly from global_settings.cfg
		var config = new ConfigFile();
		if (config.Load("user://global_settings.cfg") == Error.Ok)
		{
			if (config.HasSectionKey("range_settings", "tcp_server_port"))
			{
				var p = config.GetValue("range_settings", "tcp_server_port", DefaultPort).AsInt32();
				if (p >= 1 && p <= 65535)
				{
					Port = p;
				}
			}
			if (config.HasSectionKey("range_settings", "tcp_server_ip"))
			{
				var ip = config.GetValue("range_settings", "tcp_server_ip", DefaultAddress).AsString();
				if (!string.IsNullOrWhiteSpace(ip))
				{
					BindAddress = ip.Trim();
				}
			}
		}
	}

	public void Restart(int port, string bindAddress)
	{
		Port = Math.Clamp(port, 1, 65535);
		BindAddress = string.IsNullOrWhiteSpace(bindAddress) ? DefaultAddress : bindAddress.Trim();
		ListenOnEndpoint(Port, BindAddress);
	}

	public void Restart()
	{
		LoadConfiguredEndpoint();
		ListenOnEndpoint(Port, BindAddress);
	}

	private void ListenOnEndpoint(int port, string bindAddress)
	{
		Port = Math.Clamp(port, 1, 65535);
		BindAddress = string.IsNullOrWhiteSpace(bindAddress) ? DefaultAddress : bindAddress.Trim();

		if (_tcpServer.IsListening())
		{
			_tcpServer.Stop();
		}

		if (_tcpConnection != null)
		{
			_tcpConnection.DisconnectFromHost();
			_tcpConnection = null;
			_tcpConnected = false;
		}

		LastError = string.Empty;
		var error = _tcpServer.Listen((ushort)Port, BindAddress);
		if (error != Error.Ok)
		{
			LastError = $"Failed to bind to {BindAddress}:{Port} ({error})";
			GD.PushError($"[TcpServer] TCP server failed to listen on {BindAddress}:{Port}. Error: {error}");

			// Fallback: If custom bind address failed and wasn't "*", try binding to "*" on the same port
			if (BindAddress != "*" && BindAddress != "0.0.0.0")
			{
				GD.PushWarning($"[TcpServer] Retrying port {Port} on wildcard address '*'...");
				error = _tcpServer.Listen((ushort)Port, "*");
				if (error == Error.Ok)
				{
					BindAddress = "*";
					LastError = string.Empty;
					GD.Print($"[TcpServer] Successfully bound fallback on *:{Port}");
				}
				else
				{
					LastError = $"Failed to bind to *:{Port} ({error})";
				}
			}
		}
		else
		{
			GD.Print($"[TcpServer] Listening for GSPro / external launch monitor connections on {BindAddress}:{Port}");
		}

		EmitSignal(SignalName.ServerStatusChanged, _tcpServer.IsListening(), BindAddress, Port, LastError);
	}

	public Dictionary GetServerInfo()
	{
		return new Dictionary
		{
			{ "is_listening", _tcpServer.IsListening() },
			{ "port", Port },
			{ "bind_address", BindAddress },
			{ "last_error", LastError }
		};
	}

	private void Shutdown()
	{
		if (_tcpConnection != null)
		{
			_tcpConnection.DisconnectFromHost();
			_tcpConnection = null;
		}

		_tcpConnected = false;
		_shotData.Clear();
		_tcpString = string.Empty;

		if (_tcpServer.IsListening())
		{
			_tcpServer.Stop();
		}
	}
}
