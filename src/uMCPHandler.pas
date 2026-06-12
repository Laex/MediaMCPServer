unit uMCPHandler;

interface

uses
  System.SysUtils, System.Classes, System.JSON;

type
  TMCPHandler = class
  private
    FDebugLog: Boolean;
    procedure Log(const Msg: string);
    function BuildInitializeResponse(const Id: TJSONValue; Params: TJSONObject): string;
    function BuildPingResponse(const Id: TJSONValue): string;
    function BuildEmptyListResponse(const Id: TJSONValue; const ListKey: string): string;
    function BuildToolsListResponse(const Id: TJSONValue): string;
    function BuildToolsCallResponse(const Id: TJSONValue; Params: TJSONObject): string;
    function BuildErrorResponse(const Id: TJSONValue; Code: Integer; const Msg: string): string;
  public
    constructor Create(ADebugLog: Boolean = False);
    function ProcessMessage(const JsonText: string): string;
  end;

implementation

uses
  uMediaEngine, Winapi.Windows;

constructor TMCPHandler.Create(ADebugLog: Boolean);
begin
  inherited Create;
  FDebugLog := ADebugLog;
end;

procedure TMCPHandler.Log(const Msg: string);
var
  Buffer: TBytes;
  Written: DWORD;
  LogLine: string;
begin
  if not FDebugLog then
    Exit;
  LogLine := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' [media-mcp] ' + Msg + #10;
  Buffer := TEncoding.UTF8.GetBytes(LogLine);
  if Length(Buffer) > 0 then
    WriteFile(GetStdHandle(STD_ERROR_HANDLE), Buffer[0], Length(Buffer), Written, nil);
end;

function TMCPHandler.BuildErrorResponse(const Id: TJSONValue; Code: Integer; const Msg: string): string;
var
  Response, ErrObj: TJSONObject;
begin
  Response := TJSONObject.Create;
  try
    Response.AddPair('jsonrpc', '2.0');
    if Id <> nil then
      Response.AddPair('id', Id.Clone as TJSONValue)
    else
      Response.AddPair('id', TJSONNull.Create);
    ErrObj := TJSONObject.Create;
    ErrObj.AddPair('code', TJSONNumber.Create(Code));
    ErrObj.AddPair('message', Msg);
    Response.AddPair('error', ErrObj);
    Result := Response.ToJSON;
  finally
    Response.Free;
  end;
end;

function TMCPHandler.BuildInitializeResponse(const Id: TJSONValue; Params: TJSONObject): string;
var
  Response, ResultObj, ServerInfo, Capabilities, ToolsCap: TJSONObject;
  ProtocolVersion: string;
begin
  Response := TJSONObject.Create;
  try
    Response.AddPair('jsonrpc', '2.0');
    if Id <> nil then
      Response.AddPair('id', Id.Clone as TJSONValue)
    else
      Response.AddPair('id', TJSONNull.Create);

    ResultObj := TJSONObject.Create;
    ProtocolVersion := '2024-11-05';
    if Params <> nil then
      Params.TryGetValue<string>('protocolVersion', ProtocolVersion);
    if ProtocolVersion = '' then
      ProtocolVersion := '2024-11-05';
    ResultObj.AddPair('protocolVersion', ProtocolVersion);

    Capabilities := TJSONObject.Create;
    ToolsCap := TJSONObject.Create;
    Capabilities.AddPair('tools', ToolsCap);
    ResultObj.AddPair('capabilities', Capabilities);

    ServerInfo := TJSONObject.Create;
    ServerInfo.AddPair('name', 'media-mcp-server');
    ServerInfo.AddPair('version', '1.0.0');
    ResultObj.AddPair('serverInfo', ServerInfo);

    Response.AddPair('result', ResultObj);
    Result := Response.ToJSON;
  finally
    Response.Free;
  end;
end;

function TMCPHandler.BuildPingResponse(const Id: TJSONValue): string;
var
  Response, ResultObj: TJSONObject;
begin
  Response := TJSONObject.Create;
  try
    Response.AddPair('jsonrpc', '2.0');
    if Id <> nil then
      Response.AddPair('id', Id.Clone as TJSONValue)
    else
      Response.AddPair('id', TJSONNull.Create);
    ResultObj := TJSONObject.Create;
    Response.AddPair('result', ResultObj);
    Result := Response.ToJSON;
  finally
    Response.Free;
  end;
end;

function TMCPHandler.BuildEmptyListResponse(const Id: TJSONValue; const ListKey: string): string;
var
  Response, ResultObj: TJSONObject;
begin
  Response := TJSONObject.Create;
  try
    Response.AddPair('jsonrpc', '2.0');
    if Id <> nil then
      Response.AddPair('id', Id.Clone as TJSONValue)
    else
      Response.AddPair('id', TJSONNull.Create);
    ResultObj := TJSONObject.Create;
    ResultObj.AddPair(ListKey, TJSONArray.Create);
    Response.AddPair('result', ResultObj);
    Result := Response.ToJSON;
  finally
    Response.Free;
  end;
end;

function TMCPHandler.BuildToolsListResponse(const Id: TJSONValue): string;
var
  Response, ResultObj: TJSONObject;
  ToolsList: TJSONArray;
begin
  Response := TJSONObject.Create;
  try
    Response.AddPair('jsonrpc', '2.0');
    if Id <> nil then
      Response.AddPair('id', Id.Clone as TJSONValue)
    else
      Response.AddPair('id', TJSONNull.Create);
    ResultObj := TJSONObject.Create;
    ToolsList := TMediaEngine.GetToolsSchema;
    ResultObj.AddPair('tools', ToolsList);
    Response.AddPair('result', ResultObj);
    Result := Response.ToJSON;
  finally
    Response.Free;
  end;
end;

function TMCPHandler.BuildToolsCallResponse(const Id: TJSONValue; Params: TJSONObject): string;
var
  Response, McpResult, ContentItem, ToolResult: TJSONObject;
  ContentArray: TJSONArray;
  ToolName: string;
  ToolArgs: TJSONObject;
  ToolArgsVal: TJSONValue;
  ErrorMsg: string;
begin
  if (Params = nil) or not Params.TryGetValue('name', ToolName) then
    Exit(BuildErrorResponse(Id, -32602, 'Invalid params: name is required'));

  ToolArgs := nil;
  if Params.TryGetValue('arguments', ToolArgsVal) and (ToolArgsVal is TJSONObject) then
    ToolArgs := ToolArgsVal as TJSONObject;

  Response := TJSONObject.Create;
  try
    Response.AddPair('jsonrpc', '2.0');
    if Id <> nil then
      Response.AddPair('id', Id.Clone as TJSONValue)
    else
      Response.AddPair('id', TJSONNull.Create);

    try
      ToolResult := TMediaEngine.CallTool(ToolName, ToolArgs);
      try
        McpResult := TJSONObject.Create;
        ContentArray := TJSONArray.Create;
        ContentItem := TJSONObject.Create;
        ContentItem.AddPair('type', 'text');
        ContentItem.AddPair('text', ToolResult.ToJSON);
        ContentArray.Add(ContentItem);
        McpResult.AddPair('content', ContentArray);
        if ToolResult.TryGetValue('error', ErrorMsg) then
          McpResult.AddPair('isError', TJSONBool.Create(True));
        Response.AddPair('result', McpResult);
        Result := Response.ToJSON;
      finally
        ToolResult.Free;
      end;
    except
      on E: Exception do
      begin
        Log('ERROR executing tool ' + ToolName + ': ' + E.Message);
        McpResult := TJSONObject.Create;
        ContentArray := TJSONArray.Create;
        ContentItem := TJSONObject.Create;
        ContentItem.AddPair('type', 'text');
        ContentItem.AddPair('text', Format('{"error":"%s"}',
          [StringReplace(E.Message, '"', '\"', [rfReplaceAll])]));
        ContentArray.Add(ContentItem);
        McpResult.AddPair('content', ContentArray);
        McpResult.AddPair('isError', TJSONBool.Create(True));
        Response.AddPair('result', McpResult);
        Result := Response.ToJSON;
      end;
    end;
  finally
    Response.Free;
  end;
end;

function TMCPHandler.ProcessMessage(const JsonText: string): string;
var
  JsonRequest: TJSONObject;
  JsonValue: TJSONValue;
  JsonRpc, Method: string;
  Id, ParamsValue: TJSONValue;
  Params: TJSONObject;
begin
  Result := '';
  if Trim(JsonText) = '' then
    Exit;

  JsonValue := TJSONObject.ParseJSONValue(JsonText);
  if not (JsonValue is TJSONObject) then
  begin
    if Assigned(JsonValue) then
      JsonValue.Free;
    Exit(BuildErrorResponse(nil, -32700, 'Parse error: Invalid JSON'));
  end;

  JsonRequest := JsonValue as TJSONObject;
  try
    if not JsonRequest.TryGetValue('jsonrpc', JsonRpc) or (JsonRpc <> '2.0') then
      Exit(BuildErrorResponse(nil, -32600, 'Invalid Request: missing or invalid jsonrpc version'));

    if not JsonRequest.TryGetValue('method', Method) then
      Exit(BuildErrorResponse(nil, -32600, 'Invalid Request: missing method'));

    Id := nil;
    JsonRequest.TryGetValue('id', Id);

    Params := nil;
    if JsonRequest.TryGetValue('params', ParamsValue) and (ParamsValue is TJSONObject) then
      Params := ParamsValue as TJSONObject;

    if Method = 'initialize' then
      Exit(BuildInitializeResponse(Id, Params))
    else if (Method = 'notifications/initialized') or (Method = 'notifications/cancelled') then
      Exit('')
    else if Method = 'ping' then
      Exit(BuildPingResponse(Id))
    else if Method = 'resources/list' then
      Exit(BuildEmptyListResponse(Id, 'resources'))
    else if Method = 'resources/templates/list' then
      Exit(BuildEmptyListResponse(Id, 'resourceTemplates'))
    else if Method = 'prompts/list' then
      Exit(BuildEmptyListResponse(Id, 'prompts'))
    else if Method = 'tools/list' then
      Exit(BuildToolsListResponse(Id))
    else if Method = 'tools/call' then
      Exit(BuildToolsCallResponse(Id, Params))
    else if Id <> nil then
      Exit(BuildErrorResponse(Id, -32601, 'Method not found: ' + Method));
  finally
    JsonRequest.Free;
  end;
end;

end.
