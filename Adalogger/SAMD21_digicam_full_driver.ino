//this is the full digicam driver with the camera included
//it has external switches for data transfer, meaning that the entire setup can be run simply from the DE0Nano

//it has three different distinct elements:
//1)

//Known BUGS:
//1) SPI speed above 4 MHz is noisy. Likely related to the noise the breadboard model generates. Repair to the issue may come when a more integrated model is produced.
//2) "Regular" SPI commands follow each other with a delay of 1 us. This slows down data transfer. Repair may come by using a different SPI commanding solution compared to SPI.transfer(). This indicates that the delay could be as small as 440 ns only or none if we transfer 16 bits: https://wiki.analog.com/resources/eval/sdp/sdp-b/peripherals/spi

//To add:
//1)Error detection - idle cycle counter
//2)Extenal reset


//How to use this code:
//1)Upload digicam code to the DE0nano and modified_selfie_OV7670 to the Grand Central/adafruit setup
//2)Upload this code to the gateway microscontroller
//3)Adjust the digicam setup state within the "manual control" area at the end of the setup section within this code
//4)Adjust bmp file generation parameters to match capture parameters(adjusted by sending SPI commands to the DE0nano) and image generation parameters (choose the clock divider for the image within the adafruit setup's code)
//5)Run the code. Resetting the microcontroller with force the setup for the digicam. Open the serial monitor for the gateway micro and press ENTER to start data transfer
//6)Recover the SDcard and inspect the result

//**************************************************************************************
//Camera - master clock and setup
//**************************************************************************************
#include <Wire.h>                 // I2C comm to camera

//Master clock period definition
uint32_t period = 1;

//Call camera SAM21 library
#include "Master_lib_SAMD21_OV2640.h"      // Camera library for SAMD21

//Define pin pointer
OV2640_pins pins;

//Define I2C bus
#define CAM_I2C  Wire

//Call camera
Adafruit_OV2640 cam(OV7670_ADDR, &pins, &CAM_I2C);

//**************************************************************************************
//Scope
//**************************************************************************************

#include <SPI.h>
#include "wiring_private.h" // pinPeripheral() function
SPIClass scope_SPI (&sercom1, 12, 13, 11, SPI_PAD_0_SCK_1, SERCOM_RX_PAD_3);
    //define a second SPI on pins 11 (MOSI), 12 (MISO) and 13 (SCK)
#define SPI_CS_SCOPE 10
int CMD_HEX;

#include <string.h>

#define SCOPE_EXTERNAL_TRIGGER 6

#define SCOPE_DATA_TRANSFER 5

//**************************************************************************************
//SDCard
//**************************************************************************************
#include <SD.h>
#define SPI_CS_CARD 4

static char buf[17];

bool image_logged = false;


//------------------------------------------------------------------------------------------------------------------------------


void setup() {
  // put your setup code here, to run once:
  SPI.begin();
  Serial.begin(9600);


/////////////!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!////////////////////
//  while (!Serial);              //uncomment in case it is necessary to inspect the setup of the code. Code won't run until we open the serial monitor!!!!!!!!!!!
/////////////!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!////////////////////


//**************************************************************************************
//Camera master clock
//**************************************************************************************

  // Because we are using TCC0, limit period to 24 bits
  period = ( period < 0x00ffffff ) ? period : 0x00ffffff;

  // Enable and configure generic clock generator 4
  // GCLK registers are on page 119 of the SAMD21 datasheet
  GCLK->GENCTRL.reg = GCLK_GENCTRL_IDC |          // Improve duty cycle. IT will be 50/50
                      GCLK_GENCTRL_GENEN |        // Enable generic clock gen. Turn on the generator.
                      GCLK_GENCTRL_SRC_DFLL48M |  // Select 48MHz as source. Source will be the DFLL48MHz.
                                                  // Note: FDPLL96M is not activated
                      GCLK_GENCTRL_ID(4);         // Select GCLK4
  while (GCLK->STATUS.bit.SYNCBUSY);              // Wait for synchronization

  // Set clock divider of 1 to generic clock generator 4
  GCLK->GENDIV.reg = GCLK_GENDIV_DIV(1) |         // Divide 48 MHz by 1. This division is different for different GCLK values
                     GCLK_GENDIV_ID(4);           // Apply to GCLK4 4
  while (GCLK->STATUS.bit.SYNCBUSY);              // Wait for synchronization
  
  // Enable GCLK4 and connect it to TCC0 and TCC1
  GCLK->CLKCTRL.reg = GCLK_CLKCTRL_CLKEN |        // Enable generic clock, specific one.
                      GCLK_CLKCTRL_GEN_GCLK4 |    // Select GCLK4
                      GCLK_CLKCTRL_ID_TCC0_TCC1;  // Feed GCLK4 to TCC0/1. We pick, which periphery we will be using for "GCLK_CLKCTRL_ID_TCC0_TCC1". Alternative could be "GCLK_TCC2, GCLK_TC3" or "GCLK_TC4, GCLK_TC5" or "GCLK_TC6, GCLK_TC7"
                                                  // Mind, different TCCs have different capabilities.
  while (GCLK->STATUS.bit.SYNCBUSY);              // Wait for synchronization

  //we use TCC1 so we don't accidentally mess up in the future the scope SPI designated bus
  //the master clock will be on D9

  //PA7 is TCC1/WO[1], where PA7 is D9 on the Feather. The TCC1 function will be on the "E" function. This should not clash with anything. It will be on CC1.
  //PA8/TCC1/WO[2], F, D4
  // Divide counter by 1 giving 48 MHz (20.83 ns) on each TCC0 tick
  TCC1->CTRLA.reg |= TCC_CTRLA_PRESCALER(TCC_CTRLA_PRESCALER_DIV1_Val);

  // Use "Normal PWM" (single-slope PWM): count up to PER, match on CC[n]
  TCC1->WAVE.reg = TCC_WAVE_WAVEGEN_NPWM;         // Select NPWM as waveform
  while (TCC1->SYNCBUSY.bit.WAVE);                // Wait for synchronization

  // Set the period (the number to count to (TOP) before resetting timer)
  TCC1->PER.reg = period;
  while (TCC1->SYNCBUSY.bit.PER);

  // Set PWM signal to output 50% duty cycle
  // n for CC[n] is determined by n = x % 4 where x is from WO[x]               //I don't get this part, but it works now.
  TCC1->CC[1].reg = period;
  while (TCC1->SYNCBUSY.bit.CC1);

  // Configure PA18 (D10 on Arduino Zero) to be output. Port registers are on page 371 of the SAMD21 datasheet
  PORT->Group[PORTA].DIRSET.reg = PORT_PA07;      // Set pin as output
  PORT->Group[PORTA].OUTCLR.reg = PORT_PA07;      // Set pin to low

  // Enable the port multiplexer for PA18
  PORT->Group[PORTA].PINCFG[7].reg |= PORT_PINCFG_PMUXEN;              //we enable the peripherial multiplexer on pin 18

  // Connect TCC0 timer to PA18. Function F is TCC0/WO[2] for PA18.
  // Odd pin num (2*n + 1): use PMUXO
  // Even pin num (2*n): use PMUXE
  PORT->Group[PORTA].PMUX[3].reg = PORT_PMUX_PMUXO_E;                   //set up peripherial multiplexing. We choose the multiplexing for "even" number pin - here, 18 - and activate the function "F"
                                                                        //Mux comes in pairs, so we need to pick pair "9" to reach pin 18 - which will be PMUXE function then. It is a bit confusing to find the right pin, but likely it is starightforward.
                                                                        //the number is 2n+1 for odd pins, 2n for even pins
  // Enable output (start PWM)
  TCC1->CTRLA.reg |= (TCC_CTRLA_ENABLE);
  while (TCC1->SYNCBUSY.bit.ENABLE);              // Wait for synchronization

//**************************************************************************************
//Camera function setup
//**************************************************************************************

  OV2640_status status = cam.begin();
  if (status != OV2640_STATUS_OK) {
    Serial.println("Camera initialization failed!");
    while (1);
//    for(;;);
  }
  Serial.println("Camera initialized.");

//**************************************************************************************
//SDCard
//**************************************************************************************
  Serial.print("Initializing SD card...");
  if (!SD.begin(SPI_CS_CARD)) {
    Serial.println("initialization failed!");
    while (1);
  }
  Serial.println("initialization done.");

//**************************************************************************************
//Scope SPI
//**************************************************************************************

  // do this first, for Reasons
  scope_SPI.begin();

  // Assign pins 11, 12, 13 to SERCOM functionality
  pinPeripheral(11, PIO_SERCOM);
  pinPeripheral(12, PIO_SERCOM);
  pinPeripheral(13, PIO_SERCOM);


//**************************************************************************************
//Scope
//**************************************************************************************
  
  pinMode(SPI_CS_SCOPE, OUTPUT);
  digitalWrite(SPI_CS_SCOPE, HIGH);
  delay(100);
  digitalWrite(SPI_CS_SCOPE, LOW);
  scope_SPI.beginTransaction(SPISettings(4000000, MSBFIRST, SPI_MODE0));                       //SPI is adjusted to 500kHz due to noise within the breadboard model.

//Use the following section to set up the digicam for a certain starting state
//This is the "manual control" section of the setup. For command table, see below.
//Mind, transfer bits are in hex, while serial monitor typing is in decimal. If full manual control is used, the decimal line of the command table would need to be used.
//Note: the Arduino often encodes data in ASCII unless specifically told not to do so. This could mean that the assumed command won't be the same as the received one (decimal command 11 will be 049 049 in ASCII encoding, for instance)

//Here, we wipe the SDRAM active area
  scope_SPI.transfer(0x53);       //we remove read_only to erase the SDRAM
  scope_SPI.transfer(0x27);       //active area is currently at maximum 4096x2048
  scope_SPI.transfer(0x51);       //we erase
  delay(1000);
  scope_SPI.transfer(0x90);       //we stop the erase

//A set of pattern to generate with their time demand:
    
//  scope_SPI.transfer(0x10);     //pattern - 10 is wide striped, 11 is red, 12 is one pixel lines, 13 is compex pattern
//  scope_SPI.transfer(0x23);     //resolution - 20 is 160x120, 21 is 320x240, 22 is 640x480, 23 is 800x525
//  scope_SPI.transfer(0x01);     //action
//  delay(40);
//
//  scope_SPI.transfer(0x11);     //pattern - 10 is wide striped, 11 is red, 12 is one pixel lines, 13 is compex pattern
//  scope_SPI.transfer(0x22);     //resolution - 20 is 160x120, 21 is 320x240, 22 is 640x480, 23 is 800x525
//  scope_SPI.transfer(0x01);     //action
//  delay(20);
//
//  scope_SPI.transfer(0x12);     //pattern - 10 is wide striped, 11 is red, 12 is one pixel lines, 13 is compex pattern
//  scope_SPI.transfer(0x21);     //resolution - 20 is 160x120, 21 is 320x240, 22 is 640x480, 23 is 800x525
//  scope_SPI.transfer(0x01);     //action
//  delay(5);
//  
//  scope_SPI.transfer(0x13);     //pattern - 10 is wide striped, 11 is red, 12 is one pixel lines, 13 is compex pattern
//  scope_SPI.transfer(0x20);     //resolution - 20 is 160x120, 21 is 320x240, 22 is 640x480, 23 is 800x525
//  scope_SPI.transfer(0x01);     //action
//  delay(1);

//Image capture setup
  scope_SPI.transfer(0x90);     //Halt command in case it was not done before
  scope_SPI.transfer(0x22);     //resolution - 20 is 160x120, 21 is 320x240, 22 is 640x480, 23 is 800x525
                                //also, change COM7 register value: 0x14 is for QVGA, 0x4 is for VGA. QQVGA can not be generated by simply calling a different register.
  scope_SPI.transfer(0x02);     //action

 //Note: every pattern generation takes time, depending on pattern size. Every SPI command that engages a pattern or image generation should not be followed immediatelly by another SPI command. Failing to do so would lead to only part of the image/pattern generated.

  digitalWrite(SPI_CS_SCOPE, HIGH);
  delay(100);

//////External trigger///////////
  pinMode(SCOPE_EXTERNAL_TRIGGER, OUTPUT);
  digitalWrite(SCOPE_EXTERNAL_TRIGGER, LOW);
//////External trigger///////////

//////Data transfer switch///////////
  pinMode(SCOPE_DATA_TRANSFER, INPUT);
//////Data transfer switch///////////
  
  Serial.println("digicam setup finished");

//detect OV7670  
  while(1){
    //Check if the camera module type is OV2640
    cam.writeRegister(0xff, 0x01);
    int pid = cam.readRegister(0x0A);
    int ver = cam.readRegister(0x0B);
    if ((pid != 0x76 ) && (( ver != 0x70 ) || ( pid != 0x42 ))){
      Serial.println(F("Can't find OV7670 module!"));
      delay(1000);continue;
    }else{
      Serial.println(F("OV7670 detected."));break;
    }
  }

}


//------------------------------------------------------------------------------------------------------------------------------


void loop() {
  
//  while (Serial.available() == 0);

while (digitalRead(SCOPE_DATA_TRANSFER) == LOW);

////Automated data transfer into a BMP file
//Note: no "Strings" or "print" and "println" are allowed in this section. The reason for that is that any of those formats will encode the data to ASCII. The number "1" in ASCII is "049".
//Note: the BMP file is a specific file format that needs to have headers defined and a specific pixel array. Below these formats are being followed/implemented.

    byte received_from_fpga;
    byte upper_byte;
    byte lower_byte;
    uint16_t received_pixel;
    if (image_logged == false) {
      File imagefile = SD.open("img_1.bmp", FILE_WRITE);        //generate file
      if(imagefile) {
        // BMP header, 14 bytes:
        imagefile.write(0x42);                               // Windows BMP signature
        imagefile.write(0x4D);                               // "
        writeLE32(&imagefile, 14 + 56 + 800 * 525 * 2); // File size in bytes               // - update according to pattern/image size. For capture resolutions below 800x525, the BMP file remains at 800x525 resolution. Why? Because we log the padding with the image.
        writeLE32(&imagefile, 0);                            // Creator bytes (ignored)
        writeLE32(&imagefile, 14 + 56);                      // Offset to pixel data
      
        // DIB header, 56 bytes "BITMAPV3INFOHEADER" type (for RGB565):
        writeLE32(&imagefile, 56);                 // Header size in bytes
        writeLE32(&imagefile, 800);              // Width in pixels                         // - update according to pattern/image size
        writeLE32(&imagefile, 525);             // Height in pixels (bottom-to-top)         // - update according to pattern/image size
        writeLE16(&imagefile, 1);                  // Planes = 1
        writeLE16(&imagefile, 16);                 // Bits = 16
        writeLE32(&imagefile, 3);                  // Compression = bitfields
        writeLE32(&imagefile, 800 * 525);     // Bitmap size (adobe adds 2 here also)       // - update according to pattern/image size
        writeLE32(&imagefile, 2835);               // Horiz resolution (72dpi)
        writeLE32(&imagefile, 2835);               // Vert resolution (72dpi)
        writeLE32(&imagefile, 0);                  // Default # colors in palette
        writeLE32(&imagefile, 0);                  // Default # "important" colors
        writeLE32(&imagefile, 0b1111100000000000); // Red mask
        writeLE32(&imagefile, 0b0000011111100000); // Green mask
        writeLE32(&imagefile, 0b0000000000011111); // Blue mask
        writeLE32(&imagefile, 0);                  // Alpha mask
  
  
      digitalWrite(SPI_CS_SCOPE, LOW);
      
      scope_SPI.transfer(0x90);           //we need to stop whatever is running already (pattern generation? image capture?) so the coutners could be reset. If we don't, we may transition into data transfer from an read pixel counter unknown spot.
      scope_SPI.transfer(0x52);           //We engage read_only to prevent an accidental overwrite.
      delay(1);
      scope_SPI.transfer(0x03);           //Force quick data transfer mode and reset the capture module counters.
                                          //Note: if read_only is not engaged before this command, the data will be overwritten!
      digitalWrite(SPI_CS_SCOPE, HIGH); 
       
        //Log data as one 2-byte WORD - binary forma. Pixel array follows the demands posed by the BMP file itaself.     
        for (int y=524;y >= 0; y--) {                                                      // - update according to pattern/image size
          for (int x=799;x >= 0; x--) {                                                    // - update according to pattern/image size
            for (int b=1;b >= 0; b--) {
                  digitalWrite(SPI_CS_SCOPE, LOW);
                  received_from_fpga = scope_SPI.transfer(0x93);
                  digitalWrite(SPI_CS_SCOPE, HIGH);
                  if (b == 1) {
                    upper_byte =  received_from_fpga;
                    } else {
                    lower_byte =  received_from_fpga;
                    }        
              }
              //Flip byte order
              //Note: this is a BMP pixel format requirement
              imagefile.write(lower_byte);
              imagefile.write(upper_byte);
              upper_byte = 0;
              lower_byte = 0;
              received_pixel = 0;
            }
  
            //Padding at the end of the line should come here
            //Empirical experience suggests that adding distorts the image
            //No padding is added
        }
         imagefile.close();
         scope_SPI.endTransaction();
         Serial.println("Pixel data saved");
         image_logged = true;
     }
    } else {
      //empoty else loop to avoid pgoram freeze
      }
}

////Gateway manual control in the loop
////Used for debugging
////Repalce "loop" with this part for manual control
////Allows manually controlling each function within the digicam using the Arudino IDE serial input
////Command table is below
//    Serial.println("digicam command: ");
//    CMD_HEX = Serial.parseInt();
//    delay(100);
//    digitalWrite(SPI_CS_SCOPE, LOW);
//    scope_SPI.beginTransaction(SPISettings(500000, MSBFIRST, SPI_MODE0));
//    scope_SPI.transfer(CMD_HEX);                            //command
//    int received_from_fpga = scope_SPI.transfer(0xE1);      //response for the command
//    delay(10);
//    digitalWrite(SPI_CS_SCOPE, HIGH);
//    scope_SPI.endTransaction();
//    Serial.print("Reply for command ");
//    Serial.print(CMD_HEX);
//    Serial.print(" is ");
//    Serial.println(received_from_fpga);             //response is pritned out


/////////digicam command table///////


    //Note:
    //Be careful if the command is assigned as decimal or hex, encoded in ASCII or not encoded.
    //Mixing up the command formats could lead to failrue in control



////Setup commands
//
//localparam          SCOPE_STANDBY     =     8'hFF;    //255
//localparam          PATTERN_IN      =     8'h33;    //51
//localparam          HDMI_OUT      =     8'h66;    //102
//localparam          STANDARD_OP     =     8'h99;    //153
//
////Functional commands
//
//localparam          EXT_OUT_TRIG_MODE_ON    =     8'h43;    //67
//localparam          EXT_OUT_TRIG_MODE_OFF     =     8'h44;    //68
//
//localparam          ERASE_SDRAM     =     8'h51;    //81
//localparam          READ_ONLY_ON    =     8'h52;    //82
//localparam          READ_ONLY_OFF     =     8'h53;    //83
//
////Run commands
//
//localparam          START         =     8'h91;    //145
//localparam          START_READOUT     =     8'h92;    //146             //this should allow the readout and already connect the output of the SPI data transfer to the response
//localparam          TRANSMIT_DATA   =   8'h93;    //147
//localparam          STOP          =     8'h94;    //148
//
////Dummy commands
//
//localparam          DUMMY_CMD     =   8'hE1;    //d225          //it is there to provide the answer to a command the same time when it is sent. Compensates for SPI duplex behaviour.
//localparam          READOUT_PADDING =   8'h95;                  //needs two of these after START_READOUT to clock the data extraction from the capture module once
//
////Debugging commands
//
//localparam          HALT            =   8'h90;  //144
//
//localparam          QUICK_START_PATTERN =     8'h01;  //1
//localparam          QUICK_START_IMAGE   =     8'h02;  //2
//localparam          DEBUG_DATA_TRANSFER =     8'h03;  //3
//
//localparam          SELECT_PATTERN_0    =   8'h10;  //16            //wide stripes
//localparam          SELECT_PATTERN_1    =   8'h11;  //17            //red progression
//localparam          SELECT_PATTERN_2    =   8'h12;  //18            //1 pixel lines
//localparam          SELECT_PATTERN_3    =   8'h13;  //19            //complex pattern       
//
//localparam          SELECT_RESOLUTION_0 =   8'h20;  //32            //160x120
//localparam          SELECT_RESOLUTION_1 =   8'h21;  //33            //320x240
//localparam          SELECT_RESOLUTION_2 =   8'h22;  //34            //640x480
//localparam          SELECT_RESOLUTION_3 =   8'h23;  //35            //800x525       -     original full screen HDMI output
//localparam          SELECT_RESOLUTION_4 =   8'h24;  //36            //800x600
//localparam          SELECT_RESOLUTION_5 =   8'h25;  //37            //1600x1200       -     1.2 MP
//localparam          SELECT_RESOLUTION_6 =   8'h26;  //38            //2592x1944       -     5MP
//localparam          SELECT_RESOLUTION_7 =   8'h27;  //39            //4096x2045       -     dummy
//
//localparam          EXT_IN_TRIG_MODE_ON   =     8'h41;  //65
//localparam          EXT_IN_TRIG_MODE_OFF =    8'h42;  //66
//
////Replies
//localparam          ACKNOWLEDGE     =   8'hAA;    //d170          //this is a reply to be always in the SPI response register to be sent over upon a new command arriving                                               
//localparam          SCOPE_BUSY      =   8'hBB;    //d187          //this reply is sent when we wish to extract data from the setup that is busy - occurs when data transfer is not enabled
//localparam          UNKNOWN_COMMAND =   8'hCC;    //d204          //sent when we can't find the command
//localparam          INVALID_COMMAND =   8'hDD;    //d221          //happens when we want to erase a read_only setup
//localparam          DUMMY_RPL     =   8'hE2;    //d226



// Write 16-bit value to BMP file in little-endian order
void writeLE16(File *file, uint16_t value) {
#if(__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
  file->write((char *)&value, sizeof value);
#else
  file->write( value       & 0xFF);
  file->write((value >> 8) & 0xFF);
#endif
}

// Write 32-bit value to BMP file in little-endian order
void writeLE32(File *file, uint32_t value) {
#if(__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
  file->write((char *)&value, sizeof value);
#else
  file->write( value        & 0xFF);
  file->write((value >>  8) & 0xFF);
  file->write((value >> 16) & 0xFF);
  file->write((value >> 24) & 0xFF);
#endif
}


//Problems:
//1)Data transfer image is one pixel off. Image is "tilted".
    //Removing a few incoming pixels does not help.
    //Logging one more pixel into the BMP file does not help either.
    //REPAIRED: the padding was extra and too much. Once removed, the tilt is gone.
//2)Running the data transfer multiple times, the output changes when using the "19" pattern. Doesn't seem to be the case for actualy images. Likely source of problem is the byte order.
    //REPAIRED: this doesn't seem to come up anymore now that the padding is removed
//3)Padding to 800x525 doesn't seem to work. The small image loops with 640x480.
//4)Data transfer reset should occur upon data transfer commencing.
//5)Command and data handling is pretty buggy.
//    Reason is the mixup between expecting a hex number, but writing decimal into the serial monitor

//Okay, so...
//Image positioning failure is due to the faulty resetting timing. We commence a the mode "3" before we start the transfer. The relative position from the SPI command sent out AND the first SPI command to start the 

//Note: if acknowledge is not received, the command should be sent again!

//Note: initialization must occur before we start any work, otherwise the whole thing bugs out

//Note: all commands should be followed by 0xE1 to receive the right reply. Exceptions are START_READOUT, PADDING and TRANSMIT. These should not have a DUMMY afterwards to offer a continous data flow.

//Note: dummy loading does not seem to work on the gateway side.

//Note: data loading may not work either since it is based on the same idea as dummy loading

//Note: both dummy loading and data transfer should work now. This also means that the reply for each command arrives the same cycle the command is sent. If the reply is not "ACKNOWLEDGE" - d170 - or BUSY - d187 - the command can and should be resent.


////Gateway manual control in the loop
////Used for debugging
////Allows manually controlling each function within the digicam using the Arudino IDE serial input
////Command table is below
//    Serial.println("digicam command: ");
//    CMD_HEX = Serial.parseInt();
//    delay(100);
//    digitalWrite(SPI_CS_SCOPE, LOW);
//    scope_SPI.beginTransaction(SPISettings(500000, MSBFIRST, SPI_MODE0));
//    scope_SPI.transfer(CMD_HEX);                            //command
//    int received_from_fpga = scope_SPI.transfer(0xE1);      //response for the command
//    delay(10);
//    digitalWrite(SPI_CS_SCOPE, HIGH);
//    scope_SPI.endTransaction();
//    Serial.print("Reply for command ");
//    Serial.print(CMD_HEX);
//    Serial.print(" is ");
//    Serial.println(received_from_fpga);             //response is pritned out

////Gateway automatic data load
////Automatically engages data transfer towards SPI at 100 Hz
////Starts after pressing ENTER within the IDE serial input
////Recommended to run it with the 1 pixel lines pattern generated to see the pattern 248-0-7-224-0-31-0-0 coming through the SPI
//    Serial.println("digicam command: ");
//    digitalWrite(SPI_CS_SCOPE, LOW);
//    scope_SPI.beginTransaction(SPISettings(500000, MSBFIRST, SPI_MODE0));
//    int received_from_fpga = scope_SPI.transfer(0x93);
//    delay(500);
//    digitalWrite(SPI_CS_SCOPE, HIGH);
//    scope_SPI.endTransaction();
//    Serial.print("Reply for command ");
//    Serial.print(CMD_HEX);
//    Serial.print(" is ");
//    Serial.println(received_from_fpga);   

