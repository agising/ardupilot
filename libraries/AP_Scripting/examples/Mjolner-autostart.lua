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

local _tune_count_down = "L8O4aaO2"   -- "MFT240 L8O4aa"
local _tune_LAUNCH = "L2O5FO2"        -- "MFT240  L2O5F"
local _tune_ABORT = "L4O1FL1E"      -- "MFT240  L4O1FL1E"

-- Tune timing parameters
local to_lt = 50                 -- take_off_loop_time in ms. Keep low to monitor abort
local tpt = 20 * to_lt            -- Time_Per_Tone - in multiplers of to_lt
local to_tt = 0                  -- Take_off_total_time - Keep track of total time in takeo_off mode.

local flight_mode = vehicle:get_mode()
local prev_flight_mode = vehicle:get_mode()

function update() -- this is the loop which periodically runs
  -- Get current flight mode
  flight_mode = vehicle:get_mode()

  -- Monitor mode switches
  if flight_mode ~= prev_flight_mode then
    -- There is a new flight mode, update prev flight mode
    prev_flight_mode = flight_mode

    -- If the new flight mode is TAKEOFF, init takeoff tuness
    if flight_mode == _flight_mode_TAKEOFF then
      if arming:is_armed() then
        to_tt = 0
        return takeoff(), to_lt
      end 
      send_to_gcs(_WARNING, "Not armed, Goto MANUAL, Arm then try TAKEOFF")
      play_tune(_tune_ABORT)
    end
  end

  -- loop and continue looking for mode changes
  return update, loop_time
end



function takeoff()
  -- Get current flight mode
  flight_mode = vehicle:get_mode()
  if flight_mode ~= _flight_mode_TAKEOFF then
    -- Take off was aborted
    send_to_gcs(_WARNING, "TAKEOFF canceled")
    play_tune(_tune_ABORT)
    -- abort take off and go back monitoring flight modes
    to_tt = 0
    return update, loop_time
  end 
  
  -- Time to play tune or not? 
  if tpt == to_tt or tpt*2 == to_tt or tpt*3 == to_tt then
    send_to_gcs(_INFO, "Ready for catapult..")
    play_tune(_tune_count_down)   
  end

  if tpt*4 == to_tt then
    send_to_gcs(_INFO, "LAUNCH!")
    play_tune(_tune_LAUNCH)
    to_tt = 0
    return update, loop_time
  end

  -- Add the loop time to total time and return
  to_tt = to_tt + to_lt

  return takeoff, to_lt
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