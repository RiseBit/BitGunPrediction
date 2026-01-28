--[[
	last edited: 28/01/2026
	by: RiseBit, discord: risebit
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = {}

--[[ =========  NETWORK EVENTS  ========= ]]
Config.EventParent = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BitGunPredictionShared")
Config.EventName = "BitGunPredictionEvent"
Config.EventRateLimit = 0.01
Config.HitEventName = "BitGunPredictionHitEvent"
Config.HitEventRateLimit = 0.01
Config.HitAckEventName = "BitGunPredictionHitAckEvent"

--[[ =========  DEBUG (Client-Side)  ========= ]]
Config.Debug = {
	Enabled = false,
	ShowLocalRaycasts = true,
	ShowReplicatedBullets = true,
	LocalRaycastColor = Color3.fromRGB(0, 255, 0),
	ReplicatedRaycastColor = Color3.fromRGB(255, 255, 0),
	DebugDuration = 1,
}

return Config