--[[
	last edited: 25/01/2026
	by: RiseBit, discord: risebit
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = {}

Config.EventParent = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BitGunPredictionShared")
Config.EventName = "BitGunPredictionEvent"
Config.EventRateLimit = .01
Config.HitEventName = "BitGunPredictionHitEvent"
Config.HitEventRateLimit = .01
Config.HitAckEventName = "BitGunPredictionHitAckEvent"

return Config