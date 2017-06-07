USE [PRDEL]
GO

/****** Object:  StoredProcedure [dbo].[sp_zSop035PasoNPedidos1Pedido]    Script Date: 03/08/2016 13:41:03 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/*
Convert SOP ORDERS into ONE SOP Invoice
*/

                                      
/*                                               
Creado por: Javier Layana Dávalos.

Fecha: 2016.02.22
Descripción: Procedimiento para pasar varios Pedidos a un Pedido.

Modificaciones: 
                                                             
Grant exec on sp_zSop035PasoNPedidos1Pedido to DOTNETGRP
Grant exec on sp_zSop035PasoNPedidos1Pedido to DYNGRP

exec sp_zSop035PasoNPedidos1Pedido 'PEDI00030028;PEDI00030029;PEDI00030030;', '', 'sa'

*/                                               
CREATE Procedure [dbo].[sp_zSop035PasoNPedidos1Pedido] @pSOPNUMBRS varchar(max), @pGUIAS varchar(max), @pUsuario varchar(15)
as
                                             
Begin
	Declare @Return_Value int, @O_iErrorState int, @oErrString varchar(255), @vBACHNUMB varchar(15)
	Declare @iError int=0, @tError varchar(255)='', @tUsrMsg varchar(255)=''
	Declare @vNextSOPNUMBE varchar(21), @vDOCDATE datetime, @vDOCID varchar(15), @vSOPTYPE int, @vLNITMSEQ int, @vMaxIdControl int
	Declare @cCUSTNMBR varchar(15), @cITEMNMBR varchar(31), @cUOFM varchar(9), @cLOCNCODE varchar(11), @cCURRQTY numeric(19,5),
			@clITEMNMBR varchar(31), @clLOCNCODE varchar(11), @clSERLTNUM  varchar(21), @clSERLTQTY numeric(19,5)
	
	Set @vDOCDATE = DATEADD(dd, 0, DATEDIFF(dd, 0, GETDATE()))
	Set @vDOCID = 'PEDIDO'
	Set @vSOPTYPE = 2
	Set @vLNITMSEQ = 0

	/*Guadar los números de pedidos en una tabla temporal. */
	If Exists (Select * From tempdb..sysobjects Where name = '##tSop035A')                                             
		Drop Table ##tSop035A
	Create Table ##tSop035A (
		SOPNUMBE varchar(21)
	)
	Insert into ##tSop035A
	Select stringPart from dbo.zfnSplit2(@pSOPNUMBRS,';')

	/*Datos de Pedidos y Guias. Se buscan los Pedidos son en trabajo ya que se supone no han sido facturados. Si los pedidos
	no están en trabajo, significa que estos no pueden ser facturados. */
	If Exists (Select * From tempdb..sysobjects Where name = '##tSop035B')
		Drop Table ##tSop035B
	Create Table ##tSop035B (
		SOPTYPE int,
		SOPNUMBE varchar(21),
		CUSTNMBR varchar(15),
		CUSTNAME varchar(65),
		LNITMSEQ int,
		ITEMNMBR varchar(31),
		ITEMDESC varchar(101),
		UOFM varchar(9),
		LOCNCODE varchar(11),
		QUANTITY numeric(19,5),
		QTYCANCE numeric(19,5),
		g_Linea int, 
		g_Item varchar(31), 
		g_UOfM varchar(9), 
		g_bodega varchar(11), 
		g_Cantidad_Entregada numeric (19,5),
		QTYINVOICE numeric(19,5)
	)
	Insert Into ##tSop035B 
	Select A.SOPTYPE, A.SOPNUMBE, A.CUSTNMBR, A.CUSTNAME,
				B.LNITMSEQ, B.ITEMNMBR, B.ITEMDESC, B.UOFM, B.LOCNCODE, Isnull(B.QUANTITY,0), Isnull(B.QTYCANCE,0),
				C.Linea, C.Item, C.UOfM, C.bodega, Isnull(C.Cantidad_Entregada,0),
				Isnull(B.QUANTITY,0) - Isnull(B.QTYCANCE,0)-- - Isnull(C.Cantidad_Entregada,0)
				from SOP10100 A
				Inner join ##tSop035A A1 on A1.SOPNUMBE = A.SOPNUMBE 
				Left outer join SOP10200 B on B.SOPTYPE = A.SOPTYPE and B.SOPNUMBE = A.SOPNUMBE
				Left outer join (
								Select tipo_original, documento_original, Linea, Item, UOfM, bodega, Sum(Cantidad_Entregada) Cantidad_Entregada 
								from Tb_guias_remision
								Where estado = 0
								Group by tipo_original, documento_original, Linea, Item, UOfM, bodega
								) as C on C.tipo_original = B.SOPTYPE and C.documento_original = B.SOPNUMBE and C.Linea = B.LNITMSEQ
				where A.SOPTYPE = 2  and A.VOIDSTTS = 0 

	/*Guardar los lotes de los Pedidos que deben ser los mismos ser facturados. */
	If Exists (Select * From tempdb..sysobjects Where name = '##tSop035C')
	Drop Table ##tSop035C
	Create Table ##tSop035C (
		SOPTYPE int,
		SOPNUMBE varchar(21),
		LNITMSEQ int,
		SERLTNUM varchar(21),
		LOCNCODE varchar(11),
		SERLTQTY numeric(19,5),
		ITEMNMBR varchar(31)
	)
	Insert Into ##tSop035C
	Select A.SOPTYPE, A.SOPNUMBE, A.LNITMSEQ, A.SERLTNUM, B.LOCNCODE, Isnull(A.SERLTQTY,0), A.ITEMNMBR
	from SOP10201 A
	Inner join ##tSop035B B on B.SOPNUMBE = A.SOPNUMBE and B.LNITMSEQ = A.LNITMSEQ
	
	/* Validar que los pedidos no estén en histórico.*/
	If Exists ( Select 1 from SOP30200 Where SOPNUMBE in (Select SOPNUMBE from ##tSop035A))
	Begin
		Print 'Validando que pedidos no esten en histórico: error'
		Set @iError = 104
		Set @tError = 'Uno o varios pedidos se encuentran en estado histórico.'
		Set @tUsrMsg = @tError 
		Goto Fin
	End
	Else
		Print 'Validando que pedidos no esten en histórico: ok'

	/* Validar que existan datos. */
	If Not Exists (Select 1 from ##tSop035B)
	Begin
		Set @iError = 100
		Set @tError = 'Los pedidos no existen.'
		Set @tUsrMsg = @tError
		Goto Fin
	End
	
	/* Validar que los pedidos pertenezcan al mismo cliente. */
	Declare @vNroClientes as Int = 0
	Select @vNroClientes = count(*) from (Select distinct CUSTNMBR from ##tSop035B) as A
	If @vNroClientes > 1
	Begin
		Print 'Validando número de clientes: error'
		Set @iError = 101
		Set @tError = 'Los pedidos a pasar a factura deben ser del mismo cliente.'
		Set @tUsrMsg = @tError
		Goto Fin
	End
	Else
		Print 'Validando número de clientes: ok'


	/* Validar que los pedidos estén totalmente entregadas. */
	If exists (
				Select 1 from ##tSop035B
				Where
				QTYINVOICE <> 0 and
				QTYINVOICE > g_Cantidad_Entregada
	)
	Begin
		Select Distinct @tError =  Coalesce(@tError,' ') + Rtrim(SOPNUMBE) + ' ' from ##tSop035B where QTYINVOICE <> 0 and QTYINVOICE > g_Cantidad_Entregada
		Print 'Validando entregas: error ' + @tError
		Set @iError = 102
		Set @tError = 'Existen pedidos que no han sido totalmente despachados: ' + @tError
		Set @tUsrMsg = @tError
		Goto Fin
	End
	Else
		Print 'Validando entregas: ok'
	
	/*Validar que la cantidad a facturar sea igual a la cantidad entregada en guías.*/
	If Exists (
		Select 1 from ##tSop035B
		Where
		QTYINVOICE <> g_Cantidad_Entregada
	)
	Begin
		Print 'Validando que cantidad a facturar = cantidad entregada: error'
		Set @iError = 103
		Set @tError = 'La cantidad a facturar no coincide con la cantidad despachada.'
		Set @tUsrMsg = @tError 
		Goto Fin
	End
	Else
		Print 'Validando que cantidad a facturar = cantidad entregada: ok'
		
	/* Validar que en 1 pedido no exista el articulo dos veces 
	If Exists (
		Select SOPNUMBE, SOPTYPE, ITEMNMBR, count(*)Cnt 
		From SOP10200 
		Where SOPNUMBE In (Select SOPNUMBE from ##tSop035B)
		Group by SOPNUMBE,SOPTYPE,ITEMNMBR Having count(*)>1
	)
	Begin
		Print 'Validando que en 1 Pedido no exista un artículo mas de una vez: error'
		Set @iError = 105
		Set @tError = 'Existe al menos 1 Pedido con un artículo repetido dentro del Pedido.'
		Set @tUsrMsg = @tError 
		Goto Fin
	End
	Else
		Print 'Validando que en 1 Pedido no exista un articulo dos veces o más: ok'
	*/
	
	Begin Transaction TRX

	/* Crear lote de ventas */
	Set @vBACHNUMB = 'Pedidos/' + convert(varchar, getdate(), 111)
	If not exists (Select 1 from sy00500 where BACHNUMB = @vBACHNUMB)
	Begin
		Print 'Creando lote taCreateUpdateBatchHeaderRcd'
		Exec @Return_Value = taCreateUpdateBatchHeaderRcd        
		  @I_vBACHNUMB = @vBACHNUMB,
		  @I_vBCHCOMNT = @vBACHNUMB,        
		  @I_vSERIES = 3,
		  @I_vGLPOSTDT = N'1900/01/01',        
		  @I_vBCHSOURC = 'Sales Entry',        
		  @I_vORIGIN = 1,        
		  @I_vNUMOFTRX = 1,        
		  @I_vDOCAMT = 1.00,        
		  @O_iErrorState = @O_iErrorState OUTPUT,        
		  @oErrString = @oErrString OUTPUT;        
		If @Return_value <> 0
		Begin
			Print 'Error al ejecutar taCreateUpdateBatchHeaderRcd (@Return_Value).'
			Select @tError = ErrorDesc from DYNAMICS.dbo.taErrorCode where ErrorCode = @O_iErrorState
			Set @tUsrMsg = 'Se ha producido un error al ejecutar taCreateUpdateBatchHeaderRcd. ' + @tError + '.'
			Rollback Transaction TRX
			Goto Fin
		End
		Else
		Begin
			Print 'Se ha creado el lote de ventas:' + @vBACHNUMB
		End
	End

	/* Obtener número de factura */
	Exec @Return_Value = dbo.taGetSopNumber
		 @I_tSOPTYPE = @vSOPTYPE,
		 @I_cDOCID = @vDOCID, 
		 @I_tInc_Dec = 1,       
		 @O_vSopNumber = @vNextSOPNUMBE OUTPUT,        
		 @O_iErrorState = @O_iErrorState OUTPUT
	Print 'El siguiente número de Pedido es: ' + @vNextSOPNUMBE + '.'


	/* Para cada línea */
	Print 'Inicio para cada línea.'
	Declare cLINEA cursor for
		Select CUSTNMBR, ITEMNMBR, UOFM, LOCNCODE, Sum(QTYINVOICE)
		From ##tSop035B
		Group By CUSTNMBR, ITEMNMBR, UOFM, LOCNCODE
		Having  Sum(QTYINVOICE) > 0
	Open cLINEA
	Fetch Next From cLINEA into @cCUSTNMBR, @cITEMNMBR, @cUOFM, @cLOCNCODE, @cCURRQTY
	While @@fetch_status = 0
	Begin
		Print 'Dentro del While línea: ' + Rtrim(@cCUSTNMBR) + ' ' + Rtrim(@cITEMNMBR) + ' ' + Rtrim(@cUOFM) + ' ' + Rtrim(@cLOCNCODE) + ' ' + Convert(varchar, @cCURRQTY)
		Set @vLNITMSEQ = @vLNITMSEQ + 16384
		/*Insertar lotes: deben ser iguales que los de las guías.*/
		Begin
			Print 'Inicio para cada lote.'
			Declare cLOTE cursor for
				Select ITEMNMBR, LOCNCODE, SERLTNUM, Sum(SERLTQTY) 
				from ##tSop035C
				Where ITEMNMBR = @cITEMNMBR and LOCNCODE = @cLOCNCODE
				Group By ITEMNMBR, LOCNCODE, SERLTNUM
			Open cLOTE
			Fetch Next From cLOTE into @clITEMNMBR, @clLOCNCODE, @clSERLTNUM, @clSERLTQTY
			While @@fetch_status = 0
			Begin
				Print 'Dentro del While lote: ' + Rtrim(@clSERLTNUM) + ' ' + Convert(varchar,@clSERLTQTY)
				Begin Try
					Print 'Ejecutando taSopLotAuto.'
					Exec @Return_Value = taSopLotAuto
						@I_vSOPTYPE = @vSOPTYPE,
						@I_vSOPNUMBE = @vNextSOPNUMBE,
						@I_vLNITMSEQ = @vLNITMSEQ,
						@I_vITEMNMBR = @clITEMNMBR,
						@I_vLOCNCODE = @clLOCNCODE,
						@I_vQUANTITY = @clSERLTQTY,
						@I_vLOTNUMBR = @clSERLTNUM,
						@I_vQTYTYPE = 1,
						@I_vAUTOCREATELOT = 0,
						@I_vDOCID = @vDOCID,
						@O_iErrorState    = @O_iErrorState OUTPUT,
						@oErrString       = @oErrString OUTPUT
					If @Return_Value <> 0
					Begin
						Print 'Error al ejecutar taSopLotAuto (@Return_Value).'
						Set    @iError = 200
						Select @tError = ErrorDesc from DYNAMICS.dbo.taErrorCode where ErrorCode = @O_iErrorState
						Set    @tUsrMsg = 'Se ha producido un error al ejecutar taSopLotAuto. ' + @tError + '.'
						Close cLINEA
						Deallocate cLINEA
						Close cLOTE
						Deallocate cLOTE
						Rollback Transaction TRX
						Goto Fin
					End
				End Try
				
				Begin Catch
					Print 'Error al ejecutar taSopLotAuto (Catch).'
					Set		@iError		= 201
					Select	@tError		= error_message()
					Set		@tUsrMsg	= 'Se ha producido un error al ejecutar taSopLotAuto. ' + @tError + '.'
					Close cLINEA
					Deallocate cLINEA
					Close cLOTE
					Deallocate cLOTE
					Rollback Transaction TRX
					Goto Fin
				End Catch
				
				Fetch Next From cLOTE into @clITEMNMBR, @clLOCNCODE, @clSERLTNUM, @clSERLTQTY
			End
			Close cLOTE
			Deallocate cLOTE
		End
		
		/*Insertar líneas de ventas*/
		Begin Try
			Print 'Ejecutando taSopLineIvcInsert.'
			Exec @Return_Value = taSopLineIvcInsert
				@I_vSOPTYPE = @vSOPTYPE,
				@I_vSOPNUMBE = @vNextSOPNUMBE,
				@I_vDOCID = @vDOCID,
				@I_vCUSTNMBR = @cCUSTNMBR,
				@I_vDOCDATE = @vDOCDATE,
				@I_vACTLSHIP = @vDOCDATE,
				@I_vLOCNCODE = @cLOCNCODE,
				@I_vITEMNMBR = @clITEMNMBR,
				@I_vQUANTITY = @cCURRQTY,
				@I_vLNITMSEQ = @vLNITMSEQ,
				@I_vAUTOALLOCATELOT = 1,
				--@I_vQtyShrtOpt = 2,
				@O_iErrorState    = @O_iErrorState OUTPUT,
				@oErrString       = @oErrString OUTPUT
				If @Return_Value <> 0
				Begin
					Print 'Error al ejecutar taSopLineIvcInsert (@Return_Value).'
					Set    @iError = 202
					Select @tError = ErrorDesc from DYNAMICS.dbo.taErrorCode where ErrorCode = @O_iErrorState
					Set    @tUsrMsg = 'Se ha producido un error al ejecutar taSopLineIvcInsert. ' + @tError + '.'
					Close cLINEA
					Deallocate cLINEA
					Rollback Transaction TRX
					Goto Fin
				End
		End Try
				
		Begin Catch
			Print 'Error al ejecutar taSopLineIvcInsert (Catch).'
			Set		@iError		= 203
			Select	@tError		= error_message()
			Set		@tUsrMsg	= 'Se ha producido un error al ejecutar taSopLineIvcInsert. ' + @tError + '.'
			Close cLINEA
			Deallocate cLINEA
			Rollback Transaction TRX
			Goto Fin
		End Catch

		/* Guardar relacion del documento con los viejos documentos */
		Begin Try
			Print 'Guardando relacion de documentos/linea en tabla ZSOP010.'
			Insert into ZSOP010
			Select A.SOPTYPE, A.SOPNUMBE, A.CUSTNMBR, A.LNITMSEQ, A.ITEMNMBR, A.LOCNCODE, A.UOFM, A.QUANTITY, A.QTYCANCE ,
			@vSOPTYPE, @vNextSOPNUMBE, @vDOCDATE, @cCUSTNMBR, @vLNITMSEQ, @cITEMNMBR, @cLOCNCODE, @cUOFM, @cCURRQTY, 0,
			@pUsuario, getdate()
			from ##tSop035B A
			Where
			QTYINVOICE > 0 and ITEMNMBR = @cITEMNMBR and UOFM = @cUOFM and LOCNCODE = @cLOCNCODE
		End Try
		Begin Catch
			Print 'Error al guardar relacion de documentos/linea en tabla ZSOP010.'
			Set @iError = 204
			Set @tError = error_message()
			Set @tUsrMsg = 'Se ha producido un error al guardar la relacion de documentos en la tabla ZSOP010. ' + @tError + '.'
			Close cLINEA
			Deallocate cLINEA
			Rollback Transaction TRX
			Goto Fin
		End Catch
		
		--Update tb_relacion_guia_lotes
		--Set LNITMSEQ = @vLNITMSEQ
		--Where
		--SOPNUMBE in (Select SOPNUMBE from ##tSop035B Where ITEMNMBR = @cITEMNMBR and  LOCNCODE = @cLOCNCODE and UOFM = @cUOFM and QTYINVOICE > 0) and
		--ITEMNMBR = @cITEMNMBR and
		--LNITMSEQ in (Select g_Linea from ##tSop035B Where ITEMNMBR = @cITEMNMBR and  LOCNCODE = @cLOCNCODE and UOFM = @cUOFM and QTYINVOICE > 0)
		
		Fetch Next from cLINEA into @cCUSTNMBR, @cITEMNMBR, @cUOFM, @cLOCNCODE, @cCURRQTY
	End
	Close cLINEA
	Deallocate cLINEA
	
	/* Insertar cabecera del documento de ventas */
	Begin 
		Begin Try
			Print 'Ejecutando taSopHdrIvcInsert.'
			Exec @Return_Value = taSopHdrIvcInsert
				@I_vSOPTYPE  = @vSOPTYPE,
				@I_vDOCID    = @vDOCID,
				@I_vSOPNUMBE = @vNextSOPNUMBE,
				@I_vDOCDATE = @vDOCDATE,
				@I_vLOCNCODE = @cLOCNCODE,
				@I_vCUSTNMBR = @cCUSTNMBR,
				@I_vBACHNUMB = @vBACHNUMB,
				@O_iErrorState    = @O_iErrorState OUTPUT,
				@oErrString       = @oErrString OUTPUT
				If @Return_Value <> 0
				Begin
					Print 'Error al ejecutar taSopHdrIvcInsert (@Return_Value).'
					Set    @iError = 205
					Select @tError = ErrorDesc from DYNAMICS.dbo.taErrorCode where ErrorCode = @O_iErrorState
					Set    @tUsrMsg = 'Se ha producido un error al ejecutar taSopLineIvcInsert. ' + @tError + '.'
					Close cLOTE
					Deallocate cLOTE
					Rollback Transaction TRX
					Goto Fin
				End
		End Try
				
		Begin Catch
			Print 'Error al ejecutar taSopHdrIvcInsert (Catch).'
			Set		@iError		= 206
			Select	@tError		= error_message()
			Set		@tUsrMsg	= 'Se ha producido un error al ejecutar taSopLineIvcInsert. ' + @tError + '.'
			Close cLOTE
			Deallocate cLOTE
			Rollback Transaction TRX
			Goto Fin
		End Catch
	End

	/* Re-asignar Guías a nuevo Pedido */
	Begin
		Begin Try
			
			--Select * from ##tSop035B
			--Select 'SOP10200-1Nuevo', A.SOPNUMBE,A.LNITMSEQ,A.ITEMNMBR,B.LOCNCODE,SERLTNUM,SERLTQTY from SOP10201 A inner join SOP10200 B on A.SOPNUMBE = B.SOPNUMBE and A.LNITMSEQ = B.LNITMSEQ 
			--where A.SOPNUMBE = @vNextSOPNUMBE --and A.ITEMNMBR='4m0042'
			
			Print 'Actualizando Documento_Original en Tb_guias_remision y tb_relacion_guia_lotes.'
			Update Tb_guias_remision 
			Set Documento = @vNextSOPNUMBE, documento_original = @vNextSOPNUMBE
			From Tb_guias_remision A, ##tSop035B B
			Where
			A.tipo_original = B.SOPTYPE and A.documento_original = B.SOPNUMBE and A.Linea = B.LNITMSEQ and
			B.QTYINVOICE = B.g_Cantidad_Entregada and B.QTYINVOICE > 0
			
			Update tb_relacion_guia_lotes
			Set SOPNUMBE = @vNextSOPNUMBE
			From tb_relacion_guia_lotes A, ##tSop035B B
			Where
			A.SOPTYPE = B.SOPTYPE and A.SOPNUMBE = B.SOPNUMBE and A.LNITMSEQ = B.LNITMSEQ and
			B.QTYINVOICE = B.g_Cantidad_Entregada and B.QTYINVOICE > 0
			
			Print 'Actualizando Indice de Linea en Tb_guias_remision y tb_relacion_guia_lotes.'

			--Select'GuiaAntes', id_control,Linea,Item,bodega,Cantidad_Entregada from Tb_guias_remision where documento_original = @vNextSOPNUMBE and Item='4m0042' Order by Item,id_control
			--Select'RelacionAntes', * from tb_relacion_guia_lotes where SOPNUMBE = @vNextSOPNUMBE and ITEMNMBR='4m0042' Order by ITEMNMBR,id_control
			
			Update tb_relacion_guia_lotes
			Set LNITMSEQ = B.LNITMSEQ
			From Tb_guias_remision A, SOP10200 B, tb_relacion_guia_lotes C
			Where
			A.documento_original = B.SOPNUMBE and A.tipo_original = B.SOPTYPE and A.Item = B.ITEMNMBR and A.bodega = B.LOCNCODE and
			A.documento_original = C.SOPNUMBE and A.id_control = C.id_control and A.Linea = C.LNITMSEQ and
			A.documento_original = @vNextSOPNUMBE
			
			--Select 'RelacionDespues', * from tb_relacion_guia_lotes where SOPNUMBE = @vNextSOPNUMBE --and ITEMNMBR='4m0042' Order by ITEMNMBR
		
			--Select * from Tb_guias_remision where documento_original = @vNextSOPNUMBE
			
			Update Tb_guias_remision
			Set Linea = B.LNITMSEQ
			From Tb_guias_remision A, SOP10200 B
			Where
			A.documento_original = B.SOPNUMBE and A.tipo_original = B.SOPTYPE and
			A.Item = B.ITEMNMBR and A.bodega = B.LOCNCODE and 
			A.documento_original = @vNextSOPNUMBE
			
			--Select * from Tb_guias_remision where documento_original = @vNextSOPNUMBE
						
		End Try
		Begin Catch
			Print 'Error al re-asignar las guías originales hacia el nuevo Pedido.'
			Set @iError = 207
			Set @tError = 'Error al re-asignar las guías originales hacia el nuevo Pedido: tablas Tb_guias_remision y tb_relacion_guia_lotes.'
			Set @tUsrMsg = @tError
		End Catch
	End
	
	/* Anular Pedidos. Inventario disponible es actualizado. */
	Declare @cSOPNUMBE varchar(21)
	Declare cPedidos cursor for
		Select distinct SOPNUMBE from ##tSop035B
	
	Open cPedidos
	Fetch Next from cPedidos into @cSOPNUMBE
	While @@fetch_status = 0
	Begin
		Print 'While cPedidos, anular pedido: ' + @cSOPNUMBE
		Begin Try
			Print 'Ejecutando taSopVoidDocument'
			Exec @Return_Value = dbo.taSopVoidDocument
				@I_vSOPTYPE = 2,
				@I_vSOPNUMBE = @cSOPNUMBE,
				@O_iErrorState = @O_iErrorState OUTPUT,
				@oErrString = @oErrString OUTPUT
			if @Return_Value <> 0
			Begin
				Print 'Error al ejecutar taSopVoidDocument (@Return_Value).'
				Set @iError = 208
				Select @tError = errordesc from dynamics.dbo.taErrorCode where errorcode = @O_iErrorState
				Set @tUsrMsg = 'Se ha producido un error al ejecutar taSopVoidDocument. ' + @tError + '.'
				Close cPedidos
				Deallocate cPedidos
				Rollback Transaction TRX
				Goto Fin
			End
			Else
			Begin
				Print 'El pedido ha sido anulado: ' + @cSOPNUMBE
			End
		End Try
		Begin Catch
			Print 'Error al ejecutar taSopVoidDocument (Catch).'
			Set		@iError		= 209
			Select	@tError		= error_message()
			Set		@tUsrMsg	= 'Se ha producido un error al ejecutar taSopVoidDocument. ' + @tError + '.'
			Close cPedidos
			Deallocate cPedidos
			Rollback Transaction TRX
			Goto Fin
		End Catch
		Fetch Next from cPedidos into @cSOPNUMBE
	End
	Close cPedidos
	Deallocate cPedidos
	
	
	Commit Transaction TRX
	--Rollback Transaction TRX

	--Set @iError = 0
	--Set @tError = ''
	--Set @tUsrMsg = ''
	If @iError = 0 
		Set @tUsrMsg = 'Se generado el documento ' + Rtrim(@vNextSOPNUMBE) + '.'
	
	Fin:
	
	Select @iError as iError, @tError as tError, @tUsrMsg as tUsrMsg, Isnull(@vNextSOPNUMBE,'') as 'NextSOPNUMBE'


	--Select * from ##tSop035A
	--Select * from ##tSop035B
	--Select * from ##tSop035C

	
	Drop Table ##tSop035A
	Drop Table ##tSop035B
	Drop Table ##tSop035C
	
	

End







GO


