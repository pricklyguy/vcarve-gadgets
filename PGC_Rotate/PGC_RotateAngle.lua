-- VECTRIC LUA SCRIPT
-- Name = Rotate Each Object By Angle
-- Version = 1.0
-- Help = Rotates every selected object by a user-specified angle around its own center.

require("strict")

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

    end

    ----------------------------------------------------------------
    -- Step 4: Refresh the 2D view
    ----------------------------------------------------------------

    job:Refresh2DView()

    return true
end
