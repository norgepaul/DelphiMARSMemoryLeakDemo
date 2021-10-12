unit MemLeak.Server.Resource;

interface

uses
  System.SysUtils, System.Generics.Collections, System.Hash, System.DateUtils,
  System.IOUtils, System.Variants, System.Classes,

  Web.HTTPApp,

  MARS.Core.Attributes, MARS.Core.Registry, MARS.Core.JSON, MARS.Core.MediaType,

  MemLeak.Utils;

type
  (*
    The leak behaviour only occurs on Linux. Windows works as expected.

    See comments below for issues with Delphi versions.
  *)

  [Path('test')]
  [Produces(TMediaType.APPLICATION_JSON)]
  TMemLeakResource = class
  public
    (* --------------------------------------------- *)
    (* Functions with memory leak in Delphi 11.0.0   *)
    (* --------------------------------------------- *)

    (* http://127.0.0.1:4000/rest/test/string2 *)
    [GET, Path('/string2'), Produces(TMediaType.APPLICATION_JSON)]
    function TestString2: TJSONRawString;


    (* --------------------------------------------- *)
    (* Functions with memory leak in Delphi 10.4.3   *)
    (* --------------------------------------------- *)

    (* http://127.0.0.1:4000/rest/test/stringlist *)
    [GET, Path('/stringlist'), Produces(TMediaType.APPLICATION_JSON)]
    function TestStringList(
      [QueryParam('size')] const MaxSize: Integer;
      [QueryParam('singleline')] const SingleLine: Boolean):TJSONRawString;

    (* http://127.0.0.1:4000/rest/test/stringlistobject *)
    [GET, Path('/stringlistobject'), Produces(TMediaType.APPLICATION_JSON)]
    function TestStringListObject: TJSONRawString;


    (* --------------------------------------------- *)
    (* Functions without memory leak                 *)
    (* --------------------------------------------- *)

    (* http://127.0.0.1:4000/rest/test/getmem *)
    [GET, Path('/getmem'), Produces(TMediaType.APPLICATION_JSON)]
    function TestGetMemory: TJSONRawString;

    (* http://127.0.0.1:4000/rest/test/array *)
    [GET, Path('/array'), Produces(TMediaType.APPLICATION_JSON)]
    function TestArray: TJSONRawString;

    (* http://127.0.0.1:4000/rest/test/string *)
    [GET, Path('/string'), Produces(TMediaType.APPLICATION_JSON)]
    function TestString: TJSONRawString;

    (* http://127.0.0.1:4000/rest/test/object *)
    [GET, Path('/object'), Produces(TMediaType.APPLICATION_JSON)]
    function TestObject: TJSONRawString;
  end;

  TBigObj = class(TObject)
    S: String;
  end;

  TStringListObj = class(TObject)
  public
    procedure Go;
  end;

implementation

const
  COUNT = 100000000;

{ TMemLeakResource }

function TMemLeakResource.TestString: TJSONRawString;
var
  S: String;
begin
  S := StringOfChar('X', COUNT);

  sleep(2000);

  Result := '{}';
end;

function TMemLeakResource.TestStringList(
  const MaxSize: Integer; const SingleLine: Boolean): TJSONRawString;
var
  S: TStringList;
  Size: Integer;
begin
  if MaxSize = 0 then
  begin
    Size := 1000000;
  end
  else
  begin
    Size := MaxSize;
  end;

  S := TMemLeakUtils.CreateStringList(Size, SingleLine);
  try
    sleep(2000);

    Result := format('{"length": %d}', [Length(S.Text)]);
  finally
    S.Free; // <-- This doesn't free the memory allocated by TStringList
  end;
end;

function TMemLeakResource.TestStringListObject: TJSONRawString;
var
  O: TStringListObj;
begin
  O := TStringListObj.Create;
  try
    O.Go;
  finally
    O.Free;
  end;

  Result := '{}';
end;

function TMemLeakResource.TestString2: TJSONRawString;
var
  i: Integer;
  X: String;
begin
  // First pass only leaks approx 0.2MB
  // Subsequent passes leak approx 12MB

  Result := '{}';
  X := '';

  for i := 1 to 10000 do
  begin
    X := X + '{"id":15000,"topic":"snsr","payload":"XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX","generated_at":"2021-10-12T10:05:23.663",' +
              '"published_at":"2021-10-12T10:05:23.663","created_at":"2021-10-12T10:05:23.663","protocol_version":0,"direction":0}';
  end;

  // Removing this statement reduces the leak to approx 6MB
  //Result := X;
end;

function TMemLeakResource.TestArray: TJSONRawString;
var
  A: TArray<Byte>;
  i: Integer;
begin
  SetLength(A, COUNT);

  for i := Low(A) to High(A) do
  begin
    A[i] := $AA;
  end;

  sleep(2000);

  Result := '{}';
end;

function TMemLeakResource.TestGetMemory: TJSONRawString;
type
  TBigRec = record
    S: String;
  end;
  PBigRec = ^TBigRec;
var
  P: PBigRec;
begin
  P := new(PBigRec);
  P.S := StringOfChar('X', COUNT);

  sleep(2000);

  Dispose(P);

  Result := '{}';
end;

function TMemLeakResource.TestObject: TJSONRawString;
var
  O: TBigObj;
  i: Integer;
begin
  O := TBigObj.Create;
  try
    for i := 1 to Count do
    begin
      O.S := O.S + 'X';
    end;

    sleep(2000);
  finally
    O.Free;
  end;
end;

{ TStringListObj }

procedure TStringListObj.Go;
var
  S: TStringList;
begin
  S := TMemLeakUtils.CreateStringList;
  try
    sleep(2000);
  finally
    S.Free; // <-- This doesn't free the memory allocated by TStringList
  end;
end;

initialization
  TMARSResourceRegistry.Instance.RegisterResource<TMemLeakResource>;

end.
