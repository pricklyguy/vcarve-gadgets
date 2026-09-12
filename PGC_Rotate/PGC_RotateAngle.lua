-- VECTRIC LUA SCRIPT
-- Name = Rotate Each Object By Angle
-- Version = 1.1
-- Help = Rotates every selected object by a user-specified angle around its own center.
--        Run "Undo Last PGC Change" (PGC_Undo_Last) to reverse this if VCarve's own
--        Ctrl+Z doesn't offer the option.

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


g_rotate_angle = 90.0

function GetUserAngle(script_path)

    -- load last-used angle from the registry
    local registry = Registry("PGC_RotateAngle")
    g_rotate_angle = registry:GetDouble("RotateAngle", g_rotate_angle)

    local html_path = "file:" .. script_path .. "\\PGC_RotateAngle.htm"
    local dialog = HTML_Dialog(false, html_path, 420, 280, "Rotate Each Object")

    dialog:AddDoubleField("RotateAngle", g_rotate_angle)

    if not dialog:ShowDialog() then
        return false
    end

    g_rotate_angle = dialog:GetDoubleField("RotateAngle")

    -- save as default for next time
    registry:SetDouble("RotateAngle", g_rotate_angle)

    return true
end

function main(script_path)

    -- Check for an open job
    local job = VectricJob()

    if not job.Exists then
        DisplayMessageBox("No job loaded.")
        return false
    end

    -- Get current selection
    local selection = job.Selection

    if selection.IsEmpty then
        DisplayMessageBox("Please select the objects you want to rotate.")
        return false
    end

    ----------------------------------------------------------------
    -- Step 1: Ask the user for the rotation angle.
    ----------------------------------------------------------------

    if not GetUserAngle(script_path) then
        return false -- user cancelled dialog
    end

    ----------------------------------------------------------------
    -- Step 2: Copy the selected objects into a Lua table.
    -- IMPORTANT: GetNext() returns BOTH the object and the new
    -- iterator position.
    ----------------------------------------------------------------

    local objects_to_rotate = {}

    local pos = selection:GetHeadPosition()

    while pos ~= nil do

        local object
        object, pos = selection:GetNext(pos)

        if object ~= nil then
            table.insert(objects_to_rotate, object)
        end

    end

    ----------------------------------------------------------------
    -- Step 3: Rotate each object around its own bounding-box center.
    ----------------------------------------------------------------

    local undo_ops = {}

    for _, object in ipairs(objects_to_rotate) do

        -- Get the object's bounding box
        local bbox = object:GetBoundingBox()

        -- Center of that individual object
        local center = bbox.Center

        -- Create a rotation matrix around that center using the
        -- user-specified angle
        local rot_matrix = RotationMatrix2D(center, g_rotate_angle)

        -- Apply transformation
        object:Transform(rot_matrix)

        -- Record how to undo this rotation (same center, opposite
        -- angle - rotating about its own center doesn't move the
        -- center, so it's still valid after the transform).
        --
        -- We identify the object by its center point rather than
        -- its internal ID - Vectric's RawId/RawLayerId values
        -- can't be converted with tostring() in this Lua build.
        --
        -- Wrapped in pcall so that if the undo bookkeeping ever
        -- hits something unexpected, it just skips logging that
        -- object instead of aborting the rest of the rotation.
        pcall(
            function()
                table.insert(
                    undo_ops,
                    string.format(
                        "op=rotate cx=%.8f cy=%.8f angle=%.8f",
                        center.X,
                        center.Y,
                        g_rotate_angle
                    )
                )
            end
        )

    end

    pcall(PGC_AppendUndoEntry, script_path, "PGC_Rotate", undo_ops)

    ----------------------------------------------------------------
    -- Step 4: Refresh the 2D view
    ----------------------------------------------------------------

    job:Refresh2DView()

    DisplayMessageBox(
        "Finished.\n\nRotated " .. tostring(#objects_to_rotate) ..
        " object(s) by " .. tostring(g_rotate_angle) .. " degrees."
    )

    return true
end
