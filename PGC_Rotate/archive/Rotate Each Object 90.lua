-- VECTRIC LUA SCRIPT
-- Name = Rotate Each Object 90
-- Version = 1.4
-- Help = Rotates every selected object 90 degrees around its own center.

require("strict")

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
    -- Step 1: Copy the selected objects into a Lua table.
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
    -- Step 2: Rotate each object around its own bounding-box center.
    ----------------------------------------------------------------

    for _, object in ipairs(objects_to_rotate) do

        -- Get the object's bounding box
        local bbox = object:GetBoundingBox()

        -- Center of that individual object
        local center = bbox.Center

        -- Create a 90-degree rotation matrix around that center
        local rot_matrix = RotationMatrix2D(center, 90.0)

        -- Apply transformation
        object:Transform(rot_matrix)

    end

    ----------------------------------------------------------------
    -- Step 3: Refresh the 2D view
    ----------------------------------------------------------------

    job:Refresh2DView()

    return true
end
