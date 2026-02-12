--- MacroQuest ImGui Lua API definitions.
--- Source: MQ lua bindings (lua_ImGuiCore, lua_ImGuiWidgets, lua_ImGuiEnums, lua_ImGuiUserTypes, lua_ImGuiCustom).
--- Important: Widgets return (value, changed/pressed) - e.g. Checkbox returns (value, pressed), not just pressed.

---@class ImVec2
---@field x number
---@field y number

---@class ImVec4
---@field x number
---@field y number
---@field z number
---@field w number

---@class ImGuiPayload
---@field DataType string
---@field Data any
---@field RawData string

---@class ImGuiStyle
---@field Alpha number
---@field WindowPadding ImVec2
---@field WindowRounding number
---@field FramePadding ImVec2
---@field ItemSpacing ImVec2
---@field ItemInnerSpacing ImVec2
---@field TouchExtraPadding ImVec2
---@field IndentSpacing number
---@field ScrollbarSize number
---@field GrabMinSize number
---@field Colors ImVec4[]

---@class ImGuiIO
---@field ConfigFlags number
---@field DisplaySize ImVec2
---@field DeltaTime number
---@field FontDefault ImFont
---@field MousePos ImVec2
---@field KeyCtrl boolean
---@field KeyShift boolean
---@field KeyAlt boolean
---@field KeySuper boolean

---@class ImFont
---@field LegacySize number

---@class ImDrawList
---@field Flags number
---@field PushClipRect fun(p_min: ImVec2, p_max: ImVec2): nil
---@field PushClipRectFullScreen fun(): nil
---@field PopClipRect fun(): nil
---@field PushTexture fun(texture_id: userdata): nil
---@field PopTexture fun(): nil
---@field GetClipRectMin fun(): ImVec2
---@field GetClipRectMax fun(): ImVec2
--- drawList:AddLine(p1, p2, col, thickness) — : passes self as first arg, so 5 params.
---@field AddLine fun(self: ImDrawList, p1: ImVec2, p2: ImVec2, col: number, thickness?: number): nil
---@field AddRect fun(p_min: ImVec2, p_max: ImVec2, col: number, rounding?: number, flags?: number): nil
---@field AddRectFilled fun(p_min: ImVec2, p_max: ImVec2, col: number, rounding?: number): nil
---@field AddRectFilledMultiColor fun(p_min: ImVec2, p_max: ImVec2, col_upr_left: number, col_upr_right: number, col_bot_right: number, col_bot_left: number): nil
---@field AddQuad fun(p1: ImVec2, p2: ImVec2, p3: ImVec2, p4: ImVec2, col: number, thickness?: number): nil
---@field AddQuadFilled fun(p1: ImVec2, p2: ImVec2, p3: ImVec2, p4: ImVec2, col: number): nil
---@field AddTriangle fun(p1: ImVec2, p2: ImVec2, p3: ImVec2, col: number, thickness?: number): nil
---@field AddTriangleFilled fun(p1: ImVec2, p2: ImVec2, p3: ImVec2, col: number): nil
---@field AddCircle fun(center: ImVec2, radius: number, col: number, num_segments?: number): nil
---@field AddCircleFilled fun(center: ImVec2, radius: number, col: number, num_segments?: number): nil
---@field AddNgon fun(center: ImVec2, radius: number, col: number, num_segments: number, thickness?: number): nil
---@field AddNgonFilled fun(center: ImVec2, radius: number, col: number, num_segments: number): nil
---@field AddText fun(pos: ImVec2, col: number, text: string): nil
---@field AddText fun(font: ImFont, font_size: number, pos: ImVec2, col: number, text: string): nil
---@field AddBezierCubic fun(p1: ImVec2, p2: ImVec2, p3: ImVec2, p4: ImVec2, col: number, thickness: number): nil
---@field AddBezierQuadratic fun(p1: ImVec2, p2: ImVec2, p3: ImVec2, col: number, thickness: number): nil
---@field ChannelsSplit fun(channel_count: number): nil
---@field ChannelsSetCurrent fun(channel_index: number): nil
---@field ChannelsMerge fun(): nil

---@class ImGuiTableSortSpecs
---@field SpecsCount number
---@field SpecsDirty boolean

---@class ImGuiViewport
---@field ID number
---@field Pos ImVec2
---@field Size ImVec2

---@class ImGuiWindowClass
---@field ClassId number
---@field ParentViewportId number

---@class ConsoleWidget
---@field autoScroll boolean
---@field maxBufferLines number
---@field opacity number

---@enum ImGuiWindowFlags
ImGuiWindowFlags = {
    None = 0,
    NoTitleBar = 1,
    NoResize = 2,
    NoMove = 4,
    NoScrollbar = 8,
    NoScrollWithMouse = 16,
    NoCollapse = 32,
    AlwaysAutoResize = 64,
    NoBackground = 128,
    NoSavedSettings = 256,
    NoMouseInputs = 512,
    MenuBar = 1024,
    HorizontalScrollbar = 2048,
    NoFocusOnAppearing = 4096,
    NoBringToFrontOnFocus = 8192,
    AlwaysVerticalScrollbar = 16384,
    AlwaysHorizontalScrollbar = 32768,
    NoNavInputs = 65536,
    NoNavFocus = 131072,
    UnsavedDocument = 262144,
    NoDocking = 524288,
    NoNav = 1048576,
    NoDecoration = 2097152,
    NoInputs = 4194304,
    ChildWindow = 8388608,
    Tooltip = 16777216,
    Popup = 33554432,
    Modal = 67108864,
    ChildMenu = 134217728,
    DockNodeHost = 268435456,
}

---@enum ImGuiChildFlags
ImGuiChildFlags = {
    None = 0,
    Borders = 1,
    AlwaysUseWindowPadding = 2,
    ResizeX = 4,
    ResizeY = 8,
    AutoResizeX = 16,
    AutoResizeY = 32,
    AlwaysAutoResize = 64,
    FrameStyle = 128,
    NavFlattened = 256,
    Border = 1,
}

---@enum ImGuiInputTextFlags
ImGuiInputTextFlags = {
    None = 0,
    CharsDecimal = 256,
    CharsHexadecimal = 512,
    CharsScientific = 1024,
    CharsUppercase = 2048,
    CharsNoBlank = 4096,
    AllowTabInput = 8192,
    EnterReturnsTrue = 16384,
    EscapeClearsAll = 32768,
    CtrlEnterForNewLine = 65536,
    ReadOnly = 131072,
    Password = 262144,
    AlwaysOverwrite = 524288,
    AutoSelectAll = 1048576,
    NoHorizontalScroll = 2097152,
    NoUndoRedo = 4194304,
    WordWrap = 8388608,
}

---@enum ImGuiTreeNodeFlags
ImGuiTreeNodeFlags = {
    None = 0,
    Selected = 1,
    Framed = 2,
    AllowOverlap = 4,
    NoTreePushOnOpen = 8,
    NoAutoOpenOnLog = 16,
    DefaultOpen = 32,
    OpenOnDoubleClick = 64,
    OpenOnArrow = 128,
    Leaf = 256,
    Bullet = 512,
    FramePadding = 1024,
    SpanAvailWidth = 2048,
    SpanFullWidth = 4096,
    SpanLabelWidth = 8192,
    SpanAllColumns = 16384,
    CollapsingHeader = 32768,
}

---@enum ImGuiPopupFlags
ImGuiPopupFlags = {
    None = 0,
    MouseButtonLeft = 0,
    MouseButtonRight = 1,
    MouseButtonMiddle = 2,
    NoReopen = 4,
    NoOpenOverExistingPopup = 8,
    NoOpenOverItems = 16,
    AnyPopupId = 32,
    AnyPopupLevel = 64,
    AnyPopup = 96,
    MouseButtonDefault_ = 1,
}

---@enum ImGuiSelectableFlags
ImGuiSelectableFlags = {
    None = 0,
    NoAutoClosePopups = 2,
    SpanAllColumns = 4,
    AllowDoubleClick = 8,
    Disabled = 16,
    AllowOverlap = 32,
    Highlight = 64,
    SelectOnNav = 128,
}

---@enum ImGuiComboFlags
ImGuiComboFlags = {
    None = 0,
    PopupAlignLeft = 1,
    HeightSmall = 2,
    HeightRegular = 4,
    HeightLarge = 8,
    HeightLargest = 16,
    NoArrowButton = 32,
    NoPreview = 64,
    WidthFitPreview = 128,
}

---@enum ImGuiTabBarFlags
ImGuiTabBarFlags = {
    None = 0,
    Reorderable = 1,
    AutoSelectNewTabs = 2,
    TabListPopupButton = 4,
    NoCloseWithMiddleMouseButton = 8,
    NoTabListScrollingButtons = 16,
    NoTooltip = 32,
    FittingPolicyShrink = 64,
    FittingPolicyScroll = 128,
}

---@enum ImGuiTabItemFlags
ImGuiTabItemFlags = {
    None = 0,
    UnsavedDocument = 1,
    SetSelected = 2,
    NoCloseWithMiddleMouseButton = 4,
    NoPushId = 8,
    NoTooltip = 16,
    NoReorder = 32,
    Leading = 64,
    Trailing = 128,
    NoAssumedClosure = 256,
}

---@enum ImGuiFocusedFlags
ImGuiFocusedFlags = {
    None = 0,
    ChildWindows = 1,
    RootWindow = 2,
    AnyWindow = 4,
    NoPopupHierarchy = 8,
    DockHierarchy = 16,
    RootAndChildWindows = 3,
}

---@enum ImGuiHoveredFlags
ImGuiHoveredFlags = {
    None = 0,
    ChildWindows = 1,
    RootWindow = 2,
    AnyWindow = 4,
    NoPopupHierarchy = 8,
    DockHierarchy = 16,
    AllowWhenBlockedByPopup = 32,
    AllowWhenBlockedByActiveItem = 64,
    AllowWhenOverlappedByItem = 128,
    AllowWhenOverlappedByWindow = 256,
    AllowWhenDisabled = 512,
    RectOnly = 1024,
    RootAndChildWindows = 3,
    ForTooltip = 4096,
    Stationary = 8192,
    DelayNone = 16384,
    DelayShort = 32768,
    DelayNormal = 65536,
}

---@enum ImGuiCol
ImGuiCol = {
    Text = 0,
    TextDisabled = 1,
    WindowBg = 2,
    ChildBg = 3,
    PopupBg = 4,
    Border = 5,
    BorderShadow = 6,
    FrameBg = 7,
    FrameBgHovered = 8,
    FrameBgActive = 9,
    TitleBg = 10,
    TitleBgActive = 11,
    TitleBgCollapsed = 12,
    MenuBarBg = 13,
    ScrollbarBg = 14,
    ScrollbarGrab = 15,
    ScrollbarGrabHovered = 16,
    ScrollbarGrabActive = 17,
    CheckMark = 18,
    SliderGrab = 19,
    SliderGrabActive = 20,
    Button = 21,
    ButtonHovered = 22,
    ButtonActive = 23,
    Header = 24,
    HeaderHovered = 25,
    HeaderActive = 26,
    Separator = 27,
    SeparatorHovered = 28,
    SeparatorActive = 29,
    ResizeGrip = 30,
    ResizeGripHovered = 31,
    ResizeGripActive = 32,
    Tab = 33,
    TabHovered = 34,
    TabSelected = 35,
    TabSelectedOverline = 36,
    TabDimmed = 37,
    TabDimmedSelected = 38,
    TabDimmedSelectedOverline = 39,
    TableHeaderBg = 40,
    TableBorderStrong = 41,
    TableBorderLight = 42,
    TableRowBg = 43,
    TableRowBgAlt = 44,
    TextSelectedBg = 45,
    DragDropTarget = 46,
    DragDropTargetBg = 47,
    NavCursor = 48,
    NavWindowingHighlight = 49,
    NavWindowingDimBg = 50,
    ModalWindowDimBg = 51,
    COUNT = 52,
}

---@enum ImGuiStyleVar
ImGuiStyleVar = {
    Alpha = 0,
    DisabledAlpha = 1,
    WindowPadding = 2,
    WindowRounding = 3,
    WindowBorderSize = 4,
    WindowMinSize = 5,
    WindowTitleAlign = 6,
    ChildRounding = 7,
    ChildBorderSize = 8,
    PopupRounding = 9,
    PopupBorderSize = 10,
    FramePadding = 11,
    FrameRounding = 12,
    FrameBorderSize = 13,
    ItemSpacing = 14,
    ItemInnerSpacing = 15,
    IndentSpacing = 16,
    CellPadding = 17,
    ScrollbarSize = 18,
    ScrollbarRounding = 19,
    ScrollbarPadding = 20,
    GrabMinSize = 21,
    GrabRounding = 22,
    TabRounding = 23,
    TabBarBorderSize = 24,
    TabMinWidthBase = 25,
    TabMinWidthShrink = 26,
    TabBarOverlineSize = 27,
    ButtonTextAlign = 28,
    SelectableTextAlign = 29,
    COUNT = 30,
}

---@enum ImGuiCond
ImGuiCond = {
    None = 0,
    Always = 1,
    Once = 2,
    FirstUseEver = 4,
    Appearing = 8,
}

---@enum ImGuiTableFlags
ImGuiTableFlags = {
    None = 0,
    Resizable = 1,
    Reorderable = 2,
    Hideable = 4,
    Sortable = 8,
    NoSavedSettings = 16,
    ContextMenuInBody = 32,
    RowBg = 64,
    BordersInnerH = 128,
    BordersOuterH = 256,
    BordersInnerV = 512,
    BordersOuterV = 1024,
    BordersH = 384,
    BordersV = 1536,
    BordersInner = 640,
    BordersOuter = 1280,
    Borders = 1920,
    NoBordersInBody = 2048,
    NoBordersInBodyUntilResize = 4096,
    SizingFixedFit = 8192,
    SizingFixedSame = 16384,
    SizingStretchProp = 32768,
    SizingStretchSame = 65536,
    NoHostExtendX = 131072,
    NoHostExtendY = 262144,
    NoKeepColumnsVisible = 524288,
    PreciseWidths = 1048576,
    NoClip = 2097152,
    PadOuterX = 4194304,
    NoPadOuterX = 8388608,
    NoPadInnerX = 16777216,
    ScrollX = 33554432,
    ScrollY = 67108864,
    SortMulti = 134217728,
    SortTristate = 268435456,
    HighlightHoveredColumn = 536870912,
}

---@enum ImGuiMouseCursor
ImGuiMouseCursor = {
    None = -1,
    Arrow = 0,
    TextInput = 1,
    ResizeAll = 2,
    ResizeNS = 3,
    ResizeEW = 4,
    ResizeNESW = 5,
    ResizeNWSE = 6,
    Hand = 7,
    Wait = 8,
    Progress = 9,
    NotAllowed = 10,
    COUNT = 11,
}

---@enum ImGuiSliderFlags
ImGuiSliderFlags = {
    None = 0,
    Logarithmic = 1,
    NoRoundToFormat = 2,
    NoInput = 4,
    WrapAround = 8,
    ClampOnInput = 16,
    ClampZeroRange = 32,
    NoSpeedTweaks = 64,
    AlwaysClamp = 128,
}

---@enum ImGuiColorEditFlags
ImGuiColorEditFlags = {
    None = 0,
    NoAlpha = 2,
    NoPicker = 4,
    NoOptions = 8,
    NoSmallPreview = 16,
    NoInputs = 32,
    NoTooltip = 64,
    NoLabel = 128,
    NoSidePreview = 256,
    NoDragDrop = 512,
    NoBorder = 1024,
    AlphaBar = 65536,
    AlphaPreviewHalf = 131072,
    HDR = 262144,
    DisplayRGB = 1048576,
    DisplayHSV = 2097152,
    DisplayHex = 4194304,
    Uint8 = 8388608,
    Float = 16777216,
    PickerHueBar = 33554432,
    PickerHueWheel = 67108864,
    InputRGB = 134217728,
    InputHSV = 268435456,
}

---@enum ImGuiKey
ImGuiKey = {
    None = 0,
    Tab = 512,
    LeftArrow = 513,
    RightArrow = 514,
    UpArrow = 515,
    DownArrow = 516,
    PageUp = 517,
    PageDown = 518,
    Home = 519,
    End = 520,
    Insert = 521,
    Delete = 522,
    Backspace = 523,
    Space = 524,
    Enter = 525,
    Escape = 526,
    LeftCtrl = 527,
    LeftShift = 528,
    LeftAlt = 529,
    LeftSuper = 530,
    RightCtrl = 531,
    RightShift = 532,
    RightAlt = 533,
    RightSuper = 534,
    Menu = 535,
    Key_0 = 536,
    Key_1 = 537,
    Key_2 = 538,
    Key_3 = 539,
    Key_4 = 540,
    Key_5 = 541,
    Key_6 = 542,
    Key_7 = 543,
    Key_8 = 544,
    Key_9 = 545,
    A = 546,
    B = 547,
    C = 548,
    D = 549,
    E = 550,
    F = 551,
    G = 552,
    H = 553,
    I = 554,
    J = 555,
    K = 556,
    L = 557,
    M = 558,
    N = 559,
    O = 560,
    P = 561,
    Q = 562,
    R = 563,
    S = 564,
    T = 565,
    U = 566,
    V = 567,
    W = 568,
    X = 569,
    Y = 570,
    Z = 571,
    F1 = 572,
    F2 = 573,
    F3 = 574,
    F4 = 575,
    F5 = 576,
    F6 = 577,
    F7 = 578,
    F8 = 579,
    F9 = 580,
    F10 = 581,
    F11 = 582,
    F12 = 583,
    Apostrophe = 584,
    Comma = 585,
    Minus = 586,
    Period = 587,
    Slash = 588,
    Semicolon = 589,
    Equal = 590,
    LeftBracket = 591,
    Backslash = 592,
    RightBracket = 593,
    GraveAccent = 594,
    CapsLock = 595,
    ScrollLock = 596,
    NumLock = 597,
    PrintScreen = 598,
    Pause = 599,
    Keypad0 = 600,
    Keypad1 = 601,
    Keypad2 = 602,
    Keypad3 = 603,
    Keypad4 = 604,
    Keypad5 = 605,
    Keypad6 = 606,
    Keypad7 = 607,
    Keypad8 = 608,
    Keypad9 = 609,
    KeypadDecimal = 610,
    KeypadDivide = 611,
    KeypadMultiply = 612,
    KeypadSubtract = 613,
    KeypadAdd = 614,
    KeypadEnter = 615,
    KeypadEqual = 616,
    MouseLeft = 617,
    MouseRight = 618,
    MouseMiddle = 619,
    MouseX1 = 620,
    MouseX2 = 621,
    MouseWheelX = 622,
    MouseWheelY = 623,
}

---@enum ImGuiDragDropFlags
ImGuiDragDropFlags = {
    None = 0,
    SourceNoPreviewTooltip = 1,
    SourceNoDisableHover = 2,
    SourceNoHoldToOpenOthers = 4,
    SourceAllowNullID = 8,
    SourceExtern = 16,
    PayloadAutoExpire = 32,
    PayloadNoCrossContext = 64,
    PayloadNoCrossProcess = 128,
    AcceptBeforeDelivery = 256,
    AcceptNoDrawDefaultRect = 512,
    AcceptNoPreviewTooltip = 1024,
    AcceptDrawAsHovered = 2048,
    AcceptPeekOnly = 4096,
}

---@enum ImGuiDataType
ImGuiDataType = {
    S8 = 0,
    U8 = 1,
    S16 = 2,
    U16 = 3,
    S32 = 4,
    U32 = 5,
    S64 = 6,
    U64 = 7,
    Float = 8,
    Double = 9,
    Bool = 10,
    String = 11,
    COUNT = 12,
}

---@enum ImGuiTableColumnFlags
ImGuiTableColumnFlags = {
    None = 0,
    Disabled = 1,
    DefaultHide = 2,
    DefaultSort = 4,
    WidthStretch = 8,
    WidthFixed = 16,
    NoResize = 32,
    NoReorder = 64,
    NoHide = 128,
    NoClip = 256,
    NoSort = 512,
    NoHeaderLabel = 1024,
    PreferSortAscending = 2048,
    PreferSortDescending = 4096,
    IndentEnable = 8192,
    IndentDisable = 16384,
    IsEnabled = 1048576,
    IsVisible = 2097152,
    IsSorted = 4194304,
    IsHovered = 8388608,
}

---@enum ImGuiTableBgTarget
ImGuiTableBgTarget = {
    None = 0,
    RowBg0 = 1,
    RowBg1 = 2,
    CellBg = 3,
}

---@enum ImDrawFlags
ImDrawFlags = {
    None = 0,
    Closed = 1,
    RoundCornersTopLeft = 2,
    RoundCornersTopRight = 4,
    RoundCornersBottomLeft = 8,
    RoundCornersBottomRight = 16,
    RoundCornersNone = 32,
    RoundCornersTop = 6,
    RoundCornersBottom = 24,
    RoundCornersLeft = 10,
    RoundCornersRight = 20,
    RoundCornersAll = 30,
}

---@class ImGui
---@field GetIO fun(): ImGuiIO
---@field GetStyle fun(): ImGuiStyle
---@field ShowDemoWindow fun(show?: boolean): boolean?
---@field ShowMetricsWindow fun(show?: boolean): boolean?
---@field ShowDebugLogWindow fun(show?: boolean): boolean?
---@field ShowIDStackToolWindow fun(show?: boolean): boolean?
---@field ShowAboutWindow fun(show?: boolean): boolean?
---@field ShowStyleEditor fun(ref?: ImGuiStyle): nil
---@field ShowStyleSelector fun(label: string): boolean
---@field ShowFontSelector fun(label: string): nil
---@field ShowUserGuide fun(): nil
---@field GetVersion fun(): string
---@field StyleColorsDark fun(): ImGuiStyle
---@field StyleColorsLight fun(): ImGuiStyle
---@field StyleColorsClassic fun(): ImGuiStyle
---@field Begin fun(name: string, open?: boolean, flags?: number): boolean, boolean
---@field End fun(): nil
---@field BeginChild fun(str_id: string, size_x?: number, size_y?: number, child_flags?: number, flags?: number): boolean
---@field BeginChild fun(str_id: string, size: ImVec2, child_flags?: number, flags?: number): boolean
---@field EndChild fun(): nil
---@field IsWindowAppearing fun(): boolean
---@field IsWindowCollapsed fun(): boolean
---@field IsWindowFocused fun(flags?: number): boolean
---@field IsWindowHovered fun(flags?: number): boolean
---@field GetWindowDrawList fun(): ImDrawList
---@field GetWindowDpiScale fun(): number
---@field GetWindowPos fun(): number, number
---@field GetWindowPosVec fun(): ImVec2
---@field GetWindowSize fun(): number, number
---@field GetWindowSizeVec fun(): ImVec2
---@field GetWindowWidth fun(): number
---@field GetWindowHeight fun(): number
---@field GetWindowViewport fun(): ImGuiViewport
---@field SetNextWindowPos fun(pos_x: number, pos_y: number, cond?: number, pivot_x?: number, pivot_y?: number): nil
---@field SetNextWindowPos fun(pos: ImVec2, cond?: number, pivot?: ImVec2): nil
---@field SetNextWindowSize fun(size_x: number, size_y: number, cond?: number): nil
---@field SetNextWindowSize fun(size: ImVec2, cond?: number): nil
---@field SetNextWindowContentSize fun(size_x: number, size_y: number): nil
---@field SetNextWindowContentSize fun(size: ImVec2): nil
---@field SetNextWindowCollapsed fun(collapsed: boolean, cond?: number): nil
---@field SetNextWindowFocus fun(): nil
---@field SetNextWindowScroll fun(scroll: ImVec2): nil
---@field SetNextWindowBgAlpha fun(alpha: number): nil
---@field SetNextWindowViewport fun(viewport_id: number): nil
---@field SetWindowPos fun(pos_x: number, pos_y: number, cond?: number): nil
---@field SetWindowPos fun(pos: ImVec2, cond?: number): nil
---@field SetWindowPos fun(name: string, pos_x: number, pos_y: number, cond?: number): nil
---@field SetWindowPos fun(name: string, pos: ImVec2, cond?: number): nil
---@field SetWindowSize fun(size_x: number, size_y: number, cond?: number): nil
---@field SetWindowSize fun(name: string, size_x: number, size_y: number, cond?: number): nil
---@field SetWindowSize fun(size: ImVec2, cond?: number): nil
---@field SetWindowSize fun(name: string, size: ImVec2, cond?: number): nil
---@field SetWindowCollapsed fun(collapsed: boolean, cond?: number): nil
---@field SetWindowCollapsed fun(name: string, collapsed: boolean, cond?: number): nil
---@field SetWindowFocus fun(name?: string): nil
---@field GetContentRegionAvail fun(): number, number
---@field GetContentRegionAvailVec fun(): ImVec2
---@field GetContentRegionMax fun(): number, number
---@field GetContentRegionMaxVec fun(): ImVec2
---@field GetWindowContentRegionMin fun(): number, number
---@field GetWindowContentRegionMinVec fun(): ImVec2
---@field GetWindowContentRegionMax fun(): number, number
---@field GetWindowContentRegionMaxVec fun(): ImVec2
---@field GetWindowContentRegionWidth fun(): number
---@field GetScrollX fun(): number
---@field GetScrollY fun(): number
---@field SetScrollX fun(scroll_x: number): nil
---@field SetScrollY fun(scroll_y: number): nil
---@field GetScrollMaxX fun(): number
---@field GetScrollMaxY fun(): number
---@field SetScrollHereX fun(center_x_ratio?: number): nil
---@field SetScrollHereY fun(center_y_ratio?: number): nil
---@field PushFont fun(font?: ImFont, font_size?: number): nil
---@field PopFont fun(): nil
---@field GetFont fun(): ImFont
---@field GetFontSize fun(): number
---@field PushStyleColor fun(idx: number, col: number): nil
---@field PushStyleColor fun(idx: number, colR: number, colG: number, colB: number, colA: number): nil
---@field PushStyleColor fun(idx: number, col: ImVec4): nil
---@field PushStyleColor fun(idx: number, col: number[]): nil
---@field PopStyleColor fun(count?: number): nil
---@field PushStyleVar fun(idx: number, val: number): nil
---@field PushStyleVar fun(idx: number, val_x: number, val_y: number): nil
---@field PushStyleVar fun(idx: number, val: ImVec2): nil
---@field PushStyleVarX fun(idx: number, val_x: number): nil
---@field PushStyleVarY fun(idx: number, val_y: number): nil
---@field PopStyleVar fun(count?: number): nil
---@field PushItemFlag fun(flag: number, enabled: boolean): nil
---@field PopItemFlag fun(): nil
---@field PushItemWidth fun(width: number): nil
---@field PopItemWidth fun(): nil
---@field SetNextItemWidth fun(width: number): nil
---@field CalcItemWidth fun(): number
---@field PushTextWrapPos fun(wrap_local_pos_x?: number): nil
---@field PopTextWrapPos fun(): nil
---@field GetFontTexUvWhitePixel fun(): ImVec2
---@field GetColorU32 fun(idx: number, alpha_mul?: number): number
---@field GetColorU32 fun(colR: number, colG: number, colB: number, colA: number): number
---@field GetColorU32 fun(col: ImVec4): number
---@field GetColorU32 fun(col: number): number
---@field GetStyleColor fun(idx: number): number, number, number, number
---@field GetStyleColorVec4 fun(idx: number): ImVec4
---@field GetCursorScreenPos fun(): number, number
---@field GetCursorScreenPosVec fun(): ImVec2
---@field SetCursorScreenPos fun(pos_x: number, pos_y: number): nil
---@field SetCursorScreenPos fun(pos: ImVec2): nil
---@field GetCursorPos fun(): number, number
---@field GetCursorPosVec fun(): ImVec2
---@field GetCursorPosX fun(): number
---@field GetCursorPosY fun(): number
---@field SetCursorPos fun(pos_x: number, pos_y: number): nil
---@field SetCursorPos fun(pos: ImVec2): nil
---@field SetCursorPosX fun(x: number): nil
---@field SetCursorPosY fun(y: number): nil
---@field GetCursorStartPos fun(): number, number
---@field GetCursorStartPosVec fun(): ImVec2
---@field Separator fun(): nil
---@field SameLine fun(offset_from_start_x?: number, spacing?: number): nil
---@field NewLine fun(): nil
---@field Spacing fun(): nil
---@field Dummy fun(size_x: number, size_y: number): nil
---@field Dummy fun(size: ImVec2): nil
---@field Indent fun(indent_w?: number): nil
---@field Unindent fun(indent_w?: number): nil
---@field BeginGroup fun(): nil
---@field EndGroup fun(): nil
---@field AlignTextToFramePadding fun(): nil
---@field GetTextLineHeight fun(): number
---@field GetTextLineHeightWithSpacing fun(): number
---@field GetFrameHeight fun(): number
---@field GetFrameHeightWithSpacing fun(): number
---@field PushID fun(str_id: string): nil
---@field PushID fun(int_id: number): nil
---@field PushID fun(obj: any): nil
---@field PopID fun(): nil
---@field GetID fun(str_id: string): number
---@field GetID fun(int_id: number): number
---@field GetID fun(obj: any): number
---@field BeginTooltip fun(): nil
---@field EndTooltip fun(): nil
---@field SetTooltip fun(fmt: string, ...: any): nil
---@field BeginItemTooltip fun(): nil
---@field SetItemTooltip fun(fmt: string, ...: any): nil
---@field BeginPopup fun(str_id: string, flags?: number): boolean
---@field BeginPopupModal fun(name: string, open?: boolean, flags?: number): boolean, boolean
---@field EndPopup fun(): nil
---@field OpenPopup fun(str_id: string, popup_flags?: number): nil
---@field OpenPopupOnItemClick fun(str_id?: string, popup_flags?: number): nil
---@field CloseCurrentPopup fun(): nil
---@field BeginPopupContextItem fun(str_id?: string, popup_flags?: number): boolean
---@field BeginPopupContextWindow fun(str_id?: string, popup_flags?: number): boolean
---@field BeginPopupContextVoid fun(str_id?: string, popup_flags?: number): boolean
---@field IsPopupOpen fun(str_id: string, flags?: number): boolean
---@field BeginTable fun(str_id: string, column: number, flags?: number, outer_size?: ImVec2, inner_width?: number): boolean
---@field EndTable fun(): nil
---@field TableNextRow fun(flags?: number, min_row_height?: number): nil
---@field TableNextColumn fun(): boolean
---@field TableSetColumnIndex fun(column_n: number): boolean
---@field TableSetupColumn fun(label: string, flags?: number, init_width_or_weight?: number, user_id?: number): nil
---@field TableSetupScrollFreeze fun(cols: number, rows: number): nil
---@field TableHeader fun(label: string): nil
---@field TableHeadersRow fun(): nil
---@field TableAngledHeadersRow fun(): nil
---@field TableGetSortSpecs fun(): ImGuiTableSortSpecs?
---@field TableGetColumnCount fun(): number
---@field TableGetColumnIndex fun(): number
---@field TableGetRowIndex fun(): number
---@field TableGetColumnName fun(column_n?: number): string
---@field TableGetColumnFlags fun(column_n?: number): number
---@field TableSetColumnEnabled fun(column_n: number, v: boolean): nil
---@field TableGetHoveredColumn fun(): number
---@field TableSetBgColor fun(target: number, color: ImVec4, column_n?: number): nil
---@field TableSetBgColor fun(target: number, colorR: number, colorG: number, colorB: number, colorA: number, column_n?: number): nil
---@field TableSetBgColor fun(target: number, color: number, column_n?: number): nil
---@field TableGetColumnIsVisible fun(column_n?: number): boolean
---@field TableGetColumnIsSorted fun(column_n?: number): boolean
---@field Columns fun(count?: number, id?: string, border?: boolean): nil
---@field NextColumn fun(): nil
---@field GetColumnIndex fun(): number
---@field GetColumnWidth fun(column_index?: number): number
---@field SetColumnWidth fun(column_index: number, width: number): nil
---@field GetColumnOffset fun(column_index?: number): number
---@field SetColumnOffset fun(column_index: number, offset_x: number): nil
---@field GetColumnsCount fun(): number
---@field BeginTabBar fun(str_id: string, flags?: number): boolean
---@field EndTabBar fun(): nil
---@field BeginTabItem fun(label: string, open?: boolean, flags?: number): boolean, boolean
---@field EndTabItem fun(): nil
---@field TabItemButton fun(label: string, flags?: number): boolean
---@field SetTabItemClosed fun(tab_or_docked_window_label: string): nil
---@field DockSpace fun(id: number, size?: ImVec2, flags?: number, window_class?: ImGuiWindowClass): number
---@field DockSpaceOverViewport fun(viewport?: ImGuiViewport, flags?: number, window_class?: ImGuiWindowClass): number
---@field SetNextWindowDockID fun(dock_id: number, cond?: number): nil
---@field SetNextWindowClass fun(window_class: ImGuiWindowClass): nil
---@field GetWindowDockID fun(): number
---@field IsWindowDocked fun(): boolean
---@field BeginDisabled fun(disabled?: boolean): nil
---@field EndDisabled fun(): nil
---@field PushClipRect fun(min_x: number, min_y: number, max_x: number, max_y: number, intersect_current: boolean): nil
---@field PushClipRect fun(clip_rect_min: ImVec2, clip_rect_max: ImVec2, intersect_with_current_clip_rect: boolean): nil
---@field PopClipRect fun(): nil
---@field SetItemDefaultFocus fun(): nil
---@field SetKeyboardFocusHere fun(offset?: number): nil
---@field SetNavCursorVisible fun(visible: boolean): nil
---@field SetNextItemAllowOverlap fun(): nil
---@field IsItemHovered fun(flags?: number): boolean
---@field IsItemActive fun(): boolean
---@field IsItemFocused fun(): boolean
---@field IsItemClicked fun(mouse_button?: number): boolean
---@field IsItemVisible fun(): boolean
---@field IsItemEdited fun(): boolean
---@field IsItemActivated fun(): boolean
---@field IsItemDeactivated fun(): boolean
---@field IsItemDeactivatedAfterEdit fun(): boolean
---@field IsItemToggledOpen fun(): boolean
---@field IsAnyItemHovered fun(): boolean
---@field IsAnyItemActive fun(): boolean
---@field IsAnyItemFocused fun(): boolean
---@field GetItemID fun(): number
---@field GetItemRectMin fun(): number, number
---@field GetItemRectMinVec fun(): ImVec2
---@field GetItemRectMax fun(): number, number
---@field GetItemRectMaxVec fun(): ImVec2
---@field GetItemRectSize fun(): number, number
---@field GetItemRectSizeVec fun(): ImVec2
---@field GetMainViewport fun(): ImGuiViewport
---@field GetBackgroundDrawList fun(): ImDrawList
---@field GetForegroundDrawList fun(viewport?: ImGuiViewport): ImDrawList
---@field IsRectVisible fun(size: ImVec2): boolean
---@field IsRectVisible fun(rect_min: ImVec2, rect_max: ImVec2): boolean
---@field IsRectVisible fun(size_x: number, size_y: number): boolean
---@field IsRectVisible fun(min_x: number, min_y: number, max_x: number, max_y: number): boolean
---@field GetTime fun(): number
---@field GetFrameCount fun(): number
---@field GetStyleColorName fun(idx: number): string
---@field CalcTextSize fun(text: string, hide_text_after_double_hash?: boolean, wrap_width?: number): number, number
---@field CalcTextSizeVec fun(text: string, hide_text_after_double_hash?: boolean, wrap_width?: number): ImVec2
---@field ColorConvertU32ToFloat4 fun(in: number): number[]
---@field ColorConvertFloat4ToU32 fun(rgba: number[]): number
---@field ColorConvertRGBtoHSV fun(r: number, g: number, b: number): number, number, number
---@field ColorConvertHSVtoRGB fun(h: number, s: number, v: number): number, number, number
---@field IsKeyDown fun(key: number): boolean
---@field IsKeyPressed fun(key: number, repeat?: boolean): boolean
---@field IsKeyReleased fun(key: number): boolean
---@field IsKeyChordPressed fun(chord: number): boolean
---@field GetKeyPressedAmount fun(key: number): number
---@field GetKeyName fun(key: number): string
---@field SetNextFrameWantCaptureKeyboard fun(want_capture: boolean): nil
---@field Shortcut fun(key_chord: number, flags?: number): boolean
---@field SetNextItemShortcut fun(key_chord: number, flags?: number): nil
---@field SetItemKeyOwner fun(key: number): nil
---@field IsMouseDown fun(button: number): boolean
---@field IsMouseClicked fun(button: number, repeat?: boolean): boolean
---@field IsMouseReleased fun(button: number): boolean
---@field IsMouseDoubleClicked fun(button: number): boolean
---@field IsMouseDragging fun(button: number, lock_threshold?: number): boolean
---@field GetMouseDragDelta fun(button?: number, lock_threshold?: number): number, number
---@field ResetMouseDragDelta fun(button?: number): nil
---@field GetMouseCursor fun(): number
---@field SetMouseCursor fun(cursor_type: number): nil
---@field SetNextFrameWantCaptureMouse fun(want_capture: boolean): nil
---@field GetMousePos fun(): number, number
---@field GetMousePosVec fun(): ImVec2
---@field IsMouseHoveringRect fun(r_min: ImVec2, r_max: ImVec2, clip?: boolean): boolean
---@field IsMouseHoveringRect fun(min_x: number, min_y: number, max_x: number, max_y: number, clip?: boolean): boolean
---@field GetClipboardText fun(): string
---@field SetClipboardText fun(text: string): nil
---@field BeginDragDropSource fun(flags?: number): boolean
---@field SetDragDropPayload fun(type: string, data: boolean|number|string|number[]|ImVec4, cond?: number): boolean
---@field EndDragDropSource fun(): nil
---@field BeginDragDropTarget fun(): boolean
---@field AcceptDragDropPayload fun(type: string, flags?: number): ImGuiPayload?
---@field EndDragDropTarget fun(): nil
---@field GetDragDropPayload fun(): ImGuiPayload?
--- Text (Widgets)
---@field TextUnformatted fun(text: string): nil
---@field Text fun(text: string): nil
---@field Text fun(fmt: string, ...: any): nil
---@field TextColored fun(r: number, g: number, b: number, a: number, text: string): nil
---@field TextColored fun(r: number, g: number, b: number, a: number, fmt: string, ...: any): nil
---@field TextColored fun(col: number, text: string): nil
---@field TextColored fun(col: ImVec4, text: string): nil
---@field TextDisabled fun(text: string): nil
---@field TextDisabled fun(fmt: string, ...: any): nil
---@field TextWrapped fun(text: string): nil
---@field LabelText fun(label: string, text: string): nil
---@field LabelText fun(label: string, fmt: string, ...: any): nil
---@field BulletText fun(text: string): nil
---@field BulletText fun(fmt: string, ...: any): nil
---@field SeparatorText fun(text: string): nil
--- Main (Widgets) - RETURN (value, pressed) for Checkbox/CheckboxFlags/RadioButton/Selectable
---@field Button fun(label: string, size?: ImVec2): boolean
---@field Button fun(label: string, size_x: number, size_y: number): boolean
---@field SmallButton fun(label: string): boolean
---@field InvisibleButton fun(str_id: string, size_x: number, size_y: number, flags?: number): boolean
---@field InvisibleButton fun(str_id: string, size: ImVec2, flags?: number): boolean
---@field ArrowButton fun(str_id: string, dir: number): boolean
---@field Checkbox fun(label: string, v: boolean): boolean, boolean
---@field CheckboxFlags fun(label: string, flags: number, flags_value: number): number, boolean
---@field RadioButton fun(label: string, active: boolean): boolean
---@field RadioButton fun(label: string, v: number, v_button: number): number, boolean
---@field ProgressBar fun(fraction: number, size?: ImVec2, overlay?: string): nil
---@field ProgressBar fun(fraction: number, size_x: number, size_y: number, overlay?: string): nil
---@field Bullet fun(): nil
---@field TextLink fun(text: string): nil
---@field TextLinkOpenURL fun(text: string, url?: string): nil
--- Combo - RETURNS (current_item_1based, clicked)
---@field BeginCombo fun(label: string, preview_value: string, flags?: number): boolean
---@field EndCombo fun(): nil
---@field Combo fun(label: string, current_item: number, items_separated_by_zeros: string, popup_max_height?: number): number, boolean
---@field Combo fun(label: string, current_item: number, items: string[], items_count?: number, popup_max_height?: number): number, boolean
---@field Combo fun(label: string, current_item: number, getter: function, items_count: number, popup_max_height: number|nil): number, boolean
--- Drags - RETURN (value(s), changed)
---@field DragFloat fun(label: string, v: number, v_speed?: number, v_min?: number, v_max?: number, format?: string, flags?: number): number, boolean
---@field DragFloat2 fun(label: string, v: number[], v_speed?: number, v_min?: number, v_max?: number, format?: string, flags?: number): number[], boolean
---@field DragFloat3 fun(label: string, v: number[], v_speed?: number, v_min?: number, v_max?: number, format?: string, flags?: number): number[], boolean
---@field DragFloat4 fun(label: string, v: number[], v_speed?: number, v_min?: number, v_max?: number, format?: string, flags?: number): number[], boolean
---@field DragFloatRange2 fun(label: string, v_current_min: number, v_current_max: number, v_speed?: number, v_min?: number, v_max?: number, format?: string, format_max?: string, flags?: number): number, number, boolean
---@field DragInt fun(label: string, v: number, v_speed?: number, v_min?: number, v_max?: number, format?: string, flags?: number): number, boolean
---@field DragInt2 fun(label: string, v: number[], v_speed?: number, v_min?: number, v_max?: number, format?: string, flags?: number): number[], boolean
---@field DragInt3 fun(label: string, v: number[], v_speed?: number, v_min?: number, v_max?: number, format?: string, flags?: number): number[], boolean
---@field DragInt4 fun(label: string, v: number[], v_speed?: number, v_min?: number, v_max?: number, format?: string, flags?: number): number[], boolean
---@field DragIntRange2 fun(label: string, v_current_min: number, v_current_max: number, v_speed?: number, v_min?: number, v_max?: number, format?: string, format_max?: string, flags?: number): number, number, boolean
---@field DragScalarN fun(label: string, data_type: number, data: table, components: number, v_speed?: number, p_min?: number, p_max?: number, format?: string, flags?: number): table, boolean
--- Sliders - RETURN (value(s), changed)
---@field SliderFloat fun(label: string, v: number, v_min?: number, v_max?: number, format?: string, flags?: number): number, boolean
---@field SliderFloat2 fun(label: string, v: number[], v_min: number, v_max: number, format?: string, flags?: number): number[], boolean
---@field SliderFloatVec2 fun(label: string, value: ImVec2, v_min: number, v_max: number, format?: string, flags?: number): ImVec2, boolean
---@field SliderFloat3 fun(label: string, v: number[], v_min: number, v_max: number, format?: string, flags?: number): number[], boolean
---@field SliderFloat4 fun(label: string, v: number[], v_min: number, v_max: number, format?: string, flags?: number): number[], boolean
---@field SliderFloatVec4 fun(label: string, value: ImVec4, v_min: number, v_max: number, format?: string, flags?: number): ImVec4, boolean
---@field SliderAngle fun(label: string, v_rad: number, v_degrees_min?: number, v_degrees_max?: number, format?: string, flags?: number): number, boolean
---@field SliderInt fun(label: string, v: number, v_min?: number, v_max?: number, format?: string, flags?: number): number, boolean
---@field SliderInt2 fun(label: string, v: number[], v_min?: number, v_max?: number, format?: string, flags?: number): number[], boolean
---@field SliderInt3 fun(label: string, v: number[], v_min?: number, v_max?: number, format?: string, flags?: number): number[], boolean
---@field SliderInt4 fun(label: string, v: number[], v_min?: number, v_max?: number, format?: string, flags?: number): number[], boolean
---@field VSliderFloat fun(label: string, size: ImVec2, value: number, v_min: number, v_max: number, format?: string, flags?: number): number, boolean
---@field VSliderFloat fun(label: string, size_x: number, size_y: number, value: number, v_min: number, v_max: number, format?: string, flags?: number): number, boolean
---@field VSliderInt fun(label: string, size: ImVec2, value: number, v_min: number, v_max: number, format?: string, flags?: number): number, boolean
---@field VSliderInt fun(label: string, size_x: number, size_y: number, value: number, v_min: number, v_max: number, format?: string, flags?: number): number, boolean
--- Input - RETURN (text/value(s), changed)
---@field InputText fun(label: string, text: string, flags?: number, callback?: function): string, boolean
---@field InputTextMultiline fun(label: string, text: string, size_x: number, size_y: number, flags?: number, callback?: function): string, boolean
---@field InputTextMultiline fun(label: string, text: string, size?: ImVec2, flags?: number, callback?: function): string, boolean
---@field InputTextWithHint fun(label: string, hint: string, text: string, flags?: number, callback?: function): string, boolean
---@field InputFloat fun(label: string, value: number, step?: number, step_fast?: number, format?: string, flags?: number): number, boolean
---@field InputFloat2 fun(label: string, v: number[], format?: string, flags?: number): number[], boolean
---@field InputFloat3 fun(label: string, v: number[], format?: string, flags?: number): number[], boolean
---@field InputFloat4 fun(label: string, v: number[], format?: string, flags?: number): number[], boolean
---@field InputInt fun(label: string, value: number, step?: number, step_fast?: number, flags?: number): number, boolean
---@field InputInt2 fun(label: string, v: number[], flags?: number): number[], boolean
---@field InputInt3 fun(label: string, v: number[], flags?: number): number[], boolean
---@field InputInt4 fun(label: string, v: number[], flags?: number): number[], boolean
---@field InputDouble fun(label: string, value: number, step?: number, step_fast?: number, format?: string, flags?: number): number, boolean
--- Color - RETURN (color, changed)
---@field ColorEdit3 fun(label: string, col: ImVec4|number[], flags?: number): ImVec4|number[], boolean
---@field ColorEdit4 fun(label: string, col: ImVec4|number[], flags?: number): ImVec4|number[], boolean
---@field ColorPicker3 fun(label: string, col: ImVec4|number[], flags?: number): ImVec4|number[], boolean
---@field ColorPicker4 fun(label: string, col: ImVec4|number[], flags?: number): ImVec4|number[], boolean
---@field ColorButton fun(desc_id: string, color: ImVec4|number[]|number, flags?: number, size?: ImVec2): boolean
---@field SetColorEditOptions fun(flags: number): nil
--- Trees
---@field TreeNode fun(label: string): boolean
---@field TreeNode fun(str_id: string, fmt: string, ...: any): boolean
---@field TreeNodeEx fun(label: string, flags?: number): boolean
---@field TreeNodeEx fun(str_id: string, flags: number, fmt: string, ...: any): boolean
---@field TreePush fun(str_id?: string): nil
---@field TreePush fun(obj: any): nil
---@field TreePop fun(): nil
---@field GetTreeNodeToLabelSpacing fun(): number
---@field CollapsingHeader fun(label: string, flags?: number): boolean
---@field CollapsingHeader fun(label: string, open?: boolean, flags?: number): boolean, boolean
---@field SetNextItemOpen fun(is_open: boolean, cond?: number): nil
---@field TreeAdvanceToLabelPos fun(): nil
--- Selectable - RETURN (selected, pressed)
---@field Selectable fun(label: string, selected?: boolean, flags?: number, size?: ImVec2): boolean, boolean
---@field Selectable fun(label: string, selected: boolean, flags: number, size_x: number, size_y: number): boolean, boolean
--- ListBox - RETURN (current_item_1based, changed)
---@field BeginListBox fun(label: string, size?: ImVec2): boolean
---@field EndListBox fun(): nil
---@field ListBox fun(label: string, current_item: number, items: string[], items_count?: number, height_in_items?: number): number, boolean
---@field ListBox fun(label: string, current_item: number, getter: function, items_count: number, height_in_items: number|nil): number, boolean
--- Plot
---@field PlotLines fun(label: string, values: number[], values_count: number|nil, values_offset: number|nil, overlay_text: string|nil, scale_min: number|nil, scale_max: number|nil, graph_size: ImVec2|nil): nil
---@field PlotLines fun(label: string, getter: function, values_count: number, values_offset: number|nil, overlay_text: string|nil, scale_min: number|nil, scale_max: number|nil, graph_size: ImVec2|nil): nil
---@field PlotHistogram fun(label: string, values: number[], values_count: number|nil, values_offset: number|nil, overlay_text: string|nil, scale_min: number|nil, scale_max: number|nil, graph_size: ImVec2|nil): nil
---@field PlotHistogram fun(label: string, getter: function, values_count: number, values_offset: number|nil, overlay_text: string|nil, scale_min: number|nil, scale_max: number|nil, graph_size: ImVec2|nil): nil
---@field Value fun(prefix: string, b: boolean): nil
---@field Value fun(prefix: string, v: number): nil
---@field Value fun(prefix: string, v: number, float_format?: string): nil
--- Menu - MenuItem RETURNS (activated, selected_or_activated)
---@field BeginMenuBar fun(): boolean
---@field EndMenuBar fun(): nil
---@field BeginMainMenuBar fun(): boolean
---@field EndMainMenuBar fun(): nil
---@field BeginMenu fun(label: string, enabled?: boolean): boolean
---@field EndMenu fun(): nil
---@field MenuItem fun(label: string, shortcut?: string, selected?: boolean, enabled?: boolean): boolean, boolean
--- Images (MQ may use ImTextureRef / CTextureAnimation)
---@field Image fun(tex_ref: userdata, image_size: ImVec2, uv0?: ImVec2, uv1?: ImVec2): nil
---@field ImageWithBg fun(tex_ref: userdata, image_size: ImVec2, uv0?: ImVec2, uv1?: ImVec2, bg_col?: ImVec4, tint_col?: ImVec4): nil
---@field ImageButton fun(str_id: string, tex_ref: userdata, image_size: ImVec2, uv0?: ImVec2, uv1?: ImVec2, bg_col?: ImVec4, tint_col?: ImVec4): boolean
--- MQ Custom
---@field Register fun(name: string, callback: function): nil
---@field Unregister fun(name: string): nil
---@field DrawTextureAnimation fun(anim: userdata, size: ImVec2, tint_color?: number, border_color?: number): nil
---@field DrawTextureAnimation fun(anim: userdata, size: ImVec2, draw_border: boolean): nil
---@field DrawTextureAnimation fun(anim: userdata, x: number, y: number, draw_border?: boolean): nil
---@field DrawTextureAnimation fun(anim: userdata): nil
---@field HelpMarker fun(text: string, width?: number, font?: ImFont): nil
---@field ConsoleWidget ConsoleWidget
---@field ConsoleFont userdata

--- Constructors provided by MacroQuest at runtime (ImVec2(x, y), ImVec4(x, y, z, w)).
---@type fun(x?: number, y?: number): ImVec2
ImVec2 = ImVec2 or function() end

---@type fun(x?: number, y?: number, z?: number, w?: number): ImVec4
ImVec4 = ImVec4 or function() end

--- Global ImGui table provided by MacroQuest at runtime.
---@type ImGui
ImGui = ImGui or {}
