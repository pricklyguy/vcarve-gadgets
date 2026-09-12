-- VECTRIC LUA SCRIPT
-- Name = Replace Circles With Group
-- Version = 1.2
-- Help = Replaces selected circles with copies of the last-selected
--        grouped object, centered on the original circles. Run "Undo
--        Last PGC Change" (PGC_Undo_Last) to reverse this if VCarve's
--        own Ctrl+Z doesn't offer the option.

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

-- true  = leave the original master/template in place
-- false = remove the original master/template after replacement
--
-- This is now set from the options dialog (see GetUserChoices)
-- and remembered in the registry between runs.
g_keep_template = true

-- true  = before removing a replaced circle (or the template, if
--         g_keep_template is false), leave a copy of it on a
--         "PGC Undo Backup" layer instead of destroying it for
--         good. "Undo Last PGC Change" only needs to delete the
--         new replacement copies to undo a run - it never has to
--         touch these backups - so they're just there as a manual
--         safety net. Clear out that layer yourself once you're
--         happy with the result.
g_backup_replaced = true


----------------------------------------------------------------
-- Ask the user for the options for this run.
----------------------------------------------------------------

function GetUserChoices(script_path)

    local registry = Registry("PGC_ReplaceCircles")
    g_keep_template = registry:GetBool("KeepTemplate", g_keep_template)
    g_backup_replaced = registry:GetBool("BackupReplaced", g_backup_replaced)

    local html_path = "file:" .. script_path .. "\\PGC_Replace_Circles.htm"
    local dialog = HTML_Dialog(false, html_path, 420, 280, "Replace Circles With Group")

    dialog:AddCheckBox("KeepTemplate", g_keep_template)
    dialog:AddCheckBox("BackupReplaced", g_backup_replaced)

    if not dialog:ShowDialog() then
        return false
    end

    g_keep_template = dialog:GetCheckBox("KeepTemplate")
    g_backup_replaced = dialog:GetCheckBox("BackupReplaced")

    registry:SetBool("KeepTemplate", g_keep_template)
    registry:SetBool("BackupReplaced", g_backup_replaced)

    return true
end


----------------------------------------------------------------
-- Get (creating if needed) the layer that backup copies of
-- replaced circles/templates are parked on.
----------------------------------------------------------------

function GetBackupLayer(job)
    return job.LayerManager:GetLayerWithName("PGC Undo Backup")
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
-- Find the center of the actual circle inside the template group.
--
-- We deliberately DO NOT use the group's bounding-box center.
-- The notch can make that center different from the circle center.
--
-- We look for the largest closed contour in the group, which
-- should be the main circle in the circle + notch template.
----------------------------------------------------------------

function FindTemplateCircleCenter(template)

    if template.ClassName ~= "vcCadObjectGroup" then
        return nil
    end

    local group = CastCadObjectToCadObjectGroup(template)

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

    -- Use the bounding box of the actual circle/closed contour.
    local bbox = best_contour.BoundingBox2D

    return bbox.Center
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
            "Select the circles first, then Shift-select the " ..
            "grouped circle + notch last."
        )
        return false
    end


    ----------------------------------------------------------------
    -- Get all selected objects BEFORE changing anything.
    ----------------------------------------------------------------

    local selected_objects = GetSelectedObjects(selection)

    if #selected_objects < 2 then
        DisplayMessageBox(
            "You need at least one circle and a template group."
        )
        return false
    end


    ----------------------------------------------------------------
    -- The last selected object is the template.
    ----------------------------------------------------------------

    local template = GetLastSelectedObject(selection)

    if template == nil then
        DisplayMessageBox("Could not determine the template object.")
        return false
    end


    ----------------------------------------------------------------
    -- Verify the template is actually a group.
    ----------------------------------------------------------------

    if template.ClassName ~= "vcCadObjectGroup" then
        DisplayMessageBox(
            "The last selected object must be the grouped " ..
            "circle + notch."
        )
        return false
    end


    ----------------------------------------------------------------
    -- Find the center of the actual circle INSIDE the group.
    ----------------------------------------------------------------

    local template_circle_center = FindTemplateCircleCenter(template)

    if template_circle_center == nil then
        DisplayMessageBox(
            "Could not find a closed circle inside the template group."
        )
        return false
    end


    ----------------------------------------------------------------
    -- Ask the user whether to keep the original template.
    ----------------------------------------------------------------

    if not GetUserChoices(script_path) then
        return false -- user cancelled dialog
    end


    ----------------------------------------------------------------
    -- Create a list of the objects we are replacing.
    --
    -- Everything except the last-selected template is treated
    -- as a target.
    ----------------------------------------------------------------

    local targets = {}

    for i = 1, #selected_objects - 1 do

        local object = selected_objects[i]

        if object ~= nil then
            table.insert(targets, object)
        end

    end


    ----------------------------------------------------------------
    -- Clear the current selection before we start modifying
    -- the job.
    ----------------------------------------------------------------

    selection:Clear()


    ----------------------------------------------------------------
    -- Replace each target.
    ----------------------------------------------------------------

    local replacement_count = 0
    local undo_ops = {}

    for _, target in ipairs(targets) do

        if target ~= nil then

            --------------------------------------------------------
            -- Get the center of the original circle.
            --------------------------------------------------------

            local target_bbox = target:GetBoundingBox()
            local target_center = target_bbox.Center


            --------------------------------------------------------
            -- Clone the master group.
            --
            -- Clone creates a completely independent copy with
            -- new object IDs.
            --------------------------------------------------------

            local replacement = template:Clone()

            if replacement ~= nil then

                ----------------------------------------------------
                -- Calculate the movement needed to place the
                -- template's circle center on the target center.
                ----------------------------------------------------

                local move_vector =
                    target_center - template_circle_center

                local move_matrix =
                    TranslationMatrix2D(move_vector)


                ----------------------------------------------------
                -- Move the entire group.
                ----------------------------------------------------

                replacement:Transform(move_matrix)


                ----------------------------------------------------
                -- Put the replacement on the SAME layer as the
                -- original target.
                ----------------------------------------------------

                local layer =
                    job.LayerManager:GetLayerWithId(target.RawLayerId)

                if layer ~= nil then
                    layer:AddObject(replacement, true)
                end


                ----------------------------------------------------
                -- Leave a backup copy of the original circle
                -- before removing it, unless the user turned that
                -- off.
                ----------------------------------------------------

                if g_backup_replaced then

                    local backup = target:Clone()

                    if backup ~= nil then
                        GetBackupLayer(job):AddObject(backup, true)
                    end

                end


                ----------------------------------------------------
                -- Remove the original circle from the layer.
                ----------------------------------------------------

                if layer ~= nil then
                    layer:RemoveObject(target)
                end


                ----------------------------------------------------
                -- Record how to undo this replacement: "Undo Last
                -- PGC Change" just needs to delete the new
                -- replacement copy. (The original is either still
                -- there as a backup, or was permanently removed by
                -- choice - either way there's nothing else to
                -- reverse.)
                --
                -- We identify the replacement by its circle center
                -- rather than its internal ID - Vectric's
                -- RawId/RawLayerId values can't be converted with
                -- tostring() in this Lua build.
                ----------------------------------------------------

                if layer ~= nil then

                    -- Wrapped in pcall so any surprise in the undo
                    -- bookkeeping can't stop the rest of the
                    -- replacements from being processed.
                    pcall(
                        function()

                            local replacement_center = FindTemplateCircleCenter(replacement)

                            if replacement_center ~= nil then

                                table.insert(
                                    undo_ops,
                                    string.format(
                                        "op=delete_new cx=%.8f cy=%.8f",
                                        replacement_center.X,
                                        replacement_center.Y
                                    )
                                )

                            end

                        end
                    )

                end


                replacement_count = replacement_count + 1

            end
        end
    end


    ----------------------------------------------------------------
    -- Optionally remove the original template.
    ----------------------------------------------------------------

    if not g_keep_template then

        if g_backup_replaced then

            local template_backup = template:Clone()

            if template_backup ~= nil then
                GetBackupLayer(job):AddObject(template_backup, true)
            end

        end

        local template_layer =
            job.LayerManager:GetLayerWithId(template.RawLayerId)

        if template_layer ~= nil then
            template_layer:RemoveObject(template)
        end

    else

        -- Put the original template back into the selection.
        selection:Add(template, true, false)

    end

    pcall(PGC_AppendUndoEntry, script_path, "PGC_Replace_Circles", undo_ops)


    ----------------------------------------------------------------
    -- Refresh the 2D view.
    ----------------------------------------------------------------

    job:Refresh2DView()


    ----------------------------------------------------------------
    -- Report result.
    ----------------------------------------------------------------

    if replacement_count == 0 then

        DisplayMessageBox(
            "No replacements were created."
        )

        return false
    end


    return true

end
