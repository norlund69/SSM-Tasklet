codeunit 50154 "G2I Pick Session"
{
    SingleInstance = true;

    var
        _Lines: Text;  // Accumulated LP result lines, separated by CRLF

    procedure AddLicensePlateResult(_LPNo: Code[20]; _IsNew: Boolean)
    var
        CrLf: Text[2];
        Line: Text;
    begin
        CrLf[1] := 13;
        CrLf[2] := 10;
        if _IsNew then
            Line := 'License plate ' + _LPNo + ' created'
        else
            Line := 'License plate ' + _LPNo + ' picked';

        if _Lines = '' then
            _Lines := Line
        else
            _Lines += CrLf + Line;
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
