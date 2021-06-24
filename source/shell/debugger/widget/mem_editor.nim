# Mini memory editor for ImGui (to embed in your game/tools)
# v0.10
# Animated gif: https://cloud.githubusercontent.com/assets/8225057/9028162/3047ef88-392c-11e5-8270-a54f8354b208.gif
#
# You can adjust the keyboard repeat delay/rate in ImGuiIO.
# The code assume a mono-space font for simplicity! If you don't use the default font, use ImGui::PushFont()/PopFont() to switch to a mono-space font before caling this.
#
# Usage:
#   static MemoryEditor memory_editor;                                                     // save your state somewhere
#   memory_editor.Draw("Memory Editor", mem_block, mem_block_size, (size_t)mem_block);     // run
#
# TODO: better resizing policy (ImGui doesn't have flexible window resizing constraints yet)
# From: https://gist.github.com/cmaughan/ce1bfcee3f9947939253
import
  std/[strscans, strformat, streams],
  nimgl/imgui

type
  DataProviderProc = proc(adress: int): uint8
  DataSetterProc = proc(adress: int, value: uint8)

  MemoryEditor* = object
    open*: bool
    allowEdits: bool
    rows: int32
    dataEditingAddr: int
    dataEditingTakeFocus: bool
    dataInput: string
    addrInput: string

proc initMemoryEditor*(): MemoryEditor =
  MemoryEditor(
    rows: 16,
    dataEditingAddr: -1,
    dataEditingTakeFocus: false,
    dataInput: newString(32),
    addrInput: newString(32),
    allowEdits: true
  )

proc saveDump(data_provider: DataProviderProc, mem_size: int) =
  let
    s = newFileStream("memdump.txt", fmWrite)
  var
    i = 0
  for address in 0..<mem_size:
    if i == 0:
      s.write(&"{address:#06x}\t")
    s.write(&"{data_provider(address):02x}")
    i += 1
    if i == 8:
      s.write("\t")
    else:
      s.write(" ")
    if i == 16:
      s.write("\n")
      i = 0
  s.close()

proc get_cursor_pos(data: ptr ImGuiInputTextCallbackData): int32 {.cdecl.} =
  var
    p_cursor_pos = cast[ptr int32](data.userData)
  if not data.hasSelection():
      p_cursor_pos[] = data.cursorPos
  return 0

proc draw*(isOpen: var bool, self: var MemoryEditor, title: string, data_provider: DataProviderProc, data_setter: DataSetterProc, mem_size: int, base_display_addr = 0) =
  if not isOpen:
    return
  if igBegin(title, addr isOpen) and not igIsWindowCollapsed():
    igBeginChild("##scrolling", ImVec2(x: 0, y: -igGetFrameHeightWithSpacing()))

    igPushStyleVar(ImGuiStyleVar.FramePadding, ImVec2(x: 0, y: 0))
    igPushStyleVar(ImGuiStyleVar.ItemSpacing, ImVec2(x: 0, y: 0))

    var
      addr_digits_count = 0
      n = base_display_addr + mem_size - 1
    while n > 0:
      addr_digits_count += 1
      n = n shr 4

    var
      text_size: ImVec2
    igCalcTextSizeNonUDT(addr text_size, "F")
    var
      glyph_width = text_size.x
      cell_width = glyph_width * 3  # "FF " we include trailing space in the width to easily catch clicks everywhere
    
    var
      line_height = igGetTextLineHeight()
      line_total_count = ((mem_size + self.rows-1) / self.rows).int32
      clipper = newImGuiListClipper()
    clipper.begin(line_total_count, line_height)
    clipper.step()

    if not self.allowEdits or self.dataEditingAddr >= mem_size:
      self.dataEditingAddr = -1

    let
      visible_start_addr = clipper.displayStart * self.rows
      visible_end_addr = clipper.displayEnd * self.rows
      data_editing_addr_backup = self.dataEditingAddr
    if self.dataEditingAddr != -1:
      if igIsKeyPressed(igGetKeyIndex(ImGuiKey.UpArrow)) and self.dataEditingAddr >= self.rows:
        self.dataEditingAddr -= self.rows
        self.dataEditingTakeFocus = true
      elif igIsKeyPressed(igGetKeyIndex(ImGuiKey.DownArrow)) and self.dataEditingAddr < mem_size - self.rows:
        self.dataEditingAddr += self.rows
        self.dataEditingTakeFocus = true
      elif igIsKeyPressed(igGetKeyIndex(ImGuiKey.LeftArrow)) and self.dataEditingAddr > 0:
        self.dataEditingAddr -= 1
        self.dataEditingTakeFocus = true
      elif igIsKeyPressed(igGetKeyIndex(ImGuiKey.RightArrow)) and self.dataEditingAddr < mem_size - 1:
        self.dataEditingAddr += 1
        self.dataEditingTakeFocus = true
    if (self.dataEditingAddr / self.rows) != (data_editing_addr_backup / self.rows):
      # Track cursor movements
      let
        scroll_offset = ((self.dataEditingAddr / self.rows) - (data_editing_addr_backup / self.rows)) * line_height
        scroll_desired = (scroll_offset < 0.0 and self.dataEditingAddr < visible_start_addr + self.rows*2) or
          (scroll_offset > 0.0 and self.dataEditingAddr > visible_end_addr - self.rows*2)
      if scroll_desired:
        igSetScrollY(igGetScrollY() + scroll_offset)

    var
      draw_separator = true
      data_next = false
    for line_i in clipper.displayStart..<clipper.displayEnd:  # display only visible items
      var
        address = line_i * self.rows
      igText("%0*X: ", addr_digits_count, base_display_addr+address)
      igSameLine()

      # Draw Hexadecimal
      let
        line_start_x = igGetCursorPosX()
      var n = 0
      while n < self.rows and address < mem_size:
        igSameLine(line_start_x + cell_width * n.float32)

        if self.dataEditingAddr == address:
          # Display text input on current byte
          igPushID(address.int32)
          var
            cursor_pos = -1
            data_write = false
          if self.dataEditingTakeFocus:
            igSetKeyboardFocusHere()
            self.addrInput = newStringOfCap(32)
            self.addrInput.formatValue(base_display_addr+address, "0" & $addr_digits_count & "X")
            self.dataInput = newStringOfCap(32)
            self.dataInput.formatValue(data_provider(address), "02X")
          var
            text_size: ImVec2
          igCalcTextSizeNonUDT(addr text_size, "FF")
          igPushItemWidth(text_size.x)
          let
            flags = cast[ImGuiInputTextFlags](ImGuiInputTextFlags.CharsHexadecimal.int32 or
              ImGuiInputTextFlags.EnterReturnsTrue.int32 or
              ImGuiInputTextFlags.AutoSelectAll.int32 or
              ImGuiInputTextFlags.NoHorizontalScroll.int32 or
              ImGuiInputTextFlags.AlwaysOverwrite.int32 or
              ImGuiInputTextFlags.CallbackAlways.int32)
          if igInputText("##data", self.dataInput, 32, flags, get_cursor_pos, addr cursor_pos):
            data_write = true
            data_next = true
          elif not self.dataEditingTakeFocus and not igIsItemActive():
            self.dataEditingAddr = -1
          self.dataEditingTakeFocus = false
          igPopItemWidth()
          if cursor_pos >= 2:
            data_write = true
            data_next = true
          if data_write:
            var
              data: int
            if scanf(self.dataInput, "$h", data):
              data_setter(address, data.uint8)
          igPopID()
        else:
          let
            b = data_provider(address)
          if b == 0:
            igTextDisabled("%02X ", b)
          else:
            igText("%02X ", b)
          if self.allowEdits and igIsItemHovered() and igIsMouseClicked(ImGuiMouseButton.Left):
            self.dataEditingTakeFocus = true
            self.dataEditingAddr = address

        n += 1
        address += 1

      igSameLine(line_start_x + cell_width * self.rows.float32 + glyph_width * 2)

      if draw_separator:
        var
          screen_pos: ImVec2
        igGetCursorScreenPosNonUDT(addr screen_pos)
        igGetWindowDrawList().addLine(
          ImVec2(x: screen_pos.x - glyph_width, y: screen_pos.y - 9999),
          ImVec2(x: screen_pos.x - glyph_width, y: screen_pos.y + 9999),
          igGetColorU32(igGetStyle().colors[ImGuiCol.Border.int32]))
        draw_separator = false

      # Draw ASCII values
      address = line_i * self.rows
      block:
        var
          n = 0
        while n < self.rows and address < mem_size:
          if n > 0:
            igSameLine()
          let
            c = data_provider(address)
          igText(if c >= 32 and c < 128: "%c" else: ".", c)
          n += 1
          address += 1
    clipper.end()
    destroy clipper
    igPopStyleVar(2)

    igEndChild()

    if data_next and self.dataEditingAddr < mem_size:
      self.dataEditingAddr = self.dataEditingAddr + 1
      self.dataEditingTakeFocus = true

    igSeparator()

    igAlignTextToFramePadding()
    igPushItemWidth(50)
    igPushAllowKeyboardFocus(false)
    var
      rows_backup = self.rows
    if igDragInt("rows##rows", addr self.rows, 0.2, 4, 32, "%.0f"):
      var
        new_window_size: ImVec2
      igGetWindowSizeNonUDT(addr new_window_size)
      new_window_size.x += (self.rows - rows_backup).float32 * (cell_width + glyph_width)
      igSetWindowSize(new_window_size)
    igPopAllowKeyboardFocus()
    igPopItemWidth()
    igSameLine()
    igText("Range %0*X..%0*X", addr_digits_count, base_display_addr, addr_digits_count, base_display_addr+mem_size-1)
    igSameLine()
    igPushItemWidth(70)
    if igInputText("##addr", self.addrInput, 32, (ImGuiInputTextFlags.CharsHexadecimal.int32 or ImGuiInputTextFlags.EnterReturnsTrue.int32).ImGuiInputTextFlags):
      var
        goto_addr: int
      if scanf(self.addrInput, "$h", goto_addr):
        goto_addr -= base_display_addr
        if goto_addr >= 0 and goto_addr < mem_size:
          igBeginChild("##scrolling")
          var
            cursor_pos: ImVec2
          igGetCursorStartPosNonUDT(addr cursor_pos)
          igSetScrollFromPosY(cursor_pos.y + (goto_addr / self.rows) * igGetTextLineHeight())
          igEndChild();
          self.dataEditingAddr = goto_addr
          self.dataEditingTakeFocus = true
    igPopItemWidth()
    igSameLine(igGetWindowWidth() - 60)
    if igButton("Dump"):
      saveDump(data_provider, mem_size)
  igEnd()