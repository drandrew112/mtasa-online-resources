function betolt()
	if tags_loaded then return end
	tags_loaded = true
	local tags_file = xmlLoadFile("saved_tags/positions.xml")
	if not tags_file then return end
	local tag_nodes = xmlNodeGetChildren(tags_file)
	for tagnum,tag_node in ipairs(tag_nodes) do
		local tagdata = xmlNodeGetAttributes(tag_node)
		exports.drawtag:createTagFromExistingData(
			nil,
			tagdata.x,tagdata.y
		)
	end
	xmlUnloadFile(tags_file)
end

function lement()
	if not tags_loaded then return end
	tags_loaded = nil
	local tags_file = xmlCreateFile("saved_tags/positions.xml","tags")
	if not tags_file then return end
	local png_file = fileCreate("saved_tags/tags_png.dat")
	if not png_file then xmlUnloadFile(tags_file) return end
	local all_tags = exports.drawtag:getAllTags()
	for tagnum,tag in ipairs(all_tags) do
		local att,x,y,z,x1,y1,z1,x2,y2,z2,nx,ny,nz,size,vis,png = exports.drawtag:getTagData(tag)
		if not att then
			local tag_node = xmlCreateChild(tags_file,"tag")
			xmlNodeSetAttribute(tag_node,"x",x)
			xmlNodeSetAttribute(tag_node,"y",y)
			destroyElement(tag)
		end
	end
	xmlSaveFile(tags_file)
	xmlUnloadFile(tags_file)
end