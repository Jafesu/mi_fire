--- Inventory bridge.
---
--- Gear integrity, SCBA bottle pressure, and extinguisher charge all live in item
--- metadata, so a specific bottle or a specific set of turnout gear carries its own
--- state. That is the same pattern `mi_diving` uses for rebreather air.

MIFire = MIFire or {}

local Inventory = { available = false, resource = 'ox_inventory' }

local function ensure()
    if Inventory.available then return true end
    Inventory.available = GetResourceState(Inventory.resource) == 'started'
    return Inventory.available
end

-- ---------------------------------------------------------------------------

--- Does the player have at least `count` of an item?
---@param source integer
---@param item string
---@param count integer|nil
---@return boolean
function Inventory.has(source, item, count)
    if not ensure() then return false end
    local ok, result = pcall(function()
        return exports[Inventory.resource]:GetItemCount(source, item)
    end)
    if not ok then return false end
    return (result or 0) >= (count or 1)
end

--- The first matching item slot, with its metadata.
---@param source integer
---@param item string
---@return table|nil slot
function Inventory.getSlot(source, item)
    if not ensure() then return nil end
    local ok, result = pcall(function()
        return exports[Inventory.resource]:GetSlotWithItem(source, item)
    end)
    if not ok then return nil end
    return result
end

--- Read one metadata key off the first matching item.
---@param source integer
---@param item string
---@param key string
---@param default any
---@return any
function Inventory.getMetadata(source, item, key, default)
    local slot = Inventory.getSlot(source, item)
    if not slot or type(slot.metadata) ~= 'table' then return default end
    local value = slot.metadata[key]
    if value == nil then return default end
    return value
end

--- Write metadata back to a specific slot.
---
--- Always writes the whole metadata table rather than one key, because ox_inventory
--- replaces rather than merges -- writing a single key silently drops the others.
---@param source integer
---@param slotId integer
---@param metadata table
---@return boolean
function Inventory.setMetadata(source, slotId, metadata)
    if not ensure() or not slotId then return false end
    local ok = pcall(function()
        exports[Inventory.resource]:SetMetadata(source, slotId, metadata)
    end)
    return ok
end

--- Update one key while preserving the rest.
---@param source integer
---@param item string
---@param key string
---@param value any
---@return boolean
function Inventory.updateMetadata(source, item, key, value)
    local slot = Inventory.getSlot(source, item)
    if not slot then return false end

    local metadata = slot.metadata or {}
    metadata[key] = value
    return Inventory.setMetadata(source, slot.slot, metadata)
end

--- Durable equipment wear. Returns the new value so a caller can react to it hitting
--- the condemned threshold without reading it back.
---@param source integer
---@param item string
---@param key string
---@param amount number Positive removes durability.
---@param minimum number|nil
---@return number|nil remaining
function Inventory.consumeDurability(source, item, key, amount, minimum)
    local slot = Inventory.getSlot(source, item)
    if not slot then return nil end

    local metadata = slot.metadata or {}
    local current = tonumber(metadata[key]) or 100.0
    local remaining = math.max(minimum or 0.0, current - (tonumber(amount) or 0.0))

    metadata[key] = remaining
    if not Inventory.setMetadata(source, slot.slot, metadata) then return nil end

    return remaining
end

MIFire.Inventory = Inventory

return Inventory
