--[[
	last edited: 25/01/2026
	by: RiseBit, discord: risebit
--]]

local HumanoidTracker = {}

--[[ =========  SERVICES  ========= ]]
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--[[ =========  CONSTANTS  ========= ]]
local HISTORY_DURATION = 1
local RECORD_INTERVAL = 1/60

--[[ =========  VARIABLES  ========= ]]
local History = {}
local LastRecordTime = 0
local IsRunning = false

--[[ =========  HELPER FUNCTION  ========= ]]
local function RecordPositions()
	local now = Workspace:GetServerTimeNow()
	
	if now - LastRecordTime < RECORD_INTERVAL then return end
	LastRecordTime = now
	
	local cutoffTime = now - HISTORY_DURATION
	
	for _, character in pairs(Workspace:GetDescendants()) do
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then continue end
		
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then continue end
		
		local id = character
		
		if not History[id] then
			History[id] = {}
		end
		
		table.insert(History[id], {
			time = now,
			cframe = rootPart.CFrame
		})
		
		while #History[id] > 0 and History[id][1].time < cutoffTime do
			table.remove(History[id], 1)
		end
	end
	
	-- Cleanup invalid/destroyed characters
	for character, records in pairs(History) do
		if not character:IsDescendantOf(Workspace) then
			History[character] = nil
		elseif #records == 0 then
			History[character] = nil
		end
	end
end

--[[ =========  PUBLIC FUNCTION  ========= ]]

function HumanoidTracker.Start()
	if IsRunning then return end
	IsRunning = true
	
	RunService.Heartbeat:Connect(RecordPositions)
end

function HumanoidTracker.GetCFrameAtTime(character, targetTime)
	if not character then return nil end
	
	local records = History[character]
	if not records or #records == 0 then
		return character:GetPivot()
	end
	
	if targetTime <= records[1].time then
		return records[1].cframe
	end
	
	if targetTime >= records[#records].time then
		return records[#records].cframe
	end
	
	for i = 1, #records - 1 do
		local currD = records[i]
		local nextD = records[i + 1]
		
		if targetTime >= currD.time and targetTime <= nextD.time then
			local alpha = (targetTime - currD.time) / (nextD.time - currD.time)
			return currD.cframe:Lerp(nextD.cframe, alpha)
		end
	end
	
	return records[#records].cframe
end

function HumanoidTracker.GetHistory(character)
	if not character then return nil end
	return History[character]
end

function HumanoidTracker.RewindAll(targetTime, excludeCharacter)
	local originalPositions = {}
	
	for character, _ in pairs(History) do
		if character == excludeCharacter then continue end
		if not character:IsDescendantOf(Workspace) then continue end
		
		originalPositions[character] = character:GetPivot()
		
		local historicalCFrame = HumanoidTracker.GetCFrameAtTime(character, targetTime)
		if historicalCFrame then
			character:PivotTo(historicalCFrame)
		end
	end
	
	return originalPositions
end

function HumanoidTracker.RestoreAll(originalPositions)
	for character, cframe in pairs(originalPositions) do
		if character:IsDescendantOf(Workspace) then
			character:PivotTo(cframe)
		end
	end
end

--[[ =========  DEBUG VISUALIZATION  ========= ]]
function HumanoidTracker.DrawDebugSphere(position, color, duration)
	local sphere = Instance.new("Part")
	sphere.Name = "DebugSphere"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(2, 2, 2)
	sphere.Position = position
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.Transparency = 0.5
	sphere.Color = color
	sphere.Material = Enum.Material.Neon
	sphere.Parent = Workspace
	
	task.delay(duration or 1, function()
		sphere:Destroy()
	end)
	
	return sphere
end

function HumanoidTracker.VisualizeHistory(character, color, duration)
	local records = History[character]
	if not records then return end
	
	for _, record in ipairs(records) do
		HumanoidTracker.DrawDebugSphere(record.cframe.Position, color or Color3.fromRGB(255, 100, 100), duration or 1)
	end
end

function HumanoidTracker.DrawDebugLine(startPos, endPos, color, duration)
	local distance = (endPos - startPos).Magnitude
	local midPoint = (startPos + endPos) / 2
	
	local line = Instance.new("Part")
	line.Name = "DebugLine"
	line.Size = Vector3.new(0.1, 0.1, distance)
	line.CFrame = CFrame.lookAt(midPoint, endPos)
	line.Anchored = true
	line.CanCollide = false
	line.Transparency = 0.3
	line.Color = color
	line.Material = Enum.Material.Neon
	line.Parent = Workspace
	
	task.delay(duration or 1, function()
		line:Destroy()
	end)
	
	return line
end

return HumanoidTracker
