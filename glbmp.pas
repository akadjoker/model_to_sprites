
unit glBMP;

interface

uses Windows,
     OpenGL,
     Sysutils,
     Graphics,
     JPEG;

const
  BM = $4D42;     // Identifies a windows bitmap (as apposed to a OS/2 bitmap)
  TGA_RGB = 2;    // Identifies an uncompressed TGA in RGB format
  READ_ONLY = 0;

type
  pFile = ^File;

  // Record for holding pixel data for a 24bpp OpenGL image
  PGLRGBTRIPLE = ^TGLRGBTRIPLE;
  tagGLRGBTRIPLE = packed record
    red : Byte;
    green : Byte;
    blue : Byte;
  end;
  TGLRGBTRIPLE = tagGLRGBTRIPLE;

  // Record for holding pixel data for a 24bpp OpenGL image
  PGLRGBQUAD = ^TGLRGBQUAD;
  tagGLRGBQUAD = packed record
    red : Byte;
    green : Byte;
    blue : Byte;
    alpha : Byte;
  end;
  TGLRGBQUAD = tagGLRGBQUAD;

  // Array to hold palette data for 8bpp and 4bpp images
  TColorTable = Array[Byte] of TRGBQUAD;

  // Holds either the palette (4, 8bpp) or bitmasks (16bpp)
  TPalette = record
    case Boolean of
      True : (Colors : TColorTable);
      False: (redMask, greenMask, blueMask : Dword);
  end;

  // Defines the type of function that is accepted for an alpha channel callback
  TAlphaFunc = function (red, green, blue : Byte) : Byte;

  // Header type for TGA images
  TTGAHEADER = packed record
    tfType : Byte;
    tfColorMapType : Byte;
    tfImageType : Byte;
    tfColorMapSpec : Array[0..4] of Byte;
    tfOrigX : Array [0..1] of Byte;
    tfOrigY : Array [0..1] of Byte;
    tfWidth : Array [0..1] of Byte;
    tfHeight : Array [0..1] of Byte;
    tfBpp : Byte;
    tfImageDes : Byte;
  end;

  TGLBMP = class
    TextureID : integer;         // OpenGL texture id
{!} HatAlpha  : Boolean;

    // Public procedures: descriptions are in the individual headers below
    constructor Create(); overload;
    constructor Create(filename : String); overload;
    
    destructor Destroy(); override;

    function LoadImage(filename : String) : Boolean;
    function SaveImage(filename : String) : Boolean;

    function SaveScreen(filename : String) : Boolean; overload;
    function SaveScreen() : Boolean; overload;

    procedure InitEmpty(w, h : Integer);

    function SaveGLPixels(x,y,w,h:integer;filename : String) : Boolean;


    // Alpha function
    function AddAlpha(filename : String) : Boolean;
    procedure SetAlphaFunc(aFunc : TAlphaFunc);
    function ColorKey(red, green, blue : Byte; tolerance : Byte) : Boolean;
    function Stencil(filename : String; red, green, blue : Byte) : Boolean;

    function ToNormalMap(scale : Single) : Boolean;

    // Misc utility functions
    function Invert() : Boolean;
    function FlipVert() : Boolean;
    function FlipHorz() : Boolean;
    function Rotate180() : Boolean;
    procedure SetJPGQuality(quality : Integer);

    // OpenGL texture utility functions
{!} procedure GenTexture(pS3TC, pAni : Boolean);


    function GetWidth() : Integer;
    function GetHeight() : Integer;
    function GetData() : Pointer;

  private
    width : Integer;          // Width of the bitmap
    height : Integer;         // Height of the bitmap
    colorDepth : Integer;     // Color depth of the bitmap

    rgbBits : PGLRGBQUAD;     // Holds the image in 32bpp (RGBA) format

    palette : TPalette;       // Holds the images palette (if required)
    jpgQuality : Integer;     // Sets the quality to save a JPG as

    minFilter : integer;        // Texture minification filter
    magFilter : integer;        // Texture magnification filter
    texWrapS : integer;         // Texture wrapping in s direction
    texWrapT : integer;         // Texture wrapping in t direction

    imageSize : Integer;      // Size of BMP when its loaded

    alphaFunc : TAlphaFunc;   // Alpha channel callback

    // Functions for loading from each type of image
    function LoadBMP(filename : String) : Boolean;
    function LoadJPG(filename : String) : Boolean;
    function LoadTGA(filename : String) : Boolean;

    // Functions to save to each type of image
    function SaveBMP(filename : String) : Boolean;
    function SaveJPG(filename : String) : Boolean;
    function SaveTGA(filename : String) : Boolean;

    // Saves the OpenGL framebuffer to screen
    function SaveGLBuffer(filename : String) : Boolean;
    
    // Functions for loading x bpp images
    procedure Load32(imgFile : pFile);
    procedure Load24(imgFile : pFile);
    procedure Load16(imgFile : pFile);
    procedure Load8(imgFile : pFile);
    procedure Load4(imgFile : pFile);

    // Functions used to decode 16bpp images
    function GetRightShiftCount(dwVal : DWord) : Integer;
    function GetNumSet(dwVal : DWord) : Integer;
    function Scale8(colorValue, colorBits : Integer) : Integer;
    function GetLineWidth(bpp : Integer) : Integer;

    // Utility functions
    procedure ClearMem();
    procedure SwapRB();
    procedure ExpandTo32(image : Pointer; pad : Integer; swapRB : Boolean);
    procedure SetAlpha(alpha : Byte);
  end;

implementation

{ TGLBMP }

// Name       : Create
// Purpose    : Sets up the initial values for the bitmap
// Parameters : None
constructor TGLBMP.Create;
begin
  Width := 0;
  Height := 0;
  ColorDepth := 0;
  jpgQuality := 75;

  // Set defualt texture generation settings
  minFilter := GL_LINEAR;
  magFilter := GL_LINEAR;
  texWrapS := GL_REPEAT;
  texWrapT := GL_REPEAT;
end;

// Name       : Create
// Desription : Overloaded version of above creator, initializes the image
//              and loads an image from disk
// Parameters :
//  filename - Image to load
constructor TGLBMP.Create(filename : String);
begin
  Create();

  LoadImage(filename);  
end;

// Name       : LoadImage
// Purpose    : Loads BMP, JPG, PNG, or TGA image files into a memory array
// Parameters :
//  filename - name and path of the image to open
// Returns    : Whether the image could be loaded or not
function TGLBMP.LoadImage(filename : String): Boolean;
begin
  Result := False;

  // If an image has already been loaded into memory, free it
  ClearMem();

  // Check extension and load image using appropriate function
  if (CompareText(ExtractFileExt(filename), '.bmp') = 0) then begin
    Result := LoadBMP(filename);
    Exit;
  end;

  if (CompareText(ExtractFileExt(filename), '.jpg') = 0) then begin
    Result := LoadJPG(filename);
    Exit;
  end;

  if (CompareText(ExtractFileExt(filename), '.tga') = 0) then begin
    Result := LoadTGA(filename);
    Exit;
  end;
end;

// Name       : SaveImage
// Purpose    : Save's the current image as a JPG, PNG, TGA, or BMP file
// Parameters : Name and path of file to save to (if it already exists, it is
//              overwritten!)
// Returns    : Whether image could be saved succesfully
function TGLBMP.SaveImage(filename : String) : Boolean;
begin
  Result := False;

  // Check extension and save image accordingly
  if (CompareText(ExtractFileExt(filename), '.bmp') = 0) then begin
    Result := SaveBMP(filename);
    Exit;
  end;

  if (CompareText(ExtractFileExt(filename), '.jpg') = 0) then begin
    Result := SaveJPG(filename);
    Exit;
  end; 


  if (CompareText(ExtractFileExt(filename), '.tga') = 0) then begin
    Result := SaveTGA(filename);
    Exit;
  end;
end;

// Name       : LoadBitmap
// Purpose    : Loads a windows bitmap and converts it to OpenGL format (RGB)
// Parameters :
//   filename - name and location of the file to open
// Returns    : Whether the bitmap could be loaded successfully
function TGLBMP.LoadBMP(filename : String) : Boolean;
var
  fHeader : BITMAPFILEHEADER;   // Holds the file information for the bitmap
  iHeader : BITMAPINFOHEADER;   // Holds the height, width, colordepth, etc..
                                // for the bitmap
  bmpFile : File;               // Used to load the bitmap
  bytesRead : Integer;          // Used in read operations to check for errors

  palSize : Integer;            // size of the image's palette
begin
  Result := True;
  if FileExists(filename) then begin
    // "Tie" the bmpFile variable to the filename passed in
    AssignFile(bmpFile, filename);

    // Set file mode to read only (defined in const section)
    FileMode := READ_ONLY;

    // Opens the file (if it doesn't exist its created) and sets the size
    // of the reads to 1 byte
    Reset(bmpFile, 1);

    // Read in the bitmap file header
    BlockRead(bmpFile, fHeader, SizeOf(fHeader));

    // Check if its a windows bitmap by comparing its "magic number" to what
    // the BMP specs say it should be
    if fHeader.bfType <> BM then begin
      Result := False;
      CloseFile(bmpFile);
      Exit;
    end;

    // Read in the bitmap info header
    BlockRead(bmpFile, iHeader, SizeOf(iHeader));

    // Make sure that the image doesn't use a bitmap core header (not supported)
    if iHeader.biSize = SizeOf(BITMAPCOREHEADER) then begin
      Result := False;
      CloseFile(bmpFile);
      Exit;
    end;

    // Set the bitmaps width, height, and colordepth to the bitmap
    // being loaded's values
    Width := iHeader.biWidth;
    Height := Abs(iHeader.biHeight);
    ColorDepth := iHeader.biBitCount;

    // Check for compression or lack thereof
    if iHeader.biCompression <> BI_RGB then begin
      if iHeader.biCompression = BI_BITFIELDS then begin
        // Read in the red, blue, and green bitmasks, later used to
        // decode the 16bpp image's color information
        if ColorDepth = 16 then begin
          BlockRead(bmpFile, palette.redMask, SizeOf(Dword));
          BlockRead(bmpFile, palette.greenMask, SizeOf(Dword));
          BlockRead(bmpFile, palette.blueMask, SizeOf(Dword));
        end;
      end else begin
        // RLE compression is unsupported so exit
        Result := False;
        CloseFile(bmpFile);
        Exit;
      end;
    end;

    // Read in the images palette if its required (8 and 4bpp images)
    if ColorDepth < 16 then begin
      // Size of palette in bytes
      palSize := iHeader.biClrUsed*4;

      // Read in the palette 
      BlockRead(bmpFile, palette.Colors, palSize, bytesRead);
      if bytesRead <> palSize then begin
        Result := False;
        CloseFile(bmpFile);
        Exit;
      end;
    end;

    // Jump to the bitmaps bits
    Seek(bmpFile, fHeader.bfOffBits);

    // Get the size of the image (in bytes)
    imageSize := iHeader.biSizeImage;

    // Some images have this set to zero so if they do, manually calculate it
    if imageSize = 0 then begin
      imageSize := Height * GetLineWidth(ColorDepth);
    end;

    // Load the images pixel data depending on the color depth of the image
    case ColorDepth of
      32 : Load32(@bmpFile);
      24 : Load24(@bmpFile);
      16 : Load16(@bmpFile);
      8 : Load8(@bmpFile);
      4 : Load4(@bmpFile);
      else Result := False;
    end;

    // Check to see if image was loaded
    if not Assigned(rgbBits) then begin
      Result := False;
      CloseFile(bmpFile);
      Exit;
    end;

    // Set the alpha channel of the image to completely opaque
    SetAlpha(255);

    // Done with the file so close it
    CloseFile(bmpFile);
  end else
    Result := False;
end;

// Name       : LoadJPG
// Desription : Loads a JPG file
// Parameters :
//  filename - Name of the file to be loaded  
// Returns    : Succes or failure
function TGLBMP.LoadJPG(filename : String) : Boolean;
var
  BMP : TBitmap;          // Used to get the data from the JPEG image
  JPG : TJPEGImage;       // Used to load and decompress the JPEG image
  iHeader : PBitmapInfo;  // Bitmap information header
  res : Integer;          // Error var
begin
  Result := True;
  
  // Initialize the BMP and JPEG
  JPG := TJPEGImage.Create();
  BMP := TBitmap.Create();

  if (not FileExists(filename)) then begin
    Result := False;
    Exit;
  end;

  // Try to load the JPG image
  try
    JPG.LoadFromFile(filename);
  except
    Result := False;
    JPG.Free;
    BMP.Free;
    Exit;
  end;

  // Set the bitmaps properties
  BMP.PixelFormat := pf32Bit;
  BMP.Width := JPG.Width;
  BMP.Height := JPG.Height;

  // Load the JPEG image into the bitmap
  BMP.Assign(JPG);

  // Set the global image properties
  Width := BMP.Width;
  Height := BMP.Height;
  ColorDepth := 32;

  // Allocate enough memory to hold the uncompressed, 32bpp, JPG image
  GetMem(rgbBits, Width*Height*4);

  // Allocate the bitmap info header
  GetMem(iHeader, SizeOf(TBitmapInfoHeader));

  // Define what kind of data we want from the bitmap
  with iHeader^.bmiHeader do begin
    biSize := SizeOf(TBitmapInfoHeader);
    biWidth := Width;
    biHeight := Height;
    biPlanes := 1;
    biBitCount := 32;
    biCompression := BI_RGB;
    biSizeImage := Width*Height*4;
  end;

  // Get the image data from the bitmap into our memory buffer
  res := GetDIBits(BMP.Canvas.Handle, BMP.handle, 0, Height, rgbBits, TBitmapInfo(iHeader^), DIB_RGB_COLORS);
  if (res = 0) then begin
    Result := False;
    JPG.Free;
    BMP.Free;
    Exit;
  end;

  // Swap the red and blue channels in the image (from BGR to RGB)
  SwapRB();

  // Set the alpha channel of the image to completely opaque
  SetAlpha(255);  

  // Free the JPG and BMP images
  JPG.Free;
  BMP.Free;
end;

// Name       : LoadTGA
// Desription : Loads 24 and 32bpp (with alpha channel) TGA images
// Parameters : 
//  filename - name of image to load  
// Returns    : Success or failure
function TGLBMP.LoadTGA(filename : String) : Boolean;
var
  tgaFile : File;           // File pointer
  tgaHeader : TTGAHEADER;   // Holds the images header
  bytesRead : Integer;      // Used for error checking
  image : PRGBTRIPLE;       // Holds the 24bpp image
begin
  Result := True;
  if FileExists(filename) then begin
    // "Tie" the tgaFile variable to the filename passed in
    AssignFile(tgaFile, filename);

    // Set file mode to read only (defined in const section)
    FileMode := READ_ONLY;

    // Opens the file and sets the size
    // of the reads to 1 byte
    Reset(tgaFile, 1);

    // Read in the bitmap file header
    BlockRead(tgaFile, tgaHeader, SizeOf(tgaHeader));

    // Only support uncompressed images
    if (tgaHeader.tfImageType <> TGA_RGB) then begin
      Result := False;
      CloseFile(tgaFile);
      Exit;
    end;

    // Don't support colormapped files
    if tgaHeader.tfColorMapType <> 0 then begin
      Result := False;
      CloseFile(tgaFile);
      Exit;
    end;
    
    // Get the width, height, and color depth
    Width := tgaHeader.tfWidth[0] + tgaHeader.tfWidth[1] * 256;
    Height := tgaHeader.tfHeight[0] + tgaHeader.tfHeight[1] * 256;
    ColorDepth := tgaHeader.tfBpp;
    imageSize := Width*Height*(ColorDepth div 8);

    // Only support 24 or 32bpp images
    if (ColorDepth <> 32) and (ColorDepth <> 24) then begin
      Result := False;
      CloseFile(tgaFile);
      Exit;
    end;
    
    // Read in the appropriate image
    case ColorDepth of
      32 : 
        begin
          // Allocate memory to hold the image
          GetMem(rgbBits, imageSize);

          // Read in the image
          BlockRead(tgaFile, rgbBits^, imageSize, bytesRead);
          if bytesRead <> imageSize then begin
            Result := False;
            CloseFile(tgaFile);
            Exit;
          end;
        end;
      24 : 
        begin
          // Allocate memory to hold the 24bpp image
          GetMem(image, imageSize);         

          // Read in the image
          BlockRead(tgaFile, image^, imageSize, bytesRead);
          if bytesRead <> imageSize then begin
            Result := False;
            FreeMem(image);
            CloseFile(tgaFile);
            Exit;
          end;

          // Allocate memory to hold the 32bpp image
          GetMem(rgbBits, Width*Height*4);

          // Expand it from 24bpp to 32bpp and into the rgbBits buffer
          ExpandTo32(image, 0, False);

          FreeMem(image);

          // Set the alpha channel of the image to completely opaque
          SetAlpha(255);
        end;
    end;

    // Swap the red and blue channels
    SwapRB();

  end else
    Result := False;
end;

// Name       : SaveBitmap
// Purpose    : Saves the values in the Bits variable to a windows bitmap
// Parameters :
//   filename - name and location of the file to open
// Returns    : Whether the bitmap could be saved
function TGLBMP.SaveBMP(filename : String) : Boolean;
var
  fHeader : BITMAPFILEHEADER;   // Holds the file information for the bitmap
  iHeader : BITMAPINFOHEADER;   // Holds the height, width, colordepth, etc..
                                // for the bitmap
  bmpFile : File;               // Used to load the bitmap
  length : Integer;             // Number of bytes in the bitmap
  bytesWritten : Integer;       // Used in write operations to check for errors
begin
  Result := True;

  // Check to see if there is data in the bitmap
  if Assigned(rgbBits) then begin
    // "Tie" the bmpFile to the filename
    AssignFile(bmpFile, filename);

    // Creates a new file (if one exists with the same name, it is overwritten)
    // and sets the amount to transfer in write operations (1 byte at a time)
    Rewrite(bmpFile, 1);

    // Calculate the number of bytes in the image
    length := Width*Height*4;
    
    // Set up the file header
    fHeader.bfType := BM;     // Windows bitmap
    fHeader.bfSize := SizeOf(BITMAPFILEHEADER) + SizeOf(iHeader) + length;
    fHeader.bfReserved1 := 0; // Reserved
    fHeader.bfReserved2 := 0; // Reserved

    // This sets the distance from the start of the file to the start
    // of the bitmaps color data
    fHeader.bfOffBits := SizeOf(BITMAPFILEHEADER) + SizeOf(iHeader);

    // Save the file header to file
    BlockWrite(bmpFile, fHeader, SizeOf(fHeader), bytesWritten);
    if bytesWritten <> SizeOf(fHeader) then begin
      Result := False;
      CloseFile(bmpFile);
      Exit;
    end;

    // Clear the info header structure
    ZeroMemory(@iHeader, SizeOf(BITMAPINFOHEADER));

    // Set up the information header
    iHeader.biSize := SizeOf(BITMAPINFOHEADER);
    iHeader.biWidth := Width;           // Current width
    iHeader.biHeight := Height;         // Current height
    iHeader.biPlanes := 1;              // Number of planes, must be set to 1
    iHeader.biBitCount := 32;           // Current color depth
    iHeader.biCompression := BI_RGB;    // No compression
    iHeader.biSizeImage := length;      // Number of bytes in bitmap

    // Save the information header to file
    BlockWrite(bmpFile, iHeader, SizeOf(iHeader), bytesWritten);
    if bytesWritten <> SizeOf(iHeader) then begin
      Result := False;
      CloseFile(bmpFile);
      Exit;
    end;

    // Swap the red and blue channels (from RGB to BGR)
    SwapRB();

    // Save the color data to file
    BlockWrite(bmpFile, rgbBits^, length, bytesWritten);
    if bytesWritten <> length then begin
      Result := False;
      CloseFile(bmpFile);
      Exit;
    end;

    // Swap back to RGB, so as to not screw up the existing image
    SwapRB();
    
    // Close the file
    CloseFile(bmpFile);
  end else
    Result := False;
end;

// Name       : SaveJPG
// Desription : Saves the currently loaded image to disk
// Parameters :
//  filename - name of file to be saved
// Returns    : Success or failure
function TGLBMP.SaveJPG(filename : String) : Boolean;
var
  JPG : TJPEGImage;       // Holds the JPEG image
  BMP : TBitmap;          // Holds the BMP image
  iHeader : PBitmapInfo;  // Bitmap info header
  res : Integer;          // Error var
begin 
  Result := True;

  // Ensure that there is something to save
  if Assigned(rgbBits) then begin

    // Initialize the JPG and BMP containers
    JPG := TJPEGImage.Create();
    BMP := TBitmap.Create;

    // Set the BMP parameters
    BMP.PixelFormat := pf32bit;
    BMP.Width  := Width;
    BMP.Height := Height;
    
    // Allocate the bitmap info header
    GetMem(iHeader, SizeOf(TBitmapInfoHeader));

    // Set what kind of bitmap we have
    with iHeader^.bmiHeader do begin
      biSize := SizeOf(TBitmapInfoHeader);
      biWidth := Width;
      biHeight := Height;
      biPlanes := 1;
      biBitCount := 32;
      biCompression := BI_RGB;
      biSizeImage := Width*Height*4;
    end;
    
    // Swap red and blue channels (from RGB to BGR)
    SwapRB();

    // Set our currently loading image into the bitmap
    res := SetDIBits(bmp.Canvas.Handle, bmp.Handle, 0, Height, rgbBits, TBitmapInfo(iHeader^), DIB_RGB_COLORS);
    if (res = 0) then begin
      Result := False;
      JPG.Free;
      BMP.Free;
      Exit;
    end;

    // Swap back to RGB, so as to not screw up the existing image
    SwapRB();

    // Set the JPEG quality
    JPG.CompressionQuality := jpgQuality;

    // Try to save the image
    try
      // Get the image data from the BMP container
      JPG.Assign(BMP);

      // Save it to disk
      JPG.SaveToFile(filename);
    except
      // If there were errors then...
      Result := False;
      JPG.Free;
      BMP.Free;
      Exit;
    end;
  end else 
    Result := False;
end;


// Name       : SaveTGA
// Desription : Saves a TGA image to disk
// Parameters :
//  filename - name and path to save file  
// Returns    : Success or failure
function TGLBMP.SaveTGA(filename : String) : Boolean;
var
  tgaHeader : TTGAHEADER; // TGA image header
  tgaFile : File;         // File pointer
  length : Integer;       // Number of bytes in image
  bytesWritten : Integer; // Error checker
begin
  Result := True;

  // Make sure there is a file to save
  if Assigned(rgbBits) then begin
    // "Tie" the filename to the filepointer
    AssignFile(tgaFile, filename);

    // Create a new file and open it 
    Rewrite(tgaFile, 1);

    // Clear the TGA header
    ZeroMemory(@tgaHeader, SizeOf(tgaHeader));
    
    // Fill the structure with info for the image to be saved
    tgaHeader.tfImageType := TGA_RGB;
    tgaHeader.tfWidth[0] := Width mod 256;
    tgaHeader.tfWidth[1] := Width div 256;
    tgaHeader.tfHeight[0] := Height mod 256;
    tgaHeader.tfHeight[1] := Height div 256;
    tgaHeader.tfBpp := 32;
    
    // Write the header to disk
    BlockWrite(tgaFile, tgaHeader, SizeOf(tgaHeader), bytesWritten);
    if bytesWritten <> SizeOf(tgaHeader) then begin
      Result := False;
      CloseFile(tgaFile);
      Exit;
    end;

    // Switch the red and blue channels (from RGB to BGR)
    SwapRB();

    // Calculate number of bytes in image
    length := Width*Height*4;

    // Save the image contents to file
    BlockWrite(tgaFile, rgbBits^, length, bytesWritten);
    if bytesWritten <> length then begin
      Result := False;
      CloseFile(tgaFile);
      Exit;
    end;

    // Swap back to RGB, so as to not screw up the existing image
    SwapRB();
    
    CloseFile(tgaFile);    
  end else
    Result := False;
end;

// Name       : SaveScreen
// Desription : Saves the current contents of the OpenGL framebuffer to disk
// Parameters :
//  filename - Name of file to save to  
// Returns    : Success or failure
function TGLBMP.SaveScreen(filename : String) : Boolean;
begin
  Result := SaveGLBuffer(filename);
end;

// Name       : SaveScreen
// Desription : Saves the current contents of the OpenGL framebuffer to memory
//              After calling this function, the Bits properties points to a
//              32bpp image of the framebuffer
// Parameters : None 
// Returns    : Success or failure
function TGLBMP.SaveScreen() : Boolean;
begin
  Result := SaveGLBuffer('');
end;


function TGLBMP.SaveGLBuffer(filename : String) : Boolean;
var
  viewport : Array[0..3] of integer;  // Current OpenGL viewport
begin
  Result := True;

  // Get the current OpenGL viewport
  glGetIntegerv(GL_VIEWPORT, @viewport);

  // Set up the images information
  Width := viewport[2];
  Height := viewport[3];
  ColorDepth := 32;

  // Free memory if required
  ClearMem();

  // Allocate enough memory to save the current OpenGL framebuffer
  GetMem(rgbBits, Width*Height*4);

  // Tell OpenGL to finish what its doing
  glFinish();

  // Set the pixel storage modes
  glPixelStorei(GL_PACK_ALIGNMENT, 4);
  glPixelStorei(GL_PACK_ROW_LENGTH, 0);
  glPixelStorei(GL_PACK_SKIP_ROWS, 0);
  glPixelStorei(GL_PACK_SKIP_PIXELS, 0);

  // Read in the current OpenGL framebuffer
  glReadPixels(0, 0, viewport[2], viewport[3], GL_RGBA, GL_UNSIGNED_BYTE, rgbBits);

  // Only save to file if the filename isn't blank, if it is blank then instead
  // of saving to file, the image is just saved to memory
  if filename <> '' then begin
    // Save the framebuffer to disk
    if not SaveImage(filename) then
      Result := False;
  end;
end;

function TGLBMP.SaveGLPixels(x,y,w,h:integer;filename : String) : Boolean;

begin
  Result := True;

  Width := w;
  Height := h;
  ColorDepth := 32;

  // Free memory if required
  ClearMem();

  // Allocate enough memory to save the current OpenGL framebuffer
  GetMem(rgbBits, Width*Height*4);

  // Tell OpenGL to finish what its doing
  glFinish();

  // Set the pixel storage modes
  glPixelStorei(GL_PACK_ALIGNMENT, 4);
  glPixelStorei(GL_PACK_ROW_LENGTH, 0);
  glPixelStorei(GL_PACK_SKIP_ROWS, 0);
  glPixelStorei(GL_PACK_SKIP_PIXELS, 0);

  // Read in the current OpenGL framebuffer
  glReadPixels(x,y,w,h, GL_RGBA, GL_UNSIGNED_BYTE, rgbBits);

  // Only save to file if the filename isn't blank, if it is blank then instead
  // of saving to file, the image is just saved to memory
  if filename <> '' then begin
    // Save the framebuffer to disk
    if not SaveImage(filename) then
      Result := False;
  end;
end;

procedure TGLBMP.InitEmpty(w, h : Integer);
begin
  ClearMem();
  GetMem(rgbBits, w*h*4);

  Width := w;
  Height := h;
  ColorDepth := 32;
end;

// Name       : AddAlpha
// Desription : Adds an alpha channel to the loaded image. The alpha channel
//              is generated from the file specified. The two images must
//              have the same dimensions.
// Parameters :
//  filename - File to generate the alpha channel from
// Returns    : Success or failure
function TGLBMP.AddAlpha(filename : String) : Boolean;
var
  pixel : PGLRGBQUAD;
  alpha : PGLRGBQUAD;
  I : Integer;
  alphaImg : TGLBMP;
begin
  Result := True;

  // Initialize the alpha image
  alphaImg := TGLBMP.Create();

  // Make sure an image is loaded and that the alpha image loads successfully
  if Assigned(rgbBits) and (alphaImg.LoadImage(filename)) then begin

    // Make sure the two images's dimensions are the same
    if (alphaImg.Width <> Width) or (alphaImg.Height <> Height) then begin
      Result := False;
      alphaImg.Free();
      Exit;
    end;

    // Loop through the image generating its alpha channel from the alpha img
    pixel := rgbBits;
    alpha := alphaImg.rgbBits;
    for I := 0 to (Width*Height)-1 do begin
      // If a user defined alpha callback has been defined, then use it
      if Assigned(alphaFunc) then
        pixel.alpha := alphaFunc(alpha.red, alpha.green, alpha.blue)
      else
        pixel.alpha := Round(((alpha.red + alpha.blue + alpha.green) / 765) * 255);

      Inc(pixel);
      Inc(alpha);
    end;
  HatAlpha := True;
  end else
    Result := False;

  alphaImg.Free();
end;

// Name       : SetAlphaFunc
// Desription : Sets the user defined alpha callback function
// Parameters : 
//  aFun - alpha callback function pointer
procedure TGLBMP.SetAlphaFunc(aFunc : TAlphaFunc);
begin
  if Assigned(aFunc) then
    alphaFunc := aFunc;
end;

// Name       : ColorKey
// Desription : Sets all pixels having the same color values as the 
//              red,green,blue values passed in, to transparent (alpha of 0).
//              All other pixels are set to fully opaque (alpha of 255)
// Parameters :
//  red, green, blue - Color to set transparent
//  tolerance - allows a range of colors to be set transparent, anything less
//              than tolerance+colorvalue is set to transparent. This is usefull 
//              for JPG images with black backgrounds, the black isn't always
//              pure black (0,0,0) instead its often slightly brighter (5, 0, 0).
// Returns    : Success or failure
function TGLBMP.ColorKey(red, green, blue : Byte; tolerance : Byte) : Boolean;
var
  pixel : PGLRGBQUAD;
  I : Integer;
begin
  Result := True;

  // Make sure that an image has been loaded
  if Assigned(rgbBits) then begin
    // Increase the color values by the tolerance value
    red := red + tolerance;
    green := green + tolerance;
    blue := blue + tolerance;
    
    pixel := rgbBits;
    for I := 0 to Width*Height-1 do begin
      // If the pixel color is less than the specified color - the tolerance value
      // then it is culled (set to fully transparent)
      if ((pixel.red <= red) and (pixel.green <= green) and (pixel.blue <= blue)) then
        pixel.alpha := 0
      else
        pixel.alpha := 255;

      Inc(pixel);
    end;
  end else
    Result := False;
end;

// Name       : Stencil
// Desription : Applys a stencil image to the image. A stencil can be though of 
//              as a cookie cutter, leaving portions of the image visible and
//              other portions transparent.
// Parameters :
//  filename - name of stencil image
//  red/green/blue - color of transparent part in stencil image
// Returns    : Success or failure
function TGLBMP.Stencil(filename : String; red, green, blue : Byte) : Boolean;
var
  pixel : PGLRGBQUAD;
  alpha : PGLRGBQUAD;
  I : Integer;
  stencil : TGLBMP;
begin
  Result := True;

  // Initialize the stencil image
  stencil := TGLBMP.Create();
  
  // Make sure an image is loaded and that the stencil image is loaded
  if Assigned(rgbBits) and (stencil.LoadImage(filename)) then begin

    // Make sure image and stencil image are same dimensions
    if (stencil.Width <> Width) or (stencil.Height <> Height) then begin
      Result := False;
      stencil.Free();
      Exit;
    end;

    // Loop through image, if a pixel in the stencil image is equal to the 
    // color values passed in, the same pixel in the loaded image is set to
    // transparent
    for I := 0 to (Width*Height)-1 do begin
      pixel := Ptr(Integer(rgbBits) + I*4);
      alpha := Ptr(Integer(stencil.rgbBits) + I*4);

      if ((alpha.red = red) and (alpha.green = green) and (alpha.blue = blue)) then
        pixel.alpha := 0
      else
        pixel.alpha := 255;
    end;
    
  end else
    Result := False;

  stencil.Free();
end;

function TGLBMP.ToNormalMap(scale : Single) : Boolean;
const
  oneOver255 = 1.0/255.0;
var
  i, j : Integer;
  image : PByteArray;
  pixel : PGLRGBQUAD;
  p1, p2, p3 : Double;
  dcx, dcy : Double;
  len : Double;
  nx, ny, nz : Double;
begin
  Result := True;

  if (Assigned(rgbBits)) then begin
    image := PByteArray(rgbBits);
    pixel := rgbBits;
    for i := 0 to height-1 do begin
      for j := 0 to width-1 do begin
        p1 := image[(i*width + j)*4] * oneOver255;
        p2 := image[(i*width + (j+1))*4] * oneOver255;
        p3 := image[((i+1)*width + j)*4] * oneOver255;

        dcx := scale * (p2 - p1);
        dcy := scale * (p3 - p1);

        len :=  1.0/sqrt((dcx*dcx + dcy*dcy)+1);
        nx := dcy*len;
        ny := -dcx*len;
        nz := len;

        pixel.red := Trunc(128 + 127*nx);
        pixel.green := Trunc(128 + 127*ny);
        pixel.blue := Trunc(128 + 127*nz);
        pixel.alpha := 255;

        Inc(pixel);
      end;
    end;
  end else
    Result := False;
end;

// Name       : Load32
// Purpose    : Loads a 32bpp bitmap image
// Parameters :
//  bmpFile : Pointer to a open bitmap file
//  length : number of bytes in the image
// Returns    : Loaded bits or nil if there was a problem
procedure TGLBMP.Load32(imgFile : pFile);
var
  bytesRead : Integer;  // Used in read operations to check for errors
  size : Integer;
begin
  size := Width*Height*4;
  
  // Allocate enough memory to hold the BGR image
  GetMem(rgbBits, size);

  // Read in the bitmaps color bytes
  BlockRead(imgFile^, rgbBits^, size, bytesRead);
  if bytesRead <> size then begin
    CloseFile(imgFile^);
    Exit;
  end;

  SwapRB();
end;

// Name       : Load24
// Purpose    : Loads a 24bpp bitmap
// Parameters : Pointer to an open file, the file pointer must be pointing at
//              the bitmap data already
procedure TGLBMP.Load24(imgFile : pFile);
var
  bgrBits24 : PRGBTRIPLE;   // Temporary image buffer
  bytesRead : Integer;      // File IO error check
  pad : Integer;            // Line padding
begin
  // Calculate amount of padding at the end of each line in the image
  pad := GetLineWidth(24) - (Width*3);
  
  // Allocate enough memory for the temp bitmap
  GetMem(bgrBits24, imageSize);

  // Read in the bitmaps color bytes
  BlockRead(imgFile^, bgrBits24^, imageSize, bytesRead);
  if bytesRead <> imageSize then begin
    CloseFile(imgFile^);
    Exit;
  end;

  // Allocate memory for the bitmap
  GetMem(rgbBits, Width*Height*4);

  ExpandTo32(bgrBits24, pad, True);
  FreeMem(bgrBits24);

  ColorDepth := 32;
end;

// Name       : Load16
// Purpose    : Loads a 16bpp image into a 32bpp memory buffer
// Parameters :
//  bmpFile - Pointer to an open file with the file pointer at the bitmap bits
//  length - Number of bytes in source image
// Returns    : A pointer to the image data (in 32bpp RGB format)
procedure TGLBMP.Load16(imgFile : pFile);
var
  bytesRead : Integer;  // Error checker
  source16 : PWord;     // Pointer to 16bpp image
  dest : PGLRGBQUAD;    // Pointer to 32bpp image
  bgrBits16 : PWord;    // 16bpp image

  x, y : Integer;       // Loop counters

  pad : Integer;      // Amount to pad end of each line in 16bpp image

  redBits : Integer;    // Number of bits set in the redmask
  greenBits : Integer;  // Number of bits set in the greenmask
  blueBits : Integer;   // Number of bits set in the blue mask

  redShr : Integer;     // Amount to shift the red channel right
  greenShr : Integer;   // Amount to shift the green channel right

begin
  // Allocate enough memory for the temp bitmap
  GetMem(bgrBits16, imageSize);

  // Read in the bitmaps color bytes
  BlockRead(imgFile^, bgrBits16^, imageSize, bytesRead);
  if bytesRead <> imageSize then begin
    CloseFile(imgFile^);
    Exit;
  end;

  // Allocate memory to hold 32bpp image
  GetMem(rgbBits, Width*Height*4);

  // Calculate end of line padding
  pad := GetLineWidth(16) - (Width*SizeOf(Word));

  // Calculate the shift amounts (number of 0 bits before the first 1 (set) bit)
  redShr := GetRightShiftCount(palette.redMask);
  greenShr := GetRightShiftCount(palette.greenMask);

  // Calculate the number of set bits in the color mask
  redBits := GetNumSet(palette.redMask);
  greenBits := GetNumSet(palette.greenMask);
  blueBits := GetNumSet(palette.blueMask);

  source16 := bgrBits16;
  dest := rgbBits;

  // Loop through image getting color data extracting the red, green, and blue
  // channel data from the current word in the source image. This is done by
  // applying the mask to the source word and scaling the result (otherwise image
  // colors are faded)
  for x := 0 to Height-1 do begin
    for y := 0 to Width-1 do begin
      dest.red := Scale8(source16^ and Integer(palette.redMask) shr redShr, redBits);
      dest.green := Scale8(source16^ and Integer(palette.greenMask) shr greenShr, greenBits);
      dest.blue := Scale8(source16^ and Integer(palette.blueMask), blueBits);
      Inc(source16);
      Inc(dest);
    end;
    source16 := Ptr(Integer(source16) + pad);
  end;
  ColorDepth := 32;
  FreeMem(bgrBits16);
end;

// Name       : Load8
// Purpose    : Loads a 8bpp bitmap image into a 24bpp memory buffer
// Parameters :
//  bmpFile - Pointer to an open file with the file pointer at the bitmap bits
//  length - Number of bytes in source image
// Returns    : A pointer to the image data (in 24bpp RGB format)
procedure TGLBMP.Load8(imgFile : pFile);
var
  bytesRead : Integer;  // Error checker
  source8 : PByte;      // Pointer to 8bpp image
  dest : PGLRGBQUAD;  // Pointer to 24bpp image
  bgrBits8 : PByte;     // Temp image buffer
  x, y : Integer;       // Loop counters

  pad : Integer;       // Amount to pad end of each line in 8pp image
begin
  // Allocate enough memory for the temp bitmap
  GetMem(bgrBits8, imageSize);

  // Read in the bitmaps color bytes
  BlockRead(imgFile^, bgrBits8^, imageSize, bytesRead);
  if bytesRead <> imageSize then begin
    CloseFile(imgFile^);
    Exit;
  end;

  // Allocate memory to hold 32bpp image
  GetMem(rgbBits, Width*Height*4);

  // Calculate the amount to pad end of each line in 8pp image
  pad := GetLineWidth(8) - Width;

  source8 := bgrBits8;
  dest := rgbBits;

  // Loop through image getting color values from the palette
  for x := 0 to Height-1 do begin
    for y := 0 to Width-1 do begin
      dest.red := palette.Colors[source8^].rgbRed;
      dest.green := palette.Colors[source8^].rgbGreen;
      dest.blue := palette.Colors[source8^].rgbBlue;
      Inc(dest);
      Inc(source8);
    end;
    source8 := Ptr(Integer(source8) + pad);
  end;
  ColorDepth := 32;
  FreeMem(bgrBits8);
end;

// Name       : Load4
// Purpose    : Loads a 4bpp image into a 24bpp memory buffer
// Parameters :
//  bmpFile - Pointer to an open file with the file pointer at the bitmap bits
//  length - Number of bytes in source image
// Returns    : A pointer to the image data (in 24bpp RGB format)
procedure TGLBMP.Load4(imgFile : pFile);
var
  bytesRead : Integer;  // Error checker
  source4 : PByte;      // Pointer to 4bpp image
  dest : PGLRGBQUAD;    // Pointer to 24bpp image
  bgrBits4 : PByte;     // 4bpp image
  x, y : Integer;       // Loop counters

  pad : Integer;        // Amount to pad end of each line in 4pp image

  palEntry : Integer;   // Which palette entry to use
begin
  // Allocate enough memory for the bitmap
  GetMem(bgrBits4, imageSize);

  // Read in the bitmaps color bytes
  BlockRead(imgFile^, bgrBits4^, imageSize, bytesRead);
  if bytesRead <> imageSize then begin
    CloseFile(imgFile^);
    Exit;
  end;

  // Allocate memory for the bitmap
  GetMem(rgbBits, Width*Height*4);

  // Calculate amount to pad end of each line in 4bpp image
  pad := GetLineWidth(4) - (Width shr 1);

  source4 := bgrBits4;
  dest := rgbBits;

  // Loop through image reading pixel colors from the palette. Each
  // Byte in the source image is two pixels, the upper and lower nibble of
  // the byte contain an index into the palette for the image
  for x := 0 to Height-1 do begin
    for y := 0 to Width-1 do begin
      if Odd(y) then
        palEntry := Integer(source4^ and $F)
      else
        palEntry := Integer((source4^ shr 4) and $F);

      dest.red := palette.Colors[palEntry].rgbRed;
      dest.green := palette.Colors[palEntry].rgbGreen;
      dest.blue := palette.Colors[palEntry].rgbBlue;


      Inc(dest);
      if Odd(y) then
        Inc(source4);
    end;
    source4 := Ptr(Integer(source4) + pad);
  end;

  ColorDepth := 32;
  FreeMem(bgrBits4);
end;

// Name       : Invert
// Purpose    : Inverts the color data in the current bitmap
// Parameters : None
// Returns    : Success or failure
function TGLBMP.Invert() : Boolean;
var
  I : Integer;    // Loop counter
  pixel : PByte;  // pointer to current pixel
begin
  Result := True;

  // Make sure there is a bitmap to invert
  if Assigned(rgbBits) then begin
    pixel := PByte(rgbBits);

    // Loop through image, inverting the colors
    for I := 0 to Width*Height*4-1 do begin
      pixel^ := 255 - pixel^;
      Inc(pixel);
    end;
  end else
    Result := False;
end;

// Name       : FlipVert
// Purpose    : Flips the image vertically (around X axis)
// Parameters : None
// Returns    : Success or failure
function TGLBMP.FlipVert() : Boolean;
var
  I : Integer;            // Loop counter

  top : PGLRGBQUAD;          // Pointer to top line in the image
  bottom : PGLRGBQUAD;       // Pointer to bottom line in the image
  tmpBits : PGLRGBQUAD; // Temporarily holds one line in image
  line : Integer;
begin
  Result := True;
  if Assigned(rgbBits) then begin
    line := Width * 4;
    
    // Allocate enough memory in our temp buffer to hold a whole line
    // in the image
    GetMem(tmpBits, line);

    top := rgbBits;                                  // Point to top
    bottom := Ptr(Integer(rgbBits) + line*(Height-1));   // Point to bottom

    // Loop through image and swap the top and bottom lines, then move the top
    // pointer down a row and the bottom pointer up a row and repeat
    for I := 0 to (Height shr 1)-1 do begin
      Move(top^, tmpBits^, line);
      Move(bottom^, top^, line);
      Move(tmpBits^, bottom^, line);
      top := Ptr(Integer(top) + line);
      bottom := Ptr(Integer(bottom) - line);
    end;
    FreeMem(tmpBits);
  end else
    Result := False;
end;

// Name       : FlipHorz
// Purpose    : Flips the image horizontally (around Y axis)
// Parameters : None
// Returns    : Success or failure
function TGLBMP.FlipHorz() : Boolean;
var
  x, y : Integer;         // Loop counters

  // 32bpp image pointers
  front32 : PGLRGBQUAD;
  back32 : PGLRGBQUAD;
  tmp32 : TGLRGBQUAD;     // Temp buffer for swapping pixels

  line : Integer;
begin
  Result := True;
  if Assigned(rgbBits) then begin
    line := Width*4;
    for y := 0 to Height-1 do begin
      // Point to the front of the current line
      front32 := Ptr(Integer(rgbBits) + line*y);

      // Point to the end of the current line
      back32 := Ptr(Integer(rgbBits) + (line*y) + line-4);

      // Swap each pixel in the line
      for x := 0 to (Width shr 1)-1 do begin
        tmp32 := front32^;
        front32^ := back32^;
        back32^ := tmp32;
        Inc(front32);
        Dec(back32);
      end;
    end;
  end else
    Result := False;
end;

// Name       : Rotate180
// Purpose    : Rotates the image 180 degrees by using the FlipHorz and FlipVert
//              functions together
// Parameters : None
// Returns    : Success or failure
function TGLBMP.Rotate180() : Boolean;
begin
  Result := True;
  // First flip it horizontally
  if not (FlipHorz()) then begin
    Result := False;
    Exit;
  end;

  // Then flip it vertically
  if not (FlipVert()) then begin
    Result := False;
    Exit;
  end;
end;

// Name       : SetJPGQuality
// Purpose    : Sets the JPG saving quality, all further JPG saves use this
//              quality setting
// Parameters : Desired quality (quality is clamped between 1 and 100)
procedure TGLBMP.SetJPGQuality(quality : Integer);
begin
  // Clamp the quality in the range between 1 and 100
  if quality > 100 then quality := 100;
  if quality < 1 then quality := 1;

  // Set JPG quality
  jpgQuality := quality;
end;

// Name       : GenTexture
// Purpose    : Generates an OpenGL texture from the currently loaded image, this texture
//              can be used (applyed to a surface) by calling the Bind function before drawing
//              geometry
// Parameters : None
procedure TGLBMP.GenTexture(pS3TC, pAni : Boolean);
var
 MaxAnisotropy : integer;
begin

end;


// Name       : GetWidth
// Desription : Gets the current image width
// Returns    : image width
function TGLBMP.GetWidth() : Integer;
begin
  Result := width;
end;

// Name       : GetHeight
// Desription : Gets the current image height
// Returns    : image height
function TGLBMP.GetHeight() : Integer;
begin
  Result := height;
end;

// Name       : GetData
// Desription : Gets the current image data
// Returns    : pointer to image data
function TGLBMP.GetData() : Pointer;
begin
  Result := PByte(rgbBits);
end;

// Name       : Scale8
// Purpose    : Scales the color value for a pixel in a 8bpp image
// Parameters :
//  colorValue - value to be scaled
//  colorBits - number of set bits in the color mask for this color
// Returns    : Scaled value (0-255)
function TGLBMP.Scale8(colorValue, colorBits : Integer) : Integer;
begin
  case colorBits of
    1: if Boolean(colorValue) then Result := 255 else Result := 0;
    2: Result := (colorValue shl 6) or (colorValue shl 4) or (colorValue shl 2)or colorValue;
    3: Result := (colorValue shl 5) or (colorValue shl 2) or (colorValue shr 1);
    4: Result := (colorValue shl 4) or colorValue;
    5: Result := (colorValue shl 3) or (colorValue shr 2);
    6: Result := (colorValue shl 2) or (colorValue shr 4);
    7: Result := (colorValue shl 1) or (colorValue shr 6);
    else Result := colorValue;
  end;
end;

function TGLBMP.GetLineWidth(bpp : Integer) : Integer;
begin
  Result := ((Width * bpp + 31) and - 32) shr 3;
end;

// Name       : GetRightShiftCount
// Purpose    : Calculates the amount needed to shift the color mask right
// Parameters :
//  dwVal - the color mask
// Returns    : Number of 0's before first set bit
function TGLBMP.GetRightShiftCount(dwVal : DWord): Integer;
var
  I : Integer;
begin
  for I := 0 to SizeOf(DWORD)*8 do begin
    if ((dwVal and 1) = 1) then begin
      Result := I;
      Exit;
    end;
    dwVal := dwVal shr 1;
  end;
  Result := -1;
end;

// Name       : GetNumSet
// Purpose    : Gets the number of set bits in the color mask
// Parameters :
//  dwVal - color mask
// Returns    : number of set bits
function TGLBMP.GetNumSet(dwVal : DWord): Integer;
var
  nCount : Integer;
begin
  nCount := 0;
  while (dwVal <> 0) do begin
    Inc(nCount, (dwVal and 1));
    dwVal := dwVal shr 1;
  end;

  Result := nCount;
end;

// Name       : SwapRB
// Desription : Swaps the red and blue channels for a 32bpp image
// Parameters : None
procedure TGLBMP.SwapRB();
var
  x, y : Integer;
  pixel : PGLRGBQUAD;
  tmp : Byte;
begin
  // Loop through buffer swapping red and blue channels
  pixel := rgbBits;
  for x := 0 to Width - 1 do begin
    for y := 0 to Height - 1 do begin
      tmp := pixel.blue;
      pixel.blue := pixel.red;
      pixel.red := tmp;

      Inc(pixel);    
    end;
  end;
end;

// Name       : ExpandTo32
// Desription : Takes the passed in image buffer and expands it from 24bpp into
//              the rgbBits 32bpp buffer.
// Parameters :
//  image - Pointer to the 24bpp image buffer
//  pad - Amount of padding at the end of each line in the 24bpp image
//  swapRB - Whether to swap the red and blue channels
// Returns    :
procedure TGLBMP.ExpandTo32(image : Pointer; pad : Integer; swapRB : Boolean);
var
  x, y : Integer;
  pixel24 : PGLRGBTRIPLE;
  pixel32 : PGLRGBQUAD;
begin

  // Loop through memory buffer copying it into 32bpp buffer and swapping
  // red/blue channels if neccessary
  pixel24 := image;
  pixel32 := rgbBits;
  for x := 0 to Width-1 do begin
    for y := 0 to Height-1 do begin

      if swapRB then begin
        pixel32.red := pixel24.blue;
        pixel32.blue := pixel24.red;
      end else begin
        pixel32.red := pixel24.red;
        pixel32.blue := pixel24.blue;
      end;
      pixel32.green := pixel24.green;
  
      Inc(pixel24);
      Inc(pixel32);
    end;
    pixel24 := Ptr(Integer(pixel24) + pad);
  end;
end;

// Name       : SetAlpha
// Desription : Sets the alpha channel for an image to one value
// Parameters : 
//  alpha - desired alpha value
procedure TGLBMP.SetAlpha(alpha : Byte);
var
  I : Integer;
  pixel : PGLRGBQUAD;
begin
  pixel := rgbBits;
  for I := 0 to Width*Height - 1 do begin
    pixel.alpha := alpha;
    Inc(pixel);
  end;  
end;

// Name       : ClearMem
// Purpose    : Free's image memory
// Parameters : None
procedure TGLBMP.ClearMem;
begin
  if Assigned(rgbBits) then begin
    FreeMem(rgbBits);
    rgbBits := nil;
  end;
end;

// Name       : Destroy
// Purpose    : Frees used memory
// Parameters : None
destructor TGLBMP.Destroy;
begin
  // Free memory used by bitmap
  ClearMem();

  // Free the PNG libraries

  
  inherited Destroy;
end;

end.
