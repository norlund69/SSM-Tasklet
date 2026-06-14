namespace G2I.Tasklet;

using Microsoft.Inventory.Item;

page 50150 "G2I LP Content Factbox"
{
    Caption = 'License Plate Content';
    PageType = ListPart;
    ApplicationArea = All;
    SourceTable = "MOB License Plate Content";
    Editable = false;
    LinksAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field(Type; Rec.Type)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies whether the content line is an item or a sub license plate.';
                }
                field("No."; Rec."No.")
                {
                    ApplicationArea = All;
                    Caption = 'Item No.';
                    ToolTip = 'Specifies the item number stored on the license plate.';
                }
                field(ItemName; ItemName)
                {
                    ApplicationArea = All;
                    Caption = 'Item Name';
                    ToolTip = 'Specifies the description of the item.';
                }
                field(Quantity; Rec.Quantity)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the quantity on the license plate.';
                }
                field("Unit Of Measure Code"; Rec."Unit Of Measure Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the unit of measure of the quantity.';
                }
            }
        }
    }

    var
        ItemName: Text[100];

    trigger OnAfterGetRecord()
    var
        Item: Record Item;
    begin
        ItemName := '';
        if (Rec.Type = Rec.Type::Item) and (Rec."No." <> '') then
            if Item.Get(Rec."No.") then
                ItemName := Item.Description;
    end;
}
