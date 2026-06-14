pageextension 50152 "SSM MOB License Plate Content" extends "MOB License Plate Content"
{
    layout
    {
        addafter("No.")
        {
            field(SSMItemDescription; SSMItemDescription)
            {
                Caption = 'Description';
                ApplicationArea = All;
                Editable = false;
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        Item: Record Item;
    begin
        SSMItemDescription := '';
        if (Rec.Type = Rec.Type::Item) and Item.Get(Rec."No.") then
            SSMItemDescription := Item.Description;
    end;

    var
        SSMItemDescription: Text[100];
}
