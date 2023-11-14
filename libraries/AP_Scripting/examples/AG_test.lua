-- This is my stupid test script

local left_tune = "cdefcdefcdef"
local right_tune = "fedcfedcfedc"
local _NOTICE = 5
local _WARNING = 4
local _SLOW = "L8 O5"
local _FAST = "L16 O6"
local _llim = 5
local _hlim = 15

function update()
    -- Get roll angle in radians
    local roll_rad = ahrs:get_roll()
    
    -- Test that roll_rad has been read properly
    if roll_rad~=nil then
        -- Convert to degrees
        local roll = math.deg(roll_rad)
        -- Sort four different cases
        if roll > _llim and roll < _hlim then
            -- leaning little right
            send_to_gcs(_NOTICE, string.format("Leaning little right, %.1f degreees", roll))
            play_tune(right_tune, _SLOW)
        elseif roll > _hlim then
            -- Leaning right
            send_to_gcs(_WARNING, string.format("Leaning right, %.1f degreees", roll))
            play_tune(right_tune, _FAST)
        elseif roll < -_llim and roll > -_hlim then
            -- leaning little left
            send_to_gcs(_NOTICE, string.format("Leaning little left, %.1f degreees", roll))
            play_tune(left_tune, _SLOW)
        elseif roll < -_hlim then
            -- Leaning right
            send_to_gcs(_WARNING, string.format("Leaning left, %.1f degreees", roll))
            play_tune(left_tune, _FAST)
        end
    else
        send_to_gcs(_WARNING, "roll_rad = nil, cant be read properly")
    end

    return update, 1500
end

function send_to_gcs(level, mess)
    gcs:send_text(level, mess)
end

function play_tune(tune, speed)
    notify:play_tune(speed .. tune)
    -- notify:play_tune("cdcdcddddddd")
end

function init()
    send_to_gcs(_WARNING, "Lua script initiating")
    send_to_gcs(_NOTICE, string.format("This is current throttle: %.1f", motors:get_throttle()))
    return update, 2000   -- Start the main scritp
end

return init, 10000    -- Start the init script
