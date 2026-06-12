unit uMCPServer;

interface

uses
  System.SysUtils, System.Classes, Winapi.Windows, uMCPHandler;

type
  TMCPServer = class
  private
    FInputReader: TStreamReader;
    FHandler: TMCPHandler;
    procedure SendResponse(const JsonText: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run;
  end;

implementation

constructor TMCPServer.Create;
var
  StdInHandle: THandle;
  InStream: THandleStream;
  DebugLog: Boolean;
begin
  inherited Create;
  StdInHandle := GetStdHandle(STD_INPUT_HANDLE);
  InStream := THandleStream.Create(StdInHandle);
  FInputReader := TStreamReader.Create(InStream, TEncoding.UTF8);
  DebugLog := GetEnvironmentVariable('MEDIA_MCP_DEBUG') <> '';
  FHandler := TMCPHandler.Create(DebugLog);
end;

destructor TMCPServer.Destroy;
begin
  FHandler.Free;
  FInputReader.Free;
  inherited Destroy;
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
  while not FInputReader.EndOfStream do
  begin
    Line := FInputReader.ReadLine;
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
