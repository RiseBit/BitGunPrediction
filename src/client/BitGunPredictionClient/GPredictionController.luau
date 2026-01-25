local GPredictionController = {}

--[[ =========  SERVICES  ========= ]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

--[[ =========  MODULE  ========= ]]
local BitGunPredictionShared = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BitGunPredictionShared")
local Config = require(BitGunPredictionShared.Config)
local ProjectileSimulation = require(BitGunPredictionShared.ProjectileSimulation)
local Comm = require(BitGunPredictionShared.Packages.Comm)

--[[ =========  VARIABLES  ========= ]]
local isInit = false
local clientEvent, clientHitEvent
local shotIndex = 0
local MAX_SHOT_INDEX = 255

--[[ =========  PUBLIC FUNCTION  ========= ]]
function GPredictionController.GlobalInit(visualOnStep, visualOnFinish, replicatedHitOnStep)
	if isInit then return end
	isInit = true
	
	ProjectileSimulation.Start()
	
	local clientComm = Comm.ClientComm.new(Config.EventParent, false, Config.EventName)
	clientEvent = clientComm:GetSignal(Config.EventName)
	clientHitEvent = clientComm:GetSignal(Config.HitEventName)
	
	clientEvent:Connect(function(player, origin, direction, speed, lifetime, timestamp, shotId, simType)

		local bulletKey = player.UserId .. "_" .. shotId
		
		local function onStepWrapper(startCF, endCF)
			if visualOnStep then
				visualOnStep(startCF, endCF, player, bulletKey)
			end
			
			if replicatedHitOnStep then
				return replicatedHitOnStep(startCF, endCF, player)
			end
			
			return false
		end

		ProjectileSimulation.Create({
			Origin = origin,
			Direction = direction,
			Speed = speed,
			Lifetime = lifetime,
			StartTime = timestamp,
			OnStep = onStepWrapper,
			OnFinish = function()
				if visualOnFinish then
					visualOnFinish(bulletKey)
				end
			end,
			BulletKey = bulletKey,
			SimulationType = simType
		})
	end)
	
	clientHitEvent:Connect(function(shooterPlayer, hitPart, hitPosition, shotId, simType)
		local bulletKey = shooterPlayer.UserId .. "_" .. shotId
		ProjectileSimulation.StopProjectile(bulletKey)
	end)
end

function GPredictionController.FireProjectile(origin, direction, speed, lifetime, simType, visualOnStep, visualOnFinish)
	if not isInit then warn("GPredictionController not initialized!") return end
	
	local now = Workspace:GetServerTimeNow()
	shotIndex = (shotIndex % MAX_SHOT_INDEX) + 1
	local shotId = shotIndex
	local hasHit = false

	ProjectileSimulation.Create({
		Origin = origin,
		Direction = direction,
		Speed = speed,
		Lifetime = lifetime,
		StartTime = now,
		OnStep = function(startCF, endCF)
			if hasHit then return true end
			
			local result = nil
			if visualOnStep then 
				result = visualOnStep(startCF, endCF, Players.LocalPlayer) 
			end
			if result and typeof(result) == "RaycastResult" then
				hasHit = true
				clientHitEvent:Fire(result.Instance, result.Position, Workspace:GetServerTimeNow(), shotId, simType, speed)
				return result
			end
			return nil
		end, 
		OnFinish = visualOnFinish,
		BulletKey = shotId,
		SimulationType = simType
	})

	clientEvent:Fire(origin, direction, speed, lifetime, now, shotId, simType)
end

return GPredictionController