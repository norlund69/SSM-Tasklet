codeunit 50152 "MOB WMS Pick G2I"
{
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Reference Data", 'OnGetReferenceData_OnAddHeaderConfigurations', '', true, true)]
    local procedure PickOnGetReferenceData_OnAddHeaderConfigurations(var _HeaderFields: Record "MOB HeaderField Element")
    var
        MobWmsLanguage: Codeunit "MOB WMS Language";
    begin
        _HeaderFields.InitConfigurationKey('PickOrderFilters');

        _HeaderFields.Create_TextField_ShipmentNoFilter(15);
        _HeaderFields.Set_label(MobWmsLanguage.GetMessage('SHIPMT_NO') + ':');
        _HeaderFields.Set_clearOnClear(true);
        _HeaderFields.Set_length(20);
        _HeaderFields.Set_optional(true);
        _HeaderFields.Set_acceptBarcode(true);

        _HeaderFields.Create_TextField(16, 'DeliveryTripFilter');
        _HeaderFields.Set_label('Delivery Trip:');
        _HeaderFields.Set_clearOnClear(true);
        _HeaderFields.Set_length(20);
        _HeaderFields.Set_optional(true);
        _HeaderFields.Set_acceptBarcode(true);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Reference Data", 'OnGetReferenceData_OnAfterAddHeaderField', '', true, true)]
    local procedure PickGetReferenceData_OnAfterAddHeaderField(var _HeaderField: Record "MOB HeaderField Element")
    begin
        if (_HeaderField.ConfigurationKey = 'PickOrderFilters') and (_HeaderField.Get_name() = 'AssignedUser') then
            _HeaderField.Set_visible(false);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Pick", 'OnGetPickOrders_OnSetFilterWarehouseActivity', '', true, true)]
    local procedure OnSetFilterWhseActivityForPick(_HeaderFilter: Record "MOB NS Request Element"; var _WhseActHeader: Record "Warehouse Activity Header"; var _WhseActLine: Record "Warehouse Activity Line"; var _IsHandled: Boolean)
    var
        ShipmentNoFilter: Code[20];
        DeliveryTripFilter: Text;
        SourceNoList: Text;
    begin
        if _IsHandled then
            exit;

        // Force "OnlyMine" regardless of what the client sent.
        // AssignedUser is hidden and preset to OnlyMine, but the client caches
        // the last accepted value per user and that cache wins over defaultValue.
        // SetRange here unconditionally overrides whatever Tasklet applied earlier.
        _WhseActHeader.SetRange("Assigned User ID", UserId());

        ShipmentNoFilter := _HeaderFilter.Get_ShipmentNoFilter();
        DeliveryTripFilter := _HeaderFilter.GetValue('DeliveryTripFilter');

        if (ShipmentNoFilter = '') and (DeliveryTripFilter = '') then
            exit;

        if ShipmentNoFilter <> '' then begin
            _WhseActLine.SetRange("Whse. Document Type", _WhseActLine."Whse. Document Type"::Shipment);
            _WhseActLine.SetFilter("Whse. Document No.", WildcardFilter(ShipmentNoFilter));
        end;

        if DeliveryTripFilter <> '' then begin
            // "LGS DT Delivery Trip No." lives on the source order, not the warehouse
            // documents, so collect matching Order Nos and filter by that list.
            SourceNoList := BuildSourceNoListForTrip(WildcardFilter(DeliveryTripFilter));

            // No matches → impossible value so the result is an empty list,
            // not an unfiltered list.
            if SourceNoList = '' then
                SourceNoList := '<<<NO_MATCH>>>';

            _WhseActLine.SetFilter("Source No.", SourceNoList);
        end;

        // Do NOT set _IsHandled — Tasklet still needs to apply its own filters.
    end;

    local procedure BuildSourceNoListForTrip(_TripFilter: Text) ResultList: Text
    var
        SalesHeader: Record "Sales Header";
        TransferHeader: Record "Transfer Header";
    begin
        SalesHeader.SetFilter("LGS DT Delivery Trip No.", _TripFilter);
        if SalesHeader.FindSet() then
            repeat
                AppendToList(ResultList, SalesHeader."No.");
            until SalesHeader.Next() = 0;

        TransferHeader.SetFilter("LGS DT Delivery Trip No.", _TripFilter);
        if TransferHeader.FindSet() then
            repeat
                AppendToList(ResultList, TransferHeader."No.");
            until TransferHeader.Next() = 0;
    end;

    // Wraps plain input as "*value*" for substring matching.
    // Inputs that already contain BC filter metacharacters pass through unchanged.
    local procedure WildcardFilter(_Input: Text) Result: Text
    begin
        Result := _Input.Trim();
        if Result = '' then
            exit('');
        if HasFilterMetachar(Result) then
            exit(Result);
        exit('*' + Result + '*');
    end;

    local procedure HasFilterMetachar(_Input: Text): Boolean
    begin
        exit(
            (StrPos(_Input, '*') > 0) or
            (StrPos(_Input, '?') > 0) or
            (StrPos(_Input, '|') > 0) or
            (StrPos(_Input, '&') > 0) or
            (StrPos(_Input, '..') > 0) or
            (StrPos(_Input, '<') > 0) or
            (StrPos(_Input, '>') > 0) or
            (StrPos(_Input, '=') > 0) or
            (StrPos(_Input, '@') > 0));
    end;

    local procedure AppendToList(var _List: Text; _Value: Code[20])
    begin
        if _Value = '' then
            exit;
        if _List = '' then
            _List := _Value
        else
            _List += '|' + _Value;
    end;

    local procedure GetDeliveryTripForLine(_WhseActLine: Record "Warehouse Activity Line") Trip: Text
    var
        SalesHeader: Record "Sales Header";
        TransferHeader: Record "Transfer Header";
    begin
        case _WhseActLine."Source Document" of
            _WhseActLine."Source Document"::"Sales Order":
                if SalesHeader.Get(SalesHeader."Document Type"::Order, _WhseActLine."Source No.") then
                    Trip := SalesHeader."LGS DT Delivery Trip No.";
            _WhseActLine."Source Document"::"Sales Return Order":
                if SalesHeader.Get(SalesHeader."Document Type"::"Return Order", _WhseActLine."Source No.") then
                    Trip := SalesHeader."LGS DT Delivery Trip No.";
            _WhseActLine."Source Document"::"Outbound Transfer":
                if TransferHeader.Get(_WhseActLine."Source No.") then
                    Trip := TransferHeader."LGS DT Delivery Trip No.";
        end;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Pick", 'OnGetPickOrderLines_OnAfterSetFromWarehouseActivityLine', '', true, true)]
    local procedure OnAfterSetPickLine_RemoveBinAndTote(_WhseActLineTake: Record "Warehouse Activity Line"; var _BaseOrderLineElement: Record "MOB NS BaseDataModel Element")
    var
        TripText: Text;
    begin
        _BaseOrderLineElement.Set_ValidateFromBin(false);
        _BaseOrderLineElement.Set_Destination('');

        TripText := GetDeliveryTripForLine(_WhseActLineTake);
        if TripText <> '' then
            _BaseOrderLineElement.Set_DisplayLine6('Trip: ' + TripText);

        if _WhseActLineTake."LGS Pallet Type" <> '' then
            _BaseOrderLineElement.Set_DisplayLine7('Pallet: ' + _WhseActLineTake."LGS Pallet Type");
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Pick", 'OnGetPickOrderLines_OnAddStepsToAnyLine', '', true, true)]
    local procedure OnAddStepsToPickLine_ModifyLicensePlateSteps(_RecRef: RecordRef; var _BaseOrderLineElement: Record "MOB NS BaseDataModel Element"; var _Steps: Record "MOB Steps Element")
    var
        WhseActLine: Record "Warehouse Activity Line";
    begin
        if _RecRef.Number() <> Database::"Warehouse Activity Line" then
            exit;
        _RecRef.SetTable(WhseActLine);

        if WhseActLine."Activity Type" <> WhseActLine."Activity Type"::Pick then
            exit;

        if not (WhseActLine."Whse. Document Type" in
                [WhseActLine."Whse. Document Type"::Shipment,
                    WhseActLine."Whse. Document Type"::Production]) then
            exit;

        _Steps.SetRange(ConfigurationKey, _Steps.ConfigurationKey);
        if _Steps.FindSet() then
            repeat
                case _Steps.Get_name() of
                    'FromLicensePlate':
                        begin
                            _Steps.Set_onlineValidation('LicensePlateValidation', true);
                            _Steps.Save();
                        end;
                end;
            until _Steps.Next() = 0;
    end;

    // "Transferred From License Plate" is set after handling so Tasklet's
    // OnAfterFindWhseActivLine (License Plate Mgt) skips this registration
    // and does not perform a second LP content update inside WhseActRegister.Run.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Pick", 'OnPostPickOrder_OnHandleRegistrationForWarehouseActivityLine', '', true, true)]
    local procedure OnPostPickLine_SplitLicensePlate(var _Registration: Record "MOB WMS Registration"; var _WarehouseActivityLine: Record "Warehouse Activity Line")
    var
        G2ILicensePlateMgt: Codeunit "G2I License Plate Mgt";
    begin
        // PLACE fires the same event — only the source LP matters here.
        if _WarehouseActivityLine."Action Type" <> _WarehouseActivityLine."Action Type"::Take then
            exit;

        G2ILicensePlateMgt.HandlePartialPickSplit(
            _Registration."From License Plate No.",
            _WarehouseActivityLine."Item No.",
            _WarehouseActivityLine."Variant Code",
            _Registration.LotNumber,
            _Registration.Quantity,
            _WarehouseActivityLine."LGS Pallet Type",
            _WarehouseActivityLine."Whse. Document Type",
            _WarehouseActivityLine."Whse. Document No.");

        if _Registration."From License Plate No." <> '' then
            _Registration."Transferred From License Plate" := true;
    end;

    // Uses the AsXml variant because two sibling <step> nodes (LotNumber and
    // Quantity) are needed under one <stepUpdates> response — the standard buffer
    // API uses path as the record key and cannot produce two siblings.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Whse. Inquiry", 'OnWhseInquiryOnCustomDocumentTypeAsXml', '', true, true)]
    local procedure OnLicensePlateValidation(
        var _XMLRequestDoc: XmlDocument;
        var _XMLResponseDoc: XmlDocument;
        _DocumentType: Text;
        var _RegistrationTypeTracking: Text[200];
        var _IsHandled: Boolean)
    var
        WhseActLine: Record "Warehouse Activity Line";
        LicensePlate: Record "MOB License Plate";
        LPContent: Record "MOB License Plate Content";
        LotNoInfo: Record "Lot No. Information";
        LotStatus: Record "LGS LS Lot Status";
        LPStatus: Record "LGS LPS License Plate Status";
        G2ILicensePlateMgt: Codeunit "G2I License Plate Mgt";
        MobToolbox: Codeunit "MOB Toolbox";
        MobXmlMgt: Codeunit "MOB XML Management";
        MobRequestMgt: Codeunit "MOB NS Request Management";
        TempRequestValues: Record "MOB NS Request Element" temporary;
        XmlResponseData: XmlNode;
        XmlStepUpdates: XmlNode;
        XmlStep: XmlNode;
        LicensePlateNo: Code[20];
        LotNo: Code[50];
        BackendId: Code[20];
        Count: Integer;
        ErrorMsg: Text;
    begin
        if _DocumentType <> 'LicensePlateValidation' then
            exit;

        _IsHandled := true;

        MobRequestMgt.SaveAdhocRequestValues(_XMLRequestDoc, TempRequestValues);

        LicensePlateNo := CopyStr(TempRequestValues.GetValue('FromLicensePlate'), 1, MaxStrLen(LicensePlateNo));

        if not LicensePlate.Get(LicensePlateNo) then
            Error('License Plate %1 does not exist.', LicensePlateNo);

        if LicensePlate."Whse. Document Type" <> LicensePlate."Whse. Document Type"::" " then
            Error('You cannot pick from License Plate %1 because it is linked to %2 %3.',
                LicensePlateNo, LicensePlate."Whse. Document Type", LicensePlate."Whse. Document No.");

        BackendId := CopyStr(TempRequestValues.GetValue('backendId'), 1, MaxStrLen(BackendId));

        WhseActLine.Get(WhseActLine."Activity Type"::Pick, BackendId, TempRequestValues.Get_LineNumberAsInteger());

        G2ILicensePlateMgt.ValidateLicensePlateHasItem(
            LicensePlateNo,
            WhseActLine."Item No.",
            WhseActLine."Variant Code");

        if (WhseActLine."LGS Pallet Type" <> '') and
           (LicensePlate."LGS Pallet Type" <> WhseActLine."LGS Pallet Type")
        then
            Error('License Plate %1 has pallet type %2, but pick requires %3.',
                LicensePlateNo, LicensePlate."LGS Pallet Type", WhseActLine."LGS Pallet Type");

        if LicensePlate."LGS LPS LP Status Code" = '' then
            Error('License Plate %1 has no status set and cannot be picked.', LicensePlateNo);
        if not LPStatus.Get(LicensePlate."LGS LPS LP Status Code") then
            Error('License Plate %1 has unknown status ''%2''.',
                LicensePlateNo, LicensePlate."LGS LPS LP Status Code");
        case WhseActLine."Source Document" of
            WhseActLine."Source Document"::"Sales Order":
                if not LPStatus."Available for Sale" then
                    Error('License Plate %1 (status ''%2'') is not available for sale.',
                        LicensePlateNo, LPStatus.Code);
            WhseActLine."Source Document"::"Outbound Transfer":
                if not LPStatus."Available for Transfer" then
                    Error('License Plate %1 (status ''%2'') is not available for transfer.',
                        LicensePlateNo, LPStatus.Code);
            WhseActLine."Source Document"::"Prod. Consumption":
                if not LPStatus."Available for Consumption" then
                    Error('License Plate %1 (status ''%2'') is not available for consumption.',
                        LicensePlateNo, LPStatus.Code);
        end;

        // All lot-tracked content lines on this LP must be available for the pick action.
        LPContent.SetRange("License Plate No.", LicensePlateNo);
        LPContent.SetRange(Type, LPContent.Type::Item);
        LPContent.SetRange("No.", WhseActLine."Item No.");
        LPContent.SetFilter("Lot No.", '<>%1', '');
        if LPContent.FindSet() then
            repeat
                if not LotNoInfo.Get(LPContent."No.", LPContent."Variant Code", LPContent."Lot No.") or
                   (LotNoInfo."LGS LS Lot Status Code" = '')
                then
                    Error('Lot %1 has no lot status set and cannot be picked.', LPContent."Lot No.");

                if not LotStatus.Get(LotNoInfo."LGS LS Lot Status Code") then
                    Error('Lot %1 has unknown lot status ''%2''.',
                        LPContent."Lot No.", LotNoInfo."LGS LS Lot Status Code");

                case WhseActLine."Source Document" of
                    WhseActLine."Source Document"::"Sales Order":
                        if not LotStatus."Available for Sale" then
                            Error('Lot %1 (status ''%2'') is not available for sale.',
                                LPContent."Lot No.", LotStatus.Code);
                    WhseActLine."Source Document"::"Outbound Transfer":
                        if not LotStatus."Available for Transfer" then
                            Error('Lot %1 (status ''%2'') is not available for transfer.',
                                LPContent."Lot No.", LotStatus.Code);
                    WhseActLine."Source Document"::"Prod. Consumption":
                        if not LotStatus."Available for Consumption" then
                            Error('Lot %1 (status ''%2'') is not available for consumption.',
                                LPContent."Lot No.", LotStatus.Code);
                end;
            until LPContent.Next() = 0;

        if not CanPickEntireLicensePlate(LicensePlate, BackendId) then
            Error('License Plate %1 cannot be fully picked from this pick order. Only full license plate picks are allowed.', LicensePlateNo);

        // LP quantity must not exceed the outstanding quantity on this line.
        // (Partial-split code remains in the post handler for future use.)
        ErrorMsg := CheckLPQtyForOrderLines(LicensePlate, BackendId, TempRequestValues.Get_LineNumberAsInteger());
        if ErrorMsg <> '' then
            Error(ErrorMsg);

        LotNo := G2ILicensePlateMgt.GetSingleLotFromLicensePlate(
            LicensePlateNo,
            WhseActLine."Item No.",
            WhseActLine."Variant Code");

        LPContent.SetRange("License Plate No.", LicensePlateNo);
        LPContent.SetRange(Type, LPContent.Type::Item);
        LPContent.SetRange("No.", WhseActLine."Item No.");
        if WhseActLine."Variant Code" <> '' then
            LPContent.SetRange("Variant Code", WhseActLine."Variant Code");
        if LotNo <> '' then
            LPContent.SetRange("Lot No.", LotNo);

        MobToolbox.InitializeResponseDoc(_XMLResponseDoc, XmlResponseData);

        if not LPContent.FindFirst() then
            exit;  // No content found — return OK, let standard flow handle it.

        MobXmlMgt.AddElement(XmlResponseData, 'stepUpdates',
            '', 'http://schemas.taskletfactory.com/MobileWMS/WarehouseInquiryDataModel', XmlStepUpdates);

        if LotNo <> '' then begin
            MobXmlMgt.AddElement(XmlStepUpdates, 'step', '', '', XmlStep);
            MobXmlMgt.AddAttribute(XmlStep, 'name', 'LotNumber');
            MobXmlMgt.AddAttribute(XmlStep, 'value', LotNo);
            MobXmlMgt.AddAttribute(XmlStep, 'interactionPermission',
                Format(Enum::"MOB ValueInteractionPermission"::ApplyDirectly));
        end;

        if WhseActLine.Quantity > LPContent.Quantity then begin
            MobXmlMgt.AddElement(XmlStepUpdates, 'step', '', '', XmlStep);
            MobXmlMgt.AddAttribute(XmlStep, 'name', 'Quantity');
            MobXmlMgt.AddAttribute(XmlStep, 'value',
                Format(LPContent.Quantity, 0, '<Precision,0:5><Standard Format,0>'));
            MobXmlMgt.AddAttribute(XmlStep, 'interactionPermission',
                Format(Enum::"MOB ValueInteractionPermission"::VerifyOnly));
        end;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Whse. Inquiry", 'OnWhseInquiryOnCustomDocumentTypeAsXml', '', true, true)]
    local procedure OnValidateLPFromOrderLines(
        var _XMLRequestDoc: XmlDocument;
        var _XMLResponseDoc: XmlDocument;
        _DocumentType: Text;
        var _RegistrationTypeTracking: Text[200];
        var _IsHandled: Boolean)
    var
        LicensePlate: Record "MOB License Plate";
        LPContent: Record "MOB License Plate Content";
        MobRequestMgt: Codeunit "MOB NS Request Management";
        TempRequestValues: Record "MOB NS Request Element" temporary;
        LicensePlateNo: Code[20];
        BackendId: Code[20];
        ErrorMsg: Text;
    begin
        if _DocumentType <> 'GetLicensePlateContentToPick' then
            exit;

        MobRequestMgt.SaveAdhocRequestValues(_XMLRequestDoc, TempRequestValues);
        LicensePlateNo := CopyStr(TempRequestValues.GetValue('scannedValue'), 1, MaxStrLen(LicensePlateNo));
        BackendId := CopyStr(TempRequestValues.Get_BackendID(), 1, MaxStrLen(BackendId));

        if not LicensePlate.Get(LicensePlateNo) then
            exit; // let Tasklet show its own LP_NOT_FOUND error

        LPContent.SetRange("License Plate No.", LicensePlateNo);
        LPContent.SetRange(Type, LPContent.Type::Item);
        if LPContent.IsEmpty() then
            Error('License Plate %1 has no items and cannot be picked.', LicensePlateNo);

        ErrorMsg := CheckLPStatusForOrderLines(LicensePlate, BackendId);
        if ErrorMsg <> '' then
            Error(ErrorMsg);

        ErrorMsg := CheckLotStatusForOrderLines(LicensePlate, BackendId);
        if ErrorMsg <> '' then
            Error(ErrorMsg);

        if not CanPickEntireLicensePlate(LicensePlate, BackendId) then
            Error('License Plate %1 cannot be fully picked from this pick order. Only full license plate picks are allowed.', LicensePlateNo);

        ErrorMsg := CheckLPQtyForOrderLines(LicensePlate, BackendId, 0);
        if ErrorMsg <> '' then
            Error(ErrorMsg);
    end;

    // _LineNo = 0 : check all TAKE lines in the order (order-lines flow).
    // _LineNo > 0 : check only the specific line and only its item/variant (per-line flow).
    local procedure CheckLPQtyForOrderLines(_LicensePlate: Record "MOB License Plate"; _BackendId: Code[20]; _LineNo: Integer) ErrorMsg: Text
    var
        LPContent: Record "MOB License Plate Content";
        LPContent2: Record "MOB License Plate Content";
        WhseActLine: Record "Warehouse Activity Line";
        LPQty: Decimal;
        LineQty: Decimal;
    begin
        LPContent.SetRange("License Plate No.", _LicensePlate."No.");
        LPContent.SetRange(Type, LPContent.Type::Item);
        if _LineNo > 0 then begin
            WhseActLine.Get(WhseActLine."Activity Type"::Pick, _BackendId, _LineNo);
            LPContent.SetRange("No.", WhseActLine."Item No.");
            if WhseActLine."Variant Code" <> '' then
                LPContent.SetRange("Variant Code", WhseActLine."Variant Code");
        end;
        if not LPContent.FindSet() then
            exit('');

        repeat
            LPContent2.SetRange("License Plate No.", _LicensePlate."No.");
            LPContent2.SetRange(Type, LPContent2.Type::Item);
            LPContent2.SetRange("No.", LPContent."No.");
            LPContent2.SetRange("Variant Code", LPContent."Variant Code");
            LPContent2.CalcSums(Quantity);
            LPQty := LPContent2.Quantity;

            WhseActLine.SetRange("Activity Type", WhseActLine."Activity Type"::Pick);
            WhseActLine.SetRange("No.", _BackendId);
            WhseActLine.SetRange("Action Type", WhseActLine."Action Type"::Take);
            WhseActLine.SetRange("Item No.", LPContent."No.");
            WhseActLine.SetRange("Variant Code", LPContent."Variant Code");
            if _LineNo > 0 then
                WhseActLine.SetRange("Line No.", _LineNo);
            WhseActLine.CalcSums("Qty. Outstanding");
            LineQty := WhseActLine."Qty. Outstanding";

            if LPQty > LineQty then
                exit(StrSubstNo(
                    'License Plate %1 contains %2 %3 but only %4 remains on the pick line. Partial picks are not allowed.',
                    _LicensePlate."No.",
                    Format(LPQty, 0, '<Precision,0:5><Standard Format,0>'),
                    LPContent."Unit Of Measure Code",
                    Format(LineQty, 0, '<Precision,0:5><Standard Format,0>')));
        until LPContent.Next() = 0;
    end;

    local procedure CheckLPStatusForOrderLines(_LicensePlate: Record "MOB License Plate"; _BackendId: Code[20]) ErrorMsg: Text
    var
        WhseActLine: Record "Warehouse Activity Line";
        LPStatus: Record "LGS LPS License Plate Status";
    begin
        if _LicensePlate."LGS LPS LP Status Code" = '' then
            exit(StrSubstNo('License Plate %1 has no status set and cannot be picked.', _LicensePlate."No."));
        if not LPStatus.Get(_LicensePlate."LGS LPS LP Status Code") then
            exit(StrSubstNo('License Plate %1 has unknown status ''%2''.', _LicensePlate."No.", _LicensePlate."LGS LPS LP Status Code"));

        WhseActLine.SetRange("Activity Type", WhseActLine."Activity Type"::Pick);
        WhseActLine.SetRange("No.", _BackendId);
        WhseActLine.SetRange("Action Type", WhseActLine."Action Type"::Take);
        if not WhseActLine.FindFirst() then
            exit('');

        case WhseActLine."Source Document" of
            WhseActLine."Source Document"::"Sales Order":
                if not LPStatus."Available for Sale" then
                    exit(StrSubstNo('License Plate %1 (status ''%2'') is not available for sale.', _LicensePlate."No.", LPStatus.Code));
            WhseActLine."Source Document"::"Outbound Transfer":
                if not LPStatus."Available for Transfer" then
                    exit(StrSubstNo('License Plate %1 (status ''%2'') is not available for transfer.', _LicensePlate."No.", LPStatus.Code));
            WhseActLine."Source Document"::"Prod. Consumption":
                if not LPStatus."Available for Consumption" then
                    exit(StrSubstNo('License Plate %1 (status ''%2'') is not available for consumption.', _LicensePlate."No.", LPStatus.Code));
        end;
    end;

    local procedure CheckLotStatusForOrderLines(_LicensePlate: Record "MOB License Plate"; _BackendId: Code[20]) ErrorMsg: Text
    var
        LPContent: Record "MOB License Plate Content";
        LotNoInfo: Record "Lot No. Information";
        LotStatus: Record "LGS LS Lot Status";
        WhseActLine: Record "Warehouse Activity Line";
        SourceDocument: Enum "Warehouse Activity Source Document";
    begin
        WhseActLine.SetRange("Activity Type", WhseActLine."Activity Type"::Pick);
        WhseActLine.SetRange("No.", _BackendId);
        WhseActLine.SetRange("Action Type", WhseActLine."Action Type"::Take);
        if not WhseActLine.FindFirst() then
            exit('');
        SourceDocument := WhseActLine."Source Document";

        LPContent.SetRange("License Plate No.", _LicensePlate."No.");
        LPContent.SetRange(Type, LPContent.Type::Item);
        LPContent.SetFilter("Lot No.", '<>%1', '');
        if not LPContent.FindSet() then
            exit('');

        repeat
            if not LotNoInfo.Get(LPContent."No.", LPContent."Variant Code", LPContent."Lot No.") or
               (LotNoInfo."LGS LS Lot Status Code" = '')
            then
                exit(StrSubstNo('Lot %1 has no lot status set and cannot be picked.', LPContent."Lot No."));

            if not LotStatus.Get(LotNoInfo."LGS LS Lot Status Code") then
                exit(StrSubstNo('Lot %1 has unknown lot status ''%2''.', LPContent."Lot No.", LotNoInfo."LGS LS Lot Status Code"));

            case SourceDocument of
                WhseActLine."Source Document"::"Sales Order":
                    if not LotStatus."Available for Sale" then
                        exit(StrSubstNo('Lot %1 (status ''%2'') is not available for sale.', LPContent."Lot No.", LotStatus.Code));
                WhseActLine."Source Document"::"Outbound Transfer":
                    if not LotStatus."Available for Transfer" then
                        exit(StrSubstNo('Lot %1 (status ''%2'') is not available for transfer.', LPContent."Lot No.", LotStatus.Code));
                WhseActLine."Source Document"::"Prod. Consumption":
                    if not LotStatus."Available for Consumption" then
                        exit(StrSubstNo('Lot %1 (status ''%2'') is not available for consumption.', LPContent."Lot No.", LotStatus.Code));
            end;
        until LPContent.Next() = 0;
    end;

    local procedure CanPickEntireLicensePlate(_LicensePlate: Record "MOB License Plate"; _BackendId: Code[20]): Boolean
    var
        LPContent: Record "MOB License Plate Content";
        WhseActLine: Record "Warehouse Activity Line";
        WhseLineRemainingQty: Dictionary of [Integer, Decimal];
        RemainingLPQty: Decimal;
    begin
        LPContent.SetRange("License Plate No.", _LicensePlate."No.");
        LPContent.SetRange(Type, LPContent.Type::Item);
        if not LPContent.FindSet() then
            exit(true); // no content — nothing to block

        repeat
            RemainingLPQty := LPContent.Quantity;

            // First pass: lines with matching lot
            if LPContent."Lot No." <> '' then begin
                SetWhseActLineFiltersForLP(WhseActLine, _BackendId, LPContent);
                WhseActLine.SetRange("Lot No.", LPContent."Lot No.");
                AllocateToWhseLines(WhseActLine, WhseLineRemainingQty, RemainingLPQty);
            end;

            // Second pass: lines without lot specified
            if RemainingLPQty > 0 then begin
                SetWhseActLineFiltersForLP(WhseActLine, _BackendId, LPContent);
                WhseActLine.SetRange("Lot No.", '');
                AllocateToWhseLines(WhseActLine, WhseLineRemainingQty, RemainingLPQty);
            end;

            if RemainingLPQty > 0 then
                exit(false);
        until LPContent.Next() = 0;

        exit(true);
    end;

    local procedure SetWhseActLineFiltersForLP(var _WhseActLine: Record "Warehouse Activity Line"; _BackendId: Code[20]; _LPContent: Record "MOB License Plate Content")
    begin
        _WhseActLine.Reset();
        _WhseActLine.SetRange("Activity Type", _WhseActLine."Activity Type"::Pick);
        _WhseActLine.SetRange("No.", _BackendId);
        _WhseActLine.SetRange("Action Type", _WhseActLine."Action Type"::Take);
        _WhseActLine.SetRange("Item No.", _LPContent."No.");
        _WhseActLine.SetRange("Variant Code", _LPContent."Variant Code");
        _WhseActLine.SetRange("Unit of Measure Code", _LPContent."Unit Of Measure Code");
        _WhseActLine.SetFilter("Qty. Outstanding", '>0');
    end;

    local procedure AllocateToWhseLines(var _WhseActLine: Record "Warehouse Activity Line"; var _Dict: Dictionary of [Integer, Decimal]; var _RemainingLPQty: Decimal)
    var
        RemainingWhseQty: Decimal;
    begin
        if not _WhseActLine.FindSet() then
            exit;
        repeat
            if _RemainingLPQty <= 0 then
                exit;
            if not _Dict.ContainsKey(_WhseActLine."Line No.") then
                _Dict.Add(_WhseActLine."Line No.", _WhseActLine."Qty. Outstanding");
            RemainingWhseQty := _Dict.Get(_WhseActLine."Line No.");
            if RemainingWhseQty > 0 then
                if _RemainingLPQty >= RemainingWhseQty then begin
                    _RemainingLPQty -= RemainingWhseQty;
                    _Dict.Set(_WhseActLine."Line No.", 0);
                end else begin
                    _Dict.Set(_WhseActLine."Line No.", RemainingWhseQty - _RemainingLPQty);
                    _RemainingLPQty := 0;
                end;
        until _WhseActLine.Next() = 0;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Pick", 'OnPostPickOrder_OnAfterPostAnyOrder', '', true, true)]
    local procedure OnAfterPostPickOrder(var _OrderValues: Record "MOB Common Element"; var _RecRef: RecordRef; var _ResultMessage: Text)
    var
        G2IPickSession: Codeunit "G2I Pick Session";
        ResultLines: Text;
        CrLf: Text[2];
    begin
        ResultLines := G2IPickSession.GetResultLines();
        G2IPickSession.Clear();

        if ResultLines = '' then
            exit;

        CrLf[1] := 13;
        CrLf[2] := 10;
        _ResultMessage := 'Order posted successfully.' + CrLf + ResultLines;
    end;

    // OnAfterCreateDefaultDocumentTypes ensures registrations survive re-install and upgrade.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Setup Doc. Types", 'OnAfterCreateDefaultDocumentTypes', '', true, true)]
    local procedure OnAfterCreateDefaultDocumentTypes()
    var
        MobWmsSetupDocTypes: Codeunit "MOB WMS Setup Doc. Types";
    begin
        MobWmsSetupDocTypes.CreateDocumentType('LicensePlateValidation', '', Codeunit::"MOB WMS Whse. Inquiry");
    end;

}
