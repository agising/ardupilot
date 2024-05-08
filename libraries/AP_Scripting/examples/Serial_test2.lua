-- From https://discuss.ardupilot.org/t/problem-with-opening-portby-script-in-pixhawk-cube-orange/104815
--[[
Skrypt LUA dekodujący ramkę MAVLink2 przychodzącą z managera silnika.
Zdekodowane dane są deklarowane w Mission Planner jako zmienne użytkownika i są wyswietlane 
z przedrostkiem MAV_ w oknie gdzie wybiera się źródło danych dla panelu Quick
w Quick trzeba kliklnąć w jedną z liczb, wtedy otwiera się powyższe okno z naszymi danymi.

Ustawienie:
Wybieramy wolny port UART w pixhawku np. Telem2
1) CONFIG -> Standard Param -> Telemetry 2 Baud Rate = 57600
2) CONFIG -> Standard Param -> Telemetry 2 protocol selection = Scripting (28)


(c) Piotr Laskowski 
Opracowano na bazie kodu napisanego przez Stephen Dade (stephen_dade@hotmail.com)


https://ardupilot.org/plane/docs/common-serial-options.html  !Uwaga - numery portów są blędne
Serial 0    USB port
Serial 1    Telemetry port 1
Serial 2    Telemetry port 2
Serial 3    GPS1 port
Serial 4    GPS2 port
Serial 5    USER port
Serial 6    USER port
Serial 7    USER port
--]]


gcs:send_text(0, "Start MAVLink LUA script")
--local port = serial:find_serial(0)  -- 0=Telem1
local port = serial:find_serial(1)  -- 1=Telem2
--local port = serial:find_serial(2)  -- 2=GPS2 
--local port = serial:find_serial(3)  -- 3=GPS1 (sprawdzić)



if not port == 0 then
    gcs:send_text(0, "No Scriping Serial Port: "  .. tostring(port))
    return
end

port:begin(57600)
port:set_flow_control(0)



local function MAVLinkProcessor()
    -- public fields
    local self = {
        -- define MAVLink message id's
        EFI_STATUS  = 225
    }

    -- private fields
    local _mavbuffer = ""     -- bufer for incoming data
    local _mavresult = {}     -- buffer for parts of frame body  
    local _payload_len = 0
    local _mavdecodestate = 0 -- 0=looking for marker, 1=getting header,2=getting payload,3=getting crc
    PROTOCOL_MARKER_V2 = 0xFD
    HEADER_LEN_V2 = 10
    EFI_FRAME_LEN = 73
    --local _txseqid = 0
    

    -- AUTOGEN from MAVLink generator
    local _crc_extra = {}
    _crc_extra[75] = 0x9e
    _crc_extra[76] = 0x98
    _crc_extra[235] = 0xb3
    _crc_extra[73] = 0x26

    local _messages = {}
    _messages[225] = { -- EFI_STATUS 
        {"ecu_index", "<f"}, {"rpm", "<f"}, {"fuel_consumed", "<f"}, {"fuel_flow", "<f"}, {"engine_load", "<f"}, {"throttle_position", "<f"}, 
        {"spark_dwell_time", "<f"}, {"barometric_pressure", "<f"}, {"intake_manifold_pressure", "<f"}, {"intake_manifold_temperature", "<f"}, 
        {"cylinder_head_temperature", "<f"}, {"ignition_timing", "<f"}, {"injection_time", "<f"}, {"exhaust_gas_temperature", "<f"}, 
        {"throttle_out", "<f"}, {"pt_compensation", "<f"}, {"health", "<B"}, {"ignition_voltage", "<f"}, {"fuel_pressure", "<f"}
    }	


    function self.generateCRC(buffer)
        -- generate the x25crc for a given buffer. Make sure to include crc_extra!
        local crc = 0xFFFF
        for i = 1, #buffer do
            local tmp = string.byte(buffer, i, i) ~ (crc & 0xFF)
            tmp = (tmp ~ (tmp << 4)) & 0xFF
            crc = (crc >> 8) ~ (tmp << 8) ~ (tmp << 3) ~ (tmp >> 4)
            crc = crc & 0xFFFF
        end
        return string.pack("<H", crc)
    end

--------------------------------------------------------------------------------
-- parse a new byte and see if we've got MAVLink 2 message
-- returns true if a packet was decoded, false otherwise
    function self.parseMAVLink(byte)        
        _mavbuffer = _mavbuffer .. string.char(byte)
        --gcs:send_text(0, "ds:" .. tostring(_mavdecodestate))

        --gcs:send_text(0, "mbuf size: " .. tostring(#_mavbuffer) .. "ds: " .. tostring(_mavdecodestate))

        -- parse buffer to find MAVLink packets
        --if #_mavbuffer == 1 and string.byte(_mavbuffer, 1) == PROTOCOL_MARKER_V2 and _mavdecodestate == 0 then
        if _mavdecodestate == 0 then
            if #_mavbuffer == 1 and string.byte(_mavbuffer, 1) == PROTOCOL_MARKER_V2 then
                _mavdecodestate = 1
                --gcs:send_text(0, "Header")
                return false
            else
                _mavbuffer = ""
            end
        end

        -- if we have a full header, try parsing
        if #_mavbuffer == HEADER_LEN_V2 and _mavdecodestate == 1 then
            -- wartosc, reszta = string.unpack("format", string, pozycja=1)
            _payload_len, _ = string.unpack("<B", _mavbuffer, 2)            
            _mavresult.seq, _mavresult.sysid, _mavresult.compid, _ = string.unpack("<BBB", _mavbuffer, 5)            
            _mavresult.msgid, _ = string.unpack("I3", _mavbuffer, 8)
            --gcs:send_text(0, "sys:" .. tostring(_mavresult.sysid) ..", comp:" .. tostring(_mavresult.compid) ..", msgid:" .. tostring(_mavresult.msgid) ..", seq:" .. tostring(_mavresult.seq))
            _mavdecodestate = 2
            return false
        end

        -- get payload
        if _mavdecodestate == 2 and #_mavbuffer == (_payload_len + HEADER_LEN_V2) then
            _mavdecodestate = 3
            _mavresult.payload = string.sub(_mavbuffer, HEADER_LEN_V2 + 1)

            --gcs:send_text(0, "pay: " .. tostring(_payload_len) ..", len: " .. tostring(#_mavresult.payload))
            return false
        end

        -- get crc, then process if CRC ok
        if _mavdecodestate == 3 and #_mavbuffer == (_payload_len + HEADER_LEN_V2 + 2) then
            _mavdecodestate = 0
            _mavresult.crc = string.sub(_mavbuffer, -2, -1)

            local message_map = _messages[_mavresult.msgid]
            if not message_map then
                -- we don't know how to decode this message, bail on it
                _mavbuffer = ""
                return true
            end

            -- ignoruj ramki EFI_STATUS  o rozmiarze innym niż domyślny
            if  _mavresult.msgid == 225 and _payload_len ~= EFI_FRAME_LEN then
                _mavbuffer = ""
                gcs:send_text(3, "Wrong frame len")
                return true
            end

            -- check CRC, if message defined
            local crc_extra_msg = _crc_extra[_mavresult.msgid]
            if crc_extra_msg ~= nil then
                local calccrc = self.generateCRC( string.sub(_mavbuffer, 2, -3) .. string.char(crc_extra_msg))
                if _mavresult.crc ~= calccrc then
                    gcs:send_text(3, "Bad CRC: " .. self.bytesToString(_mavbuffer, -2, -1) .. ", " .. self.bytesToString(calccrc, 1, 2))
                    _mavbuffer = ""
                    return
                end
            end            

            -- map all the fields out
            local offset = 1
            for _, v in ipairs(message_map) do 
                _mavresult[v[1]], offset = string.unpack(v[2], _mavresult.payload, offset)
            end
            _mavbuffer = ""
            gcs:send_text(0, "Decoded")
           
            gcs:send_named_float("Head1_temp", _mavresult.cylinder_head_temperature)
            gcs:send_named_float("Head2_temp", _mavresult.exhaust_gas_temperature)
            gcs:send_named_float("Local_temp", _mavresult.ignition_timing)

            gcs:send_named_float("Motor_RPM", _mavresult.rpm)
            gcs:send_named_float("Fuel_Lev",  _mavresult.fuel_consumed)
            gcs:send_named_float("Health",    _mavresult.health)
            gcs:send_named_float("Throttle",  _mavresult.throttle_out)
            gcs:send_named_float("Ign_volt",  _mavresult.ignition_voltage)

            --zmienne debugujące
            gcs:send_named_float("Cap_sens1", _mavresult.spark_dwell_time)
            gcs:send_named_float("Cap_sens2", _mavresult.barometric_pressure)
            gcs:send_named_float("Cap_sens3", _mavresult.intake_manifold_pressure)
            gcs:send_named_float("Cap_sens4", _mavresult.intake_manifold_temperature)
            gcs:send_named_float("Test",      _mavresult.fuel_pressure)     
            
            gcs:send_named_float("Fuel_Min",  _mavresult.engine_load)  
            gcs:send_named_float("Fuel_Max",  _mavresult.throttle_position)  
            return true
        end

        -- packet too big ... start again
        if #_mavbuffer > 263 then 
            _mavbuffer = "" 
            gcs:send_text(0, "To big:" .. tostring(_mavdecodestate))
            _mavdecodestate = 0
        end        
        return false
    end

    function self.bytesToString(buf, start, stop)
        local ret = ""
        for idx = start, stop do
            ret = ret .. string.format("0x%x ", buf:byte(idx), 1, -1) .. " "
        end
        return ret
    end

    

    -- return the instance
    return self
end


-- Define the MAVLink processor
local mavlink = MAVLinkProcessor()


function HLSatcom()
    -- read in any bytes from UART and and send to MAVLink processor
    -- only read in 1 packet at a time to avoid time overruns
    while port:available() > 0 do
        -- local byte = port:read()
        -- if mavlink.parseMAVLink(byte) then break end

        if mavlink.parseMAVLink(port:read()) then 
            break 
        end
    end

   
    return HLSatcom, 100
end

return HLSatcom, 100