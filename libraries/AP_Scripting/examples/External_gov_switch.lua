-- This script is a test for AP_Mission bindings

local loop_time = 500
local _INFO = 6
local _NOTICE = 5
local _WARNING = 4
local previous_state = ""

local _flight_mode_STABILIZED = 0
local _flight_mode_AUTO = 3
local _flight_mode_GUIDED = 4
local _fligth_mode_RTL = 6
local _flight_mode_POSHOLD = 16
local _flight_mode_TAKEOFF = 13   -- Mode 13 for plane

local loop_time = 50

local _tune_count_down = "L8O4aaO2"   -- "MFT240 L8O4aa"
local _tune_LAUNCH = "L2O5FO2"        -- "MFT240  L2O5F"
local _tune_ABORT = "L4O1FL1E"      -- "MFT240  L4O1FL1E"
local _tune_GOV_ON = "MFT240L8 O4cdefL1g"
local _tune_GOV_OFF= "MFT240L8 O4gfedL1c" 


local flight_mode = vehicle:get_mode()
local prev_flight_mode = vehicle:get_mode()
local gov_switch_high = 1800
local gov_switch_low = 1100
local gov_switch_rsc_limit = 1370  --(1350)
local gov_switch_channel_out = 6
local gov_switch = gov_switch_low

function update() -- this is the loop which periodically runs

  -- Get current value of helicopter RCS (number per servo function)
  local rsc = SRV_Channels:get_output_pwm(31)
  
  -- Test and verificaion
  -- local _gov_switch = SRV_Channels:get_output_pwm(94)
  -- local _gov_switch_str = string.format("LUA: _gov_output is: %f", _gov_switch)
  -- send_to_gcs(_INFO, _gov_switch_str)

  -- Get the interlock status, boolean
  local interlock = motors:get_interlock()

  -- Test if rsc (basically gov ramp up throttle) is high enough for triggering governor.
  if rsc > gov_switch_rsc_limit then
    -- Check that RC has gov on, this is the interlock nob
    if interlock then
      -- If mode change, play tune and send text to gcs
      if gov_switch ~= gov_switch_high then
        play_tune(_tune_GOV_ON)
        gov_switch = gov_switch_high
        send_to_gcs(_INFO, string.format("Governor switch is set to: %d", gov_switch_high))
      end
    end
  -- rsc is below trigger value
  elseif rsc <= gov_switch_rsc_limit - 40 then
    -- If mode change, play tune and send text to gcs
    if gov_switch ~= gov_switch_low then
      play_tune(_tune_GOV_OFF)
      gov_switch = gov_switch_low
      send_to_gcs(_INFO, string.format("Governor switch is set to: %d", gov_switch_low))
    end
  end

  -- Set the servo channel, numbered per function, 94 is Script1.
  SRV_Channels:set_output_pwm(94, gov_switch)    -- servo funcition 94. Servo6 is set up t script1, i.e. 94
  
  return update, loop_time
end


-- Helper functions

-- Print to GCS
function send_to_gcs(level, mess)
  gcs:send_text(level, mess)
end

function play_tune(tune)
  notify:play_tune(tune)
end


function parse_flight_mode(flight_mode_num)
  if flight_mode_num == _flight_mode_STABILIZED then
    return "STABILIZED"
  elseif flight_mode_num == _flight_mode_AUTO then
    return "AUTO"
  elseif flight_mode_num == _flight_mode_POSHOLD then
    return "POSHOLD"
  elseif flight_mode_num == _flight_mode_GUIDED then
    return "GUIDED"
  else
    return string.format("%d",flight_mode_num)
  end
end


-- Start up the script
return update, 5000