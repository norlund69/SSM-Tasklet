codeunit 50158 "MOB WMS License Plate G2I"
{
    // -------------------------------------------------------------------------
    // License Plate customisation — Sunshine Mills (SMBI-34)
    //
    // 4.  LICENSE PLATES
    //
    //   Extra display info:
    //     When scanning a License Plate, display Pallet Status and Pallet Type
    //     below the standard Bin and Comment lines.  Both fields were added to
    //     the MOB License Plate table (page 6182217) by a prior customisation.
    //
    //   Display line layout (LicensePlateList listConfiguration):
    //     DisplayLine1            LP No.              standard
    //     DisplayLine2            Bin                 standard
    //     DisplayLine3            Comment             standard (if set)
    //     DisplayLine4            Pallet Status       added here
    //     DisplayLine5            Pallet Type         added here
    //     ExtraInfo cols 1–3      LP content rows     standard
    //
    //   ChangePalletType action:
    //     Added to the LicensePlate page action menu in application.cfg.
    // -------------------------------------------------------------------------

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"MOB WMS LicensePlate Lookup", 'OnLookupOnLicensePlate_OnAfterSetFromLicensePlate', '', true, true)]
    local procedure OnAfterSetFromLicensePlate(
        _LicensePlate: Record "MOB License Plate";
        var _LookupResponseElement: Record "MOB NS WhseInquery Element")
    begin
        // Display Pallet Status on DisplayLine4.
        // Field added by the LGS License Plate Status extension (LGS LPS LP Header Ext).
        if _LicensePlate."LGS LPS LP Status Code" <> '' then
            _LookupResponseElement.Set_DisplayLine4('Status: ' + _LicensePlate."LGS LPS LP Status Code");

        // Display Pallet Type (e.g. CHEP, WW, HEAT) on DisplayLine5.
        if _LicensePlate."LGS Pallet Type" <> '' then
            _LookupResponseElement.Set_DisplayLine5('Pallet Type: ' + _LicensePlate."LGS Pallet Type");
    end;
}
