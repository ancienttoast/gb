import
  nimgl/imgui



converter imGuiItemFlagsToInt32(value: ImGuiItemFlags): int32 =
  value.int32

template `+`(a, b: ImVec2): ImVec2 =
  ImVec2(x: a.x + b.x, y: a.y + b.y)


func igToggleButton*(label: cstring, v: var bool) =
  let
    window = igGetCurrentWindow()
  if window.skipItems:
    return

  let
    style = igGetStyle()
    id = window.getID(label)
  
  var
    labelSize: ImVec2
  igCalcTextSizeNonUDT(addr labelSize, label, nil, true)

  let
    pos = window.dc.cursorPos
    size = ImVec2(x: igGetFrameHeight(), y: igGetFrameHeight())
    bb = ImRect(min: pos, max: pos + size)
  igItemSize(size, style.framePadding.y)
  if not igItemAdd(bb, id):
    return

  var
    hovered = false
    held = false
  let
    pressed = igButtonBehavior(bb, id, addr hovered, addr held)
  if pressed:
    v = not v

  let
    col = igGetColorU32(if v: ImGuiCol.ButtonActive elif hovered: ImGuiCol.ButtonHovered else: ImGuiCol.Button)
    text_col = igGetColorU32(ImGuiCol.Text)
  igRenderNavHighlight(bb, id)
  igRenderFrame(bb.min, bb.max, col, true, style.frameRounding)
  igRenderArrow(window.drawList, bb.min + ImVec2(x: max(0.0, (size.x - igGetFontSize()) * 0.5), y: max(0.0, (size.y - igGetFontSize()) * 0.5)), text_col, ImGuiDir.Right)


func igButtonArrow*(label: cstring, dir: ImGuiDir): bool =
  const
    ArrowDistance = 7
  let
    window = igGetCurrentWindow()
    style = igGetStyle()

  let
    pos = window.dc.cursorPos
    size = ImVec2(x: igGetFrameHeight() + ArrowDistance, y: igGetFrameHeight())
  
  var
    flags = 0.ImGuiButtonFlags
  if (window.dc.itemFlags and ImGuiItemFlags.ButtonRepeat) == ImGuiItemFlags.ButtonRepeat:
    flags = ImGuiButtonFlagsPrivate.Repeat.ImGuiButtonFlags

  let
    bb = ImRect(min: pos, max: pos + size)
  result = igInvisibleButton(label, size, flags)

  let
    col = igGetColorU32(if result: ImGuiCol.ButtonActive elif igIsItemHovered(): ImGuiCol.ButtonHovered else: ImGuiCol.Button)
    text_col = igGetColorU32(ImGuiCol.Text)
  igRenderFrame(bb.min, bb.max, col, true, style.frameRounding)
  igRenderArrow(window.drawList, bb.min + ImVec2(x: max(0.0, (size.x - igGetFontSize() - ArrowDistance) * 0.5), y: max(0.0, (size.y - igGetFontSize()) * 0.5)), text_col, dir)
  igRenderArrow(window.drawList, ImVec2(x: ArrowDistance, y: 0) + bb.min + ImVec2(x: max(0.0, (size.x - igGetFontSize() - ArrowDistance) * 0.5), y: max(0.0, (size.y - igGetFontSize()) * 0.5)), text_col, dir)
