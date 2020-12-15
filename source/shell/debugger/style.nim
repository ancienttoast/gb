import
  nimgl/imgui



func ImVec4(x: float32, y: float32, z: float32, w: float32): ImVec4 = ImVec4(x: x, y: y, z: z, w: w)


proc styleVGui*() =
  # https://github.com/ocornut/imgui/issues/707#issuecomment-576867100
  let
    style = igGetStyle()
  style.colors[ImGuiCol.Text.int32]                  = ImVec4(1.00, 1.00, 1.00, 1.00)
  style.colors[ImGuiCol.TextDisabled.int32]          = ImVec4(0.50, 0.50, 0.50, 1.00)
  style.colors[ImGuiCol.WindowBg.int32]              = ImVec4(0.29, 0.34, 0.26, 1.00)
  style.colors[ImGuiCol.ChildBg.int32]               = ImVec4(0.29, 0.34, 0.26, 1.00)
  style.colors[ImGuiCol.PopupBg.int32]               = ImVec4(0.24, 0.27, 0.20, 1.00)
  style.colors[ImGuiCol.Border.int32]                = ImVec4(0.54, 0.57, 0.51, 0.50)
  style.colors[ImGuiCol.BorderShadow.int32]          = ImVec4(0.14, 0.16, 0.11, 0.52)
  style.colors[ImGuiCol.FrameBg.int32]               = ImVec4(0.24, 0.27, 0.20, 1.00)
  style.colors[ImGuiCol.FrameBgHovered.int32]        = ImVec4(0.27, 0.30, 0.23, 1.00)
  style.colors[ImGuiCol.FrameBgActive.int32]         = ImVec4(0.30, 0.34, 0.26, 1.00)
  style.colors[ImGuiCol.TitleBg.int32]               = ImVec4(0.24, 0.27, 0.20, 1.00)
  style.colors[ImGuiCol.TitleBgActive.int32]         = ImVec4(0.29, 0.34, 0.26, 1.00)
  style.colors[ImGuiCol.TitleBgCollapsed.int32]      = ImVec4(0.00, 0.00, 0.00, 1.00)
  style.colors[ImGuiCol.MenuBarBg.int32]             = ImVec4(0.24, 0.27, 0.20, 1.00)
  style.colors[ImGuiCol.ScrollbarBg.int32]           = ImVec4(0.35, 0.42, 0.31, 1.00)
  style.colors[ImGuiCol.ScrollbarGrab.int32]         = ImVec4(0.28, 0.32, 0.24, 1.00)
  style.colors[ImGuiCol.ScrollbarGrabHovered.int32]  = ImVec4(0.25, 0.30, 0.22, 1.00)
  style.colors[ImGuiCol.ScrollbarGrabActive.int32]   = ImVec4(0.23, 0.27, 0.21, 1.00)
  style.colors[ImGuiCol.CheckMark.int32]             = ImVec4(0.59, 0.54, 0.18, 1.00)
  style.colors[ImGuiCol.SliderGrab.int32]            = ImVec4(0.35, 0.42, 0.31, 1.00)
  style.colors[ImGuiCol.SliderGrabActive.int32]      = ImVec4(0.54, 0.57, 0.51, 0.50)
  style.colors[ImGuiCol.Button.int32]                = ImVec4(0.29, 0.34, 0.26, 0.40)
  style.colors[ImGuiCol.ButtonHovered.int32]         = ImVec4(0.35, 0.42, 0.31, 1.00)
  style.colors[ImGuiCol.ButtonActive.int32]          = ImVec4(0.54, 0.57, 0.51, 0.50)
  style.colors[ImGuiCol.Header.int32]                = ImVec4(0.35, 0.42, 0.31, 1.00)
  style.colors[ImGuiCol.HeaderHovered.int32]         = ImVec4(0.35, 0.42, 0.31, 0.60)
  style.colors[ImGuiCol.HeaderActive.int32]          = ImVec4(0.54, 0.57, 0.51, 0.50)
  style.colors[ImGuiCol.Separator.int32]             = ImVec4(0.14, 0.16, 0.11, 1.00)
  style.colors[ImGuiCol.SeparatorHovered.int32]      = ImVec4(0.54, 0.57, 0.51, 1.00)
  style.colors[ImGuiCol.SeparatorActive.int32]       = ImVec4(0.59, 0.54, 0.18, 1.00)
  style.colors[ImGuiCol.ResizeGrip.int32]            = ImVec4(0.19, 0.23, 0.18, 0.00) # grip invis
  style.colors[ImGuiCol.ResizeGripHovered.int32]     = ImVec4(0.54, 0.57, 0.51, 1.00)
  style.colors[ImGuiCol.ResizeGripActive.int32]      = ImVec4(0.59, 0.54, 0.18, 1.00)
  style.colors[ImGuiCol.Tab.int32]                   = ImVec4(0.35, 0.42, 0.31, 1.00)
  style.colors[ImGuiCol.TabHovered.int32]            = ImVec4(0.54, 0.57, 0.51, 0.78)
  style.colors[ImGuiCol.TabActive.int32]             = ImVec4(0.59, 0.54, 0.18, 1.00)
  style.colors[ImGuiCol.TabUnfocused.int32]          = ImVec4(0.24, 0.27, 0.20, 1.00)
  style.colors[ImGuiCol.TabUnfocusedActive.int32]    = ImVec4(0.35, 0.42, 0.31, 1.00)
  style.colors[ImGuiCol.PlotLines.int32]             = ImVec4(0.61, 0.61, 0.61, 1.00)
  style.colors[ImGuiCol.PlotLinesHovered.int32]      = ImVec4(0.59, 0.54, 0.18, 1.00)
  style.colors[ImGuiCol.PlotHistogram.int32]         = ImVec4(1.00, 0.78, 0.28, 1.00)
  style.colors[ImGuiCol.PlotHistogramHovered.int32]  = ImVec4(1.00, 0.60, 0.00, 1.00)
  style.colors[ImGuiCol.TextSelectedBg.int32]        = ImVec4(0.59, 0.54, 0.18, 1.00)
  style.colors[ImGuiCol.DragDropTarget.int32]        = ImVec4(0.73, 0.67, 0.24, 1.00)
  style.colors[ImGuiCol.NavHighlight.int32]          = ImVec4(0.59, 0.54, 0.18, 1.00)
  style.colors[ImGuiCol.NavWindowingHighlight.int32] = ImVec4(1.00, 1.00, 1.00, 0.70)
  style.colors[ImGuiCol.NavWindowingDimBg.int32]     = ImVec4(0.80, 0.80, 0.80, 0.20)
  style.colors[ImGuiCol.ModalWindowDimBg.int32]      = ImVec4(0.80, 0.80, 0.80, 0.35)

  style.frameBorderSize = 1.0
  style.windowRounding = 0.0
  style.childRounding = 0.0
  style.frameRounding = 0.0
  style.popupRounding = 0.0
  style.scrollbarRounding = 0.0
  style.grabRounding = 0.0
  style.tabRounding = 0.0