-- VECTRIC LUA SCRIPT
-- Name = Count Selected Object
-- Version = 2.0
--
-- Description:
-- Counts selected vectors matching the LAST-SELECTED object.
--
-- V2 additions:
--   * Detects duplicate matching objects at the same location.
--   * Reports unique count.
--   * Reports duplicate object count.
--   * Reports duplicate locations.
--   * Selects/highlights the duplicate objects when finished.
--
-- HOW TO USE:
--   1. Select all objects you want to search.
--   2. Select the object you want to COUNT LAST.
--   3. Run the gadget.
--
-- IMPORTANT:
--   The geometry is never moved, deleted, or modified.
--   V2 changes the final selection to the duplicate objects
--   so they can be visually identified.

require("strict")


-- ============================================================
-- SETTINGS
-- ============================================================

-- Position tolerance used when deciding whether two matching
-- objects occupy the same location.
--
-- VCarve's default contour tolerance is used so this works
-- appropriately in either inch or metric jobs.
--
local POSITION_TOLERANCE = GetDefaultContourTolerance()


-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================


-- ------------------------------------------------------------
-- Compare two numbers using an absolute tolerance.
-- ------------------------------------------------------------

local function NearlyEqual(a, b, tolerance)

    return math.abs(a - b) <= tolerance

end


-- ------------------------------------------------------------
-- Compare geometry values such as length and area.
--
-- A relative comparison prevents problems when working with
-- objects that are very large or very small.
-- ------------------------------------------------------------

local function GeometryValueEqual(a, b, tolerance)

    local scale =
        math.max(
            1.0,
            math.abs(a),
            math.abs(b)
        )

    return math.abs(a - b) <=
        (tolerance * scale)

end


-- ------------------------------------------------------------
-- Extract useful geometry information from a CadObject.
--
-- Groups, bitmaps, etc. do not provide a usable contour and
-- therefore return nil here.
-- ------------------------------------------------------------

local function GetGeometryInfo(object)

    if object == nil then
        return nil
    end


    local contour =
        object:GetContour()


    if contour == nil then
        return nil
    end


    local bbox =
        object:GetBoundingBox()


    local info = {}


    info.contour =
        contour

    info.center =
        bbox.Center

    info.width =
        bbox.XLength

    info.height =
        bbox.YLength

    info.area =
        contour.Area

    info.length =
        contour.Length

    info.span_count =
        contour.Count

    info.is_closed =
        contour.IsClosed

    info.has_arcs =
        contour.ContainsArcs

    info.has_beziers =
        contour.ContainsBeziers


    return info

end


-- ------------------------------------------------------------
-- Determine whether two vectors have the same geometry.
--
-- We intentionally use several characteristics instead of
-- simply comparing width and height.
-- ------------------------------------------------------------

local function GeometryMatches(
    reference,
    candidate,
    tolerance
)

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


    -- Arc characteristics must match.
    if reference.has_arcs ~= candidate.has_arcs then
        return false
    end


    -- Bezier characteristics must match.
    if reference.has_beziers ~= candidate.has_beziers then
        return false
    end


    -- Bounding-box width.
    if not NearlyEqual(
        reference.width,
        candidate.width,
        tolerance
    ) then
        return false
    end


    -- Bounding-box height.
    if not NearlyEqual(
        reference.height,
        candidate.height,
        tolerance
    ) then
        return false
    end


    -- Total contour length.
    if not GeometryValueEqual(
        reference.length,
        candidate.length,
        tolerance
    ) then
        return false
    end


    -- Contour area.
    if not GeometryValueEqual(
        reference.area,
        candidate.area,
        tolerance
    ) then
        return false
    end


    return true

end


-- ------------------------------------------------------------
-- Determine whether two matching objects occupy the same
-- physical location.
--
-- Because geometry has already been matched, comparing the
-- bounding-box centers is sufficient for our purposes.
-- ------------------------------------------------------------

local function SameLocation(
    center_a,
    center_b,
    tolerance
)

    if center_a == nil or center_b == nil then
        return false
    end


    return
        NearlyEqual(
            center_a.X,
            center_b.X,
            tolerance
        )
        and
        NearlyEqual(
            center_a.Y,
            center_b.Y,
            tolerance
        )

end


-- ============================================================
-- MAIN
-- ============================================================

function main(script_path)

    local job =
        VectricJob()


    -- --------------------------------------------------------
    -- Make sure a job exists.
    -- --------------------------------------------------------

    if not job.Exists then

        DisplayMessageBox(
            "No VCarve job is currently loaded."
        )

        return false

    end


    -- --------------------------------------------------------
    -- Get current selection.
    -- --------------------------------------------------------

    local selection =
        job.Selection


    if selection.IsEmpty then

        DisplayMessageBox(
            "Please select the objects you want to count.\n\n" ..
            "The object you want counted must be selected LAST."
        )

        return false

    end


    -- --------------------------------------------------------
    -- Copy the selection into a Lua table.
    --
    -- This allows us to analyze everything without modifying
    -- the actual VCarve selection until we're finished.
    -- --------------------------------------------------------

    local selected_objects = {}


    local pos =
        selection:GetHeadPosition()


    while pos ~= nil do

        local object

        object, pos =
            selection:GetNext(pos)


        if object ~= nil then

            table.insert(
                selected_objects,
                object
            )

        end

    end


    -- --------------------------------------------------------
    -- Find the LAST selected object.
    --
    -- This becomes our geometry reference.
    -- --------------------------------------------------------

    local tail_pos =
        selection:GetTailPosition()


    local reference_object =
        nil


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
    -- Get reference geometry.
    -- --------------------------------------------------------

    local reference_geometry =
        GetGeometryInfo(
            reference_object
        )


    if reference_geometry == nil then

        DisplayMessageBox(
            "The last-selected object does not contain " ..
            "a usable vector contour.\n\n" ..
            "Please select a single vector as the LAST " ..
            "selected object."
        )

        return false

    end


    -- ========================================================
    -- SEARCH FOR MATCHES
    -- ========================================================

    local matching_count =
        0


    local duplicate_count =
        0


    local duplicate_location_count =
        0


    -- --------------------------------------------------------
    -- Each entry represents one unique physical location.
    --
    -- Example:
    --
    --   Location #1
    --       object A
    --
    --   Location #2
    --       object B
    --       object C   <-- duplicate
    --
    --   Location #3
    --       object D
    --
    -- Unique count = 3
    -- Matching count = 4
    -- Duplicate count = 1
    -- Duplicate locations = 1
    -- --------------------------------------------------------

    local unique_locations = {}


    -- --------------------------------------------------------
    -- Objects that should ultimately be highlighted.
    --
    -- We only add the EXTRA copies here.
    -- The first object at a location is considered the valid
    -- copy and is not highlighted.
    -- --------------------------------------------------------

    local duplicate_objects = {}


    -- --------------------------------------------------------
    -- Search every selected object.
    -- --------------------------------------------------------

    for _, object in ipairs(selected_objects) do

        local geometry =
            GetGeometryInfo(object)


        -- Ignore anything that isn't a vector contour.
        if geometry ~= nil then


            -- ------------------------------------------------
            -- Does it match the last-selected object?
            -- ------------------------------------------------

            if GeometryMatches(
                reference_geometry,
                geometry,
                POSITION_TOLERANCE
            ) then


                matching_count =
                    matching_count + 1


                -- --------------------------------------------
                -- Look for an existing matching object at the
                -- same physical location.
                -- --------------------------------------------

                local existing_location =
                    nil


                for _, location_data
                    in ipairs(unique_locations) do


                    if SameLocation(
                        geometry.center,
                        location_data.center,
                        POSITION_TOLERANCE
                    ) then

                        existing_location =
                            location_data

                        break

                    end

                end


                -- --------------------------------------------
                -- This is a NEW unique location.
                -- --------------------------------------------

                if existing_location == nil then

                    table.insert(
                        unique_locations,
                        {
                            center = geometry.center,
                            object = object,
                            duplicate_count = 0
                        }
                    )


                -- --------------------------------------------
                -- This is another copy at an existing
                -- location.
                -- --------------------------------------------

                else

                    duplicate_count =
                        duplicate_count + 1


                    existing_location.duplicate_count =
                        existing_location.duplicate_count + 1


                    -- The extra copy is the object we want
                    -- highlighted.
                    table.insert(
                        duplicate_objects,
                        object
                    )

                end

            end

        end

    end


    -- ========================================================
    -- COUNT DUPLICATE LOCATIONS
    -- ========================================================

    for _, location_data
        in ipairs(unique_locations) do

        if location_data.duplicate_count > 0 then

            duplicate_location_count =
                duplicate_location_count + 1

        end

    end


    -- ========================================================
    -- FINAL UNIQUE COUNT
    -- ========================================================

    local unique_count =
        #unique_locations


    -- ========================================================
    -- HIGHLIGHT DUPLICATES
    -- ========================================================
    --
    -- VCarve has one active selection, so we replace the
    -- original selection with the duplicate objects.
    --
    -- Nothing about the actual geometry is changed.
    -- ========================================================

    selection:Clear()


    for _, duplicate_object
        in ipairs(duplicate_objects) do

        selection:Add(
            duplicate_object,
            true,
            true
        )

    end


    -- Tell VCarve the grouped selection operation is complete.
    selection:GroupSelectionFinished()


    job:Refresh2DView()


    -- ========================================================
    -- BUILD RESULT MESSAGE
    -- ========================================================

    local message =

        "----------------------------------------\n" ..
        "       COUNT SELECTED OBJECT V2\n" ..
        "----------------------------------------\n\n" ..

        "Objects originally selected: " ..
        tostring(#selected_objects) .. "\n\n" ..

        "Matching objects found:      " ..
        tostring(matching_count) .. "\n\n" ..

        "Unique matching objects:     " ..
        tostring(unique_count) .. "\n\n" ..

        "Duplicate locations:         " ..
        tostring(duplicate_location_count) .. "\n" ..

        "Duplicate objects excluded:  " ..
        tostring(duplicate_count) .. "\n\n" ..

        "----------------------------------------\n" ..

        "UNIQUE COUNT:                 " ..
        tostring(unique_count) .. "\n" ..

        "----------------------------------------\n\n"


    if duplicate_count > 0 then

        message = message ..

            "The duplicate objects are now selected\n" ..
            "for visual inspection."

    else

        message = message ..

            "No duplicate objects were found."

    end


    DisplayMessageBox(message)


    return true

end
