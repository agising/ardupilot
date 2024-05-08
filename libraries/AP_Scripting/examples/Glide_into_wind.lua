-- This script is to GLIDE INTO WIND if the FS_LONG_ACTN = 2 is triggered. This is triggered by coms and or low battery depending on paramter settings.
-- This script also introduces a parameter for enabling this specific script.
-- GLIDE_WIND_WIND
-- Value   |  Meaning
-- 0       |  Disabled
-- 1       |  Enabled 


-- Tuning parameters
local looptime = 1000
local long_looptime = 5000
local rlim = 300                      -- Absolute roll contribution limit [PWM]

-- GCS text levels
local _INFO = 6
local _NOTICE = 5
local _WARNING = 4

-- Plane flight modes
local mode_MANUAL = 0
local mode_CIRCLE = 1
local mode_STABILIZE = 2
local mode_FBWA = 5
local mode_FBWB = 6 
local mode_AUTO = 10
local mode_RTL = 11
local mode_LOITER = 12
local mode_TAKEOFF = 13
local mode_GUIDED = 15

-- Tunes
local _tune_short_low = "L8O4aaO2"   -- "MFT240 L8O4aa"
local _tune_long_high = "L2O5FO2"    -- "MFT240  L2O5F"
local _tune_ABORT = "L4O1FL1E"       -- "MFT240  L4O1FL1E"

-- Mode memory
local flight_mode = vehicle:get_mode()
local prev_flight_mode = vehicle:get_mode()

-- Flags

-- Variables
local wind_dir_rad = nil
local wind_dir_180 = nil
local error = nil
local roll = nil
local gw_enable = nil
local yaw = nil
local wind = Vector3f()
local link_lost_for = 0
local last_seen

-- Add param table
local PARAM_TABLE_KEY = 74
local PARAM_TABLE_PREFIX = "GLIDE_WIND_"
assert(param:add_table(PARAM_TABLE_KEY, PARAM_TABLE_PREFIX, 30), 'could not add param table')


-------
-- Init
-------

function _init()  
  -- Add and init paramters
  GLIDE_WIND_ENABLE = bind_add_param('ENABLE', 1, 0)
  GLIDE_WIND_RKP = bind_add_param('RKP', 2, 2)
  
  -- Init parameters
  AFS_GCS_TIMEOUT = bind_param('AFS_GCS_TIMEOUT')
  RCMAP_ROLL = bind_param('RCMAP_ROLL')
  
  send_to_gcs(_INFO, 'LUA: GCS timeout: ' .. AFS_GCS_TIMEOUT:get() .. 's')

  -- Test paramter
  if GLIDE_WIND_ENABLE:get() == nil then
    send_to_gcs(_INFO, 'LUA: Something went wrong, GLIDE_WIND_WIND not created')
    return _init(), looptime
  else 
    gw_enable = GLIDE_WIND_ENABLE:get()
    send_to_gcs(_INFO, 'LUA: GLIDE_WIND_ENABLE: ' .. gw_enable)
  end

  -- Get the rc channel to override 
  RC_ROLL = rc:get_channel(RCMAP_ROLL:get())

  -- init last seen
  last_seen = gcs:last_seen()

  -- If GLIDE_WIND_WIND, but other required setting missing, warning
  -- TODO the test and warning

  -- All set, go to update
  -- await take-off?
  return update(), long_looptime
end

------------
-- Main loop
------------
function update()
  
  -- Check if state of GLIDE_WIND_WIND parameter changed, print every change
  if gw_enable ~= GLIDE_WIND_ENABLE:get() then
    gw_enable = GLIDE_WIND_ENABLE:get()
    send_to_gcs(_INFO, 'LUA: GLIDE_WIND_WIND: ' .. gw_enable)
    -- If feature is not enabled, loop slowly
    if ~gw_enable then
      return update, long_looptime
    end
  end

  -- GLIDE_WIND_ENABLE is enabled, look for triggers
  -- Monitor time since last gcs heartbeat
  if last_seen == gcs:last_seen() then
    link_lost_for = link_lost_for + looptime
  else
    last_seen = gcs:last_seen()
    link_lost_for = 0
  end

  -- If link has been lost for more than AFS_GCS_TIMEOUT and we are in FBWA, turn into wind
  if link_lost_for > AFS_GCS_TIMEOUT:get() * 1000 then
    if vehicle:get_mode() == mode_FBWA then
      -- Get the yaw angle
      yaw = math.floor(math.deg(ahrs:get_yaw()))
      -- Get wind direction. Function wind_estimate returns x and y for direction wind blows in, add pi to get true wind dir
      wind = ahrs:wind_estimate()
      wind_dir_rad = math.atan(wind:y(), wind:x())+math.pi
      wind_dir_180 = math.floor(wrap_180(math.deg(wind_dir_rad)))

      -- P-regulator
      error = wind_dir_180 - yaw
      roll = math.floor(error*GLIDE_WIND_RKP:get()) -- cast to int
      -- Limit output
      if roll > rlim then
        roll = rlim
      elseif roll < -rlim then
        roll = -rlim
      end

      -- Could stop steering when heading is correct and stable:
        -- Pros: less risk for stall
        -- Cons: could drift off form wind

      RC_ROLL:set_override(1500+roll)  -- TODO for how long is this active?

    end
  end
  return update, looptime
end

-- Fail safe functions:
-- https://ardupilot.org/plane/docs/apms-failsafe-function.html

-------------------
-- Helper functions
-------------------

-- bind a parameter to a variable
function bind_param(name)
  local p = Parameter()
  assert(p:init(name), string.format('could not find %s parameter', name))
  return p
end

-- add a parameter and bind it to a variable
function bind_add_param(name, idx, default_value)
  assert(param:add_param(PARAM_TABLE_KEY, idx, name, default_value), string.format('could not add param %s', name))
  return bind_param(PARAM_TABLE_PREFIX .. name)
end

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

-- Play tune
function play_tune(tune)
  notify:play_tune(tune)
end

-- Parse flight mode
function parse_flight_mode(flight_mode_num)
  if flight_mode_num == mode_MANUAL then
    return "MANUAL"
  elseif flight_mode_num == mode_CIRCLE then
    return "CIRLCE"
  elseif flight_mode_num == mode_STABILIZE then
    return "STABILIZED"
  elseif flight_mode_num == mode_FBWA then
    return "FBWA"
  elseif flight_mode_num == mode_FBWB then
    return "FBWB"
  elseif flight_mode_num == mode_AUTO then
    return "AUTO"
  elseif flight_mode_num == mode_RTL then
    return "RTL"
  elseif flight_mode_num == mode_LOITER then
    return "LOITER"
  elseif flight_mode_num == mode_TAKEOFF then
    return "TAKEOFF"
  elseif flight_mode_num == mode_GUIDED then
    return "GUIDED"
  else
    return string.format("%d",flight_mode_num)
  end
end

-- Returns the angle in range 0-360
function wrap_360(angle)
  local res = math.fmod(angle, 360.0)
   if res < 0 then
       res = res + 360.0
   end
   return res
end

-- Returns the angle in range -180-180
function wrap_180(angle)
  local res = wrap_360(angle)
  if res > 180 then
     res = res - 360
  end
  return res
end

-- Start up the script
return _init, 2000
