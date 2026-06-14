namespace G2I.Tasklet;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;

pageextension 50151 "G2I MOB LP List Ext" extends "MOB License Plate List"
{
    layout
    {
        addbefore(General)
        {
            group(G2IFilters)
            {
                Caption = 'Filters';

                field(G2ILocationFilter; G2ILocationFilter)
                {
                    ApplicationArea = All;
                    Caption = 'Location';
                    Editable = true;
                    ToolTip = 'Show only the license plates at the selected location.';

                    trigger OnAssistEdit()
                    var
                        Location: Record Location;
                        LocationList: Page "Location List";
                    begin
                        LocationList.LookupMode(true);
                        if LocationList.RunModal() <> Action::LookupOK then
                            exit;
                        LocationList.GetRecord(Location);
                        G2ILocationFilter := Location.Code;
                        ApplyLocationFilter();
                    end;

                    trigger OnValidate()
                    begin
                        ApplyLocationFilter();
                    end;
                }
                field(G2IItemNoFilter; G2IItemNoFilter)
                {
                    ApplicationArea = All;
                    Caption = 'Item No.';
                    Editable = true;
                    ToolTip = 'Pick an item to show only the license plates that contain that item.';

                    trigger OnAssistEdit()
                    var
                        Item: Record Item;
                        ItemList: Page "Item List";
                    begin
                        GetItemsOnLicensePlates(Item);
                        ItemList.SetTableView(Item);
                        ItemList.LookupMode(true);
                        if ItemList.RunModal() <> Action::LookupOK then
                            exit;
                        ItemList.GetRecord(Item);
                        G2IItemNoFilter := Item."No.";
                        ApplyItemFilter();
                    end;

                    trigger OnValidate()
                    begin
                        ApplyItemFilter();
                    end;
                }
            }
        }
        addafter("Package Type")
        {
            field(G2IItemNo; G2IItemNo)
            {
                ApplicationArea = All;
                Caption = 'Item No.';
                ToolTip = 'Specifies the item on the license plate, or "Mixed" when it holds more than one item.';
            }
            field(G2IItemName; G2IItemName)
            {
                ApplicationArea = All;
                Caption = 'Item Name';
                ToolTip = 'Specifies the item description. When the plate holds more than one item, shows the item with the highest quantity.';
            }
        }
        addfirst(factboxes)
        {
            part(LPContentFactbox; "G2I LP Content Factbox")
            {
                ApplicationArea = All;
                Caption = 'License Plate Content';
                SubPageLink = "License Plate No." = field("No.");
                UpdatePropagation = Both;
            }
        }
    }

    var
        G2ILocationFilter: Code[10];
        G2IItemNoFilter: Code[20];
        G2IItemNo: Code[20];
        G2IItemName: Text[100];

    trigger OnAfterGetRecord()
    begin
        CalcPlateItemSummary();
    end;

    local procedure CalcPlateItemSummary()
    var
        Content: Record "MOB License Plate Content";
        Item: Record Item;
        ItemQty: Dictionary of [Code[20], Decimal];
        ItemKeys: List of [Code[20]];
        ItemNo: Code[20];
        TopItemNo: Code[20];
        TopQty: Decimal;
        Qty: Decimal;
    begin
        Clear(G2IItemNo);
        Clear(G2IItemName);

        Content.SetRange("License Plate No.", Rec."No.");
        Content.SetRange(Type, Content.Type::Item);
        if Content.FindSet() then
            repeat
                if ItemQty.ContainsKey(Content."No.") then
                    ItemQty.Set(Content."No.", ItemQty.Get(Content."No.") + Content.Quantity)
                else
                    ItemQty.Add(Content."No.", Content.Quantity);
            until Content.Next() = 0;

        ItemKeys := ItemQty.Keys();
        case ItemKeys.Count of
            0:
                exit;
            1:
                begin
                    G2IItemNo := ItemKeys.Get(1);
                    if Item.Get(G2IItemNo) then
                        G2IItemName := Item.Description;
                end;
            else begin
                G2IItemNo := 'Mixed';
                TopQty := -1;
                foreach ItemNo in ItemKeys do begin
                    Qty := ItemQty.Get(ItemNo);
                    if Qty > TopQty then begin
                        TopQty := Qty;
                        TopItemNo := ItemNo;
                    end;
                end;
                if Item.Get(TopItemNo) then
                    G2IItemName := Item.Description;
            end;
        end;
    end;

    local procedure ApplyLocationFilter()
    begin
        Rec.FilterGroup(2);
        if G2ILocationFilter = '' then
            Rec.SetRange("Location Code")
        else
            Rec.SetRange("Location Code", G2ILocationFilter);
        Rec.FilterGroup(0);
        CurrPage.Update(false);
    end;

    local procedure GetItemsOnLicensePlates(var Item: Record Item): Boolean
    var
        Content: Record "MOB License Plate Content";
        ItemFilter: TextBuilder;
        LastNo: Code[20];
    begin
        Content.SetCurrentKey(Type, "No.");
        Content.SetRange(Type, Content.Type::Item);
        Content.SetFilter("No.", '<>%1', '');
        if Content.FindSet() then
            repeat
                if Content."No." <> LastNo then begin
                    LastNo := Content."No.";
                    if ItemFilter.Length() > 0 then
                        ItemFilter.Append('|');
                    ItemFilter.Append(Content."No.");
                end;
            until Content.Next() = 0;

        if ItemFilter.Length() = 0 then
            exit(false);

        Item.SetFilter("No.", ItemFilter.ToText());
        exit(true);
    end;

    local procedure ApplyItemFilter()
    var
        Content: Record "MOB License Plate Content";
        PlateFilter: TextBuilder;
        Plates: List of [Code[20]];
        PlateNo: Code[20];
    begin
        Rec.FilterGroup(2);
        if G2IItemNoFilter = '' then begin
            Rec.SetRange("No.");
            Rec.FilterGroup(0);
            CurrPage.Update(false);
            exit;
        end;

        Content.SetCurrentKey(Type, "No.");
        Content.SetRange(Type, Content.Type::Item);
        Content.SetRange("No.", G2IItemNoFilter);
        if Content.FindSet() then
            repeat
                if not Plates.Contains(Content."License Plate No.") then
                    Plates.Add(Content."License Plate No.");
            until Content.Next() = 0;

        if Plates.Count = 0 then begin
            // No plate contains the item -> show an empty list.
            Rec.SetRange("No.", '');
            Rec.FilterGroup(0);
            CurrPage.Update(false);
            exit;
        end;

        foreach PlateNo in Plates do begin
            if PlateFilter.Length() > 0 then
                PlateFilter.Append('|');
            PlateFilter.Append(PlateNo);
        end;
        Rec.SetFilter("No.", PlateFilter.ToText());
        Rec.FilterGroup(0);
        CurrPage.Update(false);
    end;
}
