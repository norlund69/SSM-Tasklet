codeunit 50155 "MOB WMS Receive G2I"
{
    // -------------------------------------------------------------------------
    // Receiving customisation — Sunshine Mills (SMBI-34)
    //
    // Per-line step flow (stepSorting="ById", standard workflow):
    //
    //   id  6   NumberOfPallets   integer, min 1, default 1            always
    //   id  7   PalletType        list of Pallet items                 always
    //   id  8   QtyPerPallet      decimal, min 0.00001                 always
    //   id 20   ToBin             standard step                        skipped — fixed to 'Production'
    //   id 31   expirationDate    standard step                        if tracked
    //   id 32   lotNumber         standard step                        if tracked
    //   id 50   Quantity          standard step                        auto-applied = QtyPerPallet × NumberOfPallets
    //   id 55   LicensePlate      standard step                        hidden — LP created automatically
    //
    // Custom steps 6, 7, 8 are injected via OnAddStepsToAnyLine.
    // LotNumber default (today's date) is set on the order line element via
    // OnAfterSetFromAnyLine so the {LotNumber} binding in app.cfg picks it up.
    // ExpirationDateValidation overrides it when the user enters an expiry date.
    //
    // On post: _Registration.Quantity = QtyPerPallet × NumberOfPallets (total).
    //          Divide across NumberOfPallets LPs; last LP absorbs rounding remainder.
    // -------------------------------------------------------------------------

    // =========================================================================
    // 1.  LINE STEPS — injected directly per line
    // =========================================================================
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Receive", 'OnGetReceiveOrderLines_OnAddStepsToAnyLine', '', true, true)]
    local procedure OnAddReceiveLineSteps(
       _RecRef: RecordRef;
       var _BaseOrderLineElement: Record "MOB NS BaseDataModel Element";
       var _Steps: Record "MOB Steps Element")
    begin
        // Step 6: Number of pallets.
        _Steps.Create_IntegerStep(6, 'NumberOfPallets');
        _Steps.Set_header('Number of pallets:');
        _Steps.Set_helpLabel('Enter the number of pallets for this line.');
        _Steps.Set_defaultValue('1');
        _Steps.Set_minValue('1');
        _Steps.Set_optional(false);
        _Steps.Set_onlineValidation('NumberOfPalletsValidation', true);

        // Step 7: Pallet type.
        _Steps.Create_ListStep(7, 'PalletType');
        _Steps.Set_header('Pallet type:');
        _Steps.Set_helpLabel('Select the pallet type for this delivery.');
        _Steps.Set_listValues(GetPalletTypeList());
        _Steps.Set_optional(false);
        _Steps.Set_onlineValidation('PalletTypeValidation', true);

        // Step 8: Quantity per pallet — auto-multiplies with NumberOfPallets and
        // applies the result to the standard Quantity step (which is then hidden).
        _Steps.Create_DecimalStep(8, 'QtyPerPallet', false);
        _Steps.Set_header('Qty per pallet:');
        _Steps.Set_helpLabel('Enter the quantity of items per pallet.');
        _Steps.Set_minValue('0.00001');
        _Steps.Set_optional(false);
        _Steps.Set_onlineValidation('QtyPerPalletValidation', true);
    end;

    // =========================================================================
    // 2.  ORDER LINE SETUP — ToBin and default LotNumber
    // =========================================================================

    // =========================================================================
    // 3.  POST — handle each registration line
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Receive", 'OnPostReceiveOrder_OnHandleRegistrationForWarehouseReceiptLine', '', true, true)]
    local procedure OnHandleReceiveRegistrationForWhseReceiptLine(
        var _Registration: Record "MOB WMS Registration";
        var _WhseReceiptLine: Record "Warehouse Receipt Line";
        var _NewReservationEntry: Record "Reservation Entry")
    var
        NumberOfPallets: Integer;
        ToBin: Code[20];
        PalletType: Code[20];
    begin
        if not Evaluate(NumberOfPallets, _Registration.GetValue('NumberOfPallets')) then
            NumberOfPallets := 1;
        if NumberOfPallets < 1 then
            NumberOfPallets := 1;

        ToBin := 'Production';

        PalletType := CopyStr(_Registration.GetValue('PalletType'), 1, MaxStrLen(PalletType));

        CreateReceiveLicensePlates(
            _Registration, _WhseReceiptLine, NumberOfPallets, ToBin, PalletType);
    end;

    // =========================================================================
    // 4.  LP CREATION  (Palletized path)
    // =========================================================================

    local procedure CreateReceiveLicensePlates(
        var _Registration: Record "MOB WMS Registration";
        var _WhseReceiptLine: Record "Warehouse Receipt Line";
        _NumberOfPallets: Integer;
        _ToBin: Code[20];
        _PalletType: Code[20])
    var
        G2ILicensePlateMgt: Codeunit "G2I License Plate Mgt";
        G2IReceiveSession: Codeunit "G2I Receive Session";
        NewLP: Record "MOB License Plate";
        SourceContent: Record "MOB License Plate Content";
        QtyPerPallet: Decimal;
        LastPalletQty: Decimal;
        i: Integer;
    begin
        if _Registration.Quantity <= 0 then
            exit;

        QtyPerPallet := Round(_Registration.Quantity / _NumberOfPallets, 0.00001, '=');
        LastPalletQty := _Registration.Quantity - (QtyPerPallet * (_NumberOfPallets - 1));

        SourceContent.Init();
        SourceContent.Validate(Type, SourceContent.Type::Item);
        SourceContent.Validate("No.", _WhseReceiptLine."Item No.");
        SourceContent.Validate("Variant Code", _WhseReceiptLine."Variant Code");
        SourceContent.Validate("Unit Of Measure Code", _Registration.UnitOfMeasure);
        SourceContent.Validate("Location Code", _Registration."Location Code");
        SourceContent.Validate("Bin Code", _ToBin);
        SourceContent.Validate(
            "Lot No.",
            CopyStr(_Registration.LotNumber, 1, MaxStrLen(SourceContent."Lot No.")));

        for i := 1 to _NumberOfPallets do begin
            if i = _NumberOfPallets then
                QtyPerPallet := LastPalletQty;

            NewLP.Init();
            NewLP.Validate("No.", G2ILicensePlateMgt.GetNextLicensePlateNo());
            NewLP.Validate("Location Code", _WhseReceiptLine."Location Code");
            NewLP.Validate("Bin Code", _ToBin);
            NewLP."LGS Pallet Type" := _PalletType;
            NewLP.Validate("LGS LPS LP Status Code", 'Released');
            NewLP.Insert(true);

            G2ILicensePlateMgt.AddContentLine(NewLP, SourceContent, QtyPerPallet);
            G2IReceiveSession.AddLicensePlateResult(NewLP."No.");
        end;
    end;

    // =========================================================================
    // 5.  POST-SUCCESS MESSAGE
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Receive", 'OnPostReceiveOrder_OnAfterPostAnyOrder', '', true, true)]
    local procedure OnAfterPostReceiveOrder(
        var _OrderValues: Record "MOB Common Element";
        var _RecRef: RecordRef;
        var _ResultMessage: Text)
    var
        G2IReceiveSession: Codeunit "G2I Receive Session";
        ResultLines: Text;
        CrLf: Text[2];
    begin
        ResultLines := G2IReceiveSession.GetResultLines();
        G2IReceiveSession.Clear();
        if ResultLines = '' then
            exit;
        CrLf[1] := 13;
        CrLf[2] := 10;
        _ResultMessage := 'Receipt posted successfully.' + CrLf + ResultLines;
    end;

    // =========================================================================
    // 6.  HELPERS
    // =========================================================================

    local procedure GetPalletTypeList() ReturnList: Text
    var
        PalletItem: Record Item;
    begin
        PalletItem.SetRange("LGS Item Type", PalletItem."LGS Item Type"::Pallet);
        if PalletItem.FindSet() then
            repeat
                if ReturnList = '' then
                    ReturnList := PalletItem."No."
                else
                    ReturnList += ';' + PalletItem."No.";
            until PalletItem.Next() = 0;

        if ReturnList = '' then
            ReturnList := ' '
        else
            ReturnList := ' ;' + ReturnList;
    end;

    // =========================================================================
    // 7.  ONLINE VALIDATION — QtyPerPallet step
    //
    // Fires when the user confirms QtyPerPallet.
    // Calculates TotalQty = QtyPerPallet × NumberOfPallets and returns it as a
    // stepUpdate for the standard 'Quantity' step with ApplyDirectly, so the
    // standard Quantity step is never shown.  _Registration.Quantity therefore
    // holds the correct total when the post handler runs.
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Whse. Inquiry", 'OnWhseInquiryOnCustomDocumentTypeAsXml', '', true, true)]
    local procedure OnQtyPerPalletValidationAsXml(
        var _XMLRequestDoc: XmlDocument;
        var _XMLResponseDoc: XmlDocument;
        _DocumentType: Text;
        var _RegistrationTypeTracking: Text[200];
        var _IsHandled: Boolean)
    var
        MobToolbox: Codeunit "MOB Toolbox";
        MobXmlMgt: Codeunit "MOB XML Management";
        MobRequestMgt: Codeunit "MOB NS Request Management";
        TempRequestValues: Record "MOB NS Request Element" temporary;
        WhseReceiptLine: Record "Warehouse Receipt Line";
        XmlResponseData: XmlNode;
        XmlStepUpdates: XmlNode;
        XmlStep: XmlNode;
        NumberOfPallets: Integer;
        QtyPerPallet: Decimal;
        TotalQty: Decimal;
        BackendId: Code[20];
    begin
        if _DocumentType <> 'QtyPerPalletValidation' then
            exit;

        _IsHandled := true;

        MobRequestMgt.SaveAdhocRequestValues(_XMLRequestDoc, TempRequestValues);

        if not Evaluate(NumberOfPallets, TempRequestValues.GetValue('NumberOfPallets')) then
            Error('Number of pallets is missing or invalid.');
        if NumberOfPallets < 1 then
            Error('Number of pallets must be at least 1.');

        if not Evaluate(QtyPerPallet, TempRequestValues.GetValue('QtyPerPallet')) then
            Error('Quantity per pallet is missing or invalid.');
        if QtyPerPallet <= 0 then
            Error('Quantity per pallet must be greater than 0.');

        TotalQty := QtyPerPallet * NumberOfPallets;

        BackendId := CopyStr(TempRequestValues.GetValue('backendId'), 1, MaxStrLen(BackendId));
        if WhseReceiptLine.Get(BackendId, TempRequestValues.Get_LineNumberAsInteger()) then
            if TotalQty > WhseReceiptLine."Qty. Outstanding" then
                Error('Total quantity (%1) exceeds the outstanding quantity (%2) on the receipt line.',
                    Format(TotalQty, 0, 9), Format(WhseReceiptLine."Qty. Outstanding", 0, 9));

        MobToolbox.InitializeResponseDoc(_XMLResponseDoc, XmlResponseData);

        MobXmlMgt.AddElement(XmlResponseData, 'stepUpdates',
            '', 'http://schemas.taskletfactory.com/MobileWMS/WarehouseInquiryDataModel', XmlStepUpdates);

        MobXmlMgt.AddElement(XmlStepUpdates, 'step', '', '', XmlStep);
        MobXmlMgt.AddAttribute(XmlStep, 'name', 'Quantity');
        MobXmlMgt.AddAttribute(XmlStep, 'value', Format(TotalQty, 0, 9));
        MobXmlMgt.AddAttribute(XmlStep, 'interactionPermission',
            Format(Enum::"MOB ValueInteractionPermission"::ApplyDirectly));
    end;

    // =========================================================================
    // 8.  ONLINE VALIDATION — ExpirationDate step
    //
    // Fires when the user confirms the expiration date.
    // Re-generates the lot number using the entered date and returns it as an
    // editable step update for 'LotNumber', replacing the pre-filled default.
    // Exits silently if the item has no lot format or the date cannot be parsed,
    // leaving whatever value is already in the LotNumber step unchanged.
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Whse. Inquiry", 'OnWhseInquiryOnCustomDocumentTypeAsXml', '', true, true)]
    local procedure OnExpirationDateValidationAsXml(
        var _XMLRequestDoc: XmlDocument;
        var _XMLResponseDoc: XmlDocument;
        _DocumentType: Text;
        var _RegistrationTypeTracking: Text[200];
        var _IsHandled: Boolean)
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        Item: Record Item;
        LotFormatHeader: Record "LGS EL Lot Format Header";
        LotNoInfo: Record "Lot No. Information";
        ItemLedgerEntry: Record "Item Ledger Entry";
        LotFormatImpl: Codeunit "LGS EL Lot Format Impl";
        MobToolbox: Codeunit "MOB Toolbox";
        MobXmlMgt: Codeunit "MOB XML Management";
        MobRequestMgt: Codeunit "MOB NS Request Management";
        TempRequestValues: Record "MOB NS Request Element" temporary;
        XmlResponseData: XmlNode;
        XmlStepUpdates: XmlNode;
        XmlStep: XmlNode;
        BackendId: Code[20];
        ExpirationDate: Date;
        LotDate: Date;
        LastLotNo: Text;
        LotNoText: Text;
    begin
        if _DocumentType <> 'ExpirationDateValidation' then
            exit;

        _IsHandled := true;

        MobRequestMgt.SaveAdhocRequestValues(_XMLRequestDoc, TempRequestValues);

        if not Evaluate(ExpirationDate, TempRequestValues.GetValue('ExpirationDate')) then
            exit;
        if ExpirationDate = 0D then
            exit;

        BackendId := CopyStr(TempRequestValues.GetValue('backendId'), 1, MaxStrLen(BackendId));
        if not WhseReceiptLine.Get(BackendId, TempRequestValues.Get_LineNumberAsInteger()) then
            exit;

        if not Item.Get(WhseReceiptLine."Item No.") then
            exit;
        if Item."LGS EL Lot No. Format Code" = '' then
            exit;
        if not LotFormatHeader.Get(Item."LGS EL Lot No. Format Code") then
            exit;

        LotNoInfo.SetRange("Item No.", WhseReceiptLine."Item No.");
        if LotNoInfo.FindLast() then
            LastLotNo := LotNoInfo."Lot No."
        else begin
            ItemLedgerEntry.SetRange("Item No.", WhseReceiptLine."Item No.");
            ItemLedgerEntry.SetRange("Location Code", WhseReceiptLine."Location Code");
            ItemLedgerEntry.SetFilter("Lot No.", '<>%1', '');
            if ItemLedgerEntry.FindLast() then
                LastLotNo := ItemLedgerEntry."Lot No.";
        end;

        // Lot date = expiration date minus the item's expiration calculation (e.g. -36M).
        // Falls back to expiration date itself when no calculation is defined on the item.
        LotDate := ExpirationDate;
        if Format(Item."Expiration Calculation") <> '' then
            LotDate := CalcDate(StrSubstNo('<-%1>', Format(Item."Expiration Calculation")), ExpirationDate);

        LotNoText := LotFormatImpl.GenerateLotNo(
            LotFormatHeader,
            WhseReceiptLine."Location Code",
            LotDate,
            '',     // ShiftCode
            '',     // WorkCenterCode
            '',     // MachineCenterCode
            LastLotNo);

        if LotNoText = '' then
            exit;

        MobToolbox.InitializeResponseDoc(_XMLResponseDoc, XmlResponseData);

        MobXmlMgt.AddElement(XmlResponseData, 'stepUpdates',
            '', 'http://schemas.taskletfactory.com/MobileWMS/WarehouseInquiryDataModel', XmlStepUpdates);

        MobXmlMgt.AddElement(XmlStepUpdates, 'step', '', '', XmlStep);
        MobXmlMgt.AddAttribute(XmlStep, 'name', 'LotNumber');
        MobXmlMgt.AddAttribute(XmlStep, 'value', LotNoText);
        MobXmlMgt.AddAttribute(XmlStep, 'interactionPermission',
            Format(Enum::"MOB ValueInteractionPermission"::AllowEdit));
    end;

    // =========================================================================
    // 9.  ONLINE VALIDATION — NumberOfPallets step
    //
    // Fires when the user confirms the NumberOfPallets value.
    // Rejects if the value is missing or less than 1.
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Whse. Inquiry", 'OnWhseInquiryOnCustomDocumentType', '', true, true)]
    local procedure OnNumberOfPalletsValidation(
        _DocumentType: Text;
        var _RequestValues: Record "MOB NS Request Element";
        var _ResponseElement: Record "MOB NS Resp Element";
        var _RegistrationTypeTracking: Text;
        var _IsHandled: Boolean)
    var
        NumberOfPallets: Integer;
        NumberOfPalletsText: Text;
    begin
        if _DocumentType <> 'NumberOfPalletsValidation' then
            exit;

        _IsHandled := true;

        NumberOfPalletsText := _RequestValues.GetValue('NumberOfPallets');

        if NumberOfPalletsText = '' then
            Error('Number of pallets must be entered.');

        if not Evaluate(NumberOfPallets, NumberOfPalletsText) then
            Error('Number of pallets must be a valid number.');

        if NumberOfPallets < 1 then
            Error('Number of pallets must be greater than 0.');
    end;

    // =========================================================================
    // 10. ONLINE VALIDATION — PalletType step
    //
    // Fires when the user confirms the PalletType selection.
    // Rejects if no pallet type was selected.
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Whse. Inquiry", 'OnWhseInquiryOnCustomDocumentType', '', true, true)]
    local procedure OnPalletTypeValidation(
        _DocumentType: Text;
        var _RequestValues: Record "MOB NS Request Element";
        var _ResponseElement: Record "MOB NS Resp Element";
        var _RegistrationTypeTracking: Text;
        var _IsHandled: Boolean)
    begin
        if _DocumentType <> 'PalletTypeValidation' then
            exit;

        _IsHandled := true;

        if _RequestValues.GetValue('PalletType') = '' then
            Error('Pallet type must be selected for Palletized receipts.');
    end;

    // =========================================================================
    // 11. DOCUMENT TYPE REGISTRATION
    //
    // Registers custom online validation document types handled by
    // MOB WMS Whse. Inquiry.  Runs on extension install and upgrade.
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Setup Doc. Types", 'OnAfterCreateDefaultDocumentTypes', '', true, true)]
    local procedure OnAfterCreateDefaultDocumentTypes()
    var
        MobWmsSetupDocTypes: Codeunit "MOB WMS Setup Doc. Types";
    begin
        MobWmsSetupDocTypes.CreateDocumentType('NumberOfPalletsValidation', '', Codeunit::"MOB WMS Whse. Inquiry");
        MobWmsSetupDocTypes.CreateDocumentType('PalletTypeValidation', '', Codeunit::"MOB WMS Whse. Inquiry");
        MobWmsSetupDocTypes.CreateDocumentType('QtyPerPalletValidation', '', Codeunit::"MOB WMS Whse. Inquiry");
        MobWmsSetupDocTypes.CreateDocumentType('ExpirationDateValidation', '', Codeunit::"MOB WMS Whse. Inquiry");
    end;

    // ToBin is fixed to 'Production'; suppress the Scan Bin step.
    // Also pre-fills LotNumber on the element so the {LotNumber} binding in
    // app.cfg shows a today-based default.  ExpirationDateValidation replaces
    // it with the expiry-date-derived lot number when the user enters a date.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Receive", 'OnGetReceiveOrderLines_OnAfterSetFromAnyLine', '', true, true)]
    local procedure OnSetReceiveToBin(
        _RecRef: RecordRef;
        var _BaseOrderLineElement: Record "MOB NS BaseDataModel Element")
    var
        LotNoText: Text;
    begin
        _BaseOrderLineElement.Set_ToBin('Production');
        _BaseOrderLineElement.Set_ValidateToBin(false);

        LotNoText := GetReceiveLotNo(_RecRef);
        if LotNoText <> '' then
            _BaseOrderLineElement.Set_LotNumber(LotNoText);
    end;

    // Returns the default lot number for the receive line using the item's LGS lot
    // format with today's date. Returns '' when not applicable.
    local procedure GetReceiveLotNo(_RecRef: RecordRef): Text
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        PurchaseLine: Record "Purchase Line";
        Item: Record Item;
        LotFormatHeader: Record "LGS EL Lot Format Header";
        LotNoInfo: Record "Lot No. Information";
        ItemLedgerEntry: Record "Item Ledger Entry";
        LotFormatImpl: Codeunit "LGS EL Lot Format Impl";
        ItemNo: Code[20];
        LocationCode: Code[10];
        LastLotNo: Text;
    begin
        case _RecRef.Number() of
            Database::"Warehouse Receipt Line":
                begin
                    _RecRef.SetTable(WhseReceiptLine);
                    ItemNo := WhseReceiptLine."Item No.";
                    LocationCode := WhseReceiptLine."Location Code";
                end;
            Database::"Purchase Line":
                begin
                    _RecRef.SetTable(PurchaseLine);
                    ItemNo := PurchaseLine."No.";
                    LocationCode := PurchaseLine."Location Code";
                end;
            else
                exit('');
        end;

        if not Item.Get(ItemNo) then
            exit('');
        if Item."LGS EL Lot No. Format Code" = '' then
            exit('');
        if not LotFormatHeader.Get(Item."LGS EL Lot No. Format Code") then
            exit('');

        LotNoInfo.SetRange("Item No.", ItemNo);
        if LotNoInfo.FindLast() then
            LastLotNo := LotNoInfo."Lot No."
        else begin
            ItemLedgerEntry.SetRange("Item No.", ItemNo);
            ItemLedgerEntry.SetRange("Location Code", LocationCode);
            ItemLedgerEntry.SetFilter("Lot No.", '<>%1', '');
            if ItemLedgerEntry.FindLast() then
                LastLotNo := ItemLedgerEntry."Lot No.";
        end;

        exit(LotFormatImpl.GenerateLotNo(
            LotFormatHeader,
            LocationCode,
            Today(),
            '', '', '',     // ShiftCode, WorkCenterCode, MachineCenterCode — not applicable for receive
            LastLotNo));
    end;

    // LP step is always suppressed — LPs are created automatically in the post handler.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS License Plate Receive", 'OnBeforeHandleToLicensePlateStep', '', true, true)]
    local procedure OnSkipReceiveLPStep(
        _RecRef: RecordRef;
        var _BaseOrderLineElement: Record "MOB NS BaseDataModel Element";
        var _Steps: Record "MOB Steps Element";
        var _IsHandled: Boolean)
    begin
        _IsHandled := true;
    end;
}
