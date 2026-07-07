local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP             = Players.LocalPlayer
local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes") :: ModuleScript)

-- ── helpers ────────────────────────────────────────────────────────────────────

local function getHumanoid(): Humanoid?
	local character = LP.Character
	return character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

-- ── ragdoll apply ──────────────────────────────────────────────────────────────
-- The server has already disabled Motor6Ds and added BallSocketConstraints so
-- other players see the collapse. We now tell the local humanoid to yield physics
-- ownership to the engine; without this the client keeps sending positional
-- corrections that override the joint changes and the body just stands frozen.

CommandRemotes.RagdollApply.OnClientEvent:Connect(function()
	local humanoid = getHumanoid()
	if not humanoid then return end
	-- Physics state stops the humanoid controller from fighting gravity, so the
	-- loose BallSocketConstraints can actually let the limbs fall naturally.
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
end)

-- ── ragdoll remove ─────────────────────────────────────────────────────────────
-- The server has re-enabled Motor6Ds and removed constraints; tell the humanoid
-- to resume its normal state machine so the player can move again.

CommandRemotes.RagdollRemove.OnClientEvent:Connect(function()
	local humanoid = getHumanoid()
	if not humanoid then return end
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
end)

-- ── respawn guard ──────────────────────────────────────────────────────────────
-- If the character is replaced while ragdolled (death, re, respawn commands),
-- the new character starts with a fresh humanoid in its default state — no
-- action needed here; the server handles clearing the ragdollData entry.
