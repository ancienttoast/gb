import
  nimgl/imgui



proc styleVGui*() =
  # https://github.com/ocornut/imgui/issues/707#issuecomment-576867100
  const ImVec4 = proc(x: float32, y: float32, z: float32, w: float32): ImVec4 = ImVec4(x: w, y: x, z: y, w: z)

  let
    style = igGetStyle()
  style.colors[ImGuiCol.Text.int32]                  = ImVec4(1.00f, 1.00f, 1.00f, 1.00f)
  style.colors[ImGuiCol.TextDisabled.int32]          = ImVec4(0.50f, 0.50f, 0.50f, 1.00f)
  style.colors[ImGuiCol.WindowBg.int32]              = ImVec4(0.29f, 0.34f, 0.26f, 1.00f)
  style.colors[ImGuiCol.ChildBg.int32]               = ImVec4(0.29f, 0.34f, 0.26f, 1.00f)
  style.colors[ImGuiCol.PopupBg.int32]               = ImVec4(0.24f, 0.27f, 0.20f, 1.00f)
  style.colors[ImGuiCol.Border.int32]                = ImVec4(0.54f, 0.57f, 0.51f, 0.50f)
  style.colors[ImGuiCol.BorderShadow.int32]          = ImVec4(0.14f, 0.16f, 0.11f, 0.52f)
  style.colors[ImGuiCol.FrameBg.int32]               = ImVec4(0.24f, 0.27f, 0.20f, 1.00f)
  style.colors[ImGuiCol.FrameBgHovered.int32]        = ImVec4(0.27f, 0.30f, 0.23f, 1.00f)
  style.colors[ImGuiCol.FrameBgActive.int32]         = ImVec4(0.30f, 0.34f, 0.26f, 1.00f)
  style.colors[ImGuiCol.TitleBg.int32]               = ImVec4(0.24f, 0.27f, 0.20f, 1.00f)
  style.colors[ImGuiCol.TitleBgActive.int32]         = ImVec4(0.29f, 0.34f, 0.26f, 1.00f)
  style.colors[ImGuiCol.TitleBgCollapsed.int32]      = ImVec4(0.00f, 0.00f, 0.00f, 1.00f)
  style.colors[ImGuiCol.MenuBarBg.int32]             = ImVec4(0.24f, 0.27f, 0.20f, 1.00f)
  style.colors[ImGuiCol.ScrollbarBg.int32]           = ImVec4(0.35f, 0.42f, 0.31f, 1.00f)
  style.colors[ImGuiCol.ScrollbarGrab.int32]         = ImVec4(0.28f, 0.32f, 0.24f, 1.00f)
  style.colors[ImGuiCol.ScrollbarGrabHovered.int32]  = ImVec4(0.25f, 0.30f, 0.22f, 1.00f)
  style.colors[ImGuiCol.ScrollbarGrabActive.int32]   = ImVec4(0.23f, 0.27f, 0.21f, 1.00f)
  style.colors[ImGuiCol.CheckMark.int32]             = ImVec4(0.59f, 0.54f, 0.18f, 1.00f)
  style.colors[ImGuiCol.SliderGrab.int32]            = ImVec4(0.35f, 0.42f, 0.31f, 1.00f)
  style.colors[ImGuiCol.SliderGrabActive.int32]      = ImVec4(0.54f, 0.57f, 0.51f, 0.50f)
  style.colors[ImGuiCol.Button.int32]                = ImVec4(0.29f, 0.34f, 0.26f, 0.40f)
  style.colors[ImGuiCol.ButtonHovered.int32]         = ImVec4(0.35f, 0.42f, 0.31f, 1.00f)
  style.colors[ImGuiCol.ButtonActive.int32]          = ImVec4(0.54f, 0.57f, 0.51f, 0.50f)
  style.colors[ImGuiCol.Header.int32]                = ImVec4(0.35f, 0.42f, 0.31f, 1.00f)
  style.colors[ImGuiCol.HeaderHovered.int32]         = ImVec4(0.35f, 0.42f, 0.31f, 0.60f)
  style.colors[ImGuiCol.HeaderActive.int32]          = ImVec4(0.54f, 0.57f, 0.51f, 0.50f)
  style.colors[ImGuiCol.Separator.int32]             = ImVec4(0.14f, 0.16f, 0.11f, 1.00f)
  style.colors[ImGuiCol.SeparatorHovered.int32]      = ImVec4(0.54f, 0.57f, 0.51f, 1.00f)
  style.colors[ImGuiCol.SeparatorActive.int32]       = ImVec4(0.59f, 0.54f, 0.18f, 1.00f)
  style.colors[ImGuiCol.ResizeGrip.int32]            = ImVec4(0.19f, 0.23f, 0.18f, 0.00f) # grip invis
  style.colors[ImGuiCol.ResizeGripHovered.int32]     = ImVec4(0.54f, 0.57f, 0.51f, 1.00f)
  style.colors[ImGuiCol.ResizeGripActive.int32]      = ImVec4(0.59f, 0.54f, 0.18f, 1.00f)
  style.colors[ImGuiCol.Tab.int32]                   = ImVec4(0.35f, 0.42f, 0.31f, 1.00f)
  style.colors[ImGuiCol.TabHovered.int32]            = ImVec4(0.54f, 0.57f, 0.51f, 0.78f)
  style.colors[ImGuiCol.TabActive.int32]             = ImVec4(0.59f, 0.54f, 0.18f, 1.00f)
  style.colors[ImGuiCol.TabUnfocused.int32]          = ImVec4(0.24f, 0.27f, 0.20f, 1.00f)
  style.colors[ImGuiCol.TabUnfocusedActive.int32]    = ImVec4(0.35f, 0.42f, 0.31f, 1.00f)
  style.colors[ImGuiCol.PlotLines.int32]             = ImVec4(0.61f, 0.61f, 0.61f, 1.00f)
  style.colors[ImGuiCol.PlotLinesHovered.int32]      = ImVec4(0.59f, 0.54f, 0.18f, 1.00f)
  style.colors[ImGuiCol.PlotHistogram.int32]         = ImVec4(1.00f, 0.78f, 0.28f, 1.00f)
  style.colors[ImGuiCol.PlotHistogramHovered.int32]  = ImVec4(1.00f, 0.60f, 0.00f, 1.00f)
  style.colors[ImGuiCol.TextSelectedBg.int32]        = ImVec4(0.59f, 0.54f, 0.18f, 1.00f)
  style.colors[ImGuiCol.DragDropTarget.int32]        = ImVec4(0.73f, 0.67f, 0.24f, 1.00f)
  style.colors[ImGuiCol.NavHighlight.int32]          = ImVec4(0.59f, 0.54f, 0.18f, 1.00f)
  style.colors[ImGuiCol.NavWindowingHighlight.int32] = ImVec4(1.00f, 1.00f, 1.00f, 0.70f)
  style.colors[ImGuiCol.NavWindowingDimBg.int32]     = ImVec4(0.80f, 0.80f, 0.80f, 0.20f)
  style.colors[ImGuiCol.ModalWindowDimBg.int32]      = ImVec4(0.80f, 0.80f, 0.80f, 0.35f)

  style.frameBorderSize = 1.0
  style.windowRounding = 0.0
  style.childRounding = 0.0
  style.frameRounding = 0.0
  style.popupRounding = 0.0
  style.scrollbarRounding = 0.0
  style.grabRounding = 0.0
  style.tabRounding = 0.0