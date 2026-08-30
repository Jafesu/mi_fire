--- Dispatch integration.
---
--- The provider pattern here matches `mi_gunrunner/config.lua` deliberately -- same
--- shape, same escape hatch, so anyone who has configured one has configured both.
---
--- The payload mi_fire builds is lb-tablet's real `AddDispatch` shape. If you switch
--- providers, `bridge/dispatch/<provider>.lua` is the only file that needs to know the
--- difference; nothing in `server/modules/` ever sees a dispatch payload.

Config = Config or {}

Config.Dispatch = {
    --- 'lb-tablet', 'custom', or 'none'.
    provider = 'lb-tablet',

    --- Resource name for the provider. Separate from `provider` so a renamed or forked
    --- resource does not need a code change.
    resource = 'lb-tablet',

    --- Who receives fire calls. `mdts` wins over `jobs` when both are set, matching
    --- lb-tablet's own precedence.
    recipients = {
        jobs = { 'fireman' },
        mdts = {},
    },

    --- Suppress dispatch entirely for admin-started fires. Testing a scene should not
    --- spam the board.
    suppressForAdmin = true,

    --- Rate limit. A propagation bug that creates fifty incidents should not create
    --- fifty dispatches.
    minSecondsBetweenCalls = 20,
}

--- Per-call-type dispatch presentation. `code` and `title` are what the board shows.
--- Keys are fire classes from `shared/enums.lua`, plus a `default`.
Config.DispatchCalls = {
    default = {
        code = '10-70', title = 'Fire', priority = 'medium',
        blip = { sprite = 436, color = 1, size = 0.9, radius = 60.0 },
        duration = 900, notificationTime = 20, sound = true,
    },

    A = {
        code = '10-70', title = 'Structure Fire', priority = 'high',
        blip = { sprite = 436, color = 1, size = 1.0, radius = 60.0 },
    },
    B = {
        code = '10-70F', title = 'Flammable Liquid Fire', priority = 'high',
        blip = { sprite = 436, color = 47, size = 1.0, radius = 80.0 },
    },
    C = {
        code = '10-70E', title = 'Electrical Fire', priority = 'high',
        blip = { sprite = 436, color = 5, size = 0.9, radius = 50.0 },
    },
    D = {
        code = '10-70M', title = 'Combustible Metal Fire', priority = 'high',
        blip = { sprite = 436, color = 5, size = 1.0, radius = 100.0 },
    },
    K = {
        code = '10-70K', title = 'Commercial Kitchen Fire', priority = 'medium',
        blip = { sprite = 436, color = 1, size = 0.8, radius = 40.0 },
    },
    gas = {
        code = '10-70G', title = 'Gas Leak with Fire', priority = 'high',
        blip = { sprite = 436, color = 5, size = 1.0, radius = 120.0 },
    },
    wildland = {
        code = '10-71', title = 'Brush Fire', priority = 'medium',
        blip = { sprite = 436, color = 44, size = 1.2, radius = 150.0 },
    },
    vehicle = {
        code = '10-70V', title = 'Vehicle Fire', priority = 'medium',
        blip = { sprite = 436, color = 1, size = 0.8, radius = 40.0 },
    },
}

--- Used only when `Config.Dispatch.provider` is 'custom'. Return true on success.
--- The payload argument is the lb-tablet-shaped table described above.
---@param _payload table
---@return boolean
Config.CustomDispatch = function(_payload)
    return false
end

return Config.Dispatch
