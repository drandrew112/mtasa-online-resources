numb1 = 3976
numb2 = 4230

 function loadModel1 (name,id)
    Name = engineLoadTXD(name)
	engineImportTXD(Name,id)
 end

addEventHandler("onClientResourceStart",resourceRoot,function()
	loadModel1("txd/Txd1.txd",numb1) 
	loadModel1("txd/Txd2.txd",numb2) 
	loadModel1("txd/int_ppol2.txd",14846) 
	dff = engineLoadDFF("txd/police.dff", 3976 )
	engineReplaceModel(dff, 3976)
	
	col = engineLoadCOL ( "txd/police.col" )
	engineReplaceCOL ( col, 3976 )
	
	col = engineLoadCOL ( "txd/int_ppol2.col" )
	engineReplaceCOL ( col, 14846 )

	dff = engineLoadDFF("txd/int_ppol2.dff", 14846 )
	engineReplaceModel(dff, 14846)
end)
