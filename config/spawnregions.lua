-- Zroyecto Pombie - regiones donde pueden aparecer los personajes nuevos.
-- Fuente de verdad; copia de los valores por defecto de la 42.20.
-- Si en la fase 3 anadimos un mod de mapa, aqui es donde se le da spawn.
function SpawnRegions()
	return {
		{ name = "Muldraugh, KY", file = "media/maps/Muldraugh, KY/spawnpoints.lua" },
		{ name = "West Point, KY", file = "media/maps/West Point, KY/spawnpoints.lua" },
		{ name = "Rosewood, KY", file = "media/maps/Rosewood, KY/spawnpoints.lua" },
		{ name = "Riverside, KY", file = "media/maps/Riverside, KY/spawnpoints.lua" },
		-- Uncomment the line below to add a custom spawnpoint for this server.
--		{ name = "Twiggy's Bar", serverfile = "_bootstrap_spawnpoints.lua" },
	}
end
