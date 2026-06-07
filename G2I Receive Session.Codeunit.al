codeunit 50156 "G2I Receive Session"
{
    // -------------------------------------------------------------------------
    // Single-instance codeunit used by MOB WMS Receive G2I to accumulate
    // created LP numbers for the post-success message.
    // Pattern mirrors G2I Pick Session (codeunit 50154).
    // -------------------------------------------------------------------------
    SingleInstance = true;

    var
        _Lines: Text;

    procedure AddLicensePlateResult(_LPNo: Code[20])
    var
        CrLf: Text[2];
    begin
        CrLf[1] := 13;
        CrLf[2] := 10;
        if _Lines = '' then
            _Lines := 'License plate ' + _LPNo + ' created'
        else
            _Lines += CrLf + 'License plate ' + _LPNo + ' created';
    end;

    procedure GetResultLines(): Text
    begin
        exit(_Lines);
    end;

    procedure Clear()
    begin
        _Lines := '';
    end;
}
