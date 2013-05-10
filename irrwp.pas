unit irrwp;

interface
uses windows;


type
void=pointer;


procedure  CreateEngine( hWnd,   dwWidth,  dwHeight:integer;VSync:boolean );stdcall external 'irrwp.dll';
procedure  FreeEngine();stdcall external 'irrwp.dll';

procedure  BeginScene( R,  G,  B :integer );stdcall external 'irrwp.dll';
procedure  DrawScene();stdcall external 'irrwp.dll';
procedure  EndScene();stdcall external 'irrwp.dll';
procedure   SetRenderTarget( target:void;clearBackBuffer,  clearZBuffe:integer; color:dword);stdcall external 'irrwp.dll';
procedure  DrawSceneToTexture (  renderTarget:void; R,  G,  B :integer);stdcall external 'irrwp.dll';




procedure  TargetCamera( x, y, z:single);stdcall external 'irrwp.dll';

procedure  PositionCamera( x, y, z:single);stdcall external 'irrwp.dll';

procedure  RotateCamera(  x,  y,  z:single);stdcall external 'irrwp.dll';


procedure  PositionNode(node:VOID;  x,  y,  z:single);stdcall external 'irrwp.dll';

procedure  RotateNode(node:VOID;  x,  y,  z:single);stdcall external 'irrwp.dll';

procedure  ScaleNode(node:VOID;  x,  y,  z:single);stdcall external 'irrwp.dll';

procedure  TurnNode(node:VOID;  x,  y,  z:single);stdcall external 'irrwp.dll';

procedure  TextureNode(node:VOID; filename:pchar;Layer:integer );stdcall external 'irrwp.dll';

procedure  ParentNode(node,PARENT:VOID);stdcall external 'irrwp.dll';




FUNCTION LoadNode(filename:pchar):VOID;stdcall external 'irrwp.dll';


procedure  SetFrameLoop(node:VOID; ibegin, iend:integer);stdcall external 'irrwp.dll';


procedure  SetCurrentFrame(node:VOID; iframe:integer) ;stdcall external 'irrwp.dll';


function GetCurrentFrame(node:VOID):integer ;stdcall external 'irrwp.dll';

function  GetStartFrame(node:VOID):integer;stdcall external 'irrwp.dll';

function  GetEndFrame(node:VOID):integer;stdcall external 'irrwp.dll';


function GetJointNode(node:VOID;value:integer):void   ;stdcall external 'irrwp.dll';

function NumJointNodes(node:VOID):integer;stdcall external 'irrwp.dll';




procedure  SetAnimationSpeed(node:VOID; value:single) ;stdcall external 'irrwp.dll';





implementation

end.
