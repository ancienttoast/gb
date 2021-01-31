import
  std/strformat,
  imageman, nimgl/imgui, opengl



type
  Texture* = tuple[texture: GLuint, width, height: int]

proc upload*(self: var Texture, image: Image[ColorRGBU]) =
  glBindTexture(GL_TEXTURE_2D, self.texture)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB.GLint, image.width.GLsizei, image.height.GLsizei, 0, GL_RGB, GL_UNSIGNED_BYTE, unsafeAddr image.data[0])

  self.width = image.width
  self.height = image.height

proc initTexture*(): Texture =
  glGenTextures(1, addr result.texture)
  glBindTexture(GL_TEXTURE_2D, result.texture)

  glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

proc destroy*(self: Texture) =
  glDeleteTextures(1, unsafeAddr self.texture)

proc igTexture*(self: Texture, scale: float) =
  igImage(cast[pointer](self.texture), ImVec2(x: self.width.float32 * scale, y: self.height.float32 * scale))


template rawDataTooltip*(body: untyped): untyped =
  igTextDisabled("(raw)")
  if igIsItemHovered():
    igBeginTooltip()
    igPushTextWrapPos(igGetFontSize() * 35.0)
    body
    igPopTextWrapPos()
    igEndTooltip()


func displayBytes*(bytes: int): string =
  const
    Divider = 1000
    Units = [ "B", "kB", "MB", "GB", "TB" ]
  var
    current = bytes.float
  for unit in Units:
    if current <= Divider:
      result = &"{current:6.2f}{unit}"
      break
    current = current / Divider