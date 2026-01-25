# BitGunPrediction

A **client-side prediction** framework for Roblox projectile-based weapons. Provides smooth, lag-free shooting mechanics with server-authoritative hit validation and anti-cheat protection.

![Roblox](https://img.shields.io/badge/Platform-Roblox-red)
![License](https://img.shields.io/badge/License-MIT-green)
![Luau](https://img.shields.io/badge/Language-Luau-blue)

---

DevForum: https://devforum.roblox.com/t/bitgunprediction-no-need-to-deal-with-annoying-client-prediction-or-lag-compensation-no-more/4294107/2

## ✨ Features

- **Client-Side Prediction** – Instant visual feedback for projectiles, no waiting for server round-trip
- **Server-Authoritative Validation** – All hits are validated server-side to prevent cheating
- **Lag Compensation** – Automatic catch-up simulation for replicated projectiles
- **8 Trajectory Types** – Linear, Exponential (gravity), Sine Wave, Spiral, Decelerate, Accelerate, Boomerang, Bezier Curves
- **Humanoid Position Tracking** – Historical position interpolation for accurate hit validation
- **Rate Limiting** – Built-in protection against event spam
- **Easy Integration** – Clean callback-based API

---

## 📦 Installation

### Using Rojo
1. Clone this repository
2. Build the place:
```bash
rojo build -o "BitGunPrediction.rbxlx"
```
3. Serve with Rojo:
```bash
rojo serve
```

### Manual Installation
Copy the `src/shared/BitGunPredictionShared`, `src/server/BitGunPredictionServer`, and `src/client/BitGunPredictionClient` folders into your project.

---

## 🚀 Quick Start

### Server Setup

```lua
local GPredictionService = require(path.to.GPredictionService)

--[[ initialize this once
    Name the Function same like the SimulationType that it was using
    As for the Validation Function, Name it same like above + "Check" Prefixes
--]]
GPredic tionService.GlobalInit({
    
    --[[
    Linear = function(shooter, result, speed)
    --]]
        local hitPart = result.Instance
        local hitPosition = result.Position
        
        -- apply dmg, vfx, sfx, your own logic here. :>
        local humanoid = hitPart.Parent:FindFirstChild("Humanoid")
        if humanoid then
            humanoid:TakeDamage(25)
        end
    end,
    
    LinearCheck = function(player, origin, direction, speed, lifetime, clientFiredAt, simType)
        -- Check if player can shoot (cooldowns, ammo, etc.)
        return true
    end
})
```

### Client Setup

```lua
local GPredictionController = require(path.to.GPredictionController)

--[[ initialize this once
    Name the Function same like the SimulationType that it was using
--]]
GPredictionController.GlobalInit(
    --[[
        visualOnStep: Called every frame for "ALL" Bullet ( Hit-Scan, Bullet Visualization, etc..)
        must return true or false indicating hit
    --]]
    function(startCF, endCF, shooter, bulletKey)
        return true
    end,
    
    -- visualOnFinish: Called when projectile Destroyed/End cause of lifetime
    function(bulletKey)
    end,
    
    --[[
        onHitAcknowledge: Called when server confirms/rejects hit
        this can be used for Reconcilation aswell
    --]]
    function(confirmed, hitPart, hitPosition, shotId)
        if confirmed then
            print("Hit confirmed!")
        else
            print("Hit rejected by server")
        end
    end
)

GPredictionController.FireProjectile(
    origin,      -- Vector3: Starting position
    direction,   -- Vector3: Direction to fire
    100,         -- number: Speed (studs/second)
    5,           -- number: Lifetime (seconds)
    "Linear",    -- string: Simulation type
    visualOnStep, -- only accept a Return of raycastResult if hit
    visualOnFinish -- wat ever
)
```

---

## � Full Example Implementation

Here is a complete example showing **Exponential trajectory**, **Client-Side Prediction with Rollback**, and **Server Validation**.

### Client (`init.client.luau`)

```lua
--[[ =========  SERVICES  ========= ]]
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

--[[ =========  MODULES  ========= ]]
local BitGunPredictionClient = script:WaitForChild("BitGunPredictionClient")
local GPredictionController = require(BitGunPredictionClient.GPredictionController)

--[[ =========  CONSTANTS  ========= ]]
local SIMULATION_TYPE = "Exponential"
local PROJECTILE_SPEED = 100
local PROJECTILE_LIFETIME = 2
local PREDICTED_DAMAGE = 25

--[[ =========  VARIABLES  ========= ]]
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local ReplicatedBullets = {}

local PendingHits = {}

--[[ =========  HELPER FUNCTIONS  ========= ]]
local function CreateBullet()
	local part = Instance.new("Part")
	part.Color = Color3.fromRGB(255, 200, 50)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Parent = Workspace
	return part
end

local function GetHumanoid(part)
	local current = part
	while current do
		local humanoid = current:FindFirstChildOfClass("Humanoid")
		if humanoid then return humanoid, current end
		current = current.Parent
	end
	return nil, nil
end

local function FireProjectile()
	local head = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
	if not head then return end
	
	local myBullet = CreateBullet()
	
	local function myOnStep(startCF, endCF)
		if myBullet and myBullet.Parent then
			myBullet.CFrame = endCF
		end
		
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {LocalPlayer.Character, myBullet}
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		
		local dir = endCF.Position - startCF.Position
		local result = Workspace:Raycast(startCF.Position, dir, rayParams)
		
		if result then
			if myBullet then myBullet:Destroy() end
			
			local humanoid = GetHumanoid(result.Instance)
			if humanoid then
				local previousHealth = humanoid.Health
				humanoid.Health -= PREDICTED_DAMAGE
				
				PendingHits[result.Instance] = {
					Humanoid = humanoid,
					PreviousHealth = previousHealth,
					PredictedHealth = humanoid.Health,
				}
			end
		end
		
		return result
	end
	
	local function myOnFinish()
		if myBullet then myBullet:Destroy() end
	end
	
	GPredictionController.FireProjectile(
		head.Position,
		Camera.CFrame.LookVector,
		PROJECTILE_SPEED,
		PROJECTILE_LIFETIME,
		SIMULATION_TYPE,
		myOnStep,
		myOnFinish
	)
end

--[[ =========  MAIN  ========= ]]
GPredictionController.GlobalInit(
	function(startCF, endCF, shooterPlayer, bulletKey)
		if not ReplicatedBullets[bulletKey] then
			ReplicatedBullets[bulletKey] = CreateBullet()
			ReplicatedBullets[bulletKey].Color = Color3.fromRGB(255, 100, 100)
		end
		ReplicatedBullets[bulletKey].CFrame = endCF
		
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {shooterPlayer.Character, ReplicatedBullets[bulletKey]}
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		
		local dir = endCF.Position - startCF.Position
		local result = Workspace:Raycast(startCF.Position, dir, rayParams)
		return result ~= nil
	end,
	function(bulletKey)
		if ReplicatedBullets[bulletKey] then
			ReplicatedBullets[bulletKey]:Destroy()
			ReplicatedBullets[bulletKey] = nil
		end
	end,
	function(confirmed, hitPart, hitPosition, shotId)
		if not hitPart then return end
		
		local pendingHit = PendingHits[hitPart]
		if not pendingHit then return end
		
		if confirmed then
			PendingHits[hitPart] = nil
		else
			if pendingHit.Humanoid and pendingHit.Humanoid.Parent then
				pendingHit.Humanoid.Health = pendingHit.PreviousHealth
			end
			
			PendingHits[hitPart] = nil
		end
	end
)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		FireProjectile()
	end
end)
```

### Server (`init.server.luau`)

```lua
--[[ =========  SERVICES  ========= ]]
local Players = game:GetService("Players")

--[[ =========  MODULES  ========= ]]
local BitGunPredictionServer = script:WaitForChild("BitGunPredictionServer")
local GPredictionService = require(BitGunPredictionServer.GPredictionService)

--[[ =========  CONSTANTS  ========= ]]
local DAMAGE = 25

--[[ =========  HELPER FUNCTIONS  ========= ]]
local function GetHumanoid(part)
	local current = part
	while current do
		local humanoid = current:FindFirstChildOfClass("Humanoid")
		if humanoid then return humanoid, current end
		current = current.Parent
	end
	return nil, nil
end

--[[ =========  CALLBACKS  ========= ]]
local Callbacks = {}

function Callbacks.Exponential(shooter, result, speed)
	local humanoid, character = GetHumanoid(result.Instance)
	if not humanoid then return end
	
	local hitPlayer = Players:GetPlayerFromCharacter(character)
	if hitPlayer and hitPlayer ~= shooter then
		humanoid:TakeDamage(DAMAGE)
	end
end

function Callbacks.ExponentialCheck(player, origin, direction, speed, lifetime)
	return speed <= 200 and lifetime <= 5
end

--[[ =========  MAIN  ========= ]]
GPredictionService.GlobalInit(Callbacks)
```

---

## �🎯 Trajectory Types

| Type | Description |
|------|-------------|
| `Linear` | Straight line projectile |
| `Exponential` | Affected by gravity (arcing trajectory) |
| `SineWave` | Oscillates side-to-side |
| `Spiral` | Corkscrews through the air |
| `Decelerate` | Slows down over time |
| `Accelerate` | Speeds up over time |
| `Boomerang` | Returns to origin |
| `QuadraticBezier` | Follows a 3-point curve |
| `CubicBezier` | Follows a 4-point curve |

## 🛡️ Security Features

- **Origin Validation** – Shots must originate within 10 studs of player
- **Latency Buffer** – Rejects claims with >500ms latency
- **Historical Position Check** – Validates hits against recorded positions
- **Shot Tracking** – Prevents duplicate hit claims
- **Rate Limiting** – Configurable event rate limits
- **Anti-NaN / nil** – Rejects invalid number values

---

## ⚙️ Configuration

Edit `Config.luau` to customize:

```lua
Config.EventParent = ReplicatedStorage.Shared.BitGunPredictionShared
Config.EventName = "BitGunPredictionEvent"
Config.EventRateLimit = 0.01          -- 100 shots/second max
Config.HitEventName = "BitGunPredictionHitEvent"
Config.HitEventRateLimit = 0.01
Config.HitAckEventName = "BitGunPredictionHitAckEvent"
```

Server-side constants in `GPredictionService.luau`:

```lua
MAX_ORIGIN_DIST = 10          -- Max distance from player to shot origin
MAX_LATENCY_BUFFER = 0.5      -- Max acceptable network latency
LATENCY_TOLERANCE = 0.15      -- Additional tolerance for hit timing
HIT_POSITION_TOLERANCE = 15   -- Max error between claimed and historical position
```

---

## 📋 API Reference

### GPredictionController (Client)

| Method | Description |
|--------|-------------|
| `GlobalInit(visualOnStep, visualOnFinish, replicatedHitOnStep, onHitAcknowledge)` | Initialize the client controller |
| `FireProjectile(origin, direction, speed, lifetime, simType, visualOnStep, visualOnFinish)` | Fire a new projectile |

### GPredictionService (Server)

| Method | Description |
|--------|-------------|
| `GlobalInit(callbacks)` | Initialize the server service with hit callbacks |

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 📝 Changelog

### v1.0.0
- Initial release

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/RiseBit/BitGunPrediction/issues)
- **Discussions**: [GitHub Discussions](https://github.com/RiseBit/BitGunPrediction/discussions)

---

Made with ❤️ by [RiseBit](https://github.com/RiseBit)
