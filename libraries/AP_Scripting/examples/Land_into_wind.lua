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

-- Tunes
local _tune_short_low = "L8O4aaO2"   -- "MFT240 L8O4aa"
local _tune_long_high = "L2O5FO2"        -- "MFT240  L2O5F"
local _tune_ABORT = "L4O1FL1E"      -- "MFT240  L4O1FL1E"

-- Tune timing parameters
local looptime = 50                 -- 

local flight_mode = vehicle:get_mode()
local prev_flight_mode = vehicle:get_mode()

function update() -- this is the loop which periodically runs
  -- Get current flight mode
  flight_mode = vehicle:get_mode()

  -- Monitor failsafe beeing triggered

  -- loop and continue looking for mode changes
  return update, looptime
end


-- rc:has_valid_input()
-- battery:has_failsafed()
-- Gör egna parametrar:
-- https://ardupilot.org/plane/docs/common-scripting-parameters.html

-- Fail safe functions:
-- https://ardupilot.org/plane/docs/apms-failsafe-function.html

-- If glide AND battery fs triggered, adjust heading and then GLIDE?




function land_into_wind()

  return land_into_wind, looptime
end

-- Helper functions

-- Monitor mode change, NOT tested
function did_mode_change()
  flight_mode = vehicle:get_mode()
  if flight_mode ~= prev_flight_mode then
    -- There is a new flight mode, update prev flight mode
    prev_flight_mode = flight_mode
    return true
  else
    return false
  end
end

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