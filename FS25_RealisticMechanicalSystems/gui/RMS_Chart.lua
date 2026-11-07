-- Copyright © 2026 Squallqt. All rights reserved.

---Smooth chart strokes: lines, dashed curves and discs
RMS_Chart = {}

-- the line slice is 16 texels high, its opaque core 8
local LINE_SLICE_TO_CORE = 16 / 8

---Creates the stroke overlays from the loaded atlases
function RMS_Chart.createOverlays()
    RMS_Chart.line = g_overlayManager:createOverlay("rms_ChartLine.line", 0, 0, 0, 0)
    RMS_Chart.disc = g_overlayManager:createOverlay("gui.whiteCircleFilled", 0, 0, 0, 0)
end

---Draws a straight stroke between two screen points
function RMS_Chart.drawLine(x1, y1, x2, y2, thickness, color)
    local overlay = RMS_Chart.line
    local dx, dy = (x2 - x1) * g_screenWidth, (y2 - y1) * g_screenHeight
    local height = thickness * LINE_SLICE_TO_CORE / g_screenHeight
    overlay:setDimension(math.sqrt(dx * dx + dy * dy) / g_screenWidth, height)
    overlay:setColor(color[1], color[2], color[3], color[4])
    overlay:setPosition(x1, y1 - height * 0.5)
    -- overlays turn counter-clockwise
    overlay:setRotation(math.atan2(dy, dx), 0, height * 0.5)
    overlay:render()
end

---Draws a curve through screen points, solid or in dashes, bends rounded
-- @param float? dash dash length in screen pixels, solid when nil
function RMS_Chart.drawCurve(xs, ys, thickness, color, dash)
    local travelled, wasDrawn = 0, false
    for index = 2, #xs do
        local dx, dy = (xs[index] - xs[index - 1]) * g_screenWidth, (ys[index] - ys[index - 1]) * g_screenHeight
        local isDrawn = dash == nil or travelled % (dash * 1.8) < dash
        if isDrawn then
            RMS_Chart.drawLine(xs[index - 1], ys[index - 1], xs[index], ys[index], thickness, color)
            -- two straight strokes leave a notch outside a bend
            if wasDrawn then
                RMS_Chart.drawDisc(xs[index - 1], ys[index - 1], thickness, color)
            end
        end
        wasDrawn = isDrawn
        travelled = travelled + math.sqrt(dx * dx + dy * dy)
    end
end

---Draws a disc centred on a screen point
function RMS_Chart.drawDisc(x, y, diameter, color)
    local overlay = RMS_Chart.disc
    local width, height = diameter / g_screenWidth, diameter / g_screenHeight
    overlay:setDimension(width, height)
    overlay:setColor(color[1], color[2], color[3], color[4])
    overlay:setPosition(x - width * 0.5, y - height * 0.5)
    overlay:render()
end
