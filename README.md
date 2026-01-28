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
- **Full Rewind System** – Optional full-world rewind for accurate lag compensation
- **9 Trajectory Types** – Linear, Exponential (gravity), Sine Wave, Spiral, Decelerate, Accelerate, Boomerang, Quadratic & Cubic Bezier Curves
- **Signal Events** – Subscribe to projectile events for custom logic
- **Humanoid Position Tracking** – Historical position interpolation for accurate hit validation
- **Rate Limiting** – Built-in protection against event spam
- **Debug Utilities** – Built-in debug visualization tools
- **Type Definitions** – Full Luau type exports for IDE support

---

## 📦 Installation

### Download RBXM/ZIP ( Reccomended by the Ancestor )
Just go to Github and find Release Section, Download it, Drag it, Enjoy!

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

local Callbacks = {}

function Callbacks.Linear(shooter, result, speed)
    local hitPart = result.Instance
    local hitPosition = result.Position
    
    local humanoid = hitPart.Parent:FindFirstChild("Humanoid")
    if humanoid then
        humanoid:TakeDamage(25)
    end
end

function Callbacks.LinearCheck(player, origin, direction, speed, lifetime, clientFiredAt, simType)
    return true
end

GPredictionService.GlobalInit(Callbacks)
```

### Client Setup

```lua
local GPredictionController = require(path.to.GPredictionController)

GPredictionController.GlobalInit(
    function(startCF, endCF, shooter, bulletKey)
        return false
    end,
    function(bulletKey)
    end,
    function(confirmed, hitPart, hitPosition, shotId)
        if confirmed then
            print("Hit confirmed!")
        else
            print("Hit rejected by server")
        end
    end
)

GPredictionController.FireProjectile({
    Origin = head.Position,
    Direction = Camera.CFrame.LookVector,
    Speed = 100,
    Lifetime = 5,
    SimulationType = "Linear",
    OnStep = function(startCF, endCF, player)
        return nil
    end,
    OnFinish = function()
    end,
})
```

---

## 📝 Full Example Implementation

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
    part.Size = Vector3.new(0.3, 0.3, 0.3)
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
    
    GPredictionController.FireProjectile({
        Origin = head.Position,
        Direction = Camera.CFrame.LookVector,
        Speed = PROJECTILE_SPEED,
        Lifetime = PROJECTILE_LIFETIME,
        SimulationType = SIMULATION_TYPE,
        OnStep = function(startCF, endCF, player)
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
        end,
        OnFinish = function()
            if myBullet then myBullet:Destroy() end
        end,
    })
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
-- this can do aswell :>
GPredictionService.GlobalInit(Callbacks)
```

---

## 🎯 Trajectory Types

| Type | Description | Args |
|------|-------------|------|
| `Linear` | Straight line projectile | - |
| `Exponential` | Affected by gravity (arcing trajectory) | - |
| `SineWave` | Oscillates side-to-side | `Amplitude`, `Frequency` |
| `Spiral` | Corkscrews through the air | `Radius`, `RotationSpeed` |
| `Decelerate` | Slows down over time | `DecayRate` |
| `Accelerate` | Speeds up over time | `Acceleration` |
| `Boomerang` | Returns to origin | `PeakTime` |
| `QuadraticBezier` | Follows a 3-point curve | `ControlPoint1`, `ControlPoint2`, `ControlOffset` |
| `CubicBezier` | Follows a 4-point curve | `ControlPoint1`, `ControlPoint2`, `ControlOffset1`, `ControlOffset2` |

---

## 🛡️ Security Features

- **Origin Validation** – Shots must originate within configurable distance of player
- **Latency Buffer** – Rejects claims with excessive latency
- **Historical Position Check** – Validates hits against recorded positions
- **Full Rewind Mode** – Optional server-side world rewind for hit validation
- **Shot Tracking** – Prevents duplicate hit claims
- **Rate Limiting** – Configurable event rate limits
- **Anti-NaN / nil** – Rejects invalid data types

```

---

## 📋 API Reference

### GPredictionController (Client)

| Method | Description |
|--------|-------------|
| `GlobalInit(visualOnStep, visualOnFinish, onHitAcknowledge)` | Initialize the client controller |
| `FireProjectile(config: FireConfig)` | Fire a new projectile using config table |
| `BulletLerping(bullet, targetCF, lerpPercentage?)` | Smoothly interpolate bullet position |
| `DrawDebugLine(startPos, endPos, color?, duration?)` | Draw debug visualization line |

#### FireConfig Type

```lua
{
    Origin: Vector3,
    Direction: Vector3,
    Speed: number,
    Lifetime: number,
    SimulationType: string,
    TrajectoryArgs: TrajectoryArgs?,
    OnStep: ((startCF, endCF, player) -> RaycastResult?)?,
    OnFinish: (() -> nil)?,
}
```

#### Signal Events (Client)

| Event | Parameters |
|-------|------------|
| `OnProjectileFired` | `origin, direction, shotId, simType` |
| `OnHitRegistered` | `hitInstance, hitPosition, shotId` |
| `OnHitAcknowledged` | `confirmed, hitPart, hitPosition, shotId` |

### GPredictionService (Server)

| Method | Description |
|--------|-------------|
| `GlobalInit(callbacks)` | Initialize the server service with hit callbacks |

#### Signal Events (Server)

| Event | Parameters |
|-------|------------|
| `OnProjectileFired` | `player, origin, direction, speed, simType` |
| `OnHitValidated` | `player, hitPart, hitPosition, shotId, simType` |
| `OnHitRejected` | `player, hitPart, hitPosition, shotId, reason` |

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 📝 Changelog

### v1.1.0
- **New Config-Based API** – `FireProjectile` now accepts a config table for cleaner syntax
- **Signal Events** – Added subscribable events for projectile lifecycle
- **OnStep** - Can Return a Basepart/Model aswell.
- **BulletLerping Helper** – New utility method for smooth bullet visual interpolation
- **Debug Utilities** – Added `DrawDebugLine` and configurable debug options
- **Separated ServerConfig** – Server configuration now in dedicated `ServerConfig.luau`
- **Full Rewind System** – Optional full-world rewind mode for lag compensation
- **Type Exports** – Full Luau type definitions for IDE autocomplete support
- **Improved Validation** – Enhanced hit validation with rejection reasons

### v1.0.0
- Initial release

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/RiseBit/BitGunPrediction/issues)
- **Discussions**: [GitHub Discussions](https://github.com/RiseBit/BitGunPrediction/discussions)

---

Made with ❤️ by [RiseBit](https://github.com/RiseBit)
