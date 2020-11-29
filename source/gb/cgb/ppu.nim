##[

Differences

  VRAM has 2 banks now

  0xff40  lcdc - The main LCD control register.
    bit 0 - BG and Window Master Priority
            When Bit 0 is cleared, the background and window lose their priority - the sprites will be
            always displayed on top of background and window, independently of the priority flags in OAM
            and BG Map attributes.
  
  OAM
    Byte3  Flags
      bit3   - Tile VRAM-Bank (0=Bank 0, 1=Bank 1)
      bit2-0 - Palette number (OBP0-7)
    
    The first sprite has the highest priority as opposed to the one with the lowest X coordinate.

Additions

    0xff4f  VBK - VRAM Bank (R/W)
      bit 0 - Currently selected VRAM bank (0=Bank 0, 1=Bank 1) (all other bits are ignored and set to 1)
    
    Needs to go at the end of PpuIoState

  LCD VRAM DMA Transfers
    0xff51  HDMA1 - New DMA Source, High
    0xff52  HDMA2 - New DMA Source, Low
    0xff53  HDMA3 - New DMA Destination, High
    0xff54  HDMA4 - New DMA Destination, Low
    0xff55  HDMA5 - New DMA Length/Mode/Start

    Needs new MemSlot

  CGB Palette Memory
    0xff68  BCPS/BGPI - Background Color Palette Specification or Background Palette Index
    0xff69  BCPD/BGPD - Background Color Palette Data or Background Palette Data
    0xff6a  OCPS/OBPI - Object Color Palette Specification or Sprite Palette Index
    0xff6b  OCPD/OBPD - Object Color Palette Data or Sprite Palette Data

    Needs new MemSlot

]##

type
  PpuIoHdmaState = tuple
    ## Source should be in the range of 0x0000-0x7ff0 or 0xa000-0xdfg0 (According to gbdev.io
    ## this isn'T a 100%). Trying to specify a source address in VRAM will cause garbage to be
    ## copied.
    ##
    ## Hdma3 and hdma4 specify the address within 8000-9FF0 to which the data will be copied.
    ## Only bits 12-4 are respected; others are ignored.
    ## 
    ## `<https://gbdev.io/pandocs/#lcd-vram-dma-transfers-cgb-only>`_
    hdma1: uint8    ## 0xff51  New DMA Source, High
    hdma2: uint8    ## 0xff52  New DMA Source, Low
                    ##   The four lower bits of this address will be ignored and treated as 0.
    hdma3: uint8    ## 0xff53  New DMA Destination, High
                    ##   The 4 higher bits of this address will be ignored and treated as 0.
    hdma4: uint8    ## 0xff54  New DMA Destination, Low
                    ##   The 4 lower bits of this address will be ignored and treated as 0.
    hdma5: uint8    ## 0xff55  New DMA Length/Mode/Start
                    ##   Writing to this registers starts the transfer.
                    ##   bit 0-6 - Specifies the transfer length: value / 0x10 - 1
                    ##   bit 7   - Transfer mode (0=General Purpose DMA, 1=H-Blank DMA)
  
  PpuIoCgbPalette = tuple
    ## BGP0-7 - Background Palette (8*8 bytes)
    ##   Boot rom initializes these to white
    ## OBP0-7 - Object Palette (8*8 bytes)
    ##   Unitialized, somewhat random
    ##
    ## `<https://gbdev.io/pandocs/#lcd-color-palettes-cgb-only>`_
    bgpi: uint8    ## 0xff68  Background Palette Index
    bgpd: uint8    ## 0xff69  Background Palette Data
    obpi: uint8    ## 0xff6a  Object Palette Index
    obpd: uint8    ## 0xff6b  Object Palette Data
