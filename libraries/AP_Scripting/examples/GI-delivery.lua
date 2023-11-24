-- This script is a test for AP_Mission bindings

local last_mission_index = 0
local next_drop_index = 2
local plant_switch_channel = 10
local plant_switch_high = 1600
local drop_switch_channel = 7
local drop_switch_drop = 1900
local drop_switch_grab = 1100
local loop_time = 1000
local _INFO = 6
local _NOTICE = 5
local _WARNING = 4
local state = "RESET"
local previous_state = ""

local _flight_mode_STABILIZED = 0
local _flight_mode_AUTO = 3
local _flight_mode_GUIDED = 4
local _fligth_mode_RTL = 6
local _flight_mode_POSHOLD = 16

local hover_thr = 100               -- Hover throttle to identify, 100 is safe init
local average_thr = 99              -- Average throttle, 99 is safe init
local thr_ident_loops = 0           -- Number of loops used to ident hover thr
local hover_thr = 100               -- Limit to go below to stop descending, 100 is safe
local throttle_drop_limit = -0.05   -- Throttle descrease to detect cargo touch down, shall be negative
local descent_rate = 0.5            -- Positive vel_z is descending
local descend_start_alt = 0


function update() -- this is the loop which periodically runs
  
  -- local _mission_index = mission:get_current_nav_index()
  -- send_to_gcs(_INFO, string.format("Mission index from vehicle is %d", _mission_index))



  if state == "RESET" then
    -- To do once every time state is initiated
    if previous_state ~= "RESET" then
      announce_state_if_new("RESET")
      -- Grab cargo if not already grabbed
      SRV_Channels:set_output_pwm_chan(drop_switch_channel, drop_switch_grab)
      send_to_gcs(_NOTICE, "Grabbing PL")
    end
    
    -- servo.set_output(drop_switch_channel, drop_switch_grab)
    -- get flight mode and mission state, wait for AUTO and mission running
    local flight_mode = vehicle:get_mode()
    local mission_state = mission:state()
    if flight_mode == _flight_mode_AUTO and mission_state == mission.MISSION_RUNNING then
      -- start tracking wp numbers, init last_mission_index
      last_mission_index = mission:get_current_nav_index()
      state = "ON_MISSION"
    end
    return update, loop_time
  end

  -- If state ON_MISSION
  if state == "ON_MISSION" then
    if previous_state ~= "ON_MISSION" then
      announce_state_if_new("ON_MISSION")
    end
   
    -- get mission state
    local mission_state = mission:state()
    -- make sure the mission is running when looking for wp change
    if mission_state == mission.MISSION_COMPLETE then
      send_to_gcs(_INFO, "LUA: Mission Complete")
      state = "RESET"
      return update, loop_time -- reschedules the loop
    elseif mission_state == mission.MISSION_STOPPED then
      send_to_gcs(_NOTICE, "LUA: Mission stopped")
      -- This happens when reaching the last wp
      -- We are mission the last drop off
      
      -- what to do more?
      return update, loop_time -- reschedules the loop
    end

    -- Update mission_index
    local mission_index = mission:get_current_nav_index()

    -- Look for arriving at altitude after take-off
    if mission_index == 2 and mission_index ~= last_mission_index then
      
      -- Update mission index state
      last_mission_index = mission_index
      -- Modify where to go
      if mission:set_current_cmd(next_drop_index) then
        send_to_gcs(_NOTICE, string.format("LUA: Going to next drop location: wp%d", next_drop_index))
      else
        send_to_gcs(_WARNING, "LUA: Could not set next drop location. Pay attention!")
      end
    end


    -- If we have arrived to drop wp
    if mission_index == (next_drop_index + 1) and mission_index ~= last_mission_index then

      -- Update mission index state
      last_mission_index = mission_index
    
      -- we just continued the mission, lets see..
      -- If the switch is set, stop and make a drop. Otherwise just pass
      local plant_switch = rc:get_pwm(plant_switch_channel)
      
      send_to_gcs(_INFO, string.format("Plant switch PWM is: %d", plant_switch))

      -- If switch is not set, just looop
      if not plant_switch then
        send_to_gcs(_WARNING, "Plant switch could not be read")
        return update, loop_time
      elseif plant_switch < plant_switch_high then
        send_to_gcs(_NOTICE, string.format("Plant switch not high: %d", plant_switch))
        -- Skip this drop location, aim for next
        next_drop_index = mission_index
        return update, loop_time
      end

      -- Ok, we should drop a box, 
      -- set guided mode
      vehicle:set_mode(_flight_mode_GUIDED)
      stop()
      
      -- prepare where next drop is going to be, if there are more dropes planned
      -- num commands includes home so - 1
      local mission_length = mission:num_commands() - 1
      if mission_length > next_drop_index then
        next_drop_index = next_drop_index + 1
        send_to_gcs(_NOTICE, "Planning for an other drop after this one")
      end     

      -- Init thr filter and change state to THR_IDENT
      init_hover_thr_ident()
      state = "THR_IDENT"
      return update, loop_time
    end

    -- loop fast to quickly find wp change. No other computations are done.
    return update, loop_time/4
  end
  
  -- state_THR_IDENT
  if state == "THR_IDENT" then 
    if previous_state ~= "THR_IDENT" then
      announce_state_if_new("THR_IDENT")
    end

    -- Build average
    hover_thr = (hover_thr + motors:get_throttle())/2
    thr_ident_loops = thr_ident_loops + 1
    -- 4 loops, 4 averagings of a total of 5 values
    if thr_ident_loops == 4 then
      -- init average throttle to hover throttle
      average_thr = hover_thr
      descend_start_alt = get_alt()
      send_to_gcs(_INFO, string.format("Hover throttle identified to %0.1f, start descent", average_thr))
      send_to_gcs(_INFO, string.format("Starting descent from %0.1f meters", descend_start_alt/100))
      state = "DESCEND"
    end
    -- return quicker in this state
    return update, loop_time/2
  end
  
  -- state_DESCEND
  if state == "DESCEND" then
    if previous_state ~= "DESCEND" then
      announce_state_if_new("DESCEND")
    end

      -- Check mode is GUIDED
    if not vehicle:get_mode() == _flight_mode_GUIDED then
      send_to_gcs(_WARNING, "Mode is not GUIDED during state DESCEND, Resetting script")
      stop()
      return update, loop_time
    end

    -- Try to read thr
    local thr = motors:get_throttle()
    if thr == nil then
      send_to_gcs(_WARNING, "Could not read throttle, Resetting script")
      stop()
      return update, loop_time
    end

    -- Look for cargo touch down
    average_thr = (average_thr + thr)/2    
    send_to_gcs(_NOTICE, string.format("Throttle running average is %0.1f, limit is %0.1f", average_thr, (hover_thr - throttle_drop_limit)))
    if average_thr - hover_thr < throttle_drop_limit then
      -- We have cargo touch down, drop and RTL and start over
      stop()
      -- drop cargo!
      SRV_Channels:set_output_pwm_chan(drop_switch_channel, drop_switch_drop)
      --servo.set_output(drop_switch_channel, drop_switch_drop)
      send_to_gcs(_NOTICE, "Box dropped, RTL to replenish")
      vehicle:set_mode(_fligth_mode_RTL)
      state = "RESET"
      return update, loop_time
    end
    
    -- For simulation, look for meters descent
    local alt = get_alt()
    send_to_gcs(_NOTICE, string.format("Altitude descending %0.1f m", alt))
    if descend_start_alt - alt > 10 then
      -- We have cargo touch down, drop and RTL and start over
      stop()
      -- drop cargo!
      SRV_Channels:set_output_pwm_chan(drop_switch_channel, drop_switch_drop)
      --servo.set_output(drop_switch_channel, drop_switch_drop)
      send_to_gcs(_NOTICE, "Box dropped, RTL to replenish")
      vehicle:set_mode(_fligth_mode_RTL)
      state = "RESET"
      return update, loop_time
    end

    -- No abort condition met, continue descending
    vel_xyz(0, 0, descent_rate)

    return update, loop_time/2
  end

  return update, 1000 -- reschedules the loop
end

-- Helper functions

-- Print to GCS
function send_to_gcs(level, mess)
  gcs:send_text(level, mess)
end

-- Reset, stop and reset the state machine
function reset(mess)
  -- try to send 0 velocity
  stop()
  send_to_gcs(_NOTICE, mess)
  state = "RESET"
  hover_thr = 100
  average_thr = 99
  thr_ident_loops = 0
  
end

-- Stop, try to set velicities to 0. Will only work in GUIDED
function stop()
  -- Command will only go through in GUIDED
  vel_xyz(0,0,0)
end

-- Init the hover throttle identification code
function init_hover_thr_ident()
  hover_thr = motors:get_throttle()
  thr_ident_loops = 0
end

function get_alt()
  local pos = ahrs:get_position()
  local baroalt = baro:get_altitude()
  -- send_to_gcs(_NOTICE, string.format("pos altitude is %0.1f", pos:alt()))
  -- send_to_gcs(_NOTICE, string.format("baro altitude is %0.1f", baroalt))
  -- local _ABSOLUTE = 0
  -- local _ABOVE_HOME = 1
  -- local _ABOVE_ORIGIN = 2
  -- local _ABOVE_TERRAIN = 3
  return pos:alt()/100
end

-- Send velocity command, will only work in GUIDED mode
function vel_xyz(vel_x, vel_y,vel_z)
  local target_vel = Vector3f()
  target_vel:x(vel_x)
  target_vel:y(vel_y)
  target_vel:z(vel_z)

  if not (vehicle:set_target_velocity_NED(target_vel)) then
    send_to_gcs(_WARNING, "Failed to execute velocity command")
    -- Should we reset?
  end
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

function announce_state_if_new(state_name)
  if previous_state ~= state_name then
    send_to_gcs(_NOTICE, "State machine changed state: " .. state_name)
  end
  previous_state = state_name
end
  
-- Start up the script
return update, 5000

-- print the current and previous nav commands
-- gcs:send_text(0, string.format("Prev: %d, Current: %d",mission:get_prev_nav_cmd_id(),mission:get_current_nav_id()))
