import
  nimgl/imgui



func openKeyPopup*(id: string) =
  igOpenPopup(id & "##keyPopup")

proc keyPopup*(id: string): tuple[key: int, isInput: bool] =
  result = (key: 0, isInput: false)
  let
    center = ImVec2(x: igGetIO().displaySize.x * 0.5, y: igGetIO().displaySize.y * 0.5)
  igSetNextWindowPos(center, ImGuiCond.Appearing, ImVec2(x: 0.5, y: 0.5))
  if igBeginPopupModal(id & "##keyPopup", nil, ImGuiWindowFlags.AlwaysAutoResize):
    igText("Press any key.")
    let
      io = igGetIO()
    for key, state in io.keysDown:
      if igIsKeyPressed(key):
        result.key = key
        result.isInput = true
        igCloseCurrentPopup()
        break
    igEndPopup()