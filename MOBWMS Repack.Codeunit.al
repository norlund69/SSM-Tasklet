codeunit 50159 "MOB WMS Repack G2I"
{
    // -------------------------------------------------------------------------
    // Repack Production Orders — Sunshine Mills (SMBI-36)
    //
    // The Repack module is a clone of the Production module showing only
    // Released Production Orders where LGS PW Repack = true.  The standard
    // Production module shows only orders where LGS PW Repack = false.
    //
    // Flow:
    //   1. User opens Repack module — sees only Repack = true orders.
    //   2. CONSUMPTION: User scans LP → confirms quantity → posts.
    //      The consumed quantity, lot number, and expiration date are
    //      captured in G2I Repack Session (SingleInstance).
    //   3. OUTPUT: User creates new LP → selects pallet type → confirms
    //      quantity and lot (pre-filled from session) → posts and prints.
    //      The same lot and expiration date are applied to the new LP.
    //
    // Filtering:
    //   Both the Production Output lookup and the standard Production module
    //   need to filter on LGS PW Repack.  This codeunit reads a context value
    //   'RepackModule' passed from the cfg to know which filter to apply:
    //     RepackModule = true  → show only LGS PW Repack = true
    //     RepackModule = false / absent → show only LGS PW Repack = false
    //
    // Session:
    //   G2I Repack Session (SingleInstance) carries the consumed lot, expiration
    //   date, and quantity from Consumption to Output within one device session.
    // -------------------------------------------------------------------------

    // =========================================================================
    // 1.  REFERENCE DATA — register RepackOrderLineFilters header configuration
    //
    // Adds a hidden 'RepackModule' field with default value 'true' to a custom
    // filter header key.  The Repack order list page uses this key via
    // <filter configurationKey="RepackOrderLineFilters"/>.  When the device
    // sends the order list request, TempHeaderFilter will contain an entry with
    // Name='RepackModule', Value='true', which our OnSetFilterProdOrderLine
    // subscriber reads to apply the LGS PW Repack = true filter.
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Reference Data", 'OnGetReferenceData_OnAddHeaderConfigurations', '', true, true)]
    local procedure OnAddRepackOrderLineFilters(var _HeaderFields: Record "MOB HeaderField Element")
    begin
        // Repack module filter — replicates standard ProdOrderLineFilters fields
        // plus locked OrderType defaulting to 'Repack'.
        _HeaderFields.InitConfigurationKey('RepackOrderLineFilters');
        _HeaderFields.Create_ListField_FilterLocationAsLocation(10);
        _HeaderFields.Create_DateField_StartingDate(20);
        _HeaderFields.Create_ListField_ProductionProgress(30);
        _HeaderFields.Create_ListField_WorkCenterFilter(40);
        _HeaderFields.Create_ListField_AssignedUserFilterAsAssignedUser(50);
        _HeaderFields.Create_ListField(60, 'OrderType', 'Order Type:');
        _HeaderFields.Set_listValues('Production;Repack;Combo');
        _HeaderFields.Set_defaultValue('Repack');
        _HeaderFields.Set_locked(true);
        _HeaderFields.Save();
    end;

    // =========================================================================
    // 2.  ORDER FILTER — OnGetProdOrderLines_OnSetFilterProdOrderLine
    //
    // Fires once per header filter field in the request.
    // When Name = 'OrderType', applies LGS PW Repack filter accordingly:
    //   Repack     → LGS PW Repack = true
    //   Production → LGS PW Repack = false
    //   Combo      → handled when implemented
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Production Consumption", 'OnGetProdOrderLines_OnSetFilterProdOrderLine', '', true, true)]
    local procedure OnSetFilterProdOrderLine(
        _HeaderFilter: Record "MOB NS Request Element";
        var _ProdOrderLine: Record "Prod. Order Line";
        var _ProductionOrder: Record "Production Order";
        var _IsHandled: Boolean)
    var
        G2IRepackSession: Codeunit "G2I Repack Session";
    begin
        if _HeaderFilter.Name <> 'OrderType' then
            exit;

        // Store in session so all subsequent subscribers know which module is active.
        G2IRepackSession.SetOrderType(_HeaderFilter.Value);
        // Filter production orders by LGS PW Repack based on the selected order type.
        case _HeaderFilter.Value of
            'Repack':
                _ProductionOrder.SetRange("LGS PW Repack", true);
            'Production':
                _ProductionOrder.SetRange("LGS PW Repack", false);
        // 'Combo' will be handled here when implemented.
        end;
        _IsHandled := true;
    end;

    // =========================================================================
    // 2.  REPACK CONSUMPTION STEPS — LP scan only
    //
    // The only step shown for Repack consumption is a scan of the source LP.
    // Lot number, expiration date, and quantity are auto-filled from the LP
    // content via online validation and applied with ApplyDirectly so the user
    // never sees those standard steps.
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Production Consumption", 'OnGetProdConsumptionLines_OnAfterSetFromProdOrderComponent', '', true, true)]
    local procedure OnAfterSetRepackConsumptionComponent(
        _ProdOrderComponent: Record "Prod. Order Component";
        _TrackingSpecification: Record "Tracking Specification";
        var _BaseOrderLineElement: Record "MOB NS BaseDataModel Element")
    var
        G2IRepackSession: Codeunit "G2I Repack Session";
    begin
        if G2IRepackSession.GetOrderType() <> 'Repack' then
            exit;

        _BaseOrderLineElement.Set_ValidateFromBin(false);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Production Consumption", 'OnGetProdConsumptionLines_OnAddStepsToProdOrderComponent', '', true, true)]
    local procedure OnAddLPScanStepToRepackConsumption(
        _ProdOrderComponent: Record "Prod. Order Component";
        _TrackingSpecification: Record "Tracking Specification";
        var _BaseOrderLineElement: Record "MOB NS BaseDataModel Element";
        var _Steps: Record "MOB Steps Element")
    var
        G2IRepackSession: Codeunit "G2I Repack Session";
    begin
        if G2IRepackSession.GetOrderType() <> 'Repack' then
            exit;

        _Steps.Create_TextStep(5, 'FromLicensePlate',
            'License Plate:', 'Scan LP:', 'Scan the source license plate to consume.', '', 20);
        _Steps.Set_optional(false);
        _Steps.Set_onlineValidation('RepackConsumptionLPValidation', true);
    end;

    // Fires when the user scans the source LP on the consumption component.
    // Auto-fills lot, expiration date, and quantity from the LP content via
    // ApplyDirectly so those standard steps are hidden from the user.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Whse. Inquiry", 'OnWhseInquiryOnCustomDocumentTypeAsXml', '', true, true)]
    local procedure OnRepackConsumptionLPValidation(
        var _XMLRequestDoc: XmlDocument;
        var _XMLResponseDoc: XmlDocument;
        _DocumentType: Text;
        var _RegistrationTypeTracking: Text[200];
        var _IsHandled: Boolean)
    var
        LicensePlate: Record "MOB License Plate";
        LPContent: Record "MOB License Plate Content";
        ItemLedgerEntry: Record "Item Ledger Entry";
        MobToolbox: Codeunit "MOB Toolbox";
        MobXmlMgt: Codeunit "MOB XML Management";
        MobRequestMgt: Codeunit "MOB NS Request Management";
        TempRequestValues: Record "MOB NS Request Element" temporary;
        XmlResponseData: XmlNode;
        XmlStepUpdates: XmlNode;
        XmlStep: XmlNode;
        LicensePlateNo: Code[20];
        ItemNo: Code[20];
        VariantCode: Code[10];
        ExpirationDate: Date;
    begin
        if _DocumentType <> 'RepackConsumptionLPValidation' then
            exit;

        _IsHandled := true;

        MobRequestMgt.SaveAdhocRequestValues(_XMLRequestDoc, TempRequestValues);
        LicensePlateNo := CopyStr(TempRequestValues.GetValue('FromLicensePlate'), 1, MaxStrLen(LicensePlateNo));
        ItemNo := CopyStr(TempRequestValues.GetValueOrContextValue('ItemNumber'), 1, MaxStrLen(ItemNo));
        VariantCode := CopyStr(TempRequestValues.GetValueOrContextValue('VariantCode'), 1, MaxStrLen(VariantCode));

        if not LicensePlate.Get(LicensePlateNo) then
            Error('License Plate %1 does not exist.', LicensePlateNo);

        LPContent.SetRange("License Plate No.", LicensePlateNo);
        LPContent.SetRange(Type, LPContent.Type::Item);
        LPContent.SetRange("No.", ItemNo);
        if VariantCode <> '' then
            LPContent.SetRange("Variant Code", VariantCode);
        if not LPContent.FindFirst() then
            Error('License Plate %1 does not contain item %2.', LicensePlateNo, ItemNo);

        MobToolbox.InitializeResponseDoc(_XMLResponseDoc, XmlResponseData);

        MobXmlMgt.AddElement(XmlResponseData, 'stepUpdates',
            '', 'http://schemas.taskletfactory.com/MobileWMS/WarehouseInquiryDataModel', XmlStepUpdates);

        if LPContent."Lot No." <> '' then begin
            MobXmlMgt.AddElement(XmlStepUpdates, 'step', '', '', XmlStep);
            MobXmlMgt.AddAttribute(XmlStep, 'name', 'LotNumber');
            MobXmlMgt.AddAttribute(XmlStep, 'value', LPContent."Lot No.");
            MobXmlMgt.AddAttribute(XmlStep, 'interactionPermission',
                Format(Enum::"MOB ValueInteractionPermission"::ApplyDirectly));

            // Read expiration date from the most recent item ledger entry for this lot.
            ItemLedgerEntry.SetRange("Item No.", LPContent."No.");
            ItemLedgerEntry.SetRange("Variant Code", LPContent."Variant Code");
            ItemLedgerEntry.SetRange("Lot No.", LPContent."Lot No.");
            ItemLedgerEntry.SetFilter("Expiration Date", '<>%1', 0D);
            if ItemLedgerEntry.FindFirst() then
                ExpirationDate := ItemLedgerEntry."Expiration Date";
        end;

        if ExpirationDate <> 0D then begin
            MobXmlMgt.AddElement(XmlStepUpdates, 'step', '', '', XmlStep);
            MobXmlMgt.AddAttribute(XmlStep, 'name', 'ExpirationDate');
            MobXmlMgt.AddAttribute(XmlStep, 'value',
                Format(ExpirationDate, 0, '<Day,2>-<Month,2>-<Year4>'));
            MobXmlMgt.AddAttribute(XmlStep, 'interactionPermission',
                Format(Enum::"MOB ValueInteractionPermission"::ApplyDirectly));
        end;

        MobXmlMgt.AddElement(XmlStepUpdates, 'step', '', '', XmlStep);
        MobXmlMgt.AddAttribute(XmlStep, 'name', 'Quantity');
        MobXmlMgt.AddAttribute(XmlStep, 'value', Format(LPContent.Quantity, 0, 9));
        MobXmlMgt.AddAttribute(XmlStep, 'interactionPermission',
            Format(Enum::"MOB ValueInteractionPermission"::ApplyDirectly));
    end;

    // =========================================================================
    // 3.  CONSUMPTION — capture lot, expiration date, and quantity from registration
    // =========================================================================

    // Fires during posting of each consumption journal line.
    // We capture the lot number, expiration date, and quantity from the
    // registration so Output can apply the same values to the new LP.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Production Consumption", 'OnPostProdConsumption_OnHandleRegistrationForProductionJnlLine', '', true, true)]
    local procedure OnHandleRepackConsumptionRegistration(
        var _Registration: Record "MOB WMS Registration";
        var _ProductionJnlLine: Record "Item Journal Line")
    var
        G2IRepackSession: Codeunit "G2I Repack Session";
        LicensePlate: Record "MOB License Plate";
        LotNo: Code[50];
        ExpirationDate: Date;
        Quantity: Decimal;
        FromLPNo: Code[20];
        PalletType: Code[20];
    begin
        if G2IRepackSession.GetOrderType() <> 'Repack' then
            exit;

        LotNo := CopyStr(_Registration.GetValue('LotNumber'), 1, MaxStrLen(LotNo));
        if not Evaluate(ExpirationDate, _Registration.GetValue('ExpirationDate')) then
            ExpirationDate := 0D;
        Quantity := _Registration.Quantity;
        FromLPNo := CopyStr(_Registration.GetValue('FromLicensePlate'), 1, MaxStrLen(FromLPNo));
        if LicensePlate.Get(FromLPNo) then
            PalletType := LicensePlate."LGS Pallet Type";

        G2IRepackSession.SetConsumptionValues(LotNo, ExpirationDate, Quantity, FromLPNo, PalletType);
    end;

    // =========================================================================
    // 3.  OUTPUT — pre-fill lot and quantity from session
    // =========================================================================

    // Pre-fill the output line with the consumed lot number, expiration date,
    // and quantity captured at consumption time.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Lookup", 'OnLookupOnProdOutput_OnAfterSetFromProductionOutput', '', true, true)]
    local procedure OnAfterSetFromRepackOutput(
        _ProdOrderLine: Record "Prod. Order Line";
        _ProdOrderRtngLine: Record "Prod. Order Routing Line";
        _TrackingSpecification: Record "Tracking Specification";
        var _LookupResponseElement: Record "MOB NS WhseInquery Element")
    var
        G2IRepackSession: Codeunit "G2I Repack Session";
        LotNo: Code[50];
        ExpirationDate: Date;
        Quantity: Decimal;
        FromLPNo: Code[20];
        PalletType: Code[20];
    begin
        if G2IRepackSession.GetOrderType() <> 'Repack' then
            exit;

        G2IRepackSession.GetConsumptionValues(LotNo, ExpirationDate, Quantity, FromLPNo, PalletType);

        // Show the source LP consumed in the previous step for reference.
        if FromLPNo <> '' then
            _LookupResponseElement.Set_DisplayLine7('Source LP: ' + FromLPNo);

        // Pre-fill pallet type — user confirms before posting.
        if PalletType <> '' then
            _LookupResponseElement.SetValue('PalletType', PalletType);

        // Pre-fill lot number and expiration — user confirms before posting.
        if LotNo <> '' then
            _LookupResponseElement.SetValue('LotNumber', LotNo);
        if ExpirationDate <> 0D then
            _LookupResponseElement.SetValue('ExpirationDate', Format(ExpirationDate, 0, '<Day,2>/<Month,2>/<Year4>'));

        // Pre-fill quantity from the consumed LP.
        if Quantity > 0 then begin
            _LookupResponseElement.Set_Quantity(Format(Quantity, 0, '<Precision,0:5><Standard Format,0>'));
            _LookupResponseElement.Set_UoM(_ProdOrderLine."Unit of Measure Code");
        end;
    end;

    // =========================================================================
    // 4.  OUTPUT POST — apply confirmed lot and expiration to journal line,
    //     then auto-create a new LP with the confirmed pallet type.
    // =========================================================================

    // Applies the user-confirmed lot number and expiration date to the output
    // journal line in case Tasklet's standard tracking does not pick them up.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Adhoc Registr.", 'OnPostAdhocRegistrationOnProdOutput_OnAfterCreateProductionJnlLine', '', true, true)]
    local procedure OnAfterCreateRepackOutputJnlLine(
        var _RequestValues: Record "MOB NS Request Element";
        var _ProductionJnlLine: Record "Item Journal Line")
    var
        G2IRepackSession: Codeunit "G2I Repack Session";
        LotNo: Code[50];
        ExpirationDate: Date;
    begin
        if G2IRepackSession.GetOrderType() <> 'Repack' then
            exit;

        LotNo := CopyStr(_RequestValues.GetValue('LotNumber'), 1, MaxStrLen(LotNo));
        if LotNo = '' then
            exit;

        _ProductionJnlLine.Validate("Lot No.", LotNo);
        if Evaluate(ExpirationDate, _RequestValues.GetValue('ExpirationDate')) then
            if ExpirationDate <> 0D then
                _ProductionJnlLine.Validate("Expiration Date", ExpirationDate);
        _ProductionJnlLine.Modify(true);
    end;

    // Auto-creates a new LP for the output item using the user-confirmed
    // pallet type, lot, and base quantity.  Mirrors OnAutoCreateProdOutputLP
    // in MOB WMS Production G2I but applies to Repack orders only.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Adhoc Registr.", 'OnPostAdhocRegistrationOnProdOutput_OnAfterCreateProductionJnlLine', '', true, true)]
    local procedure OnAutoCreateRepackOutputLP(
        var _RequestValues: Record "MOB NS Request Element";
        var _ProductionJnlLine: Record "Item Journal Line")
    var
        Item: Record Item;
        G2ILicensePlateMgt: Codeunit "G2I License Plate Mgt";
        NewLP: Record "MOB License Plate";
        SourceContent: Record "MOB License Plate Content";
        G2IRepackSession: Codeunit "G2I Repack Session";
        PalletType: Code[20];
        ToBin: Code[20];
        LotNo: Code[50];
    begin
        if G2IRepackSession.GetOrderType() <> 'Repack' then
            exit;

        if _ProductionJnlLine."Output Quantity" <= 0 then
            exit;

        if not Item.Get(_ProductionJnlLine."Item No.") then
            exit;

        ToBin := CopyStr(_RequestValues.GetValueOrContextValue('ToBin'), 1, MaxStrLen(ToBin));
        LotNo := CopyStr(_RequestValues.GetValue('LotNumber'), 1, MaxStrLen(LotNo));
        PalletType := CopyStr(_RequestValues.GetValue('PalletType'), 1, MaxStrLen(PalletType));

        SourceContent.Init();
        SourceContent.Validate(Type, SourceContent.Type::Item);
        SourceContent.Validate("No.", _ProductionJnlLine."Item No.");
        SourceContent.Validate("Variant Code", _ProductionJnlLine."Variant Code");
        SourceContent.Validate("Unit Of Measure Code", Item."Base Unit of Measure");
        SourceContent.Validate("Location Code", _ProductionJnlLine."Location Code");
        SourceContent.Validate("Bin Code", ToBin);
        SourceContent.Validate("Lot No.", LotNo);

        NewLP.Init();
        NewLP.Validate("No.", G2ILicensePlateMgt.GetNextLicensePlateNo());
        NewLP.Validate("Location Code", _ProductionJnlLine."Location Code");
        NewLP.Validate("Bin Code", ToBin);
        NewLP."LGS Pallet Type" := PalletType;
        NewLP.Validate("LGS LPS LP Status Code", 'Released');
        NewLP.Insert(true);

        G2ILicensePlateMgt.AddContentLine(NewLP, SourceContent, _ProductionJnlLine."Output Quantity (Base)");
    end;

    // =========================================================================
    // 5.  CLEAR SESSION after output is fully posted
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Setup Doc. Types", 'OnAfterCreateDefaultDocumentTypes', '', true, true)]
    local procedure OnAfterCreateDefaultDocumentTypes()
    var
        MobWmsSetupDocTypes: Codeunit "MOB WMS Setup Doc. Types";
    begin
        MobWmsSetupDocTypes.CreateDocumentType('RepackConsumptionLPValidation', '', Codeunit::"MOB WMS Whse. Inquiry");
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Production Output", 'OnPostProdOutput_OnAfterMobSyncItemTracking', '', true, true)]
    local procedure OnAfterRepackOutputPosted(
        var _ProdOrderLine: Record "Prod. Order Line";
        var _OutputJnlLine: Record "Item Journal Line")
    var
        G2IRepackSession: Codeunit "G2I Repack Session";
    begin
        if G2IRepackSession.GetOrderType() <> 'Repack' then
            exit;

        G2IRepackSession.Clear();
    end;
}
