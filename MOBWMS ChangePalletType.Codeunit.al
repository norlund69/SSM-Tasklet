codeunit 50151 "MOB WMS Change Pallet Type"
{
    // ---------------------------------------------------------------------
    // Scanner function: Change Pallet Type on a License Plate
    //
    // Flow on the scanner:
    //   1) Header  : pick Location, scan License Plate (filtered by location)
    //   2) Step 1  : Information step - shows LP No., current Pallet Type,
    //                Lot Number(s) and the items on the LP (item no.,
    //                description, quantity). First 2 lines are shown; if
    //                more exist, a "..." line with the overflow count.
    //   3) Step 2  : List step - pick the new Pallet Type
    //   4) Post    : Validate and update "LGS Pallet Type" on the LP
    // ---------------------------------------------------------------------

    // ---------- 1) Header configuration ----------
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Reference Data", 'OnGetReferenceData_OnAddHeaderConfigurations', '', true, true)]
    local procedure OnAddHeaderConfigurations(var _HeaderFields: Record "MOB HeaderField Element")
    var
        MobWmsLanguage: Codeunit "MOB WMS Language";
    begin
        // ConfigurationKey - must match cfg + install codeunit
        _HeaderFields.InitConfigurationKey('ChangePalletType');

        // ---- Field 1: Location ----
        _HeaderFields.Create_ListField_FilterLocationAsLocation(10);
        _HeaderFields.Set_label(MobWmsLanguage.GetMessage('LOCATION') + ':');
        _HeaderFields.Set_clearOnClear(true);
        _HeaderFields.Set_optional(false);

        // ---- Field 2: License Plate ----
        _HeaderFields.Create_TextField_LicensePlate(20);
        _HeaderFields.Set_label(MobWmsLanguage.GetMessage('LICENSEPLATE') + ':');
        _HeaderFields.Set_clearOnClear(true);
        _HeaderFields.Set_length(50);
        _HeaderFields.Set_acceptBarcode(true);
        _HeaderFields.Set_eanAi('00,01,02,91,98');
        //_HeaderFields.Set_searchType('LicensePlateSearch');
    end;

    // ---------- 2) Steps after header is accepted ----------
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Adhoc Registr.", 'OnGetRegistrationConfiguration_OnAddSteps', '', true, true)]
    local procedure OnAddSteps(_RegistrationType: Text; var _HeaderFieldValues: Record "MOB NS Request Element"; var _Steps: Record "MOB Steps Element"; var _RegistrationTypeTracking: Text)
    var
        LicensePlate: Record "MOB License Plate";
        LP: Code[20];
        LocationCode: Code[10];
        InfoText: Text;
    begin
        if _RegistrationType <> 'ChangePalletType' then
            exit;

        LocationCode := CopyStr(_HeaderFieldValues.Get_Location(false), 1, MaxStrLen(LocationCode));
        LP := _HeaderFieldValues.Get_LicensePlate();

        if not LicensePlate.Get(LP) then
            Error('License Plate %1 does not exist.', LP);

        // Defensive: header filter should already enforce this.
        if (LocationCode <> '') and (LicensePlate."Location Code" <> LocationCode) then
            Error('License Plate %1 is in location %2, not %3.', LP, LicensePlate."Location Code", LocationCode);

        // ---- Step 1: Information step - LP details ----
        // Create_InformationStep(_Id, _Name, _Header). The Header is the
        // body text shown to the user; embed newlines for multi-line.
        /*InfoText := BuildInfoText(LicensePlate);
        _Steps.Create_InformationStep(10, 'LPDetails', InfoText);
        _Steps.Set_header('License Plate Details');*/

        // ---- Step 2: New Pallet Type list ----
        _Steps.Create_ListStep(20, 'NewPalletType');
        _Steps.Set_header('New Pallet Type:');
        _Steps.Set_helpLabel('Select the new pallet type for License Plate ' + LP);
        _Steps.Set_optional(false);
        _Steps.Set_listValues(GetPalletTypeList(LicensePlate."LGS Pallet Type"));

        _RegistrationTypeTracking := StrSubstNo('ChangePalletType: %1 (current: %2)', LP, LicensePlate."LGS Pallet Type");
    end;

    // ---------- 3) Post ----------
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS Adhoc Registr.", 'OnPostAdhocRegistrationOnCustomRegistrationType', '', true, true)]
    local procedure OnPostChangePalletType(_RegistrationType: Text; var _RequestValues: Record "MOB NS Request Element"; var _SuccessMessage: Text; var _RegistrationTypeTracking: Text; var _IsHandled: Boolean)
    var
        LicensePlate: Record "MOB License Plate";
        PalletItem: Record Item;
        LP: Code[20];
        OldPalletType: Code[20];
        NewPalletType: Code[20];
    begin
        if _RegistrationType <> 'ChangePalletType' then
            exit;
        if _IsHandled then
            exit;

        LP := _RequestValues.Get_LicensePlate();
        NewPalletType := CopyStr(_RequestValues.GetValue('NewPalletType'), 1, MaxStrLen(NewPalletType));

        if not LicensePlate.Get(LP) then
            Error('License Plate %1 does not exist.', LP);

        OldPalletType := LicensePlate."LGS Pallet Type";

        if NewPalletType = '' then
            Error('A pallet type must be selected.');

        // The new pallet type must be an Item flagged as Pallet
        PalletItem.SetRange("No.", NewPalletType);
        PalletItem.SetRange("LGS Item Type", PalletItem."LGS Item Type"::Pallet);
        if not PalletItem.FindFirst() then
            Error('Item %1 is not a valid Pallet Type.', NewPalletType);

        if OldPalletType = NewPalletType then begin
            _SuccessMessage := StrSubstNo('LP %1 already has Pallet Type %2', LP, NewPalletType);
            _RegistrationTypeTracking := StrSubstNo('ChangePalletType: %1 unchanged (%2)', LP, NewPalletType);
            _IsHandled := true;
            exit;
        end;

        LicensePlate.Validate("LGS Pallet Type", NewPalletType);
        LicensePlate.Modify(true);

        _SuccessMessage := StrSubstNo('Pallet Type changed: %1 -> %2', OldPalletType, NewPalletType);
        _RegistrationTypeTracking := StrSubstNo('ChangePalletType: LP %1 from %2 to %3', LP, OldPalletType, NewPalletType);
        _IsHandled := true;
    end;

    // =====================================================================
    // Helpers
    // =====================================================================

    // Builds the multi-line text shown in the information step:
    //   LP: <no>
    //   Pallet Type: <code>
    //   Location: <loc>   Bin: <bin>
    //   Lot: <lot1, lot2, ...>
    //   <item1 line>
    //   <item2 line>
    //   ... (+N more)
    local procedure BuildInfoText(_LicensePlate: Record "MOB License Plate") Result: Text
    var
        CurrentPalletType: Text;
        NL: Text[2];
    begin
        NL[1] := 13;  // CR
        NL[2] := 10;  // LF

        if _LicensePlate."LGS Pallet Type" <> '' then
            CurrentPalletType := _LicensePlate."LGS Pallet Type"
        else
            CurrentPalletType := '<none>';

        Result :=
            StrSubstNo('LP: %1', _LicensePlate."No.") + NL +
            StrSubstNo('Pallet Type: %1', CurrentPalletType) + NL +
            StrSubstNo('Location: %1   Bin: %2', _LicensePlate."Location Code", _LicensePlate."Bin Code") + NL +
            GetLotSummary(_LicensePlate."No.") + NL +
            BuildContentLines(_LicensePlate."No.");
    end;

    // First 2 item lines on the LP, separated by newlines.
    // If more lines exist, append "... (+N more)".
    local procedure BuildContentLines(_LP: Code[20]) Result: Text
    var
        LPContent: Record "MOB License Plate Content";
        Item: Record Item;
        Total: Integer;
        Shown: Integer;
        Line: Text;
        QtyText: Text;
        UoM: Text;
        NL: Text[2];
    begin
        NL[1] := 13;
        NL[2] := 10;

        LPContent.SetRange("License Plate No.", _LP);
        LPContent.SetRange(Type, LPContent.Type::Item);
        if not LPContent.FindSet() then
            exit('No items on License Plate');

        Total := 0;
        Shown := 0;
        repeat
            Total += 1;
            if Shown < 2 then begin
                Shown += 1;
                QtyText := Format(LPContent.Quantity, 0, '<Precision,0:5><Standard Format,0>');
                UoM := LPContent."Unit Of Measure Code";
                if Item.Get(LPContent."No.") then
                    Line := StrSubstNo('%1 %2 - %3 %4',
                        LPContent."No.",
                        CopyStr(Item.Description, 1, 22),
                        QtyText,
                        UoM)
                else
                    Line := StrSubstNo('%1 - %2 %3', LPContent."No.", QtyText, UoM);
                if Result = '' then
                    Result := Line
                else
                    Result += NL + Line;
            end;
        until LPContent.Next() = 0;

        if Total > Shown then
            Result += NL + StrSubstNo('... (+%1 more)', Total - Shown);
    end;

    // "Lot: x, y, z" - unique lots present on the LP, or "Lot: <none>".
    local procedure GetLotSummary(_LP: Code[20]) Summary: Text
    var
        LPContent: Record "MOB License Plate Content";
        SeenLots: Text;
        ThisLot: Text;
    begin
        LPContent.SetRange("License Plate No.", _LP);
        LPContent.SetFilter("Lot No.", '<>%1', '');
        if LPContent.FindSet() then
            repeat
                ThisLot := LPContent."Lot No.";
                if StrPos(';' + SeenLots + ';', ';' + ThisLot + ';') = 0 then begin
                    if SeenLots = '' then
                        SeenLots := ThisLot
                    else
                        SeenLots += ', ' + ThisLot;
                end;
            until LPContent.Next() = 0;

        if SeenLots = '' then
            Summary := 'Lot: <none>'
        else
            Summary := 'Lot: ' + SeenLots;
    end;

    // Semicolon-separated list of pallet items: current first, then the rest, then a blank.
    local procedure GetPalletTypeList(_CurrentPalletType: Code[20]) ReturnList: Text
    var
        PalletItem: Record Item;
    begin
        PalletItem.SetRange("LGS Item Type", PalletItem."LGS Item Type"::Pallet);

        if _CurrentPalletType <> '' then begin
            ReturnList := _CurrentPalletType;
            PalletItem.SetFilter("No.", '<>%1', _CurrentPalletType);
        end;

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
            if _CurrentPalletType <> '' then
                ReturnList += ';' + ' '
            else
                ReturnList := ' ;' + ReturnList;
    end;
}
