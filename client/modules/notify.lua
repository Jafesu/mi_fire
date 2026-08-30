--- Notifications.
---
--- One place that knows how this server tells a player something, so swapping notification
--- resources later is a change here rather than everywhere.

MIFire = MIFire or {}

RegisterNetEvent('mi_fire:client:notify', function(message, kind)
    if type(message) ~= 'string' then return end

    if lib and lib.notify then
        lib.notify({
            title = 'Fire',
            description = message,
            type = kind == 'error' and 'error' or (kind == 'success' and 'success' or 'inform'),
        })
        return
    end

    -- ox_lib is a hard dependency, so this should not be reachable. Falling back to the
    -- console beats swallowing the message if it ever is.
    print(('[mi_fire] %s'):format(message))
end)
