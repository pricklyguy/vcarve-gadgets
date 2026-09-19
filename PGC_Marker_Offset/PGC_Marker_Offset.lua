-- VECTRIC LUA SCRIPT
-- Name = Marker Offset Copy
-- Version = 1.0
-- Help = Copies the selected vectors onto a "PGC Marker Path" layer, shifted so a
--        marker/pen mounted beside the spindle draws them in the right place.
--        Enter where the marker sits relative to the spindle; the copy is shifted
--        the opposite way. Run "Undo Last PGC Change" (PGC_Undo_Last) to remove the copy.

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

-- Where the marker sits relative to the spindle, in millimeters
-- (work coordinates): marker position = spindle position + this.
-- Default matches the user's Sharpie adapter: same X, 58mm toward
-- -Y (spindle at 0,0 -> marker at 0,-58). Remembered in the
-- registry between runs. Always stored in mm; converted to the
-- job's own units for the dialog and for the shift.
g_marker_x_mm = 0.0
g_marker_y_mm = -58.0

g_marker_layer_name = "PGC Marker Path"


----------------------------------------------------------------
-- Ask the user where the marker sits relative to the spindle.
----------------------------------------------------------------

function GetUserChoices(script_path, job)

    local registry = Registry("PGC_MarkerOffset")
    g_marker_x_mm = registry:GetDouble("MarkerXmm", g_marker_x_mm)
    g_marker_y_mm = registry:GetDouble("MarkerYmm", g_marker_y_mm)

    -- mm -> job units (the dialog and the shift both work in job units)
    local units_per_mm = 1.0
    local units_text = "mm"

    if not job.InMM then
        units_per_mm = 1.0 / 25.4
        units_text = "inches"
    end

    local html_path = "file:" .. script_path .. "\\PGC_Marker_Offset.htm"
    local dialog = HTML_Dialog(false, html_path, 480, 460, "Marker Offset Copy")

    dialog:AddLabelField("Units1", units_text)
    dialog:AddLabelField("Units2", units_text)
    dialog:AddDoubleField("MarkerX", g_marker_x_mm * units_per_mm)
    dialog:AddDoubleField("MarkerY", g_marker_y_mm * units_per_mm)

    if not dialog:ShowDialog() then
        return false
    end

    g_marker_x_mm = dialog:GetDoubleField("MarkerX") / units_per_mm
    g_marker_y_mm = dialog:GetDoubleField("MarkerY") / units_per_mm

    registry:SetDouble("MarkerXmm", g_marker_x_mm)
    registry:SetDouble("MarkerYmm", g_marker_y_mm)

    return true, units_per_mm
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
-- Main
----------------------------------------------------------------

function main(script_path)

    local job = VectricJob()

    if not job.Exists then
        DisplayMessageBox("No job loaded.")
        return false
    end

    local selection = job.Selection

    if selection.IsEmpty then
        DisplayMessageBox(
            "Select the vectors you want the marker to draw " ..
            "(e.g. the wiring path layers), then run this gadget."
        )
        return false
    end

    local selected_objects = GetSelectedObjects(selection)

    local ok, units_per_mm = GetUserChoices(script_path, job)

    if not ok then
        return false -- user cancelled dialog
    end

    if g_marker_x_mm == 0.0 and g_marker_y_mm == 0.0 then
        DisplayMessageBox(
            "The marker offset is 0, 0 - there's nothing to shift. " ..
            "Enter where the marker sits relative to the spindle."
        )
        return false
    end

    ----------------------------------------------------------------
    -- The marker sits at (spindle + offset), so to put the marker on
    -- a point P the spindle has to be at (P - offset): shift the
    -- copy by the NEGATIVE of the marker offset.
    ----------------------------------------------------------------

    local shift_x = -g_marker_x_mm * units_per_mm
    local shift_y = -g_marker_y_mm * units_per_mm

    local move_matrix = TranslationMatrix2D(Vector2D(shift_x, shift_y))

    local layer = job.LayerManager:GetLayerWithName(g_marker_layer_name)

    local copies = {}
    local undo_ops = {}

    for _, object in ipairs(selected_objects) do

        local copy = object:Clone()

        if copy ~= nil then

            copy:Transform(move_matrix)
            layer:AddObject(copy, true)
            table.insert(copies, copy)

            -- Record where the copy sits now, so "Undo Last PGC Change"
            -- can find it again on the marker layer by position.
            pcall(
                function()
                    local center = copy:GetBoundingBox().Center
                    table.insert(
                        undo_ops,
                        string.format(
                            "op=delete_copy cx=%.8f cy=%.8f",
                            center.X,
                            center.Y
                        )
                    )
                end
            )

        end

    end

    pcall(PGC_AppendUndoEntry, script_path, "PGC_Marker_Offset", undo_ops)

    -- Leave the new copies selected so a toolpath can be made from
    -- them straight away.
    selection:Clear()

    for _, copy in ipairs(copies) do
        selection:Add(copy, true, true)
    end

    selection:GroupSelectionFinished()

    job:Refresh2DView()

    if #copies == 0 then
        DisplayMessageBox("Nothing could be copied from the selection.")
        return false
    end

    local units_text = "mm"

    if not job.InMM then
        units_text = "inches"
    end

    DisplayMessageBox(
        "Finished.\n\n" ..
        "Copied " .. tostring(#copies) .. " object(s) to the \"" ..
        g_marker_layer_name .. "\" layer, shifted " ..
        string.format("%.3f", shift_x) .. ", " ..
        string.format("%.3f", shift_y) .. " " .. units_text ..
        ".\n\nThe copies are selected - make the marker toolpath from " ..
        "them using the same work zero as your cutting job."
    )

    return true

end
