-- VECTRIC LUA SCRIPT
-- Name = Nudge To Guide
-- Version = 1.1
-- Help = Nudges selected circles/notches onto a guide line, arc, or
--        polyline (the last-selected object), with an option to
--        evenly distribute them along it afterwards. Run "Undo
--        Last PGC Change" (PGC_Undo_Last) to reverse this if
--        VCarve's own Ctrl+Z doesn't offer the option.

require("strict")


----------------------------------------------------------------
-- PGC UNDO LOG (shared with PGC_Undo_Last.lua - keep in sync)
--
-- File-based undo log used by PGC_* gadgets that modify the
-- drawing, so "Undo Last PGC Change" can reverse the most recent
-- one even in a completely separate gadget run (VCarve's own
-- Ctrl+Z does not see changes gadgets make).
--
-- Lives one folder up from every gadget (the shared Gadgets
-- folder) so any PGC_* gadget can find it.
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

function PGC_AppendUndoEntry(script_path, gadget_name, ops)

    if ops == nil or #ops == 0 then
        return
    end

    local log_path = PGC_GetUndoLogPath(script_path)
    local entries = PGC_ReadUndoEntries(log_path)

    local entry = {}
    table.insert(entry, "gadget=" .. gadget_name)
    table.insert(entry, "time=" .. os.date("%Y-%m-%dT%H:%M:%S"))

    for _, op in ipairs(ops) do
        table.insert(entry, op)
    end

    table.insert(entries, entry)

    while #entries > PGC_UNDO_LOG_MAX_ENTRIES do
        table.remove(entries, 1)
    end

    PGC_WriteUndoEntries(log_path, entries)

end


----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------

-- Whether to evenly redistribute the objects along the guide
-- after nudging them onto it. Set from the options dialog (see
-- GetUserChoices) and remembered in the registry between runs.
g_distribute_evenly = false


----------------------------------------------------------------
-- Ask the user whether to evenly distribute after nudging.
----------------------------------------------------------------

function GetUserChoices(script_path)

    local registry = Registry("PGC_NudgeToGuide")
    g_distribute_evenly = registry:GetBool("DistributeEvenly", g_distribute_evenly)

    local html_path = "file:" .. script_path .. "\\PGC_Nudge_To_Guide.htm"
    local dialog = HTML_Dialog(false, html_path, 440, 260, "Nudge To Guide")

    dialog:AddCheckBox("DistributeEvenly", g_distribute_evenly)

    if not dialog:ShowDialog() then
        return false
    end

    g_distribute_evenly = dialog:GetCheckBox("DistributeEvenly")

    registry:SetBool("DistributeEvenly", g_distribute_evenly)

    return true
end


----------------------------------------------------------------
-- Find the last-selected object
----------------------------------------------------------------

function GetLastSelectedObject(selection)

    local pos = selection:GetTailPosition()

    if pos == nil then
        return nil
    end

    local object
    object, pos = selection:GetPrev(pos)

    return object
end


----------------------------------------------------------------
-- Copy the current selection into a normal Lua table.
--
-- IMPORTANT:
-- GetNext() returns BOTH the object and the new position.
----------------------------------------------------------------

function GetSelectedObjects(selection)

    local objects = {}

    local pos = selection:GetHeadPosition()

    while pos ~= nil do

        local object

        object, pos = selection:GetNext(pos)

        if object ~= nil then
            table.insert(objects, object)
        end

    end

    return objects
end


----------------------------------------------------------------
-- Find the point on an object that should be nudged onto the
-- guide.
--
-- For a grouped notch (circle + flat/keyway) we deliberately DO
-- NOT use the group's own bounding-box center, since the flat
-- can shift that off the true circle center. Instead we look
-- for the largest closed contour in the group - the same
-- approach used by PGC_Replace_Circles.
--
-- For anything else (a plain circle, etc.) the bounding-box
-- center is the object's center.
----------------------------------------------------------------

function FindObjectAnchorPoint(object)

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
-- Sample the guide contour at (roughly) equal arc-length
-- intervals, recording the cumulative arc length (S) at each
-- sample so we can both find the closest point on the guide and
-- (for the "distribute evenly" option) interpolate a point at
-- any arc length along it.
----------------------------------------------------------------

function BuildGuideSamples(contour, sample_count)

    if contour == nil or contour.IsEmpty then
        return nil
    end

    local length = contour.Length

    if length <= 0 then
        return nil
    end

    local step = length / sample_count

    local carriage = ContourCarriage(0, 0.0)

    if carriage.IsInvalid then
        return nil
    end

    local samples = {}
    local arc_length = 0.0

    if contour.IsClosed then

        for i = 0, sample_count - 1 do

            local point = carriage:Position(contour)

            if point == nil then
                return nil
            end

            table.insert(samples, { X = point.X, Y = point.Y, S = arc_length })

            local moved = carriage:Move(contour, step)
            arc_length = arc_length + step

            if not moved then
                break
            end

        end

    else

        for i = 0, sample_count do

            local point = carriage:Position(contour)

            if point == nil then
                return nil
            end

            table.insert(samples, { X = point.X, Y = point.Y, S = arc_length })

            if i < sample_count then

                local moved = carriage:Move(contour, step)

                if not moved then
                    break
                end

                arc_length = arc_length + step

            end

        end

    end

    return samples

end


----------------------------------------------------------------
-- Index of the sample closest to the given point.
----------------------------------------------------------------

function FindClosestSampleIndex(samples, point)

    local best_index = nil
    local best_dist_sq = math.huge

    for i, sample in ipairs(samples) do

        local dx = sample.X - point.X
        local dy = sample.Y - point.Y
        local dist_sq = (dx * dx) + (dy * dy)

        if dist_sq < best_dist_sq then
            best_dist_sq = dist_sq
            best_index = i
        end

    end

    return best_index

end


----------------------------------------------------------------
-- Interpolate a point at a given arc length (S) along the
-- sampled guide. Used to place objects at exact even spacing
-- rather than snapping to the nearest coarse sample.
----------------------------------------------------------------

function GetPointAtArcLength(samples, s)

    local first = samples[1]
    local last = samples[#samples]

    if s <= first.S then
        return Point2D(first.X, first.Y)
    end

    if s >= last.S then
        return Point2D(last.X, last.Y)
    end

    for i = 1, #samples - 1 do

        local a = samples[i]
        local b = samples[i + 1]

        if s >= a.S and s <= b.S then

            local span = b.S - a.S
            local t = 0.0

            if span > 0 then
                t = (s - a.S) / span
            end

            local x = a.X + ((b.X - a.X) * t)
            local y = a.Y + ((b.Y - a.Y) * t)

            return Point2D(x, y)

        end

    end

    return Point2D(last.X, last.Y)

end


----------------------------------------------------------------
-- Move an object so its anchor point lands on the given target
-- point.
----------------------------------------------------------------

function MoveAnchorTo(object, anchor, target_point)

    local move_vector = target_point - anchor
    local move_matrix = TranslationMatrix2D(move_vector)

    object:Transform(move_matrix)

end


----------------------------------------------------------------
-- Main
----------------------------------------------------------------

function main(script_path)

    ----------------------------------------------------------------
    -- Check for an open job
    ----------------------------------------------------------------

    local job = VectricJob()

    if not job.Exists then
        DisplayMessageBox("No job loaded.")
        return false
    end


    ----------------------------------------------------------------
    -- Get selection
    ----------------------------------------------------------------

    local selection = job.Selection

    if selection.IsEmpty then
        DisplayMessageBox(
            "Select the circles/notches you want to align, then " ..
            "Shift-select the guide line, arc, or polyline LAST."
        )
        return false
    end


    ----------------------------------------------------------------
    -- Get all selected objects BEFORE changing anything.
    ----------------------------------------------------------------

    local selected_objects = GetSelectedObjects(selection)

    if #selected_objects < 2 then
        DisplayMessageBox(
            "Select at least one object to align, then Shift-select " ..
            "the guide line/arc last."
        )
        return false
    end


    ----------------------------------------------------------------
    -- The last selected object is the guide curve.
    ----------------------------------------------------------------

    local guide_object = GetLastSelectedObject(selection)

    if guide_object == nil then
        DisplayMessageBox("Could not determine the guide object.")
        return false
    end

    local guide_contour = guide_object:GetContour()

    if guide_contour == nil or guide_contour.IsEmpty then
        DisplayMessageBox(
            "The last selected object must be a line, arc, or " ..
            "polyline to use as the guide."
        )
        return false
    end


    ----------------------------------------------------------------
    -- Everything except the guide is a target to align.
    ----------------------------------------------------------------

    local targets = {}

    for i = 1, #selected_objects - 1 do

        local object = selected_objects[i]

        if object ~= nil then
            table.insert(targets, object)
        end

    end

    if #targets < 1 then
        DisplayMessageBox(
            "Select at least one object to align, then Shift-select " ..
            "the guide line/arc last."
        )
        return false
    end


    ----------------------------------------------------------------
    -- Ask the user whether to evenly distribute after nudging.
    ----------------------------------------------------------------

    if not GetUserChoices(script_path) then
        return false -- user cancelled dialog
    end


    ----------------------------------------------------------------
    -- Sample the guide curve. Resolution adapts to the job's own
    -- geometry tolerance so this works sensibly in both inch and
    -- mm jobs without asking the user to pick a number.
    ----------------------------------------------------------------

    local tolerance = GetDefaultContourTolerance()
    local sample_step = tolerance * 2.0

    if sample_step <= 0 then
        sample_step = 0.01
    end

    local sample_count = math.ceil(guide_contour.Length / sample_step)

    if sample_count < 200 then
        sample_count = 200
    end

    if sample_count > 4000 then
        sample_count = 4000
    end

    local guide_samples = BuildGuideSamples(guide_contour, sample_count)

    if guide_samples == nil then
        DisplayMessageBox("Could not sample the guide curve.")
        return false
    end


    ----------------------------------------------------------------
    -- Find each target's anchor point and its closest point on
    -- the guide.
    ----------------------------------------------------------------

    local aligned = {}
    local skipped_count = 0

    for _, target in ipairs(targets) do

        local anchor = FindObjectAnchorPoint(target)

        if anchor == nil then

            skipped_count = skipped_count + 1

        else

            local closest_index = FindClosestSampleIndex(guide_samples, anchor)
            local closest_sample = guide_samples[closest_index]

            table.insert(
                aligned,
                {
                    object = target,
                    anchor = anchor,
                    arc_length = closest_sample.S
                }
            )

        end

    end

    if #aligned == 0 then
        DisplayMessageBox(
            "None of the selected objects had usable geometry to align."
        )
        return false
    end


    ----------------------------------------------------------------
    -- Step 1: Nudge every object onto the guide.
    ----------------------------------------------------------------

    for _, entry in ipairs(aligned) do

        local target_point = GetPointAtArcLength(guide_samples, entry.arc_length)

        MoveAnchorTo(entry.object, entry.anchor, target_point)

    end


    ----------------------------------------------------------------
    -- Step 2 (optional): Evenly distribute along the guide,
    -- between the first and last object's position, preserving
    -- their order along the guide.
    ----------------------------------------------------------------

    if g_distribute_evenly and #aligned >= 2 then

        table.sort(
            aligned,
            function(a, b) return a.arc_length < b.arc_length end
        )

        local s_min = aligned[1].arc_length
        local s_max = aligned[#aligned].arc_length
        local step = (s_max - s_min) / (#aligned - 1)

        for i, entry in ipairs(aligned) do

            local new_s = s_min + (step * (i - 1))
            local target_point = GetPointAtArcLength(guide_samples, new_s)

            -- Re-find the anchor now, since the object already
            -- moved once in Step 1.
            local current_anchor = FindObjectAnchorPoint(entry.object)

            MoveAnchorTo(entry.object, current_anchor, target_point)

        end

    end


    ----------------------------------------------------------------
    -- Record how to undo this run.
    --
    -- Every move here is a pure translation (no rotation), so the
    -- net effect on each object - however many steps it went
    -- through above - is just the vector from where it started to
    -- where it ended up. We log the ORIGINAL anchor (before Step 1)
    -- and the FINAL anchor (now) so "Undo Last PGC Change" can find
    -- the object by its final position and move it back to the
    -- original one.
    --
    -- We identify the object by position rather than its internal
    -- ID - Vectric's RawId/RawLayerId values can't be converted
    -- with tostring() in this Lua build.
    ----------------------------------------------------------------

    local undo_ops = {}

    for _, entry in ipairs(aligned) do

        local final_anchor = FindObjectAnchorPoint(entry.object)

        if final_anchor ~= nil then

            -- Wrapped in pcall so any surprise in the undo
            -- bookkeeping can't undermine work that's already done.
            pcall(
                function()
                    table.insert(
                        undo_ops,
                        string.format(
                            "op=translate ox=%.8f oy=%.8f fx=%.8f fy=%.8f",
                            entry.anchor.X,
                            entry.anchor.Y,
                            final_anchor.X,
                            final_anchor.Y
                        )
                    )
                end
            )

        end

    end

    pcall(PGC_AppendUndoEntry, script_path, "PGC_Nudge_To_Guide", undo_ops)


    ----------------------------------------------------------------
    -- Select the aligned objects for visual feedback.
    ----------------------------------------------------------------

    selection:Clear()

    for _, entry in ipairs(aligned) do
        selection:Add(entry.object, true, true)
    end

    selection:GroupSelectionFinished()

    job:Refresh2DView()


    ----------------------------------------------------------------
    -- Report result.
    ----------------------------------------------------------------

    local message =
        "Aligned " .. tostring(#aligned) .. " object(s) to the guide."

    if g_distribute_evenly and #aligned >= 2 then
        message = message .. "\nEvenly distributed along the guide."
    end

    if skipped_count > 0 then
        message = message ..
            "\n\nSkipped " .. tostring(skipped_count) ..
            " object(s) with no usable geometry."
    end

    DisplayMessageBox(message)

    return true

end
