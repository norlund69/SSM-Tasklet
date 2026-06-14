codeunit 50157 "MOB WMS Production G2I"
{
    // -------------------------------------------------------------------------
    // Production customisation — Sunshine Mills (SMBI-34)
    //
    // a.   OUTPUT HEADER
    //      When a production order line is opened, display BOM No. and Pallet
    //      Type in the extra display lines.  Hide time tracking (Setup Time /
    //      Run Time) and scrap (Scrap Quantity / Scrap Code) options.
    //      Default output quantity UoM to PALL if it exists on the item.
    //      Pre-fill lot number from LGS EL Lot No. Format Code if configured;
    //      user can validate or change before posting.
    //
    // b.I  SCAN TO BIN — HIDDEN
    //      All production output goes to the fixed "Production" bin.  The ToBin
    //      step (id 20) is suppressed; the bin on the Prod. Order Line is used
    //      automatically by the standard posting path.
    //
    // b.II MACHINE CENTER / WORK CENTER STEP
    //      After opening the production order line, the user must select the
    //      Work Center (or Machine Center) they are working on.
    //
    // c.   CONSUMPTION STEPS
    //      c.I   Hide Picked Qty field — SSM does not pick components.
    //      c.II  Hide Scan Bin (Take) — all consumption from Production bin.
    //      c.III Default Quantity to zero — user must enter consumed qty.  A new list
    //      step is inserted that shows the Work Centers linked to the Prod.
    //      Order Routing Lines for this order.  The selected value is written
    //      to the output journal line at post time.
    //
    // Implementation notes:
    //   • OnLookupOnProdOutput_OnAfterSetFromProductionOutput sets the header
    //     display values (BOM No., Pallet Type) on the lookup response element
    //     before the order line is shown to the user.
    //   • OnGetRegistrationConfigurationOnProdOutput_OnAfterAddStepToProductionOutputQuantity
    //     fires once per step already added by Tasklet.  We use it to hide
    //     ToBin (b.I), SetupTime, RunTime, ScrapQuantity, and ScrapCode (a).
    //   • OnGetRegistrationConfigurationOnProdOutput_OnAddStepsToProductionOutputQuantity
    //     fires after all standard steps are added.  We use it to append the
    //     Work Center step (b.II).
    //   • OnPostAdhocRegistrationOnProdOutput_OnAfterCreateProductionJnlLine
    //     reads the selected Work Center and writes it to the journal line.
    // -------------------------------------------------------------------------

    // =========================================================================
    // a.  OUTPUT HEADER — add BOM No. and Pallet Type to display lines
    // =========================================================================
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Lookup", 'OnLookupOnProdOutput_OnAfterSetFromProductionOutput', '', true, true)]
    local procedure OnAfterSetFromProdOutput(
        _ProdOrderLine: Record "Prod. Order Line";
        _ProdOrderRtngLine: Record "Prod. Order Routing Line";
        _TrackingSpecification: Record "Tracking Specification";
        var _LookupResponseElement: Record "MOB NS WhseInquery Element")
    var
        ProductionOrder: Record "Production Order";
        Item: Record Item;
        LotFormatHeader: Record "LGS EL Lot Format Header";
        LotNoInfo: Record "Lot No. Information";
        ItemLedgerEntry: Record "Item Ledger Entry";
        LotFormatImpl: Codeunit "LGS EL Lot Format Impl";
        ItemUoM: Record "Item Unit of Measure";
        WorkCenterCode: Code[20];
        MachineCenterCode: Code[20];
        LastLotNo: Text;
        LotNoText: Text;
        PallQtyPerUoM: Decimal;
        NewLine: Char;
        G2IRepackSession: Codeunit "G2I Repack Session";
    begin
        // Persist order type in the element so GetRegistrationConfiguration
        // (a new session) can read it from transferred context instead of
        // relying on G2IRepackSession which is empty in the new session.
        _LookupResponseElement.SetValue('G2I_OrderType', G2IRepackSession.GetOrderType());

        if G2IRepackSession.GetOrderType() <> 'Production' then
            exit;

        // Remove Actual Setup Time, Actual Run Time and Actual Scrap Qty from the
        // order line display — SSM does not track these on the handheld.
        _LookupResponseElement.SetValue('ExtraInfo2_Col1', '');
        _LookupResponseElement.SetValue('ExtraInfo2_Col2', '');

        if _ProdOrderLine."Production BOM No." <> '' then begin
            if _ProdOrderLine."Production BOM Version Code" <> '' then
                _LookupResponseElement.Set_DisplayLine7(
                    'BOM: ' + _ProdOrderLine."Production BOM No." + '  v.' + _ProdOrderLine."Production BOM Version Code")
            else
                _LookupResponseElement.Set_DisplayLine7('BOM: ' + _ProdOrderLine."Production BOM No.");
        end;

        // Display Pallet Type — read from prod. order line first, fall back to header.
        if _ProdOrderLine."LGS Pallet Type" <> '' then
            _LookupResponseElement.Set_DisplayLine8('Pallet Type: ' + _ProdOrderLine."LGS Pallet Type")
        else
            if ProductionOrder.Get(ProductionOrder.Status::Released, _ProdOrderLine."Prod. Order No.") then
                if ProductionOrder."LGS Pallet Type" <> '' then
                    _LookupResponseElement.Set_DisplayLine8('Pallet Type: ' + ProductionOrder."LGS Pallet Type");

        // Non-Finished-Good items default to quantity 0 — they are not the primary
        // output so the remaining quantity should not pre-fill.
        // Finished Good items default to PALL UoM quantity if PALL exists on the item.
        if Item.Get(_ProdOrderLine."Item No.") then begin
            if Item."LGS Item Type" <> Item."LGS Item Type"::"Finished Good" then
                _LookupResponseElement.Set_Quantity('0')
            else if ItemUoM.Get(_ProdOrderLine."Item No.", 'PALL') then begin
                if ItemUoM."Qty. per Unit of Measure" > 0 then
                    PallQtyPerUoM := Round(
                        _ProdOrderLine."Remaining Quantity" / ItemUoM."Qty. per Unit of Measure",
                        0.00001, '=');
                _LookupResponseElement.Set_UoM('PALL');
                _LookupResponseElement.Set_Quantity(Format(PallQtyPerUoM, 0, '<Precision,0:5><Standard Format,0>'));
                NewLine := 10;
                _LookupResponseElement.SetValue('DisplayUoM', 'UoM: PALL' + NewLine + 'Qty pr. PALL = ' + Format(ItemUoM."Qty. per Unit of Measure", 0, '<Precision,0:5><Standard Format,0>'));
            end;
        end;

        // Pre-fill lot number from the item's lot format if configured.
        // Work Center / Machine Center resolved from the routing line if available.
        // This gives the user a default even when no work center step is shown.
        if Item.Get(_ProdOrderLine."Item No.") then
            if Item."LGS EL Lot No. Format Code" <> '' then
                if LotFormatHeader.Get(Item."LGS EL Lot No. Format Code") then begin
                    // Resolve work/machine center from routing line.
                    if _ProdOrderRtngLine."No." <> '' then
                        if _ProdOrderRtngLine.Type = _ProdOrderRtngLine.Type::"Machine Center" then begin
                            MachineCenterCode := _ProdOrderRtngLine."No.";
                            WorkCenterCode := _ProdOrderRtngLine."Work Center No.";
                        end else
                            WorkCenterCode := _ProdOrderRtngLine."No.";

                    // Resolve last lot number.
                    LotNoInfo.SetRange("Item No.", _ProdOrderLine."Item No.");
                    if LotNoInfo.FindLast() then
                        LastLotNo := LotNoInfo."Lot No."
                    else begin
                        ItemLedgerEntry.SetRange("Item No.", _ProdOrderLine."Item No.");
                        ItemLedgerEntry.SetRange("Location Code", _ProdOrderLine."Location Code");
                        ItemLedgerEntry.SetFilter("Lot No.", '<>%1', '');
                        if ItemLedgerEntry.FindLast() then
                            LastLotNo := ItemLedgerEntry."Lot No.";
                    end;

                    LotNoText := LotFormatImpl.GenerateLotNo(
                        LotFormatHeader,
                        _ProdOrderLine."Location Code",
                        Today(),
                        GetShiftCodeForWorkCenter(WorkCenterCode),
                        WorkCenterCode,
                        MachineCenterCode,
                        LastLotNo);

                    if LotNoText <> '' then
                        _LookupResponseElement.SetValue('LotNumber', LotNoText);
                end;

        // Suppress time tracking and scrap steps — SSM does not register these on
        // the handheld.  Setting Register* = false prevents CreateStepsForProdOutput*
        // from adding the steps at all, which is cleaner than hiding them via the
        // OnAfterAddStep event (which fires from a different event than Quantity steps).
        _LookupResponseElement.SetValue('RegisterSetupTime', 'false');
        _LookupResponseElement.SetValue('RegisterRunTime', 'false');
        _LookupResponseElement.SetValue('RegisterScrapQuantity', 'false');
        _LookupResponseElement.SetValue('RegisterScrapCode', 'false');
    end;

    // =========================================================================
    // a. + b.I  HIDE TO BIN AND EXPIRATION DATE STEPS
    //
    // OnAfterAddStepToProductionOutputQuantity fires once per step after
    // Tasklet adds it to the step buffer.  We use it to suppress unwanted
    // steps by setting them invisible.
    //
    // Note: Time tracking (SetupTime/RunTime) and scrap steps are suppressed
    // upstream by setting Register* = false in OnAfterSetFromProductionOutput,
    // so they are never added to the buffer and don't need hiding here.
    // =========================================================================
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Adhoc Registr.", 'OnGetRegistrationConfigurationOnProdOutput_OnAfterAddStepToProductionOutputQuantity', '', true, true)]
    local procedure OnAfterAddStepToProdOutputQuantity(
        _RegistrationType: Text;
        var _LookupResponse: Record "MOB NS WhseInquery Element";
        var _Step: Record "MOB Steps Element")
    var
        OrderType: Text;
    begin
        OrderType := _LookupResponse.GetValue('G2I_OrderType');

        case _Step.Get_name() of
            // b.I: Hide ToBin for Production — output goes to the fixed Production bin.
            'ToBin':
                if OrderType = 'Production' then begin
                    _Step.Set_visible(false);
                    _Step.Save();
                end;

            // a: Hide expiration date — not used in production output.
            'ExpirationDate':
                if OrderType = 'Production' then begin
                    _Step.Set_visible(false);
                    _Step.Save();
                end;

            // b.II: WorkCenter is only relevant for Production orders.
            // At login (order type blank) the step is hidden so it does not
            // appear before an order is selected. Per-order it is shown only
            // when the order type is Production.
            'WorkCenter':
                if OrderType <> 'Production' then begin
                    _Step.Set_visible(false);
                    _Step.Save();
                end;
        end;
    end;

    // =========================================================================
    // b.II  WORK CENTER / MACHINE CENTER STEP
    //
    // The step is always added in OnAddStepsToProductionOutput so it is present
    // in the scanner's cached config from login.  OnAfterAddStepToProdOutputQuantity
    // hides it when no order is selected (blank order type) or when the order is
    // Repack/Combo.  The routing line list is populated per-order when the
    // ProdOrderRtngLine_RecordId is available in the lookup response.
    // Id 5 places WorkCenter before all standard steps (ToBin 20, LotNumber 40, Quantity 80).
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Adhoc Registr.", 'OnGetRegistrationConfigurationOnProdOutput_OnAddStepsToProductionOutput', '', true, true)]
    local procedure OnAddWorkCenterStepToProdOutput(
        var _LookupResponse: Record "MOB NS WhseInquery Element";
        var _Steps: Record "MOB Steps Element")
    var
        ProdOrderRtngLine: Record "Prod. Order Routing Line";
        CurrentRtngLine: Record "Prod. Order Routing Line";
        ProdOrderRtngLineRecordId: RecordId;
        WorkCenterList: Text;
        DefaultValue: Code[20];
    begin
        // Build the routing line list when an order is selected.
        // At login the RecordId is blank — the step is still added so it lands
        // in the scanner's cached config; OnAfterAddStepToProdOutputQuantity
        // hides it until a Production order is selected.
        if Evaluate(ProdOrderRtngLineRecordId, _LookupResponse.GetValue('ProdOrderRtngLine_RecordId')) then
            if CurrentRtngLine.Get(ProdOrderRtngLineRecordId) then begin
                ProdOrderRtngLine.SetRange(Status, CurrentRtngLine.Status);
                ProdOrderRtngLine.SetRange("Prod. Order No.", CurrentRtngLine."Prod. Order No.");
                ProdOrderRtngLine.SetRange("Routing Reference No.", CurrentRtngLine."Routing Reference No.");
                if ProdOrderRtngLine.FindSet() then begin
                    repeat
                        if WorkCenterList = '' then
                            WorkCenterList := ProdOrderRtngLine."No."
                        else
                            WorkCenterList += ';' + ProdOrderRtngLine."No.";
                    until ProdOrderRtngLine.Next() = 0;
                    DefaultValue := CurrentRtngLine."No.";
                end;
            end;

        // No routing lines available (login time or order has no routing).
        // Use 'N/A' so the cached step definition has a valid list entry.
        if WorkCenterList = '' then begin
            WorkCenterList := 'N/A';
            DefaultValue := 'N/A';
        end;

        _Steps.Create_ListStep(5, 'WorkCenter');
        _Steps.Set_header('Work center:');
        _Steps.Set_helpLabel('Select the work center or machine center for this output.');
        _Steps.Set_listValues(WorkCenterList);
        _Steps.Set_defaultValue(DefaultValue);
        _Steps.Set_optional(false);
        _Steps.Set_onlineValidation('ProdOutputWorkCenterValidation', true);
    end;

    // Online validation for WorkCenter step.
    // Uses LGS EL Lot Format Impl.GenerateLotNo directly so the full context
    // (item, location, date, work center) is available — TryGenerateLotNoForItem
    // does not accept a work center parameter so we call GenerateLotNo ourselves,
    // mirroring what TryGenerateLotNoFromItemJournalLineRecord does.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Whse. Inquiry", 'OnWhseInquiryOnCustomDocumentTypeAsXml', '', true, true)]
    local procedure OnProdOutputWorkCenterValidation(
        var _XMLRequestDoc: XmlDocument;
        var _XMLResponseDoc: XmlDocument;
        _DocumentType: Text;
        var _RegistrationTypeTracking: Text[200];
        var _IsHandled: Boolean)
    var
        Item: Record Item;
        LotFormatHeader: Record "LGS EL Lot Format Header";
        LotNoInfo: Record "Lot No. Information";
        ItemLedgerEntry: Record "Item Ledger Entry";
        LotFormatImpl: Codeunit "LGS EL Lot Format Impl";
        MobToolbox: Codeunit "MOB Toolbox";
        MobXmlMgt: Codeunit "MOB XML Management";
        TempRequestValues: Record "MOB NS Request Element" temporary;
        MobRequestMgt: Codeunit "MOB NS Request Management";
        XmlResponseData: XmlNode;
        XmlStepUpdates: XmlNode;
        XmlStep: XmlNode;
        WorkCenterCode: Code[20];
        MachineCenterCode: Code[20];
        ItemNo: Code[20];
        LocationCode: Code[10];
        LastLotNo: Text;
        GeneratedLotNo: Code[50];
        LotNoText: Text;
        ProdOrderRtngLineRecordId: RecordId;
        ProdOrderRtngLine: Record "Prod. Order Routing Line";
    begin
        if _DocumentType <> 'ProdOutputWorkCenterValidation' then
            exit;

        // No order-type guard — the WorkCenter step is hidden for non-Production
        // orders, so this validation only fires when it should.
        _IsHandled := true;

        MobRequestMgt.SaveAdhocRequestValues(_XMLRequestDoc, TempRequestValues);
        WorkCenterCode := CopyStr(TempRequestValues.GetValue('WorkCenter'), 1, MaxStrLen(WorkCenterCode));
        ItemNo := CopyStr(TempRequestValues.GetValueOrContextValue('ItemNumber'), 1, MaxStrLen(ItemNo));
        LocationCode := CopyStr(TempRequestValues.GetValueOrContextValue('Location'), 1, MaxStrLen(LocationCode));

        // 'N/A' means no routing lines were available — treat as no work center.
        if WorkCenterCode = 'N/A' then
            WorkCenterCode := '';

        // Resolve Machine Center code from the routing line if applicable.
        if Evaluate(ProdOrderRtngLineRecordId, TempRequestValues.GetValueOrContextValue('ProdOrderRtngLine_RecordId')) then
            if ProdOrderRtngLine.Get(ProdOrderRtngLineRecordId) then
                if ProdOrderRtngLine.Type = ProdOrderRtngLine.Type::"Machine Center" then begin
                    MachineCenterCode := ProdOrderRtngLine."No.";
                    WorkCenterCode := ProdOrderRtngLine."Work Center No.";
                end;

        MobToolbox.InitializeResponseDoc(_XMLResponseDoc, XmlResponseData);

        // Only generate lot if item has a format code configured.
        if not Item.Get(ItemNo) then
            exit;
        if Item."LGS EL Lot No. Format Code" = '' then
            exit;
        if not LotFormatHeader.Get(Item."LGS EL Lot No. Format Code") then
            exit;

        // Resolve last lot number — mirrors GetLastLotNoFromItem in LGS source.
        LotNoInfo.SetRange("Item No.", ItemNo);
        if LotNoInfo.FindLast() then
            LastLotNo := LotNoInfo."Lot No."
        else begin
            ItemLedgerEntry.SetRange("Item No.", ItemNo);
            if LocationCode <> '' then
                ItemLedgerEntry.SetRange("Location Code", LocationCode);
            ItemLedgerEntry.SetFilter("Lot No.", '<>%1', '');
            if ItemLedgerEntry.FindLast() then
                LastLotNo := ItemLedgerEntry."Lot No.";
        end;

        // Generate lot number with full context including work center, machine center,
        // and the active shift derived from the work center's shop calendar.
        LotNoText := LotFormatImpl.GenerateLotNo(
            LotFormatHeader,
            LocationCode,
            Today(),
            GetShiftCodeForWorkCenter(WorkCenterCode),
            WorkCenterCode,
            MachineCenterCode,
            LastLotNo);

        GeneratedLotNo := CopyStr(LotNoText, 1, MaxStrLen(GeneratedLotNo));

        // Return the generated lot as a pre-filled editable step update.
        MobXmlMgt.AddElement(XmlResponseData, 'stepUpdates',
            '', 'http://schemas.taskletfactory.com/MobileWMS/WarehouseInquiryDataModel', XmlStepUpdates);

        MobXmlMgt.AddElement(XmlStepUpdates, 'step', '', '', XmlStep);
        MobXmlMgt.AddAttribute(XmlStep, 'name', 'LotNumber');
        MobXmlMgt.AddAttribute(XmlStep, 'value', GeneratedLotNo);
        MobXmlMgt.AddAttribute(XmlStep, 'interactionPermission',
            Format(Enum::"MOB ValueInteractionPermission"::AllowEdit));
    end;

    // =========================================================================
    // b.III  CONSUMPTION ORDER HEADER — BOM No. and Version Code
    //
    // Appends BOM No. and Version Code on new lines below the existing header
    // values in the Consume Items screen. Labels are left unchanged.
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Production Consumption", 'OnGetProdOrderLines_OnAfterSetFromProdOrderLine', '', true, true)]
    local procedure OnAfterSetFromProdOrderLineForConsumption(
        _ProdOrderLine: Record "Prod. Order Line";
        var _BaseOrderElement: Record "MOB NS BaseDataModel Element")
    var
        G2IRepackSession: Codeunit "G2I Repack Session";
        CrLf: Text;
    begin
        if G2IRepackSession.GetOrderType() <> 'Production' then
            exit;

        if _ProdOrderLine."Production BOM No." = '' then
            exit;

        CrLf[1] := 13;
        CrLf[2] := 10;

        _BaseOrderElement.Set_HeaderLabel1(_BaseOrderElement.Get_HeaderLabel1() + CrLf + _BaseOrderElement.Get_HeaderLabel2());
        _BaseOrderElement.Set_HeaderValue1(_BaseOrderElement.Get_HeaderValue1() + CrLf + _BaseOrderElement.Get_HeaderValue2());

        _BaseOrderElement.Set_HeaderLabel2('BOM');
        _BaseOrderElement.Set_HeaderValue2(_ProdOrderLine."Production BOM No.");

        if _ProdOrderLine."Production BOM Version Code" <> '' then begin
            _BaseOrderElement.Set_HeaderLabel2(_BaseOrderElement.Get_HeaderLabel2() + CrLf + 'Version');
            _BaseOrderElement.Set_HeaderValue2(_BaseOrderElement.Get_HeaderValue2() + CrLf + _ProdOrderLine."Production BOM Version Code");
        end;
    end;

    // =========================================================================
    // c.  CONSUMPTION STEPS
    //
    // c.I   Hide Picked Qty — SSM does not pick components before consumption.
    //        The ExtraInfo2 row showing Picked Qty / Expected Qty is cleared.
    //
    // c.II  Hide Scan Bin (Take) — all consumption is from the Production bin.
    //        ValidateFromBin is set to false so the bin scan step is suppressed.
    //
    // c.III Default Quantity to zero — the user must enter the consumed qty
    //        explicitly; the pre-filled remaining quantity is replaced with 0.
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Production Consumption", 'OnGetProdConsumptionLines_OnAfterSetFromProdOrderComponent', '', true, true)]
    local procedure OnAfterSetFromProdOrderComponent(
        _ProdOrderComponent: Record "Prod. Order Component";
        _TrackingSpecification: Record "Tracking Specification";
        var _BaseOrderLineElement: Record "MOB NS BaseDataModel Element")
    var
        G2IRepackSession: Codeunit "G2I Repack Session";
        Item: Record Item;
        RndPrecision: Decimal;
    begin
        if G2IRepackSession.GetOrderType() <> 'Production' then
            exit;

        // c.I: Clear the Picked Qty / Expected Qty ExtraInfo row.
        // Tasklet populates ExtraInfo2 with Picked Qty when the location requires
        // pick + shipment, or Expected Qty otherwise.  SSM does not use picking
        // for production components so we suppress this row entirely.
        _BaseOrderLineElement.SetValue('ExtraInfo2_Col1', '');
        _BaseOrderLineElement.SetValue('ExtraInfo2_Col2', '');

        // c.II: Suppress the From Bin scan step.
        // All consumption is done from the Production bin; the bin on the
        // Prod. Order Component is used by the standard posting path.
        _BaseOrderLineElement.Set_ValidateFromBin(false);

        // c.III: Reformat Quantity Per display row using Item."Rounding Precision".
        Item.Get(_ProdOrderComponent."Item No.");
        RndPrecision := Item."Rounding Precision";
        if RndPrecision <= 0 then
            RndPrecision := 0.00001;
        _BaseOrderLineElement.SetValue('ExtraInfo1_Col2',
            Format(Round(_ProdOrderComponent."Quantity per", RndPrecision))
            + ' ' + _ProdOrderComponent."Unit of Measure Code");
    end;

    // =========================================================================
    // a.II  HIDE LP SCAN STEP — LP is created automatically for Finished Goods
    //
    // The standard LP step (id 300) is added by MOB License Plate Prod Output
    // when the location has "MOB Prod. Output to LP" = Required or Optional.
    // We suppress it entirely via OnBeforeCheckLicensePlateHandlingInProdOutput
    // and instead create the LP automatically at post time if the item's
    // LGS Item Type = Finished Good.
    // =========================================================================
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB License Plate Prod Output", 'OnBeforeCheckLicensePlateHandlingInProdOutput', '', true, true)]
    local procedure OnBeforeCheckLPHandlingInProdOutput(
        _ProdOrderRoutingLine: Record "Prod. Order Routing Line";
        _LookupResponse: Record "MOB NS WhseInquery Element";
        _Steps: Record "MOB Steps Element";
        Location: Record Location;
        var IsHandled: Boolean)
    var
        G2IRepackSession: Codeunit "G2I Repack Session";
        OrderType: Text;
    begin
        OrderType := G2IRepackSession.GetOrderType();
        if (OrderType <> 'Production') and (OrderType <> 'Repack') then
            exit;

        // Suppress the standard LP scan step — LP is created automatically at post time.
        // Production: see OnAutoCreateProdOutputLP.  Repack: see OnAutoCreateRepackOutputLP.
        IsHandled := true;
    end;

    // =========================================================================
    // a.II.pre  SEED SESSION ORDER TYPE FOR GetRegistrationConfiguration
    //
    // When ProdOutputQuantity is opened from the action menu it runs in a new
    // BC session where G2IRepackSession is empty.  OnAfterSetFromProdOutput
    // persists the order type as G2I_OrderType on the element; here we read it
    // back from the transferred context and re-populate G2IRepackSession so
    // OnBeforeCheckLPHandlingInProdOutput (and other subscribers) work
    // correctly.  This fires before CreateStepsForProdOutputLicensePlate.
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Adhoc Registr.", 'OnGetRegistrationConfiguration_OnBeforeAddSteps', '', true, true)]
    local procedure OnBeforeAddProdOutputSteps_SeedOrderType(
        _RegistrationType: Text;
        var _HeaderFieldValues: Record "MOB NS Request Element";
        var _Steps: Record "MOB Steps Element";
        var _RegistrationTypeTracking: Text;
        var _IsHandled: Boolean)
    var
        TempLookupResponse: Record "MOB NS WhseInquery Element" temporary;
        G2IRepackSession: Codeunit "G2I Repack Session";
        OrderType: Text;
    begin
        if not _RegistrationType.StartsWith('ProdOutput') then
            exit;

        _HeaderFieldValues.Get_ContextValuesAsWhseInquiryElement(TempLookupResponse, true);
        OrderType := TempLookupResponse.GetValue('G2I_OrderType');
        if OrderType <> '' then
            G2IRepackSession.SetOrderType(OrderType);
    end;

    // =========================================================================
    // a.III AUTO-CREATE LP AT POST — Finished Good items only
    //
    // Fires after the production output journal line is created.
    // If the item's LGS Item Type = Finished Good, a new LP is created and
    // populated with the output item, quantity, lot, and pallet type.
    // All other item types (Intermediate, Raw Material, etc.) are skipped.
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Adhoc Registr.", 'OnPostAdhocRegistrationOnProdOutput_OnAfterCreateProductionJnlLine', '', true, true)]
    local procedure OnAutoCreateProdOutputLP(
        var _RequestValues: Record "MOB NS Request Element";
        var _ProductionJnlLine: Record "Item Journal Line")
    var
        Item: Record Item;
        G2ILicensePlateMgt: Codeunit "G2I License Plate Mgt";
        NewLP: Record "MOB License Plate";
        SourceContent: Record "MOB License Plate Content";
        PalletType: Code[20];
        ToBin: Code[20];
        LotNo: Code[50];
        G2IRepackSession: Codeunit "G2I Repack Session";
    begin
        if G2IRepackSession.GetOrderType() <> 'Production' then
            exit;

        // Only create LP for Finished Good items.
        if not Item.Get(_ProductionJnlLine."Item No.") then
            exit;
        if Item."LGS Item Type" <> Item."LGS Item Type"::"Finished Good" then
            exit;

        if _ProductionJnlLine."Output Quantity" <= 0 then
            exit;

        ToBin := CopyStr(_RequestValues.GetValueOrContextValue('ToBin'), 1, MaxStrLen(ToBin));
        LotNo := CopyStr(_RequestValues.GetValue('LotNumber'), 1, MaxStrLen(LotNo));
        PalletType := CopyStr(_RequestValues.GetValue('PalletType'), 1, MaxStrLen(PalletType));

        // Build content template.
        // Always store LP content in the item's base unit of measure (EA).
        // The journal line quantity may be in PALL; Output Quantity (Base)
        // is already converted to base units by BC.
        SourceContent.Init();
        SourceContent.Validate(Type, SourceContent.Type::Item);
        SourceContent.Validate("No.", _ProductionJnlLine."Item No.");
        SourceContent.Validate("Variant Code", _ProductionJnlLine."Variant Code");
        SourceContent.Validate("Unit Of Measure Code", Item."Base Unit of Measure");
        SourceContent.Validate("Location Code", _ProductionJnlLine."Location Code");
        SourceContent.Validate("Bin Code", ToBin);
        SourceContent.Validate("Lot No.", LotNo);

        // Create LP header.
        NewLP.Init();
        NewLP.Validate("No.", G2ILicensePlateMgt.GetNextLicensePlateNo());
        NewLP.Validate("Location Code", _ProductionJnlLine."Location Code");
        NewLP.Validate("Bin Code", ToBin);
        NewLP."LGS Pallet Type" := PalletType;
        NewLP.Validate("LGS LPS LP Status Code", 'Released');
        NewLP.Insert(true);

        // Add item content using base quantity (EA), not PALL quantity.
        G2ILicensePlateMgt.AddContentLine(NewLP, SourceContent, _ProductionJnlLine."Output Quantity (Base)");
    end;

    // =========================================================================
    // b.II  WRITE WORK CENTER TO OUTPUT JOURNAL LINE AT POST TIME
    //
    // Reads the WorkCenter code selected by the user and writes it to the
    // production output journal line before posting.
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Adhoc Registr.", 'OnPostAdhocRegistrationOnProdOutput_OnAfterCreateProductionJnlLine', '', true, true)]
    local procedure OnWriteWorkCenterToProdOutputJnlLine(
        var _RequestValues: Record "MOB NS Request Element";
        var _ProductionJnlLine: Record "Item Journal Line")
    var
        WorkCenter: Record "Work Center";
        MachineCenter: Record "Machine Center";
        WorkCenterCode: Code[20];
        G2IRepackSession: Codeunit "G2I Repack Session";
    begin
        if G2IRepackSession.GetOrderType() <> 'Production' then
            exit;

        WorkCenterCode := CopyStr(_RequestValues.GetValue('WorkCenter'), 1, MaxStrLen(WorkCenterCode));
        if (WorkCenterCode = '') or (WorkCenterCode = 'N/A') then
            exit;

        // Try Work Center first, then Machine Center.
        if WorkCenter.Get(WorkCenterCode) then begin
            _ProductionJnlLine.Validate("Work Center No.", WorkCenterCode);
            _ProductionJnlLine.Modify(true);
            exit;
        end;

        if MachineCenter.Get(WorkCenterCode) then begin
            _ProductionJnlLine.Validate("Work Center No.", MachineCenter."Work Center No.");
            _ProductionJnlLine.Modify(true);
        end;
    end;

    // =========================================================================
    // REFERENCE DATA — OrderType header field
    //
    // Adds a locked OrderType field (Production / Repack / Combo) to three
    // header configurations:
    //   ProdOrderLineFilters — the production order list
    //   ProdOutputHeader     — the output registration header
    //
    // The field value is read in the corresponding filter events (see below)
    // and written to G2I Repack Session so all subsequent subscribers know
    // which module is active for the current request chain.
    //
    // Consumption does not need its own header field: the order list filters
    // (including OrderType) are passed through to GetProdConsumptionLines by
    // the mobile app, so they are available in the consumption filter event.
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Reference Data", 'OnGetReferenceData_OnAddHeaderConfigurations', '', true, true)]
    local procedure OnAddOrderTypeHeaderField(var _HeaderFields: Record "MOB HeaderField Element")
    begin
        _HeaderFields.InitConfigurationKey_ProdOrderLineFilters();
        _HeaderFields.Create_ListField(60, 'OrderType', 'Order Type:');
        _HeaderFields.Set_listValues('Production;Repack;Combo');
        _HeaderFields.Set_defaultValue('Production');
        _HeaderFields.Set_locked(true);
        _HeaderFields.Save();

        _HeaderFields.InitConfigurationKey_ProdOutputHeader();
        _HeaderFields.Create_ListField(60, 'OrderType', 'Order Type:');
        _HeaderFields.Set_listValues('Production;Repack;Combo');
        _HeaderFields.Set_defaultValue('Production');
        _HeaderFields.Set_locked(true);
        _HeaderFields.Save();
    end;

    // Set order type when the output routing line lookup applies its filters.
    // This fires on every output registration request, so the session state is
    // always correct regardless of which BC service session handles the request.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Lookup", 'OnLookupOnProdOutput_OnSetFilterProdOrderRoutingLine', '', true, true)]
    local procedure OnSetOrderTypeForOutput(
        var _RequestValues: Record "MOB NS Request Element";
        var _ProdOrderRtngLine: Record "Prod. Order Routing Line")
    var
        G2IRepackSession: Codeunit "G2I Repack Session";
        OrderType: Text;
    begin
        OrderType := _RequestValues.GetValue('OrderType');
        if OrderType <> '' then
            G2IRepackSession.SetOrderType(OrderType);
    end;

    // Set order type when consumption lines are loaded.
    // The order list header filters (including OrderType) are forwarded by the
    // mobile app to GetProdConsumptionLines, so no separate header field is needed.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Production Consumption", 'OnGetProdConsumptionLines_OnSetFilterProdOrderComponent', '', true, true)]
    local procedure OnSetOrderTypeForConsumption(
        var _HeaderFilter: Record "MOB NS Request Element";
        var _ProdOrderComponent: Record "Prod. Order Component")
    var
        G2IRepackSession: Codeunit "G2I Repack Session";
        OrderType: Text;
    begin
        OrderType := _HeaderFilter.GetValue('OrderType');
        if OrderType <> '' then
            G2IRepackSession.SetOrderType(OrderType);
    end;

    // =========================================================================
    // DOCUMENT TYPE REGISTRATION
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Setup Doc. Types", 'OnAfterCreateDefaultDocumentTypes', '', true, true)]
    local procedure OnAfterCreateDefaultDocumentTypes()
    var
        MobWmsSetupDocTypes: Codeunit "MOB WMS Setup Doc. Types";
    begin
        MobWmsSetupDocTypes.CreateDocumentType('ProdOutputWorkCenterValidation', '', Codeunit::"MOB WMS Whse. Inquiry");
    end;

    // =========================================================================
    // SHIFT CODE HELPERS
    // =========================================================================

    // Returns the active shift code for a work center based on the work center's
    // shop calendar and the current time of day.  Returns '' when no shift matches
    // (e.g. outside scheduled hours) or when the work center has no calendar.
    local procedure GetShiftCodeForWorkCenter(_WorkCenterCode: Code[20]): Code[10]
    var
        WorkCenter: Record "Work Center";
    begin
        if _WorkCenterCode = '' then
            exit('');
        if not WorkCenter.Get(_WorkCenterCode) then
            exit('');
        exit(GetCurrentShiftFromCalendar(WorkCenter."Shop Calendar Code"));
    end;

    // Looks up the active shift in a shop calendar for the current day and time.
    // Handles overnight shifts where Ending Time < Starting Time.
    local procedure GetCurrentShiftFromCalendar(_ShopCalendarCode: Code[10]): Code[10]
    var
        ShopCalWorkingDay: Record "Shop Calendar Working Days";
        CurrentTime: Time;
        DayNo: Integer;
        InShift: Boolean;
    begin
        if _ShopCalendarCode = '' then
            exit('');
        CurrentTime := Time;
        DayNo := Date2DWY(Today, 1);

        ShopCalWorkingDay.SetRange("Shop Calendar Code", _ShopCalendarCode);
        ShopCalWorkingDay.SetRange(Day, DayNo);
        if ShopCalWorkingDay.FindSet() then
            repeat
                if ShopCalWorkingDay."Starting Time" < ShopCalWorkingDay."Ending Time" then
                    // Normal shift — start and end on same day.
                    InShift :=
                        (CurrentTime >= ShopCalWorkingDay."Starting Time") and
                        (CurrentTime < ShopCalWorkingDay."Ending Time")
                else
                    // Overnight shift — wraps past midnight.
                    InShift :=
                        (CurrentTime >= ShopCalWorkingDay."Starting Time") or
                        (CurrentTime < ShopCalWorkingDay."Ending Time");

                if InShift then
                    exit(ShopCalWorkingDay."Work Shift Code");
            until ShopCalWorkingDay.Next() = 0;
    end;
}
