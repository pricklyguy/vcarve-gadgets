-- VECTRIC LUA SCRIPT
-- Name = Count Selected Object
-- Version = 3.0
--
-- Description:
-- Counts selected vectors matching the LAST-SELECTED object.
--
-- V3:
--   * Rotation-independent geometry matching
--   * Translation-independent geometry matching
--   * Closed vectors can have different starting spans
--   * Detects duplicate objects at the same physical location
--   * Highlights duplicate objects
--
-- HOW TO USE:
--
--   1. Select all objects you want to search.
--   2. Select the object you want to COUNT LAST.
--   3. Run the gadget.
--
-- The geometry is never moved, deleted, rotated, or modified.
--
-- The final selection is changed to the duplicate objects
-- so they can be visually inspected.


require("strict")


-- ============================================================
-- SETTINGS
-- ============================================================

-- Base tolerance supplied by VCarve.
--
-- Vectric normally uses approximately:
--   0.001 mm
--   0.00004 inch
--
local GEOMETRY_TOLERANCE =
    GetDefaultContourTolerance()


-- Duplicate-location tolerance.
--
-- This is intentionally based on VCarve's normal geometry
-- tolerance rather than requiring mathematically identical
-- floating-point coordinates.
--
local POSITION_TOLERANCE =
    GetDefaultContourTolerance()


-- ============================================================
-- BASIC COMPARISON HELPERS
-- ============================================================


local function NearlyEqual(
    a,
    b,
    tolerance
)

    return math.abs(a - b) <= tolerance

end


local function GeometryValueEqual(
    a,
    b,
    tolerance
)

    local scale =
        math.max(
            1.0,
            math.abs(a),
            math.abs(b)
        )

    return
        math.abs(a - b) <=
        (tolerance * scale)

end


-- ============================================================
-- SPAN GEOMETRY
-- ============================================================
--
-- A span is a line, arc, or Bezier.
--
-- Instead of comparing X/Y coordinates directly, we describe
-- each span using measurements that don't care what direction
-- the object is pointing.
--
-- Therefore:
--
--       NOTCH
--
--       rotated 0 degrees
--       rotated 17 degrees
--       rotated 42 degrees
--       rotated 91 degrees
--
-- all produce the same geometry signature.
--
-- Vectric exposes span length, chord length, type, tangent
-- vectors, and control-point positions through the Lua API.
-- ============================================================


local function GetSpanType(span)

    if span.IsLineType then
        return "LINE"
    end

    if span.IsArcType then
        return "ARC"
    end

    if span.IsBezierType then
        return "BEZIER"
    end

    return "OTHER"

end


-- ------------------------------------------------------------
-- Create a rotation-independent description of one span.
--
-- Control points are converted into a LOCAL coordinate system
-- based on the span's own start/end points.
--
-- This removes the object's overall rotation from the
-- comparison.
-- ------------------------------------------------------------

local function GetSpanDescriptor(
    span,
    tolerance
)

    local descriptor = {}


    descriptor.type =
        GetSpanType(span)


    descriptor.length =
        span:GetLength(tolerance)


    descriptor.chord =
        span:ChordLength()


    descriptor.control_points =
        {}


    local start_pt =
        span.StartPoint2D

    local end_pt =
        span.EndPoint2D


    local dx =
        end_pt.X - start_pt.X

    local dy =
        end_pt.Y - start_pt.Y


    local chord =
        math.sqrt(
            (dx * dx) +
            (dy * dy)
        )


    -- --------------------------------------------------------
    -- If the chord has usable length, create a local coordinate
    -- system:
    --
    --   local X = along the span chord
    --   local Y = perpendicular to the span chord
    --
    -- This makes control-point geometry independent of rotation.
    -- --------------------------------------------------------

    if chord > tolerance then

        local ux =
            dx / chord

        local uy =
            dy / chord

        local vx =
            -uy

        local vy =
            ux


        local num_controls =
            span.NumberOfControlPoints


        for i = 0, num_controls - 1 do

            local cp =
                span:GetControlPointPosition(i)


            local cdx =
                cp.X - start_pt.X

            local cdy =
                cp.Y - start_pt.Y


            local local_x =
                (cdx * ux) +
                (cdy * uy)


            local local_y =
                (cdx * vx) +
                (cdy * vy)


            table.insert(
                descriptor.control_points,
                {
                    x = local_x,
                    y = local_y
                }
            )

        end

    end


    return descriptor

end


-- ============================================================
-- BUILD CONTOUR SIGNATURE
-- ============================================================


local function BuildContourSignature(
    contour,
    tolerance
)

    local signature = {}


    signature.is_closed =
        contour.IsClosed


    signature.is_open =
        contour.IsOpen


    signature.span_count =
        contour.Count


    signature.total_length =
        contour.Length


    signature.area =
        contour.Area


    signature.has_arcs =
        contour.ContainsArcs


    signature.has_beziers =
        contour.ContainsBeziers


    signature.spans =
        {}


    -- --------------------------------------------------------
    -- Extract every span.
    -- --------------------------------------------------------

    local pos =
        contour:GetHeadPosition()


    while pos ~= nil do

        local span

        span, pos =
            contour:GetNext(pos)


        if span ~= nil then

            table.insert(
                signature.spans,
                GetSpanDescriptor(
                    span,
                    tolerance
                )
            )

        end

    end


    -- --------------------------------------------------------
    -- Add rotation-independent transition information.
    --
    -- For every pair of connected spans we calculate:
    --
    --   dot product
    --   cross product
    --
    -- between the tangent vectors.
    --
    -- These represent the angle between spans but do NOT
    -- depend on the object's overall rotation.
    -- --------------------------------------------------------

    local count =
        #signature.spans


    if count > 1 then

        for i = 1, count do

            local next_index =
                i + 1


            if next_index > count then

                if signature.is_closed then
                    next_index = 1
                else
                    next_index = nil
                end

            end


            if next_index ~= nil then

                local span_a =
                    nil

                local span_b =
                    nil


                -- Retrieve the actual spans again.
                --
                -- This keeps the descriptor table simple and
                -- avoids storing Vectric span objects long-term.
                --

                local span_pos =
                    contour:GetHeadPosition()


                local index = 1


                while span_pos ~= nil do

                    local current_span

                    current_span, span_pos =
                        contour:GetNext(span_pos)


                    if index == i then
                        span_a = current_span
                    end


                    if index == next_index then
                        span_b = current_span
                    end


                    index =
                        index + 1

                end


                if span_a ~= nil and span_b ~= nil then

                    local v1 =
                        span_a:EndVector(true)

                    local v2 =
                        span_b:StartVector(true)


                    if v1 ~= nil and v2 ~= nil then

                        -- Dot = cos(angle)
                        local dot =
                            (v1.X * v2.X) +
                            (v1.Y * v2.Y)


                        -- Cross = sin(angle)
                        local cross =
                            (v1.X * v2.Y) -
                            (v1.Y * v2.X)


                        signature.spans[i].turn_dot =
                            dot

                        signature.spans[i].turn_cross =
                            cross

                    end

                end

            end

        end

    end


    return signature

end


-- ============================================================
-- CONTROL POINT COMPARISON
-- ============================================================


local function ControlPointsMatch(
    a,
    b,
    tolerance
)

    if #a.control_points ~=
       #b.control_points then

        return false

    end


    for i = 1, #a.control_points do

        local cp_a =
            a.control_points[i]

        local cp_b =
            b.control_points[i]


        if not GeometryValueEqual(
            cp_a.x,
            cp_b.x,
            tolerance
        ) then

            return false

        end


        if not GeometryValueEqual(
            cp_a.y,
            cp_b.y,
            tolerance
        ) then

            return false

        end

    end


    return true

end


-- ============================================================
-- SPAN COMPARISON
-- ============================================================


local function SpanMatches(
    a,
    b,
    tolerance
)

    if a.type ~= b.type then
        return false
    end


    if not GeometryValueEqual(
        a.length,
        b.length,
        tolerance
    ) then

        return false

    end


    if not GeometryValueEqual(
        a.chord,
        b.chord,
        tolerance
    ) then

        return false

    end


    -- Compare local control-point geometry.
    if not ControlPointsMatch(
        a,
        b,
        tolerance
    ) then

        return false

    end


    -- --------------------------------------------------------
    -- Compare the angle between this span and the next span.
    --
    -- These values are already rotation-independent.
    -- --------------------------------------------------------

    if
        a.turn_dot ~= nil and
        b.turn_dot ~= nil
    then

        if not GeometryValueEqual(
            a.turn_dot,
            b.turn_dot,
            0.00001
        ) then

            return false

        end


        if not GeometryValueEqual(
            a.turn_cross,
            b.turn_cross,
            0.00001
        ) then

            return false

        end

    elseif
        a.turn_dot ~= nil or
        b.turn_dot ~= nil
    then

        return false

    end


    return true

end


-- ============================================================
-- COMPARE COMPLETE CONTOUR SIGNATURES
-- ============================================================
--
-- This is the important part.
--
-- For an OPEN contour:
--
--     span 1
--     span 2
--     span 3
--     span 4
--
-- must match in that order.
--
-- For a CLOSED contour, the starting span doesn't matter.
--
-- Example:
--
-- Reference:
--     A B C D
--
-- Candidate:
--     C D A B
--
-- Those are the same closed geometry, so they match.
--
-- Overall rotation does not matter because none of the
-- measurements contain global X/Y orientation.
-- ============================================================


local function SignaturesMatch(
    reference,
    candidate,
    tolerance
)

    -- Basic contour properties.
    if reference.is_closed ~=
       candidate.is_closed then

        return false

    end


    if reference.span_count ~=
       candidate.span_count then

        return false

    end


    if reference.has_arcs ~=
       candidate.has_arcs then

        return false

    end


    if reference.has_beziers ~=
       candidate.has_beziers then

        return false

    end


    -- Overall geometry.
    if not GeometryValueEqual(
        reference.total_length,
        candidate.total_length,
        tolerance
    ) then

        return false

    end


    if not GeometryValueEqual(
        reference.area,
        candidate.area,
        tolerance
    ) then

        return false

    end


    local count =
        reference.span_count


    if count == 0 then
        return false
    end


    -- --------------------------------------------------------
    -- OPEN CONTOUR
    -- --------------------------------------------------------

    if not reference.is_closed then

        for i = 1, count do

            if not SpanMatches(
                reference.spans[i],
                candidate.spans[i],
                tolerance
            ) then

                return false

            end

        end


        return true

    end


    -- --------------------------------------------------------
    -- CLOSED CONTOUR
    --
    -- Try every possible cyclic starting span.
    -- --------------------------------------------------------

    for offset = 0, count - 1 do

        local all_match =
            true


        for i = 1, count do

            local candidate_index =
                ((i - 1 + offset) % count) + 1


            if not SpanMatches(
                reference.spans[i],
                candidate.spans[candidate_index],
                tolerance
            ) then

                all_match =
                    false

                break

            end

        end


        if all_match then
            return true
        end

    end


    return false

end


-- ============================================================
-- OBJECT INFORMATION
-- ============================================================


local function GetObjectInfo(
    object
)

    if object == nil then
        return nil
    end


    local contour =
        object:GetContour()


    if contour == nil then
        return nil
    end


    local info = {}


    info.contour =
        contour


    info.signature =
        BuildContourSignature(
            contour,
            GEOMETRY_TOLERANCE
        )


    -- --------------------------------------------------------
    -- Centre of gravity is used instead of bounding-box center.
    --
    -- This is important because the bounding-box center can
    -- change when a notch is rotated.
    -- --------------------------------------------------------

    info.location =
        contour.CentreOfGravity


    return info

end


-- ============================================================
-- LOCATION COMPARISON
-- ============================================================


local function SameLocation(
    a,
    b,
    tolerance
)

    if a == nil or b == nil then
        return false
    end


    return
        NearlyEqual(
            a.X,
            b.X,
            tolerance
        )
        and
        NearlyEqual(
            a.Y,
            b.Y,
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
    -- Verify job.
    -- --------------------------------------------------------

    if not job.Exists then

        DisplayMessageBox(
            "No VCarve job is currently loaded."
        )

        return false

    end


    -- --------------------------------------------------------
    -- Get selection.
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
    -- Copy selection into Lua table.
    -- --------------------------------------------------------

    local selected_objects =
        {}


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
    -- Find LAST selected object.
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

    local reference_info =
        GetObjectInfo(
            reference_object
        )


    if reference_info == nil then

        DisplayMessageBox(
            "The last-selected object does not contain " ..
            "a usable vector contour.\n\n" ..
            "Please select a single vector as the LAST " ..
            "selected object."
        )

        return false

    end


    -- ========================================================
    -- SEARCH
    -- ========================================================


    local matching_count =
        0


    local duplicate_count =
        0


    local duplicate_location_count =
        0


    local unique_locations =
        {}


    local duplicate_objects =
        {}


    -- --------------------------------------------------------
    -- Search all selected objects.
    -- --------------------------------------------------------

    for _, object in ipairs(selected_objects) do

        local info =
            GetObjectInfo(object)


        if info ~= nil then

            if SignaturesMatch(
                reference_info.signature,
                info.signature,
                GEOMETRY_TOLERANCE
            ) then


                matching_count =
                    matching_count + 1


                -- --------------------------------------------
                -- See if this matching object occupies a
                -- location we've already counted.
                -- --------------------------------------------

                local existing_location =
                    nil


                for _, location_data
                    in ipairs(unique_locations) do


                    if SameLocation(
                        info.location,
                        location_data.location,
                        POSITION_TOLERANCE
                    ) then

                        existing_location =
                            location_data

                        break

                    end

                end


                -- --------------------------------------------
                -- New unique location.
                -- --------------------------------------------

                if existing_location == nil then

                    table.insert(
                        unique_locations,
                        {
                            location = info.location,
                            object = object,
                            duplicate_count = 0
                        }
                    )


                -- --------------------------------------------
                -- Duplicate at an existing location.
                -- --------------------------------------------

                else

                    duplicate_count =
                        duplicate_count + 1


                    existing_location.duplicate_count =
                        existing_location.duplicate_count + 1


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
    -- UNIQUE COUNT
    -- ========================================================


    local unique_count =
        #unique_locations


    -- ========================================================
    -- HIGHLIGHT DUPLICATES
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


    selection:GroupSelectionFinished()


    job:Refresh2DView()


    -- ========================================================
    -- RESULTS
    -- ========================================================


    local message =

        "----------------------------------------\n" ..
        "       COUNT SELECTED OBJECT V3\n" ..
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
