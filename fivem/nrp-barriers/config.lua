Config = {}

-- ============================================================================
--  Walls save AUTOMATICALLY to walls.json when you press ENTER.
--  You do not need to edit this file to add walls.
--  Manage them in game with /barrier
-- ============================================================================

-- ============================================================================
--  LAYER 1 - REAL COLLISION (invisible panels)
-- ============================================================================

-- Line every wall with invisible, frozen props so GTA's own physics stops
-- people and cars. This is what makes it feel like a real wall.
Config.UsePanels = true

-- Thin, solid props used as panels. The script measures each one in game,
-- skips any that do not exist or are too thick, and uses the widest one that
-- fits each wall segment. Order does not matter.
-- /barrier panels shows them so you can check the coverage.
Config.PanelModels = {
    'prop_ld_garaged_01',
    'prop_com_ls_door_01',
    'prop_ss1_14_garage_door',
    'prop_cons_plyboard_01',
    'prop_const_fence01a',
}

-- Panels thicker than this are ignored (thick panels stop you too early).
Config.MaxPanelThickness = 0.6

-- Panels are spawned for walls within this many metres of you.
Config.PanelRange = 150.0

-- Safety cap on the number of panel props per client.
Config.MaxPanels = 600

-- ============================================================================
--  LAYER 2 - SWEEP GUARD (catches anything the panels miss)
-- ============================================================================

-- How far off the wall line the guard keeps a ped, in metres. Keep this
-- SMALLER than where the panels physically stop you (~0.3) so the guard never
-- fights the physics during normal contact. It only kicks in on a real breach.
Config.Thickness = 0.2

-- Extra margin around a vehicle's body, in metres.
Config.VehicleMargin = 0.1

-- Also block vehicles, not just players on foot.
Config.BlockVehicles = true

-- Walls within this range of you are checked every frame.
Config.ActiveRange = 60.0

-- Movement bigger than this in one frame is treated as a teleport (respawn,
-- admin tp) and is not blocked.
Config.MaxStep = 40.0

-- ============================================================================
--  GEOMETRY
-- ============================================================================

-- Default wall height in metres, measured from the ground under each point.
-- Adjust live with PgUp / PgDn while building.
Config.DefaultHeight = 4.0

-- How far below your clicked points the wall starts, so small floor height
-- differences do not leave a gap you can crouch or fall under.
Config.FloorOffset = 1.0

-- ============================================================================
--  MISC
-- ============================================================================

-- Draw wall outlines. Toggle live with /barrier show
Config.ShowWalls = false

-- How far the aim raycast reaches while building, in metres.
Config.RayDistance = 60.0

-- Require permission to create, delete, teleport or open the UI.
-- Anyone with the 'nrp.barrier' ace OR the 'command' ace (your admins) passes.
Config.RequireAce = true

-- ============================================================================
--  LEGACY / SEED ONLY
--  On first run anything here migrates into walls.json once. Leave empty.
-- ============================================================================

Config.Walls = {

}
