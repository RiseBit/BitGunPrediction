local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = {}

Config.EventParent = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BitGunPredictionShared")
Config.EventName = "BitGunPredictionEvent"
Config.EventRateLimit = .05
Config.HitEventName = "BitGunPredictionHitEvent"
Config.HitEventRateLimit = .05

return Config