codeunit 50160 "G2I Repack Session"
{
    // -------------------------------------------------------------------------
    // Single-instance codeunit used by MOB WMS Repack G2I to carry the
    // consumed lot number, expiration date, and quantity from the Consumption
    // step to the Output step within one device session.
    // -------------------------------------------------------------------------
    SingleInstance = true;

    var
        _LotNo: Code[50];
        _ExpirationDate: Date;
        _Quantity: Decimal;
        _OrderType: Text;
        _FromLicensePlateNo: Code[20];
        _PalletType: Code[20];

    procedure SetOrderType(_Value: Text)
    begin
        _OrderType := _Value;
    end;

    procedure IsRepackModule(): Boolean
    begin
        exit(_OrderType = 'Repack');
    end;

    procedure GetOrderType(): Text
    begin
        exit(_OrderType);
    end;

    procedure SetConsumptionValues(_LotNo2: Code[50]; _ExpirationDate2: Date; _Quantity2: Decimal; _FromLPNo2: Code[20]; _PalletType2: Code[20])
    begin
        _LotNo := _LotNo2;
        _ExpirationDate := _ExpirationDate2;
        _Quantity := _Quantity2;
        _FromLicensePlateNo := _FromLPNo2;
        _PalletType := _PalletType2;
    end;

    procedure GetConsumptionValues(var _LotNo2: Code[50]; var _ExpirationDate2: Date; var _Quantity2: Decimal; var _FromLPNo2: Code[20]; var _PalletType2: Code[20])
    begin
        _LotNo2 := _LotNo;
        _ExpirationDate2 := _ExpirationDate;
        _Quantity2 := _Quantity;
        _FromLPNo2 := _FromLicensePlateNo;
        _PalletType2 := _PalletType;
    end;

    procedure Clear()
    begin
        _LotNo := '';
        _ExpirationDate := 0D;
        _Quantity := 0;
        _OrderType := '';
        _FromLicensePlateNo := '';
        _PalletType := '';
    end;
}
