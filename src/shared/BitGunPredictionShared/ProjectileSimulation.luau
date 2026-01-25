--[[ =========  TYPE  ========= ]]
export type ConfigType = {
	Origin: Vector3,
	Direction: Vector3,
	Speed: number,
	Lifetime: number,
	StartTime: number?,
	OnStep: (startCF: CFrame, endCF: CFrame) -> boolean,
	OnFinish: () -> nil,
	BulletKey: string,
	SimulationType: string
}


local ProjectileSimulation = {}

--[[ =========  SERVICES  ========= ]]
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--[[ =========  CONSTANTS  ========= ]]
local GRAVITY = Vector3.new(0, -196.2/4, 0)

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

local function ProcessCatchUp(origin, unitDir, speed, startTime, trajectoryCalculator, onStep, onFinish)
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
		config.StartTime, 
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
	
	table.insert(ActiveProjectiles, bullet)
	
	if config.BulletKey then
		ProjectileKeyMap[config.BulletKey] = bullet
	end
end

-- function ProjectileSimulation.Linear(origin: Vector3, direction: Vector3, speed: number, lifetime: number, startTime: number?, onStep, onFinish, bulletKey: string?)
-- 	local unitDir = direction.Unit
	
-- 	local didHit, startPos, startDir, timePassed = ProcessCatchUp(origin, unitDir, speed, startTime, Linear, onStep, onFinish)
	
-- 	if didHit then
-- 		return 
-- 	end

-- 	local bullet = {
-- 		Key = bulletKey,
-- 		Origin = origin,
-- 		InitialDirection = unitDir,
-- 		CurrentPos = startPos,
-- 		Direction = startDir,
-- 		Speed = speed,
-- 		Lifetime = lifetime,
-- 		ElapsedTime = timePassed,
-- 		OnStep = onStep,
-- 		OnFinish = onFinish,
-- 		Removed = false,
-- 		TrajectoryCalculator = TrajectoryCalculator.Linear,
-- 	}
	
-- 	table.insert(ActiveProjectiles, bullet)
	
-- 	if bulletKey then
-- 		ProjectileKeyMap[bulletKey] = bullet
-- 	end
-- end

-- function ProjectileSimulation.Exponential(origin: Vector3, direction: Vector3, speed: number, lifetime: number, startTime: number?, onStep, onFinish, bulletKey: string?)
-- 	local unitDir = direction.Unit
	
-- 	local didHit, startPos, startDir, timePassed = ProcessCatchUp(origin, unitDir, speed, startTime, Exponential, onStep, onFinish)
	
-- 	if didHit then
-- 		return 
-- 	end

-- 	local bullet = {
-- 		Key = bulletKey,
-- 		Origin = origin,
-- 		InitialDirection = unitDir,
-- 		CurrentPos = startPos,
-- 		Direction = startDir,
-- 		Speed = speed,
-- 		Lifetime = lifetime,
-- 		ElapsedTime = timePassed,
-- 		OnStep = onStep,
-- 		OnFinish = onFinish,
-- 		Removed = false,
-- 		TrajectoryCalculator = Exponential,
-- 	}
	
-- 	table.insert(ActiveProjectiles, bullet)
	
-- 	if bulletKey then
-- 		ProjectileKeyMap[bulletKey] = bullet
-- 	end
-- end

function ProjectileSimulation.StopProjectile(bulletKey: string)
	local bullet = ProjectileKeyMap[bulletKey]
	if not bullet then return false end
	
	if bullet.OnFinish then bullet.OnFinish() end
	bullet.Removed = true
	ProjectileKeyMap[bulletKey] = nil
	return true
end

return ProjectileSimulation