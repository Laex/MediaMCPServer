unit uMCPServer;

interface

uses
  System.SysUtils, Winapi.Windows, uMCPHandler;

type
  TMCPServer = class
  private
    FStdInHandle: THandle;
    FLineBuffer: TBytes;
    FReadBuffer: array [0 .. 8191] of Byte;
    FHandler: TMCPHandler;
    procedure PrepareStdInPipe;
    procedure AppendToLineBuffer(const Chunk: TBytes);
    function TryExtractLine(out Line: string): Boolean;
    function ReadNextLine(out Line: string): Boolean;
    procedure SendResponse(const JsonText: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run;
  end;

implementation

constructor TMCPServer.Create;
var
  DebugLog: Boolean;
begin
  inherited Create;
  PrepareStdInPipe;
  SetLength(FLineBuffer, 0);
  DebugLog := GetEnvironmentVariable('MEDIA_MCP_DEBUG') <> '';
  FHandler := TMCPHandler.Create(DebugLog);
end;

destructor TMCPServer.Destroy;
begin
  FHandler.Free;
  inherited Destroy;
end;

procedure TMCPServer.PrepareStdInPipe;
var
  Mode: DWORD;
begin
  FStdInHandle := GetStdHandle(STD_INPUT_HANDLE);
  if GetConsoleMode(FStdInHandle, Mode) then
    SetConsoleMode(FStdInHandle, Mode and not (ENABLE_LINE_INPUT or ENABLE_ECHO_INPUT));
end;

procedure TMCPServer.AppendToLineBuffer(const Chunk: TBytes);
var
  OldLen: Integer;
begin
  if Length(Chunk) = 0 then
    Exit;
  OldLen := Length(FLineBuffer);
  SetLength(FLineBuffer, OldLen + Length(Chunk));
  Move(Chunk[0], FLineBuffer[OldLen], Length(Chunk));
end;

function TMCPServer.TryExtractLine(out Line: string): Boolean;
var
  I, LineLen: Integer;
  Chunk: TBytes;
begin
  Result := False;
  Line := '';
  for I := 0 to High(FLineBuffer) do
  begin
    if FLineBuffer[I] <> 10 then
      Continue;
    LineLen := I;
    if (LineLen > 0) and (FLineBuffer[LineLen - 1] = 13) then
      Dec(LineLen);
    SetLength(Chunk, LineLen);
    if LineLen > 0 then
      Move(FLineBuffer[0], Chunk[0], LineLen);
    if I < High(FLineBuffer) then
      FLineBuffer := Copy(FLineBuffer, I + 1, MaxInt)
    else
      SetLength(FLineBuffer, 0);
    Line := TEncoding.UTF8.GetString(Chunk);
    Exit(True);
  end;
end;

function TMCPServer.ReadNextLine(out Line: string): Boolean;
var
  BytesRead: DWORD;
  Chunk: TBytes;
begin
  Line := '';
  while True do
  begin
    if TryExtractLine(Line) then
      Exit(True);

    if not ReadFile(FStdInHandle, FReadBuffer[0], Length(FReadBuffer), BytesRead, nil) then
      Break;
    if BytesRead = 0 then
      Break;

    SetLength(Chunk, BytesRead);
    Move(FReadBuffer[0], Chunk[0], BytesRead);
    AppendToLineBuffer(Chunk);
  end;

  if Length(FLineBuffer) > 0 then
  begin
    Line := TEncoding.UTF8.GetString(FLineBuffer);
    SetLength(FLineBuffer, 0);
    Exit(Line <> '');
  end;
end;

procedure TMCPServer.SendResponse(const JsonText: string);
var
  Utf8: TBytes;
  Written: DWORD;
begin
  if JsonText = '' then
    Exit;
  Utf8 := TEncoding.UTF8.GetBytes(JsonText + #10);
  if Length(Utf8) > 0 then
  begin
    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), Utf8[0], Length(Utf8), Written, nil);
    FlushFileBuffers(GetStdHandle(STD_OUTPUT_HANDLE));
  end;
end;

procedure TMCPServer.Run;
var
  Line, Response: string;
begin
  while ReadNextLine(Line) do
  begin
    if Line = '' then
      Continue;
    try
      Response := FHandler.ProcessMessage(Line);
      SendResponse(Response);
    except
      on E: Exception do
        SendResponse(Format('{"jsonrpc":"2.0","error":{"code":-32603,"message":"%s"}}',
          [StringReplace(E.Message, '"', '\"', [rfReplaceAll])]));
    end;
  end;
end;

end.
