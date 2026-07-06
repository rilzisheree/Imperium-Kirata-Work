local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local CommandRemotes = {}

local function getOrCreate(name)
        local e = ReplicatedStorage:FindFirstChild(name)
        if e and e:IsA("RemoteEvent") then return e end
        e = Instance.new("RemoteEvent")
        e.Name   = name
        e.Parent = ReplicatedStorage
        return e
end

local function waitFor(name)
        local r = ReplicatedStorage:WaitForChild(name, 15)
        if not r then warn("CommandRemotes: timed out waiting for " .. name) end
        return r :: RemoteEvent
end

if RunService:IsServer() then
        CommandRemotes.CommandExecuted = getOrCreate("CmdExecuted")
        CommandRemotes.CommandFeedback = getOrCreate("CmdFeedback")
        CommandRemotes.SM              = getOrCreate("CmdSM")
        CommandRemotes.IM              = getOrCreate("CmdIM")
        CommandRemotes.Anxiety         = getOrCreate("CmdAnxiety")
        CommandRemotes.Blind           = getOrCreate("CmdBlind")
        CommandRemotes.Unblind         = getOrCreate("CmdUnblind")
        CommandRemotes.HelpRequest     = getOrCreate("CmdHelpRequest")
        CommandRemotes.HelpUIToggle    = getOrCreate("CmdHelpUIToggle")
        CommandRemotes.Notif           = getOrCreate("CmdNotif")
        CommandRemotes.WeatherOpen        = getOrCreate("CmdWeatherOpen")
        CommandRemotes.WeatherApply       = getOrCreate("CmdWeatherApply")
        CommandRemotes.WeatherSync        = getOrCreate("CmdWeatherSync")
        CommandRemotes.WeatherSetProp     = getOrCreate("CmdWeatherSetProp")
        CommandRemotes.WeatherReset       = getOrCreate("CmdWeatherReset")
        CommandRemotes.WeatherToggleEffect = getOrCreate("CmdWeatherToggleEffect")
else
        CommandRemotes.CommandExecuted = waitFor("CmdExecuted")
        CommandRemotes.CommandFeedback = waitFor("CmdFeedback")
        CommandRemotes.SM              = waitFor("CmdSM")
        CommandRemotes.IM              = waitFor("CmdIM")
        CommandRemotes.Anxiety         = waitFor("CmdAnxiety")
        CommandRemotes.Blind           = waitFor("CmdBlind")
        CommandRemotes.Unblind         = waitFor("CmdUnblind")
        CommandRemotes.HelpRequest     = waitFor("CmdHelpRequest")
        CommandRemotes.HelpUIToggle    = waitFor("CmdHelpUIToggle")
        CommandRemotes.Notif           = waitFor("CmdNotif")
        CommandRemotes.WeatherOpen        = waitFor("CmdWeatherOpen")
        CommandRemotes.WeatherApply       = waitFor("CmdWeatherApply")
        CommandRemotes.WeatherSync        = waitFor("CmdWeatherSync")
        CommandRemotes.WeatherSetProp     = waitFor("CmdWeatherSetProp")
        CommandRemotes.WeatherReset       = waitFor("CmdWeatherReset")
        CommandRemotes.WeatherToggleEffect = waitFor("CmdWeatherToggleEffect")
end

return CommandRemotes
