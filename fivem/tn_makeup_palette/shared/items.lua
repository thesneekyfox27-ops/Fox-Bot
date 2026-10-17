--[[
    Paste this into tgiann-inventory/items/items.lua

    IMPORTANT (tgiann): leave `unique` and `hasMetadata` FALSE here.
    This item carries no per-instance data - the saved makeup lives in
    player metadata, not on the item. Setting unique/hasMetadata will
    cause the usual stacking weirdness for no benefit.

    Image goes in: tgiann-inventory/inventory_images/images/makeup_palette.png
]]

['makeup_palette'] = {
    ['name']        = 'makeup_palette',
    ['label']       = 'Makeup Palette',
    ['weight']      = 100,
    ['type']        = 'item',
    ['image']       = 'makeup_palette.png',
    ['unique']      = false,
    ['useable']     = true,
    ['shouldClose'] = true,
    ['combinable']  = nil,
    ['description'] = 'A compact palette with a mirror. Touch up or wipe off your look.'
},
