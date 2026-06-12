unit uMCPHttpServer;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.SyncObjs,
  uMCPHandler, uMCPConfig;

type
  TMCPHttpServer = class
  private
    FConfig: TMCPConfig;
    FHandler: TMCPHandler;
    FSessions: TDictionary<string, Byte>;
    FSessionLock: TCriticalSection;
    FRunning: Boolean;
    function CreateSessionId: string;
    function SessionExists(const SessionId: string): Boolean;
    procedure AddSession(const SessionId: string);
    procedure RemoveSession(const SessionId: string);
    procedure HandleConnection(ASocket: NativeUInt);
    function RecvLine(ASocket: NativeUInt; out Line: AnsiString): Boolean;
    function RecvExact(ASocket: NativeUInt; Count: Integer): AnsiString;
    procedure SendRaw(ASocket: NativeUInt; const Data: AnsiString);
    procedure ProcessHttpRequest(ASocket: NativeUInt; const Method, Path, Body: string;
      const Headers: TDictionary<string, string>);
    function HeaderValue(const Headers: TDictionary<string, string>; const Name: string): string;
    function IsOriginAllowed(const Origin: string): Boolean;
    function IsProtocolVersionAllowed(const Version: string): Boolean;
    function NormalizePath(const Path: string): string;
  public
    constructor Create(const AConfig: TMCPConfig);
    destructor Destroy; override;
    procedure Run;
    procedure Stop;
  end;

implementation

uses
  Winapi.Windows, Winapi.WinSock2, System.JSON, System.StrUtils;

function InitWinSock: Boolean;
var
  Wsa: TWsaData;
begin
  Result := WSAStartup(MAKEWORD(2, 2), Wsa) = 0;
end;

procedure DoneWinSock;
begin
  WSACleanup;
end;

function Ipv4AddrToString(Addr: Cardinal): string;
var
  Bytes: array[0..3] of Byte absolute Addr;
begin
  Result := Format('%d.%d.%d.%d', [Bytes[0], Bytes[1], Bytes[2], Bytes[3]]);
end;

constructor TMCPHttpServer.Create(const AConfig: TMCPConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FHandler := TMCPHandler.Create(AConfig.DebugLog);
  FSessions := TDictionary<string, Byte>.Create;
  FSessionLock := TCriticalSection.Create;
  FRunning := False;
end;

destructor TMCPHttpServer.Destroy;
begin
  Stop;
  FSessionLock.Free;
  FSessions.Free;
  FHandler.Free;
  inherited Destroy;
end;

function TMCPHttpServer.CreateSessionId: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := GUIDToString(G);
  Result := StringReplace(Result, '{', '', [rfReplaceAll]);
  Result := StringReplace(Result, '}', '', [rfReplaceAll]);
end;

function TMCPHttpServer.SessionExists(const SessionId: string): Boolean;
begin
  FSessionLock.Enter;
  try
    Result := (SessionId <> '') and FSessions.ContainsKey(SessionId);
  finally
    FSessionLock.Leave;
  end;
end;

procedure TMCPHttpServer.AddSession(const SessionId: string);
begin
  FSessionLock.Enter;
  try
    FSessions.AddOrSetValue(SessionId, 1);
  finally
    FSessionLock.Leave;
  end;
end;

procedure TMCPHttpServer.RemoveSession(const SessionId: string);
begin
  FSessionLock.Enter;
  try
    FSessions.Remove(SessionId);
  finally
    FSessionLock.Leave;
  end;
end;

procedure TMCPHttpServer.Stop;
begin
  FRunning := False;
end;

function TMCPHttpServer.NormalizePath(const Path: string): string;
var
  P: Integer;
begin
  Result := Path;
  P := Pos('?', Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
  if Result = '' then
    Result := '/';
end;

function TMCPHttpServer.HeaderValue(const Headers: TDictionary<string, string>; const Name: string): string;
var
  Key: string;
begin
  Result := '';
  for Key in Headers.Keys do
    if SameText(Key, Name) then
      Exit(Headers.Items[Key]);
end;

function TMCPHttpServer.IsOriginAllowed(const Origin: string): Boolean;
begin
  if Origin = '' then
    Exit(True);
  Result := StartsText('http://127.0.0.1', Origin) or
            StartsText('http://localhost', Origin) or
            StartsText('https://127.0.0.1', Origin) or
            StartsText('https://localhost', Origin);
end;

function TMCPHttpServer.IsProtocolVersionAllowed(const Version: string): Boolean;
begin
  if Version = '' then
    Exit(True);
  Result := (Version = '2024-11-05') or (Version = '2025-03-26') or (Version = '2025-11-25');
end;

procedure TMCPHttpServer.SendRaw(ASocket: NativeUInt; const Data: AnsiString);
var
  Sent, Total, N: Integer;
  Ptr: PAnsiChar;
begin
  Total := Length(Data);
  Ptr := PAnsiChar(Data);
  Sent := 0;
  while Sent < Total do
  begin
    N := send(ASocket, Ptr[Sent], Total - Sent, 0);
    if N <= 0 then
      Break;
    Inc(Sent, N);
  end;
end;

function TMCPHttpServer.RecvLine(ASocket: NativeUInt; out Line: AnsiString): Boolean;
var
  Ch: AnsiChar;
  N: Integer;
begin
  Line := '';
  Result := False;
  while True do
  begin
    N := recv(ASocket, Ch, 1, 0);
    if N <= 0 then
      Exit;
    if Ch = #10 then
      Break;
    if Ch <> #13 then
      Line := Line + Ch;
  end;
  Result := True;
end;

function TMCPHttpServer.RecvExact(ASocket: NativeUInt; Count: Integer): AnsiString;
var
  Buf: AnsiString;
  Received, N: Integer;
begin
  SetLength(Buf, Count);
  Received := 0;
  while Received < Count do
  begin
    N := recv(ASocket, Buf[Received + 1], Count - Received, 0);
    if N <= 0 then
      Break;
    Inc(Received, N);
  end;
  SetLength(Buf, Received);
  Result := Buf;
end;

procedure TMCPHttpServer.ProcessHttpRequest(ASocket: NativeUInt; const Method, Path, Body: string;
  const Headers: TDictionary<string, string>);
var
  SessionId, AcceptHdr, ProtoHdr, ResponseJson, MethodName: string;
  StatusCode: Integer;
  StatusText, ContentType, ExtraHeaders, ResponseBody: string;
  JsonReq: TJSONObject;
  JsonVal: TJSONValue;
begin
  StatusCode := 200;
  StatusText := 'OK';
  ContentType := 'application/json';
  ExtraHeaders := '';
  ResponseBody := '';

  if not SameText(NormalizePath(Path), FConfig.HttpPath) then
  begin
    StatusCode := 404;
    StatusText := 'Not Found';
    ContentType := 'text/plain';
    ResponseBody := 'Not Found';
  end
  else if not IsOriginAllowed(HeaderValue(Headers, 'Origin')) then
  begin
    StatusCode := 403;
    StatusText := 'Forbidden';
    ContentType := 'application/json';
    ResponseBody := '{"jsonrpc":"2.0","error":{"code":-32600,"message":"Invalid Origin"}}';
  end
  else if SameText(Method, 'GET') then
  begin
    StatusCode := 405;
    StatusText := 'Method Not Allowed';
    ContentType := 'text/plain';
    ResponseBody := 'SSE stream not supported';
  end
  else if SameText(Method, 'DELETE') then
  begin
    SessionId := HeaderValue(Headers, 'Mcp-Session-Id');
    if SessionId = '' then
    begin
      StatusCode := 400;
      StatusText := 'Bad Request';
      ContentType := 'text/plain';
      ResponseBody := 'Missing Mcp-Session-Id';
    end
    else
    begin
      RemoveSession(SessionId);
      StatusCode := 200;
      StatusText := 'OK';
      ContentType := 'text/plain';
      ResponseBody := '';
    end;
  end
  else if SameText(Method, 'POST') then
  begin
    AcceptHdr := HeaderValue(Headers, 'Accept');
    if (Pos('application/json', AcceptHdr) = 0) or (Pos('text/event-stream', AcceptHdr) = 0) then
    begin
      StatusCode := 400;
      StatusText := 'Bad Request';
      ContentType := 'text/plain';
      ResponseBody := 'Accept must include application/json and text/event-stream';
    end
    else
    begin
      ProtoHdr := HeaderValue(Headers, 'Mcp-Protocol-Version');
      if not IsProtocolVersionAllowed(ProtoHdr) then
      begin
        StatusCode := 400;
        StatusText := 'Bad Request';
        ContentType := 'application/json';
        ResponseBody := '{"jsonrpc":"2.0","error":{"code":-32600,"message":"Unsupported MCP-Protocol-Version"}}';
      end
      else
      begin
        SessionId := HeaderValue(Headers, 'Mcp-Session-Id');
        MethodName := '';
        JsonVal := TJSONObject.ParseJSONValue(Body);
        if not (JsonVal is TJSONObject) then
        begin
          if Assigned(JsonVal) then
            JsonVal.Free;
          StatusCode := 400;
          StatusText := 'Bad Request';
          ContentType := 'text/plain';
          ResponseBody := 'Invalid JSON body';
        end
        else
        try
          JsonReq := JsonVal as TJSONObject;
          JsonReq.TryGetValue<string>('method', MethodName);

          if SameText(MethodName, 'initialize') then
          begin
            if SessionId <> '' then
              RemoveSession(SessionId);
            SessionId := CreateSessionId;
            AddSession(SessionId);
            ResponseJson := FHandler.ProcessMessage(Body);
            if ResponseJson = '' then
            begin
              StatusCode := 202;
              StatusText := 'Accepted';
              ContentType := '';
            end
            else
            begin
              StatusCode := 200;
              StatusText := 'OK';
              ContentType := 'application/json';
              ResponseBody := ResponseJson;
            end;
            ExtraHeaders := ExtraHeaders + 'Mcp-Session-Id: ' + SessionId + #13#10;
          end
          else if SessionId = '' then
          begin
            StatusCode := 400;
            StatusText := 'Bad Request';
            ContentType := 'text/plain';
            ResponseBody := 'Missing Mcp-Session-Id';
          end
          else if not SessionExists(SessionId) then
          begin
            StatusCode := 404;
            StatusText := 'Not Found';
            ContentType := 'text/plain';
            ResponseBody := 'Session not found';
          end
          else
          begin
            ResponseJson := FHandler.ProcessMessage(Body);
            if ResponseJson = '' then
            begin
              StatusCode := 202;
              StatusText := 'Accepted';
              ContentType := '';
            end
            else
            begin
              StatusCode := 200;
              StatusText := 'OK';
              ContentType := 'application/json';
              ResponseBody := ResponseJson;
              ExtraHeaders := ExtraHeaders + 'Mcp-Session-Id: ' + SessionId + #13#10;
            end;
          end;
        finally
          JsonVal.Free;
        end;
      end;
    end;
  end
  else
  begin
    StatusCode := 405;
    StatusText := 'Method Not Allowed';
    ContentType := 'text/plain';
    ResponseBody := 'Unsupported method';
  end;

  if ContentType <> '' then
    ExtraHeaders := ExtraHeaders + 'Content-Type: ' + ContentType + #13#10;
  ExtraHeaders := ExtraHeaders + Format('Content-Length: %d'#13#10, [Length(UTF8Encode(ResponseBody))]);
  SendRaw(ASocket, AnsiString(Format('HTTP/1.1 %d %s'#13#10, [StatusCode, StatusText]) + ExtraHeaders + #13#10));
  if ResponseBody <> '' then
    SendRaw(ASocket, UTF8Encode(ResponseBody));
end;

procedure TMCPHttpServer.HandleConnection(ASocket: NativeUInt);
var
  RequestLine, Line, Method, Path, Body, Key, Value: string;
  Headers: TDictionary<string, string>;
  ContentLength, P: Integer;
  RawLine, RawBody: AnsiString;
begin
  Headers := TDictionary<string, string>.Create;
  try
    if not RecvLine(ASocket, RawLine) then
      Exit;
    RequestLine := string(RawLine);
    Method := '';
    Path := '/';
    if RequestLine <> '' then
    begin
      P := Pos(' ', RequestLine);
      if P > 0 then
      begin
        Method := Copy(RequestLine, 1, P - 1);
        Delete(RequestLine, 1, P);
        while (RequestLine <> '') and (RequestLine[1] = ' ') do
          Delete(RequestLine, 1, 1);
        P := Pos(' ', RequestLine);
        if P > 0 then
          Path := Copy(RequestLine, 1, P - 1)
        else
          Path := RequestLine;
      end;
    end;

    while RecvLine(ASocket, RawLine) do
    begin
      Line := string(RawLine);
      if Line = '' then
        Break;
      P := Pos(':', Line);
      if P > 0 then
      begin
        Key := Trim(Copy(Line, 1, P - 1));
        Value := Trim(Copy(Line, P + 1, MaxInt));
        Headers.AddOrSetValue(Key, Value);
      end;
    end;

    ContentLength := StrToIntDef(HeaderValue(Headers, 'Content-Length'), 0);
    Body := '';
    if ContentLength > 0 then
    begin
      RawBody := RecvExact(ASocket, ContentLength);
      Body := UTF8ToString(RawBody);
    end;

    ProcessHttpRequest(ASocket, Method, Path, Body, Headers);
  finally
    Headers.Free;
    closesocket(ASocket);
  end;
end;

procedure TMCPHttpServer.Run;
var
  ListenSock, ClientSock: NativeUInt;
  Addr, ClientAddr: TSockAddrIn;
  SockAddr, ClientSockAddr: TSockAddr;
  AddrLen: Integer;
  Opt: Integer;
  HostAnsi: AnsiString;
begin
  if not InitWinSock then
    raise Exception.Create('WSAStartup failed');

  try
    ListenSock := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if ListenSock = INVALID_SOCKET then
      raise Exception.Create('socket() failed');

    try
      Opt := 1;
      setsockopt(ListenSock, SOL_SOCKET, SO_REUSEADDR, PAnsiChar(@Opt), SizeOf(Opt));

      FillChar(Addr, SizeOf(Addr), 0);
      Addr.sin_family := AF_INET;
      Addr.sin_port := htons(FConfig.HttpPort);
      if (FConfig.HttpHost = '0.0.0.0') or (FConfig.HttpHost = '') then
        Addr.sin_addr.S_addr := INADDR_ANY
      else
      begin
        HostAnsi := AnsiString(FConfig.HttpHost);
        Addr.sin_addr.S_addr := inet_addr(PAnsiChar(HostAnsi));
      end;

      Move(Addr, SockAddr, SizeOf(Addr));
      if bind(ListenSock, SockAddr, SizeOf(Addr)) = SOCKET_ERROR then
        raise Exception.CreateFmt('bind(%s:%d) failed', [FConfig.HttpHost, FConfig.HttpPort]);

      if listen(ListenSock, SOMAXCONN) = SOCKET_ERROR then
        raise Exception.Create('listen() failed');

      FRunning := True;
      Writeln(ErrOutput, Format('[media-mcp] Streamable HTTP listening on http://%s:%d%s',
        [FConfig.HttpHost, FConfig.HttpPort, FConfig.HttpPath]));

      while FRunning do
      begin
        FillChar(ClientSockAddr, SizeOf(ClientSockAddr), 0);
        AddrLen := SizeOf(ClientSockAddr);
        ClientSock := accept(ListenSock, @ClientSockAddr, @AddrLen);
        if ClientSock = INVALID_SOCKET then
          Continue;
        HandleConnection(ClientSock);
      end;
    finally
      closesocket(ListenSock);
    end;
  finally
    DoneWinSock;
  end;
end;

end.
