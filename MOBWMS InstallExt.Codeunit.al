codeunit 50150 "MOB Install Ext"
{
    Subtype = Install;

    procedure InstallApp()
    var
        MobWmsSetupDocTypes: Codeunit "MOB WMS Setup Doc. Types";
    begin
        // Register the new scanner menu entry under the "WMS" group, sort key 10.
        // The first parameter MUST match the ConfigurationKey used in the
        // header / steps / post event subscribers.
        MobWmsSetupDocTypes.CreateMobileMenuOptionAndAddToMobileGroup('ChangePalletType', 'WMS', 10);
        MobWmsSetupDocTypes.CreateMobileMenuOptionAndAddToMobileGroup('Repack', 'WMS', 651);
    end;

    trigger OnInstallAppPerCompany()
    begin
        if GetCurrentVersion() = Version.Create(0, 0, 0, 0) then
            FreshInstall()
        else
            Reinstall();
    end;

    local procedure FreshInstall();
    begin
        InstallApp();
    end;

    local procedure Reinstall();
    begin
        InstallApp();
    end;

    procedure GetInstallingVersion(): Version
    var
        AppInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(AppInfo);
        exit(AppInfo.AppVersion());
    end;

    procedure GetCurrentVersion(): Version
    var
        AppInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(AppInfo);
        exit(AppInfo.DataVersion());
    end;
}
