--[[
	last edited: 28/01/2026
	by: RiseBit, discord: risebit
--]]

local GPredictionService = {}

--[[ =========  SERVICES  ========= ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

--[[ =========  MODULE  ========= ]]
local BitGunPredictionShared = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BitGunPredictionShared")
local Checker = require(script.Parent.Checker)
local Config = require(BitGunPredictionShared.Config)
local ServerConfig = require(script.Parent.ServerConfig)
local ProjectileSimulation = require(BitGunPredictionShared.ProjectileSimulation)
local Comm = require(BitGunPredictionShared.Packages.Comm)
local Signal = require(BitGunPredictionShared.Packages.Signal)
local HumanoidTracker = require(script.Parent.HumanoidTracker)

--[[ =========  CONSTANTS  ========= ]]
local CHECK_PREFIXES = "Check"

--[[ =========  VARIABLES  ========= ]]
local isInit = false
local ActiveShots = {}

--[[ =========  EVENTS  ========= ]]
GPredictionService.OnProjectileFired = Signal.new()
GPredictionService.OnHitValidated = Signal.new()
GPredictionService.OnHitRejected = Signal.new()

--[[ =========  HELPER  ========= ]]
local function ValidateAndGetRoot(player, origin)
	if not player.Character then return nil end
	local root = player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	
	if (origin - root.Position).Magnitude > ServerConfig.MaxOriginDist then
		return nil
	end
	return root
end

local function CleanupPlayerShots(userId, maxAge)
	local playerShots = ActiveShots[userId]
	if not playerShots then return end
	
	local now = Workspace:GetServerTimeNow()
	for shotId, shotData in pairs(playerShots) do
		if now - shotData.firedAt > maxAge then
			playerShots[shotId] = nil
		end
	end
end

local function StartCleanupLoop()
	task.spawn(function()
		while true do
			task.wait(ServerConfig.ShotCleanupInterval)
			for userId, _ in pairs(ActiveShots) do
				CleanupPlayerShots(userId, ServerConfig.MaxLatencyBuffer + 5)
			end
		end
	end)
end

local function GetCharacterFromPart(part)
	local current = part
	while current do
		if current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

--[[ =========  PUBLIC FUNCTION  ========= ]]
function GPredictionService.GlobalInit(callbacks, USE_FULL_REWIND)
	if isInit then
		warn("[GPredictionService] already initialized!")
		return
	end
	isInit = true
	
	ProjectileSimulation.Start()
	HumanoidTracker.Start()
	StartCleanupLoop()

	local serverComm = Comm.ServerComm.new(Config.EventParent, Config.EventName)
	local serverEvent = serverComm:CreateSignal(Config.EventName, false, nil, nil, Config.EventRateLimit)
	local serverHitEvent = serverComm:CreateSignal(Config.HitEventName, false, nil, nil, Config.HitEventRateLimit)
	local serverHitAckEvent = serverComm:CreateSignal(Config.HitAckEventName)

	Players.PlayerRemoving:Connect(function(player)
		ActiveShots[player.UserId] = nil
	end)

	serverHitEvent:Connect(function(player, hitPart, hitPosition, clientHitTimestamp, shotId, simType, speed)
		if not hitPart or typeof(hitPart) ~= "Instance" or not hitPart:IsDescendantOf(Workspace) then
			GPredictionService.OnHitRejected:Fire(player, hitPart, hitPosition, shotId, "InvalidInstance")
			serverHitAckEvent:Fire(player, false, nil, nil, shotId)
			return
		end
		if not Checker.IsArgumentDataTypeValid(hitPosition) then
			GPredictionService.OnHitRejected:Fire(player, hitPart, hitPosition, shotId, "InvalidPosition")
			serverHitAckEvent:Fire(player, false, nil, nil, shotId)
			return
		end
		if not Checker.IsArgumentDataTypeValid(clientHitTimestamp) then
			GPredictionService.OnHitRejected:Fire(player, hitPart, hitPosition, shotId, "InvalidTimestamp")
			serverHitAckEvent:Fire(player, false, nil, nil, shotId)
			return
		end
		if not Checker.IsArgumentDataTypeValid(shotId) then
			GPredictionService.OnHitRejected:Fire(player, hitPart, hitPosition, shotId, "InvalidShotId")
			serverHitAckEvent:Fire(player, false, nil, nil, shotId)
			return
		end
		if not Checker.IsArgumentDataTypeValid(simType) then
			GPredictionService.OnHitRejected:Fire(player, hitPart, hitPosition, shotId, "InvalidSimType")
			serverHitAckEvent:Fire(player, false, nil, nil, shotId)
			return
		end

		local playerShots = ActiveShots[player.UserId]
		if not playerShots then
			GPredictionService.OnHitRejected:Fire(player, hitPart, hitPosition, shotId, "NoActiveShots")
			serverHitAckEvent:Fire(player, false, nil, nil, shotId)
			return
		end

		local shotData = playerShots[shotId]
		if not shotData then
			GPredictionService.OnHitRejected:Fire(player, hitPart, hitPosition, shotId, "ShotNotFound")
			serverHitAckEvent:Fire(player, false, nil, nil, shotId)
			return
		end

		local serverNow = Workspace:GetServerTimeNow()
		local timeSinceFired = serverNow - shotData.clientFiredAt
		local allowedTime = shotData.latency + ServerConfig.LatencyTolerance + shotData.lifetime

		if timeSinceFired > allowedTime then
			playerShots[shotId] = nil
			GPredictionService.OnHitRejected:Fire(player, hitPart, hitPosition, shotId, "TimingExpired")
			serverHitAckEvent:Fire(player, false, nil, nil, shotId)
			return
		end

		local hitCharacter = GetCharacterFromPart(hitPart)
		local originalPositions = nil
		
		if ServerConfig.UseFullRewind then
			originalPositions = HumanoidTracker.RewindAll(clientHitTimestamp, player.Character)
			
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = {player.Character}
			
			local rayResult = Workspace:Raycast(shotData.origin, shotData.direction * (shotData.speed * shotData.lifetime), rayParams)
			
			HumanoidTracker.RestoreAll(originalPositions)
			
			if not rayResult then
				playerShots[shotId] = nil
				GPredictionService.OnHitRejected:Fire(player, hitPart, hitPosition, shotId, "FullRewindMiss")
				serverHitAckEvent:Fire(player, false, nil, nil, shotId)
				return
			end
			
			local serverHitCharacter = GetCharacterFromPart(rayResult.Instance)
			if serverHitCharacter ~= hitCharacter then
				playerShots[shotId] = nil
				GPredictionService.OnHitRejected:Fire(player, hitPart, hitPosition, shotId, "CharacterMismatch")
				serverHitAckEvent:Fire(player, false, nil, nil, shotId)
				return
			end
			
			hitPart = rayResult.Instance
			hitPosition = rayResult.Position

		elseif hitCharacter then
			local historicalPosition = HumanoidTracker.GetCFrameAtTime(hitCharacter, clientHitTimestamp).Position
			if not historicalPosition then
				local root = hitCharacter:FindFirstChild("HumanoidRootPart")
				if root then
					historicalPosition = root.Position
				else
					playerShots[shotId] = nil
					GPredictionService.OnHitRejected:Fire(player, hitPart, hitPosition, shotId, "NoRootPart")
					serverHitAckEvent:Fire(player, false, nil, nil, shotId)
					return
				end
			end

			local positionError = (hitPosition - historicalPosition).Magnitude
			if positionError > ServerConfig.HitPositionTolerance then
				playerShots[shotId] = nil
				GPredictionService.OnHitRejected:Fire(player, hitPart, hitPosition, shotId, "PositionMismatch")
				serverHitAckEvent:Fire(player, false, nil, nil, shotId)
				return
			end
		end

		playerShots[shotId] = nil

		local onHitCallback = callbacks[simType]
		if onHitCallback then
			local result = {
				Instance = hitPart,
				Position = hitPosition
			}
			onHitCallback(player, result, speed)
		else
			warn("No Callback found for simType:", simType)
		end

		GPredictionService.OnHitValidated:Fire(player, hitPart, hitPosition, shotId, simType)
		
		if ServerConfig.Debug.Enabled then
			HumanoidTracker.DrawDebugSphere(hitPosition, Color3.fromRGB(0, 255, 0), ServerConfig.Debug.DebugDuration)
			if hitCharacter then
				HumanoidTracker.VisualizeHistory(hitCharacter, ServerConfig.Debug.HistoryColor, ServerConfig.Debug.DebugDuration)
			end
		end
		
		serverHitAckEvent:Fire(player, true, hitPart, hitPosition, shotId)
		serverHitEvent:FireAll(player, hitPart, hitPosition, shotId, simType)
	end)

	serverEvent:Connect(function(player, origin, direction, speed, lifetime, clientFiredAt, shotId, simType, trajectoryArgs)
		if not Checker.IsArgumentDataTypeValid(origin) then return end
		if not Checker.IsArgumentDataTypeValid(direction) then return end
		if not Checker.IsArgumentDataTypeValid(speed) then return end
		if not Checker.IsArgumentDataTypeValid(lifetime) then return end
		if not Checker.IsArgumentDataTypeValid(clientFiredAt) then return end
		if not Checker.IsArgumentDataTypeValid(shotId) then return end
		if not Checker.IsArgumentDataTypeValid(simType) then return end
		
		local root = ValidateAndGetRoot(player, origin)
		if not root then return end

        local checkCallback = callbacks[`{simType}{CHECK_PREFIXES}`]
        if checkCallback then
            if not checkCallback(player, origin, direction, speed, lifetime, clientFiredAt, simType) then return end
        end
		
		local serverNow = Workspace:GetServerTimeNow()
		local latency = serverNow - clientFiredAt
		
		if latency > ServerConfig.MaxLatencyBuffer then return end

		if not ActiveShots[player.UserId] then
			ActiveShots[player.UserId] = {}
		end
		
		ActiveShots[player.UserId][shotId] = {
			origin = origin,
			direction = direction,
			speed = speed,
			lifetime = lifetime,
			latency = latency,
			clientFiredAt = clientFiredAt,
			firedAt = serverNow
		}

		local actualStartTime = math.max(clientFiredAt, serverNow - ServerConfig.MaxLatencyBuffer)
		actualStartTime = math.min(actualStartTime, serverNow)

		if type(ProjectileSimulation) ~= "table" then
			warn("CRITICAL: ProjectileSimulation is not a table!")
			return
		end
		
		ProjectileSimulation.Create({
			Origin = origin,
			Direction = direction,
			Speed = speed,
			Lifetime = lifetime,
			StartTime = actualStartTime,
			OnStep = function(startCF, endCF)
				return false
			end,
			OnFinish = nil,
			BulletKey = shotId,
			SimulationType = simType,
			TrajectoryArgs = trajectoryArgs,
		})

		GPredictionService.OnProjectileFired:Fire(player, origin, direction, speed, simType)
		serverEvent:FireExcept(player, player, origin, direction, speed, lifetime, actualStartTime, shotId, simType, trajectoryArgs)
	end)
end

return GPredictionService