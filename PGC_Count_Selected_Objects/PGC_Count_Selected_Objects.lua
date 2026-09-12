-- VECTRIC LUA SCRIPT
-- Name = Count Selected Object
-- Version = 4.3
--
-- Description:
-- Counts selected vectors matching the LAST-SELECTED object.
--
-- V4.3:
--   * Enforced a sane range (8-200) on Sample Points and said so in the
--     dialog, and gave the dialog more vertical room.
--
-- V4.2:
--   * Added an options dialog (PGC_Count_Selected_Objects.htm) so the
--     contour sample resolution can be adjusted without editing the
--     script. The value is remembered in the registry between runs.
--
-- V4.1 (bug-fix release):
--   * FIXED crash: GetObjectInfo() re-sampled the contour a second
--     time to find its location, then read point.X / point.Y from a
--     samples table that only ever has lowercase x / y fields. That
--     nil arithmetic is what made V4 error out immediately on every
--     run. BuildSignature() now computes the centroid once (before
--     normalizing) and returns it as part of the signature, so the
--     contour is only ever sampled once and there's only one place
--     the x/y fields are read.
--
-- V4 feature set (unchanged):
--   * Rotation independent
--   * Translation independent
--   * Starting-node independent for closed vectors
--   * Direction independent (tries both winding directions)
--   * Works from actual sampled contour geometry rather than X/Y bounds
--   * Detects overlapping duplicates
--   * Highlights duplicate objects
--
-- HOW TO USE:
--
--   1. Select all objects you want to search.
--   2. Select the object you want to COUNT LAST.
--   3. Run the gadget.
--
-- Nothing in the drawing is modified.


require("strict")


-- ============================================================
-- SETTINGS
-- ============================================================

-- Number of points used to sample each contour.
--
-- 32 is plenty for the small notch geometry we're dealing with
-- and keeps the gadget fast when hundreds of objects are
-- selected.
--
-- If some extremely complicated shapes need more detail, this
-- can be increased via the options dialog (32 / 64 / 128).
--
-- This is now set from the options dialog (see GetUserChoices)
-- and remembered in the registry between runs.
g_sample_count = 32


-- VCarve's normal geometry tolerance.
local GEOMETRY_TOLERANCE =
    GetDefaultContourTolerance()


-- Tolerance used when comparing sampled geometry.
--
-- This is deliberately a little more forgiving than the raw
-- VCarve contour tolerance because we're comparing sampled
-- floating-point positions.
--
local SAMPLE_TOLERANCE =
    GEOMETRY_TOLERANCE * 10.0


-- Tolerance for determining whether two matching objects are
-- occupying the same physical location.
local POSITION_TOLERANCE =
    GEOMETRY_TOLERANCE * 10.0


-- ============================================================
-- OPTIONS DIALOG
-- ============================================================
--
-- Lets the user adjust the contour sample resolution without
-- editing the script. Value is remembered in the registry.
-- ============================================================


function GetUserChoices(script_path)

    local registry = Registry("PGC_CountSelectedObjects")
    g_sample_count = registry:GetInt("SampleCount", g_sample_count)

    local html_path = "file:" .. script_path .. "\\PGC_Count_Selected_Objects.htm"
    local dialog = HTML_Dialog(false, html_path, 440, 320, "Count Selected Object")

    dialog:AddIntegerField("SampleCount", g_sample_count)

    if not dialog:ShowDialog() then
        return false
    end

    g_sample_count = dialog:GetIntegerField("SampleCount")

    if g_sample_count < 8 or g_sample_count > 200 then
        DisplayMessageBox("Sample Points must be between 8 and 200.")
        return false
    end

    registry:SetInt("SampleCount", g_sample_count)

    return true
end


-- ============================================================
-- BASIC MATH
-- ============================================================


local function Distance(
    a,
    b
)

    local dx =
        a.x - b.x

    local dy =
        a.y - b.y

    return math.sqrt(
        (dx * dx) +
        (dy * dy)
    )

end


local function NearlyEqual(
    a,
    b,
    tolerance
)

    return math.abs(a - b) <= tolerance

end


-- ============================================================
-- SAMPLE A CONTOUR
-- ============================================================
--
-- We walk around the contour at equal distance intervals.
--
-- We are NOT looking at:
--
--     X dimension
--     Y dimension
--     global angle
--     span orientation
--
-- We are looking at the actual shape.
--
-- NOTE: every point stored here uses lowercase .x / .y fields.
-- Every piece of code downstream that reads from a samples
-- table MUST use .x / .y (not .X / .Y) - that mismatch was the
-- cause of the V4.0 crash.
-- ============================================================


local function SampleContour(
    contour
)

    if contour == nil then
        return nil
    end


    if contour.IsEmpty then
        return nil
    end


    local length =
        contour.Length


    if length <= 0 then
        return nil
    end


    local samples =
        {}


    -- --------------------------------------------------------
    -- For closed contours we sample exactly g_sample_count
    -- equally spaced points around the perimeter.
    --
    -- For open contours we include both ends.
    -- --------------------------------------------------------

    local count =
        g_sample_count


    local step =
        length / count


    local carriage =
        ContourCarriage(
            0,
            0.0
        )


    if carriage.IsInvalid then
        return nil
    end


    if contour.IsClosed then

        for i = 0, count - 1 do

            local point =
                carriage:Position(
                    contour
                )


            if point == nil then
                return nil
            end


            table.insert(
                samples,
                {
                    x = point.X,
                    y = point.Y
                }
            )


            carriage:Move(
                contour,
                step
            )

        end


    else

        -- ----------------------------------------------------
        -- Open contour.
        --
        -- We sample the full length including the endpoint.
        -- ----------------------------------------------------

        for i = 0, count do

            local point =
                carriage:Position(
                    contour
                )


            if point == nil then
                return nil
            end


            table.insert(
                samples,
                {
                    x = point.X,
                    y = point.Y
                }
            )


            if i < count then

                local moved =
                    carriage:Move(
                        contour,
                        step
                    )


                if not moved then
                    break
                end

            end

        end

    end


    return samples

end


-- ============================================================
-- CENTROID OF THE RAW (UN-NORMALIZED) SAMPLES
-- ============================================================
--
-- This is the object's physical location, computed from the
-- sampled contour rather than the bounding-box center (which
-- can shift when a notch is rotated).
--
-- Uses the same samples table SampleContour() produced, so
-- this is the ONLY place the raw centroid is calculated - no
-- second sampling pass, no chance of an x/X mismatch.
-- ============================================================


local function CentroidOfSamples(
    samples
)

    if samples == nil or #samples == 0 then
        return nil
    end


    local center_x =
        0.0

    local center_y =
        0.0


    for _, point in ipairs(samples) do

        center_x =
            center_x + point.x

        center_y =
            center_y + point.y

    end


    center_x =
        center_x / #samples

    center_y =
        center_y / #samples


    return
    {
        X = center_x,
        Y = center_y
    }

end


-- ============================================================
-- NORMALIZE SAMPLES
-- ============================================================
--
-- Translate the sampled shape so its sample centroid is at
-- 0,0.
--
-- This removes the object's absolute position.
-- ============================================================


local function NormalizeSamples(
    samples,
    centroid
)

    if samples == nil or #samples == 0 then
        return nil
    end


    local normalized =
        {}


    for _, point in ipairs(samples) do

        table.insert(
            normalized,
            {
                x = point.x - centroid.X,
                y = point.y - centroid.Y
            }
        )

    end


    return normalized

end


-- ============================================================
-- ROTATION-INDEPENDENT DISTANCE SIGNATURE
-- ============================================================
--
-- For every sampled point we calculate its distance from the
-- sample centroid.
--
-- Rotation does not change this distance.
--
-- We also calculate the distance between consecutive sample
-- points.
--
-- This gives us a very strong shape fingerprint without
-- depending on X/Y orientation.
-- ============================================================


local function BuildSignature(
    contour
)

    local samples =
        SampleContour(
            contour
        )


    if samples == nil then
        return nil
    end


    -- --------------------------------------------------------
    -- Compute the physical location BEFORE normalizing -
    -- normalizing recenters the samples around 0,0 and we'd
    -- lose the real-world position if we did this after.
    -- --------------------------------------------------------

    local centroid =
        CentroidOfSamples(
            samples
        )


    if centroid == nil then
        return nil
    end


    local normalized =
        NormalizeSamples(
            samples,
            centroid
        )


    if normalized == nil then
        return nil
    end


    local signature =
        {}


    signature.closed =
        contour.IsClosed


    signature.count =
        #normalized


    signature.location =
        centroid


    signature.radius =
        {}


    signature.chord =
        {}


    -- --------------------------------------------------------
    -- Distance of every sample from the centroid.
    -- --------------------------------------------------------

    for i, point in ipairs(normalized) do

        local radius =
            math.sqrt(
                (point.x * point.x) +
                (point.y * point.y)
            )


        signature.radius[i] =
            radius

    end


    -- --------------------------------------------------------
    -- Distance between consecutive samples.
    -- --------------------------------------------------------

    for i = 1, #normalized do

        local next_i =
            i + 1


        if next_i > #normalized then

            if contour.IsClosed then
                next_i = 1
            else
                next_i = nil
            end

        end


        if next_i ~= nil then

            signature.chord[i] =
                Distance(
                    normalized[i],
                    normalized[next_i]
                )

        end

    end


    return signature

end


-- ============================================================
-- SIGNATURE VALUE COMPARISON
-- ============================================================


local function ValueMatches(
    a,
    b
)

    return
        NearlyEqual(
            a,
            b,
            SAMPLE_TOLERANCE
        )

end


-- ============================================================
-- COMPARE SIGNATURES
-- ============================================================
--
-- CLOSED SHAPES:
--
-- The starting point of a contour doesn't matter.
--
-- For example:
--
-- Reference:
--     A B C D E F
--
-- Candidate:
--     D E F A B C
--
-- These are the same shape.
--
-- We therefore try every possible cyclic offset.
--
-- We also test the reverse direction so that a contour drawn
-- clockwise and one drawn counter-clockwise still match.
-- ============================================================


local function SignatureMatches(
    reference,
    candidate
)

    if reference == nil or candidate == nil then
        return false
    end


    if reference.closed ~= candidate.closed then
        return false
    end


    if reference.count ~= candidate.count then
        return false
    end


    local count =
        reference.count


    if count == 0 then
        return false
    end


    -- ========================================================
    -- OPEN CONTOUR
    -- ========================================================

    if not reference.closed then

        -- Normal direction.
        local normal_match =
            true


        for i = 1, count do

            if not ValueMatches(
                reference.radius[i],
                candidate.radius[i]
            ) then

                normal_match =
                    false

                break

            end


            if
                reference.chord[i] ~= nil and
                candidate.chord[i] ~= nil
            then

                if not ValueMatches(
                    reference.chord[i],
                    candidate.chord[i]
                ) then

                    normal_match =
                        false

                    break

                end

            end

        end


        if normal_match then
            return true
        end


        -- Reverse direction.
        for i = 1, count do

            local reverse_i =
                count - i + 1


            if not ValueMatches(
                reference.radius[i],
                candidate.radius[reverse_i]
            ) then

                return false

            end

        end


        return true

    end


    -- ========================================================
    -- CLOSED CONTOUR
    -- ========================================================


    -- --------------------------------------------------------
    -- Try every possible starting point.
    -- --------------------------------------------------------

    for offset = 0, count - 1 do

        local match =
            true


        for i = 1, count do

            local candidate_i =
                ((i - 1 + offset) % count) + 1


            if not ValueMatches(
                reference.radius[i],
                candidate.radius[candidate_i]
            ) then

                match =
                    false

                break

            end


            if
                reference.chord[i] ~= nil and
                candidate.chord[candidate_i] ~= nil
            then

                if not ValueMatches(
                    reference.chord[i],
                    candidate.chord[candidate_i]
                ) then

                    match =
                        false

                    break

                end

            end

        end


        if match then
            return true
        end

    end


    -- --------------------------------------------------------
    -- Try the reverse direction.
    -- --------------------------------------------------------

    for offset = 0, count - 1 do

        local match =
            true


        for i = 1, count do

            local candidate_i =
                ((offset - (i - 1)) % count) + 1


            if not ValueMatches(
                reference.radius[i],
                candidate.radius[candidate_i]
            ) then

                match =
                    false

                break

            end


            if
                reference.chord[i] ~= nil and
                candidate.chord[candidate_i] ~= nil
            then

                if not ValueMatches(
                    reference.chord[i],
                    candidate.chord[candidate_i]
                ) then

                    match =
                        false

                    break

                end

            end

        end


        if match then
            return true
        end

    end


    return false

end


-- ============================================================
-- GET OBJECT INFORMATION
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


    local signature =
        BuildSignature(
            contour
        )


    if signature == nil then
        return nil
    end


    -- --------------------------------------------------------
    -- The location was already computed once, inside
    -- BuildSignature(), from the same sample pass used to
    -- build the shape signature. No second sampling call, no
    -- second place for an x/X typo to hide.
    -- --------------------------------------------------------

    return
    {
        signature = signature,
        location = signature.location
    }

end


-- ============================================================
-- LOCATION COMPARISON
-- ============================================================


local function SameLocation(
    a,
    b
)

    if a == nil or b == nil then
        return false
    end


    return
        NearlyEqual(
            a.X,
            b.X,
            POSITION_TOLERANCE
        )
        and
        NearlyEqual(
            a.Y,
            b.Y,
            POSITION_TOLERANCE
        )

end


-- ============================================================
-- MAIN
-- ============================================================


function main(script_path)

    local job =
        VectricJob()


    -- --------------------------------------------------------
    -- Check for job.
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
    -- Ask the user for the sample resolution.
    -- --------------------------------------------------------

    if not GetUserChoices(script_path) then
        return false -- user cancelled dialog
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
    -- Build reference signature.
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
    -- Scan every selected object.
    -- --------------------------------------------------------

    for _, object in ipairs(selected_objects) do

        local info =
            GetObjectInfo(
                object
            )


        if info ~= nil then

            if SignatureMatches(
                reference_info.signature,
                info.signature
            ) then


                matching_count =
                    matching_count + 1


                -- --------------------------------------------
                -- Determine whether this matching object is
                -- already represented at this location.
                -- --------------------------------------------

                local existing_location =
                    nil


                for _, location_data
                    in ipairs(unique_locations) do


                    if SameLocation(
                        info.location,
                        location_data.location
                    ) then

                        existing_location =
                            location_data

                        break

                    end

                end


                -- --------------------------------------------
                -- New unique object.
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
                -- Duplicate object.
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
        "       PGC COUNT SELECTED OBJECT V4.3\n" ..
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


    DisplayMessageBox(
        message
    )


    return true

end
