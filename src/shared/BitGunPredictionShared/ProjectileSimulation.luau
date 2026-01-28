--[[
	last edited: 28/01/2026
	by: RiseBit, discord: risebit
--]]

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

export type ConfigType = {
	Origin: Vector3,
	Direction: Vector3,
	Speed: number,
	Lifetime: number,
	StartTime: number?,
	OnStep: (startCF: CFrame, endCF: CFrame) -> boolean,
	OnFinish: () -> nil,
	BulletKey: string,
	SimulationType: string,
	TrajectoryArgs: TrajectoryArgs?,
}


local ProjectileSimulation = {}

--[[ =========  SERVICES  ========= ]]
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--[[ =========  CONSTANTS  ========= ]]
local GRAVITY = Vector3.new(0, -196.2/2, 0)

--[[ =========  VARIABLES  ========= ]]
local ActiveProjectiles = {}
local ProjectileKeyMap = {}
local IsRunning = false

--[[ =========  TRAJECTORY CALCULATORS  ========= ]]
local TrajectoryCalculator = {}

function TrajectoryCalculator.Linear(bullet)
	local newPos = bullet.Origin + (bullet.InitialDirection * bullet.Speed * bullet.ElapsedTime)
	return newPos, bullet.InitialDirection
end

function TrajectoryCalculator.Exponential(bullet)
	local t = bullet.ElapsedTime
	local initialVelocity = bullet.InitialDirection * bullet.Speed
	local newPos = bullet.Origin + (initialVelocity * t) + (0.5 * GRAVITY * t * t)
	
	local currentVelocity = initialVelocity + (GRAVITY * t)
	local direction = currentVelocity.Unit
	
	return newPos, direction
end

function TrajectoryCalculator.SineWave(bullet)
	local t = bullet.ElapsedTime
	local amplitude = bullet.Amplitude or 3
	local frequency = bullet.Frequency or 5
	
	local forward = bullet.InitialDirection
	local right = forward:Cross(Vector3.yAxis).Unit
	if right.Magnitude < 0.01 then
		right = forward:Cross(Vector3.xAxis).Unit
	end
	
	local basePos = bullet.Origin + (forward * bullet.Speed * t)
	local sineOffset = right * math.sin(t * frequency) * amplitude
	local newPos = basePos + sineOffset
	
	local cosComponent = math.cos(t * frequency) * amplitude * frequency
	local tangent = (forward * bullet.Speed + right * cosComponent).Unit
	
	return newPos, tangent
end

function TrajectoryCalculator.Spiral(bullet)
	local t = bullet.ElapsedTime
	local radius = bullet.Radius or 2
	local rotationSpeed = bullet.RotationSpeed or 8
	
	local forward = bullet.InitialDirection
	local right = forward:Cross(Vector3.yAxis).Unit
	if right.Magnitude < 0.01 then
		right = forward:Cross(Vector3.xAxis).Unit
	end
	local up = right:Cross(forward).Unit
	
	local basePos = bullet.Origin + (forward * bullet.Speed * t)
	local spiralOffset = (right * math.cos(t * rotationSpeed) + up * math.sin(t * rotationSpeed)) * radius
	local newPos = basePos + spiralOffset
	
	local tangentSpiral = (-right * math.sin(t * rotationSpeed) + up * math.cos(t * rotationSpeed)) * radius * rotationSpeed
	local tangent = (forward * bullet.Speed + tangentSpiral).Unit
	
	return newPos, tangent
end

function TrajectoryCalculator.Decelerate(bullet)
	local t = bullet.ElapsedTime
	local decayRate = bullet.DecayRate or 2
	
	local distance = bullet.Speed * (1 - math.exp(-decayRate * t)) / decayRate
	local newPos = bullet.Origin + (bullet.InitialDirection * distance)
	
	return newPos, bullet.InitialDirection
end

function TrajectoryCalculator.Accelerate(bullet)
	local t = bullet.ElapsedTime
	local acceleration = bullet.Acceleration or 50
	
	local distance = (bullet.Speed * t) + (0.5 * acceleration * t * t)
	local newPos = bullet.Origin + (bullet.InitialDirection * distance)
	
	return newPos, bullet.InitialDirection
end

function TrajectoryCalculator.Boomerang(bullet)
	local t = bullet.ElapsedTime
	local peakTime = bullet.PeakTime or (bullet.Lifetime / 2)
	
	local progress
	if t < peakTime then
		progress = t / peakTime
		progress = progress * (2 - progress)
	else
		local returnProgress = (t - peakTime) / peakTime
		progress = 1 - (returnProgress * returnProgress)
	end
	
	local maxDistance = bullet.Speed * peakTime * 0.5
	local newPos = bullet.Origin + (bullet.InitialDirection * maxDistance * progress)
	
	local direction = bullet.InitialDirection
	if t >= peakTime then
		direction = -bullet.InitialDirection
	end
	
	return newPos, direction
end

function TrajectoryCalculator.QuadraticBezier(bullet)
	local t = bullet.ElapsedTime / bullet.Lifetime
	t = math.clamp(t, 0, 1)
	
	local p0 = bullet.Origin
	local totalDistance = bullet.Speed * bullet.Lifetime
	local p2 = bullet.ControlPoint2 or (bullet.Origin + bullet.InitialDirection * totalDistance)
	
	local controlOffset = bullet.ControlOffset or Vector3.new(totalDistance * 0.3, 0, 0)
	local p1 = bullet.ControlPoint1 or (p0 + bullet.InitialDirection * totalDistance * 0.5 + controlOffset)
	
	local oneMinusT = 1 - t
	local newPos = (oneMinusT * oneMinusT) * p0 
		+ (2 * oneMinusT * t) * p1 
		+ (t * t) * p2
	
	local tangent = (2 * oneMinusT * (p1 - p0) + 2 * t * (p2 - p1)).Unit
	
	return newPos, tangent
end

function TrajectoryCalculator.CubicBezier(bullet)
	local t = bullet.ElapsedTime / bullet.Lifetime
	t = math.clamp(t, 0, 1)
	
	local p0 = bullet.Origin
	local totalDistance = bullet.Speed * bullet.Lifetime
	local p3 = bullet.ControlPoint3 or (bullet.Origin + bullet.InitialDirection * totalDistance)
	
	local controlOffset1 = bullet.ControlOffset1 or Vector3.new(totalDistance * 0.25, 0, 0)
	local controlOffset2 = bullet.ControlOffset2 or Vector3.new(-totalDistance * 0.25, 0, 0)
	local p1 = bullet.ControlPoint1 or (p0 + bullet.InitialDirection * totalDistance * 0.33 + controlOffset1)
	local p2 = bullet.ControlPoint2 or (p0 + bullet.InitialDirection * totalDistance * 0.66 + controlOffset2)
	
	local oneMinusT = 1 - t
	local oneMinusT2 = oneMinusT * oneMinusT
	local oneMinusT3 = oneMinusT2 * oneMinusT
	local t2 = t * t
	local t3 = t2 * t
	
	local newPos = oneMinusT3 * p0 
		+ (3 * oneMinusT2 * t) * p1 
		+ (3 * oneMinusT * t2) * p2 
		+ t3 * p3
	
	local tangent = (
		3 * oneMinusT2 * (p1 - p0) 
		+ 6 * oneMinusT * t * (p2 - p1) 
		+ 3 * t2 * (p3 - p2)
	).Unit
	
	return newPos, tangent
end

--[[ =========  HELPER FUNCTION  ========= ]]
local function StepSimulation(dt)
	for i = #ActiveProjectiles, 1, -1 do
		local bullet = ActiveProjectiles[i]
		
		if bullet.Removed then
			if bullet.Key then
				ProjectileKeyMap[bullet.Key] = nil
			end
			table.remove(ActiveProjectiles, i)
			continue
		end
		
		local previousPos = bullet.CurrentPos
		bullet.ElapsedTime += dt
		
		local newPos, newDirection = bullet.TrajectoryCalculator(bullet)
		
		bullet.CurrentPos = newPos
		bullet.Direction = newDirection

		local startCFrame = CFrame.lookAt(previousPos, previousPos + bullet.Direction)
		local endCFrame = CFrame.lookAt(newPos, newPos + bullet.Direction)
		
		local didHit = false
		if bullet.OnStep then
			didHit = bullet.OnStep(startCFrame, endCFrame)
		end

		if didHit or bullet.ElapsedTime >= bullet.Lifetime then
			if bullet.OnFinish then bullet.OnFinish() end
			if bullet.Key then
				ProjectileKeyMap[bullet.Key] = nil
			end
			table.remove(ActiveProjectiles, i)
		end
	end
end

local function ProcessCatchUp(origin, unitDir, speed, lifetime, startTime, trajectoryCalculator, onStep, onFinish)
	local now = Workspace:GetServerTimeNow()
	local actualStartTime = startTime or now
	local timePassed = math.max(0, now - actualStartTime)
	
	local currentPos = origin
	local currentDir = unitDir

	if timePassed > 0 then
		local tempBullet = {
			Origin = origin,
			InitialDirection = unitDir,
			Speed = speed,
			Lifetime = lifetime,
			ElapsedTime = timePassed,
		}
		
		local catchUpPos, catchUpDir = trajectoryCalculator(tempBullet)

		local startCF = CFrame.lookAt(origin, origin + unitDir)
		local endCF = CFrame.lookAt(catchUpPos, catchUpPos + catchUpDir)

		if onStep then
			local didHit = onStep(startCF, endCF)
			
			if didHit then
				if onFinish then onFinish() end
				return true, nil, nil, timePassed
			end
		end

		currentPos = catchUpPos
		currentDir = catchUpDir
	end
	
	return false, currentPos, currentDir, timePassed
end

--[[ =========  PUBLIC FUNCTION  ========= ]]

function ProjectileSimulation.Start()
	if IsRunning then return end
	IsRunning = true

	if RunService:IsServer() then
		RunService.Heartbeat:Connect(StepSimulation)
	else
		RunService.RenderStepped:Connect(StepSimulation)
	end
end

function ProjectileSimulation.Create(config: ConfigType)
	if not config.BulletKey then
		warn("BulletKey is required!")
		return
	end
	
	if not config.Origin then
		warn("Origin is required!")
		return
	end
	
	if not config.Direction then
		warn("Direction is required!")
		return
	end
	
	if not config.Speed then
		warn("Speed is required!")
		return
	end
	
	if not config.Lifetime then
		warn("Lifetime is required!")
		return
	end
	
	if not config.SimulationType then
		warn("SimulationType is required!")
		return
	end
	
	if not TrajectoryCalculator[config.SimulationType] then
		warn("SimulationType Doesnt Exist: " .. config.SimulationType)
		return
	end

	local unitDir = config.Direction.Unit
	
	local didHit, startPos, startDir, timePassed = ProcessCatchUp(
		config.Origin, 
		unitDir, 
		config.Speed, 
		config.Lifetime,
		config.StartTime or nil, 
		TrajectoryCalculator[config.SimulationType], 
		config.OnStep, 
		config.OnFinish
	)
	
	if didHit then
		return 
	end

	local bullet = {
		Key = config.BulletKey,
		Origin = config.Origin,
		InitialDirection = unitDir,
		CurrentPos = startPos,
		Direction = startDir,
		Speed = config.Speed,
		Lifetime = config.Lifetime,
		ElapsedTime = timePassed,
		OnStep = config.OnStep,
		OnFinish = config.OnFinish,
		Removed = false,
		TrajectoryCalculator = TrajectoryCalculator[config.SimulationType],
	}
	
	if config.TrajectoryArgs then
		for key, value in pairs(config.TrajectoryArgs) do
			bullet[key] = value
		end
	end
	
	table.insert(ActiveProjectiles, bullet)
	
	if config.BulletKey then
		ProjectileKeyMap[config.BulletKey] = bullet
	end
end

function ProjectileSimulation.StopProjectile(bulletKey: string)
	local bullet = ProjectileKeyMap[bulletKey]
	if not bullet then return false end
	
	if bullet.OnFinish then bullet.OnFinish() end
	bullet.Removed = true
	ProjectileKeyMap[bulletKey] = nil
	return true
end

return ProjectileSimulation