--[[
	last edited: 28/01/2026
	by: RiseBit, discord: risebit
--]]

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
local Signal = require(BitGunPredictionShared.Packages.Signal)

--[[ =========  VARIABLES  ========= ]]
local isInit = false
local clientEvent, clientHitEvent
local shotIndex = 0
local MAX_SHOT_INDEX = 255

--[[ =========  EVENTS  ========= ]]
GPredictionController.OnProjectileFired = Signal.new()
GPredictionController.OnHitRegistered = Signal.new()
GPredictionController.OnHitAcknowledged = Signal.new()

--[[ =========  PUBLIC FUNCTION  ========= ]]
function GPredictionController.GlobalInit(visualOnStep, visualOnFinish, onHitAcknowledge)
	if isInit then
		warn("[GPredictionController] already initialized!")
		return
	end
	isInit = true
	
	ProjectileSimulation.Start()
	
	local clientComm = Comm.ClientComm.new(Config.EventParent, false, Config.EventName)
	clientEvent = clientComm:GetSignal(Config.EventName)
	clientHitEvent = clientComm:GetSignal(Config.HitEventName)
	local clientHitAckEvent = clientComm:GetSignal(Config.HitAckEventName)
	
	clientEvent:Connect(function(player, origin, direction, speed, lifetime, timestamp, shotId, simType, trajectoryArgs)

		local bulletKey = player.UserId .. "_" .. shotId
		
		local function onStepWrapper(startCF, endCF)
			if visualOnStep then
				return visualOnStep(startCF, endCF, player, bulletKey)
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
			SimulationType = simType,
			TrajectoryArgs = trajectoryArgs,
		})
	end)
	
	clientHitEvent:Connect(function(shooterPlayer, hitPart, hitPosition, shotId, simType)
		local bulletKey = shooterPlayer.UserId .. "_" .. shotId
		ProjectileSimulation.StopProjectile(bulletKey)
	end)
	
	clientHitAckEvent:Connect(function(confirmed, hitPart, hitPosition, shotId)
		GPredictionController.OnHitAcknowledged:Fire(confirmed, hitPart, hitPosition, shotId)
		if onHitAcknowledge then
			onHitAcknowledge(confirmed, hitPart, hitPosition, shotId)
		end
	end)
end

function GPredictionController.BulletLerping(bullet, targetCF, lerpPercentage)
	local bulletPosition
	if bullet:IsA("Model") then
		bullet:PivotTo(bullet.CFrame:Lerp(targetCF, lerpPercentage or .2))
		bulletPosition = bullet:GetPivot().Position
	else
		bullet.CFrame = bullet.CFrame:Lerp(targetCF, lerpPercentage or .2)
		bulletPosition = bullet.Position
	end

    local distance = (bulletPosition - targetCF.Position).Magnitude
    if distance < 0.1 then
        if bullet:IsA("Model") then
			bullet:PivotTo(targetCF)
		else
			bullet.CFrame = targetCF
		end
        return true 
    end
    
    return false
end

--[[ =========  DEBUG HELPERS  ========= ]]
function GPredictionController.DrawDebugLine(startPos, endPos, color, duration)
	if not Config.Debug.Enabled then return nil end
	
	local distance = (endPos - startPos).Magnitude
	local midPoint = (startPos + endPos) / 2
	
	local line = Instance.new("Part")
	line.Name = "DebugLine"
	line.Size = Vector3.new(0.1, 0.1, distance)
	line.CFrame = CFrame.lookAt(midPoint, endPos)
	line.Anchored = true
	line.CanCollide = false
	line.Transparency = 0.3
	line.Color = color or Config.Debug.LocalRaycastColor
	line.Material = Enum.Material.Neon
	line.Parent = Workspace
	
	task.delay(duration or Config.Debug.DebugDuration, function()
		line:Destroy()
	end)
	
	return line
end

--[[ =========  TYPE  ========= ]]
export type TrajectoryArgs = {
	Amplitude: number?,
	Frequency: number?,
	Radius: number?,
	RotationSpeed: number?,
	DecayRate: number?,
	Acceleration: number?,
	PeakTime: number?,
	ControlPoint1: Vector3?,
	ControlPoint2: Vector3?,
	ControlOffset: Vector3?,
}

export type FireConfig = {
	Origin: Vector3,
	Direction: Vector3,
	Speed: number,
	Lifetime: number,
	SimulationType: string,
	TrajectoryArgs: TrajectoryArgs?,
	OnStep: ((startCF: CFrame, endCF: CFrame, player: Player) -> (RaycastResult | Instance | {Instance: Instance, Position: Vector3})?)?,
	OnFinish: (() -> nil)?,
}

function GPredictionController.FireProjectile(config: FireConfig)
	if not isInit then
		warn("[GPredictionController] not initialized!")
		return
	end
	
	local now = Workspace:GetServerTimeNow()
	shotIndex = (shotIndex % MAX_SHOT_INDEX) + 1
	local shotId = shotIndex
	local hasHit = false

	ProjectileSimulation.Create({
		Origin = config.Origin,
		Direction = config.Direction,
		Speed = config.Speed,
		Lifetime = config.Lifetime,
		StartTime = now,
		OnStep = function(startCF, endCF)
			if hasHit then return true end
			
			local result = nil
			if config.OnStep then 
				result = config.OnStep(startCF, endCF, Players.LocalPlayer) 
			end
			
			if result then
				local hitInstance, hitPosition
				
				if typeof(result) == "RaycastResult" then
					hitInstance = result.Instance
					hitPosition = result.Position
				elseif typeof(result) == "Instance" then
					if result:IsA("Model") then
						hitInstance = result
						hitPosition = result:GetPivot().Position
					elseif result:IsA("BasePart") then
						hitInstance = result
						hitPosition = result.Position
					end
				end
				
				if hitInstance and hitPosition then
					hasHit = true
					GPredictionController.OnHitRegistered:Fire(hitInstance, hitPosition, shotId)
					clientHitEvent:Fire(hitInstance, hitPosition, Workspace:GetServerTimeNow(), shotId, config.SimulationType, config.Speed)
					return result
				end
			end
			return nil
		end, 
		OnFinish = config.OnFinish,
		BulletKey = shotId,
		SimulationType = config.SimulationType,
		TrajectoryArgs = config.TrajectoryArgs,
	})

	clientEvent:Fire(config.Origin, config.Direction, config.Speed, config.Lifetime, now, shotId, config.SimulationType, config.TrajectoryArgs)
	GPredictionController.OnProjectileFired:Fire(config.Origin, config.Direction, shotId, config.SimulationType)
	return shotId
end

return GPredictionController