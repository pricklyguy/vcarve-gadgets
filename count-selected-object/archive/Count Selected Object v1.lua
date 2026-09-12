-- VECTRIC LUA SCRIPT
-- Name = Count Selected Object
-- Version = 1.0
-- Description = Counts selected vectors matching the last-selected object.
--              Exact-position duplicates are counted only once.
--
-- HOW TO USE:
--   1. Select all objects you want to search.
--   2. Select the object you want to COUNT LAST.
--   3. Run this gadget.
--
-- IMPORTANT:
--   This version does NOT modify the drawing or selection.

require("strict")


-- ============================================================
-- SETTINGS
-- ============================================================

-- Position tolerance used when deciding whether two matching
-- objects are in the same location.
--
-- This is intentionally very small.
-- VCarve's default contour tolerance is used so the value
-- behaves sensibly in either inch or metric jobs.
--
local POSITION_TOLERANCE = GetDefaultContourTolerance()


-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

-- Return true if two numbers are close enough.
local function NearlyEqual(a, b, tolerance)

    return math.abs(a - b) <= tolerance

end


-- Compare two scalar geometry values using a relative tolerance.
--
-- This is useful for things such as contour length and area,
-- where using one fixed absolute tolerance isn't ideal.
local function GeometryValueEqual(a, b, tolerance)

    local scale = math.max(1.0, math.abs(a), math.abs(b))

    return math.abs(a - b) <= (tolerance * scale)

end


-- Get useful geometry information from a CadObject.
--
-- Objects such as groups and bitmaps don't have a contour,
-- so GetContour() will return nil for those.
local function GetGeometryInfo(object)

    if object == nil then
        return nil
    end

    local contour = object:GetContour()

    if contour == nil then
        return nil
    end

    local bbox = object:GetBoundingBox()

    local info = {}

    info.contour      = contour
    info.center       = bbox.Center

    info.width        = bbox.XLength
    info.height       = bbox.YLength

    info.area         = contour.Area
    info.length       = contour.Length

    info.span_count   = contour.Count

    info.is_closed    = contour.IsClosed
    info.has_arcs     = contour.ContainsArcs
    info.has_beziers  = contour.ContainsBeziers

    return info

end


-- Determine whether two objects have the same basic geometry.
--
-- We intentionally compare several characteristics instead of
-- simply comparing width and height. That prevents something
-- like a circle and a notch with the same bounding dimensions
-- from being treated as the same object.
local function GeometryMatches(reference, candidate, tolerance)

    if reference == nil or candidate == nil then
        return false
    end


    -- Closed/open state must match.
    if reference.is_closed ~= candidate.is_closed then
        return false
    end


    -- Number of spans must match.
    if reference.span_count ~= candidate.span_count then
        return false
    end


    -- Arc/Bezier characteristics must match.
    if reference.has_arcs ~= candidate.has_arcs then
        return false
    end

    if reference.has_beziers ~= candidate.has_beziers then
        return false
    end


    -- Bounding dimensions must match.
    if not NearlyEqual(
        reference.width,
        candidate.width,
        tolerance
    ) then
        return false
    end

    if not NearlyEqual(
        reference.height,
        candidate.height,
        tolerance
    ) then
        return false
    end


    -- Compare total contour length.
    if not GeometryValueEqual(
        reference.length,
        candidate.length,
        tolerance
    ) then
        return false
    end


    -- Compare area.
    if not GeometryValueEqual(
        reference.area,
        candidate.area,
        tolerance
    ) then
        return false
    end


    return true

end


-- Determine whether two matching objects occupy the same location.
--
-- We compare their bounding-box centers. Since the geometry has
-- already been determined to match, identical centers means they
-- are effectively the same placed object.
local function SameLocation(center_a, center_b, tolerance)

    if center_a == nil or center_b == nil then
        return false
    end

    return
        NearlyEqual(center_a.X, center_b.X, tolerance) and
        NearlyEqual(center_a.Y, center_b.Y, tolerance)

end


-- ============================================================
-- MAIN
-- ============================================================

function main(script_path)

    local job = VectricJob()


    -- --------------------------------------------------------
    -- Make sure a job exists
    -- --------------------------------------------------------

    if not job.Exists then

        DisplayMessageBox(
            "No VCarve job is currently loaded."
        )

        return false

    end


    -- --------------------------------------------------------
    -- Get the current selection
    -- --------------------------------------------------------

    local selection = job.Selection


    if selection.IsEmpty then

        DisplayMessageBox(
            "Please select the objects you want to count.\n\n" ..
            "The object you want counted must be selected LAST."
        )

        return false

    end


    -- --------------------------------------------------------
    -- Copy the selection into a normal Lua table.
    --
    -- We do this before doing any processing so the selection
    -- itself remains completely untouched.
    -- --------------------------------------------------------

    local selected_objects = {}

    local pos = selection:GetHeadPosition()

    while pos ~= nil do

        local object

        object, pos = selection:GetNext(pos)

        if object ~= nil then

            table.insert(
                selected_objects,
                object
            )

        end

    end


    -- --------------------------------------------------------
    -- The LAST selected object is our reference/template.
    --
    -- SelectionList supports GetTailPosition() and GetPrev(),
    -- which lets us retrieve the tail of the selection.
    -- --------------------------------------------------------

    local tail_pos = selection:GetTailPosition()

    local reference_object = nil

    if tail_pos ~= nil then

        reference_object, tail_pos =
            selection:GetPrev(tail_pos)

    end


    if reference_object == nil then

        DisplayMessageBox(
            "Unable to determine the last-selected object."
        )

        return false

    end


    -- --------------------------------------------------------
    -- Get the reference object's geometry.
    -- --------------------------------------------------------

    local reference_geometry =
        GetGeometryInfo(reference_object)


    if reference_geometry == nil then

        DisplayMessageBox(
            "The last-selected object does not contain " ..
            "a usable vector contour.\n\n" ..
            "Please select a single vector as the LAST " ..
            "selected object."
        )

        return false

    end


    -- --------------------------------------------------------
    -- Search all selected objects.
    -- --------------------------------------------------------

    local matching_count = 0
    local duplicate_count = 0

    -- Stores the center of each unique matching object.
    local unique_locations = {}


    for _, object in ipairs(selected_objects) do

        local geometry =
            GetGeometryInfo(object)


        -- Ignore things that aren't actual vectors.
        if geometry ~= nil then


            -- ------------------------------------------------
            -- Does this object have the same geometry as the
            -- last-selected reference object?
            -- ------------------------------------------------

            if GeometryMatches(
                reference_geometry,
                geometry,
                POSITION_TOLERANCE
            ) then


                matching_count = matching_count + 1


                -- --------------------------------------------
                -- Check whether this matching object is already
                -- represented at the same location.
                -- --------------------------------------------

                local already_counted = false


                for _, existing_center
                    in ipairs(unique_locations) do

                    if SameLocation(
                        geometry.center,
                        existing_center,
                        POSITION_TOLERANCE
                    ) then

                        already_counted = true

                        break

                    end

                end


                if already_counted then

                    duplicate_count =
                        duplicate_count + 1

                else

                    table.insert(
                        unique_locations,
                        geometry.center
                    )

                end

            end

        end

    end


    -- --------------------------------------------------------
    -- Final unique count
    -- --------------------------------------------------------

    local unique_count =
        #unique_locations


    -- --------------------------------------------------------
    -- Display results
    -- --------------------------------------------------------

    local message =

        "----------------------------------------\n" ..
        "       COUNT SELECTED OBJECT V1\n" ..
        "----------------------------------------\n\n" ..

        "Selected objects searched:  " ..
        tostring(#selected_objects) .. "\n\n" ..

        "Matching objects found:     " ..
        tostring(matching_count) .. "\n" ..

        "Duplicate objects excluded: " ..
        tostring(duplicate_count) .. "\n\n" ..

        "UNIQUE COUNT:                " ..
        tostring(unique_count) .. "\n\n" ..

        "The last-selected object was included.\n\n" ..

        "----------------------------------------"


    DisplayMessageBox(message)

    return true

end
