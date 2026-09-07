local dir = "files"
function loadMod ( f, m )
	if fileExists ( dir..'/'.. f ..'.txd' ) then
		txd = engineLoadTXD ( dir ..'/'.. f ..'.txd' )
		engineImportTXD ( txd, m )
	end
	if fileExists ( dir..'/'.. f ..'.dff' ) then
		dff = engineLoadDFF ( dir..'/'.. f ..'.dff', m )
		engineReplaceModel ( dff, m )
	end
	if fileExists(dir..'/'.. f ..'.col') then
		col = engineLoadCOL(dir..'/'.. f ..'.col')
		engineReplaceCOL ( col, m )
	end
end



addEventHandler("onClientResourceStart", resourceRoot, 
function ()
	loadMod ( "k", 7557 )
end
)

engineSetAsynchronousLoading ( true, false )