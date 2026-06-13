unit uMCPConfig;

interface

type
  TMCPTransport = (mtStdio, mtHttp);

  TMCPConfig = record
    Transport: TMCPTransport;
    HttpHost: string;
    HttpPort: Integer;
    HttpPath: string;
    DebugLog: Boolean;
    class function Load: TMCPConfig; static;
  end;

implementation

uses
  System.SysUtils, System.Classes;

function ParamValue(const Name: string): string;
var
  I: Integer;
  Arg, Key: string;
  P: Integer;
begin
  Result := '';
  for I := 1 to ParamCount do
  begin
    Arg := ParamStr(I);
    if SameText(Arg, Name) then
    begin
      if I < ParamCount then
        Result := ParamStr(I + 1);
      Exit;
    end;
    P := Pos('=', Arg);
    if P > 0 then
    begin
      Key := Copy(Arg, 1, P - 1);
      if SameText(Key, Name) then
        Exit(Copy(Arg, P + 1, MaxInt));
    end;
  end;
end;

function HasSwitch(const Name: string): Boolean;
var
  I: Integer;
begin
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), Name) then
      Exit(True);
  Result := False;
end;

function EnvOr(const Name, Default: string): string;
begin
  Result := GetEnvironmentVariable(Name);
  if Result = '' then
    Result := Default;
end;

class function TMCPConfig.Load: TMCPConfig;
var
  TransportEnv, PortStr: string;
begin
  TransportEnv := EnvOr('MEDIA_MCP_TRANSPORT', '');
  if HasSwitch('--stdio') or SameText(TransportEnv, 'stdio') then
    Result.Transport := mtStdio
  else
    Result.Transport := mtHttp;

  Result.HttpHost := ParamValue('--host');
  if Result.HttpHost = '' then
    Result.HttpHost := EnvOr('MEDIA_MCP_HTTP_HOST', '127.0.0.1');

  PortStr := ParamValue('--port');
  if PortStr = '' then
    PortStr := EnvOr('MEDIA_MCP_HTTP_PORT', '8765');
  Result.HttpPort := StrToIntDef(PortStr, 8765);

  Result.HttpPath := ParamValue('--path');
  if Result.HttpPath = '' then
    Result.HttpPath := EnvOr('MEDIA_MCP_HTTP_PATH', '/mcp');
  if (Result.HttpPath = '') or (Result.HttpPath[1] <> '/') then
    Result.HttpPath := '/' + Result.HttpPath;

  Result.DebugLog := (EnvOr('MEDIA_MCP_DEBUG', '') <> '');
end;

end.
