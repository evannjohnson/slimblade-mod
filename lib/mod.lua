local mod = require 'core/mods'

mod.hook.register("system_post_startup", "slimblade-mod prevent duplicate slimblade devices", function()
    -- overwrite hid.new with an identical function that intercepts a slimblade
    function hid_new(id, name, types, codes, dev, guid)
        local vport            = require "vport"
        local hid_device_class = require "hid_device_class"
        local tab              = require "tabutil"

        local device           = setmetatable({}, hid)

        device.id              = id
        device.name            = vport.get_unique_device_name(name, hid.devices)
        device.dev             = dev  -- opaque pointer
        device.guid            = guid -- SDL format GUID
        device.event           = nil  -- event callback
        device.remove          = nil  -- device unplug callback
        device.port            = nil

        -- copy the types and codes tables
        device.types           = {}
        device.codes           = {}
        -- types table shall be a simple array with default indexing
        for k, v in pairs(types) do
            device.types[k] = v
        end
        -- codes table shall be an associate array indexed by type
        for k, v in pairs(codes) do
            device.codes[types[k]] = {}
            for kk, vv in pairs(v) do
                device.codes[types[k]][kk] = vv
            end
        end

        device.is_ascii_keyboard = hid_device_class.is_ascii_keyboard(device)
        device.is_mouse = hid_device_class.is_mouse(device)
        device.is_gamepad = hid_device_class.is_gamepad(device)

        if device.name:match("Kensington SlimBlade Pro") and not device.is_mouse then
            return nil
        end

        -- autofill next postiion
        local connected = {}
        for i = 1, 4 do
            table.insert(connected, hid.vports[i].name)
        end
        if not tab.contains(connected, device.name) then
            for i = 1, 4 do
                if hid.vports[i].name == "none" then
                    hid.vports[i].name = device.name
                    break
                end
            end
        end

        return device
    end

    hid.new = hid_new

    -- Hid.add expects a non-nil value, our changes to Hid.new violate that
    -- Hid.add is only called from _norns.hid.add
    -- redefine _norns.hid.add
    function hid_add(id, name, types, codes, dev, guid)
        local g = hid.new(id, name, types, codes, dev, guid)
        hid.devices[id] = g
        hid.update_devices()
        if g and hid.add ~= nil then hid.add(g) end
    end

    _norns.hid.add = hid_add
end)
