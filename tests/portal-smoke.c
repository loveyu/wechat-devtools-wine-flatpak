#define COBJMACROS
#define UNICODE
#define _UNICODE

#include <windows.h>
#include <commdlg.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <stdio.h>
#include <stdlib.h>

static DWORD WINAPI watchdog_thread(void *unused)
{
    WCHAR value[32];
    DWORD milliseconds;

    if (!GetEnvironmentVariableW(L"PORTAL_SMOKE_TIMEOUT_MS", value, ARRAYSIZE(value)))
        return 0;
    milliseconds = wcstoul(value, NULL, 10);
    if (milliseconds < 1000 || milliseconds > 60000) return 0;
    Sleep(milliseconds);
    TerminateProcess(GetCurrentProcess(), 124);
    return 0;
}

static int test_legacy_open(void)
{
    WCHAR path[32768] = L"";
    static const WCHAR filter[] = L"Text files\0*.txt\0All files\0*.*\0\0";
    OPENFILENAMEW ofn = {0};

    ofn.lStructSize = sizeof(ofn);
    ofn.lpstrFilter = filter;
    ofn.lpstrFile = path;
    ofn.nMaxFile = ARRAYSIZE(path);
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_EXPLORER |
                OFN_ALLOWMULTISELECT;
    if (!GetOpenFileNameW(&ofn))
    {
        wprintf(L"cancel-or-error:%lu\n", CommDlgExtendedError());
        return 2;
    }
    wprintf(L"selected:%ls\n", path);
    return 0;
}

static int test_legacy_open_a(void)
{
    char path[32768] = "";
    static const char filter[] = "Text files\0*.txt\0All files\0*.*\0\0";
    OPENFILENAMEA ofn = {0};

    ofn.lStructSize = sizeof(ofn);
    ofn.lpstrFilter = filter;
    ofn.lpstrFile = path;
    ofn.nMaxFile = ARRAYSIZE(path);
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_EXPLORER;
    if (!GetOpenFileNameA(&ofn)) return 2;
    return 0;
}

static int test_legacy_save(void)
{
    WCHAR path[32768] = L"portal-smoke.txt";
    static const WCHAR filter[] = L"Text files\0*.txt\0All files\0*.*\0\0";
    OPENFILENAMEW ofn = {0};

    ofn.lStructSize = sizeof(ofn);
    ofn.lpstrFilter = filter;
    ofn.lpstrFile = path;
    ofn.nMaxFile = ARRAYSIZE(path);
    ofn.lpstrDefExt = L"txt";
    ofn.Flags = OFN_PATHMUSTEXIST | OFN_OVERWRITEPROMPT | OFN_EXPLORER;
    if (!GetSaveFileNameW(&ofn))
    {
        wprintf(L"cancel-or-error:%lu\n", CommDlgExtendedError());
        return 2;
    }
    wprintf(L"selected:%ls\n", path);
    return 0;
}

static int test_legacy_save_a(void)
{
    char path[32768] = "portal-smoke-ansi.txt";
    static const char filter[] = "Text files\0*.txt\0All files\0*.*\0\0";
    OPENFILENAMEA ofn = {0};

    ofn.lStructSize = sizeof(ofn);
    ofn.lpstrFilter = filter;
    ofn.lpstrFile = path;
    ofn.nMaxFile = ARRAYSIZE(path);
    ofn.lpstrDefExt = "txt";
    ofn.Flags = OFN_PATHMUSTEXIST | OFN_OVERWRITEPROMPT | OFN_EXPLORER;
    if (!GetSaveFileNameA(&ofn)) return 2;
    return 0;
}

static UINT_PTR CALLBACK smoke_hook(HWND dialog, UINT message,
                                    WPARAM wparam, LPARAM lparam)
{
    return 0;
}

static int test_hook_fallback(void)
{
    WCHAR path[32768] = L"";
    OPENFILENAMEW ofn = {0};

    ofn.lStructSize = sizeof(ofn);
    ofn.lpstrFile = path;
    ofn.nMaxFile = ARRAYSIZE(path);
    ofn.Flags = OFN_EXPLORER | OFN_ENABLEHOOK;
    ofn.lpfnHook = smoke_hook;
    if (!GetOpenFileNameW(&ofn)) return 2;
    return 0;
}

static int test_browse_folder(void)
{
    WCHAR path[32768] = L"";
    BROWSEINFOW bi = {0};
    PIDLIST_ABSOLUTE pidl;

    bi.lpszTitle = L"Portal folder smoke test";
    bi.ulFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE;
    pidl = SHBrowseForFolderW(&bi);
    if (!pidl)
    {
        wprintf(L"cancel-or-error\n");
        return 2;
    }
    if (!SHGetPathFromIDListW(pidl, path))
    {
        CoTaskMemFree(pidl);
        wprintf(L"path-conversion-error\n");
        return 3;
    }
    CoTaskMemFree(pidl);
    wprintf(L"selected:%ls\n", path);
    return 0;
}

typedef struct
{
    IFileDialogEvents IFileDialogEvents_iface;
    LONG ref;
    LONG folder_change;
    LONG folder_view_visible;
    LONG selection_change;
    LONG selection_visible;
    LONG file_ok;
    LONG file_ok_visible;
} portal_event_sink;

static portal_event_sink *impl_from_IFileDialogEvents(IFileDialogEvents *iface)
{
    return CONTAINING_RECORD(iface, portal_event_sink, IFileDialogEvents_iface);
}

static HRESULT WINAPI portal_events_QueryInterface(IFileDialogEvents *iface,
                                                     REFIID riid, void **out)
{
    if (!out) return E_POINTER;
    *out = NULL;
    if (IsEqualIID(riid, &IID_IUnknown) ||
        IsEqualIID(riid, &IID_IFileDialogEvents))
    {
        *out = iface;
        IFileDialogEvents_AddRef(iface);
        return S_OK;
    }
    return E_NOINTERFACE;
}

static ULONG WINAPI portal_events_AddRef(IFileDialogEvents *iface)
{
    portal_event_sink *sink = impl_from_IFileDialogEvents(iface);
    return InterlockedIncrement(&sink->ref);
}

static ULONG WINAPI portal_events_Release(IFileDialogEvents *iface)
{
    portal_event_sink *sink = impl_from_IFileDialogEvents(iface);
    return InterlockedDecrement(&sink->ref);
}

static BOOL dialog_selection_is_visible(IFileDialog *dialog)
{
    IShellItem *item = NULL;
    PWSTR path = NULL;
    HRESULT hr;
    BOOL visible = FALSE;

    hr = IFileDialog_GetCurrentSelection(dialog, &item);
    if (SUCCEEDED(hr) && item)
    {
        hr = IShellItem_GetDisplayName(item, SIGDN_FILESYSPATH, &path);
        if (SUCCEEDED(hr) && path && GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES)
            visible = TRUE;
    }
    if (path) CoTaskMemFree(path);
    if (item) IShellItem_Release(item);
    return visible;
}

static HRESULT WINAPI portal_events_OnFileOk(IFileDialogEvents *iface,
                                               IFileDialog *dialog)
{
    portal_event_sink *sink = impl_from_IFileDialogEvents(iface);
    IFileOpenDialog *open_dialog = NULL;
    IShellItemArray *items = NULL;
    DWORD count = 0;

    InterlockedIncrement(&sink->file_ok);
    if (SUCCEEDED(IFileDialog_QueryInterface(dialog, &IID_IFileOpenDialog,
                                              (void **)&open_dialog)) &&
        SUCCEEDED(IFileOpenDialog_GetSelectedItems(open_dialog, &items)) &&
        SUCCEEDED(IShellItemArray_GetCount(items, &count)) && count)
        InterlockedExchange(&sink->file_ok_visible, 1);

    if (items) IShellItemArray_Release(items);
    if (open_dialog) IFileOpenDialog_Release(open_dialog);
    return S_OK;
}

static HRESULT WINAPI portal_events_OnFolderChanging(IFileDialogEvents *iface,
                                                       IFileDialog *dialog,
                                                       IShellItem *folder)
{
    return S_OK;
}

static HRESULT WINAPI portal_events_OnFolderChange(IFileDialogEvents *iface,
                                                     IFileDialog *dialog)
{
    portal_event_sink *sink = impl_from_IFileDialogEvents(iface);
    IServiceProvider *provider = NULL;
    IShellBrowser *browser = NULL;
    IShellView *view = NULL;
    IFolderView2 *folder_view = NULL;
    IShellItemArray *items = NULL;
    DWORD count = 0;

    InterlockedIncrement(&sink->folder_change);
    if (SUCCEEDED(IFileDialog_QueryInterface(dialog, &IID_IServiceProvider,
                                              (void **)&provider)) &&
        SUCCEEDED(IServiceProvider_QueryService(provider, &SID_STopLevelBrowser,
                                                 &IID_IShellBrowser,
                                                 (void **)&browser)) &&
        SUCCEEDED(IShellBrowser_QueryActiveShellView(browser, &view)) &&
        SUCCEEDED(IShellView_QueryInterface(view, &IID_IFolderView2,
                                             (void **)&folder_view)) &&
        SUCCEEDED(IFolderView2_GetSelection(folder_view, FALSE, &items)) &&
        SUCCEEDED(IShellItemArray_GetCount(items, &count)) && count)
        InterlockedExchange(&sink->folder_view_visible, 1);

    if (items) IShellItemArray_Release(items);
    if (folder_view) IFolderView2_Release(folder_view);
    if (view) IShellView_Release(view);
    if (browser) IShellBrowser_Release(browser);
    if (provider) IServiceProvider_Release(provider);
    return S_OK;
}

static HRESULT WINAPI portal_events_OnSelectionChange(IFileDialogEvents *iface,
                                                        IFileDialog *dialog)
{
    portal_event_sink *sink = impl_from_IFileDialogEvents(iface);
    InterlockedIncrement(&sink->selection_change);
    if (dialog_selection_is_visible(dialog))
        InterlockedExchange(&sink->selection_visible, 1);
    return S_OK;
}

static HRESULT WINAPI portal_events_OnShareViolation(IFileDialogEvents *iface,
                                                       IFileDialog *dialog,
                                                       IShellItem *item,
                                                       FDE_SHAREVIOLATION_RESPONSE *response)
{
    *response = FDESVR_DEFAULT;
    return S_OK;
}

static HRESULT WINAPI portal_events_OnTypeChange(IFileDialogEvents *iface,
                                                   IFileDialog *dialog)
{
    return S_OK;
}

static HRESULT WINAPI portal_events_OnOverwrite(IFileDialogEvents *iface,
                                                  IFileDialog *dialog,
                                                  IShellItem *item,
                                                  FDE_OVERWRITE_RESPONSE *response)
{
    *response = FDEOR_DEFAULT;
    return S_OK;
}

static const IFileDialogEventsVtbl portal_events_vtbl =
{
    portal_events_QueryInterface,
    portal_events_AddRef,
    portal_events_Release,
    portal_events_OnFileOk,
    portal_events_OnFolderChanging,
    portal_events_OnFolderChange,
    portal_events_OnSelectionChange,
    portal_events_OnShareViolation,
    portal_events_OnTypeChange,
    portal_events_OnOverwrite,
};

static int test_ifile_dialog_events(void)
{
    portal_event_sink sink = {{&portal_events_vtbl}, 1};
    IFileOpenDialog *dialog = NULL;
    DWORD cookie = 0;
    FILEOPENDIALOGOPTIONS options;
    HRESULT hr;
    int ret = 1;

    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(hr)) return 4;
    hr = CoCreateInstance(&CLSID_FileOpenDialog, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IFileOpenDialog, (void **)&dialog);
    if (FAILED(hr)) goto done;
    hr = IFileOpenDialog_GetOptions(dialog, &options);
    if (FAILED(hr)) goto done;
    hr = IFileOpenDialog_SetOptions(dialog, options | FOS_FORCEFILESYSTEM |
                                    FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST |
                                    FOS_ALLOWMULTISELECT);
    if (FAILED(hr)) goto done;
    hr = IFileOpenDialog_Advise(dialog, &sink.IFileDialogEvents_iface, &cookie);
    if (FAILED(hr)) goto done;
    hr = IFileOpenDialog_Show(dialog, NULL);
    IFileOpenDialog_Unadvise(dialog, cookie);
    cookie = 0;
    wprintf(L"events:folder=%ld folder-view-visible=%ld "
            L"selection=%ld selection-visible=%ld "
            L"file-ok=%ld file-ok-visible=%ld show=0x%08lx\n",
            sink.folder_change, sink.folder_view_visible,
            sink.selection_change, sink.selection_visible,
            sink.file_ok, sink.file_ok_visible, (unsigned long)hr);
    if (SUCCEEDED(hr) && sink.folder_change && sink.folder_view_visible &&
        sink.selection_change &&
        sink.selection_visible && sink.file_ok && sink.file_ok_visible)
        ret = 0;

done:
    if (cookie) IFileOpenDialog_Unadvise(dialog, cookie);
    if (dialog) IFileOpenDialog_Release(dialog);
    CoUninitialize();
    return ret;
}

static int test_ifile_dialog(BOOL save)
{
    IFileDialog *dialog = NULL;
    IShellItem *item = NULL;
    PWSTR path = NULL;
    HRESULT hr;
    int ret = 1;

    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(hr))
    {
        fwprintf(stderr, L"CoInitializeEx failed: 0x%08lx\n", (unsigned long)hr);
        return 4;
    }
    hr = CoCreateInstance(save ? &CLSID_FileSaveDialog : &CLSID_FileOpenDialog,
                          NULL, CLSCTX_INPROC_SERVER, &IID_IFileDialog,
                          (void **)&dialog);
    if (FAILED(hr))
    {
        fwprintf(stderr, L"CoCreateInstance failed: 0x%08lx\n", (unsigned long)hr);
        goto done;
    }
    hr = IFileDialog_Show(dialog, NULL);
    if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED))
    {
        wprintf(L"cancel\n");
        ret = 2;
        goto done;
    }
    if (FAILED(hr))
    {
        fwprintf(stderr, L"IFileDialog::Show failed: 0x%08lx\n", (unsigned long)hr);
        goto done;
    }
    hr = IFileDialog_GetResult(dialog, &item);
    if (FAILED(hr)) goto done;
    hr = IShellItem_GetDisplayName(item, SIGDN_FILESYSPATH, &path);
    if (FAILED(hr)) goto done;
    wprintf(L"selected:%ls\n", path);
    ret = 0;

done:
    if (path) CoTaskMemFree(path);
    if (item) IShellItem_Release(item);
    if (dialog) IFileDialog_Release(dialog);
    CoUninitialize();
    return ret;
}

static int test_ifile_dialog_constructor(void)
{
    IFileDialog *dialog = NULL;
    HRESULT hr;

    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(hr))
    {
        fwprintf(stderr, L"CoInitializeEx failed: 0x%08lx\n", (unsigned long)hr);
        return 4;
    }
    hr = CoCreateInstance(&CLSID_FileOpenDialog, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IFileDialog, (void **)&dialog);
    if (dialog) IFileDialog_Release(dialog);
    CoUninitialize();
    if (FAILED(hr))
    {
        fwprintf(stderr, L"CoCreateInstance failed: 0x%08lx\n", (unsigned long)hr);
        return 1;
    }
    wprintf(L"constructed\n");
    return 0;
}

int wmain(int argc, WCHAR **argv)
{
    HANDLE watchdog;

    watchdog = CreateThread(NULL, 0, watchdog_thread, NULL, 0, NULL);
    if (watchdog) CloseHandle(watchdog);
    if (argc != 2)
    {
        fwprintf(stderr, L"usage: portal-smoke.exe open|opena|save|savea|folder|ifilecreate|ifileopen|ifileevents|ifilesave|hook\n");
        return 64;
    }
    if (!lstrcmpiW(argv[1], L"open")) return test_legacy_open();
    if (!lstrcmpiW(argv[1], L"opena")) return test_legacy_open_a();
    if (!lstrcmpiW(argv[1], L"save")) return test_legacy_save();
    if (!lstrcmpiW(argv[1], L"savea")) return test_legacy_save_a();
    if (!lstrcmpiW(argv[1], L"folder")) return test_browse_folder();
    if (!lstrcmpiW(argv[1], L"ifilecreate")) return test_ifile_dialog_constructor();
    if (!lstrcmpiW(argv[1], L"ifileopen")) return test_ifile_dialog(FALSE);
    if (!lstrcmpiW(argv[1], L"ifileevents")) return test_ifile_dialog_events();
    if (!lstrcmpiW(argv[1], L"ifilesave")) return test_ifile_dialog(TRUE);
    if (!lstrcmpiW(argv[1], L"hook")) return test_hook_fallback();
    fwprintf(stderr, L"unknown mode: %ls\n", argv[1]);
    return 64;
}
