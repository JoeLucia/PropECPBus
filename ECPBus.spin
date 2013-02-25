{{
ECPBus.SPIN  Version 1.0

Copyright (c) 2013, ASI Communications, Inc.
by Joe Lucia
See end of file for terms of use. 

A Propeller implementation of the Ademco Expanded Console Protocol (ECP).

This object allows you to create your own "Keypad" for your
Ademco Vista Alarm Panels with just a Propeller + two Opto Isolators.

The object will interpret messages from the vista panel on the DATA OUT line
and can tranmit keypad keys to the DATA IN line just like a keypad, just as if you are typing them in manually.

To READ the DATA OUT from a Vista ECP Keypad Bus:  (receive alarm status and keypad messages from panel)
Connect Vista Data Out wire to the LED side of an Opto-Isolator with an inline 2.7k resistor. Connect other side to Panel Gnd.
Connect the Output of the Opto Isolator (colletor) to a Propeller Input with a 10k Pullup. Connect the Emitter side (arrow side) to Propeller Gnd.

           (opto-isolator input)                                    + 3v3
                  2k2                                               │                                        
                ┌─────┐                                          2k2                                                 
      Vista     │         │                                      ┌──┻──  TTL INPUT                              
      DATA OUT ┘                      (opto-isolator output)                            
                        Vista                                    └──┐                                            
                         GND                                                                                    
                                                                   TTL
                                                                   GND

            
To WRITE to the DATA IN of a Vista ECP Keypad Bus:  (send keypad commands to alarm panel)
Connect the Output pin of Propeller directly to LED of Opto-Isolator + GND (maybe put an inline resistor).
Connect VISTA Data In Terminal to the Emitter (arrow side) of an Opto Isolator with a 10k Pull Down. Connect the Collector to +10v.

           (opto-isolator input)                                    
                  1k0                                               + 12v Vista                              
                ┌─────┐                                         │     BUS Power                                       
         TTL    │         │                                      ┌──┘                                            
        OUTPUT ┘                      (opto-isolator output)           Vista            
                         TTL                                     └──┳───  DATA IN                               
                         GND                                         22k0                                                    
                                                                       
                                                                  Vista
                                                                   GND
                         
Call StartSlave(rpin, tpin, address)
  rpin = TTL INPUT
  tpin = TTL OUTPUT
  address = Keypad BUS Address for this device.  Panel default keypad is 16, you should use 17..23 if this is an Addition to an existing keypad.

NOTE: You must enable the appropriate keypad in the Vista Panel programming (field *190+ depending on keypad # to use).

Opto-Isolators must have 100% CTR (current-transfer ratio).  NTE3041 works well where the NTE3040 (20% CTR) does NOT work, so choose your opto's wisely.

ECP Bus is basically a 4800 baud, 8 bits data with 1 start, 1 partity, and two stop bits (12 bits per byte).
Bytes are syncd with special sync-pulses from the Panel to all for communication of multiple devices on the BUS.

}}
con
  maxZones = 200
  maxKeypads = 1

var
  byte tbyte
  byte  rxbyte
  long  sin, sout
  byte  buf[100]
  long  bufstart, bufend
  byte  sendBuf[100]
  long  sendBufStart, sendBufEnd 
  long  stk[100]
  long  bittime
  long  keytrigger
  
  byte  tmpPacket[100] ' retrieves current packet into here
  
  byte  lastPacket[100] ' moves tmpPacket here upon completion 
  byte  lastPacketLen ' length of current lastPacket

  byte  zFault[maxZones+1] ' maintain Zone Status for each partition  0=normal(eol), 1=fault(open/short)
  long  zFaultTime[maxZones+1] ' last time we had a zone status update
  
  byte  lcdDisplay[33*maxKeypads] ' maintain most recent LCD Display TEXT for each partition
  long  ledDisplay[maxKeypads] ' maintain LED status for each partition

  byte  MYADDRESS

  long  lastPacketNum
  long  lastPacketTime
  long  keypadStatus ' bits indicating status
  long  keypadLights
  long  keypadDings
  long  isUpdating

  byte pktid
  long sendReady

PUB StartSlave(rpin,tpin,address)
  sin := rpin 
  sout := tpin
  MYADDRESS := address
  cognew(MainSlave, @stk)

PUB SetAddress(address)
  MYADDRESS := address

PRI MainSlave | x,i, h, t, dif
  '' listen to Alarm Panel on ECP Bus Data Out
  '' "be like a keypad"
  bittime := clkfreq/4800
  dira[sin]~    ' make rx pin an input
  dira[sout]~~ ' output
  outa[sout]~
  sendReady~~
  pktid:=1
  lastpackettime:=cnt-clkfreq*10
  '' STT,B0,B1,B2,B3,B4,B5,B6,B7,P,STP,STP
  repeat
    ' wait for pulse
    RefreshZoneTimers
    waitpeq(|<sin,|<sin,0)
    t := cnt
    waitpne(|<sin,|<sin,0)
    dif := cnt-t
    if (dif > (clkfreq/1000*3)) and (dif < (clkfreq/1000*6)) ' 4ms Sync Pulse for Receiving Data
      GetECPBytes    ' get packet from master
    elseif (dif > (clkfreq/1000*12)) and (dif < (clkfreq/1000*15)) ' 13ms Sync Pulse for Slave to Transmit      
      ' send bytes in sendBuf
      if (sendBufStart<>sendBufEnd) and (sendReady)
        SendKeypadAddress ' request to send our data

    if cnt-lastpackettime > (clkfreq*10)
      bytefill(@lcddisplay,0,(33*maxKeypads))
      bytemove(@lcddisplay, string("NO PANEL DATA!                  "), 32)
           
PRI addSendBuf(ch) ' add a byte to the send buffer
  sendBuf[sendBufEnd++]:=ch
  if sendBufEnd>99
    sendBufEnd:=0

PRI getSendBuf ' return next byte from send buffer
  if sendbufstart==sendbufend
    return -1
  result := sendBuf[sendBufStart++]
  if sendBufStart>99
    sendBufStart:=0

PRI RefreshZoneTimers | x
  ' reset status on faulted zones if we don't "see" a fault after a few seconds
  repeat x from 0 to maxZones-1
    if zFault[x]>0
      if (cnt-zFaultTime[x] > (clkfreq*6))
        zFault[x]:=0

PRI doTxPulse
  outa[sout]~~
  waitcnt(cnt+bittime) 
  outa[sout]~

PRI waitPulse
  waitcnt(cnt+bittime)

PRI SendKeypadAddress | x
  ' send keypad address MYADDRESS
  x:=16

  ' first pulse, 0..7
  doTxPulse ' sync pulse
  waitpeq(|<sin, |<sin, 0) ' wait for next sync marker
  waitpne(|<sin, |<sin, 0)
   
  ' second puls, 8..15
  doTxPulse ' sync pulse
  waitpeq(|<sin, |<sin, 0)
  waitpne(|<sin, |<sin, 0)
   
  ' third pulse, 16..23
  doTxPulse ' sync pulse
  repeat while myaddress>x++
    waitPulse

  doTxPulse ' pulse this address

  ' You should expect an F6 response followed by MYADDRESS, at which point it is safe to SEND

PRI SendKeypadBuffer | x,i,start,t,bt,parity,siz
  start:=1
  bt := bittime ' adjust bittime to compensate for delays in bitshifting
  siz := getSendBuf
  repeat siz
    tbyte:=getSendBuf
    if tbyte<0
      quit
    
    t := cnt
    outa[sout]:=1 ' start bit
    waitcnt(t+=bt)
    i:=0
    parity~
    repeat 8           
      outa[sout] := ((tByte>>i++ & 1)<>1)
      if outa[sout]
        !parity
      waitcnt(t+=bt)

    if parity
      outa[sout]:=0 ' parity bit
    else
      outa[sout]:=1 ' parity bit
    waitcnt(t+=bt)
    
    outa[sout]~ ' stop bits
    waitcnt(t+=bt)
    waitcnt(t+=bt)

  ' TODO: wait for ACK ($F6..) immediately after last byte sent, repeat if no ACK received.
  
PRI GetECPBytes | t, i, bnum, ptype, keypadnum, plen '' Receive and Process a packet From the Alarm Panel
  t := cnt - (bittime/2)                              ' start at now + 1/2 bit
  bnum:=0
  ptype:=-1
  bytefill(@tmpPacket, 0, 100)
  plen := -1
  repeat
    rxbyte:=i:=0

    waitcnt(t += bittime)                             ' wait for middle of start bit
    if ina[sin]  ' check start bit
      quit
      
    repeat 8         ' receive next 8 bits of byte
      waitcnt(t += bitTime)                             ' wait for middle of bit
      rxbyte := rxbyte | (ina[sin]<<(i++))
     
    waitcnt(t += bitTime)                                ' parity bit
    
    waitcnt(t += bitTime)                                ' allow for stop bit
    if not ina[sin]                                      ' verify stop bit
      quit 
    waitcnt(t += bitTime)                                ' allow for stop bit
    if not ina[sin]                                      ' verify stop bit
      quit 

    if bnum==0
      ptype:=rxbyte

    if bnum==1
      case (ptype) ' determine length of this packet
        $F2: plen:= rxbyte+2
        $F6: plen:= 2
        $F7: plen:= 48
        $F9: plen:= 5

    if bnum==1 and ptype==$F6
      '' TRIGGER OUTPUT for SAMPLING keypad bytes
      keyTrigger~~
      ' if we have keyboard output then we should send it NOW
      if rxbyte==MYADDRESS and (sendbufstart<>sendbufend)
        SendKeypadBuffer
        quit
      keyTrigger~                                                                                                                

    ' add to buffer
    tmpPacket[bnum]:=rxbyte
    bnum++ 
    buf[bufend++]:=rxbyte
    if bufend>99
      bufend:=0

    if bnum==plen
      quit


  ' save Packet
  isupdating~~
  if ptype>-1
    bytemove(@lastPacket, @tmpPacket, 100)
    lastPacketLen:=bnum
    lastPacketNum++
   

  '' ----------------------------- Process Packet --------------------------
  if ptype == $F2 ' condition update
    ' indications of system status changes
  elseif ptype == $F6 ' keypad response
    ' ack/nak to keypad presses
  elseif ptype == $F7
    keypadnum := tmpPacket[3] ' bit field of keypads destined for
    ' ignore packet if not for MYADDRESS
    if ((myaddress-15) & (>|keypadnum)) == (myaddress-15)
      lastpackettime := cnt
      if tmpPacket[1]==0 and tmpPacket[7]==0 ' Update Zone Status
        zFault[tmpPacket[5]] := 1
        zFaultTime[tmpPacket[5]] := cnt
       
      keypadStatus := tmpPacket[7]<<8 + tmpPacket[8] ' save Status byte (indicates Armed mode and some system flags)
      keypadLights := tmpPacket[12] & $80
      keypadDings := tmpPacket[6] & %11
      bytemove(@lcdDisplay, @tmpPacket[12], 32) ' save keypad display

      repeat i from 0 to 31 ' remove high-bits of ascii text part
        lcdDisplay[i]:=lcdDisplay[i] & $7F
  elseif ptype == $F9 ' polling ip/gsm (LRR) module (address #3)
    ' respond with something, dunno what yet
      
      
       
  isupdating~
    
PUB tx(ch) | x
  '' transmits byte on the Data-In line on the alarm panel (like a keypad talking to alarm panel) when in Slave (Keypad) Mode
  { ch: keycode...
    Key Press =    00..09,0A,0B                                                                                                                                                                               
    Hold Key =     10..19,1A,1B
    Special Keys = 1C,1D,1E,1F
  }
  sendReady~ ' prevent sending bytes until all bytes are added to the buffer
  ' keyboard keypress is 4-bytes
  addsendbuf(4)                 ' Our Packet Length for this transmission
  addsendbuf(pktid<<4)          ' byte 0  pktid is always $10 or $50 or $90 or $D0
  addsendbuf(2)                 ' byte 1  always 2
  addsendbuf(ch)                ' byte 2  keycode
  addsendbuf(0-(pktid<<4)-2-ch) ' byte 3  checksum
  pktid+=4                      ' increment pktid by 4 each time
  sendReady~~ ' indicate it is okay to start sending now that all the bytes for this request are buffered

PUB isKeyTrigger
  ' keytrigger is used to Monitor the keypad bus for other device data analysis (not used normally)
  ' a separata process can watch this variable to determine if it should read the
  ' keypad data from the bus on another opto-isolated input (probably running on another cog)
  return keyTrigger

PUB getlcdDisplay(keypad) '' return the most recent Display for a Partition
  repeat while isUpdating ' prevent returning display data while it is being changed
  return @lcdDisplay '[(keypad-1)*33]

PUB getlastPacketNum
  return lastPacketNum
    
PUB getLastPacket(bufptr)
  '' copy last packet into bufptr
  repeat while isUpdating ' prevent copying a partially populated packet
  bytemove(bufptr, @lastPacket, 100)
  return lastPacketLen

PUB getZoneFaults
  '' return a pointer to the array of Zones for Status
  return @zFault

PUB getStatus
  return keypadStatus

PUB getLights
  return keypadLights

PUB getDings
  result := keypadDings
  keypadDings:=0

CON  
{{

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
and to permit persons to whom the Software is furnished to do so, subject to the following conditions: 

The above copyright notice and this permission notice shall be included in all copies or substantial portions
of the Software. 

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.
}}