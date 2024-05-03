-- This script is to LAND INTO WIND if the FS_LONG_ACTN = 2 is triggered. This is triggered by coms and or low battery depending on paramter settings.
-- This script also introduces a parameter for enabling this specific script.
-- FS_GLIDE_INTO_WIND
-- Value   |  Meaning
-- 0       |  Disabled
-- 1       |  Enabled 


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
local looptime = 50
local long_looptime = 5000

-- Mode memory
local flight_mode = vehicle:get_mode()
local prev_flight_mode = vehicle:get_mode()

-- Flags

-- Variables
local giw_param = nil

-- Parameters
local FS_GLIDE_INTO_WIND = Parameter()      --creates a parameter object

function _init()
  send_to_gcs(_INFO, 'LUA: init()..')

  -- Create the parameter if not existing. Loop here until the parameter is set.
  giw_param = get_param('FS_GLIDE_INTO_WIND')
  if giw_param == nil then
    -- Create parameter
    local PARAM_TABLE_KEY = 72
    assert(param:add_table(PARAM_TABLE_KEY, "FS_GLIDE_INTO_", 30), 'could not add param table')
    assert(param:add_param(PARAM_TABLE_KEY, 1,  'WIND', 0), 'could not add param1')
    send_to_gcs(_INFO, 'LUA: Created parameter FS_GLIDE_INTO_WIND')
  else 
    FS_LAND_INTO_WIND:init('FS_GLIDE_INTO_WIND')       --get the physical location in parameters memory area so no future name search is done
    giw_param = FS_GLIDE_INTO_WIND:get()
    send_to_gcs(_INFO, 'LUA: FS_GLIDE_INTO_WIND' .. giw_param)
  end
end

function update() -- this is the loop which periodically runs
  -- Check if state of parameter changed, print at boot and every change
  if giw_param ~= FS_GLIDE_INTO_WIND:get() then
    giw_param = FS_GLIDE_INTO_WIND:get()
    send_to_gcs(_INFO, 'LUA: FS_GLIDE_INTO_WIND' .. giw_param)
    -- If feature is not enabled, loop slowly
    if ~giw_param then
      return update, long_looptime
    end
  end
  send_to_gcs(_INFO, 'LUA: looping update()..')
  return update, 1000
end

  
--   -- Get current flight mode
--   flight_mode = vehicle:get_mode()

--   -- Monitor failsafe beeing triggered

--   -- loop and continue looking for mode changes
--   return update, looptime
-- end

-- rc:has_valid_input()
-- battery:has_failsafed()
-- Gör egna parametrar:
-- https://ardupilot.org/plane/docs/common-scripting-parameters.html

-- Fail safe functions:
-- https://ardupilot.org/plane/docs/apms-failsafe-function.html

-- If glide AND battery fs triggered, adjust heading and then GLIDE?



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

-- Get a parameter value, if existing
function get_param(param_name)
  value = param:get(param_name) -- returns number or nil
  if value then
    return value
  else
    error('LUA: failed to get param ' .. param_name)
    return nil
  end
end


-- Start up the script
return _init, 2000
