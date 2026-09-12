-- VECTRIC LUA SCRIPT
-- Name = Undo Last PGC Change
-- Version = 1.0
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
-- Works for any of our op lines since every field is a single
-- whitespace-free token.
----------------------------------------------------------------

function PGC_ParseFields(line)

    local fields = {}

    for key, value in line:gmatch("([%a_]+)=(%S+)") do
        fields[key] = value
    end

    return fields

end


----------------------------------------------------------------
-- Find an object by its RawId, starting with the layer we
-- recorded (fast path), falling back to a scan of every layer in
-- the job in case the layer was since renamed/recreated.
----------------------------------------------------------------

function PGC_FindObjectInLayer(job, raw_layer_id_str, raw_id_str)

    local raw_layer_id = tonumber(raw_layer_id_str)

    if raw_layer_id == nil then
        return nil
    end

    local layer = job.LayerManager:GetLayerWithId(raw_layer_id)

    if layer == nil then
        return nil
    end

    local pos = layer:GetHeadPosition()

    while pos ~= nil do

        local object
        object, pos = layer:GetNext(pos)

        if object ~= nil and tostring(object.RawId) == raw_id_str then
            return object, layer
        end

    end

    return nil

end

function PGC_FindObjectAnywhere(job, raw_id_str)

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

                if object ~= nil and tostring(object.RawId) == raw_id_str then
                    return object, layer
                end

            end

        end

    end

    return nil

end

function PGC_FindObject(job, raw_layer_id_str, raw_id_str)

    local object, layer = PGC_FindObjectInLayer(job, raw_layer_id_str, raw_id_str)

    if object ~= nil then
        return object, layer
    end

    return PGC_FindObjectAnywhere(job, raw_id_str)

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

    local gadget_name = "a PGC gadget"
    local rotated_count = 0
    local translated_count = 0
    local removed_count = 0
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

                local object = PGC_FindObject(job, op.raw_layer_id, op.raw_id)

                if object == nil then
                    missing_count = missing_count + 1
                else
                    local center = Point2D(tonumber(op.cx), tonumber(op.cy))
                    local undo_matrix = RotationMatrix2D(center, -tonumber(op.angle))
                    object:Transform(undo_matrix)
                    rotated_count = rotated_count + 1
                end

            elseif op.op == "translate" then

                local object = PGC_FindObject(job, op.raw_layer_id, op.raw_id)

                if object == nil then
                    missing_count = missing_count + 1
                else
                    local reverse_vector = Point2D(-tonumber(op.dx), -tonumber(op.dy))
                    local undo_matrix = TranslationMatrix2D(reverse_vector)
                    object:Transform(undo_matrix)
                    translated_count = translated_count + 1
                end

            elseif op.op == "delete_new" then

                local object, layer = PGC_FindObject(job, op.raw_layer_id, op.raw_id)

                if object == nil or layer == nil then
                    missing_count = missing_count + 1
                else
                    layer:RemoveObject(object)
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

    if missing_count > 0 then
        message = message .. "\n\n" .. tostring(missing_count) ..
            " object(s) from that change could not be found " ..
            "(edited or deleted since) and were skipped."
    end

    if #entries > 0 then
        message = message .. "\n\nRun this again to undo the change before that."
    end

    DisplayMessageBox(message)

    return true

end
