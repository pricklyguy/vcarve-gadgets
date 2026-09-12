-- VECTRIC LUA SCRIPT
-- Name = Undo Last PGC Change
-- Version = 1.1
-- Help = Reverses the most recent change made by a PGC_* gadget
--        (PGC_Rotate, PGC_Nudge_To_Guide, PGC_Replace_Circles).
--        VCarve's own Ctrl+Z does not see changes gadgets make -
--        run this instead. Can be run repeatedly to step back
--        through the last several PGC changes.

require("strict")


----------------------------------------------------------------
-- PGC UNDO LOG (shared with the writing gadgets - keep in sync)
--
-- File-based undo log used by PGC_* gadgets that modify the
-- drawing. Lives one folder up from every gadget (the shared
-- Gadgets folder) so any PGC_* gadget can find it.
----------------------------------------------------------------

PGC_UNDO_LOG_MAX_ENTRIES = 10

function PGC_GetUndoLogPath(script_path)
    return script_path .. "\\..\\PGC_Undo_Log.txt"
end

function PGC_ReadUndoEntries(log_path)

    local entries = {}
    local file = io.open(log_path, "r")

    if file == nil then
        return entries
    end

    local current = nil

    for line in file:lines() do

        if line == "[ENTRY]" then
            current = {}
        elseif line == "[/ENTRY]" then
            if current ~= nil then
                table.insert(entries, current)
                current = nil
            end
        elseif current ~= nil then
            table.insert(current, line)
        end

    end

    file:close()

    return entries

end

function PGC_WriteUndoEntries(log_path, entries)

    local file = io.open(log_path, "w")

    if file == nil then
        return false
    end

    for _, entry in ipairs(entries) do

        file:write("[ENTRY]\n")

        for _, line in ipairs(entry) do
            file:write(line .. "\n")
        end

        file:write("[/ENTRY]\n")

    end

    file:close()

    return true

end


----------------------------------------------------------------
-- Parse one "key=value key=value ..." log line into a table.
----------------------------------------------------------------

function PGC_ParseFields(line)

    local fields = {}

    for key, value in line:gmatch("([%a_]+)=(%S+)") do
        fields[key] = value
    end

    return fields

end


----------------------------------------------------------------
-- Objects are identified by POSITION, not by Vectric's internal
-- RawId/RawLayerId - those can't be converted with tostring() in
-- this Lua build, so they can't be written to a text log at all.
-- Matching by position is a little less exact, but every op below
-- records the exact point the object should be sitting at right
-- now, so a tight tolerance is enough to find the right one.
----------------------------------------------------------------

function PGC_PointsMatch(x1, y1, x2, y2, tolerance)

    local dx = x1 - x2
    local dy = y1 - y2

    return ((dx * dx) + (dy * dy)) <= (tolerance * tolerance)

end


----------------------------------------------------------------
-- Find the point on an object to match against - same rule
-- PGC_Nudge_To_Guide and PGC_Replace_Circles use: for a grouped
-- notch, the center of the largest closed contour inside it
-- (the actual circle); otherwise the bounding-box center.
----------------------------------------------------------------

function PGC_FindObjectPoint(object)

    if object.ClassName == "vcCadObjectGroup" then

        local group = CastCadObjectToCadObjectGroup(object)

        if group == nil or group.IsEmpty then
            return nil
        end

        local best_contour = nil
        local best_area = 0.0

        local pos = group:GetHeadPosition()

        while pos ~= nil do

            local child

            child, pos = group:GetNext(pos)

            if child ~= nil then

                local contour = child:GetContour()

                if contour ~= nil and contour.IsClosed then

                    local area = contour.Area

                    if area > best_area then
                        best_area = area
                        best_contour = contour
                    end

                end
            end
        end

        if best_contour == nil then
            return nil
        end

        return best_contour.BoundingBox2D.Center

    else

        local bbox = object:GetBoundingBox()

        if bbox == nil then
            return nil
        end

        return bbox.Center

    end

end


----------------------------------------------------------------
-- Walk every object in every layer, returning the first one for
-- which test_fn(object) returns true, plus the layer it's on.
----------------------------------------------------------------

function PGC_FindObjectWhere(job, test_fn)

    local layer_manager = job.LayerManager
    local layer_pos = layer_manager:GetHeadPosition()

    while layer_pos ~= nil do

        local layer
        layer, layer_pos = layer_manager:GetNext(layer_pos)

        if layer ~= nil then

            local pos = layer:GetHeadPosition()

            while pos ~= nil do

                local object
                object, pos = layer:GetNext(pos)

                if object ~= nil and test_fn(object) then
                    return object, layer
                end

            end

        end

    end

    return nil, nil

end


----------------------------------------------------------------
-- Main
----------------------------------------------------------------

function main(script_path)

    local job = VectricJob()

    if not job.Exists then
        DisplayMessageBox("No job loaded.")
        return false
    end

    local log_path = PGC_GetUndoLogPath(script_path)
    local entries = PGC_ReadUndoEntries(log_path)

    if #entries == 0 then
        DisplayMessageBox(
            "There is nothing to undo.\n\n" ..
            "The PGC undo log is empty (or no PGC_* gadget has " ..
            "run since VCarve was last restarted)."
        )
        return false
    end

    local entry = table.remove(entries)

    -- Match tolerance: a small multiple of the job's own geometry
    -- tolerance, with a sane floor so it still works if that comes
    -- back as zero.
    local tolerance = GetDefaultContourTolerance() * 10.0

    if tolerance < 0.0005 then
        tolerance = 0.0005
    end

    local gadget_name = "a PGC gadget"
    local rotated_count = 0
    local translated_count = 0
    local removed_count = 0
    local restored_count = 0
    local missing_count = 0

    -- Apply in reverse order, in case a later op in the run
    -- depended on an earlier one.
    for i = #entry, 1, -1 do

        local line = entry[i]
        local name = line:match("^gadget=(.+)$")

        if name ~= nil then

            gadget_name = name

        elseif not line:match("^time=") then

            local op = PGC_ParseFields(line)

            if op.op == "rotate" then

                local cx = tonumber(op.cx)
                local cy = tonumber(op.cy)
                local angle = tonumber(op.angle)

                local object = PGC_FindObjectWhere(
                    job,
                    function(candidate)
                        local bbox = candidate:GetBoundingBox()
                        if bbox == nil then
                            return false
                        end
                        local center = bbox.Center
                        return PGC_PointsMatch(center.X, center.Y, cx, cy, tolerance)
                    end
                )

                if object == nil then
                    missing_count = missing_count + 1
                else
                    local center = Point2D(cx, cy)
                    local undo_matrix = RotationMatrix2D(center, -angle)
                    object:Transform(undo_matrix)
                    rotated_count = rotated_count + 1
                end

            elseif op.op == "translate" then

                local ox = tonumber(op.ox)
                local oy = tonumber(op.oy)
                local fx = tonumber(op.fx)
                local fy = tonumber(op.fy)

                local object = PGC_FindObjectWhere(
                    job,
                    function(candidate)
                        local point = PGC_FindObjectPoint(candidate)
                        if point == nil then
                            return false
                        end
                        return PGC_PointsMatch(point.X, point.Y, fx, fy, tolerance)
                    end
                )

                if object == nil then
                    missing_count = missing_count + 1
                else
                    local current_point = PGC_FindObjectPoint(object)
                    local original_point = Point2D(ox, oy)

                    -- TranslationMatrix2D wants a Vector2D, not a
                    -- Point2D - subtracting two points is how the
                    -- other PGC gadgets get one.
                    local move_vector = original_point - current_point
                    local undo_matrix = TranslationMatrix2D(move_vector)
                    object:Transform(undo_matrix)
                    translated_count = translated_count + 1
                end

            elseif op.op == "replace" then

                local cx = tonumber(op.cx)
                local cy = tonumber(op.cy)

                -- The replacement is the group sitting at this
                -- point. Finding it also tells us which layer the
                -- original target lived on, since the replacement
                -- was added to that same layer.
                local replacement, target_layer = PGC_FindObjectWhere(
                    job,
                    function(candidate)
                        if candidate.ClassName ~= "vcCadObjectGroup" then
                            return false
                        end
                        local point = PGC_FindObjectPoint(candidate)
                        if point == nil then
                            return false
                        end
                        return PGC_PointsMatch(point.X, point.Y, cx, cy, tolerance)
                    end
                )

                if replacement == nil or target_layer == nil then

                    missing_count = missing_count + 1

                else

                    -- If a backup of the original circle exists
                    -- (same point, but NOT a group like the
                    -- replacement is), put a copy of it back onto
                    -- the replacement's layer before removing the
                    -- replacement, so the circle actually
                    -- reappears instead of staying parked on the
                    -- backup layer. No backup is normal (and not
                    -- an error) when "Back up replaced circles"
                    -- was off for that run.
                    --
                    -- We have to Clone() it rather than moving the
                    -- existing object across layers - Vectric's
                    -- AddObject refuses an object that already
                    -- belongs to another layer ("luabind: smart
                    -- pointer does not allow ownership transfer"),
                    -- it only accepts a fresh, ownerless object.
                    local backup, backup_layer = PGC_FindObjectWhere(
                        job,
                        function(candidate)
                            if candidate.ClassName == "vcCadObjectGroup" then
                                return false
                            end
                            local point = PGC_FindObjectPoint(candidate)
                            if point == nil then
                                return false
                            end
                            return PGC_PointsMatch(point.X, point.Y, cx, cy, tolerance)
                        end
                    )

                    if backup ~= nil and backup_layer ~= nil then

                        local restored_clone = backup:Clone()

                        if restored_clone ~= nil then
                            target_layer:AddObject(restored_clone, true)
                            backup_layer:RemoveObject(backup)
                            restored_count = restored_count + 1
                        end

                    end

                    target_layer:RemoveObject(replacement)
                    removed_count = removed_count + 1

                end

            end

        end

    end

    -- Save the log with this entry removed, so running this again
    -- steps back one more PGC change.
    PGC_WriteUndoEntries(log_path, entries)

    job:Refresh2DView()

    local message = "Undid: " .. gadget_name

    if rotated_count > 0 then
        message = message .. "\nUn-rotated " .. tostring(rotated_count) .. " object(s)"
    end

    if translated_count > 0 then
        message = message .. "\nMoved back " .. tostring(translated_count) .. " object(s)"
    end

    if removed_count > 0 then
        message = message .. "\nRemoved " .. tostring(removed_count) .. " newly-created object(s)"
    end

    if restored_count > 0 then
        message = message .. "\nRestored " .. tostring(restored_count) .. " backed-up object(s)"
    end

    if missing_count > 0 then
        message = message .. "\n\n" .. tostring(missing_count) ..
            " object(s) from that change could not be found " ..
            "(moved, edited, or deleted since) and were skipped."
    end

    if #entries > 0 then
        message = message .. "\n\nRun this again to undo the change before that."
    end

    DisplayMessageBox(message)

    return true

end
