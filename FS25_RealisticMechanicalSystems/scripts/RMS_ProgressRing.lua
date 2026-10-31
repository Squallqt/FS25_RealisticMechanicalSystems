-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Segmented progress ring
RMS_ProgressRing = {}
-- centre line radius, share of the ring box
RMS_ProgressRing.RADIUS = 107 / 256
RMS_ProgressRing.SEGMENTS = 100
-- segment slice size, share of the ring box
RMS_ProgressRing.SEGMENT_WIDTH = 36 / 1024
RMS_ProgressRing.SEGMENT_HEIGHT = 82 / 1024

---Creates the segment and disc overlays from the loaded atlas
function RMS_ProgressRing.createOverlays()
    RMS_ProgressRing.segment = g_overlayManager:createOverlay("rms_ProgressRing.segment", 0, 0, 0, 0)
    RMS_ProgressRing.disc = g_overlayManager:createOverlay("rms_ProgressRing.disc", 0, 0, 0, 0)
end

---
-- @param float centerX horizontal center in screen space
-- @param float centerY vertical center in screen space
-- @param float width ring width in screen space
-- @param float height ring height in screen space
-- @param float ratio progress between 0 and 1
-- @param table arcColor colour of the filled segments
-- @param table trackColor colour of the other segments, alpha optional
function RMS_ProgressRing.render(centerX, centerY, width, height, ratio, arcColor, trackColor)
    local overlay = RMS_ProgressRing.segment
    local segmentWidth, segmentHeight = width * RMS_ProgressRing.SEGMENT_WIDTH, height * RMS_ProgressRing.SEGMENT_HEIGHT
    local radiusX, radiusY = width * RMS_ProgressRing.RADIUS, height * RMS_ProgressRing.RADIUS
    local count = RMS_ProgressRing.SEGMENTS
    local lit = math.floor(math.clamp(ratio, 0, 1) * count + 1e-6)

    overlay:setDimension(segmentWidth, segmentHeight)
    for index = 0, count - 1 do
        local angle = (index + 0.5) * 2 * math.pi / count
        local color = index < lit and arcColor or trackColor
        overlay:setColor(color[1], color[2], color[3], color[4] or 1)
        overlay:setPosition(centerX + math.sin(angle) * radiusX - segmentWidth * 0.5, centerY + math.cos(angle) * radiusY - segmentHeight * 0.5)
        -- overlays turn counter-clockwise
        overlay:setRotation(-angle, segmentWidth * 0.5, segmentHeight * 0.5)
        overlay:render()
    end
end

---Draws a ring as high as a GUI area, centred in it
-- @param table area GUI element the ring fills
-- @param float ratio lit share of the ring
-- @param table? arcColor lit segments, the highlight by default
-- @param table? trackColor unlit segments, the ring track by default
function RMS_ProgressRing.renderInArea(area, ratio, arcColor, trackColor)
    local height = area.absSize[2]
    RMS_ProgressRing.render(area.absPosition[1] + area.absSize[1] * 0.5, area.absPosition[2] + height * 0.5,
        height * g_screenHeight / g_screenWidth, height, ratio, arcColor or RMS_Utils.COLOR.HIGHLIGHT,
        trackColor or RMS_Utils.COLOR.RING_TRACK)
end
