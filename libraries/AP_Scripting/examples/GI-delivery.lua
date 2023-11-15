-- This script is a test for AP_Mission bindings

local last_mission_index = mission:get_current_nav_index()
local plant_switch_channel = 10
local plant_switch_high = 1600
local loop_time = 1100
local _NOTICE = 5
local _WARNING = 4
local state = 0
local _state_RESET = 0
local _state_ON_MISSION = 1
local _state_THR_IDENT = 2
local _state_DESCEND = 3
local hover_thr = 100               -- Hover throttle to identify, 100 is safe init
local average_thr = 99              -- Average throttle, 99 is safe init
local thr_ident_loops = 0           -- Number of loops used to ident hover thr
local hover_thr = 100               -- Limit to go below to stop descending, 100 is safe
local throttle_drop_limit = -5      -- Throttle descrease to detect cargo touch down, shall be negative
local descent_rate = 0.5            -- Positive vel_z is descending
local copter_guided_mode_num = 4
local copter_rtl_mode_num = 6



function update() -- this is the loop which periodically runs
  
  -- If state ON_MISSION
  if state == _state_ON_MISSION then
    -- get mission state
    local mission_state = mission:state()
    -- make sure the mission is running when looking for wp change
    if mission_state == mission.MISSION_COMPLETE then
      gcs:send_text(0, "LUA: Mission Complete")
      return update, loop_time -- reschedules the loop
    elseif mission_state == mission.MISSION_STOPPED then
      gcs:send_text(0, "LUA: Mission stopped")
      return update, loop_time -- reschedules the loop
    end

    local mission_index = mission:get_current_nav_index()

    -- see if we have changed since we last checked
    if mission_index ~= last_mission_index then
      -- Update mission index state
      last_mission_index = mission_index
      -- we just continued the mission, lets see..
      -- If the switch is set, stop and make a drop. Otherwise just pass
      local plant_switch = rc:get_pwm(plant_switch_channel)
      -- If switch is not set, just looop
      if not plant_switch then
        -- Plant switch could not be read. Loop
        send_to_gcs(_WARNING, "Plant switch could not be read")
        return update, loop_time
      elseif plant_switch < plant_switch_high then
        -- Plant switch is not set high. Loop
        send_to_gcs(_NOTICE, "Plant switch not set")
        return update, loop_time
      end

      -- Ok, we should drop a box, 
      -- set guided mode
      vehicle:set_mode(copter_guided_mode_num)
      stop()
      
      -- manipulate next wp number
      -- num commands includes home so - 1
      local mission_length = mission:num_commands() - 1
      if mission_length > mission_index then
        local jump_to = mission_index + 1
        -- Try to set mission index
        if mission:set_current_cmd(jump_to) then
          gcs:send_text(0, string.format("LUA: jumped to mission item %d",jump_to))
        else
          gcs:send_text(0, "LUA: mission item jump failed")
        end
      end

      -- Use init function to set state to _state_THR_IDENT and init thr filter
      init_hover_thr_ident()

      return update, loop_time
    end
  end
  
  -- state_THR_IDENT
  if state == _state_THR_IDENT then 
    -- Build average
    hover_thr = (hover_thr + motors:get_throttle())/2
    thr_ident_loops = thr_ident_loops + 1
    -- 4 loops, 4 averaging of a total of 5 values
    if thr_ident_loops == 4 then
      -- init average throttle to hover throttle
      average_thr = hover_thr
      state = _state_DESCEND
    end
    -- return quicker in this state
    return update, loop_time/2
  end
  
  -- state_DESCEND
  if state == _state_DESCNED then
    -- Check mode is GUIDED
    if not vehicle:get_mode() == copter_guided_mode_num then
      reset("Not GUIDED")
      return update, loop_time
    end

    -- Try to read thr
    local thr = motors:get_throttle()
    if thr == nil then
      reset("Thr is nil")
      return update, loop_time
    end

    -- Look for cargo touch down
    average_thr = (average_thr + thr)/2
    if average_thr - hover_thr < throttle_drop_limit then
      -- We have cargo touch down, lets stop here for now

      -- Proceed to next state..
      -- state = next_state
      reset("Cargo touch down")
    end

    -- No abort condition met, continue descending
    vel_xyz(0, 0, descent_rate)

    return update, loop_time
  end



    -- if a switch is set

    -- If not last wp, drop box, increase wp-number, RTL to pick up new box.
    
    -- set mode to guided, descend, RTL, bump mission number

    -- print the current and previous nav commands
    -- gcs:send_text(0, string.format("Prev: %d, Current: %d",mission:get_prev_nav_cmd_id(),mission:get_current_nav_id()))

    -- last_mission_index = mission_index;

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
  state = _state_RESET
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
  state = _state_THR_IDENT
  hover_thr = motors:get_throttle()
  thr_ident_loops = 0
end

-- Send velocity command, will only work in GUIDED mode
function vel_xyz(vel_x, vel_y,vel_z)
  local target_vel = Vector3f()
  target_vel:x(vel_x)
  target_vel:y(vel_y)
  target_vel:z(vel_z)

  if not (vehicle:set_target_velocity_NED(target_vel)) then
    gcs:send_text(_WARNING, "Failed to execute velocity command")
    -- Should we reset?
  end
end

-- Start up the script
return update, 5000
