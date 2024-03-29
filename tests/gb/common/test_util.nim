import
  std/unittest,
  gb/common/util


suite "unit.com.util":
  test "getBit - bit 0 = 0":
    check 0 == getBit(0b11111110, 0)
  
  test "getBit - bit 0 = 1":
    check 1 == getBit(0b00000001, 0)
  
  test "getBit - bit 6 = 0":
    check 0 == getBit(0b10111111, 6)
  
  test "getBit - bit 6 = 1":
    check 1 == getBit(0b01000000, 6)
  
  test "rotateRight - 1":
    check 0x80000000'u32 == rotateRight(1'u32, 1)