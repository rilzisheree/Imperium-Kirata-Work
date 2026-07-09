local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local CommandRemotes = {}

local function make(name)
	local e = ReplicatedStorage:FindFirstChild(name)
	if e and e:IsA("RemoteEvent") then return e end
	e = Instance.new("RemoteEvent")
	e.Name   = name
	e.Parent = ReplicatedStorage
	return e
end

local function get(name)
	local r = ReplicatedStorage:WaitForChild(name, 15)
	if not r then warn("CommandRemotes: timed out waiting for " .. name) end
	return r :: RemoteEvent
end

-- Canonical list of every remote: key on CommandRemotes → RemoteEvent name in ReplicatedStorage.
local REMOTES = {
	CommandExecuted      = "CmdExecuted",
	CommandFeedback      = "CmdFeedback",
	SM                   = "CmdSM",
	IM                   = "CmdIM",
	Anxiety              = "CmdAnxiety",
	Blind                = "CmdBlind",
	Unblind              = "CmdUnblind",
	HelpRequest          = "CmdHelpRequest",
	HelpUIToggle         = "CmdHelpUIToggle",
	Notif                = "CmdNotif",
	WeatherOpen          = "CmdWeatherOpen",
	WeatherApply         = "CmdWeatherApply",
	WeatherSync          = "CmdWeatherSync",
	WeatherSetProp       = "CmdWeatherSetProp",
	WeatherReset         = "CmdWeatherReset",
	WeatherToggleEffect  = "CmdWeatherToggleEffect",
	WeatherClientEffect  = "CmdWeatherClientEffect",
	CountdownStart       = "CmdCountdownStart",
	CountdownStop        = "CmdCountdownStop",
	LanguageOpen         = "CmdLanguageOpen",
	LanguageGrants       = "CmdLanguageGrants",
	LanguageSelect       = "CmdLanguageSelect",
	Permissions          = "CmdPermissions",
	WaypointSet          = "CmdWaypointSet",
	WaypointClear        = "CmdWaypointClear",
	FlyEnable            = "CmdFlyEnable",
	FlyDisable           = "CmdFlyDisable",
	WatchStart           = "CmdWatchStart",
	WatchStop            = "CmdWatchStop",
	Shutdown             = "CmdShutdown",
	MusicOpen            = "CmdMusicOpen",
	MusicPlay            = "CmdMusicPlay",
	MusicStop            = "CmdMusicStop",
	MusicSync            = "CmdMusicSync",
	MusicVolume          = "CmdMusicVolume",
	MusicCommand         = "CmdMusicCommand",
	MusicSeek            = "CmdMusicSeek",
	MusicCycleState      = "CmdMusicCycleState",
	EspToggle            = "CmdEspToggle",
	PrivateServerOpen    = "CmdPSOpen",
	PrivateServerReserve = "CmdPSReserve",
	PrivateServerStatus  = "CmdPSStatus",
	PrivateServerSend    = "CmdPSSend",
	PrivateServerCancel  = "CmdPSCancel",
	ServerBringNotice    = "CmdServerBringNotice",
	StaffMode            = "CmdStaffMode",
	LowHealthIM          = "CmdLowHealthIM",
	DeathIM              = "CmdDeathIM",
	VolumeSet            = "CmdVolumeSet",
}

local fn = RunService:IsServer() and make or get
for key, name in REMOTES do
	CommandRemotes[key] = fn(name)
end

return CommandRemotes
