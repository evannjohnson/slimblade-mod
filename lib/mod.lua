local mod = require 'core/mods'

mod.hook.register("system_post_startup", "slimblade-mod prevent duplicate slimblade devices", function()
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
    function hid_add(id, name, types, codes, dev, guid)
        local g = hid.new(id, name, types, codes, dev, guid)
        hid.devices[id] = g
        hid.update_devices()
        if g and hid.add ~= nil then hid.add(g) end
    end

    _norns.hid.add = hid_add
end)

-- this approach failed
-- issue is that vports is updated before devices, so needed metatables for both
-- see norns/lua/core/hid.lua Hid.new()
-- but vports is inserted raw via table.insert, so metatable doesnt work
-- will instead try changing Hid.new()
function catch_slimblade()
    -- prevent the non-mouse slimblades from being added to the table
    local mt_devices = {
        __newindex = function(table, key, value)
            -- only take action when devices are connected, not disconnected
            if value then
                if value.name:match("Kensington SlimBlade Pro") and not value.is_mouse then
                    -- caught a squirrelly extraneous device
                    print("wee woo")
                    return
                else
                    -- the name is different each time it connects, causing new entries in vports instead of using the existing ones, set to a standard name to solve this
                    value.name = "Kensington SlimBlade Pro"
                end
            end
            rawset(table, key, value)
        end
    }
    setmetatable(hid.devices, mt_devices)

    -- because of how devices get added, we also need to catch the names of these in the vports table
    -- see Hid.new() in norns/lua/core/hid.lua, note how it is *after* that function gets called that Hid.update_devices() gets called, which points entries in the vports and devices table at each other based on the name field of entries in both tables
    -- see notes for more on my findings
    local mt_vports = {}
    mt_vports.__newindex = function(table, key, value)
        local mt = getmetatable(table)
        if key:match("name") and value:match("Kensington SlimBlade Pro") then
            value = "Kensington SlimBlade Pro"
        end
        if key:match("name") then
            print("oOoOoOoO")
        end
        print(key)

        mt.underlying_table[key] = value
    end

    mt_vports.__index = function(table, key)
        local mt = getmetatable(table)
        return mt.underlying_table[key]
    end

    for i = 1, 4 do
        local vport = hid.vports[i]
        local mt_vports_copy = {
            underlying_table = {}
        }
        for k, v in pairs(mt_vports) do
            mt_vports_copy[k] = v
        end

        for k, v in pairs(vport) do
            mt_vports_copy.underlying_table[k] = v
            vport[k] = nil
        end

        setmetatable(vport, mt_vports_copy)
    end
end
