import
  std/[os, strformat],
  nimgl/imgui



type
  Item = tuple
    path: string
    name: string
    size: int
    isDir: bool

  FilePopup* = object
    title: string
    basePath: string
    isVisible*: bool
    selection: int
    currentPath: Item
    filesInScope: seq[Item]

template `or`(a, b: ImGuiWindowFlags): ImGuiWindowFlags =
  (a.int32 or b.int32).ImGuiWindowFlags

proc printSize(sizeB: int): string =
  const
    Multiplier = 1024
    Units = ["B", "KiB", "MiB", "GiB", "TiB"]
  var
    current = sizeB.float
  for unit in Units:
    if current < Multiplier:
      return &"{current:<.3f}{unit}"
    current = current / Multiplier

proc get_files_in_path(path: string): seq[Item] =
  result = newSeq[Item]()
  # TODO: come up with a solution for emscripten
  when not defined(emscripten):
    result &= (path: (path/"..").absolutePath().normalizedPath(), name: "..", size: 0, isDir: true)
    for kind, path in walkDir(path, relative = false):
      result &= (path: path, name: path.lastPathPart(), size: getFileSize(path).int, isDir: path.dirExists())

proc igBeginListBox(label: cstring, items_count: cint, height_in_items: cint): bool =
  # If height_in_items == -1, default height is maximum 7.
  let
    g = igGetCurrentContext()
    height_in_items_f = (if height_in_items < 0: min(items_count, 7).float else: height_in_items.float) + 0.25
    size = ImVec2(
      x: 0,
      y: igGetTextLineHeightWithSpacing() * height_in_items_f + igGetStyle().framePadding.y * 2.0
    )
  return igBeginListBox(label, size)

proc render*(self: var FilePopup, outPath: var string): bool =
  result = false

  let
    wasVisible = self.isVisible
  if self.isVisible:
    igOpenPopup(self.title)

  const
    ModalFlags =
      ImGuiWindowFlags.NoCollapse or
      ImGuiWindowFlags.NoScrollbar
  igSetNextWindowSize(ImVec2(x: 704, y: 261), FirstUseEver)
  if igBeginPopupModal(self.title, addr self.isVisible, ModalFlags):
    var
      isChanged = false
    igPushItemWidth(-1)
    if igBeginListBox("##", self.filesInScope.len.int32, 10):
      for i, path in self.filesInScope:
        igPushID(path.name)
        if igSelectable("##", i == self.selection):
          self.selection = i
          self.currentPath = self.filesInScope[self.selection]
          isChanged = true
        igSameLine()
        igText(path.name)
        igSameLine(igCalcItemWidth() * 0.9)
        if path.isDir:
          igText("dir")
        else:
          igText(path.size.printSize())
        igPopID()
      igEndListBox()
    igPopItemWidth()
    
    if isChanged and self.currentPath.isDir:
      self.filesInScope = get_files_in_path(self.currentPath.path)

    igPushItemWidth(-1)
    igTextWrapped(self.currentPath.path)
    igPopItemWidth()

    igSpacing()
    igSameLine(igGetWindowWidth() - 120)

    if self.currentPath.isDir:
      let
        DisabledColor = igGetStyle().colors[ImGuiCol.TextDisabled.int32]
      igPushStyleColor(ImGuiCol.Button, DisabledColor)
      igPushStyleColor(ImGuiCol.ButtonActive, DisabledColor)
      igPushStyleColor(ImGuiCol.ButtonHovered, DisabledColor)

      igButton("Select")

      igPopStyleColor()
      igPopStyleColor()
      igPopStyleColor()
    else:
      if igButton("Select"):
        igCloseCurrentPopup()
        self.isVisible = false

        outPath = self.currentPath.path
        result = true
    
    igSameLine()

    if igButton("Cancel"):
      igCloseCurrentPopup()
      self.isVisible = false

    igEndPopup()
  
  if wasVisible and not self.isVisible:
    self.currentPath = (path: self.basePath, name: self.basePath.lastPathPart(), size: 0, isDir: true)
    self.filesInScope = get_files_in_path(self.currentPath.path)

proc initFilePopup*(title: string, basePath = getCurrentDir()): FilePopup =
  FilePopup(
    title: title,
    basePath: basePath,
    isVisible: false,
    selection: 0,
    currentPath: (path: basePath, name: basePath.lastPathPart(), size: 0, isDir: true),
    filesInScope: get_files_in_path(basePath)
  )
