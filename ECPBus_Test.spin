{Test Vista ECP Keypad Bus Object

Listens on Port 1, Transmits on Port 0

Displays Status Messages

Sends keyboard keys to Panel

}


CON
        _clkmode = xtal1 + pll16x                                               'Standard clock mode * crystal frequency = 80 MHz
        _xinfreq = 5_000_000
        trigger0 = 2

        keypadmonitor = 3

obj
  debug : "FullDuplexSerial"
  ecp : "ECPBus"
  rtc : "propellerrtc_emulator"

var
  long fstart,bc, psize, pptr
  byte  status[100], sptr,sin,sout
  long lastpacket  
  long rtcTime
  byte  buf[200]
  long keybuf[100]
  byte keybuflen
  long  bittime
  long stk[50]
    
PUB main | c
  bittime:=clkfreq/4800
  'sin:=3 ' monitor keypad bus
  'sout:=0 ' output on keypad bus
  'cognew(keypadCog, @stk)

  rtc.start(@rtcTime)
  debug.start(31, 30, 0, 9600)
  ecp.startslave(1,0,17)
  debug.str(string("Ready."))
  repeat
    c := debug.rxcheck
    if c > -1
      'debug.str(string(13,"sending..."))
      case (c)
        "0".."9" : c := ecp.tx(c-"0")
        "*": c := ecp.tx($0A)
        "#": c := ecp.tx($0B)
        "a":
          ecp.tx(10)
          ecp.tx(1)
          ecp.tx(2)
          ecp.tx(3)
          ecp.tx(4)
          ecp.tx(2)
        "d":
          ecp.tx(10)
          ecp.tx(1)
          ecp.tx(2)
          ecp.tx(3)
          ecp.tx(4)
          ecp.tx(1)
        other: c := -1
       
      'if c<0
      ' debug.str(string(13,"timed out"))
      'else
      ' debug.str(string(13,"sent."))

    {
    if keybuflen>0 
      sendLastKeybuf
      keybufLen:=0
    }
    
    if (ecp.getlastpacketnum > lastpacket)
      lastpacket := ecp.getlastpacketnum
      sendLastPacket
    
    

PUB keypadCog |  rxbyte,i,t,bnum,bt
  ' run this in a COG to listen to devices on the keypad bus
  bt:=clkfreq/4800
  dira[sin]~
  dira[trigger0]~~

  repeat
    if ecp.iskeytrigger
      ' read keypad data from keypad monitor input starting at trigger
      bnum:=0
      keybuflen:=0

      'wait for start bit, then clock-in rest of byte

      repeat until not ina[sin]
      t := cnt - (bt/2)
      
      repeat 
        rxbyte:=i:=0

        waitcnt(t+=bt)                                 ' wait for middle of start bit

        outa[trigger0]~~
        ' read start bit
        if ina[sin]
          quit

        repeat 8     ' receive next 8 bits of byte
          waitcnt(t+=bt)                                ' wait for middle of bit
          rxbyte := rxbyte | (ina[sin]<<(i++))
        
        waitcnt(t+=bt)                                  ' wait for parity bit
        rxbyte := rxbyte | (ina[sin]<<8)
        
        waitcnt(t+=bt)                                  ' wait for stop bit
        if not ina[sin]
          quit
        waitcnt(t+=bt)                                  ' wait for stop bit
        if not ina[sin]
          quit

        keybuf[bnum++]:=rxbyte

      keybuflen:=bnum

      outa[trigger0]~

PUB sendLastKeybuf | x,y
  if keybuflen<1
    return
  y := keybuflen
  debug.tx(13)
  debug.dec(rtc.getSeconds)
  debug.str(string(". Client BUS",13))
  x:=0
  repeat until x=>y
    debug.dec(x)
    debug.tx(".")
    debug.hex(keybuf[x],3)
    debug.tx("=")
    debug.bin(keybuf[x],8)
    debug.tx(13)
    x++

PUB sendLastPacket | x,p
  debug.tx(13)
  debug.hex(ecp.getlaststatusbyte,2)
  debug.tx("-")
  debug.str(ecp.getlcddisplay)
 
  p := ecp.getLastPacket(@status)
  repeat x from 0 to p-1
    debug.hex(status[x],2)
    if x < p-1
      debug.tx(":")
  
  'debug.tx(13)
  'debug.dec(rtc.getSeconds)

         