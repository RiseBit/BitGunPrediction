--[[
	last edited: 28/01/2026
	by: RiseBit, discord: risebit
--]]

local ServerConfig = {}

--[[ =========  VALIDATION THRESHOLDS  ========= ]]
ServerConfig.MaxOriginDist = 10
ServerConfig.MaxLatencyBuffer = 0.5
ServerConfig.LatencyTolerance = 0.15
ServerConfig.HitPositionTolerance = 15
ServerConfig.ShotCleanupInterval = 5

--[[ =========  REWIND SYSTEM  ========= ]]
ServerConfig.UseFullRewind = false

--[[ =========  DEBUG (Server-Side)  ========= ]]
ServerConfig.Debug = {
	Enabled = false,
	ShowHistoricalPositions = true,
	ShowServerRaycasts = true,
	HistoryColor = Color3.fromRGB(255, 100, 100),
	RaycastColor = Color3.fromRGB(100, 255, 100),
	DebugDuration = 2,
}

return ServerConfig
