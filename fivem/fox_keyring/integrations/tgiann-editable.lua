-- fox_keyring ---------------------------------------------------------------
-- Paste this at the very end of tgiann-inventory/server/editable.lua.

local foxKeyringItem = "keyring"

local function foxKeyringStashData()
	for i = 1, #config.itemStash do
		if config.itemStash[i].item == foxKeyringItem then return config.itemStash[i] end
	end
end

-- The keyring can be moved around inside its owner's inventory, but never out of it:
-- no dropping, stashing, trunks, or taking it off someone while robbing them.
registerHook('swapItems', function(payload)
	local ok, block = pcall(function()
		if payload.fromInventory == payload.toInventory then return false end
		local fromInv = payload.fromInventory and GetInventoryFromKeyName(tostring(payload.fromInventory))
		if not fromInv or fromInv.invType ~= "player" then return false end

		local item = payload.fromSlot
		if type(item) ~= "table" and fromInv.Items then
			item = fromInv.Items[item] or fromInv.Items[tonumber(item)] or fromInv.Items[tostring(item)]
		end
		return type(item) == "table" and item.name == foxKeyringItem
	end)
	if ok and block then return false end
end)

-- Lets fox_keyring open someone else's keyring for a robber (registers the stash first so keys can be taken).
Export("OpenKeyringStash", function(src, stashId)
	local stashData = foxKeyringStashData()
	if not stashData or type(stashId) ~= "string" then return false end

	if not IsStashRegistered(stashId) then
		RegisterStash({
			name = stashId,
			maxWeight = stashData.maxweight,
			slots = stashData.slots,
			whitelist = stashData.whitelist,
			label = stashData.label
		})
	end

	OpenInventory(src, "stash", stashId)
	return true
end)

-- Lets fox_keyring read what's on a keyring, straight from tgiann's live inventory data.
local function foxFindStash(stashId)
	local ok, inv = pcall(GetInventory, stashId, "stash")
	if ok and type(inv) == "table" and inv.Items then return inv end
	for _, v in pairs(Inventory) do
		if v.invType == "stash" and v.invId == stashId then return v end
	end
end

Export("GetKeyringItems", function(stashId)
	if type(stashId) ~= "string" then return nil end

	local inv = foxFindStash(stashId)
	if not inv and not IsStashRegistered(stashId) then
		-- Never opened since the restart: register it (loads it from the database), then look again.
		local stashData = foxKeyringStashData()
		if stashData then
			RegisterStash({
				name = stashId,
				maxWeight = stashData.maxweight,
				slots = stashData.slots,
				whitelist = stashData.whitelist,
				label = stashData.label
			})
			inv = foxFindStash(stashId)
		end
	end

	return inv and inv.Items or nil
end)
