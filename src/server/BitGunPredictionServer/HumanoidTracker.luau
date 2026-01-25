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
		
		local id = character
		
		if not History[id] then
			History[id] = {}
		end
		
		table.insert(History[id], {
			time = now,
			cframe = character:GetPivot() or character.CFrame
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

function HumanoidTracker.GetPositionAtTime(character, targetTime)
	if not character then return nil end
	
	local records = History[character]
	
	if not records or #records == 0 then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			return root.Position
		end
		return nil
	end
	
	if targetTime <= records[1].time then
		return records[1].cframe.Position
	end
	
	if targetTime >= records[#records].time then
		return records[#records].cframe.Position
	end
	
	for i = 1, #records - 1 do
		local currD = records[i]
		local nextD = records[i + 1]
		
		-- find the Middle point in it :>
		if targetTime >= currD.time and targetTime <= nextD.time then
			local alpha = (targetTime - currD.time) / (nextD.time - currD.time)
			return currD.cframe.Position:Lerp(nextD.cframe.Position, alpha)
		end
	end
	
	return records[#records].cframe.Position
end

function HumanoidTracker.GetHistory(character)
	if not character then return nil end
	return History[character]
end

return HumanoidTracker
