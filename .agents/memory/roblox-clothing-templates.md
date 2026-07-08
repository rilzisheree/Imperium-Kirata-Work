---
name: Roblox clothing template IDs
description: Why setting Shirt/Pants by constructing rbxassetid://<id> from a user-supplied asset ID is unreliable, and the correct fix.
---

When applying catalog clothing programmatically (e.g. an admin `setshirt <id>` command), do not build the `ShirtTemplate`/`PantsTemplate` content string yourself as `"rbxassetid://" .. assetId`.

**Why:** Admins/users often supply a bundle or package ID (the ID shown prominently on most catalog pages) rather than the underlying individual Shirt/Pants asset ID. `rbxassetid://<bundleId>` does not point to a real clothing texture, so the garment silently renders as nothing — shirts appear not to apply, pants can appear to strip the avatar's clothing entirely. This is easy to misdiagnose as an asset-validation bug when the validation logic is actually fine.

**How to apply:** Load the asset via `InsertService:LoadAsset(assetId)`, find the actual `Shirt`/`Pants` instance among its descendants, and read that instance's own `ShirtTemplate`/`PantsTemplate` property to get the correct, already-resolved content id. Use that resolved string everywhere (including cache and respawn re-apply logic) instead of re-deriving a template from the raw input ID.
