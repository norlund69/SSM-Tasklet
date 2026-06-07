codeunit 50153 "G2I License Plate Mgt"
{
    // -------------------------------------------------------------------------
    // Public wrapper around Tasklet's internal License Plate management
    // procedures. Source logic derived from:
    //   - MOB License Plate Mgt  (GetNextLicensePlateNo, GetNextLicensePlateContentLineNo)
    //   - MOB No. Series         (GetNextNo)
    //   - MOB License Plate      (InitLicensePlate, AddContent, RemoveLicensePlateContent)
    // -------------------------------------------------------------------------

    /// <summary>
    /// Validates that the given License Plate contains the item being picked.
    /// Raises an error if the LP doesn't exist or doesn't hold the item.
    /// </summary>
    procedure ValidateLicensePlateHasItem(_LicensePlateNo: Code[20]; _ItemNo: Code[20]; _VariantCode: Code[10])
    var
        LPContent: Record "MOB License Plate Content";
    begin
        if _LicensePlateNo = '' then
            exit;

        LPContent.SetRange("License Plate No.", _LicensePlateNo);
        LPContent.SetRange(Type, LPContent.Type::Item);
        LPContent.SetRange("No.", _ItemNo);
        if _VariantCode <> '' then
            LPContent.SetRange("Variant Code", _VariantCode);

        if LPContent.IsEmpty() then
            Error('License Plate %1 does not contain item %2.', _LicensePlateNo, _ItemNo);
    end;

    /// <summary>
    /// If the License Plate contains exactly one lot for the given item,
    /// returns that lot number — to be used as auto-fill.
    /// Returns '' if there are zero or multiple lots (user must scan manually).
    /// </summary>
    procedure GetSingleLotFromLicensePlate(_LicensePlateNo: Code[20]; _ItemNo: Code[20]; _VariantCode: Code[10]) LotNo: Code[50]
    var
        LPContent: Record "MOB License Plate Content";
    begin
        if _LicensePlateNo = '' then
            exit('');

        LPContent.SetRange("License Plate No.", _LicensePlateNo);
        LPContent.SetRange(Type, LPContent.Type::Item);
        LPContent.SetRange("No.", _ItemNo);
        if _VariantCode <> '' then
            LPContent.SetRange("Variant Code", _VariantCode);
        LPContent.SetFilter("Lot No.", '<>%1', '');

        // Only auto-fill when there is exactly one distinct lot
        if LPContent.Count() = 1 then begin
            LPContent.FindFirst();
            exit(LPContent."Lot No.");
        end;

        exit('');
    end;


    /// <summary>
    /// Returns the next License Plate No. from the No. Series defined in MOB Setup.
    /// Advances the series.
    /// </summary>
    procedure GetNextLicensePlateNo(): Code[20]
    var
        MobSetup: Record "MOB Setup";
        NoSeries: Codeunit "No. Series";
    begin
        MobSetup.Get();
        MobSetup.TestField("LP Number Series");
        exit(NoSeries.GetNextNo(MobSetup."LP Number Series", WorkDate(), false));
    end;

    /// <summary>
    /// Returns the next available Line No. for content on the given License Plate.
    /// </summary>
    procedure GetNextContentLineNo(_LicensePlate: Record "MOB License Plate"): Integer
    var
        LPContent: Record "MOB License Plate Content";
    begin
        LPContent.SetRange("License Plate No.", _LicensePlate."No.");
        if LPContent.FindLast() then
            exit(LPContent."Line No." + 10000);
        exit(10000);
    end;

    /// <summary>
    /// Creates and inserts a new License Plate, assigning a number from the
    /// No. Series and copying location, bin and document reference from the
    /// source LP. Pallet Type is set explicitly from _PalletType.
    /// </summary>
    procedure CreateLicensePlateFromSource(_SourceLP: Record "MOB License Plate"; _PalletType: Code[20]; var _NewLP: Record "MOB License Plate")
    begin
        _NewLP.Init();
        _NewLP.Validate("No.", GetNextLicensePlateNo());
        _NewLP.Validate("Location Code", _SourceLP."Location Code");
        _NewLP.Validate("Bin Code", _SourceLP."Bin Code");
        if (_SourceLP."Whse. Document No." <> '') and (_SourceLP."Whse. Document Type" <> 0) then begin
            _NewLP.Validate("Whse. Document Type", _SourceLP."Whse. Document Type");
            _NewLP.Validate("Whse. Document No.", _SourceLP."Whse. Document No.");
        end;
        _NewLP."LGS Pallet Type" := _PalletType;
        _NewLP.Insert(true);
    end;

    /// <summary>
    /// Adds a content line for _Quantity of the item described by _SourceContent
    /// to _LicensePlate. Uses Validate(Quantity) so that Quantity (Base) is
    /// calculated correctly via UoM.
    /// </summary>
    procedure AddContentLine(_LicensePlate: Record "MOB License Plate"; _SourceContent: Record "MOB License Plate Content"; _Quantity: Decimal)
    var
        NewContent: Record "MOB License Plate Content";
    begin
        NewContent.Init();
        NewContent.Validate("License Plate No.", _LicensePlate."No.");
        NewContent.Validate("Line No.", GetNextContentLineNo(_LicensePlate));
        NewContent.Validate("Location Code", _SourceContent."Location Code");
        NewContent.Validate("Bin Code", _SourceContent."Bin Code");
        NewContent.Validate("Whse. Document Type", _SourceContent."Whse. Document Type");
        NewContent.Validate("Whse. Document No.", _SourceContent."Whse. Document No.");
        NewContent.Validate("Whse. Document Line No.", _SourceContent."Whse. Document Line No.");
        NewContent.Validate("Source Type", _SourceContent."Source Type");
        NewContent.Validate("Source No.", _SourceContent."Source No.");
        NewContent.Validate("Source Line No.", _SourceContent."Source Line No.");
        NewContent.Validate("Source Document", _SourceContent."Source Document");
        NewContent.Validate(Type, _SourceContent.Type);
        NewContent.Validate("No.", _SourceContent."No.");
        NewContent.Validate("Variant Code", _SourceContent."Variant Code");
        NewContent.Validate("Unit Of Measure Code", _SourceContent."Unit Of Measure Code");
        NewContent.Validate("Lot No.", _SourceContent."Lot No.");
        NewContent.Validate("Serial No.", _SourceContent."Serial No.");
        NewContent.Validate(Quantity, _Quantity);  // sets Quantity (Base) via trigger
        NewContent.Insert(false);
    end;

    /// <summary>
    /// Reduces the content quantity on _LicensePlate for the item described by
    /// _SourceContent by _Quantity. Deletes the content line if it reaches zero.
    /// Mirrors RemoveLicensePlateContent on MOB License Plate.
    /// </summary>
    procedure ReduceContentLine(_LicensePlate: Record "MOB License Plate"; _SourceContent: Record "MOB License Plate Content"; _Quantity: Decimal)
    var
        LPContent: Record "MOB License Plate Content";
    begin
        LPContent.SetRange("License Plate No.", _LicensePlate."No.");
        LPContent.SetRange(Type, _SourceContent.Type);
        LPContent.SetRange("No.", _SourceContent."No.");
        LPContent.SetRange("Variant Code", _SourceContent."Variant Code");
        LPContent.SetRange("Unit Of Measure Code", _SourceContent."Unit Of Measure Code");
        LPContent.SetRange("Lot No.", _SourceContent."Lot No.");
        LPContent.SetRange("Serial No.", _SourceContent."Serial No.");
        if not LPContent.FindFirst() then
            Error('No content found on License Plate %1 for item %2.', _LicensePlate."No.", _SourceContent."No.");

        if _Quantity >= LPContent.Quantity then
            LPContent.Delete(true)
        else begin
            LPContent.Validate(Quantity, LPContent.Quantity - _Quantity);
            LPContent.Modify(true);
        end;
    end;

    /// <summary>
    /// Handles a partial pick split, pallet-type alignment, and LP document linking:
    ///   - PickedQty >= LPQty (full pick): no split. Aligns pallet type if it
    ///     differs, then re-links the source LP to the outbound shipment document.
    ///   - PickedQty &lt; LPQty (partial pick): creates a new LP with the picked
    ///     quantity and links it to the outbound shipment. The source LP keeps its
    ///     existing document reference (still holds remaining stock in the warehouse).
    /// _WhseDocumentType/_WhseDocumentNo come from the TAKE warehouse activity line
    /// and are the shipment that the pick serves.
    /// </summary>
    procedure HandlePartialPickSplit(
        _SourceLPNo: Code[20];
        _ItemNo: Code[20];
        _VariantCode: Code[10];
        _LotNumber: Code[50];
        _PickedQty: Decimal;
        _PickLinePalletType: Code[20];
        _WhseDocumentType: Enum Microsoft.Warehouse.Activity."Warehouse Activity Document Type";
        _WhseDocumentNo: Code[20])
    var
        SourceLP: Record "MOB License Plate";
        NewLP: Record "MOB License Plate";
        LPContent: Record "MOB License Plate Content";
        Location: Record Location;
        G2IPickSession: Codeunit "G2I Pick Session";
        NeedModify: Boolean;
    begin
        if _SourceLPNo = '' then
            exit;
        if not SourceLP.Get(_SourceLPNo) then
            exit;

        LPContent.SetRange("License Plate No.", SourceLP."No.");
        LPContent.SetRange(Type, LPContent.Type::Item);
        LPContent.SetRange("No.", _ItemNo);
        LPContent.SetRange("Variant Code", _VariantCode);
        if _LotNumber <> '' then
            LPContent.SetRange("Lot No.", _LotNumber);
        if not LPContent.FindFirst() then
            exit;

        // Full pick — align pallet type and link the LP to the outbound shipment.
        if _PickedQty >= LPContent.Quantity then begin
            if (_PickLinePalletType <> '') and (_PickLinePalletType <> SourceLP."LGS Pallet Type") then begin
                SourceLP."LGS Pallet Type" := _PickLinePalletType;
                NeedModify := true;
            end;
            if (_WhseDocumentNo <> '') and (SourceLP."Whse. Document No." <> _WhseDocumentNo) then begin
                SourceLP.Validate("Whse. Document Type", _WhseDocumentType);
                SourceLP.Validate("Whse. Document No.", _WhseDocumentNo);
                NeedModify := true;
            end;
            if SourceLP."Whse. Document Type" = SourceLP."Whse. Document Type"::Shipment then
                if Location.Get(SourceLP."Location Code") then
                    if (Location."Shipment Bin Code" <> '') and (SourceLP."Bin Code" <> Location."Shipment Bin Code") then begin
                        SourceLP."Bin Code" := Location."Shipment Bin Code";
                        NeedModify := true;
                    end;
            if NeedModify then
                SourceLP.Modify(true);
            G2IPickSession.AddLicensePlateResult(SourceLP."No.", false);
            exit;
        end;

        // Partial pick: new LP gets the PICKED quantity and the pick line's
        // pallet type, linked to the outbound shipment.
        // Source LP keeps the remainder with its existing document reference.
        CreateLicensePlateFromSource(SourceLP, _PickLinePalletType, NewLP);
        if _WhseDocumentNo <> '' then begin
            NewLP.Validate("Whse. Document Type", _WhseDocumentType);
            NewLP.Validate("Whse. Document No.", _WhseDocumentNo);
        end;
        if NewLP."Whse. Document Type" = NewLP."Whse. Document Type"::Shipment then
            if Location.Get(NewLP."Location Code") then
                if Location."Shipment Bin Code" <> '' then
                    NewLP."Bin Code" := Location."Shipment Bin Code";
        NewLP.Modify(true);
        AddContentLine(NewLP, LPContent, _PickedQty);
        ReduceContentLine(SourceLP, LPContent, _PickedQty);

        G2IPickSession.AddLicensePlateResult(NewLP."No.", true);
    end;
}
